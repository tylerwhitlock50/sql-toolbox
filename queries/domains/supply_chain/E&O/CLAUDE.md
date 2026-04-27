# CLAUDE.md — supply_chain / E&O

Rules for historical excess & obsolescence analysis (VECA).

## Scope

Backward-looking inventory risk classification based on realized turnover. Pairs with `../performance/eo_forecast_coverage_months.sql` — which is the forward-looking view.

Use this for: reserve sizing, write-down auditing, annual turns trending.
Use the forward view for: procurement planning.

## Core approach

Snapshot of current on-hand reconciled against the last 360 days of actual issue activity from `INVENTORY_TRANS`. Classify each part into one of six turnover buckets.

**Snapshot date:** always `GETDATE()`. No `@AsOfDate` parameter — this is always "now." For retroactive basis, you'd need to re-run historically or modify the filter.

## Core tables

| Table | Use |
|---|---|
| `PART_SITE_VIEW` | Master: `UNIT_MATERIAL_COST` (std), description, buyer, commodity, ABC code |
| `PART_LOCATION` | Physical qty per (part, bin) — summed for part-level on-hand |
| `INVENTORY_TRANS` | History: `TYPE='O' AND CLASS='I'` = issues to manufacturing, `TYPE='A'` = adjustments |

## Cost basis (two views)

```sql
-- Standard cost (from PART_SITE_VIEW)
standard_cost = UNIT_MATERIAL_COST + UNIT_LABOR_COST + UNIT_BURDEN_COST + UNIT_SERVICE_COST

-- Actual cost (INVENTORY_TRANS flow)
inventory_value_on_hand_actual =
    SUM(CASE WHEN type='I' THEN (act_matl + act_lab + act_brdn + act_svc)
             WHEN type='O' THEN -(act_matl + act_lab + act_brdn + act_svc)
             ELSE 0 END)

-- Cross-check estimate
inventory_value_on_hand_standard_estimate = part_location_qty_on_hand * standard_cost
```

Divergence between actual and standard = pending cost roll or receipt costed differently than standard.

## Turnover calculation

```sql
annual_turns = issues_360_day / NULLIF(part_location_qty_on_hand, 0)
```

**Why `part_location_qty` not `inventory_trans_qty`:** `PART_LOCATION` reflects **physical** on-hand (cycle-counted); `INVENTORY_TRANS` is transactional history. They can drift, and the `qty_mismatch_flag` captures that. For turns we use the physical count.

## Six classification buckets

| Bucket | Condition | Meaning |
|---|---|---|
| `URGENT BUY / HIGH VELOCITY` | `annual_turns > 4` | Fast mover, 4+ turns/yr |
| `GREEN` | `2 <= annual_turns < 4` | Healthy (2–4 turns) |
| `YELLOW` | `1 <= annual_turns < 2` | Below-target velocity |
| `EXCESS` | `annual_turns < 1` AND `qty_on_hand > 0` | Slow; > 1 year of supply |
| `OBSOLETE / NO USAGE` | `qty_on_hand > 0` AND `issues_360_day = 0` | Zero usage in 360 days |
| `NO STOCK / NO USAGE` | `qty_on_hand = 0` AND `issues_360_day = 0` | Inactive |

**Thresholds are hardcoded** (`>4`, `>=2`, `>=1`, `<1`, `=0`). Forward view in `../performance/eo_forecast_coverage_months.sql` parameterizes them instead.

## Additional metrics

Rolling usage windows:
- `issues_30_day`, `issues_60_day`, `issues_90_day`, `issues_180_day`, `issues_360_day`

Adjustment detection:
- `total_adjust_ins`, `total_adjust_outs`, `total_adjustment_qty`
- `high_adjustment_part_flag = 1` if `ABS adjustments >= 10` OR `adjustments >= 25% of issues`

Reconciliation:
- `qty_on_hand_difference = part_location_qty - inventory_trans_qty`
- `qty_mismatch_flag = 1 if difference <> 0`

## Historical vs forward-looking (side-by-side)

| Aspect | `historical_E&O_basis.sql` | `../performance/eo_forecast_coverage_months.sql` |
|---|---|---|
| Time basis | Trailing 360 days actuals | 6-mo + 12-mo usage avg + open supply + open demand |
| On-hand source | `PART_LOCATION` (physical) | `PART_SITE_VIEW.QTY_ON_HAND` |
| Demand signal | History only | History + open SO + planned orders |
| Buckets | Turnover-based (URGENT/GREEN/YELLOW/EXCESS/OBSOLETE/NO_STOCK) | Coverage-based (HEALTHY/EXCESS/AT_RISK/STOCK_OUT/OBSOLETE_TREND) |
| Thresholds | Hardcoded | Parameterized |
| Grain | Per part (all sites collapsed) | Per (SITE_ID, PART_ID) |
| Use case | Reserves, audit, annual trending | Forward planning |

**They can disagree** on the same part — e.g., turns = 1.5 → `YELLOW` historically, but high open PO + no demand forecast → `AT_RISK` forward-looking. That's informative, not a bug.

## Files in this folder

| File | Purpose |
|---|---|
| `historical_E&O_basis.sql` | Turnover-based inventory classification at current snapshot |

## Gotchas

- **Snapshot date is always `GETDATE()`.** No retroactive snapshots without modifying the query.
- **This query collapses all sites** — no `GROUP BY SITE_ID`. For site-specific E&O, add `SITE_ID` to the grouping and select list.
- **Transfers between bins** are recorded in `PART_LOCATION` only, not `INVENTORY_TRANS`. A part that moves internally without any issues may look OBSOLETE here even though it's actively being rearranged.
- **Negative on-hand** is possible if `INVENTORY_TRANS` has unreversed entries. `NULLIF` keeps division safe, but the bucket still misreports. Reconcile via `../../inventory/fix_scripts/1`.
- **Service parts** bought once every 2 years → `annual_turns ≈ 0.5` → `EXCESS`. Legitimate for field service. Manually filter via `ABC_CODE` or buyer.
- **Forecast-only new parts** with open PO + zero history → `NO_USAGE`. Historical view can't see forward demand; use the forward view too.
- **Adjustment inflation:** +100 in / -100 out over 360d shows `issues_360 = 0` (issues tracked class='I' only) but `adjustment_qty = 200`. `high_adjustment_part_flag` catches these.
- **Cost-roll drift** between actual and standard estimate is often the "signal" in this report — investigate rather than dismissing.
