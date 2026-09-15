#requires -Version 7.2
# Local tests only: extracts actual function ASTs; never invokes Azure/Terraform.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '../Manage-MLflow.ps1'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $source), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors.Message -join '; ') }
foreach ($name in @('Assert-SafePlan', 'Assert-HealthyRevision', 'Get-Revision')) {
    $node = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($node.Extent.Text))
}
$script:passed = 0
function Check {
    param([string]$Name, [scriptblock]$Code, [string]$ExpectedError = '')
    $caught = $null
    try {
        & $Code
    }
    catch {
        $caught = $_
    }
    if ($ExpectedError -and (!$caught -or $caught.Exception.Message -notlike "*$ExpectedError*")) { throw "Missing expected error: $ExpectedError" }
    if (!$ExpectedError -and $caught) { throw $caught }
    $script:passed++
    Write-Host "PASS $Name"
}
function New-Plan {
    param([string[]]$Actions = @('update'), [string]$Address = 'module.mlflow.azurerm_container_app.this', [string]$NewImage = 'old', [string]$NewSecret = 'unchanged')
    return @{
        complete = $true; errored = $false; applyable = $true
        resource_changes = @(@{
            address = $Address
            change = @{
                actions = $Actions
                before = @{ template = @(@{ image = 'old' }); secret = @(@{ value = 'unchanged' }) }
                after = @{ template = @(@{ image = $NewImage }); secret = @(@{ value = $NewSecret }) }
            }
        })
    }
}
$Action = 'Promote'
$null = $Action
Check 'traffic-only plan accepted' { Assert-SafePlan (New-Plan) }
Check 'no-change plan accepted' { Assert-SafePlan @{ complete = $true; errored = $false; applyable = $false } }
Check 'incomplete plan rejected' { Assert-SafePlan @{ complete = $false } } 'incomplete'
Check 'errored plan rejected' { Assert-SafePlan @{ complete = $true; errored = $true } } 'errored'
Check 'delete rejected' { Assert-SafePlan (New-Plan -Actions @('delete')) } 'destructive'
Check 'replacement rejected' { Assert-SafePlan (New-Plan -Actions @('delete', 'create')) } 'destructive'
Check 'unrelated infra change rejected' { Assert-SafePlan (New-Plan -Address 'module.mlflow.azurerm_managed_redis.this') } 'only update'
Check 'traffic template drift rejected' { Assert-SafePlan (New-Plan -NewImage 'new') } 'container template'
$Action = 'Stage'
$null = $Action
Check 'candidate template accepted' { Assert-SafePlan (New-Plan -NewImage 'new') -AllowTemplateChange $true }
Check 'candidate secret rotation rejected' { Assert-SafePlan (New-Plan -NewSecret 'rotated') -AllowTemplateChange $true } 'shared secrets'

$script:connection = [pscustomobject]@{ container_app_name = 'ca-test'; resource_group_name = 'rg-test' }
$script:settings = @{ subscription_id = 'test-subscription' }
$script:health = 'Healthy'
function Invoke-Native {
    param($Program, $Arguments, [switch]$Capture)
    if ($Program -ne 'az' -or !($Arguments -contains 'show')) { throw 'Unexpected external command in test.' }
    return (@{ properties = @{ active = $true; healthState = $script:health; provisioningState = 'Provisioned' } } | ConvertTo-Json)
}
Check 'healthy revision accepted' { Assert-HealthyRevision 'ca-test--stable' }
$script:health = 'Unhealthy'
Check 'unhealthy revision blocked' { Assert-HealthyRevision 'ca-test--bad' } 'not active'
Check 'wrong application blocked' { Get-Revision 'another-app--stable' | Out-Null } 'belong'

# WhatIf must stop before any executable is found or config is rewritten.
$temp = Join-Path ([IO.Path]::GetTempPath()) ('litellm-test-' + [guid]::NewGuid().ToString('N') + '.tfvars.json')
try {
    '{"subscription_id":"test-subscription","deployment":{"name":"dryrun"}}' | Set-Content -LiteralPath $temp
    $before = (Get-FileHash $temp).Hash
    Check 'WhatIf makes no settings change' {
        & $source -Action Deploy -SettingsFile $temp -WhatIf
        if ((Get-FileHash $temp).Hash -ne $before) { throw 'WhatIf changed settings.' }
    }
}
finally { Remove-Item -LiteralPath $temp -Force }
Write-Host "$script:passed tests passed. No live resource operations."