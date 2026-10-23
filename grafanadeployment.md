# Deploy the customer/model token-usage dashboard

Import [grafanadeployment.json](grafanadeployment.json) into your own Grafana
instance, select your Azure Monitor data source, and then select your own
subscription and existing Log Analytics workspace from the dashboard dropdowns.
No tenant ID, subscription ID, workspace ID, resource group, customer, model,
credential, or sample date from the original deployment is embedded.

This JSON is a **Grafana dashboard export**, not an Azure Resource Manager
template. It creates the dashboard only. It does not create a workspace,
ingest CSV files, configure a live gateway exporter, or modify an existing
Application Insights component.

## 1. Prerequisites

- Azure Managed Grafana using Grafana 12 or later, or a compatible Grafana
  installation with the built-in **Azure Monitor** data source.
- An existing Log Analytics workspace containing **AppRequests** and
  **AppMetrics**, with the custom properties described below.
- **Grafana Editor** or **Grafana Admin** access to import dashboards.
  Configuring a data source typically also requires Grafana Admin.
- Azure authorization for the identity used by the Azure Monitor data source.
  Assign **Log Analytics Reader** on the selected workspace. Azure resource
  discovery also needs read access to the subscriptions/workspaces being listed.

The account importing the dashboard and the identity querying Azure logs are
different permission surfaces. Signing in to Grafana does not automatically
give its data source access to your workspace.

If you do not have Grafana yet, use the
[Azure Managed Grafana creation guide](https://learn.microsoft.com/azure/managed-grafana/quickstart-managed-grafana-portal):
choose your subscription, resource group, supported region, and Standard SKU;
enable a system-assigned managed identity and grant yourself Grafana Admin.
Use the smallest size suitable for your workload. **Managed Grafana is billable
while deployed**, even when nobody is viewing a dashboard. Log Analytics query,
ingestion, and retention charges depend on your existing setup.

## 2. Configure access to your existing workspace

For Azure Managed Grafana, prefer managed identity:

1. Open the Grafana Azure resource and its **Identity** page. Enable the
   system-assigned identity if necessary.
2. Open your existing Log Analytics workspace in Azure Portal.
3. Under **Access control (IAM)**, assign **Log Analytics Reader** to that
   Grafana managed identity, scoped to this workspace.
4. Ensure the identity has enough resource-read access for the subscription
   and workspace dropdowns to discover the desired workspace.
5. Allow new role assignments a few minutes to propagate.

Do not grant Owner or Contributor merely to read logs. If organizational rules
prohibit broader discovery access, use the manual-selection fallback below
instead of broadening permissions.

For self-managed Grafana, configure an
[Azure Monitor authentication method](https://grafana.com/docs/grafana/latest/datasources/azure-monitor/configure/)
appropriate to that host. Never put a client secret or bearer token in the
dashboard JSON.

The selected data source determines the Azure tenant and credentials. A
workspace in another tenant requires a data source authenticated for that
tenant; changing the dashboard's subscription selection is not cross-tenant
authentication.

## 3. Configure the Azure Monitor data source

1. Open Grafana's **Connections / Data sources** page.
2. Add **Azure Monitor**, or use a suitable existing Azure Monitor data source.
3. For Azure Managed Grafana, select **Managed Identity** authentication.
4. Set **Default Subscription** to an accessible subscription.
5. Save the configuration.

Use **Azure Monitor**, not Azure Data Explorer: these queries target Log
Analytics. Do not confuse a Log Analytics workspace with an Azure Monitor
workspace for managed Prometheus.

See [Microsoft's data-source guidance](https://learn.microsoft.com/azure/managed-grafana/how-to-data-source-plugins-managed-identity)
and [workspace permissions guidance](https://learn.microsoft.com/azure/managed-grafana/how-to-permissions).

## 4. Import the JSON

1. Download both this guide and [grafanadeployment.json](grafanadeployment.json).
2. In your own Grafana instance, choose **Dashboards > New > Import**.
3. Upload `grafanadeployment.json`.
4. Choose your dashboard folder and, if desired, change its name or UID.
5. Map the **Azure Monitor** import input to the data source configured above.
6. Select **Import**.

The file uses Grafana's normal data-source import mapping. Do not paste the
unmodified file into `POST /api/dashboards/db`: that endpoint does not resolve
the `${DS_AZURE_MONITOR}` import placeholder. For automation, use Grafana's
dashboard-import workflow with an explicit data-source input mapping, or
replace that placeholder with the destination data-source UID first.

The portable dashboard UID is `customer-model-tokens-portable`. Importing it
does not overwrite the original sample dashboard, which has a different UID.
To maintain multiple copies, assign a different UID on each import.

## 5. Select your workspace and filters

Use the dropdowns at the top in this order:

1. **Subscription**: choose the subscription containing your workspace.
2. **Log Analytics workspace**: choose an existing workspace in that subscription.
3. **Customer**: select one or more customers, or **All**.
4. **Model**: select one or more models, or **All**.
5. Choose a time range containing your data; the default is **last 24 hours**,
   displayed in UTC.

Workspace values are full Azure resource IDs returned by the Azure Monitor
data source. All nine data panels and both customer/model variable queries use
the selected workspace; none use the original deployment's workspace.

The workspace selection updates the customer and model lists. Refresh the
dashboard after new customers or models arrive. Historical samples require
selecting their original UTC date rather than expecting them in the current
time window.

### Manual selection when discovery is restricted

If the data source can query a known workspace but cannot list it:

1. Open **Dashboard settings > Variables**.
2. Change `subscription` to **Text box**, preserving its exact variable name,
   and enter your subscription GUID.
3. Change `workspace` to **Text box**, preserving its exact variable name, and
   enter the workspace's full resource ID:

   ```text
   /subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.OperationalInsights/workspaces/<workspace-name>
   ```

4. Save the dashboard and reload it.

Use the Azure resource ID, **not** the workspace's separate GUID/customer ID.
This bypasses resource enumeration only; it does not bypass workspace RBAC or
network restrictions.

## 6. Required telemetry schema and token semantics

An arbitrary workspace does not automatically contain token-usage telemetry.
The selected workspace must contain these tables and fields:

| Table | Field | Meaning |
|---|---|---|
| AppRequests | `TimeGenerated` | Request timestamp |
| AppRequests | `Properties["Subscription Name"]` | Customer label |
| AppRequests | `Properties["Response-x-aigw-model"]` | Model label |
| AppRequests | `Properties["Response-x-aigw-quota-consumed"]` | Input token amount, only if your source policy defines it that way |
| AppMetrics | `TimeGenerated` | Metric timestamp |
| AppMetrics | `Properties.Customer` | Customer label |
| AppMetrics | `Properties.Model` | Model label |
| AppMetrics | `Name` | Metric name; output counts only `Completion Tokens` |
| AppMetrics | `Sum` | Already-aggregated metric value |
| AppMetrics | `ItemCount` | Number of measurements represented by the metric |

Both tables are required, even if one currently has no rows in the chosen
time range. Rows without the required customer/model or numeric token fields
are not included in the recorded-token summaries.

**The quota-consumed header is a custom rule contract, not a standard
Application Insights input-token field.** Confirm its meaning in your own
gateway before using it. If your tenant uses other property keys or metric
names, update every affected panel query and the customer/model variable
queries in Grafana, or adapt the JSON before importing.

### Aggregation rules

- **Input:** sum the mapped quota-header amounts in AppRequests.
- **Output:** sum AppMetrics `Sum` only where `Name == "Completion Tokens"`.
- **Recorded total:** the above input plus output, not an independent
  `Total Tokens` metric.
- Never multiply a metric's `Sum` by `ItemCount`.
- Do not add prompt, cached, audio, prediction, and total-token categories
  together: some are overlapping or subsets of other metrics.
- The metric-detail panel shows those other measurements separately.
- Missing input/output samples are not proven zero usage. The coverage table
  identifies which directions have records for each customer/model pair.
- These are operational summaries, not a reconciliation-grade billing ledger.
  Sampling, duplicate ingestion, and incomplete telemetry affect totals.

The dashboard includes four stat cards, customer/model bar charts, an
input/output time series, a customer/model coverage table, and metric detail.
It reads any compatible existing telemetry, not just imported CSV samples.

## 7. Troubleshooting and access boundaries

| Symptom | Action |
|---|---|
| No data sources offered during import | Configure an Azure Monitor data source first. |
| Empty Subscription list | Set the data source's Default Subscription and check its authentication/discovery permissions. |
| Empty workspace list | Select the correct subscription; check resource discovery access or use the text-box fallback. |
| HTTP 401/403 | Check the data-source identity's workspace permissions, tenant, role propagation, and workspace network access. |
| `Failed to resolve table` | Select a workspace containing the required AppRequests/AppMetrics tables. |
| Panels are empty | Select the correct time range and review the custom-property mapping and metric names. |
| Only one direction appears | The selected model/time slice may have only input or output telemetry; inspect the coverage table. |
| Old customers remain in dropdowns | Reload the dashboard or change the time range to refresh its variable queries. |
| Totals appear inflated | Check for duplicate source ingestion and overlapping metric categories; do not multiply Sum by ItemCount. |

Customer/model filters are **not security boundaries**. Anyone able to use
this dashboard/data source may be able to query other authorized customers'
records. For external customer access, design separate data-source permissions,
workspace/RBAC isolation, or another appropriate authorization boundary.

## References

- [Grafana dashboard import](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/import-dashboards/)
- [Azure Monitor dashboard variables](https://grafana.com/docs/grafana/latest/datasources/azure-monitor/template-variables/)
- [AppRequests schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/apprequests)
- [AppMetrics schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/appmetrics)
