# CLAUDE.md — supply_chain / purchasing

Rules for open-PO inventory, UOM normalization, cost summary, and PO price history (VECA).

## Scope

PO-side datasets: what's on order, what's planned, what it costs. These are the **facts** layer; scorecards live in `../performance/`, and action lists in `../planning/`.

## Core tables

| Table | Grain | Notes |
|---|---|---|
| `PURCHASE_ORDER` (`p`) | 1 per PO header | `ID`, `VENDOR_ID`, `BUYER`, `ORDER_DATE`, `PROMISE_DATE`, `DESIRED_RECV_DATE`, `STATUS`, `CURRENCY_ID` |
| `PURC_ORDER_LINE` (`pl`) | 1 per PO line | `PART_ID`, `SERVICE_ID`, `PURCHASE_UM`, `ORDER_QTY`, `TOTAL_RECEIVED_QTY`, `UNIT_PRICE`, line dates, `LINE_STATUS` |
| `PURC_LINE_DEL` (`pd`) | 0..N per line | Delivery schedule; splits the line across expected receipts |
| `INVENTORY_TRANS` (`it`) | 1 per movement | Receipts live here (`TYPE='I' AND CLASS='R' AND PURC_ORDER_ID IS NOT NULL`); qty in stock UOM; cost in `ACT_MATERIAL/LABOR/BURDEN/SERVICE_COST` |
| `RECEIVER` / `RECEIVER_LINE` | Physical receipt | `RECEIVED_DATE`, `RECEIVED_QTY`, `REJECTED_QTY`, `TRANSACTION_ID` → `INVENTORY_TRANS` |
| `PART_SITE_VIEW` | (SITE_ID, PART_ID) | Std cost components, `STOCK_UM`, `COMMODITY_CODE`, `BUYER_USER_ID`, `PLANNING_LEADTIME`, `QTY_ON_HAND` |
| `VENDOR` (`v`) | 1 per vendor | Name, active flag, priority, currency, vendor group |
| `PART_UNITS_CONV` | UOM conversions (part-specific) | `PART_ID`, `FROM_UM`, `TO_UM`, `CONVERSION_FACTOR` |
| `UNITS_CONVERSION` | UOM conversions (global defaults) | `FROM_UM`, `TO_UM`, `CONVERSION_FACTOR` |
| `PLANNED_ORDER` | Optional Visual MRP output | `SITE_ID`, `PART_ID`, `WANT_DATE`, `ORDER_QTY`, `SEQ_NO` |

## Open PO filter (canonical)

```sql
WHERE ISNULL(p.STATUS, '')     NOT IN ('X','C')
  AND ISNULL(pl.LINE_STATUS,'') NOT IN ('X','C')
  AND pl.ORDER_QTY - ISNULL(pl.TOTAL_RECEIVED_QTY, 0) > 0
```

- `X` = cancelled, `C` = closed.
- If delivery schedules exist (`PURC_LINE_DEL`), **each schedule row** is a separate expected-receipt event — prefer the schedule grain when present.

## Due-date precedence (canonical)

```sql
target_recv_date = COALESCE(
    pd.DESIRED_RECV_DATE,   -- delivery schedule (most specific)
    pl.DESIRED_RECV_DATE,   -- line override
    p.PROMISE_DATE,         -- header promise
    p.DESIRED_RECV_DATE     -- header desired (fallback)
)
```

Same cascade everywhere — aging, OTD, shortage analysis.

## UOM normalization (open_purchase_orders_uom_normalized.sql)

PO qty is in **purchase UOM**. Stock on-hand is in **stock UOM**. Normalize using the conversion cascade:

```sql
conversion_factor = CASE
    WHEN PURCHASE_UM = STOCK_UM                             THEN 1.0
    WHEN PART_UNITS_CONV.CONVERSION_FACTOR IS NOT NULL      THEN PART_UNITS_CONV.CONVERSION_FACTOR
    WHEN UNITS_CONVERSION.CONVERSION_FACTOR IS NOT NULL     THEN UNITS_CONVERSION.CONVERSION_FACTOR
    ELSE NULL                                                -- flag for data cleanup
END
```

**Precedence:** part-specific conversion wins over global default. NULL factor means missing data — surface it.

**Transformations:**
```sql
open_qty_stock_um         = open_qty_purchase_um * conversion_factor
calc_unit_price_stock_um  = po_unit_price       / conversion_factor
expected_amount_stock_um  = open_qty_stock_um * calc_unit_price_stock_um
```

Qty multiplied, price divided.

## Unified open + planned supply (open_and_planned_supply_detail.sql)

UNION of:
- `OPEN_PO` — real POs (status filter above)
- `PLANNED_ORDER` — from MRP output; assumes `conversion_factor = 1.0` and uses `PART_SITE_VIEW.UNIT_MATERIAL_COST` as the planned price

Source-tag column `supply_type` distinguishes them. `doc_no` = `PO.ID` or `CAST(PLANNED_ORDER.ROWID AS varchar(50))`.

## Part cost summary (part_cost_summary.sql)

One row per (PART_ID, SITE_ID). Three cost views side by side:

**Standard** (from `PART_SITE_VIEW`):
```sql
UNIT_MATERIAL_COST + UNIT_LABOR_COST + UNIT_BURDEN_COST + UNIT_SERVICE_COST
```

**Current weighted-average** (lifetime netted from `INVENTORY_TRANS`):
```sql
net_value = SUM(CASE WHEN TYPE='I' THEN (act_matl + act_lab + act_brdn + act_svc)
                     ELSE -(...) END)
net_qty   = SUM(CASE WHEN TYPE='I' THEN QTY ELSE -QTY END)
current_unit_cost = net_value / NULLIF(net_qty, 0)
```
This is "book value per unit remaining on-hand across all time." Drift from `PART_SITE.UNIT_MATERIAL_COST` indicates a pending cost roll or a receipt costed differently than standard.

**Last PO receipt** (ROW_NUMBER by transaction_date DESC, rowid DESC, RN=1).

**Variances vs standard:**
```sql
CURRENT_VS_STD_MAT_PCT = 100.0 * (current_unit_cost - std_material_cost) / std_material_cost
LAST_VS_STD_MAT_PCT    = 100.0 * (last_unit_cost    - std_material_cost) / std_material_cost
```

## Purchase price history yearly

One row per (PART_ID, YEAR) from `INVENTORY_TRANS` receipts:
- Filter: `TYPE='I' AND CLASS='R' AND PURC_ORDER_ID IS NOT NULL AND QTY > 0 AND ACT_MATERIAL_COST > 0`
- Metrics: `RECEIPT_COUNT`, `TOTAL_QTY`, `MIN/MAX/AVG_UNIT_COST`, `MEDIAN_UNIT_COST` (manual ROW_NUMBER), `WEIGHTED_AVG_UNIT_COST` (= `total_value / total_qty`).

**Qty in `INVENTORY_TRANS` is already in stock UOM** — unit costs are directly comparable without UOM conversion.

## Files in this folder

| File | Purpose |
|---|---|
| `open_purchase_orders_uom_normalized.sql` | Open POs with UOM-normalized qty and price |
| `open_and_planned_supply_detail.sql` | Unified open PO + planned order supply |
| `part_cost_summary.sql` | Std vs current-weighted-avg vs last-PO cost (with variances) |
| `purchase_price_history_yearly.sql` | Per-year price history from receipts |

## Gotchas

- **Blanket POs / releases** aren't explicitly typed. Filtered by status + remaining qty only.
- **Return-to-vendor receipts** land in `INVENTORY_TRANS` with `QTY < 0` (class='R', type='O'). Exclude with `QTY > 0` when computing OTD / LT / price stats.
- **Service / freight lines** have `SERVICE_ID` populated and typically `PART_ID IS NULL`. UOM conversion doesn't apply; standard cost comparisons don't either.
- **Missing UOM conversion** → stock-normalized values go NULL. Don't silently fall back to 1.0 — flag the row.
- **Currency:** `PURCHASE_ORDER.CURRENCY_ID` and `VENDOR.CURRENCY_ID` exist but these queries don't convert. Single-currency reporting assumed; add explicit FX handling if needed.
- **`INVENTORY_TRANS.ACT_MATERIAL_COST` is landed cost** (includes freight if costed). PO `UNIT_PRICE` is the quoted PO-line price and may differ.
- **Cost roll asynchrony:** `current_unit_cost` lags or leads `PART_SITE.UNIT_MATERIAL_COST` depending on when the last roll happened. Material delta → data investigation.
