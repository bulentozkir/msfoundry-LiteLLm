#requires -Version 7.0

function Get-TerraformOutput {
    param([Parameter(Mandatory)][string]$Name)

    $raw = terraform output -json $Name
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot read Terraform output '$Name'. Run this script from the apim-only Terraform root after apply."
    }
    return $raw | ConvertFrom-Json -AsHashtable
}

function Assert-HttpStatus {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Body,
        [hashtable]$Headers = @{},
        [Parameter(Mandatory)][int]$ExpectedStatus,
        [switch]$RetryTransient
    )

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $response = Invoke-WebRequest -Uri $Uri -Method Post -Headers $Headers `
            -ContentType "application/json" -Body $Body -SkipHttpErrorCheck -TimeoutSec 180
        $status = [int]$response.StatusCode
        if ($status -eq $ExpectedStatus) {
            Write-Host "PASS: $Name (HTTP $status)"
            return $response
        }
        if ($RetryTransient -and $attempt -lt 5 -and $status -in @(401, 403, 429, 502, 503, 504)) {
            Write-Warning "$Name returned HTTP $status; retrying in 65 seconds for service/RBAC propagation or quota renewal."
            Start-Sleep -Seconds 65
            continue
        }
        throw "$Name expected HTTP $ExpectedStatus but received HTTP ${status}: $($response.Content)"
    }
}

function Get-ApimManagementResource {
    param(
        [Parameter(Mandatory)][string]$ResourceId,
        [string]$ApiVersion = "2024-05-01"
    )

    $resource = Invoke-RestMethod -Uri "https://management.azure.com${ResourceId}?api-version=$ApiVersion" `
        -Headers $managementHeaders -TimeoutSec 60
    if ($resource -is [string]) {
        return $resource.TrimStart([char]0xFEFF) | ConvertFrom-Json
    }
    return $resource
}

function Assert-CorsPreflight {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Origin,
        [Parameter(Mandatory)][bool]$Allowed
    )

    $requestedHeaders = @("content-type", "authorization", "ocp-apim-subscription-key", "api-key", "x-ms-client-request-id", "x-ms-useragent", "x-stainless-lang")
    $response = Invoke-WebRequest -Uri $Uri -Method Options -Headers @{
        Origin = $Origin
        "Access-Control-Request-Method" = "POST"
        "Access-Control-Request-Headers" = $requestedHeaders -join ","
    } -SkipHttpErrorCheck -TimeoutSec 60
    $allowOrigin = $response.Headers["Access-Control-Allow-Origin"] -join ","

    if (!$Allowed) {
        if ([int]$response.StatusCode -notin @(200, 204) -or $allowOrigin -eq $Origin -or $allowOrigin -eq "*") {
            throw "Untrusted-origin preflight on '$Uri' returned unexpected HTTP $([int]$response.StatusCode) or allowed origin '$allowOrigin'."
        }
        Write-Host "PASS: $Uri does not allow untrusted browser origin $Origin."
        return
    }

    $allowMethods = ($response.Headers["Access-Control-Allow-Methods"] -join ",") -split "," | ForEach-Object { $_.Trim() }
    $allowHeaders = ($response.Headers["Access-Control-Allow-Headers"] -join ",") -split "," | ForEach-Object { $_.Trim() }
    if ([int]$response.StatusCode -notin @(200, 204) -or $allowOrigin -ne $Origin -or
        "POST" -notin $allowMethods -or
        ($response.Headers["Access-Control-Allow-Credentials"] -join ",") -eq "true" -or
        ("*" -notin $allowHeaders -and @($requestedHeaders | Where-Object { $_ -notin $allowHeaders }).Count -gt 0)) {
        throw "Browser preflight failed for '$Origin' on '$Uri': HTTP $([int]$response.StatusCode), origin '$allowOrigin', methods '$allowMethods', headers '$allowHeaders'."
    }
    Write-Host "PASS: $Uri accepts Azure Portal preflight from $Origin without a subscription key."
}
