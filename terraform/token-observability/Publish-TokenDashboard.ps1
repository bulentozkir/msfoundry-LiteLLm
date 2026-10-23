#requires -Version 7.0
[CmdletBinding()]
param([switch] $SkipValidation)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\TokenObservability.ps1"
$config = Get-ObservabilityOutputs
$subscription = ($config.workspace_resource_id -split "/")[2]
$endpoint = $config.grafana_endpoint.TrimEnd("/")
$datasourceUid = "customer-token-logs"
$token = Get-ObservabilityAccessToken "https://dashboard.azure.com"
$headers = @{ Authorization = "Bearer $token" }

function Invoke-GrafanaRequest([string] $Method, [string] $Path, $Body = $null, [switch] $AllowNotFound) {
    $arguments = @{
        Uri = "$endpoint$Path"; Method = $Method; Headers = $headers
        SkipHttpErrorCheck = $true; TimeoutSec = 120
    }
    if ($null -ne $Body) {
        $arguments.ContentType = "application/json"
        $arguments.Body = $Body | ConvertTo-Json -Depth 60 -Compress
    }
    $response = Invoke-WebRequest @arguments
    if ($AllowNotFound -and [int] $response.StatusCode -eq 404) { return $null }
    if ([int] $response.StatusCode -lt 200 -or [int] $response.StatusCode -ge 300) {
        throw "Grafana $Method $Path returned HTTP $([int] $response.StatusCode): $($response.Content)"
    }
    return $response.Content | ConvertFrom-Json -AsHashtable
}

function New-LogsTarget([string] $Query, [string] $Format = "table", [string] $RefId = "A") {
    return @{
        refId = $RefId; queryType = "Azure Log Analytics"; subscription = $subscription
        datasource = @{ type = "grafana-azure-monitor-datasource"; uid = $datasourceUid }
        azureLogAnalytics = @{
            query = $Query; resultFormat = $Format; resources = @($config.workspace_resource_id)
        }
    }
}

try {
    $deadline = [DateTimeOffset]::UtcNow.AddMinutes(5)
    do {
        $ready = Invoke-WebRequest -Uri "$endpoint/api/org" -Headers $headers -SkipHttpErrorCheck -TimeoutSec 30
        if ([int] $ready.StatusCode -eq 200) { break }
        if ([int] $ready.StatusCode -notin @(401, 403, 502, 503)) {
            throw "Grafana readiness failed with HTTP $([int] $ready.StatusCode): $($ready.Content)"
        }
        Write-Host "Waiting for Grafana readiness/role propagation (HTTP $([int] $ready.StatusCode))."
        Start-Sleep -Seconds 15
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    if ([int] $ready.StatusCode -ne 200) { throw "Grafana access was not ready before the deadline." }

    $datasource = @{
        uid = $datasourceUid; name = "Customer token logs"; type = "grafana-azure-monitor-datasource"
        access = "proxy"; isDefault = $true
        jsonData = @{
            azureAuthType = "msi"; cloudName = "azuremonitor"; subscriptionId = $subscription
            logAnalyticsDefaultWorkspace = $config.workspace_id
        }
    }
    $existing = Invoke-GrafanaRequest "GET" "/api/datasources/uid/$datasourceUid" -AllowNotFound
    if ($null -eq $existing) {
        $null = Invoke-GrafanaRequest "POST" "/api/datasources" $datasource
    } else {
        $null = Invoke-GrafanaRequest "PUT" "/api/datasources/uid/$datasourceUid" $datasource
    }

    $base = Get-Content -LiteralPath "$PSScriptRoot\queries\token-usage.kql" -Raw
    $window = Invoke-TokenWorkspaceQuery $config.workspace_id @'
union AppRequests, AppMetrics
| where Properties.TelemetryOrigin == "Imported CSV sample"
| summarize First=min(TimeGenerated), Last=max(TimeGenerated)
'@
    if ([string]::IsNullOrWhiteSpace([string] $window.tables[0].rows[0][0])) {
        throw "Import the CSV samples before publishing their dashboard."
    }
    $first = ConvertTo-TokenUtcTime $window.tables[0].rows[0][0]
    $last = ConvertTo-TokenUtcTime $window.tables[0].rows[0][1]
    $begin = [DateTimeOffset]::new($first.UtcDateTime.Date, [TimeSpan]::Zero)
    $end = [DateTimeOffset]::new($last.UtcDateTime.Date.AddDays(1), [TimeSpan]::Zero)
    $selection = 'Customer in (${customer:singlequote}) and Model in (${model:singlequote})'
    $filtered = $base + "`n| where " + '$__timeFilter(TimeGenerated)' + "`n| where $selection"
    $queries = [ordered]@{
        Input = $filtered + "`n| summarize Tokens = sumif(Tokens, Direction == 'Input')"
        Output = $filtered + "`n| summarize Tokens = sumif(Tokens, Direction == 'Output')"
        Total = $filtered + "`n| summarize Tokens = sum(Tokens)"
        Requests = $filtered + "`n| summarize Requests = countif(Direction == 'Input')"
        Customer = $filtered + "`n| summarize InputTokens = sumif(Tokens, Direction == 'Input'), OutputTokens = sumif(Tokens, Direction == 'Output') by Customer"
        Model = $filtered + "`n| summarize InputTokens = sumif(Tokens, Direction == 'Input'), OutputTokens = sumif(Tokens, Direction == 'Output') by Model"
        Timeline = $filtered + "`n| summarize Tokens = sum(Tokens) by bin(TimeGenerated, " + '$__interval' + "), Direction`n| order by TimeGenerated asc"
        Coverage = $filtered + @"

| summarize InputTokens = sumif(Tokens, Direction == 'Input'),
            OutputTokens = sumif(Tokens, Direction == 'Output'),
            InputRecords = countif(Direction == 'Input'),
            OutputRecords = countif(Direction == 'Output') by Customer, Model
| extend RecordedTotal = InputTokens + OutputTokens,
         Coverage = case(InputRecords == 0, 'Output samples only', OutputRecords == 0, 'Input samples only', 'Both directions observed')
| order by Customer asc, Model asc
"@
        Metrics = @'
AppMetrics
| where $__timeFilter(TimeGenerated)
| extend Customer = tostring(Properties.Customer), Model = tostring(Properties.Model)
| where Customer in (${customer:singlequote}) and Model in (${model:singlequote})
| summarize MetricSum = sum(Sum), AggregatedMeasurements = sum(ItemCount) by Customer, Model, Name
| order by Customer asc, Model asc, Name asc
'@
    }
    $panels = @(@{
        id = 1; type = "text"; title = "Imported examples: interpretation and coverage"
        gridPos = @{ x = 0; y = 0; w = 24; h = 4 }
        options = @{
            mode = "markdown"
            content = "**Sample import, not a live gateway feed.** Input uses AppRequests `Properties['Response-x-aigw-quota-consumed']` per the source custom-rule design. Output uses only AppMetrics **Completion Tokens**, summing **Sum** once (never multiplying by ItemCount). Prompt, total, cache and prediction metrics are shown separately, not added to output. Source timestamps are UTC and preserved. Models/time slices are not paired request-by-request; an absent direction means missing samples, not proven zero usage. Values are operational examples, not billing-grade accounting."
        }
    })
    $titles = @{ Input = "Recorded input tokens"; Output = "Recorded output tokens"; Total = "Recorded input + output"; Requests = "Input request records" }
    $index = 0
    foreach ($key in @("Input", "Output", "Total", "Requests")) {
        $panels += @{
            id = $index + 2; type = "stat"; title = $titles[$key]
            gridPos = @{ x = $index * 6; y = 4; w = 6; h = 4 }
            datasource = @{ type = "grafana-azure-monitor-datasource"; uid = $datasourceUid }
            targets = @((New-LogsTarget $queries[$key]))
            fieldConfig = @{ defaults = @{ unit = "short"; decimals = 0 }; overrides = @() }
            options = @{ reduceOptions = @{ calcs = @("lastNotNull"); fields = ""; values = $false }; colorMode = "value"; graphMode = "none" }
        }
        $index++
    }
    foreach ($spec in @(
        @{ Key = "Customer"; Id = 6; Title = "Recorded tokens by customer"; Type = "barchart"; X = 0; Y = 8; W = 12; H = 8 },
        @{ Key = "Model"; Id = 7; Title = "Recorded tokens by model"; Type = "barchart"; X = 12; Y = 8; W = 12; H = 8 },
        @{ Key = "Timeline"; Id = 8; Title = "Input / output tokens over time"; Type = "timeseries"; X = 0; Y = 16; W = 24; H = 8 },
        @{ Key = "Coverage"; Id = 9; Title = "Customer / model totals and missing-sample coverage"; Type = "table"; X = 0; Y = 24; W = 24; H = 8 },
        @{ Key = "Metrics"; Id = 10; Title = "All imported metrics (not additive token categories)"; Type = "table"; X = 0; Y = 32; W = 24; H = 9 }
    )) {
        $panels += @{
            id = $spec.Id; type = $spec.Type; title = $spec.Title
            gridPos = @{ x = $spec.X; y = $spec.Y; w = $spec.W; h = $spec.H }
            datasource = @{ type = "grafana-azure-monitor-datasource"; uid = $datasourceUid }
            targets = @((New-LogsTarget $queries[$spec.Key] $(if ($spec.Type -eq "timeseries") { "time_series" } else { "table" })))
            fieldConfig = @{ defaults = @{ decimals = 0 }; overrides = @() }
            options = $(if ($spec.Type -eq "barchart") { @{ stacking = "normal"; orientation = "horizontal"; legend = @{ displayMode = "list"; placement = "bottom" } } } else { @{} })
        }
    }
    $variables = @()
    foreach ($dimension in @("Customer", "Model")) {
        $variableQuery = New-LogsTarget ($base + "`n| where " + '$__timeFilter(TimeGenerated)' + "`n| distinct $dimension`n| order by $dimension asc")
        $variables += @{
            name = $dimension.ToLowerInvariant(); label = $dimension; type = "query"
            datasource = @{ type = "grafana-azure-monitor-datasource"; uid = $datasourceUid }
            query = $variableQuery; refresh = 2; multi = $true; includeAll = $true; sort = 1
            current = @{ text = "All"; value = '$__all'; selected = $true }; options = @()
        }
    }
    $dashboard = @{
        uid = "customer-model-token-usage"; title = "Customer token usage by model - imported samples"
        schemaVersion = 40; version = 0; editable = $true; timezone = "utc"
        tags = @("customer-tokens", "sample-import", "azure-monitor")
        time = @{ from = $begin.ToString("o"); to = $end.ToString("o") }; refresh = "5m"
        templating = @{ list = $variables }; panels = $panels
    }
    $directory = "$PSScriptRoot\dashboards"
    $null = New-Item -ItemType Directory -Path $directory -Force
    $dashboard | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath "$directory\customer-model-token-usage.json" -Encoding utf8
    $saved = Invoke-GrafanaRequest "POST" "/api/dashboards/db" @{ dashboard = $dashboard; overwrite = $true; message = "Configure customer/model token usage from imported Application Insights samples." }
    if ($SkipValidation) {
        [pscustomobject]@{
            DashboardUrl = "$endpoint$($saved.url)"
            DashboardUid = $dashboard.uid
            TimeFromUtc = $begin.ToString("o")
            TimeToUtc = $end.ToString("o")
        }
        return
    }

    $timeFilter = "TimeGenerated between (datetime($($begin.ToString('o'))) .. datetime($($end.ToString('o'))))"
    $validationQueries = @()
    foreach ($panel in $panels) {
        if (-not $panel.ContainsKey("targets")) { continue }
        $target = $panel.targets[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
        $target.refId = "P$($panel.id)"
        $target.azureLogAnalytics.query = $target.azureLogAnalytics.query.Replace(
            '$__timeFilter(TimeGenerated)', $timeFilter).Replace($selection, "true").Replace('$__interval', "5m")
        $target["maxDataPoints"] = 1000
        $target["intervalMs"] = 300000
        $validationQueries += $target
    }
    $validated = Invoke-GrafanaRequest "POST" "/api/ds/query" @{
        queries = $validationQueries; from = [string] $begin.ToUnixTimeMilliseconds(); to = [string] $end.ToUnixTimeMilliseconds()
    }
    foreach ($entry in $validated.results.GetEnumerator()) {
        if (($entry.Value.ContainsKey("error") -and $entry.Value.error) -or
            ($entry.Value.ContainsKey("status") -and $entry.Value.status -ge 400)) {
            throw "Grafana panel $($entry.Key) failed: $($entry.Value | ConvertTo-Json -Depth 10 -Compress)"
        }
        if (@($entry.Value.frames).Count -eq 0) { throw "Grafana panel $($entry.Key) returned no data frames." }
    }
    if ($validated.results.Count -ne $validationQueries.Count) { throw "Grafana omitted panel query results." }
    $variableQueries = @()
    foreach ($variable in $variables) {
        $target = $variable.query | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
        $target.refId = $variable.name
        $target.azureLogAnalytics.query = $target.azureLogAnalytics.query.Replace('$__timeFilter(TimeGenerated)', $timeFilter)
        $target["intervalMs"] = 300000
        $target["maxDataPoints"] = 1000
        $variableQueries += $target
    }
    $variableResults = Invoke-GrafanaRequest "POST" "/api/ds/query" @{
        queries = $variableQueries; from = [string] $begin.ToUnixTimeMilliseconds(); to = [string] $end.ToUnixTimeMilliseconds()
    }
    foreach ($entry in $variableResults.results.GetEnumerator()) {
        if (($entry.Value.ContainsKey("error") -and $entry.Value.error) -or
            @($entry.Value.frames).Count -eq 0 -or
            @($entry.Value.frames[0].data.values[0]).Count -eq 0) {
            throw "Grafana filter $($entry.Key) returned an error or no options."
        }
    }
    [pscustomobject]@{
        DashboardUrl = "$endpoint$($saved.url)"
        DashboardUid = $dashboard.uid
        ValidatedPanels = $validated.results.Count
        InputTokens = $validated.results.P2.frames[0].data.values[0][0]
        OutputTokens = $validated.results.P3.frames[0].data.values[0][0]
        RecordedTotal = $validated.results.P4.frames[0].data.values[0][0]
        RequestRecords = $validated.results.P5.frames[0].data.values[0][0]
        Customers = $variableResults.results.customer.frames[0].data.values[0]
        Models = $variableResults.results.model.frames[0].data.values[0]
        TimeFromUtc = $begin.ToString("o")
        TimeToUtc = $end.ToString("o")
    }
}
finally { $token = $null; $headers.Clear() }
