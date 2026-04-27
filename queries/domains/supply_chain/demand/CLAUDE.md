# CLAUDE.md — supply_chain / demand

Rules for unified demand signals and BOM-exploded component demand (VECA).

## Scope

Queries here define the **canonical demand stream** that downstream planning consumes. Combines multiple demand sources (SO backorder, master schedule, forecast) into one shape, then optionally BOM-explodes to component level.

## The unified demand shape

Every demand row — regardless of source — flattens to this contract:

| Column | Meaning |
|---|---|
| `SITE_ID`, `PART_ID` | Demand site + part (top level; component for exploded) |
| `NEED_DATE` | When the demand is due |
| `DEMAND_SOURCE` | `SO_BACKORDER` / `MS_FIRM` / `MS_FORECAST` / `FORECAST` |
| `DEMAND_PRIORITY` | 1 (SO) / 2 (MS firm) / 3 (MS forecast) / 4 (pure forecast) |
| `DEMAND_QTY` | Positive qty |
| `UNIT_PRICE`, `DEMAND_VALUE` | SO only; NULL for MS/forecast |
| `PARTY_ID` | Customer (SO only) |
| `SOURCE_REF` | Back-reference for traceability |

**Sign convention:** all `DEMAND_QTY > 0`. No negative / return logic.

## Demand sources (priority order)

### 1. SO backorder (priority 1)

```sql
FROM   CUST_ORDER_LINE col
JOIN   CUSTOMER_ORDER  co  ON co.ID = col.CUST_ORDER_ID
WHERE  co.STATUS     IN ('R','F')
  AND  col.LINE_STATUS = 'A'
  AND  col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
  AND  col.PART_ID IS NOT NULL
  AND  (@Site IS NULL OR col.SITE_ID = @Site)
```

- `NEED_DATE = COALESCE(col.PROMISE_DATE, col.DESIRED_SHIP_DATE, co.DESIRED_SHIP_DATE)`
- `DEMAND_QTY = col.ORDER_QTY - col.TOTAL_SHIPPED_QTY`
- `DEMAND_VALUE = DEMAND_QTY * col.UNIT_PRICE`
- `SOURCE_REF = CUST_ORDER_ID + '/' + LINE_NO`

Canonical open-SO filter — same as sales/inventory domains.

### 2. Master schedule firm (priority 2)

```sql
FROM MASTER_SCHEDULE ms
WHERE ms.ORDER_QTY > 0
  AND ms.FIRMED = 'Y'
```
- `NEED_DATE = ms.WANT_DATE`
- `DEMAND_QTY = ms.ORDER_QTY`
- `SOURCE_REF = ms.MASTER_SCHEDULE_ID`

### 3. Master schedule forecast (priority 3)

Same as above with `FIRMED = 'N'`.

### 4. Forecast (priority 4)

```sql
FROM DEMAND_FORECAST df
WHERE df.REQUIRED_QTY > 0
```
- `NEED_DATE = df.REQUIRED_DATE`
- `DEMAND_QTY = df.REQUIRED_QTY`
- `SOURCE_REF = CAST(df.ROWID AS nvarchar(20))`

**Forecast tables may be empty** in your deployment. Queries should still work with SO demand alone.

## Week bucketing (ISO Monday)

```sql
DATEADD(day,
        -((DATEPART(weekday, u.NEED_DATE) + @@DATEFIRST - 2) % 7),
        CAST(u.NEED_DATE AS date)) AS WEEK_BUCKET
```

Assumes `@@DATEFIRST = 1` (Monday-first). No fiscal calendar logic here.

## Need buckets (categorical)

```
PAST_DUE      : NEED_DATE < today
0-30 DAYS     : < today + 30
30-60 DAYS    : ...
60-90 DAYS    : ...
90-180 DAYS   : ...
180+          : otherwise
```

## BOM explosion to component demand

`exploded_gross_demand.sql` walks each unified demand row down the engineering-master BOM (same CTE shape as `../bom/`), producing component-level gross requirements.

**Per-level qty math:**
```sql
GROSS_QTY = parent.GROSS_QTY * (rq.CALC_QTY / NULLIF(wo.DESIRED_QTY, 0))
```

**Critical difference from `../bom/` queries:**
- `../bom/` starts the recursion at **level 1** (children of the top part)
- This query starts at **level 0** — emits the top part itself with `GROSS_QTY = demand_qty`, then explodes. Useful so planning can peg the parent build alongside the components.

**Aggregation** (before final SELECT):
```sql
GROUP BY SITE_ID, COMPONENT_PART_ID, NEED_DATE, DEMAND_SOURCE, DEMAND_PRIORITY, SOURCE_REF
MIN(BOM_LEVEL)  -- shallowest path wins when a part appears in multiple sub-assemblies
SUM(GROSS_QTY)  -- total gross requirement
```

## Make-or-buy classification (exploded output)

```sql
CASE
    WHEN psv.PURCHASED = 'Y' AND ISNULL(psv.FABRICATED,'N') <> 'Y' THEN 'BUY'
    WHEN psv.FABRICATED = 'Y'                                      THEN 'MAKE'
    WHEN psv.DETAIL_ONLY = 'Y'                                     THEN 'PHANTOM'
    ELSE                                                                'OTHER'
END AS MAKE_OR_BUY
```

## Order-by date (lead-time backoff)

```sql
ORDER_BY_DATE = DATEADD(day, -ISNULL(psv.PLANNING_LEADTIME, 0), e.NEED_DATE)
```

When you must order to meet the need date. Feeds into `../planning/purchasing_plan.sql`.

## Site filtering

```sql
DECLARE @Site nvarchar(15) = NULL;
...
WHERE (@Site IS NULL OR col.SITE_ID = @Site)
...
AND   psv.SITE_ID = parent.SITE_ID   -- recursive join — site propagates
```

Demand and BOM are always co-sited. Top demand at site TDJ uses TDJ's engineering master.

## Files in this folder

| File | Purpose |
|---|---|
| `total_demand_by_part.sql` | Unified demand: SO + MS firm + MS forecast + forecast, per (site, part, need_date) |
| `exploded_gross_demand.sql` | BOM-exploded component-level gross demand per source/need date |

## Gotchas

- **Forecast / master-schedule tables may be empty.** SO demand is often the only non-empty source. Queries are designed to work with 0-row MS/forecast CTEs.
- **`CALC_QTY` includes scrap.** Don't double-apply `SCRAP_PERCENT` (same as `../bom/`).
- **Phantom parts** (`DETAIL_ONLY='Y'`) cascade through as demand. `MAKE_OR_BUY = 'PHANTOM'` flags them; netting out is downstream.
- **Level 0 includes the top part itself.** Be careful aggregating; a naive `SUM(GROSS_QTY) GROUP BY PART_ID` will double-count unless you filter `BOM_LEVEL > 0` or treat the top separately.
- **Cycle guard via `PATH`** is mandatory (same as BOM queries). Without it, circular BOMs hit max recursion.
- **`DEMAND_PRIORITY`** is used for `ORDER BY` and for downstream allocation logic in `../planning/shared_buildable_allocation.sql`. Keep the 1–4 ordering stable.
- **Week bucketing assumes Monday-first** (`@@DATEFIRST = 1`). If your server uses a different default, the week math shifts.
- **No UOM conversion** needed in the explosion — `CALC_QTY/DESIRED_QTY` is already in component stock UOM.
