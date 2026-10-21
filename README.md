# Switchable APIM tiers with private Microsoft Foundry

Two separate Terraform roots support one active gateway in Sweden Central:
**AI Gateway preview** for the lower-cost test configuration, or **Standard v2**
when its API-scoped subscriptions and Entra access controls are required.

**Current test profile, verified 20 October 2026:** AI Gateway
[`aigw-test-8ps1sz`](https://portal.azure.com/#resource/subscriptions/fb7dfa70-78b9-4e56-8d2d-fa2eff765241/resourceGroups/rg-foundry-aigateway-sweden/providers/Microsoft.ApiManagement/service/aigw-test-8ps1sz/overview)
is active; the Standard v2 gateway is removed and disabled in its local
deployment settings. Both Terraform roots have no pending changes.

Internet/private clients reach the selected gateway, which uses the shared
VNet and Foundry private endpoint to invoke the same three model deployments.

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
- exactly three deployments: `Gpt5.4mini`, `Phi`, and `FW-DeepSeek-V4.1-Flash`
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

AI Gateway preview instead exposes
`/default/models/openai/v1/chat/completions` with a runtime key in `api-key`.
Every runtime key can invoke every published model; per-model subscriptions,
products, XML API policies, and the Entra-only entrypoints are not reproduced.
The existing Entra registration/assignments are retained for return to Standard.

Switching is a maintenance-window replacement, not an in-place SKU patch.
Disable and apply the active root's gateway setting before enabling the other
tier. Both roots check outbound-subnet occupancy. The same four /24 subnets
and three Foundry deployments are preserved; no extra subnet or second
permanent gateway is needed. Do not destroy the foundation root to change tiers.

In Standard v2, the AI Models and APIs portal pages manage the same underlying APIs. Terraform
associates the reserved `aimodel` tag with each model API so it appears in the
AI-focused view as well as the general APIs view. This metadata does not create
another Foundry deployment or replace subscription authorization.

The requested DeepSeek name maps to the GA Foundry catalog model
`DeepSeek-V4-Flash` version `2026-04-23`. No extra per-user model deployments or
application-specific cost policies are created.

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

## Retained legacy definitions

The original [terraform](terraform) root still contains chat1, chat2, LiteLLM,
and MLflow definitions for later use. They are not part of the active isolated
state and were not deployed. The Front Door resource file and all Terraform
references to it were removed.

The standalone packages also remain unchanged:

- [standalone-litellm](standalone-litellm)
- [standalone-mlflow](standalone-mlflow)