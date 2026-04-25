# CLAUDE.md — inventory / part_information

Rules for part-level planning, on-hand, exceptions, and stocking-policy queries (VECA).

## Scope

Queries here answer: *"What do we have?"* / *"What's moving?"* / *"Where are the exceptions?"* / *"What should the reorder point be?"*

## Core tables & grain

| Table | Grain | Purpose |
|---|---|---|
| `PART` | 1 row per part (cross-site) | Master metadata + denormalized `QTY_ON_HAND` / `QTY_IN_DEMAND` rollups |
| `PART_SITE` | 1 row per (SITE_ID, PART_ID) | Site-specific overrides of lead time, safety stock, ROP, order policy, on-hand, etc. |
| **`PART_SITE_VIEW`** | 1 row per (SITE_ID, PART_ID) | **Use this.** `ISNULL(PART_SITE.col, PART.col)` fallback baked in. |
| `PART_LOCATION` | 1 row per (PART_ID, WAREHOUSE_ID, LOCATION_ID) | Bin-level on-hand — sum across locations = site on-hand |
| `INVENTORY_TRANS` | 1 row per movement | `TYPE` in `I`/`O`, `CLASS` in `I`/`R`/`A` — the audit trail |
| `TW_MRP_EXCEPTIONS` | 1 row per (site, part) with active exception | Pre-computed flags from MRP: `stockout_qty`, `overstock_qty`, `issue_late_days`, `order_late_days` |
| `REQUIREMENT` | WO component requirement | 5-part WO key + `PART_ID`; `calc_qty`, `issued_qty`, `status` |
| `WORK_ORDER` | 5-part composite key | Manufacturing job state |
| `CUSTOMER_ORDER` / `CUST_ORDER_LINE` | SO header/line | Sales demand |
| `PURCHASE_ORDER` | PO header | Inbound supply (for LT calc) |

## The PART_SITE_VIEW rule

**Always use `PART_SITE_VIEW` instead of manually joining `PART` + `PART_SITE`.**

It already does:
```sql
ISNULL(PART_SITE.PLANNING_LEADTIME, PART.PLANNING_LEADTIME) AS PLANNING_LEADTIME,
ISNULL(PART_SITE.SAFETY_STOCK_QTY,  PART.SAFETY_STOCK_QTY)  AS SAFETY_STOCK_QTY,
ISNULL(PART_SITE.QTY_ON_HAND,       PART.QTY_ON_HAND)       AS QTY_ON_HAND,
...
```

**Caveat:** `PART_SITE_VIEW` is an `INNER JOIN` internally. A part with no `PART_SITE` row at a given site does **not** appear in the view for that site. If you need parts-never-stocked-here, go to `PART` directly.

## On-hand vs available vs in-demand

| Field | Definition | Source |
|---|---|---|
| `QTY_ON_HAND` | Physical inventory at the site | `PART_SITE_VIEW.QTY_ON_HAND` (denorm); reconciles to `SUM(INVENTORY_TRANS: +I, -O)` |
| `QTY_AVAILABLE_ISS` | Free to pick (on-hand − allocated) | `PART_SITE_VIEW.QTY_AVAILABLE_ISS` |
| `QTY_AVAILABLE_MRP` | What MRP sees as free (OH + on-order − in-demand) | `PART_SITE_VIEW.QTY_AVAILABLE_MRP` — **does not** reserve safety stock |
| `QTY_ON_ORDER` | Inbound open PO | `PART_SITE_VIEW.QTY_ON_ORDER` |
| `QTY_IN_DEMAND` | Open SO + open WO requirements | `PART_SITE_VIEW.QTY_IN_DEMAND` (denorm; see fix_scripts/3) |
| `QTY_COMMITTED` | Manually reserved to specific SOs | `PART_SITE_VIEW.QTY_COMMITTED` |

**Reconciliation:** the denormalized fields drift. Fix scripts 1 and 3 recompute them from primary sources.

## Demand calculation (canonical)

Open demand = open SO + open WO requirements. The open-SO filter matches the sales domain:

```sql
-- Sales component
WHERE h.STATUS IN ('R','F') AND l.LINE_STATUS = 'A'
qty = SUM(ORDER_QTY - ISNULL(TOTAL_SHIPPED_QTY, 0))

-- Manufacturing component
WHERE w.TYPE = 'W' AND w.STATUS IN ('F','R') AND r.STATUS IN ('F','R')
qty = SUM(ISNULL(r.CALC_QTY, 0) - ISNULL(r.ISSUED_QTY, 0))
```

**Crucial:** requirement status must match work-order status. A cancelled WO with `r.STATUS='R'` double-counts demand. See `../fix_scripts/2-match_requirement_status.sql`.

## Lead-time observations (for stocking policy)

```sql
SELECT DATEDIFF(day, po.ORDER_DATE, it.TRANSACTION_DATE) AS LT_DAYS
FROM INVENTORY_TRANS it
INNER JOIN PURCHASE_ORDER po ON po.ID = it.PURC_ORDER_ID
WHERE it.TYPE = 'I' AND it.CLASS = 'R'                 -- PO receipts only
  AND it.QTY > 0
  AND DATEDIFF(day, po.ORDER_DATE, it.TRANSACTION_DATE) BETWEEN 0 AND 365
```

**Filters are non-negotiable:**
- `TYPE='I'` and `CLASS='R'` → purchase receipt only (no adjustments, scrap, returns)
- `QTY > 0` → exclude reversals
- `LT_DAYS BETWEEN 0 AND 365` → drop anomalies

## Usage / velocity history

```sql
WHERE it.TYPE = 'O' AND it.CLASS = 'I' AND it.QTY > 0   -- manufacturing issues only
-- Windows used in planning_information.sql:
--   used_qty_last_7d / 30d / 90d / 180d / 365d
--   issue_txn_last_30d / 90d / 365d    (transaction count)
--   last_issue_date
```

Other TYPE/CLASS combinations (scrap, adjustments) exist — filter them out unless you explicitly want them.

## Stocking-policy formula (stocking_policy_recommendations.sql)

Standard safety-stock / ROP in monthly units:

```
SS  = z * sqrt( LT_mo * sigma_d^2  +  d_avg^2 * sigma_LT_mo^2 )
ROP = d_avg * LT_mo + SS

where:
  z               = service-level Z (1.28=90%, 1.65=95%, 2.05=98%, 2.33=99%)
  d_avg, sigma_d  = mean and stddev of monthly demand (qty)
  LT_mo, sigma_LT = mean and stddev of LT (days / 30)
```

**Inputs and gates:**
- Monthly demand = `SUM(INVENTORY_TRANS.QTY)` grouped by month, `TYPE='O' AND QTY > 0`
- Requires **≥ 4 months** of demand history AND **≥ 2 LT observations**; else `'NO HISTORY'`.
- `@ServiceLevelZ` defaults to 1.65 (95%). Not per-ABC — parameterize if critical A-items need 99%.
- Only `PURCHASED='Y'` parts, status not `'I'` (inactive).

**Action flags (vs current SS):**
- `NEW POLICY` — current SS = 0, recommended > 0
- `INCREASE SS` — recommended > 1.5 × current AND delta > 5 units
- `DECREASE SS` — recommended < 0.5 × current AND current > 5 units
- `OK` — within 5 units

Recommendations are **not mandates** — planners overlay criticality, single-source risk, shelf life.

## Planning snapshot (planning_information.sql)

Pulls together on-hand + demand + supply + velocity + MRP exceptions + projected depletion.

Key derived columns:
```sql
avg_daily_usage_365d       = used_qty_last_365d / 365.0
projected_days_of_supply   = QTY_ON_HAND / NULLIF(avg_daily_usage_365d, 0)
expected_depletion_date    = DATEADD(DAY, projected_days_of_supply, GETDATE())

-- Usage-vs-on-hand classification
active_qty    = MIN(QTY_ON_HAND, used_qty_last_365d)         -- if usage > 0
excess_qty    = QTY_ON_HAND - used_qty_last_365d             -- if OH > 1y usage
obsolete_qty  = QTY_ON_HAND                                   -- if zero usage in 365d
```

**Known gap:** `current_unit_cost` is NULL in the file (commented: "REPLACE THIS"). Active/excess/obsolete *value* columns stay NULL until someone wires in a cost field.

## Exception report (exceptions_report.sql)

Consumes **`TW_MRP_EXCEPTIONS`** — pre-computed by the MRP module. We don't recompute flags; we join them to `PART_SITE_VIEW` for context.

Common exception types (column names):
- `stockout_qty > 0` — open demand > (on-hand + on-order)
- `overstock_qty > 0` — supply + buffer exceeds demand + SS
- `issue_late_days` — demand past its issue date, unissued
- `order_late_days` — PO overdue from expected receipt

## Location-vs-site reconciliation (inventory_vs_part_location_qty_mismatch.sql)

Compares `SUM(PART_LOCATION.QTY)` vs `SUM(INVENTORY_TRANS: +I, -O)` at (part, warehouse, location) grain. Non-zero diffs surface orphaned locations, missed transfers, or cycle-count errors. `ORDER BY ABS(qty_diff) DESC` — investigate largest first. **Diagnostic only, no writes.**

## Site filtering

```sql
DECLARE @Site nvarchar(15) = NULL;   -- NULL = all sites
WHERE (@Site IS NULL OR psv.SITE_ID = @Site)
  AND (@Site IS NULL OR it.SITE_ID  = @Site)
```

## Files in this folder

| File | Purpose |
|---|---|
| `planning_information.sql` | Part-level planning snapshot: OH, demand, supply, velocity, SS/ROP, MRP exceptions, depletion |
| `exceptions_report.sql` | MRP exception surface (joins `TW_MRP_EXCEPTIONS` to `PART_SITE_VIEW`) |
| `stocking_policy_recommendations.sql` | Recommended SS + ROP from demand × LT variability vs current setting |
| `inventory_vs_part_location_qty_mismatch.sql` | Reconcile `PART_LOCATION` vs `INVENTORY_TRANS` — diagnostic, no writes |

## Gotchas

- **Negative on-hand** is possible (more issues than receipts somewhere). `NULLIF(..., 0)` keeps calcs safe, but investigate the source — fix script 1 will perpetuate the error if not corrected in `INVENTORY_TRANS`.
- **Inactive parts (`STATUS='I'`)** are filtered out of `stocking_policy_recommendations.sql` only. Other queries still show them — add the filter if your use case excludes inactives.
- **UOM mismatches** aren't handled here. All qty fields are assumed to be in stock UOM. If a PO was placed in purchase UOM, normalize upstream (see `../../supply_chain/purchasing/open_purchase_orders_uom_normalized.sql`).
- **Service-level Z is fixed** at 1.65. No per-ABC or per-part override in-query.
- **Phantom demand** from old abandoned WOs: if the WO is cancelled but `REQUIREMENT.STATUS` is still `'R'`, the part looks in-demand. Run fix script 2 periodically.
- **`PART_SITE_VIEW` drops parts without a `PART_SITE` row** at the site. Multi-site parts not yet added to a site won't appear — query `PART` directly for those.
