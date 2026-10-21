# APIM Standard v2 AI gateway + private Microsoft Foundry

This root owns the shared foundation and the optional **Standard v2** gateway.
The alternative [AI Gateway pricing-tier root](../apim-ai-gateway/README.md)
reuses its foundation without sharing writable state or duplicating resources.
Use the [tier-switching procedure](../apim-ai-gateway/README.md#switching-tiers)
to select one active gateway. Never destroy this root merely to change tiers.

With `standard_gateway_enabled = true` (the default), this root deploys:

- one resource group
- one API Management instance in the `StandardV2` pricing tier, capacity 1
- one Microsoft Foundry `AIServices` account with exactly three model deployments
- account-scoped Foundry User access for the gateway's managed identity
- three Foundry-linked managed-identity backends, three key-protected model APIs,
  three additional Entra-protected model entrypoints, three API-scoped
  subscriptions, their AI Models classification, and three published
  model-specific products
- one single-tenant Entra API registration/service principal with three
  explicitly assigned model roles; no application passwords or certificates
- one shared VNet, four dedicated subnets, supporting NSGs, private endpoints
  for Foundry and APIM, and the required private DNS zones

It does not deploy App Service, App Service plans, per-user model deployments,
LiteLLM, MLflow, databases, Redis, storage accounts, monitoring, agents, or projects.
Other legacy Terraform roots are not used. Disabling `standard_gateway_enabled`
removes only the Standard gateway, its children, its private endpoint, its
Foundry role assignment, and the RBAC timer. Foundry, all three deployments,
the four-subnet network/DNS foundation, and Entra objects remain managed here.
Gateway endpoints/keys are no longer advertised while it is disabled.

The separate AI Gateway root uses the same outbound subnet only after the
Standard gateway has been removed. All four retained subnet prefixes remain
/24; no temporary migration subnet is needed. The Standard-specific API,
product, key, and Entra instructions below apply only while Standard is enabled.

Both roots have independent local state and persistent ignored
`gateway.auto.tfvars.json` settings. Do not copy state or enable both gateways.
An optional `gateway_name` supports an approved new name when soft-delete
reserves a previous one, without changing the retained Entra audience/roles.
The [Standard portal runbook](../../manualsteps-apimv2-standard.md) is the
manual fallback; [the other runbook](../../manualsteps-apimv2-foundry.md)
describes the AI Gateway pricing tier and its different runtime-key semantics.

## Target and models

| Setting | Value |
| --- | --- |
| Entra tenant | `16b3c013-d300-468d-ac64-7eda0820b6d3` |
| Subscription | `fb7dfa70-78b9-4e56-8d2d-fa2eff765241` |
| Resource group | `rg-foundry-aigateway-sweden` |
| Region | Sweden Central |

| Foundry deployment | Catalog model | Version | Global Standard capacity |
| --- | --- | --- | --- |
| `Gpt5.4mini` | `gpt-5.4-mini` | `2026-03-17` | 1 |
| `Phi` | `Phi-4` | `7` | 1 |
| `FW-DeepSeek-V4.1-Flash` | `DeepSeek-V4-Flash` | `2026-04-23` | 250 |

The DeepSeek deployment name is an alias for the catalog model shown above, not
a separate model version. All three deployments disable automatic version
upgrades. Quota and regional availability must be checked before applying.

Foundry local authentication and public network access are disabled. The gateway
uses its system-assigned managed identity to invoke Foundry privately; clients
reach public APIM over HTTPS with an API-scoped subscription key. APIM client
keys are not Foundry API keys and do not enable Foundry local authentication.

The Foundry option **Allow Azure services on the trusted services list to access
this cognitive services account** is enabled through
`networkAcls.bypass = "AzureServices"`. Public network access stays disabled and
the default network action stays `Deny`; this trusted-services exception does not
grant permissions or replace managed-identity authentication and RBAC.

## Shared VNet and traffic flow

`internet client -> public Standard v2 APIM -> shared VNet -> Foundry private endpoint`

The shared VNet is `10.42.0.0/16` in Sweden Central:

| Subnet | Address range | Purpose / delegation |
| --- | --- | --- |
| `snet-foundry-inbound` | `10.42.0.0/24` | Foundry private endpoint |
| `snet-foundry-outbound` | `10.42.1.0/24` | Foundry outbound injection; `Microsoft.App/environments` |
| `snet-aigw-outbound` | `10.42.2.0/24` | Standard v2 outbound integration; `Microsoft.Web/serverFarms` |
| `snet-aigw-inbound` | `10.42.3.0/24` | APIM inbound private endpoint |

Public network access on APIM remains enabled for internet clients. The
separate inbound subnet provides an additional private endpoint for VNet clients;
public requests still enter through the gateway's managed public frontend, not
through this subnet. The gateway's outbound NSG permits HTTPS to Foundry
and the required Storage and Azure Key Vault platform dependencies; those service
tags do not create storage accounts or vaults.

The Foundry private-endpoint subnet permits HTTPS from the gateway and Foundry
outbound subnets and denies other inbound traffic. Private DNS zones
`privatelink.services.ai.azure.com`, `privatelink.openai.azure.com`, and
`privatelink.cognitiveservices.azure.com` resolve the Foundry hostnames privately.
Keep using the normal Foundry hostname, not a private-link hostname or IP address.
The gateway's `privatelink.azure-api.net` zone is also linked to the shared VNet.

Foundry outbound injection is configured when the account is created. It applies
to supported agent/evaluation workloads, not to the placement of the model
hosting infrastructure. No such workloads are deployed here. Injection routes
supported outbound traffic into the VNet but is not an internet-egress firewall;
no firewall, NAT gateway, or unrestricted-outbound-isolation claim is included.

## AI Models and model-scoped subscriptions

The **AI Gateway > AI Models** and **APIs** pages are views of the same APIs in
the Standard v2 instance. Terraform manages the reserved `aimodel` tag and
associates it with the three existing key APIs and the three additional
Entra-protected entrypoints. The AI-specific view is not another
gateway, model deployment, or authentication boundary.

| Deployment | Public API path | Subscription ID |
| --- | --- | --- |
| `Gpt5.4mini` | `/gpt5-4mini/openai/v1/chat/completions` | `gpt5-4mini` |
| `Phi` | `/phi/openai/v1/chat/completions` | `phi` |
| `FW-DeepSeek-V4.1-Flash` | `/fw-deepseek-v4-1-flash/openai/v1/chat/completions` | `fw-deepseek-v4-1-flash` |

Each subscription grants access only to its own API. Send its primary or
secondary key in `Ocp-Apim-Subscription-Key`. Missing keys and another model's
key receive HTTP 401. Subscription scopes and tag associations use the current
API ID without AzureRM's `;rev=1` suffix.

Requests must contain the exact deployment name in `model` and a `messages`
array. JSON validation rejects malformed or mismatched requests and limits
request bodies to 4 MiB. Policies additionally pin the deployment, strip
client-supplied backend credentials and model-routing headers, drop query
overrides, and authenticate the fixed backend using managed identity.
Streaming responses are supported. No monthly budget, semantic cache,
content-safety service, or application-specific cost policy is installed.

### Additive Entra ID access

The original URLs and subscription keys are unchanged. Each model also has a
separate bearer-token entrypoint on the same gateway:

| Deployment | Token-only API path | Required Entra app role |
| --- | --- | --- |
| `Gpt5.4mini` | `/entra/gpt5-4mini/openai/v1/chat/completions` | `Model.Gpt.Invoke` |
| `Phi` | `/entra/phi/openai/v1/chat/completions` | `Model.Phi.Invoke` |
| `FW-DeepSeek-V4.1-Flash` | `/entra/fw-deepseek-v4-1-flash/openai/v1/chat/completions` | `Model.DeepSeek.Invoke` |

In **AI Models**, these additional entries have the suffix **(Entra ID)**.
They reuse the same three Foundry deployments/backends; they are not new models.
They are not added to the subscription products. The key APIs still require
keys; the Entra APIs always require a valid gateway access token and the
matching model role. Supplying a key to an Entra API does not bypass that role.

`entra_auth.tf` manages the resource API registration, its enterprise application,
and role assignments. Enterprise-app assignment is required. The default
`entra_model_principal_ids = {}` grants no users or workloads access. Keep
explicit deployment assignments in the ignored `entra.auto.tfvars`, for example:

```hcl
entra_model_principal_ids = {
  gpt5_4_mini = ["USER_OR_SERVICE_PRINCIPAL_OBJECT_UUID"]
  phi         = ["ANOTHER_PRINCIPAL_OBJECT_UUID"]
}
```

Use Entra **object IDs**, not application/client IDs. Assign only required roles.
Groups require suitable Entra licensing. Administrators need app-registration
permissions and permission to manage the resource service principal's assignments;
subscription Owner alone does not grant Entra directory permissions. Keep the
deployment identity as an owner when handing Terraform operation to automation.

The resource API requests v2 access tokens. The expected `aud` is its **client
ID** from `apim_entra_authentication`, not the APIM URL or Foundry audience.
The token must be issued by the configured tenant, pass signature/expiry
validation, and contain the corresponding `roles` value. A missing/invalid token
returns **401**; a valid token without the model role returns **403**.
The `access_as_user` delegated scope alone grants no model access.

Only the Microsoft Azure CLI public client is preauthorized for that delegated
scope, enabling assigned administrators to use their existing CLI session.
An application calling unattended needs its own existing service principal or
managed identity and a model-role assignment. Request
`<resource_uri>/.default` using managed identity, workload federation, or a
certificate; do not create a gateway API client secret. Delegated clients need
approved scope consent/preauthorization and model-role assignment for the user.

Example using an already signed-in, assigned administrator:

```powershell
$auth = terraform output -json apim_entra_authentication | ConvertFrom-Json
$endpoints = terraform output -json apim_entra_model_endpoints | ConvertFrom-Json -AsHashtable
$token = az account get-access-token --tenant $auth.tenant_id `
    --scope "$($auth.resource_uri)/.default" --query accessToken --output tsv --only-show-errors
if ($LASTEXITCODE -ne 0) { throw "Gateway access-token acquisition failed." }
$headers = @{ Authorization = "Bearer $token" }
$body = @{
    model = "Phi"
    messages = @(@{ role = "user"; content = "Reply READY." })
    max_tokens = 64
} | ConvertTo-Json -Depth 6
Invoke-RestMethod -Method Post -Uri $endpoints["Phi"] `
    -Headers $headers -ContentType "application/json" -Body $body
Remove-Variable token,headers
```

Tokens remain in memory. Acquire a fresh token after role changes; already issued
tokens retain their claims until expiry, and CLI/MSAL can return a cached token.
If claims are stale, reauthenticate through the approved client rather than
weakening the API's role check. Test tokens must not be printed or saved
in source, transcripts, screenshots, or evidence files.

Caller Entra authentication is independent of APIM's backend managed identity.
The validated caller bearer token is removed; APIM obtains its own Foundry token
for `https://cognitiveservices.azure.com/`. Shared policy templates preserve
request validation, model pinning, stripped routing overrides, portal CORS and
streaming on both authentication paths. A token-only API has no default
upstream, so it cannot call Foundry before its authorization policy is attached.

Both public and private gateway ingress can reach the corresponding endpoints.
Private DNS/routing is still necessary for private clients; Entra authentication
does not make an endpoint private. The existing AI Models key-based browser chat
is unchanged; bearer tests can use HTTP requests with an `Authorization` header.
An automatic browser OAuth sign-in UI is not provisioned.

The API-level `set-backend-service` reference retains the
`id="apim-generated-policy"` identifier and its literal, model-specific
`backend-id`. This policy binding and the referenced backend are the routing
configuration; a blank Backend label in the AI Models overview is not evidence
that the gateway has no backend. GPT uses the
Foundry `/openai/v1` backend; Phi and DeepSeek use `/models`. These backend URLs
are different from the public APIM base URLs above. All three backends retain
the Foundry resource association and system-assigned managed-identity audience
`https://cognitiveservices.azure.com/`.

### Azure Portal chat testing

Each API evaluates CORS before inherited inbound policies so the portal's
unauthenticated `OPTIONS` preflight does not reach request validation or Foundry.
The explicit application-origin allowlist contains `https://ms.portal.azure.com`
and `https://portal.azure.com`. The actual AI Models console runs in a sandbox
iframe, observed at `https://sandbox-3.reactblade-ms.portal.azure.net`. A policy
expression additionally allows only HTTPS origins whose entire host matches
`sandbox-<digits>.reactblade-ms.portal.azure.net` or
`sandbox-<digits>.reactblade.portal.azure.net`, with no nondefault port or extra
domain suffix. This accommodates portal sandbox selection without allowing
arbitrary origins. SDK request headers are supported, but browser credential
sharing is disabled. Actual requests still require an APIM subscription key;
Foundry continues to use managed identity and private access. Both the configured
subscription-key header and query parameter are supported; the current console
uses the query parameter.

The test console sends `/deployments/{deployment}/chat/completions` relative to
the API base URL. Each API therefore also exposes an exact, deployment-qualified
compatibility operation for its own model. It uses the same validation,
subscription boundary, pinned backend, and managed identity as the canonical
`/chat/completions` operation. No wildcard deployment route or duplicate API is
created.

Other application origins are not enabled by this policy. A successful
preflight from the outer portal address does not verify the sandbox iframe's
origin or prove that an interactive chat completed. Add an exact
trusted origin deliberately if a separate browser application needs access;
do not use a wildcard origin.
Non-browser clients are unaffected. CORS is not an authorization mechanism.
Keep the API-level CORS block when editing backend policies in the portal;
removing it can break browser chat without breaking non-browser inference.

### Foundry rate limits and HTTP 429

The current capacity-1 GPT mini and Phi deployments each advertise **one request
per 60 seconds and 1,000 tokens per 60 seconds**. Back-to-back chat turns can
therefore receive HTTP 429 even when the backend URL, subscription key, and
managed identity are correct. Honor the retry interval or deliberately raise
the deployment capacity after checking available quota. APIM products,
subscriptions, and test-console sessions share the corresponding Foundry
deployment's limits; separate keys do not create additional throughput.

### Model-specific products

Each published product contains exactly one model API:

| Product ID | Product / deployment | Included API |
| --- | --- | --- |
| `gpt5-4mini` | `Gpt5.4mini` | `gpt5-4mini` |
| `phi` | `Phi` | `phi` |
| `fw-deepseek-v4-1-flash` | `FW-DeepSeek-V4.1-Flash` | `fw-deepseek-v4-1-flash` |

The built-in `developers` group can discover the published products after
sign-in. Anonymous/guest visibility is not granted. Products require
subscriptions, and new product subscription requests require administrator
approval. Each developer may have one subscription per product; AzureRM requires
a positive per-user limit when approval is enabled. This is not a total-user,
request, or token limit. No product-specific rate policy is added.

The existing three subscriptions remain API-scoped with their current keys;
creating products does not move or rotate them. Product subscription lists
initially remain empty. An administrator can separately issue a product-scoped
subscription when needed; its key grants access only to that product's sole API.

## Deploy

Use only this directory and a newly reviewed full plan, not the parent Terraform
root or historical saved plans:

```powershell
az login --tenant 16b3c013-d300-468d-ac64-7eda0820b6d3
az account set --subscription fb7dfa70-78b9-4e56-8d2d-fa2eff765241
Set-Location .\terraform\apim-only
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
terraform plan -out=tfplan
terraform apply tfplan
```

The `Microsoft.ApiManagement`, `Microsoft.CognitiveServices`, `Microsoft.Network`,
`Microsoft.App`, and `Microsoft.Web` resource providers must already be registered.
Automatic provider registration is disabled to avoid registering unrelated
services.

Review the plan before applying: it must contain only the resources listed above
and local Terraform random/timing helpers. If an earlier deployment still has an
application, extra models, or application-specific keys, do not apply a plan
that removes them without separate approval. Never reapply historical
creation, deletion, or migration plan files.

## Endpoints and client access

- `terraform output -raw apim_gateway_url` returns the public APIM gateway.
- `terraform output -json apim_model_base_urls` returns the model-specific base URLs.
- `terraform output -json apim_model_endpoints` returns complete key-based chat endpoints.
- `terraform output -json apim_entra_model_endpoints` returns the token-only endpoints.
- `terraform output -json apim_entra_authentication` returns nonsecret Entra API/scope/role identifiers.
- `terraform output -json apim_model_product_ids` returns the three product ARM IDs.
- In Azure portal, use **apim-foundry-8ps1sz > AI Gateway > AI Models**.
- `terraform output model_deployments` lists the three Foundry deployments.
- `terraform output subnet_ids` lists the four dedicated shared-VNet subnets.

Example DeepSeek request in PowerShell 7; keep keys in memory rather than source:

```powershell
$keys = terraform output -json apim_subscription_keys | ConvertFrom-Json -AsHashtable
$endpoints = terraform output -json apim_model_endpoints | ConvertFrom-Json -AsHashtable
$headers = @{ "Ocp-Apim-Subscription-Key" = $keys["FW-DeepSeek-V4.1-Flash"] }
$body = @{
    model = "FW-DeepSeek-V4.1-Flash"
    messages = @(@{ role = "user"; content = "Reply READY." })
    max_tokens = 256
} | ConvertTo-Json -Depth 6
Invoke-RestMethod -Method Post -Uri $endpoints["FW-DeepSeek-V4.1-Flash"] `
    -Headers $headers -ContentType "application/json" -Body $body
Remove-Variable keys,headers
```

Terraform state and saved plans can contain secrets even when outputs are marked
sensitive. Keep them protected and out of version control.

## Verification

`terraform test` checks that the configured deployments contain exactly one each
of `gpt-5.4-mini`, `Phi-4`, and `DeepSeek-V4-Flash`, with the expected deployment
names, Standard v2 configuration, AI Models tag associations, revision-free API
scopes, portal backend-policy references, backend URLs/resource associations,
managed-identity policies, and public-gateway/private-Foundry settings.

Run the live integration test from this Terraform directory:

```powershell
.\tests\Test-StandardApim.ps1
.\tests\Test-EntraApim.ps1
```

The Entra test acquires a gateway access token for the assigned operator and
checks the live API policies, audience/signature rejection, per-model roles,
key-only rejection on token APIs, unchanged key requirements on original APIs,
request/routing protection, and complete token-only chat/SSE streams. It can
also accept an in-memory `-AccessToken` with `-ExpectedRoles` to verify that a
real, correctly signed token for one model receives 403 on the other two.

It verifies each published product's sole API, subscription/approval settings,
and signed-in developer visibility, each backend's URL, Foundry association,
system-assigned identity, TLS validation, and portal policy reference, followed
by both canonical and
portal-compatibility preflights from the outer portal and both sandbox host
families, readable portal
responses, rejection of another deployment's compatibility route, rejection of an
untrusted browser origin and sandbox lookalikes, real responses from all three expected models, every
cross-model subscription rejection, missing-key rejection, malformed JSON and
model override rejection, routing-header/query protection, and browser-readable
SSE streaming with the actual sandbox origin, query-key authentication, and the
portal's default request parameters for all three models.
It reads subscription keys and an ARM token into memory and does not print
them. These HTTP checks do not replace an authenticated interactive browser
retest. The low-capacity models can require rate-limit retries during the test.
