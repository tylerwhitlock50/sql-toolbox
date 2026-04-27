# CLAUDE.md — supply_chain / bom

Rules for recursive BOM and routing explosion queries (VECA).

## Scope

Walk VISUAL's engineering-master BOMs into flat "for each top part, these are all the components at all levels" datasets. Same shape for routing (operations per level).

These are the primitives used by `../demand/exploded_gross_demand.sql`, `../planning/net_requirements_weekly.sql`, and anything that needs component-level demand from a top-level order.

## The engineering-master pattern

VISUAL stores BOMs on **master work orders** (`WORK_ORDER.TYPE = 'M'`). Each fabricated part has a master WO identified by:

```sql
wo.TYPE     = 'M'
wo.BASE_ID  = psv.PART_ID
wo.LOT_ID   = CAST(psv.ENGINEERING_MSTR AS nvarchar(3))   -- from PART_SITE_VIEW
wo.SPLIT_ID = '0'
wo.SUB_ID   = '0'
wo.SITE_ID  = psv.SITE_ID
```

`PART_SITE_VIEW.ENGINEERING_MSTR` identifies the active master lot. `REQUIREMENT` rows under this master WO define the BOM edges; `OPERATION` rows define the routing.

## Core tables

| Table | Role |
|---|---|
| `PART_SITE_VIEW` | Master: `FABRICATED`, `PURCHASED`, `DETAIL_ONLY`, `ENGINEERING_MSTR`, `STOCK_UM`, `UNIT_MATERIAL_COST`, `PLANNING_LEADTIME` |
| `WORK_ORDER` | Anchors the BOM walk (TYPE='M'). `DESIRED_QTY` is the basis for qty normalization |
| `REQUIREMENT` | BOM edges. `CALC_QTY` = net qty after scrap (don't multiply again). `STATUS='U'` = live |
| `OPERATION` | Routing steps: `SETUP_HRS`, `RUN_HRS`, `MOVE_HRS` per `DESIRED_QTY`, `RESOURCE_ID`, `VENDOR_ID` (subcontract), `SERVICE_ID` |

## Recursive CTE shape

Anchor (level 1) — top part's master WO → its REQUIREMENTs:
```sql
SELECT
    1 AS BOM_LEVEL,
    top_wo.PART_ID                    AS BUILD_PART_ID,
    req.PART_ID                       AS COMPONENT_PART_ID,
    req.CALC_QTY / NULLIF(top_wo.DESIRED_QTY, 0) AS STOCK_QTY_PER,
    CAST(req.CALC_QTY / NULLIF(top_wo.DESIRED_QTY, 0) AS decimal(28,8)) AS EXTENDED_QTY,
    CAST('/' + top_wo.PART_ID + '/' + req.PART_ID + '/' AS nvarchar(4000)) AS PATH
FROM   PART_SITE_VIEW top_psv
JOIN   WORK_ORDER     top_wo ON (engineering-master join above)
JOIN   REQUIREMENT    req    ON (5-part WO composite)
WHERE  top_psv.PART_ID = @TopPart
  AND  top_psv.SITE_ID = @Site
  AND  req.PART_ID    IS NOT NULL
  AND  req.STATUS      = 'U'
```

Recursive — follow only components that themselves have a master:
```sql
SELECT
    parent.BOM_LEVEL + 1,
    ...
    CAST(parent.EXTENDED_QTY * (child_req.CALC_QTY / NULLIF(child_wo.DESIRED_QTY, 0)) AS decimal(28,8)) AS EXTENDED_QTY,
    CAST(parent.PATH + child_req.PART_ID + '/' AS nvarchar(4000)) AS PATH
FROM   bom parent
JOIN   PART_SITE_VIEW child_psv
       ON  child_psv.PART_ID    = parent.COMPONENT_PART_ID
       AND child_psv.SITE_ID    = @Site
       AND child_psv.FABRICATED = 'Y'
JOIN   WORK_ORDER  child_wo    ON (engineering-master join)
JOIN   REQUIREMENT child_req   ON (5-part composite)
WHERE  child_req.STATUS = 'U'
  AND  parent.BOM_LEVEL < @MaxDepth
  AND  CHARINDEX('/' + child_req.PART_ID + '/', parent.PATH) = 0   -- cycle guard
```

**Four non-negotiable invariants:**
1. **Anchor on `REQUIREMENT.STATUS = 'U'`** (live master). `'A'` = archived, ignore.
2. **Recurse only into `FABRICATED = 'Y'`** components. Purchased items are leaves.
3. **Cycle guard via `PATH` + `CHARINDEX`**. Cheap and works. Without it, a circular BOM crashes with max-recursion error.
4. **`@MaxDepth` ceiling** (default 20). Safety net if cycle guard is bypassed or for pathological BOMs.

## The extended-qty formula

```
EXTENDED_QTY = parent.EXTENDED_QTY * (req.CALC_QTY / wo.DESIRED_QTY)
```

- `CALC_QTY` **already includes scrap** (VISUAL bakes `SCRAP_PERCENT` into it). **Do not multiply by `(1 + SCRAP_PERCENT)` again.**
- `CALC_QTY / DESIRED_QTY` is UOM-agnostic — it already represents the conversion from USAGE_UM to the component's STOCK_UM.
- `SCRAP_PERCENT` is carried on the REQ row for audit only.

## Component classification (final SELECT)

```sql
CASE
    WHEN x.COMPONENT_PART_ID IS NULL                           THEN 'TOP'
    WHEN comp_psv.FABRICATED = 'Y' AND comp_wo.BASE_ID IS NULL THEN 'FABRICATED_NO_MASTER'
    WHEN comp_psv.FABRICATED = 'Y'                             THEN 'FABRICATED_EXPLODED'
    WHEN comp_psv.PURCHASED  = 'Y'                             THEN 'PURCHASED_LEAF'
    WHEN comp_psv.DETAIL_ONLY = 'Y'                            THEN 'PHANTOM'
    ELSE                                                            'OTHER_LEAF'
END AS COMPONENT_CLASS
```

`FABRICATED_NO_MASTER` is a data-quality flag — a part marked fabricated but missing its engineering master (BOM unavailable).

## "All active parts" starting set

In `recursive_bom_all_active_parts.sql` and `recursive_routing_all_active_parts.sql`:

```sql
SELECT col.PART_ID
FROM   CUST_ORDER_LINE col
WHERE  col.STATUS_EFF_DATE > @OrderMinDate         -- default 2020-01-01
  AND  col.PART_ID IS NOT NULL
  AND  col.PART_ID NOT IN ('repair-bg','rma repair')  -- hardcoded service excludes
GROUP BY col.PART_ID
HAVING COUNT(*) >= @MinOrderCount                  -- default 2
```

It's **finished-goods-with-sales-history**, not every part flagged MAKE/SELL. Good default for forward planning.

## Routing explosion (recursive_routing_*.sql)

Same recursion tree as BOM, but at each assembly level **LEFT JOIN to OPERATION** (one row per op step).

Hour math:
```sql
per_piece_hrs    = (SETUP_HRS + RUN_HRS + MOVE_HRS) / NULLIF(wo.DESIRED_QTY, 0)
EXTENDED_HRS     = per_piece_hrs * assembly_qty_per_top

-- Alternative: setup charged once per sub-assembly, only run + move amortized
EXTENDED_HRS_SETUP_ONCE = SETUP_HRS
                       + (RUN_HRS + MOVE_HRS) / wo.DESIRED_QTY * assembly_qty_per_top
```

Choose per cost model. Standard is per-piece (setup amortized).

**Outside services:** `VENDOR_ID` and `SERVICE_ID` surface for subcontracted ops. `RUN_TYPE` indicates cost model ('H' = hours).

## Site filtering

```sql
DECLARE @Site nvarchar(15) = NULL;
WHERE top_psv.SITE_ID = @Site
AND   psv.SITE_ID     = parent.SITE_ID   -- recursive join
```

BOMs don't split mid-recursion — the top part's site propagates all the way down.

## Files in this folder

| File | Purpose |
|---|---|
| `recursive_bom_from_masters.sql` | BOM explosion for a single top part (`@TopPart`) |
| `recursive_bom_all_active_parts.sql` | BOM explosion for every active FG (2+ SO lines since 2020) |
| `recursive_routing_from_masters.sql` | Routing explosion for a single top part |
| `recursive_routing_all_active_parts.sql` | Routing explosion for every active FG |

## Gotchas

- **`CALC_QTY` already has scrap baked in.** Don't multiply by `(1 + SCRAP_PERCENT)`. VISUAL already did it.
- **Circular BOMs crash without the cycle guard.** Never remove the `CHARINDEX('/' + part_id + '/', parent.PATH) = 0` check.
- **Phantom parts (`DETAIL_ONLY = 'Y'`) pass through as leaves.** They cascade into the output and consume qty; netting them out is the responsibility of downstream planning queries.
- **Missing masters** (`FABRICATED_NO_MASTER`) are a data gap — the part is flagged fabricated but has no engineering master to explode. Flag for the engineering team.
- **Alternate / preferred BOMs not supported** — only one active master per part (`PART_SITE_VIEW.ENGINEERING_MSTR`). If you need to explore alternates, update `ENGINEERING_MSTR` on `PART_SITE`.
- **Negative `QTY_PER`** (credit / return lines) flows through as negative extended qty. Unusual but possible; check business logic if it appears.
- **Level-0 anchor vs level-1 anchor** — the BOM queries here start at level 1 (first children of the top). `exploded_gross_demand` in `../demand/` uses level 0 (the top part itself) so the top qty can be tracked. Be careful not to double-count when mixing.
- **UOM conversions in `CALC_QTY / DESIRED_QTY`** — already normalized by VISUAL. Trust the ratio.
