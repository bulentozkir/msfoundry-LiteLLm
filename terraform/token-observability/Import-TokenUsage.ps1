#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RequestsPath = "$env:USERPROFILE\Downloads\AppRequests.csv",
    [string] $MetricsPath = "$env:USERPROFILE\Downloads\AppMetrics.csv",
    [switch] $ValidateOnly,
    [int] $VerificationTimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\TokenObservability.ps1"

$records = @(
    ConvertTo-TokenTelemetry $RequestsPath "AppRequests"
    ConvertTo-TokenTelemetry $MetricsPath "AppMetrics"
)
$summary = [ordered]@{
    RequestRows = @($records | Where-Object Table -eq "AppRequests").Count
    MetricRows = @($records | Where-Object Table -eq "AppMetrics").Count
    InputTokens = ($records | Where-Object Table -eq "AppRequests" | Measure-Object CountedTokens -Sum).Sum
    OutputTokens = ($records | Where-Object Table -eq "AppMetrics" | Measure-Object CountedTokens -Sum).Sum
}
if ($ValidateOnly) { [pscustomobject] $summary; return }

$config = Get-ObservabilityOutputs
$baselineQuery = @'
union withsource=TableName isfuzzy=true AppRequests, AppMetrics,
    (datatable(TimeGenerated:datetime, Properties:dynamic, Name:string, Id:string, ItemCount:int, Sum:real, Min:real, Max:real)[])
| where TimeGenerated > ago(30d) and Properties.TelemetryOrigin == "Imported CSV sample"
| project TableName, TimeGenerated, CsvRowId=tostring(Properties.CsvRowId), Name, Properties,
          RequestId=iff(TableName == "AppRequests", tostring(Id), ""),
          Value=iff(TableName == "AppRequests", todouble(Properties["Response-x-aigw-quota-consumed"]), todouble(Sum)),
          Count=tolong(ItemCount),
          Minimum=iff(TableName == "AppMetrics", todouble(Min), 0.0),
          Maximum=iff(TableName == "AppMetrics", todouble(Max), 0.0)
'@
$baseline = Invoke-TokenWorkspaceQuery $config.workspace_id $baselineQuery
$knownIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$legacyRows = @{}
foreach ($row in $baseline.tables[0].rows) {
    $storedId = [string] $row[2]
    $null = $knownIds.Add($storedId)
    if ($storedId.StartsWith("$($row[0])-v2-", [StringComparison]::Ordinal)) { continue }
    $identity = @{
        Table = $row[0]; Time = (ConvertTo-TokenUtcTime $row[1])
        Name = $row[3]; Properties = ($row[4] | ConvertFrom-Json -AsHashtable)
        RequestId = $row[5]; Value = $row[6]; Count = $row[7]; Minimum = $row[8]; Maximum = $row[9]
    }
    $fingerprint = Get-TokenRowFingerprint @identity
    if (-not $legacyRows.ContainsKey($fingerprint)) { $legacyRows[$fingerprint] = [Collections.Generic.Queue[string]]::new() }
    $legacyRows[$fingerprint].Enqueue($storedId)
}
foreach ($record in $records) {
    if (-not $knownIds.Contains($record.RowId) -and
        $legacyRows.ContainsKey($record.Fingerprint) -and $legacyRows[$record.Fingerprint].Count -gt 0) {
        $record.RowId = $legacyRows[$record.Fingerprint].Dequeue()
    }
}
$ids = @($records.RowId) | ConvertTo-Json -Compress
$existingQuery = @"
union isfuzzy=true AppRequests, AppMetrics, (datatable(TimeGenerated:datetime, Properties:dynamic)[])
| where TimeGenerated > ago(30d)
| extend CsvRowId = tostring(Properties.CsvRowId)
| where CsvRowId in (dynamic($ids))
| distinct CsvRowId
"@
$pending = @($records | Where-Object { -not $knownIds.Contains($_.RowId) })
Write-Host "Skipping $($records.Count - $pending.Count) previously imported rows; submitting $($pending.Count) new rows."
if ($pending.Count -gt 0) {
    if (-not $PSCmdlet.ShouldProcess($config.workspace_id, "Import $($pending.Count) new CSV rows")) {
        $summary["PendingRows"] = $pending.Count
        [pscustomobject] $summary
        return
    }
    foreach ($record in $pending) {
        if ($record.Time -lt [DateTimeOffset]::UtcNow.AddHours(-48) -or
            $record.Time -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) {
            throw "Record $($record.RowId) is outside the Application Insights replay window. Original timestamps were not changed."
        }
    }
    $connection = @{}
    foreach ($part in $config.application_insights_connection_string.Split(";", [StringSplitOptions]::RemoveEmptyEntries)) {
        $pair = $part.Split("=", 2)
        $connection[$pair[0]] = $pair[1]
    }
    foreach ($record in $pending) { $record.Envelope["iKey"] = $connection.InstrumentationKey }
    $token = Get-ObservabilityAccessToken "https://monitor.azure.com"
    try {
        $payload = @($pending.Envelope) | ConvertTo-Json -Depth 25 -Compress
        $response = Invoke-WebRequest -Method Post `
            -Uri "$($connection.IngestionEndpoint.TrimEnd('/'))/v2.1/track" `
            -Headers @{ Authorization = "Bearer $token" } -ContentType "application/json" `
            -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -SkipHttpErrorCheck -TimeoutSec 90
        $receipt = $response.Content | ConvertFrom-Json
        if ([int] $response.StatusCode -ne 200 -or $receipt.itemsAccepted -ne $pending.Count) {
            throw "Telemetry ingestion was not fully accepted (HTTP $([int] $response.StatusCode)): $($response.Content)"
        }
        Write-Host "Accepted $($receipt.itemsAccepted) records; waiting for Log Analytics query visibility."
    }
    finally { $token = $null; $connection.Clear(); $payload = $null }
} else {
    Write-Host "All source row identifiers already exist; no records were resubmitted."
}

$deadline = [DateTimeOffset]::UtcNow.AddSeconds($VerificationTimeoutSeconds)
do {
    $verification = Invoke-TokenWorkspaceQuery $config.workspace_id $existingQuery
    $count = @($verification.tables[0].rows).Count
    if ($count -eq $records.Count) {
        $summary["VerifiedDistinctRows"] = $count
        $summary["NewlySubmittedRows"] = $pending.Count
        [pscustomobject] $summary
        return
    }
    Write-Host "Visible imported rows: $count/$($records.Count)."
    Start-Sleep -Seconds 15
} while ([DateTimeOffset]::UtcNow -lt $deadline)
throw "Only $count/$($records.Count) source rows were visible before the verification deadline. Rerun to check before resubmitting."
