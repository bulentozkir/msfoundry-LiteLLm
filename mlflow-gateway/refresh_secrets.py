"""Keeps the MLflow AI Gateway's Azure OpenAI credential fresh.

MLflow's gateway stores provider credentials as a static encrypted secret
(no token-provider callback like LiteLLM's `enable_azure_ad_token_refresh`),
so this sidecar periodically mints a real Azure AD access token via the
Container App's user-assigned managed identity and PATCHes it into the
gateway secret over MLflow's own REST API. Because `openai_api_type` is set
to "azuread", MLflow sends this value as `Authorization: Bearer <value>`
(confirmed in mlflow/gateway/providers/openai.py), which is exactly the
header shape an AAD access token requires - no API key is ever used, which
matches this tenant's disableLocalAuth policy.

Must use provider="openai" (not "azure"): mlflow/server/gateway_api.py's
get_provider_config() hardcodes openai_api_type=AZURE (api-key auth) for
provider="azure" unconditionally, ignoring auth_config entirely. Only the
provider="openai" branch reads auth_config["api_type"] and honors "azuread"
(Bearer-token) auth - but that branch also sources the deployment name from
auth_config["deployment_name"] rather than the model definition's model_name,
so each deployment needs its own secret even though the token value is the
same for all of them.

Bootstraps the secret/model-definitions/endpoint/budget on first run if
they don't exist yet, then just refreshes the secret value on a loop.
"""

import os
import sys
import time

import requests
from azure.identity import ManagedIdentityCredential

MLFLOW_BASE_URL = os.environ["MLFLOW_BASE_URL"].rstrip("/")
AZURE_CLIENT_ID = os.environ["AZURE_CLIENT_ID"]
AZURE_OPENAI_ENDPOINT = os.environ["AZURE_OPENAI_ENDPOINT"]
AZURE_OPENAI_API_VERSION = os.environ["AZURE_OPENAI_API_VERSION"]
# The gateway's own admin REST API is behind mlflow's basic-auth plugin (see
# mlflow-gateway-app.tf); this sidecar needs the same credentials to keep
# managing secrets/model-definitions/endpoints.
MLFLOW_ADMIN_USERNAME = os.environ["MLFLOW_ADMIN_USERNAME"]
MLFLOW_ADMIN_PASSWORD = os.environ["MLFLOW_ADMIN_PASSWORD"]
# JSON-ish "deployment_name:model_definition_name:endpoint_name" triples,
# semicolon-separated, e.g. "gpt-5.4-mini:mini-def:gpt-5-4-mini;Phi-4:phi-def:phi-4"
MODEL_MAP = os.environ["MLFLOW_MODEL_MAP"]
REFRESH_INTERVAL_SECONDS = int(os.environ.get("REFRESH_INTERVAL_SECONDS", "2400"))


def secret_name_for(definition_name: str) -> str:
    # One secret per deployment: auth_config.deployment_name (read by the
    # provider="openai"+azuread path) can't hold more than one value, so a
    # single shared secret can't serve two differently-named deployments.
    return f"azure-openai-aad-token-{definition_name}"


credential = ManagedIdentityCredential(client_id=AZURE_CLIENT_ID)


def get_token() -> str:
    return credential.get_token("https://cognitiveservices.azure.com/.default").token


def api(method: str, path: str, **kwargs) -> dict:
    response = requests.request(
        method,
        f"{MLFLOW_BASE_URL}{path}",
        auth=(MLFLOW_ADMIN_USERNAME, MLFLOW_ADMIN_PASSWORD),
        timeout=30,
        **kwargs,
    )
    response.raise_for_status()
    return response.json() if response.content else {}


def find_secret_id(secret_name: str) -> str | None:
    for secret in api("GET", "/api/3.0/mlflow/gateway/secrets/list").get("secrets", []):
        if secret["secret_name"] == secret_name:
            return secret["secret_id"]
    return None


def ensure_secret(token: str, definition_name: str, deployment_name: str) -> str:
    secret_name = secret_name_for(definition_name)
    secret_id = find_secret_id(secret_name)
    # secret_value/auth_config are proto map<string, string> fields, so they
    # serialize as flat JSON objects, not a list of {key, value} pairs.
    body = {
        "secret_value": {"api_key": token},
        "auth_config": {
            "api_type": "azuread",
            "api_base": AZURE_OPENAI_ENDPOINT,
            "api_version": AZURE_OPENAI_API_VERSION,
            "deployment_name": deployment_name,
        },
    }
    if secret_id:
        api("POST", "/api/3.0/mlflow/gateway/secrets/update", json={"secret_id": secret_id, **body})
        return secret_id
    created = api(
        "POST",
        "/api/3.0/mlflow/gateway/secrets/create",
        json={"secret_name": secret_name, "provider": "openai", **body},
    )
    return created["secret"]["secret_id"]


def find_model_definition_id(name: str) -> str | None:
    for model_def in api("GET", "/api/3.0/mlflow/gateway/model-definitions/list").get("model_definitions", []):
        if model_def["name"] == name:
            return model_def["model_definition_id"]
    return None


def ensure_model_definition(secret_id: str, definition_name: str, deployment_name: str) -> str:
    existing = find_model_definition_id(definition_name)
    if existing:
        # provider must be resent here too - otherwise a definition created by
        # an earlier buggy run keeps its stale provider="azure" forever, since
        # update() only patches the fields it's given.
        api(
            "POST",
            "/api/3.0/mlflow/gateway/model-definitions/update",
            json={
                "model_definition_id": existing,
                "secret_id": secret_id,
                "provider": "openai",
                "model_name": deployment_name,
            },
        )
        return existing
    created = api(
        "POST",
        "/api/3.0/mlflow/gateway/model-definitions/create",
        json={
            "name": definition_name,
            "secret_id": secret_id,
            "provider": "openai",
            "model_name": deployment_name,
        },
    )
    return created["model_definition"]["model_definition_id"]


def find_endpoint(name: str) -> dict | None:
    endpoints = api("GET", "/api/3.0/mlflow/gateway/endpoints/list").get("endpoints", [])
    for endpoint in endpoints:
        if endpoint["name"] == name:
            return endpoint
    return None


def ensure_endpoint(endpoint_name: str, model_definition_id: str) -> None:
    existing = find_endpoint(endpoint_name)
    if existing:
        # Re-assert usage_tracking on every refresh so it self-heals if an
        # endpoint was ever created (or reset) with it off - it's what makes
        # mlflow log per-request token usage/cost into a trace/experiment.
        if not existing.get("usage_tracking"):
            api(
                "POST",
                "/api/3.0/mlflow/gateway/endpoints/update",
                json={"endpoint_id": existing["endpoint_id"], "usage_tracking": True},
            )
        return
    api(
        "POST",
        "/api/3.0/mlflow/gateway/endpoints/create",
        json={
            "name": endpoint_name,
            "model_configs": [{"model_definition_id": model_definition_id, "linkage_type": "PRIMARY", "weight": 1.0}],
            "usage_tracking": True,
        },
    )


def parse_model_map() -> list[tuple[str, str, str]]:
    triples = []
    for entry in MODEL_MAP.split(";"):
        entry = entry.strip()
        if not entry:
            continue
        deployment_name, definition_name, endpoint_name = entry.split(":")
        triples.append((deployment_name, definition_name, endpoint_name))
    return triples


def main() -> None:
    models = parse_model_map()
    bootstrapped = False
    while True:
        try:
            token = get_token()
            for deployment_name, definition_name, endpoint_name in models:
                secret_id = ensure_secret(token, definition_name, deployment_name)
                model_definition_id = ensure_model_definition(secret_id, definition_name, deployment_name)
                ensure_endpoint(endpoint_name, model_definition_id)
            print(f"Refreshed Azure AD token for {len(models)} model definition(s).", flush=True)
            bootstrapped = True
        except Exception as exc:  # noqa: BLE001 - keep the sidecar alive across transient API/network errors
            print(f"Token refresh failed, will retry: {exc}", file=sys.stderr, flush=True)
            # On startup the mlflow container's own dependency install/DB
            # connect/gateway init takes 20-40s, so the very first attempt
            # here (fired immediately) routinely loses this race and would
            # otherwise wait a full REFRESH_INTERVAL_SECONDS (40 min) before
            # trying again, leaving the gateway with no secret/endpoints.
            if not bootstrapped:
                time.sleep(10)
                continue
        time.sleep(REFRESH_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
