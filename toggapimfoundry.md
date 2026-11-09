# TOGG Foundry and APIM: Azure Portal administrator runbook

This runbook reproduces the final model, gateway, token-governance, Content Safety, and reporting configuration from the November 2026 session. All changes are made through browser portals, including the APIM policy code editor. There are no Terraform, CLI, Cloud Shell, or application-code deployment steps.

> **Assumptions:** APIM, Foundry, the Foundry project, storage, Application Insights and its workspace, Content Safety, networking, private endpoints, and the Azure Monitor/Application Insights implicit Grafana experience are already available. Subscription-level `Microsoft.Dashboard` registration is resolved. Infrastructure creation and identity provisioning are outside this runbook.

## Contents

1. [Resource names and final configuration](#1-resource-names-and-final-configuration)
2. [Open the correct directory and subscription](#2-open-the-correct-directory-and-subscription)
3. [Deploy and configure the Foundry models](#3-deploy-and-configure-the-foundry-models)
4. [Store backend keys in APIM](#4-store-backend-keys-in-apim)
5. [Connect APIM to Application Insights](#5-connect-apim-to-application-insights)
6. [Create the key-authenticated Content Safety fragment](#6-create-the-key-authenticated-content-safety-fragment)
7. [Publish the three HTTP APIs](#7-publish-the-three-http-apis)
8. [Apply token, routing, and safety policies](#8-apply-token-routing-and-safety-policies)
9. [Configure products and subscriptions](#9-configure-products-and-subscriptions)
10. [Enable and verify token reporting](#10-enable-and-verify-token-reporting)
11. [Import the Grafana report inside Application Insights](#11-import-the-grafana-report-inside-application-insights)
12. [Portal validation and operational checks](#12-portal-validation-and-operational-checks)
13. [Appendix A: Content Safety fragment](#appendix-a-content-safety-fragment)
14. [Appendix B: shared API policy](#appendix-b-shared-api-policy)
15. [References](#references)

## 1. Resource names and final configuration

### Existing Azure resources

Open the [RG-AI-APIM-FOUNDRY resource group](https://portal.azure.com/#@togg.onmicrosoft.com/resource/subscriptions/4be00143-6ced-4790-bba8-78efc2c755fd/resourceGroups/RG-AI-APIM-FOUNDRY/overview).

| Item | Name/value used in the session |
|---|---|
| Directory | `togg.onmicrosoft.com` |
| Tenant ID | `1414d006-f666-432a-af47-ee47eca66d66` |
| Subscription | `Subs-Togg-IT` / `4be00143-6ced-4790-bba8-78efc2c755fd` |
| Resource group | `RG-AI-APIM-FOUNDRY` |
| Region | `Sweden Central` / `swedencentral` |
| Foundry account | `TOGG-AI-PLATFORM-FOUNDRY-02` |
| Foundry project | `proj-default` |
| APIM service | `TOGG-AI-PLATFORM-APIM` |
| APIM tier | `Standard v2` |
| Application Insights | `APPI-AI-PLATFORM-FOUNDRY` |
| Application Insights App ID | `78c3ac8d-1b00-4bc2-ba20-a30bdc81bc33` |
| Linked Log Analytics workspace | `managed-APPI-AI-PLATFORM-FOUNDRY-ws` |
| Dedicated Content Safety account | `TOGG-AI-PLATFORM-CONTENT-SAFETY-02`, SKU `S0` |
| VNet | `VNET-AI-APIM-FOUNDRY-PROD` |
| APIM outbound subnet | `SN-AI-APIM-OUTBOUND` |
| Foundry private-endpoint subnet | `SN-AI-FOUNDRY-INBOUND` |
| Foundry private endpoint | `NIC-AI-FOUNDRY-INBOUND-01` |
| APIM inbound private endpoint | `AI-PLATFORM-APIM-INBOUND` |

The linked workspace is in its existing managed resource group, not necessarily `RG-AI-APIM-FOUNDRY`. Existing storage is assumed ready; no storage resource names were established or storage settings changed in the session.

Use **`APPI-AI-PLATFORM-FOUNDRY`**, not the similarly named `APPI-AI-PLATFORM-FOUNDRY-01`.

### Authentication and networking boundaries

- Azure Portal administration uses the administrator's existing Entra sign-in and permissions. This is management access, not an authentication integration added to the deployed APIs.
- Clients authenticate to APIM with **subscription keys**.
- APIM authenticates to Foundry and Content Safety with **API keys** stored as secret named values.
- Application Insights ingestion uses its existing **instrumentation key** connection.
- Do not add OAuth/OpenID settings, JWT validation, managed-identity backend authentication, app registrations, or new role assignments.
- Keep Foundry **public network access disabled** and local/API-key authentication enabled. Its private connectivity is precreated.
- The dedicated Content Safety resource used in the session has **public network access enabled**, API-key authentication enabled, and no managed identity. APIM calls it over HTTPS. Do not open Foundry public access to make Content Safety work.
- Grafana reporting uses the precreated Azure Monitor connection in the **Application Insights embedded Grafana experience**. Do not create a separate Managed Grafana workspace.

### Model deployments

These are the latest deployable releases selected during the session, not a promise that they remain the latest catalog releases indefinitely.

| Deployment/model name | Publisher format | Version | Deployment type | Model TPM allocation | Capacity units / RPM |
|---|---|---|---|---:|---:|
| `DeepSeek-V4.1-Flash-1017` | `DeepSeek` | `2026-10-17` | Global Standard | 10,000,000 | 10,000 |
| `Kimi-K3.1-Pro` | `MoonshotAI` | `2026-11-04` | Global Standard | 5,000,000 | 5,000 |

Both deployments use **`Microsoft.DefaultV2`** guardrails. The DeepSeek release was cataloged as preview; confirm the current lifecycle status before production use.

The model allocations above are different from the deliberately lower **APIM consumer limits** below.

### Gateway settings

| Setting | Final value |
|---|---|
| Shared client-compatible API ID | `togg-foundry-02-openai` |
| Shared API URL suffix | `TOGG-AI-PLATFORM-FOUNDRY-02/openai` |
| Shared base URL | `https://togg-ai-platform-apim.azure-api.net/TOGG-AI-PLATFORM-FOUNDRY-02/openai` |
| Client compatibility | Azure OpenAI: deployment name in the URL |
| Operation | `POST /deployments/{deployment-name}/chat/completions` |
| Example client API version | `2024-10-21`; normalized away before calling the versionless backend |
| Backend base URL | `https://togg-ai-platform-foundry-02.services.ai.azure.com/openai/v1` |
| Backend operation | `/chat/completions` |
| Tokens/minute per subscription | `100000` |
| Daily token quota per subscription | `1000000`, period `Daily` |
| Prompt estimation | Disabled; use actual response usage for these non-OpenAI models |
| Consumed-token header | `x-tokens-consumed` |
| Remaining-minute header | `x-ratelimit-remaining-tokens` |
| Remaining-daily-quota header | `x-ratelimit-remaining-daily-tokens` |
| Token metric namespace | `togg-foundry-models` |
| Custom metric dimensions | `API ID`, `Subscription ID`, `Model` |
| Content Safety text mode | `EightSeverityLevels` |
| Moderation rule | Allow severity `0`; block `1` through `7` in all four categories |
| Prompt shields | User and document attack checks enabled |
| Custom keyword blocklists | Not configured |
| Safety text limit | `10000` Unicode code points; reject longer text, do not truncate |
| Product approval | Disabled |
| Subscription required | Enabled |

> **Do not copy the screenshots blindly:** a literal APIM harm threshold of `0` blocks even harmless severity-0 content. The implemented strict usable rule blocks `>= 1`. Also, prompt estimation is not reliable for these non-OpenAI models. The provided policies use actual tokens instead.

## 2. Open the correct directory and subscription

1. Use the administrator's **already authenticated Microsoft Edge profile**.
2. Open [Azure Portal](https://portal.azure.com/).
3. Select the account/directory control in the upper-right corner.
4. Select **Switch directory** and choose `togg.onmicrosoft.com`.
5. Open **Subscriptions** and select `Subs-Togg-IT`.
6. Verify subscription ID `4be00143-6ced-4790-bba8-78efc2c755fd`.
7. Open **Resource groups** > **RG-AI-APIM-FOUNDRY**.

The administrator must already have permission to manage these resources, create/edit APIM APIs and policies, read the relevant resource keys, read Application Insights data, and save Grafana dashboard resources. `Microsoft.Dashboard` registration and dashboard/data-source access are assumed resolved; do not provision identities as part of this procedure.

## 3. Deploy and configure the Foundry models

Azure Portal opens the Microsoft Foundry browser portal for the model catalog and deployment screens. This remains a portal-only procedure.

### 3.1 Open the existing project

1. In the resource group, open **TOGG-AI-PLATFORM-FOUNDRY-02**.
2. On **Overview**, select **Go to Foundry portal** / **Open in Foundry**.
3. In the Foundry project selector, select **proj-default** under this account.
4. Confirm the account, project, subscription, and region before continuing.

Foundry model deployments are account-level resources available to the project; do not create a second account or project.

### 3.2 Deploy DeepSeek

1. Open **Model catalog** / **Discover** > **Models**.
2. Search for **DeepSeek-V4.1-Flash-1017**.
3. Select the **Azure-sold/native** offering with format/publisher `DeepSeek`.
4. Do not select a Hugging Face managed-compute deployment template or an `FW-` Fireworks offering.
5. Select **Deploy** / **Use this model**.
6. Select the existing account/project if prompted.
7. Set:
   - **Deployment name:** `DeepSeek-V4.1-Flash-1017`
   - **Version:** `2026-10-17`
   - **Deployment type / Token plan:** **Global Standard**, pay-per-token
   - **Tokens per minute rate limit:** `10,000,000`, if still available
   - **Guardrails / Content filter:** **DefaultV2** / `Microsoft.DefaultV2`
8. Review and select **Deploy**.
9. Open **Deployments** / **Models + endpoints** and wait for **Succeeded**.

If the quota slider cannot reach this allocation, use the available quota and record the actual allocation. Do not claim the screenshot value was applied when the subscription cannot allocate it.

### 3.3 Deploy Kimi

Repeat the model-catalog procedure with:

- **Model/deployment:** `Kimi-K3.1-Pro`
- **Native publisher format:** `MoonshotAI`
- **Version:** `2026-11-04`
- **Deployment type:** **Global Standard**, pay-per-token
- **TPM:** `5,000,000`, if still available
- **Guardrails:** **DefaultV2** / `Microsoft.DefaultV2`

Do not use `FW-Kimi-K3` or enable Fireworks for this runbook. The final session used the latest deployable native Kimi model instead.

### 3.4 Verify Foundry configuration

1. Open each deployment's **Details** / **Edit** configuration.
2. Verify deployment name, exact version, Global Standard type, allocation, **Succeeded**, and **DefaultV2**.
3. Open **Guardrails + controls** / **Content filters** if necessary to confirm the deployment's filter association.
4. Keep the built-in DefaultV2 behavior. It includes the standard harm-category controls, prompt-attack protection, and protected-material checks; some checks, such as protected code, can be annotation-only in the default configuration.
5. Do not enable unsupported dynamic-quota or automatic-version-upgrade options just to make every switch appear selected.
6. Return to the Azure Portal account's **Networking** and verify **public access remains disabled**.
7. Verify the existing private endpoint is **Approved**.
8. Open **Keys and Endpoint** and confirm local/API-key access is available. Do not disable local authentication.

`Kimi-K3.1-Pro` can return the provider's canonical response model name **`Kimi-K3.1`**. That response label alone does not mean a different deployment was selected.

## 4. Store backend keys in APIM

Keep real keys out of this document, dashboard JSON, policy XML, screenshots, and client URLs.

### 4.1 Foundry key

1. Open **TOGG-AI-PLATFORM-FOUNDRY-02** > **Keys and Endpoint**.
2. Copy **KEY 1** using the portal copy control.
3. Open **TOGG-AI-PLATFORM-APIM**.
4. Select **APIs** > **Named values** > **+ Add**.
5. Set:
   - **Name / identifier:** `deepseek-v4-1-foundry-key`
   - **Display name:** `deepseek-v4-1-foundry-key`
   - **Type:** **Secret**
   - **Value:** the Foundry key
6. Select **Save**.

Despite its historical name, this secret is the **shared account key for both models**.

### 4.2 Content Safety key

1. Open **TOGG-AI-PLATFORM-CONTENT-SAFETY-02** > **Keys and Endpoint**.
2. Confirm SKU `S0`, the existing HTTPS endpoint, and API-key access.
3. Copy **KEY 1**.
4. In APIM **Named values**, add:
   - **Name / display name:** `foundry02-content-safety-key`
   - **Type:** **Secret**
   - **Value:** the Content Safety key
5. Select **Save**.

Use the dedicated endpoint:

```text
https://togg-ai-platform-content-safety-02.cognitiveservices.azure.com/
```

Do not replace it with the private Foundry Cognitive Services endpoint. That endpoint had a missing link in centrally managed private DNS during the session. The dedicated precreated Content Safety resource avoids changing central DNS or opening Foundry public access.

### 4.3 Existing backend inventory

The initial session also created the APIM backend record **`deepseek-v4-1-backend`** with the Foundry `/openai/v1` URL and an `api-key` named-value reference. It may remain in **APIs** > **Backends**.

The **final policies below do not depend on that backend record**. They explicitly select the proven backend base URL and set the Foundry `api-key` header after safety checks. Do not substitute backend-ID credential handling for this final transport without retesting both models.

## 5. Connect APIM to Application Insights

### 5.1 Create or verify the logger connection

1. In **TOGG-AI-PLATFORM-APIM**, select **Monitoring** > **Application Insights**.
2. Select **+ Add**.
3. Choose **APPI-AI-PLATFORM-FOUNDRY** in the existing subscription/resource group.
4. Choose the existing instrumentation-key connection; do not enable managed identity or add a role assignment.
5. Use the connection/logger name **`foundry-token-appinsights`** where the form exposes a name.
6. Select **Create** / **Save**.
7. Verify the connection points to **APPI-AI-PLATFORM-FOUNDRY**, not `-01`.

If the portal assigns a different internal logger identifier, use that actual connection when configuring the API diagnostics. The exported session used `foundry-token-appinsights`; the policy does not hard-code this logger ID.

Leave the unrelated existing **`azuremonitor`** logger/global diagnostic connection unchanged.

### 5.2 API diagnostics settings to apply after API creation

For **each of the three APIs** created in section 7:

1. Open **APIs** > the API > **Settings**.
2. Find **Diagnostics logs** / **Application Insights**.
3. Enable logging and choose **foundry-token-appinsights** / the connection to **APPI-AI-PLATFORM-FOUNDRY**.
4. Set **Sampling:** `100%`.
5. Set **Always log errors:** enabled / **All errors**.
6. Set **Verbosity:** **Information**.
7. Use **W3C** HTTP correlation; enable correlation headers where exposed.
8. Set **Log client IP:** off.
9. For frontend and backend request/response logging:
   - **Body bytes:** `0`
   - **Headers to log:** none
10. Enable **Track token usage / custom metrics** in the API's AI/diagnostics settings where exposed and save.

The diagnostic entity's effective setting must be **`metrics: true`**, in addition to the token-emission policy. Merely connecting a logger does not enable token metrics.

If the portal's **Track token usage / custom metrics** control sets this flag, use that control. If it is not exposed, use the following **Azure Portal template-editor** procedure. This is still a portal-only configuration change: no CLI, REST client, Terraform, or application deployment is used.

### 5.3 Portal-only advanced diagnostic configuration

Do this only after the API and its Application Insights logger exist.

1. In the Azure Portal search bar, search for **Deploy a custom template**.
2. Open **Deploy a custom template**.
3. Select **Build your own template in the editor**.
4. Paste the configuration template below and select **Save**.
5. On **Custom deployment** > **Basics**, select:
   - **Subscription:** `Subs-Togg-IT`
   - **Resource group:** `RG-AI-APIM-FOUNDRY`
   - **Region:** `Sweden Central`
   - **Api Name:** the first API identifier from section 7
   - **Logger Name:** `foundry-token-appinsights`, or the actual logger name assigned in section 5.1
6. Select **Review + create** > **Create**.
7. Wait for **Deployment succeeded**.
8. Repeat for the other two API identifiers.

The template updates only the existing API's `applicationinsights` diagnostic. It does not create an APIM service, Application Insights resource, identity, or role assignment. Keep all prompt/response body and header logging disabled.

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "apiName": {
      "type": "string",
      "allowedValues": ["deepseek-v4-1", "kimi-k3-1-pro", "togg-foundry-02-openai"]
    },
    "loggerName": {
      "type": "string",
      "defaultValue": "foundry-token-appinsights"
    }
  },
  "resources": [
    {
      "type": "Microsoft.ApiManagement/service/apis/diagnostics",
      "apiVersion": "2024-05-01",
      "name": "[concat('TOGG-AI-PLATFORM-APIM/', parameters('apiName'), '/applicationinsights')]",
      "properties": {
        "loggerId": "[resourceId('Microsoft.ApiManagement/service/loggers', 'TOGG-AI-PLATFORM-APIM', parameters('loggerName'))]",
        "metrics": true,
        "alwaysLog": "allErrors",
        "sampling": {"samplingType": "fixed", "percentage": 100},
        "logClientIp": false,
        "verbosity": "information",
        "httpCorrelationProtocol": "W3C",
        "enableHttpCorrelationHeaders": true,
        "frontend": {
          "request": {"headers": [], "body": {"bytes": 0}},
          "response": {"headers": [], "body": {"bytes": 0}}
        },
        "backend": {
          "request": {"headers": [], "body": {"bytes": 0}},
          "response": {"headers": [], "body": {"bytes": 0}}
        }
      }
    }
  ]
}
```

## 6. Create the key-authenticated Content Safety fragment

The native APIM **`llm-content-safety`** policy requires managed-identity backend authentication in the documented configuration. It is therefore **not** the implementation used here.

1. Open **TOGG-AI-PLATFORM-APIM** > **APIs** > **Policy fragments**.
2. Select **+ Add**.
3. Set **Name:** `foundry02-key-content-safety`.
4. Enter a description such as **API-key text moderation and prompt/document shields**.
5. Open the fragment code editor.
6. Paste the complete `<fragment>` block from [Appendix A](#appendix-a-content-safety-fragment).
7. Select **Save**.

The fragment uses only `{{foundry02-content-safety-key}}`; no actual key is pasted into XML. It:

- Analyzes textual message content using eight severity levels.
- Blocks any Hate, SelfHarm, Sexual, or Violence result at severity `1` or above.
- Checks user prompts and non-user textual context for prompt/document attacks.
- Rejects text over 10,000 Unicode code points instead of truncating it.
- Fails closed if the service is unavailable or returns an invalid response.
- Leaves image-only/non-text moderation to the existing model guardrails; it does not claim that images were text-moderated.
- Does not configure custom keyword blocklists.

Do not also enable the managed-identity Content Safety wizard checkbox. The key-authenticated fragment provides the requested safety behavior without adding an Entra integration.

## 7. Publish the three HTTP APIs

Manual HTTP API creation gives the exact final route and policy control. No OpenAPI URL or external application code is required.

### 7.1 Create the API definitions

For each row below:

1. In APIM, select **APIs** > **+ Add API** > **HTTP** / **Manually define an HTTP API**.
2. Select **Full** / advanced form if the identifier is not initially visible.
3. Enter the exact **Name / API identifier**, display name, and URL suffix.
4. Set **Web service URL** to:
   `https://togg-ai-platform-foundry-02.services.ai.azure.com/openai/v1`
5. Allow **HTTPS** only.
6. Leave OAuth/OpenID authentication settings unset.
7. Enable **Subscription required**.
8. Use subscription-key header **`Ocp-Apim-Subscription-Key`**.
9. Select **Create** / **Save**.

| API identifier | Display name | API URL suffix |
|---|---|---|
| `deepseek-v4-1` | DeepSeek V4.1 | `deepseek-v4-1` |
| `kimi-k3-1-pro` | Kimi K3.1 Pro | `kimi-k3-1-pro` |
| `togg-foundry-02-openai` | TOGG-AI-PLATFORM-FOUNDRY-02 OpenAI | `TOGG-AI-PLATFORM-FOUNDRY-02/openai` |

Do not add a duplicate API if the intended definition already exists. Update that definition instead, preserving unrelated settings.

### 7.2 Add the chat-completions operations

1. Select the API > **Design** > **+ Add operation**.
2. Enter the following method, URL template, and operation identifier.
3. For the shared API, define **deployment-name** as a required string path parameter.
4. Add an **application/json** request representation where the form exposes it.
5. Select **Save**.

| API | Operation identifier | Method | URL template |
|---|---|---|---|
| `deepseek-v4-1` | `chat-completions` | POST | `/chat/completions` |
| `kimi-k3-1-pro` | `chat-completions` | POST | `/chat/completions` |
| `togg-foundry-02-openai` | `azure-chat-completions` | POST | `/deployments/{deployment-name}/chat/completions` |

The exact shared client URLs are:

```text
https://togg-ai-platform-apim.azure-api.net/TOGG-AI-PLATFORM-FOUNDRY-02/openai/deployments/DeepSeek-V4.1-Flash-1017/chat/completions?api-version=2024-10-21
https://togg-ai-platform-apim.azure-api.net/TOGG-AI-PLATFORM-FOUNDRY-02/openai/deployments/Kimi-K3.1-Pro/chat/completions?api-version=2024-10-21
```

This is the **Azure OpenAI deployment-path** option selected in the screenshot, not the separate **Azure OpenAI v1** option. The extra shared `/v1/chat/completions` and body-only `/chat/completions` aliases were removed from the final configuration. Do not recreate them as part of this runbook.

For an Azure OpenAI SDK using `azure_endpoint`, the account-style endpoint is the gateway prefix **without** its trailing `/openai`: `https://togg-ai-platform-apim.azure-api.net/TOGG-AI-PLATFORM-FOUNDRY-02`. The SDK adds `/openai/deployments/...`; avoid doubling `/openai`.

## 8. Apply token, routing, and safety policies

### 8.1 Shared API policy

1. Select **APIs** > **togg-foundry-02-openai** > **Design**.
2. Select **All operations**.
3. Open the policy **Code editor** (`</>`) for the full policy document.
4. Paste [Appendix B](#appendix-b-shared-api-policy), replacing the API-level policy document only.
5. Select **Save** and resolve any validation errors before proceeding.

Do not duplicate `<forward-request>` by adding a backend `<base />` before the provided backend block. The session's inherited backend already had a forward request.

The shared policy permits the two deployment names and protects existing per-model product keys from accessing the other model.

### 8.2 Per-model API policies

Repeat the **All operations** policy-editor procedure for the two original APIs. Start with Appendix B and replace **only** the `set-variable` element with `id="client-model"` and `name="selected-model"` as follows.

For **deepseek-v4-1**:

```xml
<set-variable name="selected-model" value="DeepSeek-V4.1-Flash-1017" />
```

For **kimi-k3-1-pro**:

```xml
<set-variable name="selected-model" value="Kimi-K3.1-Pro" />
```

Keep the remaining policy blocks unchanged. The fixed variable makes the original endpoint select its own model even if a client supplies a different `model` field.

### 8.3 Verify effective controls

In each API policy, verify:

- **`llm-token-limit`**: `100000` TPM, `1000000` quota, period `Daily`, actual-token accounting.
- The counter key contains **subscription ID only**, not API ID or model. This prevents a key holder from gaining another daily allowance by switching routes.
- The per-model request-rate counter includes subscription ID and selected model; limits are 10,000 RPM for DeepSeek and 5,000 RPM for Kimi.
- **`include-fragment`** points to `foundry02-key-content-safety`.
- **`llm-emit-token-metric`** emits namespace `togg-foundry-models` and dimensions `API ID`, `Subscription ID`, `Model`.
- The original normalized inference body is saved and restored around the safety/helper policies.
- Client Authorization and credential headers are removed before the genuine Foundry key is applied.
- The legacy `api-version` parameter is removed **after** rewriting the backend URI.
- Streaming includes actual usage and does not buffer the SSE response.
- A maximum of one buffered-body retry is allowed only for a backend `404` on the known Kimi deployment. Invalid deployment names are rejected before the backend; there is no general retry or success fallback.

Finish the per-API diagnostic setup from [section 5.2](#52-api-diagnostics-settings-to-apply-after-api-creation), including [section 5.3](#53-portal-only-advanced-diagnostic-configuration) when the metrics flag is not exposed in the API settings UI.

## 9. Configure products and subscriptions

### 9.1 Products: publish, require keys, do not require approval

For each product:

1. Open **APIs** > **Products** > **+ Add**, or open the existing product.
2. Enter the exact product identifier and display name.
3. Enable **Requires subscription / Subscription required**.
4. Disable **Requires approval / Approval required**.
5. Set **State:** **Published**.
6. Save.
7. Open the product's **APIs** tab and select **+ Add** to associate the listed APIs.

| Product identifier | Display name | APIs |
|---|---|---|
| `deepseek-v4-1` | DeepSeek V4.1 | `deepseek-v4-1`, `togg-foundry-02-openai` |
| `kimi-k3-1-pro` | Kimi K3.1 Pro | `kimi-k3-1-pro`, `togg-foundry-02-openai` |
| `togg-foundry-02-models` | TOGG-AI-PLATFORM-FOUNDRY-02 models | `togg-foundry-02-openai` |

**Approval disabled does not mean anonymous access.** Subscription keys remain required.

Do not disable subscription protection on an API, create an anonymous product, or alter unrelated products.

### 9.2 Create the subscription keys

1. Open **APIs** > **Subscriptions** > **+ Add subscription**.
2. Enter the exact subscription identifier/name below.
3. Select **Scope:** **Product** and choose the corresponding product.
4. Leave the owner/user unassigned where the form supports a standalone subscription.
5. Set **State:** **Active**.
6. Save.

| Subscription identifier | Product scope | Access |
|---|---|---|
| `deepseek-v4-1-subscription` | `deepseek-v4-1` | DeepSeek original and shared deployment-path route |
| `kimi-k3-1-pro-subscription` | `kimi-k3-1-pro` | Kimi original and shared deployment-path route |
| `togg-foundry-02-subscription` | `togg-foundry-02-models` | Both models on the shared deployment-path route |

Use existing active subscriptions instead of replacing or regenerating their keys. Leave the existing service-wide **master** subscription unchanged.

The portal's default master key can access both models for administration. Use the actual product-scoped keys, not the master key, when validating customer isolation.

### 9.3 How clients authenticate

Clients send:

```text
Ocp-Apim-Subscription-Key: <APIM product subscription key>
Content-Type: application/json
```

They do not send Foundry or Content Safety resource keys, Entra tokens, or instrumentation keys.

For the shared subscription, the daily budget is shared between DeepSeek and Kimi. Different subscription keys have their own counters.

## 10. Enable and verify token reporting

### 10.1 Application Insights Logs

1. Open **APPI-AI-PLATFORM-FOUNDRY** in Azure Portal.
2. Select **Logs**.
3. Dismiss the example-query gallery if it covers the editor.
4. Set a time range containing the test requests, such as **Last 24 hours**.
5. Paste and select **Run**:

```kql
customMetrics
| where timestamp > ago(24h)
| where name in ("Prompt Tokens", "Completion Tokens", "Total Tokens")
| extend Model = tostring(customDimensions["Model"]),
         Subscription = tostring(customDimensions["Subscription ID"]),
         API = tostring(customDimensions["API ID"])
| where Model in ("DeepSeek-V4.1-Flash-1017", "Kimi-K3.1-Pro")
| summarize Tokens = sum(coalesce(valueSum, value))
    by Model, Subscription, API, Metric = name
| order by Model asc, Metric asc
```

Allow time for APIM buffering and Application Insights ingestion. Do not interpret an immediately empty result as proof that the policy was not installed.

Use the **classic Application Insights `customMetrics` schema** for this resource-context report. The supplied dashboard was validated against this schema; do not replace it with `AppMetrics` without changing and validating the queries.

### 10.2 Correct token accounting

- **Input:** `Prompt Tokens`
- **Output:** `Completion Tokens`
- **Total:** `Total Tokens`, or Input + Output for the breakdown table
- Sum `coalesce(valueSum, value)` because telemetry can be preaggregated.
- Do not use row count or `valueCount` as the token count.
- Do not add reasoning/cache/prediction categories to Total again; they can already be included in prompt/completion totals.
- Do not sum the separate aggregate `azure.ai_gateway.client.token.usage` series with these totals.

Actual custom dimensions configured by the policy are **API ID, Subscription ID, Model**. Observed standard dimensions also include **Region, Service ID, Service Name, Service Type**. User ID and Client IP were not added to the report.

### 10.3 Optional Metrics Explorer dimension splitting

For split-by-dimension charts in the **Metrics** blade:

1. In Application Insights, select **Usage and estimated costs**.
2. Select **Custom metrics (Preview)**.
3. Select **With dimensions**.
4. Select **OK** / **Save**.
5. Return to **Metrics**, choose namespace **togg-foundry-models**, and inspect the token metrics and available split dimensions after new telemetry arrives.

This optional UI toggle was not completed by the automation in the session. It is included here for the administrator to apply manually. The Grafana report below uses **Logs dimensions** and does **not** require this Metrics Explorer opt-in.

## 11. Import the Grafana report inside Application Insights

Use the **existing implicit Grafana experience in Azure Portal**, not a new standalone Grafana server and not a new Managed Grafana workspace.

The supplied file is [togg-token-consumption-grafana.json](./togg-token-consumption-grafana.json). Download/save it locally using the repository browser or editor so the portal file picker can select it. No edits to that file are required by this runbook.

### 11.1 Import the dashboard

1. In Azure Portal, open **APPI-AI-PLATFORM-FOUNDRY**.
2. Select **Dashboards with Grafana** in the left menu.
3. In the embedded Grafana/gallery interface, select **New** > **Import**.
4. Choose **Upload JSON file** / the file picker.
5. Select **togg-token-consumption-grafana.json**.
6. Select **Load**.
7. Use title **TOGG Foundry - Input and Output Tokens**.
8. If the importer asks to resolve **Existing Azure Monitor datasource / DS_AZURE_MONITOR**, select the existing built-in/preconfigured **Azure Monitor** datasource. Do not add credentials or create a new datasource identity.
9. Verify the destination:
   - **Subscription:** `Subs-Togg-IT` / `4be00143-6ced-4790-bba8-78efc2c755fd`
   - **Resource group:** `RG-AI-APIM-FOUNDRY`
   - **Region:** `Sweden Central`
10. Select **Import** / **Save** to complete the form.
11. If the imported view is not yet saved, select **Save** / **Save As**, confirm these destination fields, and save it as a dashboard Azure resource.

The JSON dashboard UID is **`togg-foundry-token-report`**. That UID is not the name of a Grafana workspace.

### 11.2 Verify and, if necessary, map the panel datasource

1. Open the saved dashboard and select **Edit**.
2. Open each panel's **Edit** > **Query** editor.
3. Verify:
   - **Datasource:** the existing **Azure Monitor** datasource
   - **Service/query type:** **Azure Log Analytics**
   - **Resource:** **APPI-AI-PLATFORM-FOUNDRY**
   - **Resource ID:**

```text
/subscriptions/4be00143-6ced-4790-bba8-78efc2c755fd/resourceGroups/RG-AI-APIM-FOUNDRY/providers/Microsoft.Insights/components/APPI-AI-PLATFORM-FOUNDRY
```

4. Use **Table** result format for the stat/table panels and **Time series** for the trend panel.
5. Keep `timestamp` as the time column and the supplied `customMetrics` queries/macros.
6. If the importer did not resolve `${DS_AZURE_MONITOR}`, select the existing Azure Monitor datasource for every panel in the query editor and save. Do not leave an unresolved datasource placeholder.
7. Select **Apply**, then save the dashboard.

This is an Application Insights **resource-context** query, not an instruction to create a new workspace, ADX cluster, service principal, or identity connection.

### 11.3 Dashboard panels and filters

Verify these five panels:

1. **Input tokens**
2. **Output tokens**
3. **Total tokens**
4. **Input / Output over time**
5. **Input / Output by selected dimension**

Set **Time range:** Last 24 hours and **Refresh:** 1 minute.

Use:

- **Model:** All, DeepSeek V4.1 Flash, or Kimi K3.1 Pro.
- **Break down by:** Model, Subscription, API, Region, Service ID, Service name, or Service type.

The session validated all 19 panel/dimension/model query variants against live telemetry. Compare the chart/table totals with Application Insights Logs for the same time range.

### 11.4 Ensure it appears in the App Insights gallery

Dashboards created/imported **inside Application Insights** receive the gallery tag automatically. If the dashboard was imported through the top-level **Azure Monitor** gallery instead:

1. Open the saved dashboard Azure resource.
2. Select **Tags**.
3. Add:
   - **Name:** `GrafanaDashboardResourceType`
   - **Value:** `microsoft.insights/components`
4. Save.
5. Return to **APPI-AI-PLATFORM-FOUNDRY** > **Dashboards with Grafana** and refresh **Saved dashboards**.

The ordinary JSON tags such as `TOGG` and `tokens` do not replace this Azure resource tag.

Dashboard readers/editors and the existing Azure Monitor datasource permissions are assumed preconfigured. A dashboard share link does not grant access to its underlying Application Insights data.

## 12. Portal validation and operational checks

### 12.1 Test both models from APIM

1. Open **TOGG-AI-PLATFORM-APIM** > **APIs** > **togg-foundry-02-openai**.
2. Select **azure-chat-completions** > **Test**.
3. Enter deployment name **DeepSeek-V4.1-Flash-1017**.
4. Add query parameter **api-version = 2024-10-21**.
5. Select the shared or DeepSeek product subscription, or set its actual `Ocp-Apim-Subscription-Key` header.
6. Set **Content-Type = application/json**.
7. Paste:

```json
{
  "messages": [{"role": "user", "content": "Say hello briefly."}],
  "max_tokens": 128
}
```

8. Select **Send**.
9. Expect **200**, a chat-completion response, usage totals, and:
   - `x-ai-content-safety: passed`
   - `x-tokens-consumed`
   - `x-ratelimit-remaining-tokens`
   - `x-ratelimit-remaining-daily-tokens`
10. Repeat with **Kimi-K3.1-Pro** and the shared/Kimi product key.
11. Repeat on the original per-model **chat-completions** operations.

The shared URL selects the deployment from the path; a body `model` field is not required.

### 12.2 Validate access and safety

Use the APIM Test tab with real product-scoped keys:

| Test | Expected result |
|---|---|
| Missing/invalid subscription key | `401` |
| DeepSeek key used for Kimi on the shared API | `403 model_not_allowed` |
| Kimi key used for DeepSeek on the shared API | `403 model_not_allowed` |
| Unsupported deployment name | `404 deployment_not_found` |
| Malformed JSON/messages/streaming options | `400 invalid_request_body` |
| Detected user/document prompt attack | `403 prompt_attack_detected` |
| Moderation severity 1-7 | `403 content_blocked` |
| More than 10,000 Unicode code points of collected text | `403 content_safety_input_limit` |
| Content Safety outage/authentication/invalid response | `503 content_safety_unavailable`; no generation |
| Valid image-only/non-text request | Safety header `no-text`; existing model guardrails still apply |

Use only harmless verification prompts. Do not produce harmful content just to exercise the filters.

### 12.3 Streaming

In the Test request body, add:

```json
{
  "messages": [{"role": "user", "content": "Reply with exactly OK."}],
  "max_tokens": 128,
  "stream": true,
  "stream_options": {"include_usage": true}
}
```

Verify **200**, SSE content type, completion, and a final usage record. The policy forces `include_usage: true` even if the client supplied false.

A client interruption can make streaming token telemetry incomplete. Do not classify missing final usage on an interrupted stream as zero consumption.

### 12.4 Administrator checklist

- [ ] Correct directory, subscription, resource group, account and `proj-default`.
- [ ] Both exact native deployments are Succeeded, with recorded allocation and DefaultV2.
- [ ] Foundry remains private and API-key authentication remains enabled.
- [ ] Dedicated Content Safety S0 endpoint is reachable and keyed; no managed identity added.
- [ ] Both backend keys are secret named values, never literal XML/dashboard values.
- [ ] All three APIs require subscription keys and have the correct operations.
- [ ] All three products are published, require subscriptions and do not require approval.
- [ ] Product/API associations and three active subscription scopes are correct.
- [ ] Original keys cannot access the other model through the shared API.
- [ ] All API diagnostics use the correct Application Insights connection, metrics and 100% sampling.
- [ ] No prompt/response bodies or credential headers are logged.
- [ ] Actual token limits/quotas/headers and safety fragment are effective on every route.
- [ ] Both non-stream and stream requests work; unknown models and unsafe/unavailable checks fail explicitly.
- [ ] Grafana JSON imported into the existing App Insights Grafana experience, datasource resolved and dashboard saved.
- [ ] Model and dimension filters return correct Input/Output totals without duplicate counting.

## Appendix A: Content Safety fragment

Paste this entire block into **Policy fragments** > **foundry02-key-content-safety**. XML entities such as `&lt;` and `&amp;` are intentional in attribute expressions.

```xml
<fragment>
  <set-variable name="foundry02-safety-completed" value="@(false)" />
  <set-variable id="safety-input" name="foundry02-safety-input" value='@{
    var body = context.Request.Body.As&lt;JObject&gt;(preserveContent: true);
    var messages = body["messages"] as JArray;
    if (messages == null || messages.Count == 0) { throw new Exception("messages must be a nonempty array"); }
    var texts = new List&lt;string&gt;();
    var docs = new List&lt;string&gt;();
    foreach (var entry in messages) {
      var message = entry as JObject;
      if (message == null) { throw new Exception("message entries must be objects"); }
      var pieces = new List&lt;string&gt;();
      var content = message["content"];
      if (content != null &amp;&amp; content.Type != JTokenType.Null) {
        if (content.Type == JTokenType.String) { pieces.Add((string)content); }
        else if (content.Type == JTokenType.Array) {
          foreach (var token in (JArray)content) {
            var part = token as JObject;
            if (part == null) { throw new Exception("content parts must be objects"); }
            if ((string)part["type"] == "text") {
              if (part["text"] == null || part["text"].Type != JTokenType.String) { throw new Exception("text content must be a string"); }
              pieces.Add((string)part["text"]);
            }
          }
        } else { throw new Exception("content must be text, an array, or null"); }
      }
      var text = string.Join("\n", pieces);
      if (!string.IsNullOrWhiteSpace(text)) {
        texts.Add(text);
        if ((string)message["role"] != "user") { docs.Add(text); }
      }
    }
    var all = string.Join("\n", texts);
    var count = 0;
    for (var i = 0; i &lt; all.Length; i++) {
      if (char.IsHighSurrogate(all[i]) &amp;&amp; i + 1 &lt; all.Length &amp;&amp; char.IsLowSurrogate(all[i + 1])) { i++; }
      count++;
    }
    var documents = new JArray();
    if (docs.Count &gt; 0) { documents.Add(string.Join("\n", docs)); }
    var result = new JObject();
    result["text"] = all; result["documents"] = documents; result["codePoints"] = count;
    return result.ToString();
  }' />
  <choose>
    <when condition='@((int)JObject.Parse((string)context.Variables["foundry02-safety-input"])["codePoints"] &gt; 10000)'>
      <return-response>
        <set-status code="403" reason="Request rejected" />
        <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
        <set-body>{"error":{"code":"content_safety_input_limit","message":"Text exceeds the 10000 Unicode-character Content Safety limit."}}</set-body>
      </return-response>
    </when>
  </choose>
  <choose>
    <when condition='@(!string.IsNullOrWhiteSpace((string)JObject.Parse((string)context.Variables["foundry02-safety-input"])["text"]))'>
      <send-request id="safety-analyze" mode="new" response-variable-name="foundry02-moderation" timeout="20" ignore-error="false">
        <set-url>https://togg-ai-platform-content-safety-02.cognitiveservices.azure.com/contentsafety/text:analyze?api-version=2024-09-01</set-url>
        <set-method>POST</set-method>
        <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
        <set-header name="Ocp-Apim-Subscription-Key" exists-action="override"><value>{{foundry02-content-safety-key}}</value></set-header>
        <set-body><![CDATA[@{
          var input = JObject.Parse((string)context.Variables["foundry02-safety-input"]);
          var request = new JObject(); request["text"] = input["text"];
          request["categories"] = new JArray("Hate", "SelfHarm", "Sexual", "Violence");
          request["outputType"] = "EightSeverityLevels"; return request.ToString();
        }]]></set-body>
      </send-request>
      <set-variable id="safety-moderation-schema" name="foundry02-moderation-valid" value='@{
        var response = context.Variables["foundry02-moderation"] as IResponse;
        if (response == null || response.StatusCode != 200) { return false; }
        var analysis = response.Body.As&lt;JObject&gt;(preserveContent: true)["categoriesAnalysis"] as JArray;
        if (analysis == null || analysis.Count != 4) { return false; }
        var seen = new List&lt;string&gt;();
        foreach (var entry in analysis) {
          var item = entry as JObject;
          if (item == null || item["category"] == null || item["severity"] == null || item["severity"].Type != JTokenType.Integer) { return false; }
          var category = (string)item["category"];
          if (category != "Hate" &amp;&amp; category != "SelfHarm" &amp;&amp; category != "Sexual" &amp;&amp; category != "Violence") { return false; }
          if (seen.Contains(category)) { return false; } seen.Add(category);
          var severity = (int)item["severity"];
          if (severity &lt; 0 || severity &gt; 7) { return false; }
        }
        return true;
      }' />
      <choose>
        <when condition='@(!(bool)context.Variables["foundry02-moderation-valid"])'>
          <return-response>
            <set-status code="503" reason="Content Safety unavailable" />
            <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
            <set-body>{"error":{"code":"content_safety_unavailable","message":"Content Safety could not complete text moderation."}}</set-body>
          </return-response>
        </when>
      </choose>
      <choose>
        <when condition='@{
          var analysis = ((IResponse)context.Variables["foundry02-moderation"]).Body.As&lt;JObject&gt;(preserveContent: true)["categoriesAnalysis"] as JArray;
          foreach (var item in analysis) { if ((int)item["severity"] &gt;= 1) { return true; } }
          return false;
        }'>
          <return-response>
            <set-status code="403" reason="Request rejected" />
            <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
            <set-body>{"error":{"code":"content_blocked","message":"The prompt was blocked by Content Safety."}}</set-body>
          </return-response>
        </when>
      </choose>
      <send-request id="safety-shield" mode="new" response-variable-name="foundry02-shields" timeout="20" ignore-error="false">
        <set-url>https://togg-ai-platform-content-safety-02.cognitiveservices.azure.com/contentsafety/text:shieldPrompt?api-version=2024-09-01</set-url>
        <set-method>POST</set-method>
        <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
        <set-header name="Ocp-Apim-Subscription-Key" exists-action="override"><value>{{foundry02-content-safety-key}}</value></set-header>
        <set-body><![CDATA[@{
          var input = JObject.Parse((string)context.Variables["foundry02-safety-input"]);
          var request = new JObject(); request["userPrompt"] = input["text"]; request["documents"] = input["documents"];
          return request.ToString();
        }]]></set-body>
      </send-request>
      <set-variable id="safety-shield-schema" name="foundry02-shields-valid" value='@{
        var response = context.Variables["foundry02-shields"] as IResponse;
        if (response == null || response.StatusCode != 200) { return false; }
        var body = response.Body.As&lt;JObject&gt;(preserveContent: true);
        var user = body["userPromptAnalysis"] as JObject;
        if (user == null || user["attackDetected"] == null || user["attackDetected"].Type != JTokenType.Boolean) { return false; }
        var input = JObject.Parse((string)context.Variables["foundry02-safety-input"]);
        var documents = input["documents"] as JArray;
        if (documents.Count &gt; 0) {
          var analyses = body["documentsAnalysis"] as JArray;
          if (analyses == null || analyses.Count != documents.Count) { return false; }
          foreach (var item in analyses) {
            if (item["attackDetected"] == null || item["attackDetected"].Type != JTokenType.Boolean) { return false; }
          }
        }
        return true;
      }' />
      <choose>
        <when condition='@(!(bool)context.Variables["foundry02-shields-valid"])'>
          <return-response>
            <set-status code="503" reason="Content Safety unavailable" />
            <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
            <set-body>{"error":{"code":"content_safety_unavailable","message":"Content Safety could not complete prompt-shield checks."}}</set-body>
          </return-response>
        </when>
      </choose>
      <choose>
        <when condition='@{
          var body = ((IResponse)context.Variables["foundry02-shields"]).Body.As&lt;JObject&gt;(preserveContent: true);
          if ((bool)body["userPromptAnalysis"]["attackDetected"]) { return true; }
          var documents = body["documentsAnalysis"] as JArray;
          if (documents != null) { foreach (var item in documents) { if ((bool)item["attackDetected"]) { return true; } } }
          return false;
        }'>
          <return-response>
            <set-status code="403" reason="Request rejected" />
            <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
            <set-body>{"error":{"code":"prompt_attack_detected","message":"The prompt was blocked by prompt shields."}}</set-body>
          </return-response>
        </when>
      </choose>
      <set-variable name="foundry02-safety-completed" value="@(true)" />
    </when>
  </choose>
</fragment>
```

## Appendix B: shared API policy

Paste this complete policy into **togg-foundry-02-openai** > **All operations**. For the two per-model APIs, make only the fixed-model substitution described in [section 8.2](#82-per-model-api-policies).

```xml
<policies>
  <inbound>
    <base />
    <set-header name="Authorization" exists-action="delete" />
    <set-header name="api-key" exists-action="delete" />
    <set-header name="Ocp-Apim-Subscription-Key" exists-action="delete" />
    <set-query-parameter name="subscription-key" exists-action="delete" />
    <set-variable id="client-model" name="selected-model" value='@{
      var requested = context.Request.MatchedParameters.ContainsKey("deployment-name") ? context.Request.MatchedParameters["deployment-name"] : (string)context.Request.Body.As&lt;JObject&gt;(preserveContent: true)["model"];
      if (string.Equals(requested, "DeepSeek-V4.1-Flash-1017", StringComparison.OrdinalIgnoreCase)) { return "DeepSeek-V4.1-Flash-1017"; }
      if (string.Equals(requested, "Kimi-K3.1-Pro", StringComparison.OrdinalIgnoreCase) || string.Equals(requested, "Kimi-K3.1", StringComparison.OrdinalIgnoreCase)) { return "Kimi-K3.1-Pro"; }
      return "";
    }' />
    <choose>
      <when condition='@(string.IsNullOrEmpty((string)context.Variables["selected-model"]))'>
        <return-response>
          <set-status code="404" reason="Request rejected" />
          <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
          <set-body>{"error":{"code":"deployment_not_found","message":"This API exposes only the deployed DeepSeek and Kimi models."}}</set-body>
        </return-response>
      </when>
    </choose>
    <choose>
      <when condition='@{
        if (context.Product == null) { return false; }
        var product = context.Product.Id; var model = (string)context.Variables["selected-model"];
        if (product == "deepseek-v4-1") { return model != "DeepSeek-V4.1-Flash-1017"; }
        if (product == "kimi-k3-1-pro") { return model != "Kimi-K3.1-Pro"; }
        return product != "togg-foundry-02-models";
      }'>
        <return-response>
          <set-status code="403" reason="Request rejected" />
          <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
          <set-body>{"error":{"code":"model_not_allowed","message":"Your subscription is not enabled for this model."}}</set-body>
        </return-response>
      </when>
    </choose>
    <set-variable id="client-body" name="foundry02-generation-body" value='@{
      var body = context.Request.Body.As&lt;JObject&gt;(preserveContent: true);
      body["model"] = (string)context.Variables["selected-model"];
      if ((bool?)body["stream"] == true) {
        var token = body["stream_options"];
        var options = token == null || token.Type == JTokenType.Null ? new JObject() : (JObject)token;
        options["include_usage"] = true; body["stream_options"] = options;
      }
      return body.ToString();
    }' />
    <set-body>@((string)context.Variables["foundry02-generation-body"])</set-body>
    <rate-limit-by-key calls='@((string)context.Variables["selected-model"] == "DeepSeek-V4.1-Flash-1017" ? 10000 : 5000)' renewal-period="60" counter-key='@("foundry02-rpm:" + context.Subscription.Id + ":" + (string)context.Variables["selected-model"])' />
    <llm-token-limit counter-key='@("foundry02-tokens:" + context.Subscription.Id)' tokens-per-minute="100000" token-quota="1000000" token-quota-period="Daily" estimate-prompt-tokens="false" tokens-consumed-header-name="x-tokens-consumed" remaining-tokens-header-name="x-ratelimit-remaining-tokens" remaining-quota-tokens-header-name="x-ratelimit-remaining-daily-tokens" />
    <include-fragment fragment-id="foundry02-key-content-safety" />
    <llm-emit-token-metric namespace="togg-foundry-models">
      <dimension name="API ID" />
      <dimension name="Subscription ID" />
      <dimension name="Model" value='@((string)context.Variables["selected-model"])' />
    </llm-emit-token-metric>
    <set-backend-service base-url="https://togg-ai-platform-foundry-02.services.ai.azure.com/openai/v1" />
    <rewrite-uri template="/chat/completions" copy-unmatched-params="false" />
    <set-body id="generation-body-restore">@((string)context.Variables["foundry02-generation-body"])</set-body>
    <set-header name="Authorization" exists-action="delete" />
    <set-header name="Ocp-Apim-Subscription-Key" exists-action="delete" />
    <set-header name="api-key" exists-action="delete" />
    <set-header name="api-key" exists-action="override"><value>{{deepseek-v4-1-foundry-key}}</value></set-header>
    <set-query-parameter name="api-version" exists-action="delete" />
  </inbound>
  <backend>
    <retry condition='@(context.Response != null &amp;&amp; context.Response.StatusCode == 404 &amp;&amp; (string)context.Variables["selected-model"] == "Kimi-K3.1-Pro")' count="1" interval="1" first-fast-retry="true">
      <forward-request buffer-response="false" buffer-request-body="true" />
    </retry>
  </backend>
  <outbound>
    <base />
    <set-header name="x-ai-content-safety" exists-action="override">
      <value>@(!context.Variables.ContainsKey("foundry02-safety-completed") ? "not-checked" : ((bool)context.Variables["foundry02-safety-completed"] ? "passed" : "no-text"))</value>
    </set-header>
  </outbound>
  <on-error>
    <base />
    <choose>
      <when condition='@((context.LastError.PolicyId ?? "").StartsWith("safety-") &amp;&amp; context.LastError.PolicyId != "safety-input")'>
        <return-response>
          <set-status code="503" reason="Content Safety unavailable" />
          <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
          <set-body>{"error":{"code":"content_safety_unavailable","message":"Content Safety checks could not be completed."}}</set-body>
        </return-response>
      </when>
    </choose>
    <choose>
      <when condition='@(context.LastError.PolicyId == "client-model" || context.LastError.PolicyId == "client-body" || context.LastError.PolicyId == "safety-input")'>
        <return-response>
          <set-status code="400" reason="Request rejected" />
          <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
          <set-body>{"error":{"code":"invalid_request_body","message":"Provide valid JSON messages and valid streaming options."}}</set-body>
        </return-response>
      </when>
    </choose>
  </on-error>
</policies>
```

## References

- [Deploy Foundry models in the portal](https://learn.microsoft.com/azure/foundry/foundry-models/how-to/deploy-foundry-models)
- [APIM token limits and quotas](https://learn.microsoft.com/azure/api-management/llm-token-limit-policy)
- [APIM token-consumption metrics](https://learn.microsoft.com/azure/api-management/llm-emit-token-metric-policy)
- [APIM and Application Insights integration](https://learn.microsoft.com/azure/api-management/api-management-howto-app-insights)
- [Native APIM Content Safety policy and managed-identity prerequisites](https://learn.microsoft.com/azure/api-management/llm-content-safety-policy)
- [Content Safety Analyze Text REST contract](https://learn.microsoft.com/rest/api/contentsafety/text-operations/analyze-text?view=rest-contentsafety-2024-09-01)
- [Content Safety Prompt Shields REST contract](https://learn.microsoft.com/rest/api/contentsafety/text-operations/shield-prompt?view=rest-contentsafety-2024-09-01)
- [Dashboards with Grafana in Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/grafana-dashboards)
- [Azure Monitor Grafana dashboard JSON import and save](https://learn.microsoft.com/azure/azure-monitor/visualize/visualize-use-grafana-dashboards)
