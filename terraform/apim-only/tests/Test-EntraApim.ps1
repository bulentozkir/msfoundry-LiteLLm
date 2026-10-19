#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$AccessToken,
    [string[]]$ExpectedRoles = @("Model.Gpt.Invoke", "Model.Phi.Invoke", "Model.DeepSeek.Invoke")
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ApimTestHelpers.ps1"

$authentication = Get-TerraformOutput -Name "apim_entra_authentication"
$endpoints = Get-TerraformOutput -Name "apim_entra_model_endpoints"
$keyEndpoints = Get-TerraformOutput -Name "apim_model_endpoints"
$keys = Get-TerraformOutput -Name "apim_subscription_keys"
$backends = Get-TerraformOutput -Name "apim_model_backend_ids"
$models = @("Gpt5.4mini", "Phi", "FW-DeepSeek-V4.1-Flash")
$origin = "https://sandbox-3.reactblade-ms.portal.azure.net"

if ([string]::IsNullOrWhiteSpace($AccessToken)) {
    $AccessToken = az account get-access-token --tenant $authentication.tenant_id `
        --scope "$($authentication.resource_uri)/.default" --query accessToken --output tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($AccessToken)) {
        throw "Cannot acquire a gateway access token. Check the role assignment, client preauthorization, and Azure CLI sign-in."
    }
}

$parts = $AccessToken.Split(".")
if ($parts.Count -ne 3) {
    throw "The supplied access token is not a JWT."
}
$encodedClaims = $parts[1].Replace("-", "+").Replace("_", "/")
$encodedClaims = $encodedClaims.PadRight($encodedClaims.Length + ((4 - $encodedClaims.Length % 4) % 4), "=")
$claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedClaims)) | ConvertFrom-Json
if ($claims.tid -ne $authentication.tenant_id -or $claims.aud -ne $authentication.client_id -or
    $claims.ver -ne "2.0" -or [long]$claims.exp -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -or
    @(Compare-Object -ReferenceObject @($ExpectedRoles | Sort-Object) -DifferenceObject @($claims.roles | Sort-Object)).Count -ne 0) {
    throw "The acquired token does not have the expected tenant, gateway audience, version, expiry, or exact model roles."
}
Write-Host "PASS: acquired a gateway-audience v2 access token with exactly the expected model roles."

$managementToken = az account get-access-token --resource "https://management.azure.com/" `
    --query accessToken --output tsv --only-show-errors
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($managementToken)) {
    throw "Cannot acquire an ARM token for live configuration verification."
}
$managementHeaders = @{ Authorization = "Bearer $managementToken"; Accept = "application/json" }
$signature = if ($parts[2][0] -eq "A") { "B" } else { "A" }
$invalidSignatureToken = "$($parts[0]).$($parts[1]).$signature$($parts[2].Substring(1))"

foreach ($model in $models) {
    $role = $authentication.model_roles[$model].value
    $apiName = "$(([uri]$keyEndpoints[$model]).AbsolutePath.Split('/')[1])-entra"
    $apiId = $backends[$model] -replace "/backends/[^/]+$", "/apis/$apiName"
    $api = Get-ApimManagementResource -ResourceId $apiId
    $policy = Get-ApimManagementResource -ResourceId "$apiId/policies/policy"
    $xml = [xml]$policy.properties.value
    $validator = $xml.SelectSingleNode("/policies/inbound/validate-azure-ad-token")
    $roleCheck = $xml.SelectSingleNode("/policies/inbound/choose/when")
    $roleCondition = [System.Net.WebUtility]::HtmlDecode($roleCheck.GetAttribute("condition"))
    $backend = $xml.SelectSingleNode("/policies/inbound/set-backend-service")
    if ($api.properties.subscriptionRequired -or $api.properties.serviceUrl -or
        $validator.GetAttribute("tenant-id") -ne $authentication.tenant_id -or
        $validator.SelectSingleNode("audiences/audience").InnerText -ne $authentication.client_id -or
        !$roleCondition.Contains("`"$role`"") -or
        $backend.GetAttribute("backend-id") -ne $apiName.Replace("-entra", "") -or
        $xml.SelectSingleNode("/policies/inbound/authentication-managed-identity").GetAttribute("resource") -ne "https://cognitiveservices.azure.com/") {
        throw "$model Entra API does not enforce the expected token/model/identity boundary."
    }
    Write-Host "PASS: $model Entra API has its own role gate and fixed managed-identity backend."

    Assert-CorsPreflight -Uri $endpoints[$model] -Origin $origin -Allowed $true
    Assert-CorsPreflight -Uri $endpoints[$model] -Origin "https://untrusted.example" -Allowed $false

    $payload = @{
        model = $model
        messages = @(@{ role = "user"; content = "Reply with only READY." })
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
    $portalUri = $endpoints[$model] -replace "/chat/completions$", "/deployments/$model/chat/completions"

    $null = Assert-HttpStatus -Name "$model Entra API rejects missing token" -Uri $endpoints[$model] -Body $body -ExpectedStatus 401
    $null = Assert-HttpStatus -Name "$model Entra API rejects a key alone" -Uri $endpoints[$model] `
        -Body $body -Headers @{ "Ocp-Apim-Subscription-Key" = $keys[$model] } -ExpectedStatus 401
    $null = Assert-HttpStatus -Name "$model Entra API rejects malformed token" -Uri $endpoints[$model] `
        -Body $body -Headers @{ Authorization = "Bearer not-a-jwt" } -ExpectedStatus 401
    $null = Assert-HttpStatus -Name "$model Entra API rejects an ARM-audience token" -Uri $endpoints[$model] `
        -Body $body -Headers $managementHeaders -ExpectedStatus 401
    $null = Assert-HttpStatus -Name "$model Entra API rejects a modified signature" -Uri $endpoints[$model] `
        -Body $body -Headers @{ Authorization = "Bearer $invalidSignatureToken" } -ExpectedStatus 401
    $null = Assert-HttpStatus -Name "$model key API still rejects a bearer token without a key" -Uri $keyEndpoints[$model] `
        -Body $body -Headers @{ Authorization = "Bearer $AccessToken" } -ExpectedStatus 401

    $headers = @{ Authorization = "Bearer $AccessToken"; Origin = $origin }
    if ($role -notin $ExpectedRoles) {
        $null = Assert-HttpStatus -Name "$model rejects a valid token without $role" -Uri $endpoints[$model] `
            -Body $body -Headers $headers -ExpectedStatus 403
        $null = Assert-HttpStatus -Name "$model portal route rejects a valid token without $role" -Uri $portalUri `
            -Body $body -Headers $headers -ExpectedStatus 403
        $null = Assert-HttpStatus -Name "$model role cannot be bypassed by adding its subscription key" -Uri $endpoints[$model] `
            -Body $body -Headers @{ Authorization = "Bearer $AccessToken"; "Ocp-Apim-Subscription-Key" = $keys[$model] } -ExpectedStatus 403
        continue
    }

    foreach ($other in $models | Where-Object { $_ -ne $model }) {
        $payload.model = $other
        $null = Assert-HttpStatus -Name "$model Entra API rejects a $other body override" -Uri $endpoints[$model] `
            -Body ($payload | ConvertTo-Json -Depth 6 -Compress) -Headers $headers -ExpectedStatus 400
    }
    $payload.model = $model
    $null = Assert-HttpStatus -Name "$model Entra API rejects malformed JSON" -Uri $endpoints[$model] `
        -Body "{invalid-json" -Headers $headers -ExpectedStatus 400

    $spoofedModel = $models | Where-Object { $_ -ne $model } | Select-Object -First 1
    $wrongDeploymentUri = $endpoints[$model] -replace "/chat/completions$", "/deployments/$spoofedModel/chat/completions"
    $null = Assert-HttpStatus -Name "$model Entra API does not expose $spoofedModel deployment route" `
        -Uri $wrongDeploymentUri -Body $body -Headers $headers -ExpectedStatus 404
    $headers["x-ms-model-mesh-model-name"] = $spoofedModel
    $headers["azureml-model-deployment"] = $spoofedModel
    $uri = "$($endpoints[$model])?model=$spoofedModel&api-version=invalid-version"
    $response = Assert-HttpStatus -Name "$model token-only completion ignores routing overrides" `
        -Uri $uri -Body $body -Headers $headers -ExpectedStatus 200 -RetryTransient
    $completion = $response.Content | ConvertFrom-Json
    if ($completion.model -notin $allowedModels -or [string]::IsNullOrWhiteSpace($completion.choices[0].message.content) -or
        ($response.Headers["Access-Control-Allow-Origin"] -join ",") -ne $origin) {
        throw "$model token-only completion did not return the expected model, answer, and CORS header."
    }
    Write-Host "PASS: $model token-only call reached its expected Foundry model with an assistant answer."

    $payload.stream = $true
    $stream = Assert-HttpStatus -Name "$model token-only deployment-route streaming" -Uri $portalUri `
        -Body ($payload | ConvertTo-Json -Depth 6 -Compress) -Headers $headers -ExpectedStatus 200 -RetryTransient
    $chunks = @($stream.Content -split "\r?\n" |
        Where-Object { $_ -match '^data:\s*\{' } |
        ForEach-Object { ($_ -replace '^data:\s*', '') | ConvertFrom-Json })
    if ($stream.Headers["Content-Type"] -notmatch "text/event-stream" -or
        $stream.Content -notmatch "data:\s*\[DONE\]" -or
        ($stream.Headers["Access-Control-Allow-Origin"] -join ",") -ne $origin -or
        @($chunks | Where-Object { $_.model -and $_.model -notin $allowedModels }).Count -gt 0 -or
        [string]::IsNullOrWhiteSpace(($chunks.choices.delta.content -join ""))) {
        throw "$model token-only request did not return a complete stream from the expected model."
    }
    Write-Host "PASS: $model token-only deployment route returned a complete assistant SSE stream."
}

Remove-Variable AccessToken, claims, encodedClaims, parts, invalidSignatureToken, managementToken, managementHeaders, keys, headers
Write-Host "PASS: all three Entra entrypoints enforce audience/signature/model roles, preserve key boundaries and routing, and support authorized chat/streaming."
