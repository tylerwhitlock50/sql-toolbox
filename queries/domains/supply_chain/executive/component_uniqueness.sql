/*
===============================================================================
Query Name: component_uniqueness.sql

Purpose:
    For every component in the BOM of an "active" finished good, count how
    many distinct top-level (saleable) parts consume it. This is the
    foundation for separating PLATFORM cost from VARIATION cost in the
    parts inventory:

        VARIANT_UNIQUE   exactly 1 active FG uses this part
                         -> 100% of its on-hand value is the cost of that
                            single SKU's existence (e.g., the only barrel
                            for a one-off chambering, the only stock for
                            a low-runner color)
        FAMILY_LIMITED   2..@FamilyMax FGs use it
                         -> shared inside a product family (most action
                            components, family-specific receivers)
        PLATFORM_SHARED  > @FamilyMax FGs use it
                         -> common across product lines (fasteners,
                            springs, pins, generic small parts)

    Pair with:
      * sku_complexity_scorecard.sql   - per-SKU view of unique-only $
      * product_line_cost_to_serve.sql - rolled to PRODUCT_CODE / family

Grain:
    One row per (SITE_ID, COMPONENT_PART_ID).

Key technique:
    Active top parts = FGs with >= @MinOrderCount sales lines since
    @OrderMinDate (same starting set as recursive_bom_all_active_parts).
    Recursive BOM walk carries TOP_PART_ID through every level so each
    component can see every FG that pulls it.

Caveats:
    * Top-FG list is sales-history-driven. Brand-new FGs with no orders
      yet won't appear -> unique parts for those SKUs may show as
      "no top users" until first sale.
    * EXTENDED_T12_USAGE_QTY is computed at standard yield (CALC_QTY /
      DESIRED_QTY) times trailing-12 shipped qty of each consuming FG.
      Scrap is already baked into CALC_QTY -- do not re-apply.
    * On-hand $ uses standard cost from PART_SITE_VIEW. Replace with
      moving-average from part_cost_summary.sql if the cost roll is stale.
===============================================================================
*/

DECLARE @Site            nvarchar(15) = NULL;        -- NULL = all sites
DECLARE @MaxDepth        int          = 20;
DECLARE @OrderMinDate    datetime     = '2020-01-01';
DECLARE @MinOrderCount   int          = 2;
DECLARE @T12LookbackMonths int        = 12;
DECLARE @FamilyMax       int          = 5;           -- breadth threshold:
                                                     -- 2..@FamilyMax = FAMILY_LIMITED
                                                     -- > @FamilyMax  = PLATFORM_SHARED

;WITH top_parts AS (
    -- "Active" top-level FG list -- same definition used in
    -- recursive_bom_all_active_parts.sql so the two stay aligned.
    SELECT   col.PART_ID
    FROM     CUST_ORDER_LINE col
    WHERE    col.STATUS_EFF_DATE > @OrderMinDate
      AND    col.PART_ID IS NOT NULL
      AND    col.PART_ID NOT IN ('repair-bg','rma repair')
    GROUP BY col.PART_ID
    HAVING   COUNT(*) >= @MinOrderCount
),

top_part_t12 AS (
    -- Trailing-12-month shipped qty per top FG (drives volume-weighted usage).
    SELECT   col.SITE_ID,
             col.PART_ID                              AS TOP_PART_ID,
             SUM(cld.SHIPPED_QTY)                     AS T12_SHIPPED_QTY,
             SUM(cld.SHIPPED_QTY * col.UNIT_PRICE)    AS T12_REVENUE
    FROM     CUST_LINE_DEL cld
    JOIN     CUST_ORDER_LINE col
             ON  col.CUST_ORDER_ID = cld.CUST_ORDER_ID
             AND col.LINE_NO       = cld.CUST_ORDER_LINE_NO
    WHERE    cld.ACTUAL_SHIP_DATE IS NOT NULL
      AND    cld.SHIPPED_QTY > 0
      AND    cld.ACTUAL_SHIP_DATE >= DATEADD(month, -@T12LookbackMonths, GETDATE())
      AND    (@Site IS NULL OR col.SITE_ID = @Site)
    GROUP BY col.SITE_ID, col.PART_ID
),

bom AS (
    -- Anchor: level 1 = direct REQUIREMENTs of each top FG's master WO.
    SELECT
        top_psv.SITE_ID,
        top_psv.PART_ID                                AS TOP_PART_ID,
        1                                              AS BOM_LEVEL,
        req.PART_ID                                    AS COMPONENT_PART_ID,
        CAST(req.CALC_QTY / NULLIF(top_wo.DESIRED_QTY, 0) AS decimal(28,8)) AS EXTENDED_QTY,
        CAST('/' + top_wo.PART_ID + '/' + req.PART_ID + '/' AS nvarchar(4000)) AS PATH
    FROM   top_parts        tp
    JOIN   PART_SITE_VIEW   top_psv
           ON  top_psv.PART_ID = tp.PART_ID
           AND (@Site IS NULL OR top_psv.SITE_ID = @Site)
    JOIN   WORK_ORDER       top_wo
           ON  top_wo.TYPE     = 'M'
           AND top_wo.BASE_ID  = top_psv.PART_ID
           AND top_wo.LOT_ID   = CAST(top_psv.ENGINEERING_MSTR AS nvarchar(3))
           AND top_wo.SPLIT_ID = '0'
           AND top_wo.SUB_ID   = '0'
           AND top_wo.SITE_ID  = top_psv.SITE_ID
    JOIN   REQUIREMENT      req
           ON  req.WORKORDER_TYPE     = top_wo.TYPE
           AND req.WORKORDER_BASE_ID  = top_wo.BASE_ID
           AND req.WORKORDER_LOT_ID   = top_wo.LOT_ID
           AND req.WORKORDER_SPLIT_ID = top_wo.SPLIT_ID
           AND req.WORKORDER_SUB_ID   = top_wo.SUB_ID
    WHERE  req.PART_ID IS NOT NULL
      AND  req.STATUS   = 'U'

    UNION ALL

    -- Recursive: walk into fabricated children with their own master.
    SELECT
        parent.SITE_ID,
        parent.TOP_PART_ID,
        parent.BOM_LEVEL + 1,
        child_req.PART_ID,
        CAST(parent.EXTENDED_QTY
             * (child_req.CALC_QTY / NULLIF(child_wo.DESIRED_QTY, 0))
             AS decimal(28,8)),
        CAST(parent.PATH + child_req.PART_ID + '/' AS nvarchar(4000))
    FROM   bom parent
    JOIN   PART_SITE_VIEW child_psv
           ON  child_psv.PART_ID    = parent.COMPONENT_PART_ID
           AND child_psv.SITE_ID    = parent.SITE_ID
           AND child_psv.FABRICATED = 'Y'
    JOIN   WORK_ORDER     child_wo
           ON  child_wo.TYPE     = 'M'
           AND child_wo.BASE_ID  = child_psv.PART_ID
           AND child_wo.LOT_ID   = CAST(child_psv.ENGINEERING_MSTR AS nvarchar(3))
           AND child_wo.SPLIT_ID = '0'
           AND child_wo.SUB_ID   = '0'
           AND child_wo.SITE_ID  = child_psv.SITE_ID
    JOIN   REQUIREMENT child_req
           ON  child_req.WORKORDER_TYPE     = child_wo.TYPE
           AND child_req.WORKORDER_BASE_ID  = child_wo.BASE_ID
           AND child_req.WORKORDER_LOT_ID   = child_wo.LOT_ID
           AND child_req.WORKORDER_SPLIT_ID = child_wo.SPLIT_ID
           AND child_req.WORKORDER_SUB_ID   = child_wo.SUB_ID
    WHERE  child_req.PART_ID IS NOT NULL
      AND  child_req.STATUS   = 'U'
      AND  parent.BOM_LEVEL   < @MaxDepth
      AND  CHARINDEX('/' + child_req.PART_ID + '/', parent.PATH) = 0
),

-- One row per (component, top FG) -- summed across multiple sub-assembly paths.
per_top AS (
    SELECT
        b.SITE_ID,
        b.COMPONENT_PART_ID,
        b.TOP_PART_ID,
        SUM(b.EXTENDED_QTY)            AS QTY_PER_TOP,
        MIN(b.BOM_LEVEL)               AS SHALLOWEST_LEVEL
    FROM bom b
    GROUP BY b.SITE_ID, b.COMPONENT_PART_ID, b.TOP_PART_ID
),

-- Roll up to one row per component with breadth + volume metrics.
component_breadth AS (
    SELECT
        pt.SITE_ID,
        pt.COMPONENT_PART_ID,
        COUNT(DISTINCT pt.TOP_PART_ID)                          AS DISTINCT_TOP_PART_COUNT,
        MIN(pt.SHALLOWEST_LEVEL)                                AS MIN_BOM_LEVEL,
        SUM(pt.QTY_PER_TOP * ISNULL(t12.T12_SHIPPED_QTY, 0))    AS EXTENDED_T12_USAGE_QTY,
        SUM(ISNULL(t12.T12_REVENUE, 0))                         AS TOTAL_T12_FG_REVENUE,
        -- Top 5 consuming FGs by T12 qty, comma-separated. Helps the
        -- analyst eyeball "who actually uses this part".
        STUFF((
            SELECT TOP 5 ', ' + pt2.TOP_PART_ID
            FROM   per_top pt2
            LEFT JOIN top_part_t12 t2
                   ON t2.SITE_ID = pt2.SITE_ID AND t2.TOP_PART_ID = pt2.TOP_PART_ID
            WHERE  pt2.SITE_ID            = pt.SITE_ID
              AND  pt2.COMPONENT_PART_ID  = pt.COMPONENT_PART_ID
            ORDER BY ISNULL(t2.T12_SHIPPED_QTY, 0) DESC, pt2.TOP_PART_ID
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)'), 1, 2, '')                AS TOP_FG_LIST
    FROM   per_top pt
    LEFT   JOIN top_part_t12 t12
           ON  t12.SITE_ID     = pt.SITE_ID
           AND t12.TOP_PART_ID = pt.TOP_PART_ID
    GROUP BY pt.SITE_ID, pt.COMPONENT_PART_ID
)

SELECT
    cb.SITE_ID,
    cb.COMPONENT_PART_ID                                AS PART_ID,
    psv.DESCRIPTION,
    psv.PRODUCT_CODE,
    psv.COMMODITY_CODE,
    psv.STOCK_UM,
    psv.ABC_CODE,
    psv.BUYER_USER_ID,
    psv.PLANNER_USER_ID,
    psv.PREF_VENDOR_ID,
    CASE
        WHEN psv.PURCHASED = 'Y' AND ISNULL(psv.FABRICATED,'N') <> 'Y' THEN 'BUY'
        WHEN psv.FABRICATED = 'Y'                                      THEN 'MAKE'
        WHEN psv.DETAIL_ONLY = 'Y'                                     THEN 'PHANTOM'
        ELSE                                                                'OTHER'
    END                                                 AS MAKE_OR_BUY,

    -- Breadth = how many active FGs pull this part.
    cb.DISTINCT_TOP_PART_COUNT,
    cb.MIN_BOM_LEVEL,
    cb.TOP_FG_LIST,

    -- Uniqueness classification -- the headline column.
    CASE
        WHEN cb.DISTINCT_TOP_PART_COUNT = 1                         THEN 'VARIANT_UNIQUE'
        WHEN cb.DISTINCT_TOP_PART_COUNT BETWEEN 2 AND @FamilyMax    THEN 'FAMILY_LIMITED'
        ELSE                                                              'PLATFORM_SHARED'
    END                                                 AS UNIQUENESS_CLASS,

    -- On-hand exposure (standard cost basis).
    ISNULL(psv.QTY_ON_HAND, 0)                          AS QTY_ON_HAND,
    ISNULL(psv.UNIT_MATERIAL_COST, 0)                   AS UNIT_MATERIAL_COST,
    CAST(ISNULL(psv.QTY_ON_HAND, 0)
         * ISNULL(psv.UNIT_MATERIAL_COST, 0) AS decimal(23,2))      AS ON_HAND_VALUE,

    -- "Per top part" allocation -- on-hand $ split equally across consuming FGs.
    -- For VARIANT_UNIQUE this is the full on-hand $ (the tax of carrying that
    -- one SKU). For PLATFORM_SHARED it's the slice each SKU "owes" if you
    -- allocate evenly.
    CAST(ISNULL(psv.QTY_ON_HAND, 0)
         * ISNULL(psv.UNIT_MATERIAL_COST, 0)
         / NULLIF(cb.DISTINCT_TOP_PART_COUNT, 0) AS decimal(23,2))  AS ON_HAND_VALUE_PER_TOP_PART,

    -- T12 usage @ standard cost -- how much of this part actually flows in
    -- a year through the active FG demand pipe.
    cb.EXTENDED_T12_USAGE_QTY,
    CAST(cb.EXTENDED_T12_USAGE_QTY * ISNULL(psv.UNIT_MATERIAL_COST, 0)
         AS decimal(23,2))                              AS EXTENDED_T12_USAGE_VALUE,

    -- Months of supply at T12 burn rate (high MoS + low breadth = expensive).
    CASE WHEN ISNULL(cb.EXTENDED_T12_USAGE_QTY, 0) > 0
         THEN CAST(ISNULL(psv.QTY_ON_HAND, 0)
                   / (cb.EXTENDED_T12_USAGE_QTY / 12.0)
                   AS decimal(10,2))
         ELSE NULL
    END                                                 AS MONTHS_OF_SUPPLY_T12
FROM   component_breadth cb
LEFT   JOIN PART_SITE_VIEW psv
       ON  psv.PART_ID = cb.COMPONENT_PART_ID
       AND psv.SITE_ID = cb.SITE_ID
ORDER  BY
    CASE
        WHEN cb.DISTINCT_TOP_PART_COUNT = 1 THEN 1
        WHEN cb.DISTINCT_TOP_PART_COUNT BETWEEN 2 AND @FamilyMax THEN 2
        ELSE 3
    END,
    ISNULL(psv.QTY_ON_HAND, 0) * ISNULL(psv.UNIT_MATERIAL_COST, 0) DESC
OPTION (MAXRECURSION 0);
