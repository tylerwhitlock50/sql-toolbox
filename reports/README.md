# SSRS Reports

SQL Server Reporting Services report definitions (`.rdl` files) generated from the canonical SQL queries in `queries/domains/`. These are the **operational layer** — printable, parameterized, subscribable lists that the buying / planning / CSR teams work *from* every day.

For the broader strategy (Tableau dashboards vs SSRS, phased rollout, ownership), see `../REPORTING_PROPOSAL.md`.

## Inventory

| # | File | Source query | Audience | Cadence |
|---|---|---|---|---|
| 1 | `buyer_po_action_list.rdl` | `purchasing_plan.sql` | Each buyer | Mon 6 AM, per-buyer subscription |
| 2 | `buyer_summary.rdl` | `purchasing_plan_by_buyer_summary.sql` | Buyer + manager | Mon 6 AM, alongside #1 |
| 3 | `daily_build_priority.rdl` | `shared_buildable_allocation.sql` | Shop floor, scheduling | Daily 6 AM, posted to floor |
| 4 | `material_shortage_expedite.rdl` | `material_shortage_vs_open_demand.sql` | Buyer, planner | Daily 6 AM |
| 5 | `past_due_po_followup.rdl` | `past_due_po_aging.sql` | Buyer | Mon + Wed |
| 6 | `past_due_so_list.rdl` | `past_due_so_aging.sql` | CSR, sales | Daily 6 AM |
| 7 | `vendor_otd_scorecard.rdl` | `vendor_otd_scorecard.sql` | Buyer, sourcing | Monthly |
| 8 | `production_release_list.rdl` | `make_plan_weekly.sql` | Production planner | Daily 6 AM |
| 9 | `so_fulfillment_risk.rdl` | `so_fulfillment_risk.sql` | CSR, sales | On-demand by SO# / customer |
| 10 | `wo_completion_forecast.rdl` | `fg_completion_forecast.sql` | CSR, plant manager | On-demand / daily |
| 11 | `stocking_policy_review.rdl` | `stocking_policy_recommendations.sql` | Materials manager | Quarterly |
| 12 | `open_wo_aging_and_wip.rdl` | `open_wo_aging_and_wip.sql` | Plant manager | Daily 6 AM |

## Deployment

### One-time setup

1. **Update the data source connection string** in each `.rdl`. They ship with `Data Source=YOUR_SERVER;Initial Catalog=VECA` as a placeholder. Either:
   - Edit each `.rdl` (find `YOUR_SERVER` and replace with your SQL Server host name), or
   - Replace the embedded `<DataSource>` block with a `<DataSourceReference>` to a shared data source (`.rds`) on the report server. **Strongly recommended for production** so credentials and host name aren't duplicated across 12 files.

   Example replacement in each RDL — replace this:
   ```xml
   <DataSource Name="VECA">
     <ConnectionProperties>...</ConnectionProperties>
     <rd:SecurityType>Integrated</rd:SecurityType>
     <rd:DataSourceID>...</rd:DataSourceID>
   </DataSource>
   ```
   with this:
   ```xml
   <DataSource Name="VECA">
     <DataSourceReference>/Shared Data Sources/VECA</DataSourceReference>
     <rd:SecurityType>None</rd:SecurityType>
     <rd:DataSourceID>...</rd:DataSourceID>
   </DataSource>
   ```

2. **Create the shared data source** on the report server: `/Shared Data Sources/VECA` pointing at the VECA database with whatever auth model your environment uses (Integrated for SSO, or a stored SQL credential for subscriptions).

3. **Test the data source** by previewing one report (e.g. `material_shortage_expedite.rdl`) before deploying the rest.

### Deploy via Report Builder / SSDT

1. Open the `.rdl` in Microsoft Report Builder or SQL Server Data Tools.
2. Connect Report Builder to your report server (`http://yourserver/reports` or `/reportserver`).
3. Save the report to a folder on the server (suggested layout below).
4. Repeat for each report.

### Deploy via PowerShell (bulk)

For deploying all 12 at once:

```powershell
$ReportServerUri = "http://yourserver/ReportServer/ReportService2010.asmx"
$Folder          = "/Operations"
$Reports         = Get-ChildItem -Path "C:\Users\TylerW\sql-toolbox\reports" -Filter "*.rdl"

$rs = New-WebServiceProxy -Uri $ReportServerUri -UseDefaultCredential

foreach ($r in $Reports) {
    $bytes  = [System.IO.File]::ReadAllBytes($r.FullName)
    $name   = [System.IO.Path]::GetFileNameWithoutExtension($r.Name)
    $warning = $null
    $rs.CreateCatalogItem("Report", $name, $Folder, $true, $bytes, $null, [ref]$warning) | Out-Null
    Write-Host "Deployed: $name"
}
```

## Suggested folder layout on the report server

```
/Operations
   /Buying           <- buyer_po_action_list, buyer_summary, past_due_po_followup, vendor_otd_scorecard
   /Production       <- daily_build_priority, production_release_list, open_wo_aging_and_wip,
                        wo_completion_forecast, material_shortage_expedite
   /Sales            <- past_due_so_list, so_fulfillment_risk
   /Inventory        <- stocking_policy_review
/Shared Data Sources
   VECA
```

## Subscription patterns

### Per-buyer PO list (data-driven subscription)

Set up a **data-driven subscription** on `buyer_po_action_list` and `buyer_summary` so each buyer gets only their parts:

1. Create a query in your `BuyerSubscriptions` admin table (or join to `APPLICATION_USER`):
   ```sql
   SELECT BUYER_USER_ID, EMAIL_ADDRESS, ROUTE_TO_FOLDER
   FROM APPLICATION_USER
   WHERE IS_BUYER = 1 AND ACTIVE_FLAG = 'Y';
   ```
2. In the subscription, map `BUYER_USER_ID` → report parameter `Buyer`, and `EMAIL_ADDRESS` → recipient.
3. Schedule: Mondays at 6:00 AM, deliver as PDF + Excel attachment.

### Daily standup pack (single subscription)

Create one subscription per day at 6:00 AM that emails a single PDF combining:
- `daily_build_priority` (Site = TDJ)
- `material_shortage_expedite` (Site = TDJ)
- `past_due_so_list` (Site = TDJ)

Send to the production-leadership distribution list.

### On-demand reports

`so_fulfillment_risk` and `wo_completion_forecast` are designed for ad-hoc lookups. No scheduled subscription — users open them in the SSRS portal and enter the customer / SO / WO they care about.

## Customizing the reports

The SQL is embedded inline in each `.rdl`'s `<CommandText>` block (search for `CDATA`). When the canonical query in `queries/domains/...` evolves, copy the updated SQL into the matching RDL. To keep the RDL working, preserve the SSRS parameter form:

- Replace `DECLARE @Site nvarchar(15) = NULL;` (and similar) at the top of the SQL with nothing — SSRS will pass these via `<QueryParameters>`.
- Reference parameters as `@Site`, `@Buyer`, etc. — they resolve to whatever the user entered.
- Keep the optional-filter pattern: `(@Param IS NULL OR @Param = '' OR column = @Param)` so blank means "all".

## Common edits

- **Server name in connection string**: search & replace `YOUR_SERVER` across all `.rdl` files.
- **Add a Department or Customer parameter**: add a new `<ReportParameter>` in `<ReportParameters>`, a matching `<QueryParameter>` in `<QueryParameters>`, and reference it in the embedded SQL `WHERE` clause.
- **Add a column to the printable layout**: add a `<TablixColumn>` to `<TablixColumns>`, add a `<TablixCell>` to both the header `<TablixRow>` and the detail `<TablixRow>`, and add a matching `<Field>` to `<Fields>` if it isn't there yet.
- **Change the title**: update the value in `txtTitle`.

## Performance notes

The BOM-driven reports (`buyer_po_action_list`, `buyer_summary`, `daily_build_priority`, `production_release_list`, `so_fulfillment_risk`) re-walk the engineering BOM every run. For large catalogues this can take 30–60 seconds. Two ways to speed up:

1. **Cache the report** on the SSRS side: in the report's properties, enable caching with a 1-hour expiration. Subsequent renders use the cached dataset.
2. **Materialize the heavy queries to staging tables** (recommended in `REPORTING_PROPOSAL.md` §6). A nightly SQL Agent job populates `rep_purchasing_plan`, `rep_build_priority`, etc.; the reports then read from those instead of re-running the BOM walk.

For Phase 1 deployment, caching is enough. For Phase 2+ when both Tableau and SSRS are reading the same data, switch to the staging-table model.
