#requires -Version 7.0
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\..\TokenObservability.ps1"
$directory = Join-Path ([IO.Path]::GetTempPath()) ("token-csv-test-" + [Guid]::NewGuid().ToString("N"))
$null = New-Item -ItemType Directory -Path $directory
$requestsPath = Join-Path $directory "requests.csv"
$metricsPath = Join-Path $directory "metrics.csv"
try {
    [pscustomobject]@{
        "TimeGenerated [UTC]" = "10/23/2026, 3:29:47.160 AM"
        Id = "request-1"; Name = "POST chat"; DurationMs = "1.5"; ResultCode = "200"
        Success = "True"; Url = "https://example.invalid/chat"; ItemCount = "1"; Measurements = "{}"
        Properties = '{"Subscription Name":"customer-a","Response-x-aigw-model":"model-a","Response-x-aigw-quota-consumed":"100"}'
    } | Export-Csv -LiteralPath $requestsPath -NoTypeInformation
    @("Completion Tokens", "Total Tokens", "Prompt Cached Tokens") | ForEach-Object {
        [pscustomobject]@{
            "TimeGenerated [UTC]" = "10/23/2026, 7:35:01.000 AM"
            Name = $_; ItemCount = "3"; Sum = "9"; Min = "1"; Max = "5"
            Properties = '{"Customer":"customer-a","Model":"model-a"}'
        }
    } | Export-Csv -LiteralPath $metricsPath -NoTypeInformation
    $summary = & "$PSScriptRoot\..\Import-TokenUsage.ps1" -RequestsPath $requestsPath -MetricsPath $metricsPath -ValidateOnly
    if ($summary.RequestRows -ne 1 -or $summary.MetricRows -ne 3 -or
        $summary.InputTokens -ne 100 -or $summary.OutputTokens -ne 9) {
        throw "Token aggregation double-counted a metric or multiplied Sum by ItemCount."
    }
    $requests = @(ConvertTo-TokenTelemetry $requestsPath "AppRequests")
    $again = @(ConvertTo-TokenTelemetry $requestsPath "AppRequests")
    if ($requests[0].RowId -ne $again[0].RowId -or
        $requests[0].Time.Offset -ne [TimeSpan]::Zero -or
        $requests[0].Envelope.time -ne "2026-10-23T03:29:47.1600000+00:00") {
        throw "Stable row identifiers or original UTC timestamps were not preserved."
    }
    $queryTime = [DateTime]::new(2026, 10, 23, 3, 29, 47, 160, [DateTimeKind]::Utc)
    if ((ConvertTo-TokenUtcTime $queryTime).ToString("o") -ne $requests[0].Time.ToString("o")) {
        throw "A query's typed UTC timestamp lost its timezone or fractional seconds."
    }
    $metrics = @(ConvertTo-TokenTelemetry $metricsPath "AppMetrics")
    if ($metrics[0].Envelope.data.baseData.metrics[0].count -ne 3 -or
        $metrics[0].Envelope.data.baseData.metrics[0].value -ne 9) {
        throw "Aggregated metric count and sum were not preserved."
    }
    $added = Import-Csv -LiteralPath $requestsPath
    $added.Properties = '{"Subscription Name":"customer-b","Response-x-aigw-model":"model-a","Response-x-aigw-quota-consumed":"200"}'
    $added | Export-Csv -LiteralPath $requestsPath -Append -NoTypeInformation
    $appended = @(ConvertTo-TokenTelemetry $requestsPath "AppRequests")
    if ($appended.Count -ne 2 -or $appended[0].RowId -ne $requests[0].RowId -or
        $appended[1].RowId -eq $requests[0].RowId) {
        throw "Appending a different customer's row changed an existing row identifier."
    }
    $sourceRows = @(Import-Csv -LiteralPath $requestsPath)
    @($sourceRows[1], $sourceRows[0]) | Export-Csv -LiteralPath $requestsPath -NoTypeInformation
    $reordered = @(ConvertTo-TokenTelemetry $requestsPath "AppRequests")
    if ($reordered[0].RowId -ne $appended[1].RowId -or $reordered[1].RowId -ne $appended[0].RowId) {
        throw "Reordering rows changed their identities."
    }
    $duplicate = @(Import-Csv -LiteralPath $metricsPath)[0]
    $duplicate | Export-Csv -LiteralPath $metricsPath -Append -NoTypeInformation
    $appendedMetrics = @(ConvertTo-TokenTelemetry $metricsPath "AppMetrics")
    if ($appendedMetrics[0].RowId -ne $metrics[0].RowId -or $appendedMetrics[3].RowId -eq $metrics[0].RowId) {
        throw "Repeated identical metric rows were collapsed or existing identifiers changed."
    }
    $bad = @(Import-Csv -LiteralPath $requestsPath)[0]
    $bad.Properties = '{"Subscription Name":"customer-a","Response-x-aigw-model":"model-a","Response-x-aigw-quota-consumed":"-1"}'
    $bad | Export-Csv -LiteralPath $requestsPath -NoTypeInformation
    $rejected = $false
    try { $null = ConvertTo-TokenTelemetry $requestsPath "AppRequests" }
    catch {
        if ($_.Exception.Message -notmatch "nonnegative") { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw "Negative token values were accepted." }
    Write-Host "PASS: totals, metric filtering, aggregate counts, UTC, append/reorder-stable identities, duplicate occurrences, and invalid token rejection."
}
finally {
    Remove-Item -LiteralPath $requestsPath -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $metricsPath -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $directory
}
