#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\..\apim-only\tests\ApimTestHelpers.ps1"

$key = Get-TerraformOutput -Name "runtime_api_key"
$endpoint = Get-TerraformOutput -Name "chat_completions_endpoint"
$models = @(Get-TerraformOutput -Name "model_deployments")

if ([string]::IsNullOrWhiteSpace($key) -or [string]::IsNullOrWhiteSpace($endpoint) -or
    $models.Count -ne 3 -or @($models | Sort-Object -Unique).Count -ne 3) {
    throw "Apply the enabled AI Gateway root first; expected one runtime key, one endpoint, and three distinct deployments."
}

$headers = @{ "api-key" = $key }
$basicBody = @{
    model = "Phi"
    messages = @(@{ role = "user"; content = "Reply READY." })
    max_tokens = 32
} | ConvertTo-Json -Depth 6 -Compress

$null = Assert-HttpStatus -Name "Missing runtime key" -Uri $endpoint -Body $basicBody -ExpectedStatus 401
$null = Assert-HttpStatus -Name "Invalid runtime key" -Uri $endpoint -Body $basicBody `
    -Headers @{ "api-key" = "invalid-test-key" } -ExpectedStatus 401
$null = Assert-HttpStatus -Name "Subscription header is not a runtime key" -Uri $endpoint -Body $basicBody `
    -Headers @{ "Ocp-Apim-Subscription-Key" = $key } -ExpectedStatus 401

foreach ($model in $models) {
    $payload = @{
        model = $model
        messages = @(@{ role = "user"; content = "Reply with exactly the single word READY." })
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
        default { throw "Unexpected deployment '$model'." }
    }

    $body = $payload | ConvertTo-Json -Depth 6 -Compress
    $response = Assert-HttpStatus -Name "$model completion with the shared runtime key" `
        -Uri $endpoint -Body $body -Headers $headers -ExpectedStatus 200 -RetryTransient
    $completion = $response.Content | ConvertFrom-Json
    if ($completion.object -ne "chat.completion" -or $completion.choices.Count -lt 1 -or
        [string]::IsNullOrWhiteSpace($completion.choices[0].message.content) -or
        $completion.model -notin $allowedModels) {
        throw "$model did not return a valid, nonempty chat completion from the expected model."
    }

    $payload.stream = $true
    $body = $payload | ConvertTo-Json -Depth 6 -Compress
    $stream = Assert-HttpStatus -Name "$model streaming with the shared runtime key" `
        -Uri $endpoint -Body $body -Headers $headers -ExpectedStatus 200 -RetryTransient
    if ($stream.Content -notmatch "data:" -or $stream.Content -notmatch "\[DONE\]") {
        throw "$model did not return a complete server-sent-event stream."
    }
}

$unknownBody = @{
    model = "not-a-registered-model"
    messages = @(@{ role = "user"; content = "Reply READY." })
    max_tokens = 32
} | ConvertTo-Json -Depth 6 -Compress
$unknown = Invoke-WebRequest -Uri $endpoint -Method Post -Headers $headers -ContentType "application/json" `
    -Body $unknownBody -SkipHttpErrorCheck -TimeoutSec 60
if ([int]$unknown.StatusCode -notin @(400, 404)) {
    throw "An unregistered model was not rejected with HTTP 400 or 404: HTTP $([int]$unknown.StatusCode)."
}
Write-Host "PASS: Unregistered model rejected (HTTP $([int]$unknown.StatusCode))."
Write-Host "PASS: All three models use the same gateway-wide key; this tier does not provide per-model key isolation."
