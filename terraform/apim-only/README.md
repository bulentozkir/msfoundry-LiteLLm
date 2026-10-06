# App3 + APIM AI Gateway + Microsoft Foundry

This isolated Terraform root deploys only:

- chat-client3 on Azure App Service
- API Management in the `AIGateway` preview pricing tier
- one Microsoft Foundry account with `Gpt5.4mini`, `Phi`, and
  `FW-DeepSeek-V4.1-Flash` deployments
- ten additional per-user DeepSeek deployments in the same account
- managed-identity access from AI Gateway to Foundry
- separate AI Gateway runtime keys for app3, OpenCode, and Zed
- a DeepSeek cost-limit policy whose current per-key allocations total $200 per
  calendar month

The DeepSeek deployment name maps to the current generally available Foundry
catalog model `DeepSeek-V4-Flash` version `2026-04-23` through the
`FW-DeepSeek-V4.1-Flash` Global Standard deployment. Its capacity is 250, which
currently maps to 250 requests and 250,000 tokens per minute. This uses the current
regional Global Standard quota for this model; sustained traffic above this limit
requires an approved quota increase. Azure Front Door,
LiteLLM, MLflow, chat1, and chat2 are not part of this Terraform state.

## Per-user DeepSeek deployments

The `azurerm_cognitive_deployment.deepseek_user` resource creates
`user1-FW-DeepSeek-V4.1-Flash` through `user10-FW-DeepSeek-V4.1-Flash` in the
existing Foundry account. Each uses the same `DeepSeek-V4-Flash` catalog model,
version `2026-04-23`, with automatic version upgrades disabled.

| Setting | Default |
| --- | --- |
| `deepseek_user_count` | 10 |
| `deepseek_user_capacity` | 25 units per deployment |
| SKU | `DataZoneStandard` |
| Per-deployment throughput | 25,000 TPM and 25 RPM |
| Total Data Zone Standard quota allocation | 250,000 TPM |

This uses the separate Data Zone Standard quota; the original Global Standard
deployment retains its 250,000 TPM allocation. Increasing the count or capacity
requires sufficient unallocated regional quota. A 25,000 TPM limit can still
throttle large agent prompts.

The `deepseek_user_deployments` Terraform output maps each user ID to its
deployment name. Filter Foundry's `Input Tokens`, `Output Tokens`, or
`Total Tokens` metrics by `ModelDeploymentName` to view each deployment's usage.
Names alone do not enforce user access: no user identities, RBAC assignments,
or individual API keys are created. Direct Foundry access still requires an
authorized Microsoft Entra identity because Azure Policy disables key access.

These deployments are not added to APIM's model registry or aliases. The existing
APIM routes and monthly budget policy are unchanged, and that policy does not
cover direct calls to the new deployments. Publishing them through APIM with
per-user authentication and budgets is a separate configuration step.

## Deployed endpoints

- App3: <https://foundry-chat3-8ps1sz.azurewebsites.net>
- AI Gateway OpenAI base URL:
  <https://aigw-foundry-8ps1sz.azure-api.net/default/models/openai/v1>
- AI Gateway portal: <https://ai.gateway.azure.com>

## OpenCode

OpenCode is installed globally on Windows. Its user configuration is stored at
`~/.config/opencode/opencode.json`, and its dedicated runtime key is stored at
`~/.secrets/apim-aigateway-opencode-key` with inherited ACLs disabled. The
secret is not stored in this repository.

Run OpenCode from any project with:

```powershell
opencode
```

The default model is `apim-aigateway/FW-DeepSeek-V4.1-Flash`.

## Zed

Zed 1.20.2 is installed from the official Windows winget package. Its user
settings are at `%APPDATA%\Zed\settings.json`, with provider ID `azure-apim`
and default model `FW-DeepSeek-V4.1-Flash`. The dedicated runtime key is stored
in the user-scoped `AZURE_APIM_API_KEY` environment variable and is not written
to the settings file or repository.

## DeepSeek monthly budget

The AI Gateway preview cost-limit policy counts spend per caller identity, not
as one shared counter. Terraform partitions `deepseek_monthly_budget_usd`
across the current runtime keys: 33.4% for app3, 33.3% for OpenCode, and 33.3%
for Zed. The default for unallocated keys is effectively zero. Cost is
estimated by the gateway from reported token categories and public model
pricing; concurrent requests can briefly overshoot a limit.
