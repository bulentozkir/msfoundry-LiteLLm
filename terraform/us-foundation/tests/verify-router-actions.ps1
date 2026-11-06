$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$output = & terraform "-chdir=$root" test -json -verbose 2>&1
$testExit = $LASTEXITCODE

$expected = @{
  plans_router_ownership_migration = "update"
  keeps_an_unchanged_router        = "no-op"
  updates_the_subset_in_place      = "update"
}
$observed = @{}
$errorsFound = @()
$diagnostics = @()
$failedRuns = @{}
$run = ""

foreach ($line in $output) {
  try {
    $event = "$line" | ConvertFrom-Json -ErrorAction Stop
  }
  catch {
    continue
  }

  if ($event.type -eq "test_run") {
    $run = $event.test_run.run
    if ($event.test_run.status -eq "fail") {
      $failedRuns[$run] = $true
      $errorsFound += "Test run failed: $run"
    }
  }
  elseif ($event.type -eq "diagnostic" -and $event.diagnostic.severity -eq "error") {
    $summary = ($event.diagnostic.summary -split "`n")[0]
    $diagnostics += [pscustomobject]@{ Run = $run; Summary = $summary }
  }
  elseif ($event.type -eq "test_plan" -and $expected.ContainsKey($run)) {
    $change = @($event.test_plan.resource_changes | Where-Object { $_.address -eq "azapi_resource.model_router" })
    if ($change.Count -ne 1) {
      $errorsFound += "Expected exactly one router action in $run."
      continue
    }

    $actions = @($change[0].change.actions)
    if ($actions.Count -ne 1 -or $actions[0] -ne $expected[$run]) {
      $errorsFound += "Unexpected router action in $run`: $($actions -join ', ')."
    }
    if (
      $run -eq "plans_router_ownership_migration" -and
      $change[0].previous_address -ne 'azurerm_cognitive_deployment.model["model_router"]'
    ) {
      $errorsFound += "The migration plan did not move the legacy router address."
    }
    $observed[$run] = $actions -join ", "
  }
}

if ($testExit -ne 0) {
  $errorsFound += "Terraform test exited with code $testExit."
  foreach ($diagnostic in $diagnostics) {
    if ($failedRuns.Count -eq 0 -or $failedRuns.ContainsKey($diagnostic.Run)) {
      $errorsFound += "Terraform diagnostic: $($diagnostic.Summary)"
    }
  }
}
foreach ($name in $expected.Keys) {
  if (-not $observed.ContainsKey($name)) {
    $errorsFound += "Missing router plan for $name."
  }
}
if ($errorsFound.Count -gt 0) {
  $errorsFound | ForEach-Object { Write-Error $_ -ErrorAction Continue }
  exit 1
}

foreach ($name in @("plans_router_ownership_migration", "keeps_an_unchanged_router", "updates_the_subset_in_place")) {
  Write-Output "$name`: $($observed[$name])"
}
