# Switchable APIM tiers with private Microsoft Foundry

Two separate Terraform roots support one active gateway in Sweden Central:
**AI Gateway preview** for the lower-cost test configuration, or **Standard v2**
when its API-scoped subscriptions and Entra access controls are required.

**Current test profile, verified 22 October 2026:** AI Gateway
[`aigw-test-8ps1sz`](https://portal.azure.com/#resource/subscriptions/fb7dfa70-78b9-4e56-8d2d-fa2eff765241/resourceGroups/rg-foundry-aigateway-sweden/providers/Microsoft.ApiManagement/service/aigw-test-8ps1sz/overview)
is active; the Standard v2 gateway is removed and disabled in its local
deployment settings. All seven models passed completion/streaming checks, and
both Terraform roots have no pending changes. Use the validation commands in
the gateway guide to repeat these checks.

Internet/private clients reach the selected gateway, which uses the shared
VNet and Foundry private endpoint. AI Gateway publishes seven configured
deployments: `Gpt5.4mini`, `Phi`, `FW-DeepSeek-V4.1-Flash`,
`claude-opus-5-5`, `gpt-6-astra`, `FW-GLM-5.3-Flash`, and `FW-Kimi-K3`.

No application, Azure Front Door, database, or storage account is deployed.
The gateway uses its
system-assigned managed identity and the account-scoped Foundry User role to
call model deployments over private networking without Foundry API keys.

## Terraform roots and ownership

[terraform/apim-only](terraform/apim-only) owns the shared foundation and the
optional Standard v2 gateway. [terraform/apim-ai-gateway](terraform/apim-ai-gateway)
has independent state and owns only the alternative AI Gateway and its
gateway-specific resources. It reads nonsecret foundation connection metadata;
no Foundry model, VNet, subnet, or DNS zone has two Terraform owners.

The retained Standard configuration includes:

- API Management in the `StandardV2` pricing tier, one unit
- a private-only Microsoft Foundry `AIServices` account
- the original three published deployments: `Gpt5.4mini`, `Phi`, and `FW-DeepSeek-V4.1-Flash`
- three Foundry-linked backends and HTTPS model APIs, registered in AI Models,
  with three independently managed API-scoped subscriptions
- three additive Entra-protected model entrypoints on the same gateway, backed
  by one single-tenant API registration with separate per-model app roles
- three published, subscription-required products, each containing only its
  matching model API; new product subscriptions require administrator approval
  and are limited to one per developer per product
- one shared VNet with four separate inbound/outbound subnets
- Foundry and gateway private endpoints, private DNS, and supporting NSGs

The selected gateway stays publicly accessible to internet clients. Its separate inbound
subnet additionally supports private clients. Foundry public access is disabled.
The Foundry trusted Azure services network exception is enabled; authentication
and RBAC permissions are still required.
When Standard v2 is enabled, each APIM subscription is scoped to one model API. Its key cannot call the other
two APIs, and API policies validate and enforce the backend deployment rather
than trusting a client-supplied model override. Client subscription keys are
APIM credentials, not Foundry API keys; Foundry local authentication is disabled.
Entra callers use separate `/entra/<model-api-id>/openai/v1` entrypoints with
a gateway-audience bearer token and the matching model role. Existing key URLs
and keys remain unchanged; the same three backend models are reused.

The four additional deployments are owned by the same foundation root and
published by AI Gateway only. Returning to Standard retains all seven Foundry
deployments, but does not automatically create Standard APIs, subscriptions,
products, or Entra roles for the four additions.

AI Gateway preview exposes `/default/models/openai/v1/chat/completions` for
OpenAI-compatible models and `/default/models/anthropic/v1/messages` for Claude.
Clients use a gateway runtime key in `api-key`; Claude also needs
`anthropic-version: 2023-06-01`.
Every runtime key can invoke every published model; per-model subscriptions,
products, XML API policies, and the Entra-only entrypoints are not reproduced.
The existing Entra registration/assignments are retained for return to Standard.

Switching is a maintenance-window replacement, not an in-place SKU patch.
Disable and apply the active root's gateway setting before enabling the other
tier. Both roots check outbound-subnet occupancy. The same four /24 subnets
and all configured Foundry deployments are preserved; no extra subnet or second
permanent gateway is needed. Do not destroy the foundation root to change tiers.

In Standard v2, the AI Models and APIs portal pages manage the same underlying APIs. Terraform
associates the reserved `aimodel` tag with each model API so it appears in the
AI-focused view as well as the general APIs view. This metadata does not create
another Foundry deployment or replace subscription authorization.

The requested DeepSeek name maps to the GA Foundry catalog model
`DeepSeek-V4-Flash` version `2026-04-23`. No extra per-user model deployments or
application-specific cost policies are created.

The additions use pay-as-you-go `GlobalStandard`, capacity 10 each, with pinned
versions: Claude Opus 5.5 Azure-hosted version `2`, GPT-6 Astra `2026-09-03`,
and Fireworks GLM 5.3 Flash / Kimi K3 version `1`. No PTUs are purchased.
Claude requires explicit Marketplace organization attestation. Fireworks
requires the subscription feature `Fireworks.EnableDeploy`; it is outside EU
Data Boundary commitments and processes inference on Fireworks infrastructure.

## VS Code Chat: Other models

Use **Chat: Manage Language Models > Add Models > Custom Endpoint** and name
the group **AI Gateway**. Configure Chat Completions with the exact model ID
`FW-DeepSeek-V4.1-Flash` and full URL:

```text
https://aigw-test-8ps1sz.azure-api.net/default/models/openai/v1/chat/completions
```

Enable tool calling so the model is available for agents. Keep the gateway
key in VS Code's secure API-key input, not in workspace settings or source.
Bearer runtime-key authentication is accepted by the current gateway and is
compatible with the Custom Endpoint provider. In agent-host chat, enable
`chat.agentHost.byokModels.enabled`. The model appears under **Other models**
with its configured **AI Gateway** group. If the picker has not refreshed,
use **Developer: Reload Window**.

### Troubleshooting VS Code authentication

For explicit gateway key authentication, add the following model-level
configuration. The Custom Endpoint provider substitutes `${apiKey}` from its
secure credential store at request time and suppresses its default Bearer
authentication header; the setting contains no credential:

```json
"requestHeaders": {
  "api-key": "${apiKey}"
}
```

If VS Code reports `502 Unauthorized` with a missing Entra token or
`Data.All` scope message, check the underlying gateway response. The gateway
also returns that message for an invalid runtime key; it does not mean that
client Entra authentication must be enabled.

Open **Language Models > AI Gateway > More Actions > Update API Key** and
enter the current runtime key from the AI Gateway portal's **Keys** page.
Enter only the key, without an `api-key:` or `Bearer` prefix, in the secure
API-key input. Do not put it in workspace settings or source. Start a fresh
chat after updating it; reload the window if an existing chat retains an old
credential.

The preview tier uses gateway runtime keys, not Standard v2 APIM subscription
keys or Foundry API keys. Client key authentication and the gateway's backend
managed identity are independent: keep Foundry's managed-identity connection
enabled and its local-key authentication disabled. Granting `Data.All` or enabling Foundry
API keys is not a fix for a stale VS Code runtime credential.

### Maximum DeepSeek limits

The existing `FW-DeepSeek-V4.1-Flash` deployment still serves
`DeepSeek-V4-Flash` version `2026-04-23`; maximizing limits does not replace
the model. As checked on 23 October 2026:

| Limit | Foundry | AI Gateway | VS Code |
|---|---|---|---|
| Throughput | 250,000 tokens/minute | Same upstream limit; no additional configured cap | Same upstream limit; no client rate cap |
| Requests | 250 requests/minute | Same upstream limit; no additional configured cap | Same upstream limit; no client rate cap |
| Model context | 1,000,000 tokens | Passed through to Foundry | `contextWindow: 1000000` |
| Maximum output | 384,000 tokens, as published by Microsoft | Passed through to Foundry | `maxOutputTokens: 384000` |

The context/output ceilings are listed in
[Microsoft's DeepSeek model specifications](https://learn.microsoft.com/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure#deepseek).
Use this model-level configuration in VS Code:

```json
"contextWindow": 1000000,
"maxOutputTokens": 384000
```

`contextWindow` is VS Code's source of truth for input plus output.
With the full 384,000-token output reservation, VS Code derives a
616,000-token prompt budget. Omit `maxInputTokens` rather than retaining the
old 57,344-token input cap or configuring input plus output beyond the full
window. This maximum profile replaces the earlier 64K mitigation and retains
tool calling and secure `api-key` interpolation. Reload the window or start a
fresh chat if an existing session retains old model metadata.

The Foundry deployment already uses all approved Sweden Central Global
Standard quota: capacity 250 of 250 for
`AIServices.GlobalStandard.DeepSeek-V4-Flash`. The Terraform foundation also
persists capacity 250. A higher SKU capacity ceiling advertised in the model
catalog is not approved subscription quota. Raising throughput further
requires an Azure quota increase, followed by an intentional change to the
foundation's deployment capacity. No larger allocation has been approved or
applied. Gateway policies cannot raise a Foundry quota, and VS Code has no
setting that purchases or allocates more TPM.

### Troubleshooting DeepSeek token-rate limits

The maximum profile does not guarantee that a full-context request fits the
current per-minute quota. Context tokens and tokens/minute have different
units and must not be treated as the same setting. Prompt history and tool
definitions are resent on each turn; the failing conversation grew beyond
126K input tokens per turn, so two nearby turns could exhaust the deployment's
minute budget even though replies were short. The output ceiling is a maximum,
not a requirement to generate that many tokens on every call.

Agent tool loops and simultaneous clients can still exhaust the minute budget.
The agent host may display the
backend's HTTP 429 as `502 Rate limit exceeded`; its five retries over about
15 seconds do not span a full reset window. Wait for the server's
`retry-after`/`retry-after-ms` or `x-ratelimit-reset-tokens` delay before retrying.
If that timing is unavailable, pause for at least a minute instead of repeatedly
resubmitting. Compact history or start a fresh chat when practical. Sustained
larger-context or concurrent workloads need a quota increase and a reviewed
deployment-capacity change, not another runtime key or client Entra
authentication.

See [the AI Gateway deployment and switching guide](terraform/apim-ai-gateway/README.md)
for both switch directions, persistent settings, preview limitations, pricing,
and secure runtime-key retrieval. The
[Standard v2 guide](terraform/apim-only/README.md) documents its retained
configuration, private networking, and model-specific access.

For administrator-led setup without Terraform, follow the
[AI Gateway portal runbook](manualsteps-apimv2-foundry.md). It covers the
ordered four-subnet, private Foundry, standalone gateway portal,
managed-identity/RBAC, model import, runtime-key, and verification steps.
The [Standard v2 portal runbook](manualsteps-apimv2-standard.md) remains
available for that tier's APIs, products, subscriptions, and Entra controls.
These manual runbooks describe the original three-model baseline. Use the
Terraform guides for the four additional deployments and partner onboarding;
do not delete the additions to match the older baseline when switching tiers.

## Customer/model token-usage dashboards

The independent [token-observability root](terraform/token-observability/README.md)
creates Log Analytics, workspace-based Application Insights, and Azure Managed
Grafana in `rg-law`. It imports the Downloads CSV examples into the standard
`AppRequests` and `AppMetrics` tables and provides customer/model token views.
The examples are not a live feed from the existing AI Gateway; the guide
documents token mappings, missing-sample coverage, costs, and repeatable setup.

## Retained legacy definitions

The original [terraform](terraform) root still contains chat1, chat2, LiteLLM,
and MLflow definitions for later use. They are not part of the active isolated
state and were not deployed. The Front Door resource file and all Terraform
references to it were removed.

The standalone packages also remain unchanged:

- [standalone-litellm](standalone-litellm)
- [standalone-mlflow](standalone-mlflow)