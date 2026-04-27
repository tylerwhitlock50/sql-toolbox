/*
===============================================================================
Query Name: sku_complexity_scorecard.sql

Purpose:
    Per-SKU "what does this UPC really cost us to keep alive?" scorecard.
    For each active finished good, surface:

        SALES         T12 units shipped, T12 revenue, distinct customers
        OPERATIONS    T12 closed-WO count, total qty produced, avg batch
                      size, total setup hours, setup hours per unit
        BOM           total components, count by uniqueness class
                      (variant-unique / family-limited / platform-shared)
        INVENTORY     on-hand $ pegged ONLY to this SKU (variant-unique
                      parts) plus an allocated share of family-limited
                      and platform parts
        FLAGS         small-batch tax, low-volume + high-variant-cost,
                      slow-mover candidates

    Sort by SETUP_HRS_PER_UNIT desc or VARIANT_UNIQUE_INVENTORY_VALUE desc
    to find the SKUs whose existence is most expensive relative to their
    sales.

Grain:
    One row per (SITE_ID, TOP_PART_ID).

Pairs with:
    component_uniqueness.sql       - drill in to the actual unique parts
    product_line_cost_to_serve.sql - same metrics rolled to product line

Caveats:
    * "T12 closed WOs" filtered by WORK_ORDER.CLOSE_DATE; if your shop
      uses STATUS='C' but null close dates, fall back to
      STATUS_EFF_DATE.
    * Setup hours are PLANNED (OPERATION.SETUP_HRS). Use ACT_SETUP_HRS
      where available if you want actual.
    * Allocated platform/family $ uses equal-share allocation across
      consuming FGs. If you want volume-weighted allocation swap the
      divisor for a T12-qty share.
    * UNIT_MATERIAL_COST is standard cost. Replace with current weighted
      avg from part_cost_summary.sql if standards are stale.
===============================================================================
*/

DECLARE @Site              nvarchar(15) = NULL;
DECLARE @MaxDepth          int          = 20;
DECLARE @OrderMinDate      datetime     = '2020-01-01';
DECLARE @MinOrderCount     int          = 2;
DECLARE @T12LookbackMonths int          = 12;
DECLARE @FamilyMax         int          = 5;
DECLARE @SmallBatchQty     decimal(20,8)= 25;       -- WO qty <= this = small batch
DECLARE @LowVolumeUnits    decimal(20,8)= 100;      -- T12 units <= this = low volume

;WITH top_parts AS (
    SELECT   col.PART_ID
    FROM     CUST_ORDER_LINE col
    WHERE    col.STATUS_EFF_DATE > @OrderMinDate
      AND    col.PART_ID IS NOT NULL
      AND    col.PART_ID NOT IN ('repair-bg','rma repair')
    GROUP BY col.PART_ID
    HAVING   COUNT(*) >= @MinOrderCount
),

-- ======================================================================
-- Sales: trailing-12 shipments per top FG (units, revenue, customers)
-- ======================================================================
sales_t12 AS (
    SELECT
        col.SITE_ID,
        col.PART_ID                                        AS TOP_PART_ID,
        SUM(cld.SHIPPED_QTY)                               AS T12_UNITS,
        SUM(cld.SHIPPED_QTY * col.UNIT_PRICE
            * (100.0 - COALESCE(col.TRADE_DISC_PERCENT,0)) / 100.0)
                                                           AS T12_REVENUE,
        COUNT(DISTINCT co.CUSTOMER_ID)                     AS T12_DISTINCT_CUSTOMERS,
        COUNT(DISTINCT col.CUST_ORDER_ID)                  AS T12_DISTINCT_SOS,
        MIN(cld.ACTUAL_SHIP_DATE)                          AS T12_FIRST_SHIP_DATE,
        MAX(cld.ACTUAL_SHIP_DATE)                          AS T12_LAST_SHIP_DATE
    FROM     CUST_LINE_DEL cld
    JOIN     CUST_ORDER_LINE col
             ON  col.CUST_ORDER_ID = cld.CUST_ORDER_ID
             AND col.LINE_NO       = cld.CUST_ORDER_LINE_NO
    JOIN     CUSTOMER_ORDER co ON co.ID = col.CUST_ORDER_ID
    WHERE    cld.ACTUAL_SHIP_DATE IS NOT NULL
      AND    cld.SHIPPED_QTY > 0
      AND    cld.ACTUAL_SHIP_DATE >= DATEADD(month, -@T12LookbackMonths, GETDATE())
      AND    (@Site IS NULL OR col.SITE_ID = @Site)
    GROUP BY col.SITE_ID, col.PART_ID
),

-- ======================================================================
-- Production: closed WOs in T12 per top FG
-- ======================================================================
wo_closed_t12 AS (
    SELECT
        wo.SITE_ID,
        wo.PART_ID                                         AS TOP_PART_ID,
        wo.TYPE, wo.BASE_ID, wo.LOT_ID, wo.SPLIT_ID, wo.SUB_ID,
        wo.DESIRED_QTY,
        ISNULL(wo.ACT_MATERIAL_COST,0)
          + ISNULL(wo.ACT_LABOR_COST,0)
          + ISNULL(wo.ACT_BURDEN_COST,0)
          + ISNULL(wo.ACT_SERVICE_COST,0)                  AS WO_ACT_TOTAL_COST
    FROM     WORK_ORDER wo
    WHERE    wo.TYPE = 'W'
      AND    wo.STATUS = 'C'
      AND    COALESCE(wo.CLOSE_DATE, wo.STATUS_EFF_DATE)
                 >= DATEADD(month, -@T12LookbackMonths, GETDATE())
      AND    (@Site IS NULL OR wo.SITE_ID = @Site)
),

wo_setup_hours AS (
    -- Planned setup hours per closed WO. Setup is run once per WO
    -- regardless of qty, so this is the "small batch tax".
    SELECT
        w.SITE_ID,
        w.TOP_PART_ID,
        w.TYPE, w.BASE_ID, w.LOT_ID, w.SPLIT_ID, w.SUB_ID,
        SUM(ISNULL(op.SETUP_HRS, 0))                       AS WO_SETUP_HRS,
        SUM(ISNULL(op.RUN_HRS, 0) + ISNULL(op.MOVE_HRS, 0))AS WO_RUN_MOVE_HRS
    FROM     wo_closed_t12 w
    LEFT JOIN OPERATION op
             ON  op.WORKORDER_TYPE     = w.TYPE
             AND op.WORKORDER_BASE_ID  = w.BASE_ID
             AND op.WORKORDER_LOT_ID   = w.LOT_ID
             AND op.WORKORDER_SPLIT_ID = w.SPLIT_ID
             AND op.WORKORDER_SUB_ID   = w.SUB_ID
    GROUP BY w.SITE_ID, w.TOP_PART_ID,
             w.TYPE, w.BASE_ID, w.LOT_ID, w.SPLIT_ID, w.SUB_ID
),

production_t12 AS (
    SELECT
        w.SITE_ID,
        w.TOP_PART_ID,
        COUNT(*)                                           AS T12_WO_COUNT,
        SUM(w.DESIRED_QTY)                                 AS T12_WO_QTY,
        AVG(CAST(w.DESIRED_QTY AS decimal(20,4)))          AS T12_AVG_BATCH_SIZE,
        MIN(w.DESIRED_QTY)                                 AS T12_MIN_BATCH_SIZE,
        SUM(CASE WHEN w.DESIRED_QTY <= @SmallBatchQty THEN 1 ELSE 0 END)
                                                           AS T12_SMALL_BATCH_WO_COUNT,
        SUM(ISNULL(sh.WO_SETUP_HRS, 0))                    AS T12_SETUP_HRS,
        SUM(ISNULL(sh.WO_RUN_MOVE_HRS, 0))                 AS T12_RUN_MOVE_HRS,
        SUM(w.WO_ACT_TOTAL_COST)                           AS T12_WO_ACT_COST
    FROM   wo_closed_t12 w
    LEFT   JOIN wo_setup_hours sh
           ON  sh.SITE_ID = w.SITE_ID
           AND sh.TYPE     = w.TYPE
           AND sh.BASE_ID  = w.BASE_ID
           AND sh.LOT_ID   = w.LOT_ID
           AND sh.SPLIT_ID = w.SPLIT_ID
           AND sh.SUB_ID   = w.SUB_ID
    GROUP BY w.SITE_ID, w.TOP_PART_ID
),

-- ======================================================================
-- BOM walk -- recursive, carrying TOP_PART_ID for the per-SKU rollup.
-- (Same shape as component_uniqueness.sql; kept inline so this query
--  is self-contained.)
-- ======================================================================
bom AS (
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

-- One row per (component, top FG)
per_top AS (
    SELECT
        b.SITE_ID,
        b.COMPONENT_PART_ID,
        b.TOP_PART_ID
    FROM bom b
    GROUP BY b.SITE_ID, b.COMPONENT_PART_ID, b.TOP_PART_ID
),

-- Per-component breadth (= consumer count)
component_breadth AS (
    SELECT
        SITE_ID,
        COMPONENT_PART_ID,
        COUNT(DISTINCT TOP_PART_ID) AS DISTINCT_TOP_PART_COUNT
    FROM   per_top
    GROUP BY SITE_ID, COMPONENT_PART_ID
),

-- Join breadth back onto each (top, component) pair so we can roll
-- inventory $ up to the SKU.
sku_components AS (
    SELECT
        pt.SITE_ID,
        pt.TOP_PART_ID,
        pt.COMPONENT_PART_ID,
        cb.DISTINCT_TOP_PART_COUNT,
        CASE
            WHEN cb.DISTINCT_TOP_PART_COUNT = 1                        THEN 'VARIANT_UNIQUE'
            WHEN cb.DISTINCT_TOP_PART_COUNT BETWEEN 2 AND @FamilyMax   THEN 'FAMILY_LIMITED'
            ELSE                                                            'PLATFORM_SHARED'
        END AS UNIQUENESS_CLASS,
        ISNULL(psv.QTY_ON_HAND, 0)
          * ISNULL(psv.UNIT_MATERIAL_COST, 0)               AS COMPONENT_ON_HAND_VALUE,
        psv.UNIT_MATERIAL_COST
    FROM   per_top pt
    JOIN   component_breadth cb
           ON  cb.SITE_ID           = pt.SITE_ID
           AND cb.COMPONENT_PART_ID = pt.COMPONENT_PART_ID
    LEFT   JOIN PART_SITE_VIEW psv
           ON  psv.SITE_ID = pt.SITE_ID
           AND psv.PART_ID = pt.COMPONENT_PART_ID
),

-- Rollup of BOM complexity + allocated inventory $ per top FG.
sku_bom_rollup AS (
    SELECT
        sc.SITE_ID,
        sc.TOP_PART_ID,
        COUNT(*)                                                          AS BOM_COMPONENT_COUNT,
        SUM(CASE WHEN sc.UNIQUENESS_CLASS = 'VARIANT_UNIQUE'  THEN 1 ELSE 0 END) AS VARIANT_UNIQUE_COUNT,
        SUM(CASE WHEN sc.UNIQUENESS_CLASS = 'FAMILY_LIMITED'  THEN 1 ELSE 0 END) AS FAMILY_LIMITED_COUNT,
        SUM(CASE WHEN sc.UNIQUENESS_CLASS = 'PLATFORM_SHARED' THEN 1 ELSE 0 END) AS PLATFORM_SHARED_COUNT,

        -- 100% of variant-unique on-hand $ is on this SKU (no one else uses it).
        CAST(SUM(CASE WHEN sc.UNIQUENESS_CLASS = 'VARIANT_UNIQUE'
                      THEN sc.COMPONENT_ON_HAND_VALUE ELSE 0 END)
             AS decimal(23,2))                                            AS VARIANT_UNIQUE_INVENTORY_VALUE,

        -- Allocated share of family-limited and platform $ assuming
        -- equal split across consuming FGs.
        CAST(SUM(CASE WHEN sc.UNIQUENESS_CLASS = 'FAMILY_LIMITED'
                      THEN sc.COMPONENT_ON_HAND_VALUE
                           / NULLIF(sc.DISTINCT_TOP_PART_COUNT, 0)
                      ELSE 0 END)
             AS decimal(23,2))                                            AS FAMILY_LIMITED_ALLOC_VALUE,
        CAST(SUM(CASE WHEN sc.UNIQUENESS_CLASS = 'PLATFORM_SHARED'
                      THEN sc.COMPONENT_ON_HAND_VALUE
                           / NULLIF(sc.DISTINCT_TOP_PART_COUNT, 0)
                      ELSE 0 END)
             AS decimal(23,2))                                            AS PLATFORM_SHARED_ALLOC_VALUE
    FROM   sku_components sc
    GROUP BY sc.SITE_ID, sc.TOP_PART_ID
)

SELECT
    psv.SITE_ID,
    psv.PART_ID                                                AS TOP_PART_ID,
    psv.DESCRIPTION,
    psv.PRODUCT_CODE,
    psv.COMMODITY_CODE,
    psv.STOCK_UM,
    psv.ABC_CODE,
    psv.PLANNER_USER_ID,
    psv.STATUS                                                 AS PART_STATUS,

    -- ----- SALES (T12) -----
    ISNULL(s.T12_UNITS, 0)                                     AS T12_UNITS,
    CAST(ISNULL(s.T12_REVENUE, 0) AS decimal(23,2))            AS T12_REVENUE,
    ISNULL(s.T12_DISTINCT_CUSTOMERS, 0)                        AS T12_DISTINCT_CUSTOMERS,
    ISNULL(s.T12_DISTINCT_SOS, 0)                              AS T12_DISTINCT_SOS,
    s.T12_FIRST_SHIP_DATE,
    s.T12_LAST_SHIP_DATE,

    -- ----- PRODUCTION (T12) -- the small-batch tax -----
    ISNULL(p.T12_WO_COUNT, 0)                                  AS T12_WO_COUNT,
    ISNULL(p.T12_WO_QTY, 0)                                    AS T12_WO_QTY,
    CAST(p.T12_AVG_BATCH_SIZE AS decimal(20,2))                AS T12_AVG_BATCH_SIZE,
    ISNULL(p.T12_SMALL_BATCH_WO_COUNT, 0)                      AS T12_SMALL_BATCH_WO_COUNT,
    CAST(ISNULL(p.T12_SETUP_HRS, 0) AS decimal(15,2))          AS T12_SETUP_HRS,
    CAST(ISNULL(p.T12_RUN_MOVE_HRS, 0) AS decimal(15,2))       AS T12_RUN_MOVE_HRS,
    CAST(ISNULL(p.T12_SETUP_HRS, 0)
         / NULLIF(p.T12_WO_QTY, 0)
         AS decimal(15,4))                                     AS SETUP_HRS_PER_UNIT,
    CAST(ISNULL(p.T12_WO_ACT_COST, 0)
         / NULLIF(p.T12_WO_QTY, 0)
         AS decimal(20,4))                                     AS ACT_COST_PER_UNIT,

    -- ----- BOM COMPLEXITY -----
    ISNULL(b.BOM_COMPONENT_COUNT, 0)                           AS BOM_COMPONENT_COUNT,
    ISNULL(b.VARIANT_UNIQUE_COUNT, 0)                          AS VARIANT_UNIQUE_COUNT,
    ISNULL(b.FAMILY_LIMITED_COUNT, 0)                          AS FAMILY_LIMITED_COUNT,
    ISNULL(b.PLATFORM_SHARED_COUNT, 0)                         AS PLATFORM_SHARED_COUNT,
    CAST(100.0 * ISNULL(b.VARIANT_UNIQUE_COUNT, 0)
         / NULLIF(b.BOM_COMPONENT_COUNT, 0)
         AS decimal(6,2))                                      AS VARIANT_UNIQUE_PCT_OF_BOM,

    -- ----- INVENTORY EXPOSURE -----
    ISNULL(b.VARIANT_UNIQUE_INVENTORY_VALUE, 0)                AS VARIANT_UNIQUE_INVENTORY_VALUE,
    ISNULL(b.FAMILY_LIMITED_ALLOC_VALUE, 0)                    AS FAMILY_LIMITED_ALLOC_VALUE,
    ISNULL(b.PLATFORM_SHARED_ALLOC_VALUE, 0)                   AS PLATFORM_SHARED_ALLOC_VALUE,
    ISNULL(b.VARIANT_UNIQUE_INVENTORY_VALUE, 0)
      + ISNULL(b.FAMILY_LIMITED_ALLOC_VALUE, 0)
      + ISNULL(b.PLATFORM_SHARED_ALLOC_VALUE, 0)               AS ALLOCATED_TOTAL_INVENTORY_VALUE,

    -- ----- DERIVED / FLAGS -----
    -- Variation tax per shipped unit = $ of unique-only inventory tied
    -- to this SKU divided by T12 units. High = the SKU's continued
    -- existence costs a lot per unit shipped.
    CAST(ISNULL(b.VARIANT_UNIQUE_INVENTORY_VALUE, 0)
         / NULLIF(s.T12_UNITS, 0)
         AS decimal(20,4))                                     AS VARIANT_INVENTORY_PER_UNIT_T12,

    CASE
        WHEN ISNULL(s.T12_UNITS, 0) = 0 AND ISNULL(b.VARIANT_UNIQUE_INVENTORY_VALUE, 0) > 0
            THEN 'DEAD_SKU_WITH_UNIQUE_INVENTORY'
        WHEN ISNULL(s.T12_UNITS, 0) <= @LowVolumeUnits
             AND ISNULL(b.VARIANT_UNIQUE_INVENTORY_VALUE, 0) >= 5000
            THEN 'LOW_VOLUME_HIGH_VARIANT_COST'
        WHEN ISNULL(p.T12_AVG_BATCH_SIZE, 0) > 0
             AND p.T12_AVG_BATCH_SIZE <= @SmallBatchQty
             AND ISNULL(p.T12_WO_COUNT, 0) >= 3
            THEN 'CHRONIC_SMALL_BATCHES'
        WHEN ISNULL(b.VARIANT_UNIQUE_COUNT, 0) >= 5
             AND ISNULL(s.T12_UNITS, 0) <= @LowVolumeUnits
            THEN 'HIGH_VARIATION_LOW_VOLUME'
        ELSE NULL
    END                                                        AS COMPLEXITY_FLAG
FROM   PART_SITE_VIEW psv
JOIN   top_parts tp ON tp.PART_ID = psv.PART_ID
LEFT   JOIN sales_t12      s ON s.SITE_ID = psv.SITE_ID AND s.TOP_PART_ID = psv.PART_ID
LEFT   JOIN production_t12 p ON p.SITE_ID = psv.SITE_ID AND p.TOP_PART_ID = psv.PART_ID
LEFT   JOIN sku_bom_rollup b ON b.SITE_ID = psv.SITE_ID AND b.TOP_PART_ID = psv.PART_ID
WHERE  (@Site IS NULL OR psv.SITE_ID = @Site)
ORDER  BY ISNULL(b.VARIANT_UNIQUE_INVENTORY_VALUE, 0) DESC,
          ISNULL(s.T12_UNITS, 0) ASC
OPTION (MAXRECURSION 0);
