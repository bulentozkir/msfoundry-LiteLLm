# Manual portal runbook: APIM AI Gateway tier and private Microsoft Foundry

This runbook describes administrator-led deployment without Terraform, Azure
CLI, or Cloud Shell. It uses **Azure Portal**, **Microsoft Foundry portal**, and
the **standalone AI Gateway portal**. AI Gateway preview cannot be configured
end to end through the Standard v2 APIM blades in Azure Portal.

Reviewed against Microsoft documentation and the repository configuration on
**20 October 2026**. Portal labels and preview behavior can change; this is not
a claim that every live portal screen was interactively tested on that date.

For Standard v2 instead, use the
[Standard v2 manual runbook](manualsteps-apimv2-standard.md).
For resources already managed by Terraform, use the
[Terraform switching procedure](terraform/apim-ai-gateway/README.md#switching-tiers)
instead of introducing untracked portal changes.

## Scope and important differences

The Azure pricing-tier/SKU name is **`AIGateway`**, displayed as **AI Gateway
tier (preview)**. It is a separate tier, not a `StandardV2` instance with its
AI Models blade enabled, and not a SKU named `AIGatewayV2`.

The target is:

- One AI Gateway instance, with public HTTPS enabled and an additional inbound
  private endpoint.
- The existing private Microsoft Foundry `AIServices` account.
- Exactly three existing deployments: `Gpt5.4mini`, `Phi`, and
  `FW-DeepSeek-V4.1-Flash`.
- The existing VNet and four separate inbound/outbound subnets.
- A system-assigned gateway identity with account-scoped **Foundry User**.
- One Foundry provider connection, three registered models and their
  caller-visible names, and a runtime access key.

Do not create another Foundry account or model deployment for a tier replacement.
Do not add App Service, LiteLLM, MLflow, a database, storage, monitoring, an
agent workload, or a second permanent gateway.

| Setting | Standard v2 | AI Gateway preview in this runbook |
|---|---|---|
| Runtime URL | Separate model-specific API paths | Shared `/default/models/openai/v1` base URL |
| Client credential | `Ocp-Apim-Subscription-Key` or a separately protected Entra API | Runtime key in `api-key` |
| Key authorization | Can be API/product scoped | Every key can call every published model/tool |
| Per-model Entra facade APIs | Configured by the Standard runbook | Not recreated by this procedure |
| Model management | APIM APIs/backends and AI Models view | Import models in the standalone AI Gateway portal |
| Policies | APIM XML policies | Supported governance cards in the AI Gateway portal |
| Service assurance | Standard v2 service terms | Public preview, no SLA |

**A key named after a model is still gateway-wide.** Do not describe separate
keys as per-model authorization. Entra sign-in for administrators and managed
identity for backend access do not provide Entra bearer-token authentication
for runtime callers.

The current Sweden Central retail meter lists AI Gateway requests at USD 0 per
10,000 requests during preview. Standard v2's first unit is USD 1.25/hour
(about USD 912.50 per 730-hour month). These are point-in-time retail prices,
not a guarantee of future or contracted charges. Foundry inference/capacity,
private endpoints, DNS, and other applicable charges remain.

## Deployment order

1. Confirm permissions, region, names, and the maintenance window.
2. Inspect or create the four subnets, NSGs, and DNS prerequisites.
3. Inspect the existing Foundry account, or create it only for a new deployment.
4. Verify Foundry private endpoints and the three model deployments.
5. For a replacement, delete only the old gateway and its gateway-specific resources.
6. Create the AI Gateway tier instance.
7. Enable its identity and assign Foundry access.
8. Configure outbound VNet integration and inbound Private Link.
9. Import the existing Foundry models with managed identity.
10. Create and securely distribute a runtime key.
11. Verify model calls, authentication, DNS, and resource scope.

## 1. Administrator prerequisites

1. Sign in to [Azure Portal](https://portal.azure.com). Under
   **Settings > Directories + subscriptions**, select the approved tenant and
   subscription. For the existing test environment:

   | Setting | Reference value |
   |---|---|
   | Tenant | `16b3c013-d300-468d-ac64-7eda0820b6d3` |
   | Subscription | `fb7dfa70-78b9-4e56-8d2d-fa2eff765241` |
   | Resource group | `rg-foundry-aigateway-sweden` |
   | Region | Sweden Central |
   | Foundry account | `fdry-aigw-8ps1sz` |
   | Existing VNet | `vnet-foundry-aigw-8ps1sz` |
   | New gateway name | A globally available name, for example `aigw-test-8ps1sz` |

2. Confirm these permissions, activating PIM roles where required:
   - Resource creation/update/delete at the approved resource-group scope.
   - Network Contributor or equivalent on the VNet/subnets and private endpoints.
   - Private DNS Zone Contributor or equivalent on the authoritative DNS zones.
   - Role-assignment permissions, such as Owner, User Access Administrator,
     or Role Based Access Control Administrator, on the Foundry account.
   - Model deployment permissions and Foundry data-plane access if creating
     or directly testing model deployments.
3. Under **Subscriptions > Resource providers**, verify the required providers:
   `Microsoft.ApiManagement`, `Microsoft.CognitiveServices`, `Microsoft.Network`,
   `Microsoft.Web` for the gateway subnet delegation, and `Microsoft.App` if
   configuring Foundry agent network injection. Do not register unrelated providers.
4. Confirm AI Gateway preview is available to this subscription in Sweden
   Central. Microsoft's documented preview regions are Sweden Central and
   East US 2; enrollment/capacity can still affect availability.
5. Obtain approval for changed URLs/keys, gateway-wide authorization, preview
   service terms, and an outage while replacing the gateway. This is not an
   in-place Standard v2 SKU change.

No gateway-facing app registration, client secret, or per-model app role is
required for AI Gateway runtime keys. Preserve existing Standard v2 Entra
objects if a later return to Standard v2 is planned.

## 2. Verify four subnets and NSGs

For a replacement, **reuse** these resources. For a new deployment, open
**Virtual networks > approved VNet > Subnets > + Subnet** and create only
missing, approved, nonoverlapping ranges.

| Subnet | Reference prefix | Purpose | Delegation |
|---|---|---|---|
| `snet-foundry-inbound` | `10.42.0.0/24` | Foundry private endpoint | None |
| `snet-foundry-outbound` | `10.42.1.0/24` | Supported Foundry agent/evaluation egress | `Microsoft.App/environments` |
| `snet-aigw-outbound` | `10.42.2.0/24` | Active gateway's outbound integration | `Microsoft.Web/serverFarms` |
| `snet-aigw-inbound` | `10.42.3.0/24` | Active gateway's inbound private endpoint | None |

The example VNet is `10.42.0.0/16`. Substitute approved ranges consistently
for another VNet; never resize, overlap, or replace occupied subnets.

The gateway VNet must be in the same region as the gateway. This runbook also
keeps it in the same subscription. The gateway integration subnet must be
dedicated to the **one active gateway**. It cannot be shared with another
gateway, App Service, or private endpoints. Microsoft requires at least `/27`
and recommends `/24`; the retained four-subnet layout already meets that requirement.

Use **Network security groups > NSG > Subnets > Associate** to inspect or
configure associations. Use source port `*` and TCP destination port `443`:

| NSG/subnet | Direction / priority | Rule |
|---|---|---|
| Foundry inbound | Inbound / 100 | Allow HTTPS from gateway outbound and Foundry outbound subnet prefixes. Add approved administrator/client ranges only if direct Foundry access is required. |
| Foundry inbound | Inbound / 4000 | Deny other inbound traffic after approved allow rules. |
| Gateway inbound | Inbound / 100 | Allow HTTPS from approved private client ranges; the reference uses `VirtualNetwork`, which can include peered networks. |
| Gateway inbound | Inbound / 4000 | Deny other inbound traffic after approved allow rules. |
| Gateway outbound | Outbound / 100 | Allow HTTPS to the `Storage` service tag. |
| Gateway outbound | Outbound / 110 | Allow HTTPS to the `AzureKeyVault` service tag. |
| Gateway outbound | Outbound / 120 | Allow HTTPS to the Foundry inbound subnet. |

On both private-endpoint subnets, enable the private endpoint network-policy
setting for **Network security groups**; an associated NSG alone is not enough
to enforce its rules on private endpoint traffic. Keep existing DNS access,
routes, and required platform dependencies working. Service tags do not
create Storage accounts or Key Vaults. Do not add a deny-all egress rule blindly.

Inbound NSG rules on the **outbound** subnet do not protect the public gateway.
Foundry's outbound subnet is not the network location of hosted model compute,
and network injection is not an internet-egress firewall.

## 3. Foundry account: inspect existing, create only if absent

### 3.1 Existing account

For the requested gateway replacement, keep the account and all deployments.
Open the Foundry resource in Azure Portal:

1. Under **Overview > JSON View**, verify `kind = AIServices`,
   `publicNetworkAccess = Disabled`, and `disableLocalAuth = true`.
2. Under **Networking**, verify default network access is denied. Retain the
   approved **Allow Azure services on the trusted services list** exception
   (`networkAcls.bypass = AzureServices`). It does not grant RBAC or anonymous access.
3. Verify the account's agent network injection references
   `snet-foundry-outbound` with `useMicrosoftManagedNetwork = false`.
   Do not try to change this creation-time setting during gateway replacement.
4. Under **Keys and Endpoint**, verify that API-key authentication is disabled.
   Do not enable local authentication or retrieve/distribute Foundry keys.

Network injection applies to supported agent/evaluation workloads. The
gateway reaches model inference through the account's **inbound private
endpoint**, not through the Foundry outbound subnet.

### 3.2 New deployment only: exact account creation through Azure Portal

Skip this subsection if the account exists. To create only the account with
disabled local authentication and creation-time network injection:

1. Search Azure Portal for **Deploy a custom template**.
2. Select **Build your own template in the editor**.
3. Paste the following template and select **Save**.
4. Select the approved subscription/resource group, a new globally unique
   Foundry name, and the same region as the prepared VNet.
5. Paste the full ARM ID of `snet-foundry-outbound` into the subnet parameter.
6. Review the resources and select **Review + create > Create**.

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "foundryName": { "type": "string" },
    "location": { "type": "string" },
    "foundryOutboundSubnetId": { "type": "string" }
  },
  "resources": [
    {
      "type": "Microsoft.CognitiveServices/accounts",
      "apiVersion": "2025-04-01-preview",
      "name": "[parameters('foundryName')]",
      "location": "[parameters('location')]",
      "kind": "AIServices",
      "sku": { "name": "S0" },
      "identity": { "type": "SystemAssigned" },
      "properties": {
        "allowProjectManagement": true,
        "customSubDomainName": "[parameters('foundryName')]",
        "disableLocalAuth": true,
        "publicNetworkAccess": "Disabled",
        "networkAcls": {
          "defaultAction": "Deny",
          "bypass": "AzureServices",
          "ipRules": [],
          "virtualNetworkRules": []
        },
        "networkInjections": [
          {
            "scenario": "agent",
            "subnetArmId": "[parameters('foundryOutboundSubnetId')]",
            "useMicrosoftManagedNetwork": false
          }
        ]
      }
    }
  ]
}
```

This template does not create projects, agents, storage, databases, or monitoring.
If the Foundry portal requires a management project for model deployment, use
an existing project or create one under the account's **Projects** page. Do
not enable Agent service dependency resources merely to use the model UI.
If organizational policy prohibits the trusted-services exception, obtain an
approved alternative rather than enabling public access or Foundry keys.

## 4. Verify Foundry Private Link and the existing models

### 4.1 Foundry private endpoint and DNS

1. Open **Foundry resource > Networking > Private endpoint connections**.
   Reuse the existing **Approved** connection.
2. Only if absent, select **+ Private endpoint**, target the Foundry
   **account** subresource, and select `snet-foundry-inbound`.
3. Enable private DNS integration and reuse the authoritative zones:
   - `privatelink.services.ai.azure.com`
   - `privatelink.openai.azure.com`
   - `privatelink.cognitiveservices.azure.com`
4. Under each zone's **Virtual network links**, verify the shared VNet is
   linked with automatic VM registration disabled.
5. Inspect **Private endpoint > DNS configuration** and match the generated
   records to its IP configurations. Different Foundry hostnames can use
   different private IPs.
6. For custom DNS, configure the existing resolver's forwarding. Peering does
   not automatically propagate private DNS links or resolver configuration.

Continue using normal HTTPS hostnames such as
`FOUNDRY_NAME.services.ai.azure.com`, not a private IP or `privatelink` hostname.
Direct Foundry portal/playground requests require the administrator's client
to have the necessary private routes, DNS, and NSG access. Signing in to Azure
Portal does not create that connectivity.

### 4.2 Exactly three model deployments

For a replacement, inspect rather than redeploy. Open **Go to Foundry portal**
or [Microsoft Foundry](https://ai.azure.com), select the account/project, then
**Models + endpoints** or the model-deployment page for the current experience.

| Deployment name | Catalog model | Pinned version | Deployment type | Reference capacity |
|---|---|---|---|---:|
| `Gpt5.4mini` | `gpt-5.4-mini` | `2026-03-17` | Global Standard | 1 |
| `Phi` | `Phi-4` | `7` | Global Standard | 1 |
| `FW-DeepSeek-V4.1-Flash` | `DeepSeek-V4-Flash` | `2026-04-23` | Global Standard | 250 |

All three must report **Succeeded**. Preserve names, versions, capacity, and
the no-automatic-upgrade setting. The DeepSeek deployment name is an alias
for the catalog model shown, not a fourth model.

For a genuinely new deployment, use **Deploy model > Deploy base model** or
the model catalog and create each deployment once. Check region, subscription
quota, model terms, and capacity units first. Do not silently substitute a
different version, region, managed-compute endpoint, or model.

The reference capacity-1 GPT mini and Phi deployments each advertise
1 request/minute and 1,000 tokens/minute. Gateway keys and tiers do not add
model throughput. Honor `Retry-After` when repeated tests receive HTTP 429.

## 5. Replacement only: remove the old gateway, not the foundation

Skip this section for a new deployment with an unused gateway subnet.
Schedule a maintenance window: the old URLs and keys stop working.

1. Record the old gateway's resource ID, managed-identity principal ID,
   inbound private endpoint, model API/client configuration, and Foundry role
   assignment. Keep credentials in approved secret storage, not screenshots
   or exported documentation.
2. Verify the Foundry account, models, shared VNet, DNS zones, NSGs, and all
   four subnets are outside the deletion scope. Preserve Standard v2's Entra
   registration and assignments for a future return.
3. In Azure Portal, delete only the old **gateway inbound private endpoint**.
   Keep its subnet and `privatelink.azure-api.net` zone/VNet link.
4. Open the old **API Management resource > Delete** and confirm that resource
   only. Its APIs, products, subscriptions, policies, and keys are gateway
   children; they are not portable AI Gateway runtime objects.
5. Remove only the old gateway principal's **Foundry User** role assignment
   on the Foundry account if it remains. Do not remove administrator access
   or assignments belonging to other gateways/workloads.
6. Wait until deletion completes and `snet-aigw-outbound` is no longer
   occupied by the old integration.

**Never delete the resource group or Foundry account to change gateway tiers.**
Do not create the replacement on a subnet still occupied by the old gateway.
Azure soft-delete can reserve a deleted service name. Prefer an approved new
gateway name; do not purge recoverable resources without separate approval.

## 6. Create the AI Gateway pricing-tier instance

1. Open the [AI Gateway portal](https://ai.gateway.azure.com) and sign in with
   the approved Entra account. This is the standalone AI Gateway experience,
   not **APIM > APIs > AI Models** in a Standard v2 resource.
2. Select **Create gateway**.
3. Enter the approved globally available gateway name.
4. Select the existing subscription and **Sweden Central**.
5. Under **Advanced**, select the existing resource group. Do not accept an
   unintended automatically created resource group.
6. Select **Create** and wait for activation/provisioning to finish.
7. In Azure Portal, locate the resulting API Management resource and verify
   **Overview / JSON View** reports `sku.name = AIGateway` and provisioning
   **Succeeded**. Do not accept `StandardV2`, `Consumption`, or an unverified
   pricing-tier label as equivalent.

The AI Gateway portal does not ask the administrator to plan scale units.
The ARM configuration's capacity value does not make this a Standard v2 unit.

## 7. Configure managed identity and Foundry access

1. In the AI Gateway portal, open **Managed identities**.
2. Under **Configure identities**, enable **System-assigned identity** and
   save. Record its **Object (principal) ID**, not an application/client ID.
3. In Azure Portal, open the existing **Foundry resource > Access control
   (IAM) > Add > Add role assignment**.
4. Select **Foundry User**, role ID
   `53ca6127-db72-4b80-b1b0-d745d6d5456d`.
5. Select **Managed identity**, choose the new gateway's system-assigned
   identity, and complete **Review + assign** at the **Foundry account scope**.
6. Verify the principal ID and role assignment, and allow time for RBAC propagation.

If the import wizard offers to grant this same account-scoped role, verify the
existing assignment instead of granting broader permissions. Do not grant the
gateway subscription-wide Contributor/Owner. Backend authentication requests
a token for `https://cognitiveservices.azure.com/`; callers use the gateway key,
not a Foundry key or a Foundry-audience bearer token.

## 8. Configure both networking directions

### 8.1 Outbound private routing to Foundry

1. In the AI Gateway portal, open **Networking > Outbound**.
2. Select **Private routing**.
3. Select the existing VNet and now-free `snet-aigw-outbound`.
4. Resolve warnings about region, subnet dedication/size, delegation, or the
   NSG's outbound HTTPS rules for Storage and Azure Key Vault.
5. Select **Save** and wait for the long-running update to complete.
6. Confirm the saved configuration references the correct subnet. The
   Foundry private DNS zones must be linked/resolvable from this VNet.

The portal's prerequisite warnings are advisory; successfully saving a form
does not prove that routing or backend inference works.

### 8.2 Inbound Private Link for private clients

1. Under **Networking > Inbound > Private endpoints**, select
   **Create a private endpoint**. This opens Azure Portal, pre-targeted at
   the gateway.
2. Select target subresource **Gateway**, the existing VNet, and
   `snet-aigw-inbound`.
3. Enable private DNS integration with the existing
   `privatelink.azure-api.net` zone.
4. Return to the gateway networking page, **Refresh**, and approve a pending
   connection if required. Verify **Approved** and **Succeeded**.
5. Confirm the zone's VNet link and the generated record for this **new**
   gateway hostname. An old gateway's DNS record is not a replacement record.
6. Keep **Public network access = Enable** for the intended internet clients.
   A private endpoint does not disable the public gateway automatically.

Private clients use the same `https://GATEWAY_NAME.azure-api.net` hostname.
Their DNS must resolve it to the gateway private endpoint IP, with routes and
NSGs allowing TCP 443. Direct peering alone does not configure DNS. Use the
normal hostname for TLS; do not disable certificate validation or call the IP URL.

## 9. Import the three existing models

1. In the AI Gateway portal, select **Add models > Import from Foundry**,
   or **Home > Configure your gateway > Get started**.
2. Select the approved subscription and filter to the existing resource group.
3. Select the existing Foundry **account**. The setup wizard imports all
   deployments in each selected account, not an independently created model
   deployment for each client.
4. On the provider/authentication step, select **Managed identity (Microsoft
   Entra ID)** and the gateway's **system-assigned identity**. Do not leave
   the default key-based option selected.
5. Review the discovered deployments and select **Import / Create**.
6. Inspect **Verifying requirements** and any per-account warning. A partially
   completed wizard is not success; fix skipped/failed imports explicitly.
7. In **Models / Discover**, confirm exactly the three intended deployments
   and inspect their connection details and caller-visible names:
   `Gpt5.4mini`, `Phi`, and `FW-DeepSeek-V4.1-Flash`.

The import uses deployment names for model requests; catalog names are not
interchangeable. Model names must be unique across the gateway and are matched
exactly. If the current portal exposes different names, resolve the naming
configuration before distributing client samples; do not guess a model name.

Use the **OpenAI chat completions** endpoint supported by these deployments.
Do not assume `/responses` or another API is supported by every imported model.
Do not create Standard v2 backends/APIs, `aimodel` tags, products, subscriptions,
XML policies, or Entra facade APIs to register preview-tier models.

## 10. Create and distribute a runtime key

1. Open **Keys > Create API key** in the AI Gateway portal.
2. Use an application/environment-oriented name, such as `test-client`, and
   identify the accountable owner.
3. Select **Create**, then place the value in the client's approved secret store.
4. Copy the **exact base URL from the gateway connection details**. In this
   configuration it is:

   ```text
   https://GATEWAY_NAME.azure-api.net/default/models/openai/v1
   ```

5. Configure clients to send the key in **`api-key`**. An APIM subscription key,
   an `Ocp-Apim-Subscription-Key` header, or an Entra bearer token alone is not
   the runtime credential for this configuration.
6. Rotate/revoke keys through **Keys** when ownership changes or exposure is
   suspected. Use separate keys for independent applications when necessary,
   while documenting that every such key still reaches every published model.

Do not use or distribute the built-in administrative/playground key as the
application credential. Do not paste runtime keys into source, logs, shared
documents, or screenshots.

## 11. Acceptance checks and optional client sample

### 11.1 Portal and runtime sign-off

- [ ] The sole active gateway reports `AIGateway` and provisioning Succeeded.
- [ ] The old Standard v2 service and its private endpoint are removed; the
      shared resource group, VNet, four subnets, NSGs, DNS, and Entra objects remain.
- [ ] Foundry remains private, local authentication remains disabled, and the
      three deployment names/versions/capacities are unchanged.
- [ ] The new gateway identity has only the intended account-scoped Foundry User access.
- [ ] Outbound integration is saved against `snet-aigw-outbound`.
- [ ] Gateway and Foundry private endpoint connections are Approved/Succeeded;
      private DNS records match their endpoint IP configurations.
- [ ] In **Discover**, open each of the three models and obtain an actual
      nonempty chat response. Listing models is not an inference test.
- [ ] Using an application runtime key, all three models return HTTP 200 on
      the shared chat-completions endpoint; verify a streamed response as well.
- [ ] Removing the runtime key, using an invalid key, or sending only the
      subscription-key header returns HTTP 401.
- [ ] A valid runtime key reaches all three models **by design**; no per-model
      key-isolation or Entra-only entrypoint claim is made.
- [ ] From an existing private-network client, the normal gateway hostname
      resolves to its private endpoint and an authenticated request succeeds.
- [ ] Public clients still succeed where intended. A successful public call
      is not proof that the private-client ingress path works.

The built-in Discover playground can use a built-in key. Its success does
not verify the application's runtime key or negative authentication cases.
Use an approved HTTP client for those cases. Preserve diagnostics for failures
without recording credentials.

### 11.2 Optional Python HTTPS sample: internet or private client

This is an **inference test**, not a deployment step. It uses the Python
standard library. Supply `AI_GATEWAY_BASE_URL` and `AI_GATEWAY_API_KEY` through
the local environment/secret store; do not hard-code them. Optionally set
`AI_GATEWAY_MODEL` to one of the three exact names; the default is `Phi`.

For private-path verification, run from an existing network-connected host
and also set `AI_GATEWAY_PRIVATE_IP` to the private IP shown in the new
gateway endpoint's **DNS configuration**. The sample requires matching DNS
and bypasses HTTP proxies for that test. It does not create VPN connectivity.

```python
import json
import os
import socket
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPSHandler, ProxyHandler, Request, build_opener

base_url = os.environ["AI_GATEWAY_BASE_URL"].rstrip("/")
key = os.environ["AI_GATEWAY_API_KEY"]
model = os.environ.get("AI_GATEWAY_MODEL", "Phi")
url = urlsplit(base_url)
if url.scheme != "https" or not url.hostname or url.username or url.password:
    raise SystemExit("Use the gateway's HTTPS base URL without credentials.")
if model not in {"Gpt5.4mini", "Phi", "FW-DeepSeek-V4.1-Flash"}:
    raise SystemExit("Select an exact registered model name.")

private_ip = os.environ.get("AI_GATEWAY_PRIVATE_IP")
if private_ip:
    addresses = {
        item[4][0]
        for item in socket.getaddrinfo(url.hostname, 443, type=socket.SOCK_STREAM)
    }
    if addresses != {private_ip}:
        raise SystemExit(f"Private DNS mismatch: expected {private_ip}, got {addresses}")
    opener = build_opener(ProxyHandler({}), HTTPSHandler())
else:
    opener = build_opener()

payload = {
    "model": model,
    "messages": [{"role": "user", "content": "Reply with exactly READY."}],
    "stream": False,
}
if model == "Gpt5.4mini":
    payload.update(max_completion_tokens=512, reasoning_effort="low")
else:
    payload["max_tokens"] = 64 if model == "Phi" else 256

request = Request(
    f"{base_url}/chat/completions",
    data=json.dumps(payload).encode("utf-8"),
    headers={"Content-Type": "application/json", "api-key": key},
    method="POST",
)
try:
    with opener.open(request, timeout=180) as response:
        completion = json.load(response)
except HTTPError as error:
    raise SystemExit(
        f"HTTP {error.code}: {error.read().decode('utf-8', errors='replace')}"
    ) from error

print(completion["choices"][0]["message"]["content"])
```

Do not change TLS verification, substitute an IP in the URL, or enable Foundry
public access to make a private-path test pass. A corporate-proxy-only client
may need an approved direct private route before this sample can succeed.

## 12. Troubleshooting

| Symptom | Check / corrective action |
|---|---|
| Wrong tier or old Standard API UI | Confirm `sku.name = AIGateway`; manage preview models/keys at `https://ai.gateway.azure.com`. |
| Gateway creation/integration fails | Confirm region, subscription eligibility, completed old-gateway deletion, dedicated delegated subnet, NSG dependencies, and subnet join permissions. |
| Gateway name unavailable after deletion | Check soft-delete/name reservation; use an approved new name or obtain explicit recovery/purge approval. |
| HTTP 401 from gateway | Use an active runtime key in `api-key`, not a Foundry key, subscription header, or bearer token alone. |
| Backend 401/403 or failed import | Check provider managed-identity selection, the new principal ID, account-scoped Foundry User, RBAC propagation, private DNS, and Foundry network access. |
| HTTP 404 / model not found | Verify `/default/models/openai/v1`, the supported chat operation, and the exact imported name/case. |
| HTTP 429 | Honor `Retry-After`; keys do not multiply Foundry RPM/TPM. Change capacity only with quota and cost approval. |
| Private endpoint Approved but private client fails | Check DNS from that client, VNet links/forwarding, peering/VPN routes, NSGs, proxy behavior, and the new hostname's record. |
| Foundry portal loads but direct model test fails | Browser sign-in is not private network connectivity; check the administrator's route/DNS/NSG access. |
| Need per-model keys or Entra runtime authorization | Return to the Standard v2 configuration; do not pretend gateway-wide preview keys provide those boundaries. |

For return to Standard v2, retain the foundation and follow the separate
[Standard v2 runbook](manualsteps-apimv2-standard.md) after removing the AI
Gateway from the shared outbound subnet. New identities/keys and service
provisioning time must be expected; this is not an instantaneous tier toggle.

## References

- [AI Gateway overview, regions, preview terms, and key scope](https://learn.microsoft.com/azure/api-management/ai-gateway-overview)
- [Create an AI Gateway tier instance](https://learn.microsoft.com/azure/api-management/quickstart-ai-gateway-create)
- [AI Gateway private networking and subnet requirements](https://learn.microsoft.com/azure/api-management/ai-gateway-configure-private-networking)
- [Import and manage AI Gateway models](https://learn.microsoft.com/azure/api-management/ai-gateway-manage-models-tools)
- [Runtime keys and managed-identity backend access](https://learn.microsoft.com/azure/api-management/ai-gateway-govern-secure-assets)
- [Foundry private networking](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link)
- [Foundry model deployments](https://learn.microsoft.com/azure/foundry/foundry-models/how-to/create-model-deployments)
- [Disable Foundry local authentication](https://learn.microsoft.com/azure/ai-services/disable-local-auth)
- [APIM soft-delete and name reuse](https://learn.microsoft.com/azure/api-management/soft-delete)
- [AI Gateway Terraform root and tier switching](terraform/apim-ai-gateway/README.md)
- [Retained foundation and Standard v2 root](terraform/apim-only/README.md)
