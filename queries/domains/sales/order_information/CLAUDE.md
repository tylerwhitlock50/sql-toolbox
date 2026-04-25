# CLAUDE.md — sales / order_information

Rules for querying customer orders at the header + line grain (VECA).

## Scope

Queries in this folder answer: *"What's on order?"* / *"What's open and unshipped?"* / *"What's blocking a specific SO?"*

They are the **base datasets** other domains build on — e.g. sales performance, shipping, fulfillment risk, supply planning all consume the "open customer order line" definition from here.

## Core tables & grain

| Table | Grain | Notes |
|---|---|---|
| `CUSTOMER_ORDER` (`h` / `co`) | 1 row per SO header | `ID`, `SITE_ID`, `CUSTOMER_ID`, `STATUS`, `ORDER_DATE`, `DESIRED_SHIP_DATE`, `PROMISE_DATE` |
| `CUST_ORDER_LINE` (`l` / `col`) | 1 row per SO line | `CUST_ORDER_ID`, `LINE_NO`, `PART_ID`, `LINE_STATUS`, `ORDER_QTY`, `TOTAL_SHIPPED_QTY`, `UNIT_PRICE`, `TRADE_DISC_PERCENT`, line-level date overrides |
| `CUST_LINE_DEL` (`cld`) | 0..N rows per SO line | Delivery schedules / blanket-release splits. **Optional** — many lines don't have any. LEFT JOIN only. |
| `CUSTOMER` | 1 row per customer | LEFT JOIN — some orders don't resolve. |
| `SHIPPER` / `SHIPPER_LINE` | Shipment events | See `../../shipping/` and sales performance for the canonical shipment join. |
| `PART_SITE_VIEW` | 1 row per (SITE_ID, PART_ID) | Always join on **both** `SITE_ID` and `PART_ID` — costs are site-specific. |

## Canonical joins

**Header → Line (the fundamental join):**
```sql
FROM CUSTOMER_ORDER h
INNER JOIN CUST_ORDER_LINE l
    ON h.ID = l.CUST_ORDER_ID
```
Use `INNER JOIN` for operational reports (drop header-only rows); `LEFT JOIN` only when you explicitly need empty headers.

**Line → Delivery schedule (optional fine grain):**
```sql
LEFT JOIN CUST_LINE_DEL cld
    ON cld.CUST_ORDER_ID      = l.CUST_ORDER_ID
   AND cld.CUST_ORDER_LINE_NO = l.LINE_NO
```
Always LEFT — schedules are optional.

**Line → Part master:**
```sql
LEFT JOIN PART_SITE_VIEW psv
    ON psv.SITE_ID = h.SITE_ID
   AND psv.PART_ID = l.PART_ID
```
Never join on `PART_ID` alone — costs, on-hand, and planning params diverge by site.

## THE open-order filter (canonical)

This is the rule the rest of the project assumes. Use exactly this when you say "open orders":

```sql
WHERE h.STATUS IN ('R', 'F')                           -- header: released or firmed
  AND l.LINE_STATUS = 'A'                              -- line: active
  AND l.ORDER_QTY - ISNULL(l.TOTAL_SHIPPED_QTY, 0) > 0 -- still qty to ship
  AND l.PART_ID IS NOT NULL                            -- real shippable items only
```

**Status legend (memorize these):**
- `h.STATUS`: `R` = released, `F` = firmed, `C` = closed (may be short!), `X` = voided
- `l.LINE_STATUS`: `A` = active, `C` = closed, `X` = voided

**Traps to avoid:**
- **Don't** use `h.STATUS != 'C'` as a proxy for "open" — closed-short lines leak through, and voided orders slip in too.
- **Don't** forget `PART_ID IS NOT NULL` — comment lines, service charges, and misc-reference rows all have NULL parts and are not shippable.
- **Don't** forget `ISNULL(TOTAL_SHIPPED_QTY, 0)` — unshipped lines have NULL, not 0, and NULL arithmetic breaks the filter.

## Quantity conventions

- `open_qty_raw = ORDER_QTY - TOTAL_SHIPPED_QTY` — may be negative (over-shipped).
- `to_ship_qty = CASE WHEN open_qty_raw < 0 THEN 0 ELSE open_qty_raw END` — **always floor at zero** for operational outputs. Over-shipment is a data quality signal, not negative demand.
- `TOTAL_SHIPPED_QTY` is cumulative across all shipments on the line. Wrap in `ISNULL(..., 0)` before arithmetic.

## Date precedence (for aging, MRP, OTD)

The canonical coalesce chain — line overrides header, delivery schedule is most specific:

```sql
COALESCE(
    cld.DESIRED_SHIP_DATE,   -- delivery schedule (most specific)
    l.PROMISE_DATE,          -- line promise override
    l.DESIRED_SHIP_DATE,     -- line planning date
    h.PROMISE_DATE,          -- header promise override
    h.DESIRED_SHIP_DATE      -- header planning date (the fallback)
) AS target_ship_date
```

- **`DESIRED_SHIP_DATE` drives MRP and internal aging** (the planning horizon).
- **`PROMISE_DATE` drives the customer SLA.** Difference = hidden risk.
- `DATEDIFF(day, target_ship_date, CAST(GETDATE() AS DATE))` → positive = past due, negative = future.
- Always `CAST` to `DATE` (not `DATETIME`) so time-of-day doesn't leak into day aging.

## Site filtering

```sql
DECLARE @Site nvarchar(15) = NULL;   -- NULL = all sites
...
WHERE (@Site IS NULL OR h.SITE_ID = @Site)
```

Every canonical query here ships this pattern. SSRS passes NULL for "all sites"; don't special-case it.

## Files in this folder

| File | Purpose |
|---|---|
| `so_header_and_lines.sql` | **Unfiltered** base dataset — every header × line, all statuses. Foundation for downstream. Uses `LEFT JOIN` to keep header-only rows. |
| `so_header_and_lines_open_orders.sql` | Applies the canonical open-order filter above. Source of truth for "open SO lines." Primary feed for aging, at-risk, fulfillment. |
| `so_fulfillment_risk.sql` | Per SO line: blocking components + next supply that would unblock. BOM-aware; joins PO / WO / planned supply. |

## Gotchas

- **Closed-short lines** (`LINE_STATUS = 'C' AND TOTAL_SHIPPED_QTY < ORDER_QTY`) are a real failure mode — the customer got less than they ordered, and the line is no longer "open." Handled in `sales/performance/` scorecards, not here.
- **`CUST_LINE_DEL` isn't always populated.** Some customers (blanket orders, milestone billing) use it heavily; many don't. Always `LEFT JOIN`, and fall back to line/header dates.
- **Over-shipped lines (`TO_SHIP_QTY = 0` but `OPEN_QTY_RAW < 0`)**: keep `OPEN_QTY_RAW` visible in diagnostic outputs so data issues surface.
- **`PART_SITE_VIEW` is a view** that merges `PART + PART_SITE` with `ISNULL(PART_SITE.col, PART.col)` fallback. Prefer it over manual joins.
