# Customer/model token usage: CSV samples and Managed Grafana

This independent Terraform root owns only the resources in `rg-law`:

| Resource | Name |
|---|---|
| Log Analytics, Analytics plan, 30-day retention | `law-customer-tokens-8ps1sz` |
| Workspace-based Application Insights | `appi-token-import-8ps1sz` |
| Azure Managed Grafana, Standard X1 | `amg-tokens-8ps1sz` |

All resources are in Sweden Central. Grafana uses its system-assigned managed
identity with **Log Analytics Reader on this workspace only**. The deploying
operator receives Grafana Admin on this Grafana instance and Monitoring Metrics
Publisher on this Application Insights component. No client secret or Grafana
API key is created. Application Insights and the workspace disable local
authentication; the import uses Azure CLI sign-in. This does not change the
existing AI Gateway's client key authentication or Foundry managed identity.

**Costs:** Managed Grafana Standard X1 is billable while deployed, even when
not viewing a dashboard. Log Analytics ingestion/retention can also incur
charges. The CSVs contain only 20 small records, but this is not a free hosting
configuration.

## Exact table names

The original source files were data exports with 10 records each, not
table-definition files. Additional CSV rows can be imported incrementally.
`AppRequests` and `AppMetrics` are standard Application Insights tables and
[do not support direct Logs Ingestion API writes](https://learn.microsoft.com/azure/azure-monitor/reference/tables/apprequests).
The importer reconstructs supported request and metric telemetry and sends it
to the component's **Microsoft Entra authenticated `v2.1/track` endpoint**.
Application Insights routes the records into the exact requested workspace
tables, without a `_CL` suffix.

The original UTC event times, request fields, metric aggregation counts/sums,
and custom properties are retained. Workspace/resource identity fields such
as `TenantId`, `_ResourceId`, `IKey`, and `ResourceGUID` are assigned by the new
destination, not copied as if the old tenant's resources existed here. Client
IP/location enrichment is not replayed. Each record has `CsvRowId`, `CsvBatchId`,
`CsvSourceFile`, `CsvSourceTimestamp`, and `TelemetryOrigin` custom properties.

No API policy or live exporter in the existing gateway has been changed.
**These are imported examples, not a live gateway telemetry feed.**

## Token interpretation and expected sample totals

| Direction | Table and mapping |
|---|---|
| Input | `AppRequests.Properties["Response-x-aigw-quota-consumed"]` |
| Input customer/model | `Properties["Subscription Name"]` / `Properties["Response-x-aigw-model"]` |
| Output | `AppMetrics.Sum` only where `Name == "Completion Tokens"` |
| Output customer/model | `Properties.Customer` / `Properties.Model` |

The request header is interpreted as input tokens according to the stated
source custom-rule design. It is not a standard Application Insights input-token
field; verify that rule before using this mapping for production accounting.

For the original 10-row exports:

- `ford` / `claude-opus-5-5`: **22,400 recorded input tokens** in 10 requests.
- `ford` / `gpt-6.1-sol`: **1,865 recorded output tokens**.
- Recorded input plus output: **24,265**, not a complete billing total.
- The initial import created 10 request rows and 10 metric rows.

The samples cover different model/time combinations. Missing input or output
rows do not prove zero usage. The dashboard's coverage table identifies this.
The metric export also contains Prompt Tokens, Total Tokens, cache, audio,
and prediction submetrics. They appear in a separate breakdown, not summed
as output or added again to the recorded total.

`Sum` already represents the aggregate metric value. **Never multiply it by
`ItemCount`**; that field is the number of aggregated measurements.

## Deploy, import, and publish

Use PowerShell 7, Terraform 1.9+, and an authorized Azure CLI session in the
configured subscription:

```powershell
Set-Location .\terraform\token-observability
terraform init
terraform validate
terraform plan -out=observability.tfplan
terraform apply observability.tfplan

.\tests\Test-TokenCsv.ps1
.\Import-TokenUsage.ps1 -ValidateOnly
.\Import-TokenUsage.ps1
.\Publish-TokenDashboard.ps1
```

The default CSV paths are `AppRequests.csv` and `AppMetrics.csv` in the signed-in
Windows user's Downloads folder. Override `-RequestsPath` and `-MetricsPath`
when needed. Source CSVs and credentials are not copied into the repository.

The importer checks content-based row identifiers before sending records,
skips rows already visible, and waits for every source identifier to become queryable.
Appending or reordering CSV rows does not change existing row identities.
Original imports that used whole-file-hash identifiers are recognized by their
stored telemetry content without rewriting or resending those records. Repeated
identical source rows retain separate occurrence identifiers.
Do not start concurrent imports of the same files. If a run loses connectivity
or times out after submission, allow ingestion to settle before retrying.
`-ValidateOnly` parses and checks totals without connecting to Azure.
Use `-WhatIf` to see how many rows are already imported and pending without
submitting telemetry.

Original timestamps are not silently rebased to the present. Pending rows
older than 48 hours are rejected by the replay script; these original files
cannot be freshly replayed indefinitely. Data already imported remains
queryable for its configured retention.

`Publish-TokenDashboard.ps1` creates/updates the Azure Monitor data source
`customer-token-logs`, publishes dashboard UID `customer-model-token-usage`,
and executes every data-panel query through **Grafana's managed identity**.
It also generates the reusable
[dashboard JSON](dashboards/customer-model-token-usage.json). Both the data
source and dashboard use stable UIDs, so rerunning publication updates rather
than duplicating them.
Use `.\Publish-TokenDashboard.ps1 -SkipValidation` to publish without running
the optional panel and filter query checks.

The dashboard has customer/model multi-select filters, input/output/combined
stat panels, customer/model breakdowns, a time series, a coverage table, and
all-metrics detail. Its initial range is the imported samples' UTC calendar
day(s), so reopening it tomorrow does not accidentally hide the historical
examples. The supplied files select 23 October 2026. Choose a relative time
range when a live telemetry feed is configured later.

The shared [token-usage KQL](queries/token-usage.kql) is the authoritative
dashboard aggregation. Terraform states and plans contain sensitive outputs
and are ignored; protect them locally or migrate to an appropriately secured
remote backend. Do not apply historical saved plans after changing the setup.
