# Microsoft Foundry and AI Gateway in East US 2

The active deployment is in resource group `rg-foundry-aigateway`, East US 2,
in subscription `fb7dfa70-78b9-4e56-8d2d-fa2eff765241`. The former
`rg-foundry-aigateway-sweden` deployment has been deleted.

The dedicated `Microsoft.ApiManagement/aigateways` resource
`aigw-us-c2yj6j` has a **public HTTPS frontend** and uses its
system-assigned identity and the account-scoped Foundry User role to reach
the private Foundry account `fdry-aigw-us-c2yj6j`. Foundry public networking
and local key authentication are disabled; private DNS and a private
endpoint provide backend connectivity. The new gateway does **not** support
the former APIM gateway's inbound private endpoint. Gateway-wide runtime keys
authorize access to all registered models, not individual models.

The gateway service reports the `Premium` SKU. Check current pricing before
recreating or changing it. The model deployments below use `GlobalStandard`;
resource location does not by itself guarantee that inference processing
remains in the US.

## Models and endpoints

These aliases are deployed and have passed direct gateway inference:

| Gateway alias | Foundry catalog model | Protocol | Tokens/minute | Requests/minute |
|---|---|---|---:|---:|
| `FW-DeepSeek-V4.1-Flash` | `DeepSeek-V4-Flash`, version `2026-04-23` | OpenAI chat completions | 250,000 | 250 |
| `FW-Kimi-K3` | `FW-Kimi-K3`, version `1` | OpenAI chat completions | 500,000 | 500 |
| `Kimi-K3.1-Pro` | `Kimi-K3.1-Pro`, version `2026-11-04` | OpenAI chat completions and Responses | 100,000 | 100 |
| `gpt-6-astra` | `gpt-6-astra`, version `2026-09-03` | OpenAI chat completions | 250,000 | 250 |
| `claude-opus-5-5` | `claude-opus-5-5`, version `2` | Anthropic Messages | 40,000 | 40 |

These are deployed allocations. `Kimi-K3.1-Pro` uses all 100 units of its
approved East US 2 quota as verified on November 20, 2026. Capacity increases
do not raise a model's context window or guarantee that a large VS Code agent
request fits within its per-minute budget.

`model-router`, `gpt-chat-latest`, and `claude-opus-5-5-fast` were retired
from both the East US 2 Foundry account and its dedicated gateway.

Use the gateway hostname returned by Azure or the gateway Terraform output,
not a hostname inferred from the resource name. The current operation URLs
are:

```text
https://aigw-us-c2-jcr733hpvms4w.eastus2-01.ai.gateway.azure.com/default/models/openai/v1/chat/completions
https://aigw-us-c2-jcr733hpvms4w.eastus2-01.ai.gateway.azure.com/default/models/openai/v1/responses
https://aigw-us-c2-jcr733hpvms4w.eastus2-01.ai.gateway.azure.com/default/models/anthropic/v1/messages
```

Send a gateway runtime key as `Authorization: Bearer <key>`. Claude requests
also require `anthropic-version: 2023-06-01`. These are gateway credentials,
not Foundry keys or APIM subscription keys. Store them in an approved secret
store and never commit or print them.

### DeepSeek throughput and context

The DeepSeek deployment currently has Global Standard capacity 250, with
250,000 tokens and 250 requests per minute. Its published model limits are a
1,000,000-token context window and 384,000 output tokens; these are distinct
from the per-minute quota. See the
[DeepSeek model specifications](https://learn.microsoft.com/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure#deepseek).
Long histories and tool definitions are resent on each turn and can exhaust
the token rate even when replies are short. On a 429, honor the server's
retry delay, reduce or compact history, or wait before retrying. Sustained
larger workloads require a quota increase and a reviewed capacity change.

### Kimi throughput and context

The local VS Code **AI Gateway (Entra ID)** provider now selects
`Kimi-K3.1-Pro`. Its 100 units use the model-specific Moonshot quota, not the
shared Fireworks pool. The previous Azure alias remains available as a
fallback. `gpt-6-astra` remains the Astra entry because the target Foundry
account does not yet list `gpt-6.2-astra`.

The legacy Fireworks Kimi Global Standard capacity is 500, with **500,000 tokens and 500 requests
per minute**, increased from 10,000 TPM and 10 RPM. This uses the full approved
`AIServices.GlobalStandard.Fireworks` quota in East US 2, verified on
November 12, 2026; no shared Fireworks quota remains for another deployment.
It remains pay-per-token, without a provisioned-capacity commitment.

The model's 1,000,000-token context window is separate from this per-minute
rate budget. VS Code resends history, instructions, and tool definitions, so
large chats or concurrent requests can still exhaust it. Compact or start a
new chat when needed, and honor the backend retry delay instead of retrying
immediately. A higher rate requires an approved Fireworks quota increase.

## VS Code

The local **AI Gateway (Entra ID)** provider offers `claude-opus-5-5`,
`FW-DeepSeek-V4.1-Flash`, `Kimi-K3.1-Pro`, and `gpt-6-astra`. Run
**Developer: Reload Window** after a provider update to refresh the picker.
For a separate Custom Endpoint model group, keep the gateway runtime key
in VS Code's secure API-key input and configure the
model-level request header with the secure input reference:

```json
"requestHeaders": {
  "Authorization": "Bearer ${apiKey}"
}
```

Claude models additionally use `"apiType": "messages"`, the Anthropic URL,
and `"anthropic-version": "2023-06-01"` in their request headers. A gateway
authentication error mentioning a missing Entra token or `Data.All` can also
mean an invalid gateway key; it does not by itself indicate that Foundry
local keys should be enabled. Check the client credential and retry a new chat.

## Terraform roots and ownership

- [US foundation](terraform/us-foundation/README.md) manages the Foundry
  account, project, deployments, VNet, subnets, private endpoint, and DNS.
  The existing resource group is not owned by this root.
- [US AI Gateway](terraform/us-ai-gateway/README.md) has independent state
  and manages the dedicated gateway, identity assignment, model registrations,
  aliases, and runtime-key resource. It reads nonsecret connection metadata
  from the local foundation state.

Restrict access to both Terraform state files: the foundation state can
contain Anthropic Marketplace attestation information, and a remote-state
reader can access its complete snapshot. The gateway root does not retrieve
or intentionally store the runtime key. Review plans, quota, pricing, RBAC,
and network changes before applying either root.

The older [APIM foundation](terraform/apim-only/README.md),
[APIM AI Gateway](terraform/apim-ai-gateway/README.md), and
[AI Gateway](manualsteps-apimv2-foundry.md) and
[Standard v2](manualsteps-apimv2-standard.md) portal runbooks describe the
deleted Sweden-era deployment and are retained for historical reference.
Their Terraform state is not the active deployment; do not apply those roots
to manage the new US resources. The former Entra application remains outside
the deleted resource group.

## Customer/model token-usage dashboards

The independent [token-observability root](terraform/token-observability/README.md)
creates Log Analytics, workspace-based Application Insights, and Azure Managed
Grafana in `rg-law`. It imports the Downloads CSV examples into the standard
`AppRequests` and `AppMetrics` tables and provides customer/model token views.
The examples are not a live feed from the AI Gateway; the guide documents
token mappings, missing-sample coverage, costs, and repeatable setup.

## Retained legacy definitions

The original [terraform root](terraform) still contains chat1, chat2,
LiteLLM, and MLflow definitions for later use. They are not part of the active
isolated state and were not deployed. The standalone
[LiteLLM](standalone-litellm) and [MLflow](standalone-mlflow) packages remain
unchanged.
