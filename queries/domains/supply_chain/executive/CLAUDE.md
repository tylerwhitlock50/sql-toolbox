# CLAUDE.md — supply_chain / executive

Rules for executive-level KPI rollups and waste/stagnation reports (VECA).

## Scope

Top-line numbers for leadership: backlog $, WIP $, inventory $, turns, OTD %, shortages, stagnant inventory. One-row-per-site (or one-row-per-issue) summaries designed for dashboards.

These queries are **self-contained** — they aggregate directly from base tables rather than consuming other canonical queries. That keeps dependencies simple but means logic is duplicated across folders; changes to canonical filters must be made in multiple places.

## Executive KPI composition (executive_supply_chain_kpis.sql)

One row per site (plus `'_ALL_SITES_'` rollup if multi-site). 13 headline KPIs.

### KPI sources

| KPI | Source + formula |
|---|---|
| `BACKLOG_VALUE` | `SUM((ORDER_QTY - TOTAL_SHIPPED_QTY) * UNIT_PRICE)` on open SO lines |
| `PAST_DUE_BACKLOG_VALUE` | Same, filtered to `target_ship_date < @AsOfDate` |
| `WIP_VALUE` | `SUM(ACT_MATERIAL + ACT_LABOR + ACT_BURDEN + ACT_SERVICE)` from open `WORK_ORDER` (TYPE='W', STATUS NOT IN ('X','C')) |
| `INVENTORY_VALUE` | `SUM(QTY_ON_HAND * UNIT_MATERIAL_COST)` from `PART_SITE_VIEW` |
| `INVENTORY_TURNS_T12` | `ISSUE_VALUE_T12 / INVENTORY_VALUE` |
| `ISSUE_VALUE_T12` | Proxy annual COGS-material-used from `INVENTORY_TRANS` (TYPE='O') last 12 months |
| `OPEN_PO_VALUE` | `SUM((ORDER_QTY - TOTAL_RECEIVED_QTY) * UNIT_PRICE)` on open PO lines |
| `PAST_DUE_PO_VALUE` | Same, filtered to target recv date past due |
| `VENDOR_OTD_PCT_T90` | Receipts on time / receipts with promise, trailing 90 days |
| `CUSTOMER_OTD_PCT_T90` | Shipments on time / total shipments, trailing 90 days |
| `PARTS_SHORT_COUNT` | Count where `(QTY_ON_HAND + OPEN_PO_QTY - OPEN_REQ_QTY) < 0` |
| `SHORTAGE_VALUE_AT_STD` | `SUM(abs_shortfall * UNIT_MATERIAL_COST)` |
| `STAGNANT_VALUE` | `SUM(QTY_ON_HAND * UNIT_MATERIAL_COST)` where last movement older than `@StagnantMonths` |

### Canonical filters used internally

These should match the rest of the codebase — if you change them here, change them everywhere:

```sql
-- Open SO
CO.STATUS IN ('R','F') AND COL.LINE_STATUS = 'A' AND ORDER_QTY > TOTAL_SHIPPED_QTY

-- Open PO
P.STATUS / PL.LINE_STATUS NOT IN ('X','C') AND ORDER_QTY > TOTAL_RECEIVED_QTY

-- Open WO
WO.TYPE = 'W' AND STATUS NOT IN ('X','C')

-- Open WO requirement
REQUIREMENT.STATUS = 'U' AND (CALC_QTY - ISSUED_QTY) > 0
```

### Multi-site rollup

```sql
-- Weighted average for OTD % across sites
100.0 * SUM(OTD_pct * receipt_count) / SUM(receipt_count)
```

`'_ALL_SITES_'` row appears only when `@Site IS NULL` and multiple sites have data.

## Waste & stagnation categories (waste_and_stagnation.sql)

Five categories, **one row per issue**. Mixed grain — output `REF_ID` / `REF_LINE` / `REF_DATE` ties back to the source (part, PO line, WO).

### Category thresholds and logic

| Category | Trigger | Cost basis |
|---|---|---|
| `STAGNANT_INVENTORY` | `QTY_ON_HAND > 0` AND last movement > `@StagnantMonths` (12) ago AND value ≥ `@MinStagnantValue` ($1000) | `QTY_ON_HAND * UNIT_MATERIAL_COST` |
| `EXCESS_COVERAGE` | Months-of-supply > `@ExcessMonths` (12) AND value ≥ $1000 | `ON_HAND_VALUE * (MOS - @ExcessMonths) / MOS` (the "excess above target" piece) |
| `DEAD_PURCHASED_PART` | `PURCHASED='Y'` AND not fabricated AND OH > 0 AND no open SO AND no open WO requirement AND no movement in `@StagnantMonths` | `QTY_ON_HAND * UNIT_MATERIAL_COST` |
| `ORPHAN_WO` | `TYPE='W'` AND status NOT IN ('X','C','M') AND no `INVENTORY_TRANS` activity in `@OrphanWODays` (60) AND WO created > 60d ago | `SUM(ACT_* COSTS)` |
| `EARLY_PO` | Open PO receives > `@EarlyDays` (30) before earliest demand date | `open_qty * po_unit_price` |

### Cost-basis convention

- **Inventory parts:** `UNIT_MATERIAL_COST` (standard cost from `PART_SITE_VIEW`)
- **WO cost:** `ACT_MATERIAL_COST + ACT_LABOR_COST + ACT_BURDEN_COST + ACT_SERVICE_COST` (actual accumulated)
- **PO cash drag:** `open qty * PO unit_price` in purchase UOM

### Parameter defaults

```sql
DECLARE @Site              nvarchar(15)  = NULL;
DECLARE @AsOfDate          date          = CAST(GETDATE() AS date);
DECLARE @OtdLookbackDays   int           = 90;
DECLARE @StagnantMonths    int           = 12;
DECLARE @MinStagnantValue  decimal(15,2) = 1000;
DECLARE @ExcessMonths      decimal(5,2)  = 12;
DECLARE @OrphanWODays      int           = 60;
DECLARE @EarlyDays         int           = 30;
```

## Files in this folder

| File | Purpose |
|---|---|
| `executive_supply_chain_kpis.sql` | Per-site 13-KPI snapshot; multi-site rollup |
| `waste_and_stagnation.sql` | Five-category waste detail: stagnant, excess, dead, orphan WO, early PO |

## Known duplication — maintenance warning

Executive queries **re-implement** logic from other domains rather than referencing them. That makes them self-contained but creates a maintenance risk — if the canonical open-SO or open-WO filter changes, it must be updated here too.

| Duplicated logic | Canonical home |
|---|---|
| Canonical open-SO filter | `../../sales/order_information/CLAUDE.md` |
| Open-PO filter + target-recv-date cascade | `../purchasing/CLAUDE.md` |
| Open-WO requirement | `../../inventory/part_information/CLAUDE.md` |
| Vendor OTD | `../performance/vendor_otd_scorecard.sql` |
| Customer OTD | `../../sales/performance/customer_otd_scorecard.sql` |
| Stagnation usage windows | `../performance/eo_forecast_coverage_months.sql` |

**Future refactor candidate:** pull these into shared SQL views (`VW_OPEN_SO_LINE`, `VW_OPEN_PO_LINE`, etc.) so the canonical definition lives in one place.

## Cost-basis consistency

Single rule across both files: **standard cost from `PART_SITE_VIEW` for inventory/shortage/stagnant valuation.**

```sql
std_cost = UNIT_MATERIAL_COST + UNIT_LABOR_COST + UNIT_BURDEN_COST + UNIT_SERVICE_COST
```

Not last-PO cost, not FIFO, not actual receipt cost. WO costs use actual (`ACT_*`) because that's what's accumulated on the WO itself.

## Gotchas

- **Negative on-hand lots** will inflate `INVENTORY_VALUE` and `SHORTAGE_VALUE`. Reconcile via `../../inventory/fix_scripts/` before trusting the numbers.
- **Phantom demand** from cancelled WOs with lingering `REQUIREMENT.STATUS='R'` will surface as `PARTS_SHORT_COUNT`. Run inventory fix script 2 periodically.
- **Forecasted-only parts with no issue history:** turns and cover calcs go NULL. Safe via `NULLIF`/`ISNULL`, but excess/shortage classification may misfire.
- **Service / one-time-buy parts** flagged as `EXCESS_COVERAGE` are often legitimate. Use `ABC_CODE` and `BUYER_USER_ID` in the output to filter manually.
- **WO status `'M'`** (maintenance mode / engineering master) excluded from WIP and orphan checks but NOT from shortage calcs. Intentional.
- **Self-contained logic** means safe dependency-wise but risky maintenance-wise. Keep a diff against `../performance/` and `../../sales/performance/` when changing OTD formulas.
- **Weighted-avg OTD across sites** uses receipt count as the weight. For revenue-weighted customer OTD, build it explicitly from `CUST_LINE_DEL`.
