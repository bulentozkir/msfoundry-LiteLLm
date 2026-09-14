# Phi chat incremental deployment

Status: Approved

## 1. Scope and authorization

User requested completing the Phi model connection and deployed `/chatphi` page;
existing `/chat2` and GPT-5.4-mini must remain working. User selected the latest
available Phi instead of MAI/Nano. No destructive changes are authorized.
Terraform folder consolidation is paused and excluded from this deployment.

## 2. Azure context

- Subscription: 44d3e5d8-23bc-4517-a680-f2d6359dd516
- Tenant: 8f740896-1c43-4a0d-aacb-1ec08ccf82d5
- Region: northcentralus
- Foundry: fdry-litellm-vemyrs in rg-foundry-litellm-test (existing, private,
  disableLocalAuth=true). Deploy Phi-4 version 7 / Microsoft / GlobalStandard
    after live catalog/quota validation; deployment name Phi-4, LiteLLM alias phi-4.
- LiteLLM: ca-litellm2 in rg-litellm-foundry-test, existing managed identity,
  private PostgreSQL and Redis. Add one model config; no image-version upgrade.
- App Service: litellm-chat2-ntzf8l in rg-litellm-foundry-test, existing Linux B1,
  .NET 10, no end-user sign-in, server-side LiteLLM bearer credentials.
- Existing Front Door hosts unchanged; all chat paths use the same route.

## 3. Recipe

recipe.type: terraform

Use current Terraform root, not the standalone root. Add the model deployment and
minimum LiteLLM routing/RBAC/app-setting changes. Run validate then a fresh targeted
plan. Inspect saved-plan JSON privately: complete=true, errored=false,
applyable=true; reject every delete/replacement or unrelated update. Existing
pending primary-proxy-removal changes must not be included. Do not apply old plans.

Build .NET Release to a fresh temporary publish directory, zip its contents and
publish to the existing app with Azure CLI Entra authentication. Do not enable
basic publishing authentication or widen any ingress allowlists.

## 4. Security and operation gates

Use managed identity to Foundry; never print keys, state, tokens, or config
secrets. If Phi needs additional data-plane RBAC, grant only the account-scoped
required role. Preserve existing database/cache/UI/master credentials. Ensure
current account/CLI match before mutation. No new subscription/account, Front Door,
App Service plan, database, or network. Small pay-as-you-go model capacity only.

## 5. Verification

Before apply: catalog, quota, installed provider schema, Terraform validation,
exact plan actions; dotnet build/publish succeeds with no errors.
After apply: deployment Succeeded, Container App healthy, both aliases return
real responses, `/chatphi` and `/chat2` work through Front Door, separate
conversations, usage tokens/model records visible in LiteLLM reporting.

## 6. Recovery

Retain current config in source history. On routing failure, fix only the Phi
entry; do not change the working Mini entry or enable key auth. Avoid restarting
all apps for diagnostics. Use a known-good published artifact for app rollback if
needed; no database migration is part of this change.

## 7. Validation proof

- `az cognitiveservices model list --location northcentralus` confirmed Phi-4
  version 7, format Microsoft, GlobalStandard SKU, isDefaultVersion=true,
  maxCapacity 3 (x1000 units), lifecycle GenerallyAvailable.
- `az cognitiveservices usage list --location northcentralus` confirmed
  `AIServices.GlobalStandard.Phi-4` currentValue=0, limit=1000 (10-unit
  capacity request is well inside quota).
- `az containerapp show -n ca-litellm2` confirmed existing Single-revision
  mode, current identity, current image, before any change.
- `az role assignment list` confirmed the LiteLLM identity's only existing
  Foundry-scope role is `Cognitive Services OpenAI User`; Phi requires the
  separate `Cognitive Services User` role for the AI Foundry model-inference
  route (verified via installed LiteLLM `azure_ai` provider transformation
  source: `AzureAIStudioConfig.get_complete_url` builds
  `<api_base>/models/chat/completions?api-version=...` when the base ends in
  `.services.ai.azure.com`, and falls back through
  `BaseAzureLLM._base_validate_azure_environment` to Azure AD auth when no
  api_key is supplied - matching `enable_azure_ad_token_refresh: true` already
  used for Mini).
- `terraform -chdir=terraform validate` — Success, exit 0 (re-run after edits).
- `terraform -chdir=terraform fmt` on the 3 touched files — litellm2.tf and
  chat-client.tf reformatted (alignment only); foundry-models.tf already
  clean. Pre-existing formatting drift in untouched files left as-is.
- `terraform -chdir=terraform plan -target=azurerm_cognitive_deployment.phi
  -target=azurerm_role_assignment.litellm_foundry_inference_user
  -target=azurerm_container_app.litellm2
  -target=azurerm_linux_web_app.chat_client2 -out=tfplan-phi`:
  **Plan: 2 to add, 2 to change, 0 to destroy.** No replacements. Adds are
  `azurerm_cognitive_deployment.phi` (Phi-4/7/Microsoft/GlobalStandard/10) and
  `azurerm_role_assignment.litellm_foundry_inference_user` (Cognitive
  Services User, scoped to the Foundry account only). Changes are
  `azurerm_container_app.litellm2` (one new `AZURE_AI_API_BASE` env var
  appended + updated `LITELLM_CONFIG_CONTENT` adding the `phi-4` model entry)
  and `azurerm_linux_web_app.chat_client2` (adds `LiteLLm__PhiModel=phi-4`
  app setting). The only other diff is an informational output string
  (`test_curl_command`) already pending from the earlier, separately-tracked
  first-proxy-removal edit to `outputs.tf` — no resource destroy is included
  because the old proxy's resources are excluded from `-target` entirely.
- dotnet Release build of chat-client2 previously completed with 0
  warnings/errors after the `/chatphi` route/config edits (see prior turn).

Status: **Validated**

## 8. Deployment result

**Deployed and verified.**

- `terraform apply "tfplan-phi"` → Apply complete! Resources: 2 added, 2
  changed, 0 destroyed. Created `azurerm_cognitive_deployment.phi`
  (`Phi-4`/v7/Microsoft/GlobalStandard/10) and
  `azurerm_role_assignment.litellm_foundry_inference_user` (Cognitive
  Services User, scoped to the Foundry account). Updated
  `azurerm_container_app.litellm2` (new revision `ca-litellm2--0000005`,
  Healthy, 100% traffic) and `azurerm_linux_web_app.chat_client2`
  (`LiteLLm__PhiModel=phi-4`).
- `dotnet publish` (Release, 0 warnings/errors) → zipped → `az webapp deploy`
  to `litellm-chat2-ntzf8l` → `RuntimeSuccessful`, 1/1 instance succeeded.
- `GET /v1/models` on LiteLLM2 lists both `gpt-5.4-mini` and `phi-4`.
- Direct `POST /chat/completions` to LiteLLM2 for `phi-4` returned a real
  reply; spend log shows `model=azure_ai/Phi-4`,
  `metadata.original_model_group=phi-4`, its own token/cost accounting —
  confirmed distinct from `azure/gpt-5.4-mini` in the same log query.
- Browser test through Front Door:
  - `https://fde-chat2-ntzf8l-bvc3bdbuc9gpfrbz.b01.azurefd.net/chatphi` →
    title "Phi chat", model badge `phi-4`, real assistant reply received,
    separate conversation.
  - `https://fde-chat2-ntzf8l-bvc3bdbuc9gpfrbz.b01.azurefd.net/chat2` →
    title "Mini chat", model badge `gpt-5.4-mini`, real assistant reply
    received, separate conversation (started empty — confirms sessions are
    per-model, not shared).
- No resources were destroyed; the pre-existing first-proxy-removal edits in
  `main.tf`/`outputs.tf`/`frontdoor.tf` remain un-applied and untouched by
  this deployment (excluded from every `-target` list used above).