# CLAUDE.md — supply_chain / performance

Rules for vendor OTD, lead-time history, price volatility, buyer scorecards, shortage analysis, and commodity rollups (VECA).

## Scope

Scorecards and exception reports that consume the facts from `../purchasing/` and the supply/demand layers. Everything here is **measurement** — OTD, variance, aging, concentration — not planning.

## Canonical target-receipt-date (shared with ../purchasing/)

```sql
target_recv_date = COALESCE(
    PURC_LINE_DEL.DESIRED_RECV_DATE,    -- schedule
    PURC_ORDER_LINE.DESIRED_RECV_DATE,  -- line
    PURCHASE_ORDER.PROMISE_DATE,        -- header promise
    PURCHASE_ORDER.DESIRED_RECV_DATE    -- header desired
)
```

Every OTD / aging / shortage query uses this cascade.

## Vendor OTD (vendor_otd_scorecard.sql)

```sql
days_late   = DATEDIFF(day, target_recv_date, RECEIVER.RECEIVED_DATE)
is_on_time  = CASE WHEN days_late <= @OnTimeToleranceDays THEN 1 ELSE 0 END
otd_pct     = 100.0 * SUM(is_on_time) / COUNT(*)
```

- `@OnTimeToleranceDays` default **0** (ship on/before target). Parameterize for grace.
- Denominator = **receipt-level** count (`RECEIVER_LINE.RECEIVED_QTY > 0`).
- Total spend comes from `INVENTORY_TRANS.ACT_MATERIAL_COST` (landed), **not** `qty × unit_price`.
- Reject % = `rejected_qty / received_qty`.

**Vendor tier:**
```
A - PREFERRED         : OTD >= 95 AND reject_pct < 1
B - ACCEPTABLE        : OTD >= 85 AND reject_pct < 2
C - NEEDS IMPROVEMENT : OTD >= 70
D - AT RISK           : OTD < 70
```

Window: `@FromDate` / `@ToDate`, default trailing 365 days on **received_date** (not PO date).

## Vendor lead-time history (vendor_lead_time_history.sql)

```sql
LT_DAYS = DATEDIFF(day, PURCHASE_ORDER.ORDER_DATE, INVENTORY_TRANS.TRANSACTION_DATE)
```
Filter: `0 <= LT_DAYS <= 365` (drop anomalies). Multiple receipts per PO line → multiple observations.

**Compat-safe percentiles** (no `PERCENTILE_CONT`):
- P50: `ROW_NUMBER() ORDER BY LT_DAYS`, pick middle row(s)
- P90: row at `CEIL(0.9 * COUNT)`; if count < 10, use max

**ERP comparison:**
```sql
LT_ERP_PART         = PART_SITE_VIEW.PLANNING_LEADTIME
LT_VENDOR_PART      = VENDOR_PART.LEADTIME_BUFFER
LT_OPTIMISM_DAYS    = P50_LT - MIN(LT_VENDOR_PART, LT_ERP_PART)
                      -- positive = ERP is too optimistic
```

**Health flags:**
- `INSUFFICIENT DATA` — observations < `@MinObservations` (default 2)
- `ERP TOO OPTIMISTIC` — P50 > 1.5 × ERP declared LT
- `HIGH VARIABILITY` — `STDDEV > MEAN * 0.5`
- `RELIABLE` — observations ≥ 2 AND OTD ≥ 90
- `OK` — fallback

## Part price volatility (part_price_volatility.sql)

Per (SITE_ID, PART_ID, YEAR_MONTH). Monthly weighted-avg cost:
```sql
WTD_AVG_UNIT_COST = SUM(ACT_MATERIAL_COST) / SUM(QTY)
```

- **MoM %** compares to most recent **prior month with a receipt** (not strict calendar).
- **YoY %** compares to same calendar month one year ago.
- **Trailing-12 CV:** `100.0 * STDEV(last_12) / MEAN(last_12)`; NULL if < 4 months data.
- **VS_STD_PCT:** drift from `UNIT_MATERIAL_COST`.

**Trend flag:**
- `NEW (NO YOY BASELINE)` — no prior-year data
- `INFLATING` — YoY > +15
- `DEFLATING` — YoY < -10
- `VOLATILE` — CV > 25 (with ≥ 4 months data)
- `STABLE` — fallback

## Vendor scorecard 360 (vendor_scorecard_360.sql)

Consolidated per-vendor view (all sites unless `@Site`). CTEs:
- **vendor_receipts** — activity + OTD + LT stats from `INVENTORY_TRANS`
- **open_pos** — point-in-time open value + past-due exposure
- **inflation_flags** — parts with YoY > 10 % and > 25 % over a 24-month window

**Health composite (single flag):**
```
UNKNOWN : fewer than 5 receipts in window
RED     : OTD < 80 OR parts_inflating_gt_25pct > 0 OR past_due_value > 50k
YELLOW  : OTD 80-95 OR (mean_lt > 0 AND CV > 25%) OR parts_inflating_gt_10pct > 0 OR past_due_lines > 0
GREEN   : OTD >= 95 AND CV < 25 AND no inflation flags AND no past-due
```

## Commodity spend rollup (commodity_spend_rollup.sql)

Per (SITE_ID, COMMODITY_CODE) over `@LookbackMonths` (default 12):

- Spend from `INVENTORY_TRANS.ACT_MATERIAL_COST` receipts; `COMMODITY_CODE` from `PART_SITE_VIEW` (NULL → `'_NO_COMMODITY_'`)
- **HHI = `SUM((vendor_share_pct)²)`** per commodity
  - > 2500 = highly concentrated, 1500–2500 = moderate, < 1500 = competitive
- **T3 vs Prior-3 spend trend:** `100 * (AVG_T3 - AVG_PRIOR3) / AVG_PRIOR3`
- **Inflation detection:** per part, compare `MAX(cost in last 3 months)` vs `MAX(cost 12 months prior)`; count parts > 10 %
- **Top-3 vendors CSV** via `STUFF(... FOR XML PATH)`

**Sourcing flag:**
- `DIVERSIFY` — HHI > 2500 AND total_spend > 50k
- `NEGOTIATE` — 3+ parts inflating
- `WATCH` — T3 > prior3 × 1.5
- `COMPETITIVE` — ≥ 5 vendors AND HHI < 1500
- `OK` — fallback

## Buyer scorecard (buyer_performance_scorecard.sql)

Per (SITE_ID, BUYER). Buyer attribution cascade:
```sql
buyer = COALESCE(
    NULLIF(LTRIM(RTRIM(PURCHASE_ORDER.BUYER)), ''),
    PART_SITE_VIEW.BUYER_USER_ID,
    '(unassigned)'
)
```

Point-in-time open metrics: open lines, open value, past-due lines/value, weighted-avg days past due, stalled lines (no receipts in `@StalledDays` default 60).

Window metrics: received lines/qty/value, OTD %, price-variance count (> `@PriceVarPct` default 5 %).

**Attention flag:** `past_due_value > 25% of open_po_value` OR `stalled_lines >= 5` OR `OTD < 80`.

## Past-due PO aging (past_due_po_aging.sql)

Buckets past `target_recv_date` vs `@AsOfDate`:
```
0-7, 8-14, 15-30, 31-60, 61+, NOT_DUE
```

**Priority (with SO linkage):**
- `P1 - expedite, SO demand` — past due AND part on open SO
- `P2 - past due` — past due, no SO linkage
- `P3 - due soon, SO demand` — not due yet but part on SO
- `P4 - normal` — else

## Material shortage vs open demand (material_shortage_vs_open_demand.sql)

```sql
projected_position    = qty_on_hand + open_po_qty + planned_qty - open_wo_req_qty
shortage_qty          = CASE WHEN projected_position < 0 THEN ABS(projected_position) ELSE 0 END
shortage_value_at_std = shortage_qty * std_unit_cost
```

SO linkage = **direct `PART_ID` match** (no BOM walk-up). A shortage on a sub-assembly component won't ladder up to show the FG SO at risk — that's a known limitation. Use `../../sales/order_information/so_fulfillment_risk.sql` for BOM-aware pegging.

**Status:**
- `CRITICAL - short + SO demand` — shortage > 0 AND open SO value > 0
- `SHORT` — shortage > 0
- `PO LATE FOR NEED` — earliest PO receipt > earliest required date
- `NO COVERAGE PLANNED` — no PO, no planned, demand > on-hand
- `OK` — else

## E&O forecast coverage months (eo_forecast_coverage_months.sql)

Per (SITE_ID, PART_ID). Forward-looking view complementing the historical `../E&O/historical_E&O_basis.sql`.

**Blended monthly demand** (take the most demanding signal):
```sql
blended_monthly_demand = GREATEST(
    issues_180d / 6.0,
    issues_360d / 12.0,
    open_so_qty / months_to_latest_desired_ship
)

months_of_cover_on_hand = qty_on_hand / NULLIF(blended_monthly_demand, 0)
months_of_cover_total   = (qty_on_hand + open_po_qty + planned_qty) / blended_monthly_demand
```

**Classification (tunable thresholds):**
```
OBSOLETE_TREND   : issues_360d = 0 AND qty_on_hand > 0
NO_DEMAND_SIGNAL : blended_demand = 0 AND qty_on_hand > 0
EXCESS_DEEP      : months_of_cover > @ObsoleteCoverMonths (default 24)
EXCESS           : months_of_cover > @ExcessCoverMonths   (default 12)
HEALTHY          : @TargetCoverMonths <= cover <= @ExcessCoverMonths
AT_RISK          : cover < @TargetCoverMonths (default 3)
STOCK_OUT        : demand > 0 AND qty_on_hand = 0 AND supply = 0
REVIEW           : edge cases
```

## Parameter patterns

```sql
DECLARE @Site                nvarchar(15) = NULL;
DECLARE @LookbackMonths      int          = 12;
DECLARE @FromDate, @ToDate   datetime;              -- trailing window
DECLARE @AsOfDate            datetime     = GETDATE();
DECLARE @OnTimeToleranceDays int          = 0;
```

## Files in this folder

| File | Purpose |
|---|---|
| `vendor_otd_scorecard.sql` | Vendor OTD % + reject % + tier |
| `vendor_lead_time_history.sql` | Actual LT stats per (vendor, part); ERP-optimism gap |
| `part_price_volatility.sql` | Monthly price trend + MoM/YoY + T12 CV |
| `vendor_scorecard_360.sql` | Consolidated vendor health (spend + OTD + LT + price + risk) |
| `commodity_spend_rollup.sql` | Per-commodity spend, HHI concentration, inflation flags |
| `buyer_performance_scorecard.sql` | Buyer-level OTD, past-due, stalled, price variance |
| `past_due_po_aging.sql` | Past-due PO aging + SO-linkage priority (P1-P4) |
| `material_shortage_vs_open_demand.sql` | Component shortages tied to at-risk SOs (direct PART_ID match) |
| `eo_forecast_coverage_months.sql` | Forward-looking E&O risk via months-of-cover classification |

## Gotchas

- **OTD evaluated at `RECEIVED_DATE`**, not PO placement. Reflects actual vendor performance.
- **LT anomalies dropped** (< 0 or > 365 days). If your org has unusually long purchase LTs, widen the filter.
- **Currency not normalized.** All cost / price comparisons assume a single reporting currency.
- **Cost basis is actual landed** (`INVENTORY_TRANS.ACT_MATERIAL_COST`), not PO `UNIT_PRICE`. They diverge when freight is costed in.
- **Material shortage uses direct PART_ID match** — if a purchased sub-assembly is short and feeds a top-level FG on an SO, the linkage won't bubble up. Known limitation.
- **`REQUIREMENT.STATUS = 'U'`** is canonical "open" in VECA. `'A'` = archived. Don't confuse with other ERPs' open conventions.
- **Blanket POs / freight lines / service POs** — `SERVICE_ID` populated, `PART_ID NULL`. Handle explicitly in shortage / price analysis.
- **`NULLIF(..., 0)`** is used everywhere to avoid divide-by-zero. Don't skip it when adding new metrics.
- **ABC / priority tiers are hardcoded thresholds** — change them only after business review.
