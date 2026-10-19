# APIM AI Gateway and three Foundry deployments

Status: Deployed

## Stage 9: additive Entra ID access - 2026-10-17

### Scope and decisions

- Modify only the active `terraform/apim-only` root in tenant
  `16b3c013-d300-468d-ac64-7eda0820b6d3`, subscription
  `fb7dfa70-78b9-4e56-8d2d-fa2eff765241`, Sweden Central.
- Preserve the existing three key-required API URLs, API-scoped subscriptions,
  keys, products, backend identity/RBAC, private networking, and model capacity.
- Add three Entra-only model entrypoints to the same Standard v2 gateway,
  reusing its existing Foundry backends. Do not create another gateway or model.
- Manage a single-tenant gateway API registration/service principal and three
  model-specific app roles in Terraform. Require the corresponding role as
  well as valid token signature, tenant, audience, and expiry at API scope.
- The user requested additive Entra authentication. The clarification form
  returned that the user is unavailable and instructed a pragmatic choice.
  Use the separate-entrypoint design already documented in the runbook.
- Create `apim-foundry-8ps1sz-model-access` as a single-tenant resource API,
  requesting v2 access tokens. Add `Model.Gpt.Invoke`, `Model.Phi.Invoke`, and
  `Model.DeepSeek.Invoke` roles for users/workloads; require enterprise-app
  assignment. Preauthorize only the existing Microsoft Azure CLI public client
  for a delegated `access_as_user` scope, while policies still require a model role.
- Use `/entra/<existing-model-api-id>/openai/v1/chat/completions` as the new
  token-only URLs. Mark these additional authentication entrypoints clearly in
  AI Models; there remain exactly three Foundry deployments and backends.
- Assign the three roles initially only to the current operating administrator,
  object ID `dd4b506a-30a0-4a28-9948-1da6b3731c5c`, for per-model verification.
  Record explicit assignments in an ignored, persistent Terraform values file.
  No other users, groups, or systems receive access implicitly.
- Add the AzureAD Terraform provider without upgrading existing providers.
  Reuse one policy template for the key and Entra APIs, preserving existing
  key-policy behavior and all model validation, CORS, MI, and streaming controls.
- Do not grant tenant-wide access, create client secrets, consent to unrelated
  APIs, change networking/capacity, or recreate any existing resource.
- Recipe: existing standalone Terraform workflow, workspace `default`, local
  state in `terraform/apim-only`; do not migrate state or introduce azd.
- Azure context was read live and matches the above subscription/tenant.
  No new regional service or model capacity is requested; this adds only
  child APIs/policies/tags plus tenant application objects.
- The deployment approval/context form also returned that the user is unavailable
  and instructed a pragmatic choice. Proceed additively in the existing context
  under the user's explicit request to configure Entra access.
- First assign only the GPT role to the operating administrator, obtain a real
  correctly signed gateway token, and verify Phi/DeepSeek reject it with 403.
  Then add the remaining two approved administrator model roles and verify all
  three positive paths. No extra verification client application is needed.

### Preparation, validation, deployment, and acceptance

- [x] Check current state, Entra permissions, provider schemas, and supported policies.
- [x] Implement registration, isolated entrypoints, role assignments, tests, and docs.
- [x] Validate configuration and focused regressions; review an additive saved plan.
- [x] Apply through the validated Terraform deployment workflow.
- [x] Verify valid Entra requests for all models, missing/invalid/wrong-role rejection,
      streaming, unchanged subscription access, and a no-change refreshed plan.

### Validation proof

All validation checks pass:

- [x] Run Terraform recipe preflight: installed tools, Azure CLI sign-in,
      initialization, formatting, validation, saved plan, state access,
      unresolved-template scan, and optional tfvars JSON syntax.
- [x] Run affected Terraform tests and parse the PowerShell integration scripts.
- [x] Inspect saved-plan actions and policy XML; existing keys, APIs, backend
      identities, models, and network resources must remain unchanged.
- [x] Confirm single-tenant token audience, separate per-model assignments,
      assignment-required service principal, and unchanged Foundry User scope.
- [x] Record current commands, timestamps, saved-plan hash, and results.

Preparation checks completed:

- Added AzureAD provider 3.10.0 with `terraform init`; existing provider versions
  were reused unchanged.
- `terraform validate -no-color`: success.
- Targeted `terraform test` for Entra, Standard v2, and private-gateway files:
  six runs passed, zero failed. Includes empty assignments, unknown models,
  invalid object IDs, fixed audiences/roles/routing, and unchanged key boundaries.
- PowerShell AST parsing passed for both integration suites and shared helpers.
- The VS Code test runner does not discover Terraform tests; the native
  Terraform runner above is the applicable validation.

### Stage 9 Section 7: Validation Proof

- Native preflight completed **2026-10-17 21:15:44 +03:00**:
  `terraform init -input=false -no-color`, `fmt -check -recursive`,
  `validate -no-color`, `plan -input=false -no-color -out=tfplan-entra-initial`,
  and `state list` all passed. The original state contains 62 managed resources;
  unresolved-template scan passed. No `main.tfvars.json` is present/applicable.
- The installed recipe preflight wrapper was attempted first but invoked
  Terraform without its arguments because its function parameter uses the
  automatic PowerShell `$Args` name. Its five usage errors are runner failures,
  not configuration failures. The explicit native commands above cover the
  same checks. The original historical `tfplan` was preserved and restored.
- Reviewed saved plan: **13 creates, 0 updates, 0 replacements, 0 destroys**.
  Every original key API/policy/subscription/product/backend, gateway, Foundry
  deployment, role assignment, and network resource is no-op.
- Plan SHA256:
  `035D9E204B679EB2DBA40A1B8485BEF975B6A02C2434AF2B13AB825BBCA65C3A`.
- Parameterized policy XML rendered by Terraform console parses for all three
  model formats. Tenant/audience, explicit 403 role gate, MI and streaming
  controls are present. The live audience is intentionally unknown until
  Entra creates the client ID and will be checked after apply.
- Infrastructure build verification is Terraform validation plus six passing
  mocked runs; there is no application build for this infrastructure-only change.
- Static role verification: the existing APIM system identity retains only
  account-scoped Foundry User; new app-role assignments target only the gateway
  enterprise application and explicitly listed principal/model pairs.
  An empty assignment map grants no access. No broad directory or Azure roles,
  client credentials, or consent to unrelated APIs are added.
- Logs: session files `apim-entra-preflight.log` (runner defect evidence) and
  `apim-entra-initial-plan.log` (successful native plan).

Live deployment and role-isolation proof are pending. Previous records below
are historical evidence, not validation of these new authentication changes.

### Stage 9 initial deployment and real token isolation

- Initial reviewed plan applied **2026-10-17 21:24:40 +03:00**:
  **13 added, 0 changed, 0 destroyed**.
- Resource application client ID:
  `67c1b092-ecd0-4322-9c9b-ec7cd69edeb6`.
- Application object ID: `6b623342-3fa0-4a2b-9cb7-80992c9746cf`;
  resource service principal: `5b5b0b5e-c50e-4fb4-ae7e-ec354df28a05`.
- `Test-EntraApim.ps1 -ExpectedRoles Model.Gpt.Invoke` passed at
  **2026-10-17 21:29:09 +03:00** using an actual Entra-issued v2 token with only
  the GPT role: GPT completion and SSE succeeded; Phi and DeepSeek returned
  403 on both operations, including when their own subscription key was supplied.
- Missing, malformed, ARM-audience and signature-tampered tokens returned 401;
  bearer-only requests to existing key APIs returned 401. GPT schema, route,
  routing-override and portal CORS checks passed.
- Live policy readback HTML-encodes its expression attributes; the inspection
  test normalizes those entities before comparing the role string. Actual
  runtime role-isolation tests above are the acceptance evidence.
- Next staged operation adds only the administrator's Phi and DeepSeek role
  assignments, as already planned; it does not change APIs, policies or keys.
- Final-role plan validated and reviewed **2026-10-17 21:32:54 +03:00**:
  **2 creates only**, both app-role assignments to the same administrator and
  resource service principal; all 75 current resources are no-op.
  `terraform validate` passed; saved plan `tfplan-entra-final-roles` SHA256:
  `CEA9FE8D385C68197976DCD42C9300FDFCDA2D884F224072DB3028FEC768F41C`.

### Stage 9 final deployment and acceptance

- Final administrator-role apply completed **2026-10-17 21:34:26 +03:00**:
  **2 added, 0 changed, 0 destroyed**, assigning only the Phi and DeepSeek
  roles to the same operating administrator. Together with the initial GPT
  role, exactly three model assignments exist; no other principal was granted
  access. The managed resource total is 77.
- The final Entra integration suite passed **53 checks**, and the unchanged
  subscription-key regression suite passed **109 checks**. Final combined
  verification was complete by **21:41:23 +03:00**.
- A refreshed Terraform plan completed at **21:40:17 +03:00** with no changes.
  A second refreshed plan during documentation verification completed at
  **22:25:55 +03:00**, again with no changes.
- Live directory and Foundry RBAC assertions passed at **21:45:21 +03:00**:
  single-tenant v2 resource API, exactly three model roles, no app passwords or
  certificates, enterprise-app assignment required, only the administrator's
  three app-role assignments, and unchanged account-scoped Foundry User access
  for APIM's system-assigned identity.
- The documented default CLI token-acquisition path was run end to end at
  **21:50:29 +03:00**; all **53 Entra checks** passed again.
- Original key URLs, keys, subscriptions, products, models/capacity, networking,
  and upstream managed-identity permissions are unchanged. There is no new
  gateway, model deployment, hosted application, or interactive portal OAuth UI.
- Proof logs are retained in the session files directory:
  `apim-entra-final-roles-apply.log`, `apim-entra-final-verification.log`,
  `apim-entra-key-regression.log`, `apim-entra-convergence.log`,
  `apim-entra-default-client-verification.log`, and
  `apim-entra-documentation-convergence.log`. No tokens or keys are printed.

### Stage 9 diagrams, portal guide, and executable samples

- Both Internet and intranet SVGs now show the unchanged API-scoped key path
  alongside the separate Entra token/role path. Each model row includes both
  API bases and its required role; both paths reuse the same private Foundry
  backend and APIM managed identity. Editable Excalidraw sources match the SVGs.
- Browser measurements passed for all 63 Internet and 66 intranet text labels:
  no maximum-width, canvas, or card-bound violations. Both diagrams contain
  all three model-role/Entra-route labels and no proposed/not-deployed labels.
- The portal manual retains the two diagrams at the top, ordered stages 1-15
  plus section 12A, and now includes the deployable Entra policy fragment,
  both endpoint maps, role assignment, negative tests, and troubleshooting.
- The user's later request explicitly reduced SAMPLES to exactly three
  Internet examples: basic subscription-key HTTPS, subscription-key SDK
  streaming, and Entra delegated-user authentication without a key.
- All three exact documented Python blocks parse with the Python 3.10 grammar.
  Fifteen focused executable tests passed, covering payloads, paths, credential
  headers, token scope, streaming, empty output, HTTP 401/403/429, connection
  failures, missing keys, and failed user-token acquisition.
- At **2026-10-17 23:01:33 +03:00**, the three unchanged documented samples
  each returned a real assistant answer through public APIM ingress. Client
  DNS was confirmed public. Requests were paced 65 seconds apart; sample 3
  used the existing assigned CLI user and sent no subscription key.
- Missing Azure Identity was installed only into a session-isolated validation
  virtual environment, not the repository or shared interpreter. No new
  application, identity, role assignment, or Azure resource was needed.
- Proof log: `apim-entra-manual-samples-verification.log` in the session files
  directory. Credentials remained in memory and were not printed or saved.

### Stage 9 final four-sample revision and cleanup

- The user's latest explicit request supersedes the earlier three-sample
  documentation revision. SAMPLES now contains exactly four standalone GPT
  examples, in this order: Internet/key, intranet VNet/key, Internet/Entra
  user, and intranet VNet/Entra user.
- Both network variants keep the normal gateway HTTPS hostname. Internet
  samples require public DNS. Intranet samples require the configured inbound
  APIM private endpoint IP and reject public, mixed, empty, or wrong-private-IP
  DNS results before reading a key or acquiring a user token.
- All four exact blocks parse with the Python 3.10 grammar and passed
  **20 focused executable tests**, including both private-path success cases
  using mocked DNS/HTTP, credential boundaries, required token scope, SSE,
  empty outputs, missing/invalid private IP settings, DNS failures, HTTP
  401/403/429, connection failures, missing keys, and failed token acquisition.
- The updated Internet samples **1 and 3** each returned a real assistant
  answer by **2026-10-17 23:23:27 +03:00**, including their new public-DNS
  checks. The current workstation resolves APIM publicly; the intranet
  samples were not claimed as live private-network tests. Their live execution
  requires an existing VNet-connected client with the documented private DNS
  and routing.
- Proof log: `apim-entra-four-manual-samples-verification.log`; the original
  three-sample log remains historical evidence for the superseded revision.
- Removed only the two fingerprint-verified, already-applied Stage 9 binary
  plans, the session-isolated sample-validation environment, and the two
  task-specific scratch scripts. Preserved the persistent ignored role
  assignment values, Terraform state, historical `tfplan`, and proof logs.
- No additional Azure resource, application, model, role assignment, or network
  change was made for either documentation revision.

### Stage 9 sample hardening and runbook portal audit

- Clean-environment sample runs (fresh venvs, packages installed in the manual's
  order) on Python 3.14.6 and 3.10.20 with `openai` 3.28.0 and `azure-identity`
  1.26.0: 66/66 checks each. All four samples returned real answers; samples 2
  and 4 used a simulated private path (in-process private DNS plus a local TCP
  relay), because no VNet client exists and none was deployed.
- A probe found that an `http://` `APIM_GATEWAY_URL` reached the gateway in
  plaintext. All four samples now refuse a non-HTTPS URL before any key or
  token is used (confirmed, using a dummy key only). Sample 1 also reports
  timeouts and resets cleanly. Proof logs stay in the session files directory.
- Per the user's instruction, code testing stopped after that point; no Terraform
  or Azure resource was changed.
- The runbook was audited against the live Azure Portal (tenant
  `fdpo.onmicrosoft.com`, read-only, no create/submit action taken) and the
  deployed configuration. Corrections: real Foundry and APIM creation-wizard
  tabs and labels (including that the Foundry wizard has no local-authentication
  setting and auto-creates a default project, and that APIM networking uses
  *Private link (inbound only)* and *Virtual network integration (outbound
  only)*); NSG rules matched to the deployed rules; Foundry **Networking**
  tabs (Network Injection is read-only after deployment); role-assignment
  wizard and the exact **Foundry User** role; Backends, API import/Settings,
  Products, Subscriptions and policy-editor field names; Entra app-role
  details; the `servers`/Web service URL contradiction for the Entra APIs;
  continuous section numbering 1-17 with matching cross-references.
- Observation (not changed): APIM contains an unmanaged backend
  `fdry-aigw-8ps1sz-ai-endpoint` and importer tags (Anthropic, Assistants,
  Audio, Chat Completions, Embeddings, Images, Responses, Vector-Stores) from an
  earlier portal Foundry import. No API references them. Foundry also has a
  user-created project `fdry-aigw-8ps1sz-project`, and its outbound subnet has
  an automatically generated NSG with no custom rules; none is Terraform-managed.
- Cleanup: removed only task-created venvs, scratch scripts, page-text dumps and
  the Python 3.10 added through `uv`; closed only the task-owned Edge windows
  and the "Login failed" tabs the unknown-resource test had opened.

## New Standard v2 APIM instance - 2026-10-16

The user clarified: create a NEW Standard v2 API Management instance publishing
the existing Foundry models through three API subscriptions, then delete the
obsolete AI Gateway preview instance. Preserve the tenant, subscription, resource
group, Sweden Central region, private Foundry account, exactly three model
deployments, trusted-services exception, and four unchanged /24 subnets.

### Assessment and proposed migration

The live source is `aigw-foundry-8ps1sz`, SKU AIGateway, provisioning Succeeded.
Its read-only available-SKUs endpoint returns only AIGateway; an in-place
StandardV2 SKU change is not available. Microsoft documents v2 services as new
instances. Standard v2 is supported in Sweden Central and supports both outbound
VNet integration and inbound private endpoints.

Propose `apim-foundry-8ps1sz`, StandardV2 capacity 1, in the same existing tenant,
subscription, resource group, and region. Public HTTPS remains enabled. Use its
system-assigned identity and an account-scoped Foundry User assignment to call
the existing private Foundry endpoint. Keep Foundry public/local authentication
disabled, trusted-services bypass AzureServices, all three existing deployments,
and their versions/capacities unchanged.

Expose three separate OpenAI-compatible chat-completion APIs with server-enforced
deployment targets and subscription-required authentication. Issue one
API-scoped subscription per model, not an all-APIs subscription. Reject missing
keys and cross-model subscription use. Never forward a client-provided backend
credential or let a model override escape the API's permitted deployment.
Use the standard `Ocp-Apim-Subscription-Key` client header.

Standard v2 requires a dedicated integration subnet that cannot be shared with
the existing gateway. The clarified non-destructive deployment is:

1. Keep the existing preview gateway running. Create a fifth /24
   outbound subnet (`10.42.4.0/24`, delegated to Microsoft.Web/serverFarms) and
   permit its HTTPS traffic to the existing Foundry private endpoint.
2. Create Standard v2 with that subnet, model APIs, scoped subscriptions,
   managed identity, and a new private endpoint in the existing inbound subnet.
3. Verify successful completion for all three models, missing-key rejection,
   cross-model key rejection, and server-enforced model routing.
4. Remove the unused old gateway as the user's repeated follow-up explicitly
   requests; the user confirms no clients use it, so target inference testing
   is not a prerequisite to deletion. Confirm the precise old-gateway deletion and
   remove only the preview gateway, preview-only children/keys, its role
   assignment, and its private endpoint. The user explicitly requested this
   deletion in a follow-up message.
5. Move Standard v2 into the now-free original outbound subnet
   `10.42.2.0/24`, test again, and remove the temporary `10.42.4.0/24` subnet and
   its supporting NSG/rules. Final layout is the original four /24 subnets.

The new APIM has its own gateway URL and keys. Old preview clients remain
unaffected until the authorized old-gateway removal. New clients use
model-specific API paths and subscription header/keys. Remove obsolete preview
outputs only when their resources are removed; expose new APIM endpoints and
sensitive subscription keys through separately named outputs.

Public retail pricing queried for Sweden Central: Standard v2 first unit
USD 1.25/hour, approximately USD 912.50 per 730-hour month before contractual
discounts, taxes, model usage, networking, and any applicable API-call charges.
Do not deploy applications, monitoring, storage, or duplicate Foundry models.

### Safety

The user explicitly states the source is unused and repeatedly requests its
deletion. Remove it after the additive Terraform operation releases the state
lock; do not keep it running merely to wait for model tests.
After deletion, rollback would require recreating the old gateway and new keys;
do not promise immediate rollback. Restrict each saved plan to its documented
stage and review exact deletions before applying.

### Sources and proof

- Live Azure context matches tenant `16b3c013-d300-468d-ac64-7eda0820b6d3`
  and subscription `fb7dfa70-78b9-4e56-8d2d-fa2eff765241`.
- `GET Microsoft.ApiManagement/service/aigw-foundry-8ps1sz/skus` using API
  2024-05-01 returns only SKU AIGateway.
- https://learn.microsoft.com/azure/api-management/v2-service-tiers-overview
- https://learn.microsoft.com/azure/api-management/integrate-vnet-outbound
- https://learn.microsoft.com/azure/api-management/api-management-region-availability
- https://learn.microsoft.com/azure/api-management/api-management-subscriptions

- [x] Assess the supported tier transition and networking requirements.
- [x] Confirm scope: user explicitly requested a new Standard v2 instance and
      three API subscriptions, followed by deletion of the old AI Gateway.
- [ ] Update Terraform, model-scoped subscriptions, policies, tests, and docs.
- [ ] Validate and review the exact Terraform plan.
- [ ] Deploy the new instance and verify all model access boundaries.
- [ ] Confirm final Terraform convergence and record proof.

Rollback and old-gateway cleanup require an explicitly reviewed plan. Do not
stop or delete the existing gateway without separate user confirmation.

Stage 2 applied at 2026-10-16 15:25 +03:00: zero added, zero changed,
17 obsolete preview records destroyed. The old gateway deletion is complete.

The user additionally requests that the models appear under the portal's
AI Gateway > AI Models blade, not just as generic HTTP APIs. Create explicit
Foundry-linked managed-identity model backends and wire each API to its own
backend. Browser-level classification verification is pending because the
integrated portal browser is not signed in; the user is unavailable for forms.
Do not claim that the exact blade has been verified from ordinary API counts.

Live access tests found a subscription-scope defect: AzureRM API IDs include
`;rev=1`, while the current API ARM IDs do not. Matching keys were rejected
with 401 even though they match Azure's generated keys. Scope subscriptions
to revision-free API IDs. This replaces the three newly created, unusable
subscriptions and rotates their never-distributed keys.

Stage 3 also moves Standard v2 onto the now-free original outbound subnet.
Retain the temporary subnet until the integration update is confirmed complete.
Stage 4 then removes only the temporary subnet/NSG and its temporary allow rule.

### All validation checks pass - Standard v2 model backend repair

- [x] Existing Terraform/provider initialization is usable; no dependency changes.
- [x] Terraform formatting, validation, and both mocked regression tests pass.
- [x] Revision-qualified mocked API IDs verify revision-free subscription scopes.
- [x] Azure context and the user-provided APIM/Foundry URLs match the existing
      tenant, subscription, resource group, and exactly three deployed models.
- [x] Saved plan `tfplan-model-backends`: six additions, four updates, three
      subscription replacements, with no other deletion or replacement.
- [x] Foundry, its three deployments, RBAC, the VNet, and every subnet are no-op.
- [x] Only the APIM parent's outbound integration moves to the original subnet;
      temporary network resources are retained through this update.
- [x] Backend configuration uses managed identity and references the existing
      account; policies retain deployment pinning, validation, and streaming.
- [x] The precise subscription replacement/key rotation was presented through
      ask_user. The tool reports that the user is unavailable and directs a
      pragmatic choice. Repair the three newly created, unusable subscriptions
      as part of the user's explicit three-subscription access request.
- [x] Post-deployment: inference, isolation, streaming, and the exact AI Models
      blade must be verified before reporting overall completion.

Saved plan SHA256:
`D69D60823525B21B1DF331015A9636EB9C52FE80B08FFED7EA9C1B6F60F78950`.

The user's authenticated external Edge window is now accessible through Windows
UI Automation. The AI Models page is currently displaying its loading indicator;
the earlier integrated-browser sign-in limitation is not a deployment blocker.

### Section 7: Validation Proof - current model backend repair

- `terraform fmt -check -recursive`: passed.
- `terraform validate -no-color`: passed.
- `terraform test -no-color`: two passed, zero failed.
- PowerShell parser for `tests/Test-StandardApim.ps1`: zero syntax errors.
- Saved plan action and protected-resource review: passed, with the SHA256 above.
- Static role review: APIM's system-assigned principal retains Foundry User
  (`53ca6127-db72-4b80-b1b0-d745d6d5456d`) only on the existing Foundry account.
- Build verification: no applications are deployed; Terraform validation and
  mocked planning tests cover this infrastructure-only build.
- Native validation commands are used because the shared Terraform preflight
  wrapper has the previously diagnosed native-argument forwarding defect.
- The authenticated AI Models import wizard lists `fdry-aigw-8ps1sz`, AIServices,
  Sweden Central, the expected services.ai endpoint, and exactly three deployments.
- No portal create/submit action has been performed.
- Post-deployment AI Models registration, inference, and final network convergence
  are still pending and are not represented as complete by preflight validation.

### Stage 3 applied and live verification completed

The fingerprint-verified model backend/subscription repair applied successfully
at 2026-10-16 16:11:19 +03:00: six additions, four updates, three replacements.
The three new API subscription keys are now working and model-scoped.

`tests/Test-StandardApim.ps1` passed all live checks: each model returned HTTP
200 with its expected model identity and an assistant answer; all missing and
cross-model keys received 401; mismatched models and malformed JSON received
400; routing overrides were ineffective; DeepSeek returned complete SSE.

The service is StandardV2, Succeeded, using the original `snet-aigw-outbound`.
The principal is unchanged and retains account-scoped Foundry User. Foundry
local authentication remains disabled, public access Disabled, network default
Deny, and trusted-services bypass AzureServices.

### Stage 4: AI Models classification and four-subnet convergence

The portal has an existing reserved `aimodel` tag, but `apisByTags` returns no
tagged APIs. Adopt that existing tag into Terraform and associate the same three
protected model APIs with it. Do not create duplicate APIs or Foundry deployments.
The general APIs and AI Models views must both show the intended three APIs.

The temporary outbound subnet has no IP configurations, service association
links, or resource navigation links. Remove only that temporary subnet, its
NSG, three rules, and NSG association, plus its obsolete Foundry NSG source.
Retain the four original /24 subnets, all private endpoints and DNS, the active
Standard v2 service, all subscriptions/policies/backends, and Foundry/models.

Re-run native validation and mocked tests, inspect the exact saved plan, follow
the official validation workflow, apply only its verified fingerprint, and
repeat live inference/authorization/streaming and exact portal checks. End with
a refreshed no-change plan and corrected documentation.

### All validation checks pass - final AI Models registration

- [x] Existing initialized providers and default workspace are unchanged.
- [x] `terraform fmt`, `terraform validate -no-color`, and both mocked tests pass.
- [x] Regression assertions cover the exact `aimodel` marker on the same three
      revision-free API identities used by their working subscriptions.
- [x] The pre-existing `aimodel` tag is imported into Terraform, not recreated.
- [x] Earlier live inference, authorization boundaries, and streaming pass.
- [x] Temporary subnet inspection confirms no remaining IP/configuration links.
- [x] Static role scope and managed-identity-only backend configuration remain
      unchanged; this infrastructure-only build adds no applications/services.
- [x] Exact temporary-network deletion scope was presented through ask_user;
      the tool directs a pragmatic choice while the user is unavailable.
- [x] Inspect the new saved plan and fingerprint; permit only three tag
      associations, the documented temporary-network deletions, and removal of
      the temporary NSG source. No API/subscription/model replacements are allowed.
- [x] Verify the visible portal AI Models count is three after apply, rerun live
      tests on the final four-subnet layout, and obtain a refreshed no-change plan.

### Section 7: Validation Proof - final AI Models registration

Verified 2026-10-16 16:37:19 +03:00.

- Formatting and native Terraform validation pass; both mocked regression tests
  pass with the new classification assertions.
- `git diff --check` passes.
- Existing `aimodel` definition imported successfully; no existing API carries
  an API-level tag according to the live `apisByTags` response.
- Saved plan `tfplan-ai-models-final`: three tag associations added, one documented
  Foundry NSG rule updated, and six unused temporary-network records destroyed.
- An exact ten-address/action allowlist passed. APIM, APIs, subscriptions/keys,
  backends, Foundry, model deployments, RBAC, and original subnets are unchanged.
- Static role/build verification is unchanged from the passed stage-three
  verification: account-scoped Foundry User, managed identity, no app build.
- Saved plan SHA256:
  `558D64487A8E066C947AE0D6D003934F9B131C2987F591FE36EE486C7D36FF53`.

### Stage 4 applied and verified

The fingerprint-verified plan applied successfully: three tag associations
added, one NSG rule changed, and six unused migration-network records deleted.
Live `apisByTags` returns exactly the intended three APIs under `aimodel`.
The authenticated Edge AI Models table visibly contains all three model rows.

The complete live inference, model-isolation, validation, routing, and streaming
suite passed again. Azure confirms exactly the original four /24 subnets,
exactly three healthy Foundry deployments, disabled Foundry local/public access,
and the existing account-scoped Foundry User assignment. A refreshed Terraform
plan reports no changes.

### Stage 5: Azure Portal chat CORS

The user reported a CORS error in the DeepSeek AI Models test console.
An unauthenticated OPTIONS preflight to its existing chat endpoint, with origin
`https://ms.portal.azure.com`, returns HTTP 404 without CORS headers. The model
policies currently lack CORS; successful non-browser inference does not prove
browser compatibility.

Add API-level CORS first in the inbound policy for the same three APIs. Allow
only POST from `https://ms.portal.azure.com` and `https://portal.azure.com`,
support SDK request headers, and disable browser credential sharing. Do not add
an OPTIONS operation, wildcard origins, another API, or any Azure resource.
Keep subscription enforcement, deployment pinning, managed identity, RBAC,
Foundry privacy, models, subscriptions/keys, and networking unchanged.

The exact origin/policy-only scope was presented through ask_user. The user is
unavailable for forms and the tool directs a pragmatic choice; proceed with
this narrow fix to the explicitly reported portal-chat failure, not a broader
cross-origin or authentication change.

The portal HTTP pane exposed a second cause: it posts to
`/deployments/FW-DeepSeek-V4.1-Flash/chat/completions` relative to the existing
API base, while only `/chat/completions` exists. Preserve that canonical route
and add one exact deployment-qualified operation per existing API, sharing its
request schema and entire API policy. A different deployment's route must 404.
The portal's actual DeepSeek body (`max_completion_tokens=800`, temperature,
top_p, streaming) succeeds on the canonical route, so no payload conversion is
required.

#### All validation checks pass - portal chat CORS

- [x] Recursive formatting, native validation, both mocked tests, PowerShell
      parser checks, and whitespace checks pass.
- [x] Review and fingerprint a new saved plan containing only three in-place
      API imports adding exact compatibility operations and three model policy
      updates; no resource additions, deletions, or replacements.
- [x] Complete the official validation/deployment gates and apply the exact plan.
- [x] Verify both portal preflights and readable actual responses for all models,
      disallow an untrusted origin, and repeat isolation/routing/streaming tests.
- [ ] Verify the actual browser chat and obtain a refreshed no-change plan.

### Section 7: Validation Proof - portal chat CORS

This CORS-only saved plan is superseded by the required compatibility-route
fix and MUST NOT be applied. Generate a new full plan after route validation.

Validated 2026-10-16 16:59:00 +03:00; saved-plan review completed at
2026-10-16 17:03:31 +03:00.

- `terraform fmt -check -recursive`: passed.
- `terraform validate -no-color`: passed.
- `terraform test -no-color`: two passed, zero failed, including first-policy
  CORS placement, exactly two portal origins, and POST-only assertions.
- PowerShell parser for `tests/Test-StandardApim.ps1`: zero syntax errors.
- `git diff --check`: passed.
- `terraform plan -out=tfplan-portal-cors`: three in-place policy updates only.
- Exact address/action allowlist passed. XML parsing confirms one first-position
  CORS policy per API, the two intended origins, POST only, and no browser
  credential sharing. Removing the added CORS element produces XML identical to
  the previously deployed policy; no other authentication/routing change exists.
- Build/static role checks pass: infrastructure-only, no application build;
  Foundry User account scope and managed-identity backend auth are unchanged.
  Live APIM identity, original subnet, sole active StandardV2 service, exactly
  three APIs/models, four /24 subnets, and private Foundry settings are verified.
- Saved plan SHA256:
  `22EE3EA590D47E846A513A9E969AF5928B6F59C3957BA450F4CF328DB5DFC3D2`.

### Section 7: Validation Proof - complete portal chat fix

Verified 2026-10-16 17:13:09 +03:00.

- Recursive formatting/check, `terraform validate -no-color`, both mocked tests,
  both PowerShell syntax checks, and `git diff --check` pass.
- The portal HTTP pane confirms the deployment-qualified URL and subscription
  header. Its exact DeepSeek payload succeeds with complete SSE on the canonical
  route. Browser-origin preflight still lacks CORS before deployment.
- Saved plan `tfplan-portal-chat`: exactly six in-place updates, consisting of
  three API imports and three API policies; zero additions/deletions/replacements.
- API IDs, revisions, paths, subscription configuration, protocols, and service
  URLs are unchanged. The existing OpenAPI document is byte-equivalent after
  JSON normalization and removal of the new exact compatibility operation.
  The new operation shares the existing canonical request/response definition.
- XML review confirms only the first-position, two-origin, POST-only CORS block
  is added. The rest of each policy is unchanged.
- Static/live RBAC and infrastructure-only build checks remain passed. All
  Foundry, network, identity, backend, tag, subscription, and key resources are
  unchanged by this plan.
- Saved plan SHA256:
  `D5D5D3222E0BF0F9A555E7C57DE8FB482C801E5BC1DBE4CF8466C3110B00C8F7`.

### Stage 5 applied and runtime verification

The fingerprint-verified complete portal fix applied: zero additions, six
in-place API/policy updates, zero deletions. Both canonical and exact portal
routes pass both trusted-origin preflights and block an untrusted origin.
All three models return real completions, including CORS-readable responses on
their portal routes; missing/cross-model keys remain 401, wrong deployment
routes 404, bad bodies 400, and DeepSeek portal-style SSE completes.

Post-apply RBAC is unchanged and a refreshed plan reports no changes. The old
test-console error remains in browser history. Native-input automation was
interrupted by the user changing the original window, so a separate task-owned,
signed-in Edge test window was opened (HWND 2954306, owner PID 18088) for the
remaining real-browser check. Do not report that check complete yet.

### Stage 6: Three separate APIM model products

The user requests three products serving the existing AI models separately.
Live APIM inventory contains no products, so no existing product is overwritten.
Create exactly three published, subscription-required products named for the
existing deployments, with IDs matching their API IDs. Each contains only its
own existing API. Associate the existing built-in developers group for signed-in
discovery, not guests, and require administrator approval for new product
subscriptions, with one subscription per developer per product.

Subscription handling and visibility were presented through ask_user; the user
is unavailable and the tool directs a pragmatic choice. Preserve the existing
three API-scoped subscriptions and keys. Do not create/replace subscriptions,
rotate keys, add users/groups, change policies, or deploy any other service.
Product subscription lists remain empty until separately requested.

#### All validation checks pass - three model products

- [x] Recursive formatting, native validation, both mocked tests, PowerShell
      parser and whitespace checks pass.
- [x] Review and fingerprint a full plan containing only three products, three
      matching API associations, and three developers-group associations added.
      All existing resources, including subscription scopes/keys, are no-op.
- [x] Complete official validation/deployment gates and apply the exact plan.
- [x] Verify all three products are published, subscription/approval required,
      contain exactly their matching API, and allow only signed-in developers
      plus administrators for visibility.
- [x] Repeat live model/isolation/CORS/streaming tests, verify unchanged RBAC and
      private Foundry, and obtain a refreshed no-change plan.

### Section 7: Validation Proof - three model products

The plan below was rejected by a provider cross-field Create validation and
must not be reapplied. Both live inventory and Terraform state confirm zero
products were created. No existing resource was changed.

Verified 2026-10-16 17:41:36 +03:00.

- Installed AzureRM schema confirms the product, API-association, and group-
  association fields; the built-in developers group exists.
- `terraform fmt -check -recursive`, `terraform validate -no-color`, both mocked
  tests, the PowerShell parser, and `git diff --check` pass.
- Regression assertions cover three published subscription/approval-required
  products, one matching API association each, and developers-only discovery.
- `tfplan-model-products` contains exactly nine creations: three products,
  three API associations, and three existing-developers-group associations.
- Exact type/address/action and model mapping checks pass; all existing
  resources, API scopes/keys, policies, Foundry/models, networking, and RBAC are
  unchanged. Product membership is not an API-key authentication bypass.
- Static role/build checks pass: no application build, no new Azure IAM roles;
  existing account-scoped managed identity remains unchanged.
- Saved plan SHA256:
  `1FC46559B81A7C964A227518D54723F8276DE434B8C33A530B7E9632F8F4CCAE`.

### Product approval constraint and recovery

AzureRM Create requires `subscriptions_limit > 0` when `approval_required` is
true; this constraint is not exercised by mocked planning. Set the supported
limit to one subscription per developer per product, not a global developer or
request/token cap. Preserve approval instead of silently auto-approving access.
The two alternatives were presented through ask_user; the tool again reports
the user unavailable and directs the pragmatic, restrictive recommended choice.

Add a regression assertion and live check for the exact per-user limit, update
the documentation, repeat validation, and generate a fresh additions-only plan.

### Section 7: Validation Proof - approved products with per-user limit

Verified 2026-10-16 17:51:12 +03:00.

- Formatting, Terraform validation, both mocked tests, PowerShell syntax, and
  whitespace checks pass again. Assertions include the required positive
  per-user subscription limit of one.
- Official product contract confirms this limit applies per user per product,
  not to the total number of consumers.
- Both live and Terraform inventory confirm the earlier rejected apply created
  no products. A fresh full plan is saved as `tfplan-model-products-approved`.
- Exact nine-create type/address/action and target-mapping review passes.
  Products require subscription and approval, are published, and limit new
  product subscriptions to one per developer; each links only its model API.
- All existing resources, API subscription scopes/keys, roles, private Foundry,
  models, policies, and networking remain no-op.
- Infrastructure-only build and static least-privilege role verification pass.
- Saved plan SHA256:
  `133C2F7B92286BC876E9D4C065E1AF005E2CD1F07B0CE0D6191920D886FF5BBE`.

### Stage 6 deployed and verified - 2026-10-16 18:00:15 +03:00

The fingerprint-verified corrected plan applied successfully: nine additions,
zero changes, zero deletions. Azure lists exactly three published products:
`gpt5-4mini`, `phi`, and `fw-deepseek-v4-1-flash`. Each contains exactly its
matching existing API, requires subscriptions and approval, and permits one
product subscription per developer. Visibility includes developers and
administrators, not guests.

The complete live integration script passed, including product membership,
publication/approval/limit/visibility settings, both chat routes and portal
origins, all three real model completions, cross-model/missing-key rejection,
invalid-body and wrong-route rejection, routing pinning, and complete DeepSeek
SSE. The original API-scoped subscriptions and keys were preserved; no
product-scoped subscriptions were created.

Post-deployment Foundry privacy and account-scoped managed-identity RBAC checks
pass. A refreshed full Terraform plan reports no changes. No extra service,
model, identity, or subnet was deployed.

The task-created Edge window was closed without touching original user windows.
The earlier interactive-browser retest remains unverified, separately from the
completed product deployment and passing HTTP/CORS tests. Temporary final-stage
binary plans and browser helpers are removed after verification; deployment
logs, fingerprints, source, and Terraform state are retained.

### Stage 7: AI Models backend settings and renewed chat failure

The user reports another AI Models chat failure and shows GPT's overview with
blank Backend and Backend URL fields. Read-only inspection confirms the three
managed-identity backends have the correct HTTPS URLs, Foundry resource
associations, and audience. Fresh GPT and Phi requests using the portal's
deployment-qualified path, streaming, temperature 0.7, top_p 1, and
max_completion_tokens 800 return HTTP 200, complete SSE, and assistant answers.

The DeepSeek API policy has drifted: its CORS block is absent. Azure activity
records a successful policy write at 2026-10-16T16:17:35.7740144Z, after the
previous no-change plan. The existing backend references also lack the
portal-generated policy identifier.

The repair is policy-only: restore the Terraform-managed CORS block and add
`id="apim-generated-policy"` to each existing literal backend reference. Do not
change backend URLs, subscription headers/scopes/keys, products, model
deployments, identities, Foundry privacy, or networking. Extend static/live
tests to inspect all three backend bindings/URLs/MI settings and require
complete portal-style assistant streams from all three models.

The previous actual portal request capture confirms
`Ocp-Apim-Subscription-Key`, Content-Type, and the exact DeepSeek deployment
route; do not change authentication to an assumed API-key alias. The gateway
also accepts the APIM-hosted console origin during preflight without expanding
the configured application-origin allowlist.

The current integrated browser is not authenticated. The authorized external
Edge window can be inspected read-only, but native foreground/click guards
prevent safe Test console interaction. The request for a fresh error returned
"user unavailable"; this is not user confirmation. Do not claim a fresh
interactive chat succeeds without observing one.

- [x] Run formatting, Terraform validation/tests, and PowerShell syntax checks.
- [x] Review and fingerprint a fresh policy-only plan; complete official gates.
- [x] Apply only the reviewed policy changes.
- [x] Verify live backend settings, all model completions/streams, isolation,
      CORS, and Terraform convergence.
- [x] Reload the actual overview: backend labels remain blank, while the
      policy/backend bindings are correct. See Stage 8 for the actual failure.
- [x] Observe fresh successful interactive chats for all three models in Stage 8.

#### All validation checks pass - portal backend compatibility

- [x] Existing Terraform/providers/CLI and initialized state are available.
- [x] Terraform formatting and configuration validation pass.
- [x] Both mocked regression tests pass; the new resource-link assertion uses
      a deterministic plan-time mock for the computed Foundry account ID.
- [x] PowerShell syntax and whitespace checks pass.
- [x] Fresh full plan changes only the three existing model API policies.
- [x] Infrastructure-only build: no application or container build is applicable.
- [x] Static RBAC remains APIM's system-assigned identity with Foundry User
      only on the existing Foundry account; MI audience and disabled local
      authentication are unchanged.

### Section 7: Validation Proof - portal backend compatibility

Validated commands and exact saved-plan review on 2026-10-16, completed by
21:03:57 +03:00:

- Existing Azure CLI context matches tenant
  `16b3c013-d300-468d-ac64-7eda0820b6d3`, subscription
  `fb7dfa70-78b9-4e56-8d2d-fa2eff765241`, and the existing Sweden Central
  resource group. Terraform workspace is `default`, with 62 managed resources.
- `terraform fmt -check -recursive`, `terraform validate -no-color`,
  `terraform test -no-color`: pass, two tests and zero failures.
- The initial new mock assertion exposed an unknown computed Foundry ID during
  plan. A plan-time override of that computed ID fixes the fixture; no
  production value was overridden or assertion weakened.
- PowerShell parser validation of `tests/Test-StandardApim.ps1` and
  `git diff --check`: pass.
- `terraform plan -input=false -no-color -out=tfplan-portal-backend`: pass.
  In-memory JSON review asserts exactly three existing API-policy updates and
  no additions, deletions, replacements, or other resource changes.
- XML comparison proves GPT/Phi change only the backend policy ID. DeepSeek
  additionally restores exactly the two-origin, POST-only CORS block. Other
  policy content is unchanged.
- Infrastructure-only build and static role verification pass: retain the
  account-scoped Foundry User role for APIM's system-assigned identity; no
  additional identity, role, API key, network access, or backend URL is added.
- Target confirmation was requested using structured subscription, region,
  and limited-repair fields. The user was unavailable; keep the already
  established target and non-destructive repair scope. Do not describe this
  response as affirmative user confirmation.
- Saved plan SHA256:
  `82B413EA0674D1ADA9F3CA0D36DD787C82F2271FD5F6A766E56A520546EDB11E`.

### Stage 7 deployed and HTTP-verified

The fingerprint-verified plan applied at 2026-10-16 21:07:27 +03:00:
zero added, three existing API policies changed, zero destroyed.

The complete live integration test passed at 21:11:48 +03:00. It checks the
three exact backend policy references, API/backend HTTPS URL agreement,
Foundry resource associations, system-assigned managed-identity audience,
TLS validation settings, all products and access boundaries, both routes'
CORS preflights, all three real model completions, routing protection, and
complete assistant-answer SSE streams with the portal's default parameters.
Live account-scoped Foundry User RBAC and private/API-key-disabled Foundry
checks also pass. The refreshed Terraform plan at 21:13:41 +03:00 exits zero
with no changes.

Fresh deployment inventory reveals an important separate limitation:
GPT mini and Phi each advertise one request per 60 seconds and 1,000 tokens
per 60 seconds at capacity 1. Both produced HTTP 429 during repeated tests
and succeeded after the existing 65-second retry wait. DeepSeek remains at
capacity 250, advertising 250 requests and 250,000 tokens per 60 seconds.
These are shared Foundry deployment limits, not missing backend permissions.
The capacity-increase question returned "user unavailable"; leave capacities
unchanged rather than silently changing throughput.

The actual authenticated overview refresh was invoked using a supported
accessibility action without foreground typing. The subsequent address guard
no longer matched the exact APIM resource, so no further interaction was
attempted. At the end of that attempt, the backend fields and a new interactive chat
remained unverified; Stage 8 below completes the actual browser investigation.
The integrated-browser page was unauthenticated; both its close request and
subsequent read timed out, so its closure is unconfirmed. Original user Edge
windows were not closed and no chat prompt or credential was typed.

### Stage 8: Actual Azure Portal sandbox CORS repair

A new task-owned Edge window authenticated through the existing profile without
reading cookies or entering credentials. Fresh inspection confirms the GPT
overview still shows blank backend labels; the deployed policy identifier did
not resolve that display. Configuration and Settings were inspected read-only.
The routing policy, backend URLs, Foundry association, and managed identity
remain authoritative and were already verified with successful inference.

Actual Edge DevTools now identifies the browser-specific failure:
the AI Models Test console runs from
`https://sandbox-3.reactblade-ms.portal.azure.net`, not either outer portal
address. The console sends a deployment-qualified request with the APIM
subscription key in its configured query parameter. Its preflight fails with
no `Access-Control-Allow-Origin`. A direct OPTIONS request with this exact
origin independently reproduces HTTP 200 with no CORS response headers.
Subscription keys were redacted from captured error text and were not saved.

The minimal repair adds one policy expression to the existing API-level CORS
allowlist. It returns the request origin only if the complete value matches
HTTPS, a numeric `sandbox-` host, and exactly
`reactblade-ms.portal.azure.net` or `reactblade.portal.azure.net`.
Otherwise it returns the already-allowed main portal origin. Keep POST only,
browser credentials disabled, and all authorization/model isolation intact.
Do not change backend URLs, model capacities, products, subscriptions/keys,
roles, Foundry privacy, networking, or the three existing model deployments.
The expected plan is exactly three existing policy updates, no other changes.

Regression tests now require the strictly anchored expression and no wildcard
origin. Live tests cover both sandbox host families, spoofed suffixes/ports,
non-HTTPS and nonnumeric hosts, plus all three real model answers and complete
streams using the actual sandbox origin and query-key transport.

- [x] Identify the actual browser origin and reproduce the failed preflight.
- [x] Implement the narrow policy fix, regression coverage, and documentation.
- [x] Complete fresh validation and review/fingerprint the policy-only plan.
- [x] Apply only the validated plan.
- [x] Verify live tests and refreshed no-change Terraform plan.
- [x] Observe fresh successful interactive chats for all three models.
- [x] Close only the task-owned Edge window and remove temporary UI helpers.

#### All validation checks pass - actual portal sandbox origins

- [x] Terraform and Azure CLI installed, correct existing tenant/subscription,
      initialized providers/state available in the apim-only root.
- [x] Run deterministic preflight with the existing initialized providers:
      format check, configuration validation, saved plan, state listing, and
      template/JSON checks where applicable. Do not reinstall unchanged
      dependencies or overwrite the pre-existing unrelated `tfplan` file.
- [x] Both mocked Terraform regression tests, PowerShell syntax, and whitespace
      checks pass.
- [x] Saved-plan review confirms exactly three in-place API policy updates,
      with only the new strict portal-origin expression added.
- [x] Infrastructure-only build: Terraform validation/tests pass; no
      application/container build is applicable.
- [x] Static identity/role review preserves APIM system-assigned identity with
      Foundry User scoped only to the existing Foundry account.
- [x] Record command/timestamp proof, plan fingerprint, and established target.

#### Section 7: Validation Proof - actual portal sandbox origins

Validation commands completed on 2026-10-16 by 23:12:11 +03:00:

- Azure CLI context matches the established tenant
  `16b3c013-d300-468d-ac64-7eda0820b6d3` and subscription
  `fb7dfa70-78b9-4e56-8d2d-fa2eff765241`. Target remains the existing Sweden
  Central StandardV2 APIM and resource group.
- `terraform fmt -check -recursive`, `terraform validate -no-color`, and
  `terraform test -no-color` pass: two tests, zero failures. PowerShell parser
  validation and `git diff --check` also pass.
- Existing initialized providers are retained without changing dependencies.
  The workspace is `default`, with 62 managed resources. Template scanning
  passes; `main.tfvars.json` is not used. Equivalent recipe checks use a
  uniquely named saved plan to preserve the pre-existing `tfplan` artifact.
- `terraform plan -input=false -no-color -out=tfplan-portal-sandbox` passes:
  zero added, three existing API policies updated, zero destroyed.
- In-memory saved-plan JSON and XML comparisons verify that removing the one
  new origin-expression element makes every changed policy identical to its
  prior value. All other resources are no-op. No subscription keys are printed.
- Static role review confirms APIM's system-assigned principal retains the
  account-scoped Foundry User assignment and unchanged MI audience. No role,
  principal, networking, backend, capacity, model, product, or subscription
  change appears in the plan. No application/container build is applicable.
- Saved plan SHA256:
  `D2464F3D1B84A2ACC36F0A76CE1520C46F743F82C2D3806C7D880C6B43D327D1`.
- Target confirmation was requested through the required structured form.
  The user was unavailable; retain the previously authorized existing target
  and non-destructive repair scope. This is not affirmative form confirmation.

#### Stage 8 deployment and actual browser verification

The fingerprint-verified plan applied at 2026-10-16 23:17:00 +03:00:
zero added, three existing API policies changed, zero destroyed. Immediately
afterward, all three APIs accepted the exact sandbox origin that had failed.
Live role verification confirms the same APIM system-assigned identity has
Foundry User at the Foundry-account scope. Foundry public access and API-key
authentication remain disabled, with the same trusted-services exception.

Fresh authenticated Azure Portal Test console chats now succeed for every
model. Each probe used a new unique token; the exact assistant response was
observed separately from the submitted prompt, rather than inferred from
native HTTP tests or old chat history:

| Model | Exact fresh assistant answer | Verified on 2026-10-16 (+03:00) |
|---|---|---|
| GPT mini | `PORTAL_GPT_READY_2318` | 23:36:39 |
| Phi | `PORTAL_PHI_READY_2344` | 23:44:08 |
| DeepSeek Flash | `PORTAL_DEEPSEEK_READY_2346` | 23:47:16 |

The complete live integration suite finished at 23:48:45 +03:00 with 109 PASS
checks. Coverage includes all products/backends, both routes, outer portal and
sandbox origins, rejected origin lookalikes, subscriptions/model isolation,
request validation/routing protection, and complete browser-readable streams
using the actual sandbox origin and query-key authentication. Two HTTP 429
retries renewed successfully; GPT/Phi capacities and their shared 1 RPM limits
are intentionally unchanged.

The external test wrapper initially misinterpreted an array `-notmatch` result
after the suite finished. A bounded log check corrected that result check and
confirmed the actual suite's single final PASS and all 109 passing checks.
This was a reporting-wrapper issue, not a failed model test; no unnecessary
inference rerun or production change was made.

The refreshed `terraform plan -input=false -no-color -detailed-exitcode`
completed at 23:48:42 +03:00 with exit zero and no changes. The overview's blank
Backend labels are not the chat failure: the actual bindings/URLs, managed
identity, expected backend models, and interactive chats are verified. No
unsupported API metadata write or speculative backend URL change was made.

At 23:51:48 +03:00, only task-owned Edge HWND 5311672 was closed after checking
its owner, APIM URL, and empty input; four other Edge windows were preserved.
The named UI helper, task screenshot, and fingerprint-verified applied binary
plan were removed. Deployment, live-test, and convergence proof logs remain
in the session files; no subscription key or access token was written there.

Stage 1 applied successfully at 2026-10-16 15:18 +03:00: 19 added, one NSG
updated, zero destroyed. The new instance is Succeeded in StandardV2 with
managed-identity principal `59971697-1c82-4914-8746-dda1ecbd1ad6`.
The user subsequently repeated that the old gateway is unused and should be
deleted immediately. The precise deletion scope was presented with ask_user;
the user is unavailable for forms, so follow the explicit written deletion
requests and preserve every resource outside that scope. The next saved plan
must delete only preview-specific resources and must not modify new Standard v2,
Foundry/model deployments, the shared VNet, or the four original subnets.

### All validation checks pass - Standard v2 stage 1

- [x] Terraform/provider installation and initialized local state are available.
- [x] Azure tenant/subscription and existing Sweden Central resource group match.
- [x] `terraform fmt -check -recursive` and `terraform validate -no-color` pass.
- [x] `terraform test -no-color`: two mocked regression tests pass.
- [x] PowerShell parser validates `tests/Test-StandardApim.ps1`.
- [x] Saved plan is restricted to 19 additions, one documented NSG update, and
      zero deletions; original Foundry and all three model deployments are no-op.
- [x] Static RBAC: the new APIM system-assigned principal receives Foundry User
      only on the existing Foundry account. No user or subscription-wide role
      is added. No application build applies to this infrastructure-only change.

### 7. Validation Proof - Standard v2 stage 1

Verified at 2026-10-16 15:12 +03:00. Native formatting, validation, two Terraform
mock tests, and the live-test PowerShell parse check passed. The preflight
wrapper's previously diagnosed argument-forwarding bug is avoided by running
the equivalent native Terraform checks in the isolated, initialized root.

`terraform plan -input=false -no-color -detailed-exitcode
-out=tfplan-standard-v2` produced 19 additions, one update, zero destructions.
Plan JSON was inspected in memory and checked against the stage's explicit
address allowlist. Exactly three API resources and three subscriptions are
present; each subscription expression explicitly references its matching API.
The sole update adds `10.42.4.0/24` to Foundry's private HTTPS NSG source ranges.
No Foundry account/deployment or existing gateway resource is changed.

Saved-plan SHA256:
`C1F927C8C88CE81A87F07782BC991689E1CC5023E8156742067A1B3B3952A498`.

Live Foundry still reports `disableLocalAuth = true`, public access Disabled,
and bypass AzureServices. The requested organizational prohibition on Foundry
API-key authentication is preserved. Backend policies delete supplied API keys
and use `authentication-managed-identity` for the cognitive-services audience.
The account-scoped Foundry User role (`53ca6127-db72-4b80-b1b0-d745d6d5456d`)
has data-plane inference permissions. APIM client subscription keys are distinct
from Foundry credentials. Live inference and role-assignment verification occur
after the new principal and service have been provisioned.

### 7. Validation Proof - old preview gateway deletion

At 2026-10-16 15:22 +03:00, formatting, native Terraform validation, and both
mock regression tests pass with preview resources removed from configuration.
The saved `tfplan-delete-preview` plan contains zero additions, zero updates,
and 17 deletions restricted by an in-memory exact-address allowlist to the old
preview service, provider/model/alias/key records, its old Foundry role,
its old inbound private endpoint, and its obsolete timing/read-action records.
There are no operations on Standard v2, Foundry, the three model deployments,
the shared VNet, private DNS, or any subnet. Infrastructure-only build and
unchanged target-RBAC checks pass.

Cleanup-plan SHA256:
`C68B79DAE7992FAB4AC4C90C6B0FED380D33233D6247EE6B00A82F82281258BB`.

Live Standard v2 is Succeeded with managed-identity principal
`59971697-1c82-4914-8746-dda1ecbd1ad6`, verified Foundry User on the exact
Foundry account, and public HTTPS returning 401 without a subscription key.
The account's API-key authentication remains disabled.

## Trusted Azure services increment - 2026-10-16 14:34 +03:00

The user explicitly requested enabling **Allow Azure services on the trusted
services list to access this cognitive services account** and preserving it in
Terraform. The live Foundry account already reports
`networkAcls.bypass = "AzureServices"`; update the Terraform definition and test
to match, rather than reverting this out-of-band change.

Only the Foundry bypass setting changes from the original configuration.
Keep public network access Disabled, default network action Deny, local
authentication disabled, the four-subnet shared VNet, gateway settings, RBAC,
and exactly three existing model deployments unchanged.

- [x] Formatting, Terraform validation, and regression test pass.
- [x] Reviewed saved plan contains no unrelated changes or resource operations.
- [x] Reconcile Terraform state with the already-enabled live setting.
- [x] Verify live setting and a final no-change Terraform plan.

Validation proof at 2026-10-16 14:36 +03:00:

- Active CLI context matches the existing tenant/subscription. Live Foundry is
  Succeeded with bypass AzureServices, defaultAction Deny, public access Disabled,
  and local authentication disabled.
- `terraform fmt -check -recursive`, `terraform validate -no-color`, and
  `terraform test -no-color` passed. The regression test requires AzureServices
  bypass while retaining the public-access, default-deny, and local-auth guards.
- The saved `tfplan-trusted-services` plan reports no changes. Its JSON was
  checked in memory: zero Azure resource operations, exactly three existing
  models, and four unchanged /24 subnets. No build or RBAC changes apply.
- Plan SHA256:
  `1BC281C2F2F3480769C759220D3EB15BB3C7064A4722322E2CCBBE90232CA811`.
- Applied only that fingerprint-verified no-op plan: 0 added, 0 changed,
  0 destroyed. Persisted state retains AzureServices bypass and default Deny.
- Final verification at 2026-10-16 14:38 +03:00 confirmed the live account is
  Succeeded with AzureServices bypass, default Deny, public access Disabled,
  and local authentication disabled. All four live subnets remain /24.
  The final refreshed Terraform plan reports no changes.
- The user's /27 subnet question was answered from current Microsoft
  documentation only. No subnet resizing is authorized or included.

Earlier verification below is historical; statements that bypass was None
describe the original deployment, not this requested trusted-services exception.

## 1. Current scope and authorization - 2026-10-16

Deploy only API Management in the `AIGateway` tier and one Microsoft Foundry
account with the three model definitions from `terraform/apim-only/main.tf`.
Use tenant `16b3c013-d300-468d-ac64-7eda0820b6d3`, subscription
`fb7dfa70-78b9-4e56-8d2d-fa2eff765241`
(`MCAPS-Hybrid-REQ-145403-2026-bulento`), Sweden Central, and resource group
`rg-foundry-aigateway-sweden`. The user was unavailable for the confirmation
form and instructed the assistant to choose pragmatic defaults.

The resource group no longer exists in Azure. The local state is historical;
refresh it during planning and reject any plan that deletes live Azure resources.
Preserve unrelated working-tree changes and all other Terraform roots.

## 2. Current architecture

`client -> APIM AIGateway -> Microsoft Foundry model deployment`

- One resource group, one APIM AIGateway, and one AIServices S0 account.
- One shared `10.42.0.0/16` VNet with four /24 subnets: Foundry inbound
  private endpoint, Foundry outbound injection (`Microsoft.App/environments`),
  gateway outbound integration (`Microsoft.Web/serverFarms`), and gateway
  inbound private endpoint.
- Public HTTPS access to AI Gateway; Foundry public access disabled, one
  Foundry private endpoint and three private DNS zones linked to the shared VNet.
  The additional gateway private endpoint uses its own subnet and
  `privatelink.azure-api.net` zone; it does not disable public gateway access.
- Exactly `Gpt5.4mini`, `Phi`, and `FW-DeepSeek-V4.1-Flash`.
- Preserve the model catalog names, versions, Global Standard SKUs, and
  capacities from the existing main.tf, subject to live availability checks.
- APIM system-assigned managed identity with Foundry User at the account scope.
- One Foundry provider connection, three registered gateway models, three
  aliases, and three independently managed runtime keys.
- The user explicitly confirmed the `AIGateway` preview pricing tier.
  Microsoft documents that keys in this tier are gateway-scoped, not
  model-isolated subscriptions. Record this limitation rather than claiming
  unsupported per-model authorization.
- No App Service/plan, per-user deployments, LiteLLM, MLflow, database, Redis,
  storage, monitoring, or agent/project. Only the explicitly requested
  supporting private-network resources are added.

## 3. Current recipe

recipe.type: terraform

Use only `terraform/apim-only`, its existing local backend, and a newly saved
full plan. Do not apply any old saved plan or the legacy Terraform root.
The deployment is direct Terraform; azd scaffolding is not applicable.
The initially reviewed three-subnet plan was already applying when the user
explicitly requested four subnets. Let it finish; then validate and apply a
strictly additive fourth-subnet/private-endpoint increment.

## 4. Current security and cost boundaries

Foundry local authentication stays disabled. Backend authentication uses the
gateway identity over its private endpoint; client requests require a runtime
key. The trusted Azure services network exception is enabled as explicitly
requested; public access stays disabled and existing RBAC remains required.
Foundry injection is configured at creation for future agent/evaluation
egress; no agents or capability hosts are provisioned. VNet injection alone
is not an internet-egress firewall. Never print keys or
full Terraform state/plan JSON. Do not create subscription-scoped role assignments
or weaken inherited policies. APIM and model inference incur service charges.

## 5. Current validation checklist

- [x] All validation checks pass
  - [x] Terraform/CLI authentication and required providers verified.
  - [x] Exact model versions, supported SKUs, and regional quota verified.
  - [x] Terraform formatting, validation, and initialization pass.
  - [x] Saved plan allows only the resource group, gateway, Foundry account,
        three deployments, account-scoped access, gateway children, and required
        VNet/subnets/NSGs/private endpoint/private DNS.
  - [x] No live Azure resource deletes/replacements or unrelated service creates.
  - [x] No unresolved template variables or application build requirements.
  - [x] Static RBAC verification confirms the gateway-to-Foundry relationship.
  - [x] Four-subnet increment formatting/tests and a new additive plan pass.

## 6. Current recovery and verification

On failure, diagnose only this deployment. Do not delete or purge existing or
soft-deleted resources without separate approval. After apply, verify the live
resource inventory, all three model deployments, account-scoped RBAC, authenticated
gateway completions, rejection of unauthenticated requests, and a no-change plan.

## 7. Current validation proof

Initial three-subnet plan verified on 2026-10-16 at 11:41 +03:00:

- CLI token and active subscription both resolve to the requested tenant and
  subscription. Azure public cloud confirmed. Effective deployment permissions
  include resource writes and role-assignment writes.
- Required Cognitive Services, API Management, Network, App, and Web providers
  are registered. No existing VNets conflict with the chosen address space.
- Live Sweden Central model catalog confirms the three exact model versions
  support Global Standard. Available quota is 1,000 for GPT mini, 1,000 for Phi,
  and 250 for DeepSeek; planned capacities are 1, 1, and 250 respectively.
- Enforced governance deny policies were reviewed. No classic resource, blocked
  VM SKU, SQL, or provisioned OpenAI resource is in this plan. Foundry disables
  local authentication and public ingress; its trusted-service bypass is None.
- `terraform init -input=false -no-color -lockfile=readonly` passed, reusing the
  installed locked providers. `terraform fmt -check -recursive` and
  `terraform validate -no-color` passed.
- `terraform test -no-color` passed: one mocked plan test, zero failures. It
  checks the AIGateway tier, public gateway/private Foundry settings, three
  model/key/alias registrations, subnet CIDRs/delegations, and private DNS counts.
- The shared preflight helper failed because its PowerShell `Args` parameter
  causes empty Terraform invocations. Its native init/fmt/validate/plan/backend
  checks were run successfully instead. Its unresolved-template scan passed;
  `main.tfvars.json` is absent and not applicable. No application build exists.
- `terraform plan -input=false -no-color -out=tfplan` passed. The saved plan
  contains 41 creates, zero updates, and four local-only destroys/replacements:
  three obsolete secret-action records and the RBAC timer. No Azure resources
  will be deleted.
- Saved-plan JSON was inspected in memory against explicit Terraform and ARM
  resource allowlists. It contains exactly three model deployments with the
  expected names/versions/capacities, three keys, and three subnets. Configuration
  references explicitly wire gateway integration to the gateway subnet, Foundry
  injection to its outbound subnet, and the private endpoint to Foundry inbound.
- Static RBAC review confirms only Foundry User, definition
  `53ca6127-db72-4b80-b1b0-d745d6d5456d`, from the gateway managed identity at
  the Foundry account scope. Its live definition grants the required inference
  data actions. No subscription-scoped assignments are created.
- Reviewed plan SHA256:
  `F524FE7DC675EAC35FA1A1626D3BB03C882343DAC13B62BD570E615AEDE5CA4A`.
- Initial apply completed: 41 added, zero changed, four local-only records
  destroyed/replaced. No Azure resource deletions occurred.
- Live gateway is SKU `AIGateway`, public access Enabled, network type External,
  and integrated with `snet-aigw-outbound` in the shared VNet.
- Live Foundry account is Succeeded, public access Disabled, local auth disabled,
  trusted-service bypass None, with agent network injection into
  `snet-foundry-outbound`.
- Live Foundry private DNS records resolve to `10.42.0.4`, `10.42.0.5`, and
  `10.42.0.6` for Cognitive Services, OpenAI, and AI Services respectively.
- Live RBAC confirms the gateway principal
  `6e4a4dd5-3480-4f6c-bcdf-1cfbf7ae0137` holds Foundry User at only the
  Foundry account scope.
- All three gateway model probes returned HTTP 200 and `READY`. Response model
  identifiers were `gpt-5.4-mini-2026-03-17`, `phi4`, and
  `FW-DeepSeek-V4.1-Flash`; live model deployments match the pinned catalog
  names and versions. The Phi response identifier is vendor-normalized.
- Three nonempty, distinct runtime credentials were verified in memory without
  printing or persisting their values outside the existing sensitive state.

### Four-subnet increment validation - 2026-10-16 12:08 +03:00

- `terraform fmt`, `terraform validate -no-color`, and `terraform test -no-color`
  pass for the updated four-subnet configuration.
- Refresh exposed service-generated runtime-key display labels. Use native
  Terraform `lifecycle.ignore_changes` only for `body.properties.displayName`,
  consistent with the existing treatment of preview-owned key metadata.
  Keys, access settings, identities, and networking remain managed and unchanged.
- `terraform plan -input=false -no-color -out=tfplan-four-subnets` contains
  exactly eight creates, zero updates, and zero destroys: the gateway inbound
  subnet, its NSG/two rules/association, private endpoint, private DNS zone,
  and VNet DNS link.
- Saved-plan JSON was checked against the exact eight resource addresses.
  The new endpoint targets the existing AIGateway `Gateway` subresource in
  `snet-aigw-inbound`, `10.42.3.0/24`. Public gateway/private Foundry settings
  remain unchanged. No existing model, key, role, or network is modified.
- Increment plan SHA256:
  `2B082F4BBFFAE40437B5EFE083673BA9F75C455915F2ED65940C6AE9118CD0F4`.
- Increment apply succeeded: eight added, zero changed, zero destroyed.

### Final deployment verification - 2026-10-16 13:52 +03:00

- User reiterated exactly one DeepSeek, one GPT mini, and one Phi: live
  deployment listing asserts exactly three successful deployments, matching
  `Gpt5.4mini` / `gpt-5.4-mini`, `Phi` / `Phi-4`, and
  `FW-DeepSeek-V4.1-Flash` / `DeepSeek-V4-Flash`. No per-user or duplicate
  model deployments exist.
- Extended the mocked Terraform test with exact deployment-name and catalog-model
  set assertions. Formatting, configuration validation, and the test pass.
- All four subnets exist in the shared VNet with the expected /24 CIDRs and
  delegations. Both Foundry and AI Gateway private endpoints are Succeeded and
  Approved. Gateway private DNS resolves to `10.42.3.4`.
- Live inventory contains only API Management, Cognitive Services, and the
  requested supporting Network resource types. No application, database,
  storage account, monitoring service, or agent workload was added.
- Final live checks assert `AIGateway` SKU, Succeeded state, public gateway
  access Enabled, and integration into `snet-aigw-outbound`; Foundry remains
  Succeeded with public access Disabled, local auth disabled, bypass None,
  and injection into `snet-foundry-outbound`.
- Post-deployment probes for all three aliases returned HTTP 200 and `READY`.
  They ran sequentially after the state-locking plan completed. Requests
  without a runtime key return HTTP 401.
- Exactly the three Terraform-managed client key resources exist, plus Azure's
  automatically generated `master` administrative key, which was not modified
  or exposed. The three client secrets are distinct. Preview key scope remains
  gateway-wide, not per-model.
- A direct Foundry request using the deploying user's Entra token returned an
  authorization denial because that user lacks the models/read data action.
  This is not claimed as a network-denial test. Isolation is verified from live
  public-access/bypass/private-endpoint settings and successful gateway calls
  to the private-only backend, without adding user roles or network exemptions.
- `terraform plan -input=false -no-color -detailed-exitcode
  -out=tfplan-verified-final` returned exit code 0 and
  `No changes. Your infrastructure matches the configuration.`
- Edited-file whitespace validation passes. No temporary Terraform test state
  remains. Unrelated pre-existing application build-output changes are untouched.

---

# Historical deployment plans - not the current authorized scope

## LiteLLM on Container Apps + Chat App2

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
