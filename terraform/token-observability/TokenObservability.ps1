#requires -Version 7.0
Set-StrictMode -Version Latest

function Get-ObservabilityOutputs {
    $json = & terraform "-chdir=$PSScriptRoot" output -json
    if ($LASTEXITCODE -ne 0) { throw "Cannot read the token-observability Terraform outputs." }
    $values = $json | ConvertFrom-Json -AsHashtable
    $result = @{}
    foreach ($entry in $values.GetEnumerator()) { $result[$entry.Key] = $entry.Value.value }
    return $result
}

function Get-ObservabilityAccessToken([string] $Resource) {
    $token = & az account get-access-token --resource $Resource --query accessToken --output tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Cannot obtain an Azure access token for $Resource."
    }
    return $token
}

function Invoke-TokenWorkspaceQuery([string] $WorkspaceId, [string] $Query) {
    $token = Get-ObservabilityAccessToken "https://api.loganalytics.io"
    try {
        $response = Invoke-RestMethod -Method Post `
            -Uri "https://api.loganalytics.io/v1/workspaces/$WorkspaceId/query" `
            -Headers @{ Authorization = "Bearer $token" } -ContentType "application/json" `
            -Body (@{ query = $Query } | ConvertTo-Json -Compress) -TimeoutSec 90
        if ($null -ne $response.PSObject.Properties["error"]) {
            throw "Log Analytics query returned an error: $($response.error | ConvertTo-Json -Depth 8 -Compress)"
        }
        return $response
    }
    finally { $token = $null }
}

function ConvertTo-NonnegativeNumber([string] $Value, [string] $Field) {
    $number = 0.0
    if (-not [double]::TryParse($Value, [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref] $number) -or
        -not [double]::IsFinite($number) -or $number -lt 0) {
        throw "Invalid nonnegative numeric field '$Field'."
    }
    return $number
}

function Get-TokenRowFingerprint(
    [string] $Table, [DateTimeOffset] $Time, [string] $Name, [string] $RequestId,
    [double] $Value, [long] $Count, [double] $Minimum, [double] $Maximum,
    [System.Collections.IDictionary] $Properties
) {
    $keys = [string[]] @($Properties.Keys)
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    $dimensions = [ordered]@{}
    foreach ($key in $keys) {
        if ($key.StartsWith("Csv", [StringComparison]::Ordinal) -or
            $key.StartsWith("_MS.", [StringComparison]::Ordinal) -or $key -eq "TelemetryOrigin") { continue }
        $dimensions[$key] = [Convert]::ToString($Properties[$key], [Globalization.CultureInfo]::InvariantCulture)
    }
    $identity = @($Table, $Time.ToUniversalTime().ToString("o"), $Name, $RequestId,
        $Value, $Count, $Minimum, $Maximum, $dimensions) | ConvertTo-Json -Depth 20 -Compress
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes($identity))).ToLowerInvariant()
}

function ConvertTo-TokenUtcTime($Value) {
    if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
    if ($Value -is [DateTime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) { $Value = [DateTime]::SpecifyKind($Value, [DateTimeKind]::Utc) }
        return [DateTimeOffset]::new($Value).ToUniversalTime()
    }
    return [DateTimeOffset]::Parse([string] $Value, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
}

function ConvertTo-TokenTelemetry([string] $Path, [ValidateSet("AppRequests", "AppMetrics")] [string] $Table) {
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $hash = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLowerInvariant()
    $rows = @(Import-Csv -LiteralPath $resolved -Encoding utf8)
    if ($rows.Count -eq 0) { throw "$Table CSV has no records." }
    $required = @("TimeGenerated [UTC]", "Name", "Properties", "ItemCount")
    $required += if ($Table -eq "AppRequests") {
        @("Id", "DurationMs", "ResultCode", "Success", "Url", "Measurements")
    } else { @("Sum", "Min", "Max") }
    foreach ($field in $required) {
        if ($null -eq $rows[0].PSObject.Properties[$field]) { throw "$Table CSV is missing '$field'." }
    }
    $result = @()
    $occurrences = @{}
    for ($index = 0; $index -lt $rows.Count; $index++) {
        $row = $rows[$index]
        $time = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse($row."TimeGenerated [UTC]",
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal, [ref] $time)) {
            throw "$Table row $($index + 1) has an invalid UTC timestamp."
        }
        $properties = $row.Properties | ConvertFrom-Json -AsHashtable
        if ($properties -isnot [System.Collections.IDictionary]) { throw "$Table properties must be a JSON object." }
        $count = ConvertTo-NonnegativeNumber $row.ItemCount "ItemCount"
        if ($count -lt 1 -or $count -ne [Math]::Floor($count)) { throw "ItemCount must be a positive integer." }
        $properties["CsvBatchId"] = "$Table-$hash"
        $properties["CsvSourceFile"] = [IO.Path]::GetFileName($resolved)
        $properties["CsvSourceTimestamp"] = $time.ToUniversalTime().ToString("o")
        $properties["TelemetryOrigin"] = "Imported CSV sample"
        $tags = @{ "ai.internal.sdkVersion" = "csv-import:1.0" }
        $tagFields = @{
            AppRoleName = "ai.cloud.role"; AppRoleInstance = "ai.cloud.roleInstance"
            AppVersion = "ai.application.ver"; OperationName = "ai.operation.name"
            OperationId = "ai.operation.id"; ParentId = "ai.operation.parentId"
            SessionId = "ai.session.id"; UserId = "ai.user.id"
            UserAuthenticatedId = "ai.user.authUserId"; UserAccountId = "ai.user.accountId"
            SyntheticSource = "ai.operation.syntheticSource"
        }
        foreach ($field in $tagFields.Keys) {
            if ($null -ne $row.PSObject.Properties[$field] -and -not [string]::IsNullOrWhiteSpace($row.$field)) {
                $tags[$tagFields[$field]] = $row.$field
            }
        }
        if ($Table -eq "AppRequests") {
            foreach ($dimension in @("Subscription Name", "Response-x-aigw-model", "Response-x-aigw-quota-consumed")) {
                if (-not $properties.Contains($dimension) -or [string]::IsNullOrWhiteSpace([string] $properties[$dimension])) {
                    throw "AppRequests row $($index + 1) is missing '$dimension'."
                }
            }
            $tokens = ConvertTo-NonnegativeNumber $properties["Response-x-aigw-quota-consumed"] "request quota header"
            $duration = ConvertTo-NonnegativeNumber $row.DurationMs "DurationMs"
            $baseData = @{
                ver = 2; id = $row.Id; name = $row.Name; responseCode = $row.ResultCode
                duration = [TimeSpan]::FromMilliseconds($duration).ToString("c")
                success = [bool]::Parse($row.Success); url = $row.Url
                properties = $properties; measurements = ($row.Measurements | ConvertFrom-Json -AsHashtable)
            }
            if ($null -ne $row.PSObject.Properties["Source"] -and $row.Source) { $baseData.source = $row.Source }
            $baseType = "RequestData"
            $suffix = "Request"
            $customer = [string] $properties["Subscription Name"]
            $model = [string] $properties["Response-x-aigw-model"]
        } else {
            foreach ($dimension in @("Customer", "Model")) {
                if (-not $properties.Contains($dimension) -or [string]::IsNullOrWhiteSpace([string] $properties[$dimension])) {
                    throw "AppMetrics row $($index + 1) is missing '$dimension'."
                }
            }
            $sum = ConvertTo-NonnegativeNumber $row.Sum "Sum"
            $minimum = ConvertTo-NonnegativeNumber $row.Min "Min"
            $maximum = ConvertTo-NonnegativeNumber $row.Max "Max"
            if ($minimum -gt $maximum) { throw "Metric Min exceeds Max." }
            $baseData = @{
                ver = 2
                metrics = @(@{ name = $row.Name; kind = "Aggregation"; value = $sum; count = [int] $count; min = $minimum; max = $maximum })
                properties = $properties
            }
            $baseType = "MetricData"
            $suffix = "Metric"
            $tokens = if ($row.Name -eq "Completion Tokens") { $sum } else { 0.0 }
            $customer = [string] $properties["Customer"]
            $model = [string] $properties["Model"]
        }
        $identity = @{
            Table = $Table; Time = $time; Name = $row.Name; Properties = $properties; Count = [long] $count
            RequestId = $(if ($Table -eq "AppRequests") { $row.Id } else { "" })
            Value = $(if ($Table -eq "AppRequests") { $tokens } else { $sum })
            Minimum = $(if ($Table -eq "AppMetrics") { $minimum } else { 0.0 })
            Maximum = $(if ($Table -eq "AppMetrics") { $maximum } else { 0.0 })
        }
        $fingerprint = Get-TokenRowFingerprint @identity
        if (-not $occurrences.ContainsKey($fingerprint)) { $occurrences[$fingerprint] = 0 }
        $occurrences[$fingerprint]++
        $rowId = "$Table-v2-$fingerprint-$($occurrences[$fingerprint])"
        $properties["CsvRowId"] = $rowId
        $result += [pscustomobject]@{
            Table = $Table; RowId = $rowId; Fingerprint = $fingerprint; Time = $time; Customer = $customer; Model = $model
            CountedTokens = $tokens; MetricName = $row.Name
            Envelope = @{
                name = "Microsoft.ApplicationInsights.$suffix"
                time = $time.ToUniversalTime().ToString("o")
                tags = $tags; sampleRate = $(if ($Table -eq "AppRequests") { 100.0 / $count } else { 100.0 })
                data = @{ baseType = $baseType; baseData = $baseData }
            }
        }
    }
    return $result
}
