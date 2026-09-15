#requires -Version 7.2
<#
.SYNOPSIS
Operate the standalone root without editing HCL. See mlflow.md before use.
.DESCRIPTION
Deploy and Stage/Promote/Rollback always plan first and ask Terraform for approval.
BackupStatus inspects native PostgreSQL automated-backup configuration.
No action destroys infrastructure. No action bypasses plan approval.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Validate', 'Deploy', 'Status', 'Stage', 'Promote', 'Rollback', 'BackupStatus')]
    [string]$Action,
    [string]$SettingsFile = (Join-Path $PSScriptRoot 'admin.tfvars.json'),
    [string]$Image,
    [string]$RevisionSuffix,
    [string]$StableRevision,
    [string]$CandidateRevision,
    [ValidateRange(1, 100)][int]$Percent = 100,
    [switch]$MigrationReviewed,
    [switch]$SmokeTestPassed
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Native {
    param([string]$Program, [string[]]$Arguments, [switch]$Capture)
    # Do not echo arguments: some Terraform outputs are confidential.
    if ($Capture) {
        $result = & $Program @Arguments
        if ($LASTEXITCODE -ne 0) { throw "$Program failed (exit $LASTEXITCODE)." }
        return ($result -join "`n")
    }
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed (exit $LASTEXITCODE). Stop and inspect the error before retrying." }
}

function Save-Settings {
    # Saves nonsecret desired state BEFORE plan. A failed apply leaves the intended
    # settings available for review/retry; it never reports successful deployment.
    $script:settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $SettingsFile -Encoding utf8
}

function Assert-SafePlan {
    param([hashtable]$Review, [bool]$AllowTemplateChange = $false)
    if (!$Review.ContainsKey('complete') -or !$Review.complete -or ($Review.ContainsKey('errored') -and $Review.errored)) {
        throw 'Plan is incomplete or errored. Nothing applied.'
    }
    $changes = if ($Review.ContainsKey('resource_changes')) { @($Review.resource_changes) } else { @() }
    if (@($changes | Where-Object { $_.change.actions -contains 'delete' }).Count) {
        throw 'Refusing destructive/replacement plan. Handle resource migration separately after backup and review.'
    }
    if ($Action -in 'Stage', 'Promote', 'Rollback') {
        foreach ($change in $changes) {
            if (($change.change.actions -join ',') -eq 'no-op' -or ($change.change.actions -join ',') -eq 'read') { continue }
            if ($change.address -ne 'module.mlflow.azurerm_container_app.this' -or ($change.change.actions -join ',') -ne 'update') {
                throw 'Release operations may only update the existing Container App. Resolve infrastructure drift separately.'
            }
            if (!$AllowTemplateChange -and
                ($change.change.before.template | ConvertTo-Json -Depth 100 -Compress) -cne
                ($change.change.after.template | ConvertTo-Json -Depth 100 -Compress)) {
                throw 'Traffic-only operation would alter the container template. Resolve settings drift before proceeding.'
            }
            if (($change.change.before.secret | ConvertTo-Json -Depth 100 -Compress) -cne
                ($change.change.after.secret | ConvertTo-Json -Depth 100 -Compress)) {
                throw 'Release operation would rotate shared secrets. Resolve credentials separately before proceeding.'
            }
        }
    }
}

function Invoke-ReviewedPlan {
    param([bool]$AllowTemplateChange = $false)
    Invoke-Native terraform @('validate', '-no-color')
    $plan = Join-Path $PSScriptRoot ('operation-' + [guid]::NewGuid().ToString('N') + '.tfplan')
    try {
        Invoke-Native terraform @('plan', '-input=false', '-parallelism=2', '-var-file', $SettingsFile, '-out', $plan)
        $review = Invoke-Native terraform @('show', '-json', $plan) -Capture | ConvertFrom-Json -AsHashtable -Depth 100
        Assert-SafePlan -Review $review -AllowTemplateChange $AllowTemplateChange
        if (!$review.applyable) { Write-Host 'No changes to apply.'; return }
        # Applying a saved plan skips Terraform confirmation. Prompt explicitly.
        $answer = Read-Host 'Apply the reviewed plan? Type APPLY (anything else cancels)'
        if ($answer -cne 'APPLY') { throw 'Cancelled. Desired settings remain saved; Azure was not changed by this plan.' }
        Invoke-Native terraform @('apply', '-parallelism=2', $plan)
    }
    finally {
        if (Test-Path -LiteralPath $plan) { Remove-Item -LiteralPath $plan -Force }
    }
}

function Get-Revision {
    param([string]$Revision)
    if (!$Revision.StartsWith("$($script:connection.container_app_name)--", [StringComparison]::Ordinal)) {
        throw 'Revision must belong to this Container App.'
    }
    return (Invoke-Native az @('containerapp', 'revision', 'show', '--name', $script:connection.container_app_name,
        '--resource-group', $script:connection.resource_group_name, '--subscription', $script:settings.subscription_id,
        '--revision', $Revision, '--output', 'json', '--only-show-errors') -Capture | ConvertFrom-Json -Depth 100)
}

function Assert-HealthyRevision {
    param([string]$Revision)
    $r = Get-Revision $Revision
    if (!$r.properties.active -or $r.properties.healthState -ne 'Healthy' -or $r.properties.provisioningState -ne 'Provisioned') {
        throw "Revision '$Revision' is not active, provisioned and healthy. No traffic change performed."
    }
}

$SettingsFile = [IO.Path]::GetFullPath($SettingsFile)
if (!(Test-Path -LiteralPath $SettingsFile)) { throw 'Copy admin.tfvars.json.example to admin.tfvars.json and supply the five deployment values first.' }
if (!$SettingsFile.EndsWith('.tfvars.json')) { throw 'SettingsFile must end in .tfvars.json.' }
$script:settings = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json -AsHashtable -Depth 100
if (!$settings.ContainsKey('subscription_id') -or !$settings.ContainsKey('deployment')) { throw 'Settings need subscription_id and deployment.' }
if ($settings.ContainsKey('provider_secrets')) { throw 'Keep provider_secrets out of the settings file; supply TF_VAR_provider_secrets privately.' }

# WhatIf returns before init, local settings writes, cloud mutation or backup export.
if (!$PSCmdlet.ShouldProcess($settings.deployment.name, "$Action standalone AI gateway using $SettingsFile")) { return }
Push-Location $PSScriptRoot
try {
    Get-Command terraform -ErrorAction Stop | Out-Null
    if ($Action -eq 'Validate') {
        Invoke-Native terraform @('init', '-backend=false', '-input=false')
        Invoke-Native terraform @('validate', '-no-color')
        Invoke-Native terraform @('fmt', '-check', '-recursive')
        return
    }
    Get-Command az -ErrorAction Stop | Out-Null
    $account = Invoke-Native az @('account', 'show', '--subscription', $settings.subscription_id, '--output', 'json', '--only-show-errors') -Capture | ConvertFrom-Json
    if ($account.id -ne $settings.subscription_id) { throw 'Azure subscription does not match settings.' }
    # Make Terraform CLI authentication unambiguous without changing the az default account.
    $previousSubscription = $env:ARM_SUBSCRIPTION_ID
    $env:ARM_SUBSCRIPTION_ID = $settings.subscription_id
    Invoke-Native terraform @('init', '-input=false')
    if ($Action -eq 'Deploy') { Invoke-ReviewedPlan; return }

    $script:connection = Invoke-Native terraform @('output', '-json', 'connection') -Capture | ConvertFrom-Json
    $app = Invoke-Native az @('containerapp', 'show', '--name', $connection.container_app_name,
        '--resource-group', $connection.resource_group_name, '--subscription', $settings.subscription_id,
        '--output', 'json', '--only-show-errors') -Capture | ConvertFrom-Json -Depth 100

    switch ($Action) {
        'Status' {
            $connection | Format-List
            $app.properties.configuration.ingress.traffic | Format-Table revisionName, latestRevision, weight
            Invoke-Native az @('containerapp', 'revision', 'list', '--name', $connection.container_app_name,
                '--resource-group', $connection.resource_group_name, '--subscription', $settings.subscription_id,
                '--query', '[].{name:name,active:properties.active,health:properties.healthState,provisioning:properties.provisioningState}', '--output', 'table')
        }
        'Stage' {
            if (!$MigrationReviewed) { throw 'Read the migration gate in mlflow.md. Supply -MigrationReviewed only after backup and old/new schema compatibility tests.' }
            if ($Image -notmatch '@sha256:[a-f0-9]{64}$') { throw 'Stage requires an immutable image sha256 digest.' }
            if (!$RevisionSuffix) { $RevisionSuffix = 'r' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmss') }
            if ($RevisionSuffix -notmatch '^[a-z][a-z0-9-]{0,30}[a-z0-9]$' -or $RevisionSuffix.Contains('--')) { throw 'Invalid revision suffix.' }
            $routes = @($app.properties.configuration.ingress.traffic | Where-Object { $_.weight -gt 0 })
            if ($routes.Count -ne 1 -or $routes[0].weight -ne 100) { throw 'Stage requires one stable revision at 100%. Finish or roll back the current rollout first.' }
            $route = $routes[0]
            $StableRevision = if ($route.PSObject.Properties['latestRevision'] -and $route.latestRevision) { $app.properties.latestReadyRevisionName } else { $route.revisionName }
            Assert-HealthyRevision $StableRevision
            $CandidateRevision = "$($connection.container_app_name)--$RevisionSuffix"
            if ($CandidateRevision -eq $StableRevision) { throw 'Choose a new revision suffix.' }

            # FIRST apply freezes traffic. Never deploy new image while latest=100.
            $settings.deployment.traffic_weights = @{ $StableRevision = 100 }
            Save-Settings
            Invoke-ReviewedPlan
            # SECOND apply creates candidate; migrations are disabled in serving pods.
            $settings.deployment.image = $Image
            $settings.deployment.revision_suffix = $RevisionSuffix
            $settings.deployment.disable_schema_update = $true
            Save-Settings
            Invoke-ReviewedPlan -AllowTemplateChange $true
            Write-Host "Candidate staged with production traffic pinned to $StableRevision."
            Write-Host "Candidate: $CandidateRevision. Run direct revision health/Redis/model/streaming tests before Promote."
        }
        { $_ -in 'Promote', 'Rollback' } {
            if (!$StableRevision -or !$CandidateRevision -or $StableRevision -eq $CandidateRevision) { throw 'Supply distinct -StableRevision and -CandidateRevision from Status.' }
            if ($Action -eq 'Promote' -and !$SmokeTestPassed) { throw 'Supply -SmokeTestPassed after the documented candidate tests pass.' }
            if ($Action -eq 'Promote') { Assert-HealthyRevision $CandidateRevision } else { Assert-HealthyRevision $StableRevision }
            # Verify both names belong to this app even if the candidate is unhealthy.
            $null = Get-Revision $StableRevision
            $null = Get-Revision $CandidateRevision
            $settings.deployment.traffic_weights = if ($Action -eq 'Rollback') {
                @{ $StableRevision = 100; $CandidateRevision = 0 }
            } else {
                @{ $StableRevision = (100 - $Percent); $CandidateRevision = $Percent }
            }
            # Keep the latest template/image in Terraform; rollback changes only
            # routing. Reverting revision_suffix to an old immutable revision fails.
            Save-Settings
            Invoke-ReviewedPlan
        }
        'BackupStatus' {
            Invoke-Native az @('postgres', 'flexible-server', 'show', '--name', $connection.postgres_server_name,
                '--resource-group', $connection.resource_group_name, '--subscription', $settings.subscription_id,
                '--query', '{server:name,state:state,backup:backup}', '--output', 'json', '--only-show-errors')
            Write-Host 'Azure manages automatic database backups. Verify available restore points in the server Backup and restore pane; configuration alone does not prove a restore succeeded.'
        }
    }
}
finally {
    if (Test-Path variable:previousSubscription) { $env:ARM_SUBSCRIPTION_ID = $previousSubscription }
    Pop-Location
}