# LiteLLM on Container Apps + Chat App2

Status: Validated

## PostgreSQL and Managed Redis increment - 2026-09-21

The user explicitly requested the smallest PostgreSQL Flexible Server and Azure
Managed Redis added to the active LiteLLM Terraform root, to enable admin login.
Use only `terraform/litellm-app2` in the existing subscription, group, and region.

- PostgreSQL 16: `B_Standard_B1ms`, 1 vCore / 2 GiB, 32 GiB storage, seven-day
  backups, no HA/autogrow, database `litellm`.
- Azure Managed Redis: `Balanced_B0`, 0.5 GB, HA disabled, encrypted nonclustered
  database with `NoEviction`.
- Use the existing LiteLLM managed identity for both services; disable database
  passwords and Redis access keys. Add no subscription-wide permissions.
- Preserve the existing proxy hostname, image, master key, model routes, F1 plan,
  Foundry settings, APIM, and app2. No replacements or deletes are permitted.
- Existing Container Apps has no VNet. Use public datastore endpoints with TLS
  and Entra authentication. PostgreSQL has 161 exact egress-IP firewall rules;
  Managed Redis offers no IP firewall. Private endpoints require a separate
  approved network migration and are not part of this increment.
- Add a stable encryption salt, enable startup schema migrations with fail-fast
  checks, limit the DB pool to five, and use Redis for auth/router state with
  response caching opt-in. Do not persist chat prompts/responses in spend logs.
- Both datastores incur continuous service charges independently of proxy scaling.

Validation checklist for this increment:

- [x] Confirm regional minimum PostgreSQL SKU/storage and Managed Redis support.
- [x] Verify the pinned LiteLLM version supports both managed-identity auth paths.
- [x] Register PostgreSQL provider; Redis provider already registered.
- [x] Validate Terraform and match the local firewall list to live egress addresses.
- [x] Review a saved plan for only datastore/access additions and a proxy update.
- [x] Verify static datastore permissions and preserve existing proxy-key value.
- [ ] Deploy and verify database, Redis, schema migration, admin login, and models.

This increment supersedes the no-database architecture described below. The
following DeepSeek and initial-provisioning sections retain their historical proof.

## DeepSeek chat increment - 2026-09-21

The user requested DeepSeek in LiteLLM and chat app2. The existing proxy already
advertises `FW-DeepSeek-V4.1-Flash` and returned HTTP 200 with
`DEEPSEEK_APP2_READY` using app2's non-streaming request and 4,096-token output
allowance. No proxy configuration or infrastructure change is needed.

This increment publishes app2 code only to the existing
`foundry-chat2-8ps1sz` App Service using Microsoft Entra ZIP deployment. It adds
`/chatdeepseek`, independent `DeepSeekConversation` session history, a navigation
link, and bundled `Mlflow:DeepSeekModel` configuration. Mini and Phi keep their
routes, settings, and history keys. The original provisioning recipe and proof
below remain as historical context; no Terraform apply is part of this update.

Increment validation checklist:

- [x] Existing HTTPS-only target confirmed in the original subscription/group.
- [x] LiteLLM model listing and DeepSeek completion verified.
- [x] App2 Release build and publish passed with `--no-restore`; ZIP is 5,448,730 bytes.
- [x] Local route renders with the correct model and active navigation link.
- [x] Desktop/mobile navigation checked at 1440px, 390px, and 320px, with no overflow.
- [x] No changes to RBAC, Azure Policy, secrets, container image, model capacity,
  App Service plan, or APIM; infrastructure what-if/plan is not applicable.
- [ ] Live browser chat, session isolation, clear action, and existing-page checks.

Deployment validation workflow must be completed before publishing. Runtime
verification is performed against the deployed page after the ZIP update.

## 1. Current scope and authorization

On 2026-09-21, the user requested LiteLLM on Azure Container Apps and a live
chat app2 test URL. Deployment proceeds in subscription
`fb7dfa70-78b9-4e56-8d2d-fa2eff765241`, resource group
`rg-foundry-aigateway-sweden`, Sweden Central. The confirmation response
authorized autonomous decisions using the presented test configuration.

Use the isolated `terraform/litellm-app2` root and state. Do not apply the legacy
`terraform` root or the `terraform/apim-only` root. Existing app3, APIM, Foundry,
and the ten completed per-user DeepSeek deployments remain unchanged.

## 2. Current architecture

`chat-client2 -> LiteLLM Container App -> existing Foundry deployments`

- Container Apps Consumption environment and LiteLLM v1.101.0, pinned by digest.
- LiteLLM: 1 vCPU, 2 GiB, one worker, 0-1 replicas, TLS ingress, master-key auth.
- User-assigned managed identity with Foundry User at the existing account scope.
- Log Analytics: 30-day retention, 0.1 GB daily ingestion cap.
- App2: .NET 10 on the existing F1 Linux App Service plan, with always-on disabled.
- No database, Redis, ACR, paid App Service upgrade, or Foundry API keys.
- Proxy aliases: `gpt-5.4-mini`, `phi-4`, and `FW-DeepSeek-V4.1-Flash`.
- App2 retains its existing `Mlflow:*` configuration names for API compatibility,
  but sends Bearer-authenticated OpenAI requests to LiteLLM, not MLflow.

This is a no-sign-in test app. Container Apps compute, log ingestion, and Foundry
token use incur usage charges. Direct LiteLLM-to-Foundry calls are not covered by
the separate APIM monthly budget. Database-backed LiteLLM users, virtual keys,
and persistent spend tracking are not included.

## 3. Current recipe

recipe.type: terraform

1. Initialize, format, and validate `terraform/litellm-app2`.
2. Build and publish `chat-client2` without restoring from unapproved feeds.
3. Save and inspect a full plan; require creates only and read-only references
   to the existing resource group, Foundry account, and F1 plan.
4. Apply the reviewed plan from this root only.
5. Publish app2 using Azure CLI Entra-authenticated ZIP deployment.
6. Verify Container Apps health, proxy authentication, model responses, scoped
   managed-identity role, and browser chat submissions.

## 4. Current security and cost boundaries

- Keep Foundry local authentication disabled and comply with inherited policy.
- Keep SCM/FTP basic authentication disabled; no secrets in source or logs.
- Preserve the existing App Service plan's free SKU and all APIM resources.
- Bound LiteLLM to one process and at most one replica; retain scale-to-zero.
- No local Docker execution is possible: the resolved Windows `docker` file is
  empty, and Docker Desktop and Podman are absent. The official image manifest
  is verified; container runtime validation must be performed in Azure.

## 5. Current validation checklist

- [x] All validation checks pass
  - [x] Terraform and Azure CLI installed; authenticated subscription verified.
  - [x] Terraform initialization, formatting, and validation pass.
  - [x] Saved plan contains only the intended new resources, no updates/deletes.
  - [x] Local backend initialized; state is initially absent for this new root.
  - [x] No unresolved template variables exist.
  - [x] App2 Release build and publish succeed.
  - [x] Static RBAC review confirms only account-scoped Foundry User for LiteLLM.

## 6. Current recovery

On failure, inspect and repair only this new root. Do not delete or recreate
Foundry, APIM, app3, the shared App Service plan, or model deployments. Re-publish
app2 independently if its code deployment fails. Never print secrets or full
Terraform state when diagnosing failures.

## 7. Current validation proof

Persistence increment verified on 2026-09-21:

- Sweden Central capabilities advertise PostgreSQL `Standard_B1ms` (1 vCore,
  2,048 MiB RAM) and minimum storage 32,768 MiB. The chosen Terraform SKU is
  `B_Standard_B1ms`. Redis Enterprise/Managed Redis supports Sweden Central;
  the chosen documented minimum SKU is `Balanced_B0` with HA disabled.
- Both resource providers are registered. No PostgreSQL server exists in this
  subscription to reuse. Existing environment has no VNet integration.
- `terraform fmt -check`, `terraform validate`, and state access passed. The
  local firewall input has exactly 161 unique addresses matching live egress.
- Full saved-plan JSON inspection passed: 167 creates, one in-place LiteLLM
  update, zero deletes/replacements. The 161 firewall objects each permit a
  single known egress address, never `0.0.0.0` or an address range.
- Plan checks enforce B1ms/32 GiB, seven-day backups, Entra-only PostgreSQL,
  non-HA B0 with TLS and Redis keys disabled. The existing LiteLLM identity is
  granted only datastore-local access: Entra administrator on the dedicated
  PostgreSQL server for migrations and an access-policy assignment on this cache.
- The existing proxy-key secret value compares equal before and after the
  planned change. No app2, APIM, model, host-plan, or Foundry edits are planned.
- Verified the pinned v1.101.0 source's `AZURE_POSTGRESQL_AUTH` connection setup
  and `REDIS_AZURE_AD_TOKEN` sync/async token refresh implementation. No image or
  application build change is required; runtime connectivity is a post-deploy gate.

DeepSeek code-only increment verified on 2026-09-21:

- Existing LiteLLM `/v1/models` advertises `FW-DeepSeek-V4.1-Flash`; a
  `/chat/completions` request with `max_completion_tokens=4096` returned HTTP 200
  and `DEEPSEEK_APP2_READY`.
- App2 `dotnet build` and `dotnet publish --configuration Release --no-restore`
  passed; bundled settings specify the same deployment alias. No new packages.
- Local `/chatdeepseek` renders the shared Razor chat with a third navigation
  link; Playwright checks passed at 1440px, 390px, and 320px. Mobile screenshot
  confirms the model badge, navigation, and composer fit their containers.
- Live target lookup confirms `foundry-chat2-8ps1sz` is Running and HTTPS-only
  on the existing plan. This increment has no infrastructure or role edits.

Verified on 2026-09-21:

- `az account show` confirmed the enabled target subscription and tenant.
- Live inventory confirmed no existing LiteLLM, MLflow, Container Apps environment,
  or app2 in the target subscription, and the existing app3 host uses F1.
- `Microsoft.App` resource provider is registered.
- Official `ghcr.io/berriai/litellm:v1.101.0` manifest returned HTTP 200 with digest
  `sha256:d295634e09c648dcdb72c4cc2dd226f5fb87823a73e88cbbed6f205e4deb044b`.
- `terraform -chdir=terraform/litellm-app2 init`, `fmt -check`, and `validate`
  passed with AzureRM 5.6.0 and Random 3.9.1. Template-variable scan passed.
- The bundled PowerShell preflight helper was run but its `Invoke-Tf` function
  incorrectly uses PowerShell's automatic `Args` variable, forwarding no
  subcommand. All actual Terraform checks were executed directly instead.
- Saved plan JSON was checked: exactly seven creates (six Azure resources and
  one random password), no updates, deletes, or replacements. Existing resources
  are data sources only. Live hosting-plan lookup verified F1.
- Static RBAC verification passed: user-assigned identity receives only
  `Foundry User` (`53ca6127-db72-4b80-b1b0-d745d6d5456d`) at the existing
  `fdry-aigw-8ps1sz` account scope. No Contributor or subscription-scoped grants.
- App2 HTTPS-only, FTP/SCM basic auth disabled, always-on disabled, and the
  LiteLLM 1 vCPU / 2 GiB / 0-1 replica settings were checked in the saved plan.
- `dotnet build` and `dotnet publish` of `chat-client2/ChatClient2.csproj` in
  Release mode with `--no-restore` passed. ZIP artifact: 5,445,439 bytes.
- No local container execution was possible because Docker/Podman are absent.
  Azure runtime and browser validation remain required after provisioning.

## 8. Current deployment result

Deployed and verified on 2026-09-21:

- Applied the reviewed isolated plan: 7 added, 0 changed, 0 destroyed.
- LiteLLM Container App is `Succeeded` and `Running`; the latest revision is
  also the latest ready revision.
- Readiness returned HTTP 200. Anonymous inference returned HTTP 401.
- Authenticated Mini, Phi, and DeepSeek calls each returned HTTP 200 and
  `LITELLM_READY`, confirming managed-identity access to Foundry.
- Live RBAC verification confirmed exactly one account-scoped Foundry User role
  for the LiteLLM identity.
- Published the Release ZIP with Entra authentication; app2 is Running and
  HTTPS-only, with no publishing passwords enabled.
- Browser submissions through `/chat2` and `/chatphi` produced model replies.
  Switching between the pages retained separate conversation histories.
- Post-publication Terraform plan reports no changes in `terraform/litellm-app2`.
- Mini chat: <https://foundry-chat2-8ps1sz.azurewebsites.net/chat2>
- Phi chat: <https://foundry-chat2-8ps1sz.azurewebsites.net/chatphi>
- Protected LiteLLM proxy:
  <https://ca-litellm-8ps1sz.livelypebble-18eb5748.swedencentral.azurecontainerapps.io>
- Existing APIM, app3, Foundry authentication, and model allocations are unchanged.

---

# Historical: App3 + APIM AI Gateway + Microsoft Foundry

Status: Deployed (historical)

## 1. Scope and authorization

Deploy now, as explicitly requested by the user, into the only enabled
subscription in Microsoft Entra tenant `16b3c013-d300-468d-ac64-7eda0820b6d3`:
`MCAPS-Hybrid-REQ-145403-2026-bulento`
(`fb7dfa70-78b9-4e56-8d2d-fa2eff765241`). The region is Sweden Central.

Deploy only app3, API Management in the `AIGateway` preview pricing tier, and
Microsoft Foundry with three gateway model aliases. Do not deploy the legacy chat1,
chat2, LiteLLM, or MLflow resources. Their Terraform definitions remain in the
legacy root, but this deployment uses the isolated `terraform/apim-only` root
and state. Azure Front Door resources were removed from source and are not part
of the new architecture.

## 2. Architecture

`app3 -> APIM AI Gateway -> Microsoft Foundry`

- App3: Linux App Service, .NET 10, direct HTTPS endpoint.
- API Management: `AIGateway` preview SKU, capacity 1, system-assigned identity.
- Foundry: one `AIServices` account with local key authentication disabled.
- Gateway-to-Foundry authentication: managed identity with account-scoped
  Foundry User role (`53ca6127-db72-4b80-b1b0-d745d6d5456d`).
- Client authentication: separate gateway runtime access keys for app3,
  OpenCode, and Zed. Keys remain sensitive and are not committed.

Model deployments:

| Gateway/deployment name | Foundry catalog model | Version | SKU | Capacity |
| --- | --- | --- | --- | --- |
| `FW-DeepSeek-V4.1-Flash` | `DeepSeek-V4-Flash` | `2026-04-23` | `GlobalStandard` | 200 |
| `Phi` | `Phi-4` | `7` | `GlobalStandard` | 1 |
| `Gpt5.4mini` | `gpt-5.4-mini` | `2026-03-17` | `GlobalStandard` | 1 |

The requested DeepSeek deployment name is retained. The live Sweden Central
catalog has no distinct `DeepSeek-V4.1-Flash` model ID; it maps to the current
generally available `DeepSeek-V4-Flash` catalog model.

The previously added Data Zone backend was deleted outside Terraform. The
configuration adopts that change and routes the alias to the surviving
`FW-DeepSeek-V4.1-Flash` Global Standard deployment.

The DeepSeek model has a native AI Gateway `costLimit` policy with a calendar
month renewal. Because the preview policy counts per caller identity, the
combined $200 budget is partitioned across the current keys: app3 $66.80,
OpenCode $66.60, and Zed $66.60. Unallocated keys have a near-zero default.

## 3. Recipe

recipe.type: terraform

1. Validate the isolated root and app3 Release build.
2. Run a saved Terraform plan in `terraform/apim-only` and inspect its JSON.
3. Reject any delete or replacement action. The target subscription was
   confirmed empty for the relevant resource types before planning.
4. Apply only the freshly saved plan from the isolated root.
5. Publish the app3 Release artifact with Azure CLI Entra authentication.
6. Store client credentials outside the repository and configure OpenCode and
  Zed with their dedicated runtime keys.
7. Verify all three gateway model routes, app3, OpenCode, Zed, and the monthly
  DeepSeek cost policy.

## 4. Security and operational gates

- Never print runtime keys, access tokens, Terraform state, or app settings.
- Keep Foundry local authentication disabled; use managed identity only.
- Use one gateway runtime key per client and store local credentials outside
  the repository.
- Do not run plan or apply in the legacy `terraform` root.
- Do not target or mutate resources in the former Contoso subscription
  `44d3e5d8-23bc-4517-a680-f2d6359dd516`.
- The AI Gateway tier is public preview with no SLA.

## 5. Validation checklist

- [x] All validation checks pass
  - [x] `terraform fmt -check` passes in `terraform/apim-only`.
  - [x] `terraform validate` passes in `terraform/apim-only`.
  - [x] App3 Release build passes with no errors.
  - [x] Sweden Central catalog and quota support all three selected models.
  - [x] The subscription advertises APIM SKU `AIGateway` in Sweden Central.
  - [x] Saved plan is complete, applyable, not errored, and contains no deletes
        or replacements.
  - [x] Static RBAC review confirms only Foundry User at the Foundry account
        scope for the gateway identity.

## 6. Recovery

The isolated state contains no legacy resources. If provisioning fails, repair
only `terraform/apim-only` and generate a fresh plan. Do not apply the legacy
root. If app publication fails, infrastructure remains available and the app
artifact can be republished without reprovisioning. Revoke either runtime key
independently if it is exposed.

## 7. Validation proof

Validated on 2026-09-18:

- Azure CLI context: subscription
  `fb7dfa70-78b9-4e56-8d2d-fa2eff765241`, tenant
  `16b3c013-d300-468d-ac64-7eda0820b6d3`.
- Azure Resource Graph returned zero existing Foundry, API Management, or App
  Service resources in the target subscription.
- APIM SKU discovery using management API `2026-05-01-preview` returned
  `AIGateway`, capacity 1-10, with unrestricted Sweden Central availability.
- `az cognitiveservices model list --location swedencentral` confirmed:
  `DeepSeek-V4-Flash` `2026-04-23` (GA), `Phi-4` v7 (GA), and
  `gpt-5.4-mini` `2026-03-17` (GA), all with `GlobalStandard` support.
- `az cognitiveservices usage list --location swedencentral` confirmed unused
  quota: DeepSeek 250, Phi 1000, GPT-5.4-mini 1000. DeepSeek requests capacity
  50; the Phi and GPT-5.4-mini deployments each request capacity 1.
- `terraform fmt -check` and `terraform validate` in `terraform/apim-only`
  completed with exit 0 using Terraform 1.15.8, AzAPI 2.12.0, and AzureRM
  5.6.0.
- `dotnet build chat-client3/ChatClient3.csproj --configuration Release
  --no-restore` completed with exit 0, zero warnings, and zero errors after the
  DeepSeek route and AI Gateway header changes.
- Saved plan `tfplan-apim-only` completed with exit 0. Machine inspection:
  format 1.2, complete=true, errored=false, applyable=true, 22 creates, zero
  changes, zero deletes, zero replacements, and no populated diagnostics.
- Legacy Terraform validation completed with exit 0 after deleting
  `frontdoor.tf` and removing all source references to its resources.

Capacity remediation validation on 2026-09-18:

- The live DeepSeek deployment reported limits of one request and 1,000 tokens
  per 60 seconds at capacity 1. The Global Standard quota reported 1 of 250
  capacity units allocated in Sweden Central.
- The Terraform preflight completed with exit 0, including initialization,
  formatting, validation, planning, state access, and template checks.
- Saved plan `tfplan-zed-rate-limit` is complete, applyable, not errored, and
  has zero diagnostics. It contains one in-place update: DeepSeek capacity
  1 to 50, with zero creates, deletes, or replacements.
- `dotnet build chat-client3/ChatClient3.csproj --configuration Release
  --no-restore` completed with exit 0, zero warnings, and zero errors.
- Static RBAC review remains verified: the capacity update introduces no new
  identities, roles, or scope changes.

Budget and capacity increase validation on 2026-09-18:

- Global Standard DeepSeek quota reported 50 of 250 capacity units allocated
  before the change, leaving enough quota for capacity 200.
- `terraform fmt -check` and `terraform validate` completed successfully.
- Saved plan `tfplan-deepseek-200` is complete, applyable, not errored, and has
  zero diagnostics. It contains two in-place updates: DeepSeek capacity 50 to
  200 and monthly cost-limit allocations totaling $100 to $200, with zero
  creates, deletes, or replacements.
- The bundled Windows preflight wrapper passed CLI and authentication checks
  but forwarded no Terraform subcommand. The equivalent deterministic checks
  were run directly and passed: initialization, formatting, validation,
  planning, state access (24 resources), and template-variable scanning.
- `dotnet build chat-client3/ChatClient3.csproj --configuration Release
  --no-restore` completed with exit 0, zero warnings, and zero errors.
- Static RBAC review remains verified: neither update changes identities,
  roles, or scopes.

### Role assignment verification

- Status: Verified.
- Identity: APIM AI Gateway system-assigned service principal.
- Role: Foundry User
  (`53ca6127-db72-4b80-b1b0-d745d6d5456d`).
- Scope: the individual Foundry account only.
- Issues: none; no broad Contributor, resource-group, or subscription role is
  assigned.

## 8. Deployment result

Deployed and verified on 2026-09-18:

- Increased `FW-DeepSeek-V4.1-Flash` Global Standard capacity from 50 to 200
  and its monthly cost-limit allocations from $100 to $200 in place: 0
  resources added, 2 changed, and 0 destroyed.
- The live deployment reports 200 requests and 200,000 tokens per 60 seconds.
  Zed and OpenCode authenticated requests returned HTTP 200 with matching rate
  headers and the AI Gateway monthly-cost header.
- The `deepseek-monthly-budget` policy is a calendar-month `costLimit` with
  identity allocations of app3 $66.80, OpenCode $66.60, and Zed $66.60,
  totaling exactly $200.
- Post-deployment Terraform planning reports no changes. Live RBAC verification
  confirms the gateway service principal still has exactly the Foundry User
  role at the individual Foundry account scope.
- Registered `Microsoft.ApiManagement` in the target subscription, then applied
  the audited isolated plan: 22 added, 0 changed, 0 destroyed.
- API Management `aigw-foundry-8ps1sz` is `Succeeded` in Sweden Central with
  SKU `AIGateway`.
- Foundry account `fdry-aigw-8ps1sz` is serving the requested aliases:
  `FW-DeepSeek-V4.1-Flash`, `Phi`, and `Gpt5.4mini`.
- The externally deleted Data Zone backend was adopted rather than recreated;
  the gateway alias now points to the surviving Global Standard deployment.
- Published chat-client3 with Azure CLI Entra authentication. Deployment status:
  `RuntimeSuccessful`, 1/1 instance successful.
- App3: <https://foundry-chat3-8ps1sz.azurewebsites.net>
- AI Gateway OpenAI base URL:
  <https://aigw-foundry-8ps1sz.azure-api.net/default/models/openai/v1>
- Live gateway calls returned HTTP 200 with text for all three aliases.
- Browser submission to `/chat3deepseek` returned exactly `APP3_READY` through
  app3's dedicated runtime key.
- Live RBAC verification found exactly one account-scoped assignment for the
  gateway identity: Foundry User, principal type ServicePrincipal.
- Installed OpenCode 1.18.30 with npm. Global config:
  `~/.config/opencode/opencode.json`; user-only key file:
  `~/.secrets/apim-aigateway-opencode-key`. The key is not in the repository.
- `opencode run --pure --model
  apim-aigateway/FW-DeepSeek-V4.1-Flash ...` returned exactly
  `OPENCODE_READY` with exit 0.
- Installed Zed 1.20.2 from the official `ZedIndustries.Zed` winget package.
  Its nonsecret settings are at `%APPDATA%\Zed\settings.json`; the dedicated
  key is supplied through the user-scoped `AZURE_APIM_API_KEY` environment
  variable. A Bearer-authenticated request returned `ZED_READY` with HTTP 200.
- Applied the model-scoped `deepseek-monthly-budget` cost policy. Live
  verification returned type `costLimit`, period `month`, scope `resource`,
  counter key `identity`, and allocations totaling exactly $200. Governed
  requests return the `x-cost-per-month-consumed` response header.
- Removed the legacy Front Door file, all Terraform Front Door references, and
  the obsolete `Developer_1`/duplicate chat3 resources. Chat1, chat2, LiteLLM,
  and MLflow definitions remain in the legacy root.
- Final checks: both Terraform roots validate; active-root plan reports no
  changes; app source has no diagnostics.
