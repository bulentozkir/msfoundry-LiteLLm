#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\ApimTestHelpers.ps1"

$keys = Get-TerraformOutput -Name "apim_subscription_keys"
$endpoints = Get-TerraformOutput -Name "apim_model_endpoints"
$products = Get-TerraformOutput -Name "apim_model_product_ids"
$backends = Get-TerraformOutput -Name "apim_model_backend_ids"
$foundryAccountId = Get-TerraformOutput -Name "foundry_account_id"
$models = @("Gpt5.4mini", "Phi", "FW-DeepSeek-V4.1-Flash")
$portalSandboxOrigin = "https://sandbox-3.reactblade-ms.portal.azure.net"
$portalOrigins = @(
    "https://ms.portal.azure.com"
    "https://portal.azure.com"
    $portalSandboxOrigin
    "https://sandbox-17.reactblade.portal.azure.net"
)
$untrustedOrigins = @(
    "https://untrusted.example"
    "https://sandbox-3.reactblade-ms.portal.azure.net.untrusted.example"
    "https://sandbox-3.reactblade-ms.portal.azure.net:444"
    "http://sandbox-3.reactblade-ms.portal.azure.net"
    "https://sandbox-x.reactblade-ms.portal.azure.net"
)
$portalEndpoints = @{}

if ($keys.Count -ne 3 -or $endpoints.Count -ne 3 -or $products.Count -ne 3 -or $backends.Count -ne 3) {
    throw "Expected exactly three API subscription keys, model endpoints, model products, and model backends."
}
if (@($keys.Values | Sort-Object -Unique).Count -ne 3) {
    throw "The three model APIs must use distinct subscription keys."
}

$managementToken = az account get-access-token --resource "https://management.azure.com/" `
    --query accessToken --output tsv --only-show-errors
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($managementToken)) {
    throw "Cannot acquire an ARM token. Verify the Azure CLI login."
}
$managementHeaders = @{ Authorization = "Bearer $managementToken"; Accept = "application/json" }
Remove-Variable managementToken

foreach ($model in $models) {
    if ([string]::IsNullOrWhiteSpace($keys[$model]) -or [string]::IsNullOrWhiteSpace($endpoints[$model]) -or
        [string]::IsNullOrWhiteSpace($products[$model]) -or [string]::IsNullOrWhiteSpace($backends[$model])) {
        throw "The subscription key, endpoint, product, or backend for '$model' is missing."
    }

    $product = Get-ApimManagementResource -ResourceId $products[$model]
    $productApis = Get-ApimManagementResource -ResourceId "$($products[$model])/apis"
    $productGroups = Get-ApimManagementResource -ResourceId "$($products[$model])/groups"
    $apiName = ([uri]$endpoints[$model]).AbsolutePath.Split("/")[1]
    $groupNames = @($productGroups.value | ForEach-Object { $_.name })
    if ($product.properties.state -ne "published" -or !$product.properties.subscriptionRequired -or
        !$product.properties.approvalRequired -or $product.properties.subscriptionsLimit -ne 1 -or
        $productApis.nextLink -or @($productApis.value).Count -ne 1 -or
        $productApis.value[0].name -ne $apiName -or $productGroups.nextLink -or
        "developers" -notin $groupNames -or @($groupNames | Where-Object { $_ -notin @("developers", "administrators") }).Count -gt 0) {
        throw "$model product is not published, protected, or isolated to the intended API/developer visibility."
    }
    Write-Host "PASS: $model product exposes only $apiName; subscriptions require approval, with one per developer."

    $apiId = $backends[$model] -replace "/backends/[^/]+$", "/apis/$apiName"
    $api = Get-ApimManagementResource -ResourceId $apiId
    $backend = Get-ApimManagementResource -ResourceId $backends[$model] -ApiVersion "2025-09-01-preview"
    $policy = Get-ApimManagementResource -ResourceId "$apiId/policies/policy"
    $policyXml = [xml]$policy.properties.value
    $backendReferences = $policyXml.SelectNodes("/policies/inbound/set-backend-service")
    $identity = $policyXml.SelectSingleNode("/policies/inbound/authentication-managed-identity")
    $expectedBackendPath = if ($model -eq "Gpt5.4mini") { "openai/v1" } else { "models" }
    $expectedBackendUrl = "https://$($foundryAccountId.Split('/')[-1]).services.ai.azure.com/$expectedBackendPath"
    if ($backendReferences.Count -ne 1 -or
        $backendReferences[0].GetAttribute("id") -ne "apim-generated-policy" -or
        $backendReferences[0].GetAttribute("backend-id") -ne $apiName -or
        $backend.properties.url -ne $expectedBackendUrl -or $api.properties.serviceUrl -ne $expectedBackendUrl -or
        $backend.properties.protocol -ne "http" -or
        $backend.properties.resourceId -ne "https://management.azure.com$foundryAccountId" -or
        $backend.properties.credentials.managedIdentity.resource -ne "https://cognitiveservices.azure.com/" -or
        ![string]::IsNullOrWhiteSpace($backend.properties.credentials.managedIdentity.clientId) -or
        !$identity -or $identity.GetAttribute("resource") -ne "https://cognitiveservices.azure.com/" -or
        $identity.GetAttribute("ignore-error") -ne "false" -or
        $backend.properties.tls.validateCertificateChain -eq $false -or
        $backend.properties.tls.validateCertificateName -eq $false) {
        throw "$model has an incorrect portal backend reference, Foundry URL, managed-identity setting, or TLS validation setting."
    }
    Write-Host "PASS: $model references backend $apiName at $expectedBackendUrl using the APIM system-assigned identity."

    $portalEndpoints[$model] = $endpoints[$model] -replace "/chat/completions$", "/deployments/$([uri]::EscapeDataString($model))/chat/completions"
    foreach ($uri in @($endpoints[$model], $portalEndpoints[$model])) {
        foreach ($origin in $portalOrigins) {
            Assert-CorsPreflight -Uri $uri -Origin $origin -Allowed $true
        }
        foreach ($origin in $untrustedOrigins) {
            Assert-CorsPreflight -Uri $uri -Origin $origin -Allowed $false
        }
    }

    $payload = @{
        model = $model
        messages = @(@{
            role = "user"
            content = "Reply with exactly the single word READY."
        })
        stream = $false
    }
    $allowedModels = switch ($model) {
        "Gpt5.4mini" {
            $payload.max_completion_tokens = 512
            $payload.reasoning_effort = "low"
            @("Gpt5.4mini", "gpt-5.4-mini", "gpt-5.4-mini-2026-03-17")
        }
        "Phi" {
            $payload.max_tokens = 64
            @("Phi", "Phi-4", "phi4")
        }
        "FW-DeepSeek-V4.1-Flash" {
            $payload.max_tokens = 256
            @("FW-DeepSeek-V4.1-Flash", "DeepSeek-V4-Flash")
        }
    }

    $body = $payload | ConvertTo-Json -Depth 6 -Compress
    $headers = @{ "Ocp-Apim-Subscription-Key" = $keys[$model] }

    $null = Assert-HttpStatus -Name "$model without a key" -Uri $endpoints[$model] `
        -Body $body -ExpectedStatus 401
    $null = Assert-HttpStatus -Name "$model portal route without a key" -Uri $portalEndpoints[$model] `
        -Body $body -ExpectedStatus 401

    foreach ($otherModel in $models | Where-Object { $_ -ne $model }) {
        $otherHeaders = @{ "Ocp-Apim-Subscription-Key" = $keys[$otherModel] }
        $null = Assert-HttpStatus -Name "$otherModel key cannot access $model API" `
            -Uri $endpoints[$model] -Body $body -Headers $otherHeaders -ExpectedStatus 401
        $null = Assert-HttpStatus -Name "$otherModel key cannot access $model portal route" `
            -Uri $portalEndpoints[$model] -Body $body -Headers $otherHeaders -ExpectedStatus 401

        $payload.model = $otherModel
        $overrideBody = $payload | ConvertTo-Json -Depth 6 -Compress
        $null = Assert-HttpStatus -Name "$model API rejects a $otherModel body override" `
            -Uri $endpoints[$model] -Body $overrideBody -Headers $headers -ExpectedStatus 400
    }
    $payload.model = $model

    $null = Assert-HttpStatus -Name "$model malformed JSON" -Uri $endpoints[$model] `
        -Body "{invalid-json" -Headers $headers -ExpectedStatus 400

    $spoofedModel = ($models | Where-Object { $_ -ne $model } | Select-Object -First 1)
    $wrongDeploymentUri = $endpoints[$model] -replace "/chat/completions$", "/deployments/$([uri]::EscapeDataString($spoofedModel))/chat/completions"
    $null = Assert-HttpStatus -Name "$model portal route does not expose $spoofedModel" `
        -Uri $wrongDeploymentUri -Body $body -Headers $headers -ExpectedStatus 404
    $headers["x-ms-model-mesh-model-name"] = $spoofedModel
    $headers["azureml-model-deployment"] = $spoofedModel
    $uri = "$($endpoints[$model])?model=$([uri]::EscapeDataString($spoofedModel))&api-version=invalid-version"
    $response = Assert-HttpStatus -Name "$model completion ignores routing-header/query overrides" `
        -Uri $uri -Body $body -Headers $headers -ExpectedStatus 200 -RetryTransient
    $completion = $response.Content | ConvertFrom-Json
    if ($completion.model -notin $allowedModels) {
        throw "$model API returned an unexpected backend model '$($completion.model)'."
    }
    if ([string]::IsNullOrWhiteSpace($completion.choices[0].message.content)) {
        throw "$model API returned HTTP 200 without an assistant answer."
    }
    Write-Host "PASS: $model reached expected backend '$($completion.model)' with an assistant answer."

    $portalResponse = Assert-HttpStatus -Name "$model Azure Portal completion" -Uri $portalEndpoints[$model] `
        -Body $body -Headers @{ "Ocp-Apim-Subscription-Key" = $keys[$model]; Origin = $portalSandboxOrigin } `
        -ExpectedStatus 200 -RetryTransient
    if (($portalResponse.Headers["Access-Control-Allow-Origin"] -join ",") -ne $portalSandboxOrigin) {
        throw "$model returned a completion without the required Azure Portal CORS response header."
    }
    Write-Host "PASS: $model completion is readable by the Azure Portal browser."

    $streamPayload = @{
        model = $model
        messages = @(@{
            role = "user"
            content = "Reply with exactly the single word READY."
        })
        temperature = 0.7
        max_completion_tokens = 800
        top_p = 1
        stream = $true
    } | ConvertTo-Json -Depth 6 -Compress
    $portalRequestUri = "$($portalEndpoints[$model])?subscription-key=$([uri]::EscapeDataString($keys[$model]))"
    $streamResponse = Assert-HttpStatus -Name "$model portal-style query-key streaming" `
        -Uri $portalRequestUri -Body $streamPayload `
        -Headers @{ Origin = $portalSandboxOrigin } `
        -ExpectedStatus 200 -RetryTransient
    $chunks = @($streamResponse.Content -split "\r?\n" |
        Where-Object { $_ -match '^data:\s*\{' } |
        ForEach-Object { ($_ -replace '^data:\s*', '') | ConvertFrom-Json })
    if ($streamResponse.Headers["Content-Type"] -notmatch "text/event-stream" -or
        $streamResponse.Content -notmatch "data:\s*\[DONE\]" -or
        ($streamResponse.Headers["Access-Control-Allow-Origin"] -join ",") -ne $portalSandboxOrigin -or
        @($chunks | Where-Object { $_.model -and $_.model -notin $allowedModels }).Count -gt 0 -or
        [string]::IsNullOrWhiteSpace(($chunks.choices.delta.content -join ""))) {
        throw "$model did not return a complete, browser-readable stream from its expected model with an assistant answer."
    }
    Write-Host "PASS: $model returned an assistant answer in a complete portal-style server-sent event stream."
}

Remove-Variable keys, managementHeaders, portalRequestUri
Write-Host "PASS: all three model products/backends, Azure Portal CORS, subscription boundaries, request validation, routing protection, and streaming."
