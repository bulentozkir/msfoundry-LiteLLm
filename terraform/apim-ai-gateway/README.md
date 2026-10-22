# AI Gateway preview: alternate Terraform root

This root replaces the test gateway with the **`AIGateway` pricing tier** while
retaining the existing private Foundry account and its configured model deployments.
It is independent of the [Standard v2 root](../apim-only/README.md), with its
own local state and provider lock file.

The expanded seven-model test deployment was verified on **22 October 2026**:

| Setting | Current value |
|---|---|
| Gateway | `aigw-test-8ps1sz`, SKU `AIGateway`, Succeeded |
| Region / resource group | Sweden Central / `rg-foundry-aigateway-sweden` |
| OpenAI base URL | `https://aigw-test-8ps1sz.azure-api.net/default/models/openai/v1` |
| Persisted profile | Standard gateway disabled; AI Gateway enabled |
| Verification | All seven models completed and streamed, including native Claude Messages; invalid credentials were rejected; both roots converged |
| Private ingress | Endpoint Approved/Succeeded; DNS matches `10.42.3.4`. A connected-client request remains unverified because this workstation's direct connection to that IP timed out. |

**Do not run `terraform destroy` on the Standard/foundation root to switch
tiers.** It still owns the resource group, Foundry account/models, VNet, four
subnets, NSGs, shared private DNS, Foundry private endpoint, and Entra objects.

## Ownership and prerequisites

| Root | Sole ownership |
|---|---|
| `../apim-only` | Shared foundation, retained Entra registration/roles, and optionally Standard v2 gateway resources |
| This directory | AI Gateway instance, its Foundry role assignment, provider/model/alias registrations, runtime key, RBAC timer, and gateway private endpoint |

This root reads only connection metadata from the sibling root's
`gateway_foundation` output using a **read-only local-state data source**.
It does not import, copy, recreate, or jointly manage foundation resources.
The data source has access to the state file, not just its nonsecret output;
protect both local states and backups because they contain runtime credentials.
If moving to remote state later, migrate the backend/read configuration
deliberately; do not point both roots at the same writable backend.

Prerequisites:

- Terraform 1.9+, Azure CLI sign-in, and the required existing Azure/Entra permissions.
- Apply the updated foundation root so its `gateway_foundation` output exists.
- The foundation's `standard_gateway_enabled` must be `false`, and its
  gateway deletion must have finished, before this root can create a gateway.
- The original outbound subnet must be free. Both roots reject the other
  gateway occupying that subnet.
- Keep the existing tenant, subscription, resource group, and Sweden Central region.
  Those values are read from the foundation rather than independently selected here.

## Important behavior differences

AI Gateway preview is a different product surface, not a cheaper Standard v2
instance retaining all its API configuration:

- Base URL: `https://<gateway>.azure-api.net/default/models/openai/v1`.
- The six OpenAI-compatible deployments share `/chat/completions`; choose the
  exact model in the request body. Claude uses the native Anthropic Messages
  endpoint `/default/models/anthropic/v1/messages` instead.
- Clients send a runtime key in `api-key`, not `Ocp-Apim-Subscription-Key`.
  The current gateway also accepts `Authorization: Bearer <runtime-key>` for
  OpenAI-compatible clients such as VS Code's Custom Endpoint provider.
- **Every runtime key can invoke all published models and tools.** There is no
  per-model subscription-key boundary in this tier.
- The Standard v2 products, subscriptions, XML API policies, and Entra-only
  facade APIs are not recreated. The Entra registration/assignments remain in
  the foundation for a later return to Standard v2.
- Use the [standalone AI Gateway portal](https://ai.gateway.azure.com) for
  model/key administration, not the Standard v2 AI Models blade.
- Public gateway access stays enabled. The separate private endpoint adds
  private ingress; it does not disable public ingress.
- Foundry stays private with local keys disabled, the approved trusted-services
  exception enabled, and backend access through the gateway's managed identity
  with account-scoped Foundry User.
- A tier switch leaves the foundation's model names, versions, capacities,
  VNet, and four /24 subnets unchanged. Model additions are managed only by the
  foundation root. No application, database, or monitoring is added.

## Additional models

Apply the [foundation's partner onboarding and model rollout](../apim-only/README.md#partner-onboarding-and-model-rollout)
before planning this root. It creates the four requested deployments while
retaining the original three:

| Deployment | Version | Gateway operation |
|---|---|---|
| `claude-opus-5-5` | `2`, hosted on Azure | `/default/models/anthropic/v1/messages` |
| `gpt-6-astra` | `2026-09-03` | `/default/models/openai/v1/chat/completions` |
| `FW-GLM-5.3-Flash` | `1` | `/default/models/openai/v1/chat/completions` |
| `FW-Kimi-K3` | `1` | `/default/models/openai/v1/chat/completions` |

Each uses pay-as-you-go `GlobalStandard`, capacity 10, with automatic upgrades
disabled. No PTUs, new Foundry account, or second gateway are created.
Fireworks activation and Claude's actual Marketplace attestation belong to the
foundation, not this root. Existing Standard APIs/Entra roles remain unchanged.

All seven deployments use the existing gateway-wide runtime key. Adding models
does not create an APIM subscription or per-model credential boundary. Use the
nonsecret `model_endpoints` output to select the right native protocol.
For Claude, send `anthropic-version: 2023-06-01`, `model`,
`max_tokens`, and `messages`; its response has Anthropic `type: message` and
content blocks, not OpenAI `choices`. Native streams end with `message_stop`,
not `[DONE]`.

The ARM SKU is `AIGateway`, **not** `AIGatewayV2`. The API version is pinned to
`2025-09-01-preview`, the latest advertised and previously working version in
this subscription on 20 October 2026. Microsoft documentation recommends
`2026-05-01-preview`, but a read-only live request for that version returned
`NoRegisteredProviderFound`. Recheck availability before upgrading automation.
Schema validation is disabled only for these preview resource types, which
are not fully described by the installed provider schema.

## Cost and preview terms

Retail pricing queried for Sweden Central on 20 October 2026:

| Meter | Retail USD price |
|---|---:|
| Standard v2 first unit | 1.25/hour, about 912.50 per 730-hour month |
| AI Gateway preview requests | 0 per 10,000 requests |

The preview has no SLA and its pricing/limits can change. The zero request
meter is not a promise that all related resources or future gateway usage are
free. Foundry inference/capacity, private endpoints, DNS, and applicable network
charges remain. Stop the old gateway to remove its fixed Standard v2 charge;
keeping both deployed is not the intended low-cost configuration.

## Switching tiers

This is a **maintenance-window replacement**, not an in-place SKU update.
Only one gateway can use `snet-aigw-outbound` at a time. Always:

1. Persist the source tier's disabled setting.
2. Validate, review, and apply its gateway-only removal plan.
3. Wait for gateway deletion/subnet release.
4. Persist the target tier's enabled setting.
5. Validate, review, and apply its creation plan.
6. Test actual model calls, update clients, and verify both roots converge.

The files `gateway.auto.tfvars.json` below are ignored local deployment
settings, not secrets. Keep them persistent: a one-off `-var=false` does not
change the next command's default. Do not write two conflicting enable settings
in multiple tfvars files. CLI `-var` overrides must be used deliberately.

### Standard v2 to AI Gateway

From the repository root in PowerShell:

```powershell
Set-Location .\terraform\apim-only
'{"standard_gateway_enabled":false}' |
    Set-Content -Path .\gateway.auto.tfvars.json -Encoding utf8
terraform init -input=false
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan-disable-standard
# Review: only Standard gateway children, its private endpoint, MI role, and timer.
terraform apply tfplan-disable-standard

Set-Location ..\apim-ai-gateway
'{"ai_gateway_enabled":true}' |
    Set-Content -Path .\gateway.auto.tfvars.json -Encoding utf8
terraform init -input=false
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan-enable-ai
# Review: only the AI Gateway resources listed in this README.
terraform apply tfplan-enable-ai
.\tests\Test-AiGateway.ps1
..\tests\Test-TierExclusivity.ps1 -ActiveTier AIGateway
```

The first plan must not destroy/change the Foundry account, three deployments,
VNet/subnets, NSGs, shared DNS, Foundry private endpoint, resource group, or
Entra registration/assignments. Terraform moved blocks preserve existing
singleton addresses when the Standard gateway remains enabled.

### AI Gateway back to Standard v2

From this directory:

```powershell
'{"ai_gateway_enabled":false}' |
    Set-Content -Path .\gateway.auto.tfvars.json -Encoding utf8
terraform validate
terraform plan -out=tfplan-disable-ai
# Review: only AI Gateway-owned resources may be deleted.
terraform apply tfplan-disable-ai

Set-Location ..\apim-only
'{"standard_gateway_enabled":true}' |
    Set-Content -Path .\gateway.auto.tfvars.json -Encoding utf8
terraform validate
terraform plan -out=tfplan-enable-standard
terraform apply tfplan-enable-standard
.\tests\Test-StandardApim.ps1
.\tests\Test-EntraApim.ps1
..\tests\Test-TierExclusivity.ps1 -ActiveTier StandardV2
```

Review names before recreating either tier. Soft-delete can reserve a service
name for 48 hours. Each root accepts an optional `gateway_name` so a new
globally unique name can be supplied in its local tfvars rather than purging
recoverable resources. For example, the Standard root's local file can contain:

```json
{
  "standard_gateway_enabled": true,
  "gateway_name": "apim-standard-test-replacement"
}
```

Obtain approval for any purge or recovery/import workflow; it is not part of
this switching procedure. A new gateway name changes URLs. New instances also
get new managed identities and runtime/subscription keys. The Standard root
keeps its Entra audience, role IDs, registration, and assignments stable even
when `gateway_name` changes. Do not rename an active gateway without reviewing
the resulting replacement plan.

After either switch, run `terraform plan -detailed-exitcode` in **both** roots.
Exit 0 means converged; exit 2 means changes remain; exit 1 is an error.
Use newly generated plans only, never historical migration/deletion plans.
Do not copy state between roots, force-unlock an active operation, or restore a
pre-deletion state backup over live state.

## Client access

From this root, capture the credential without printing it:

```powershell
$env:AI_GATEWAY_BASE_URL = terraform output -raw openai_base_url
if ($LASTEXITCODE -ne 0) { throw "Cannot read gateway URL." }
$env:AI_GATEWAY_API_KEY = terraform output -raw runtime_api_key
if ($LASTEXITCODE -ne 0) { throw "Cannot read runtime credential." }

$body = @{
    model = "Phi"
    messages = @(@{ role = "user"; content = "Reply READY." })
    max_tokens = 64
} | ConvertTo-Json -Depth 6
try {
    Invoke-RestMethod -Method Post `
        -Uri "$env:AI_GATEWAY_BASE_URL/chat/completions" `
        -Headers @{ "api-key" = $env:AI_GATEWAY_API_KEY } `
        -ContentType "application/json" -Body $body
}
finally {
    Remove-Item Env:\AI_GATEWAY_API_KEY
}
```

Use the exact published names. The original OpenAI-compatible names are
`Gpt5.4mini`, `Phi`, and `FW-DeepSeek-V4.1-Flash`; the four additions are
listed above.
For GPT mini use `max_completion_tokens` and, if desired, `reasoning_effort = low`;
the other two accept `max_tokens`. Model RPM/TPM is unchanged by the tier switch.

For private clients, link/forward the gateway private DNS zone into their
network and retain routing/NSG access to the private endpoint. Keep the normal
HTTPS gateway hostname, not its IP. A successful internet call verifies neither
private-client DNS nor private-client routing.

## Validation and operational checks

```powershell
terraform fmt -check -recursive
terraform validate
terraform test -filter=tests\ai_gateway.tftest.hcl
.\tests\Test-AiGateway.ps1
```

The mocked tests cover tier, model registrations, MI/RBAC, private endpoint/DNS
wiring, disabled behavior, invalid names, and occupied-subnet rejection.
`Test-AiGateway.ps1` checks real completions and streaming for all seven models,
including native Anthropic response/event shapes, missing/invalid keys on
both protocols, Bearer runtime-key authentication for VS Code, the wrong
subscription-key header, unknown model rejection, and gateway-wide scope.
It can wait through Foundry throttling
and RBAC propagation; it makes billable model requests.

The 22 October verification passed all 10 foundation and 4 gateway mocked
Terraform tests, live completion/streaming for every deployment, HTTP 401
checks for missing/invalid and wrong subscription-header credentials on both
protocols, and HTTP 404 checks for unknown models. DeepSeek also returned a
valid forced function call using Bearer runtime-key authentication for VS Code.
Both live Terraform plans returned exit code 0 after the rollout. No existing
gateway, key, original model deployment, identity, or network was replaced.

The shared exclusivity test performs a real **plan only** in the inactive root
and requires the subnet-conflict diagnostic; it does not provision a second
gateway. A freshly mocked Standard foundation defers resource-group discovery,
so that guard is verified against existing live resources rather than claiming
a plan-time mock assertion proves the live boundary.

For manual administrator deployment, see the
[AI Gateway portal runbook](../../manualsteps-apimv2-foundry.md).
The [Standard v2 runbook](../../manualsteps-apimv2-standard.md) remains the
fallback reference. Existing Standard v2-specific access diagrams describe
that tier's authorization, not AI Gateway preview key isolation.
