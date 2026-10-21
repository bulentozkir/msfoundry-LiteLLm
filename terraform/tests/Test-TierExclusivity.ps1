#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("AIGateway", "StandardV2")]
    [string]$ActiveTier
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

if ($ActiveTier -eq "AIGateway") {
    $root = Join-Path $PSScriptRoot "..\apim-only"
    $enableVariable = "standard_gateway_enabled=true"
    $expectedError = "Another gateway occupies the outbound subnet"
}
else {
    $root = Join-Path $PSScriptRoot "..\apim-ai-gateway"
    $enableVariable = "ai_gateway_enabled=true"
    $expectedError = "Disable standard_gateway_enabled|Another gateway still occupies the outbound subnet"
}

$result = & terraform "-chdir=$root" plan -input=false -no-color "-var=$enableVariable" 2>&1 | Out-String
$exitCode = $LASTEXITCODE
if ($exitCode -ne 1 -or $result -notmatch $expectedError) {
    throw "Expected the inactive root to reject a conflicting gateway (exit $exitCode). $result"
}

Write-Host "PASS: The inactive Terraform root refuses to provision while $ActiveTier owns the outbound subnet."
