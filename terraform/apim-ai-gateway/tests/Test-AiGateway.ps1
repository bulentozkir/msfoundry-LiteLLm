#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\..\apim-only\tests\ApimTestHelpers.ps1"

$key = Get-TerraformOutput -Name "runtime_api_key"
$endpoint = Get-TerraformOutput -Name "chat_completions_endpoint"
$messagesEndpoint = Get-TerraformOutput -Name "messages_endpoint"
$models = @(Get-TerraformOutput -Name "model_deployments")

if ([string]::IsNullOrWhiteSpace($key) -or [string]::IsNullOrWhiteSpace($endpoint) -or
    [string]::IsNullOrWhiteSpace($messagesEndpoint) -or
    $models.Count -ne 7 -or @($models | Sort-Object -Unique).Count -ne 7) {
    throw "Apply the enabled AI Gateway root first; expected a runtime key, OpenAI and Anthropic endpoints, and seven distinct deployments."
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
$null = Assert-HttpStatus -Name "Bearer runtime key for VS Code" -Uri $endpoint -Body $basicBody `
    -Headers @{ Authorization = "Bearer $key" } -ExpectedStatus 200 -RetryTransient

$anthropicHeaders = @{ "api-key" = $key; "anthropic-version" = "2023-06-01" }
$claudeBody = @{
    model = "claude-opus-5-5"
    messages = @(@{ role = "user"; content = "Reply with exactly the single word READY." })
    max_tokens = 128
} | ConvertTo-Json -Depth 6 -Compress
$null = Assert-HttpStatus -Name "Missing Anthropic runtime key" -Uri $messagesEndpoint -Body $claudeBody `
    -Headers @{ "anthropic-version" = "2023-06-01" } -ExpectedStatus 401
$null = Assert-HttpStatus -Name "Invalid Anthropic runtime key" -Uri $messagesEndpoint -Body $claudeBody `
    -Headers @{ "api-key" = "invalid-test-key"; "anthropic-version" = "2023-06-01" } -ExpectedStatus 401
$null = Assert-HttpStatus -Name "Anthropic subscription header is not a runtime key" -Uri $messagesEndpoint -Body $claudeBody `
    -Headers @{ "Ocp-Apim-Subscription-Key" = $key; "anthropic-version" = "2023-06-01" } -ExpectedStatus 401

foreach ($model in $models) {
    if ($model -eq "claude-opus-5-5") {
        $response = Assert-HttpStatus -Name "$model native Messages completion" `
            -Uri $messagesEndpoint -Body $claudeBody -Headers $anthropicHeaders -ExpectedStatus 200 -RetryTransient
        $message = $response.Content | ConvertFrom-Json
        $text = @($message.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join ""
        if ($message.type -ne "message" -or $message.role -ne "assistant" -or
            $message.model -notmatch "^claude-opus-5-5(?:-\d{8})?$" -or [string]::IsNullOrWhiteSpace($text)) {
            throw "$model did not return a valid, nonempty native Anthropic message from the expected model."
        }
        $payload = $claudeBody | ConvertFrom-Json -AsHashtable
        $payload.stream = $true
        $stream = Assert-HttpStatus -Name "$model native Messages streaming" -Uri $messagesEndpoint `
            -Body ($payload | ConvertTo-Json -Depth 6 -Compress) -Headers $anthropicHeaders -ExpectedStatus 200 -RetryTransient
        if ($stream.Content -notmatch "event:\s*message_start" -or $stream.Content -notmatch "event:\s*message_stop") {
            throw "$model did not return a complete native Anthropic event stream."
        }
        continue
    }

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
        "gpt-6-astra" {
            $payload.max_completion_tokens = 1024
            @("gpt-6-astra", "gpt-6-astra-2026-09-03")
        }
        "FW-GLM-5.3-Flash" {
            $payload.max_tokens = 1024
            @("FW-GLM-5.3-Flash", "GLM-5.3-Flash")
        }
        "FW-Kimi-K3" {
            $payload.max_tokens = 1024
            @("FW-Kimi-K3", "Kimi-K3")
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
foreach ($uri in @($endpoint, $messagesEndpoint)) {
    $unknown = Invoke-WebRequest -Uri $uri -Method Post -Headers $anthropicHeaders -ContentType "application/json" `
        -Body $unknownBody -SkipHttpErrorCheck -TimeoutSec 60
    if ([int]$unknown.StatusCode -notin @(400, 404)) {
        throw "An unregistered model at '$uri' was not rejected with HTTP 400 or 404: HTTP $([int]$unknown.StatusCode)."
    }
    Write-Host "PASS: Unregistered model rejected at '$uri' (HTTP $([int]$unknown.StatusCode))."
}
Write-Host "PASS: All seven models use the existing gateway-wide key; this tier does not provide APIM subscriptions or per-model key isolation."
