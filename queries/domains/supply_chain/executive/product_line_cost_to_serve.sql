/*
===============================================================================
Query Name: product_line_cost_to_serve.sql

Purpose:
    Roll the per-SKU complexity scorecard up to a product family so the
    CEO can answer: "What does it cost us to support THIS product line?"

    Output is one row per (SITE_ID, GROUP_VALUE) where GROUP_VALUE is
    PRODUCT_CODE by default, switchable via @GroupBy:

        @GroupBy = 'PRODUCT_CODE'   (default)  -- accounting product code
        @GroupBy = 'COMMODITY_CODE'            -- commodity classification

    Per family the report shows:

        SKU MIX
            * total SKUs assigned to the family
            * how many shipped at least once in T12 (active)
            * dead SKUs that still hold variant-unique inventory $

        SALES (T12)
            * units, revenue, distinct customers

        OPERATIONS (T12)
            * total WOs, total qty produced, avg batch size,
              small-batch WO count, total setup hours, setup hrs / unit

        INVENTORY EXPOSURE
            * $ of variant-unique parts (the cost of variation)
            * $ of family-limited parts (allocated)
            * $ of platform-shared parts (allocated)
            * stagnant $ inside the family (no movement >= @StagnantMonths)

        COST-TO-SERVE RATIOS
            * variant-unique inventory per active SKU
            * variant-unique inventory per T12 revenue $
            * setup hours per shipped unit

Pairs with:
    component_uniqueness.sql       - drill in to the actual unique parts
    sku_complexity_scorecard.sql   - drill in to specific UPCs

Caveats:
    * Family attribution comes from the FG's PRODUCT_CODE / COMMODITY_CODE
      on PART_SITE_VIEW. SKUs without a code roll up under '(unassigned)'.
    * Component-level $ is allocated to the FG, not to the FG's family.
      A platform component used by FGs in two different product codes is
      split across consuming FGs equally regardless of family.
    * "Active SKU" = at least one shipment in T12.
===============================================================================
*/

DECLARE @Site              nvarchar(15) = NULL;
DECLARE @MaxDepth          int          = 20;
DECLARE @OrderMinDate      datetime     = '2020-01-01';
DECLARE @MinOrderCount     int          = 2;
DECLARE @T12LookbackMonths int          = 12;
DECLARE @FamilyMax         int          = 5;
DECLARE @SmallBatchQty     decimal(20,8)= 25;
DECLARE @StagnantMonths    int          = 12;
DECLARE @GroupBy           nvarchar(20) = 'PRODUCT_CODE';   -- or 'COMMODITY_CODE'

;WITH top_parts AS (
    SELECT   col.PART_ID
    FROM     CUST_ORDER_LINE col
    WHERE    col.STATUS_EFF_DATE > @OrderMinDate
      AND    col.PART_ID IS NOT NULL
      AND    col.PART_ID NOT IN ('repair-bg','rma repair')
    GROUP BY col.PART_ID
    HAVING   COUNT(*) >= @MinOrderCount
),

-- Each top FG with its family value (depending on @GroupBy).
top_with_family AS (
    SELECT
        psv.SITE_ID,
        psv.PART_ID                                              AS TOP_PART_ID,
        ISNULL(
            CASE WHEN @GroupBy = 'COMMODITY_CODE' THEN psv.COMMODITY_CODE
                 ELSE psv.PRODUCT_CODE
            END, '(unassigned)')                                 AS GROUP_VALUE
    FROM   PART_SITE_VIEW psv
    JOIN   top_parts tp ON tp.PART_ID = psv.PART_ID
    WHERE  (@Site IS NULL OR psv.SITE_ID = @Site)
),

-- ======================================================================
-- T12 sales per top FG
-- ======================================================================
sales_t12 AS (
    SELECT
        col.SITE_ID,
        col.PART_ID                                       AS TOP_PART_ID,
        SUM(cld.SHIPPED_QTY)                              AS T12_UNITS,
        SUM(cld.SHIPPED_QTY * col.UNIT_PRICE
            * (100.0 - COALESCE(col.TRADE_DISC_PERCENT,0)) / 100.0)
                                                          AS T12_REVENUE,
        COUNT(DISTINCT co.CUSTOMER_ID)                    AS T12_DISTINCT_CUSTOMERS
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
-- T12 closed-WO production per top FG
-- ======================================================================
wo_closed_t12 AS (
    SELECT
        wo.SITE_ID,
        wo.PART_ID                                        AS TOP_PART_ID,
        wo.TYPE, wo.BASE_ID, wo.LOT_ID, wo.SPLIT_ID, wo.SUB_ID,
        wo.DESIRED_QTY
    FROM     WORK_ORDER wo
    WHERE    wo.TYPE = 'W'
      AND    wo.STATUS = 'C'
      AND    COALESCE(wo.CLOSE_DATE, wo.STATUS_EFF_DATE)
                 >= DATEADD(month, -@T12LookbackMonths, GETDATE())
      AND    (@Site IS NULL OR wo.SITE_ID = @Site)
),

wo_setup_hours AS (
    SELECT
        w.SITE_ID, w.TOP_PART_ID,
        w.TYPE, w.BASE_ID, w.LOT_ID, w.SPLIT_ID, w.SUB_ID,
        SUM(ISNULL(op.SETUP_HRS, 0))                      AS WO_SETUP_HRS
    FROM   wo_closed_t12 w
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
        COUNT(*)                                          AS T12_WO_COUNT,
        SUM(w.DESIRED_QTY)                                AS T12_WO_QTY,
        AVG(CAST(w.DESIRED_QTY AS decimal(20,4)))         AS T12_AVG_BATCH_SIZE,
        SUM(CASE WHEN w.DESIRED_QTY <= @SmallBatchQty THEN 1 ELSE 0 END)
                                                          AS T12_SMALL_BATCH_WO_COUNT,
        SUM(ISNULL(sh.WO_SETUP_HRS, 0))                   AS T12_SETUP_HRS
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
-- BOM walk + breadth (same as the other two queries; inline for self-containment)
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

per_top AS (
    SELECT b.SITE_ID, b.COMPONENT_PART_ID, b.TOP_PART_ID
    FROM   bom b
    GROUP BY b.SITE_ID, b.COMPONENT_PART_ID, b.TOP_PART_ID
),

component_breadth AS (
    SELECT SITE_ID, COMPONENT_PART_ID,
           COUNT(DISTINCT TOP_PART_ID) AS DISTINCT_TOP_PART_COUNT
    FROM   per_top
    GROUP BY SITE_ID, COMPONENT_PART_ID
),

-- Per-(top, component) inventory $ allocation, classified.
sku_components AS (
    SELECT
        pt.SITE_ID,
        pt.TOP_PART_ID,
        pt.COMPONENT_PART_ID,
        cb.DISTINCT_TOP_PART_COUNT,
        CASE
            WHEN cb.DISTINCT_TOP_PART_COUNT = 1                       THEN 'VARIANT_UNIQUE'
            WHEN cb.DISTINCT_TOP_PART_COUNT BETWEEN 2 AND @FamilyMax  THEN 'FAMILY_LIMITED'
            ELSE                                                           'PLATFORM_SHARED'
        END                                                AS UNIQUENESS_CLASS,
        ISNULL(psv.QTY_ON_HAND, 0)
          * ISNULL(psv.UNIT_MATERIAL_COST, 0)              AS COMPONENT_ON_HAND_VALUE
    FROM   per_top pt
    JOIN   component_breadth cb
           ON  cb.SITE_ID           = pt.SITE_ID
           AND cb.COMPONENT_PART_ID = pt.COMPONENT_PART_ID
    LEFT   JOIN PART_SITE_VIEW psv
           ON  psv.SITE_ID = pt.SITE_ID
           AND psv.PART_ID = pt.COMPONENT_PART_ID
),

-- Per-SKU rollup (allocated $ per SKU).
sku_bom_rollup AS (
    SELECT
        sc.SITE_ID,
        sc.TOP_PART_ID,
        SUM(CASE WHEN sc.UNIQUENESS_CLASS = 'VARIANT_UNIQUE'
                 THEN sc.COMPONENT_ON_HAND_VALUE ELSE 0 END)         AS VARIANT_UNIQUE_VALUE,
        SUM(CASE WHEN sc.UNIQUENESS_CLASS = 'FAMILY_LIMITED'
                 THEN sc.COMPONENT_ON_HAND_VALUE
                      / NULLIF(sc.DISTINCT_TOP_PART_COUNT, 0)
                 ELSE 0 END)                                         AS FAMILY_LIMITED_ALLOC_VALUE,
        SUM(CASE WHEN sc.UNIQUENESS_CLASS = 'PLATFORM_SHARED'
                 THEN sc.COMPONENT_ON_HAND_VALUE
                      / NULLIF(sc.DISTINCT_TOP_PART_COUNT, 0)
                 ELSE 0 END)                                         AS PLATFORM_SHARED_ALLOC_VALUE,
        COUNT(*)                                                     AS BOM_COMPONENT_COUNT,
        SUM(CASE WHEN sc.UNIQUENESS_CLASS = 'VARIANT_UNIQUE' THEN 1 ELSE 0 END)
                                                                     AS VARIANT_UNIQUE_COMPONENT_COUNT
    FROM   sku_components sc
    GROUP BY sc.SITE_ID, sc.TOP_PART_ID
),

-- Stagnant $ inside the family: variant-unique components with no
-- INVENTORY_TRANS movement in @StagnantMonths.
last_movement AS (
    SELECT it.SITE_ID, it.PART_ID, MAX(it.TRANSACTION_DATE) AS LAST_TRANS_DATE
    FROM   INVENTORY_TRANS it
    WHERE  it.PART_ID IS NOT NULL
      AND  (@Site IS NULL OR it.SITE_ID = @Site)
    GROUP BY it.SITE_ID, it.PART_ID
),

stagnant_per_sku AS (
    SELECT
        sc.SITE_ID,
        sc.TOP_PART_ID,
        SUM(CASE
              WHEN sc.UNIQUENESS_CLASS = 'VARIANT_UNIQUE'
               AND (lm.LAST_TRANS_DATE IS NULL
                    OR lm.LAST_TRANS_DATE < DATEADD(month, -@StagnantMonths, GETDATE()))
              THEN sc.COMPONENT_ON_HAND_VALUE
              ELSE 0
            END)                                                     AS STAGNANT_VARIANT_UNIQUE_VALUE
    FROM   sku_components sc
    LEFT   JOIN last_movement lm
           ON  lm.SITE_ID = sc.SITE_ID
           AND lm.PART_ID = sc.COMPONENT_PART_ID
    GROUP BY sc.SITE_ID, sc.TOP_PART_ID
)

-- ======================================================================
-- Final rollup: family-level totals + cost-to-serve ratios
-- ======================================================================
SELECT
    twf.SITE_ID,
    twf.GROUP_VALUE                                              AS PRODUCT_LINE,
    @GroupBy                                                     AS GROUP_BY_FIELD,

    -- ----- SKU MIX -----
    COUNT(*)                                                     AS SKU_COUNT,
    SUM(CASE WHEN ISNULL(s.T12_UNITS, 0) > 0 THEN 1 ELSE 0 END)  AS ACTIVE_SKU_COUNT,
    SUM(CASE WHEN ISNULL(s.T12_UNITS, 0) = 0
              AND ISNULL(b.VARIANT_UNIQUE_VALUE, 0) > 0
              THEN 1 ELSE 0 END)                                 AS DEAD_SKUS_WITH_UNIQUE_INV,

    -- ----- SALES (T12) -----
    SUM(ISNULL(s.T12_UNITS, 0))                                  AS T12_UNITS,
    CAST(SUM(ISNULL(s.T12_REVENUE, 0)) AS decimal(23,2))         AS T12_REVENUE,
    SUM(ISNULL(s.T12_DISTINCT_CUSTOMERS, 0))                     AS T12_CUSTOMER_LINES,

    -- ----- OPERATIONS (T12) -----
    SUM(ISNULL(p.T12_WO_COUNT, 0))                               AS T12_WO_COUNT,
    SUM(ISNULL(p.T12_WO_QTY, 0))                                 AS T12_WO_QTY,
    CAST(SUM(ISNULL(p.T12_WO_QTY, 0))
         / NULLIF(SUM(ISNULL(p.T12_WO_COUNT, 0)), 0)
         AS decimal(20,2))                                       AS AVG_BATCH_SIZE,
    SUM(ISNULL(p.T12_SMALL_BATCH_WO_COUNT, 0))                   AS T12_SMALL_BATCH_WO_COUNT,
    CAST(SUM(ISNULL(p.T12_SETUP_HRS, 0)) AS decimal(15,2))       AS T12_SETUP_HRS,
    CAST(SUM(ISNULL(p.T12_SETUP_HRS, 0))
         / NULLIF(SUM(ISNULL(s.T12_UNITS, 0)), 0)
         AS decimal(15,4))                                       AS SETUP_HRS_PER_UNIT_T12,

    -- ----- INVENTORY EXPOSURE -----
    CAST(SUM(ISNULL(b.VARIANT_UNIQUE_VALUE, 0)) AS decimal(23,2))           AS VARIANT_UNIQUE_INVENTORY_VALUE,
    CAST(SUM(ISNULL(b.FAMILY_LIMITED_ALLOC_VALUE, 0)) AS decimal(23,2))     AS FAMILY_LIMITED_ALLOC_VALUE,
    CAST(SUM(ISNULL(b.PLATFORM_SHARED_ALLOC_VALUE, 0)) AS decimal(23,2))    AS PLATFORM_SHARED_ALLOC_VALUE,
    CAST(SUM(ISNULL(b.VARIANT_UNIQUE_VALUE, 0)
             + ISNULL(b.FAMILY_LIMITED_ALLOC_VALUE, 0)
             + ISNULL(b.PLATFORM_SHARED_ALLOC_VALUE, 0))
         AS decimal(23,2))                                                  AS TOTAL_ALLOCATED_INVENTORY_VALUE,
    CAST(SUM(ISNULL(st.STAGNANT_VARIANT_UNIQUE_VALUE, 0))
         AS decimal(23,2))                                                  AS STAGNANT_VARIANT_INVENTORY_VALUE,

    -- ----- BOM COMPLEXITY (avg per SKU in this family) -----
    CAST(AVG(CAST(ISNULL(b.BOM_COMPONENT_COUNT, 0) AS decimal(10,2)))
         AS decimal(10,2))                                       AS AVG_BOM_COMPONENT_COUNT,
    CAST(AVG(CAST(ISNULL(b.VARIANT_UNIQUE_COMPONENT_COUNT, 0) AS decimal(10,2)))
         AS decimal(10,2))                                       AS AVG_VARIANT_UNIQUE_COMPONENTS_PER_SKU,

    -- ----- COST-TO-SERVE RATIOS -----
    -- $ of variant-unique inventory per active SKU (the "carrying cost
    -- of variation" -- bigger = each new SKU drags more inventory).
    CAST(SUM(ISNULL(b.VARIANT_UNIQUE_VALUE, 0))
         / NULLIF(SUM(CASE WHEN ISNULL(s.T12_UNITS, 0) > 0 THEN 1 ELSE 0 END), 0)
         AS decimal(23,2))                                       AS VARIANT_INVENTORY_PER_ACTIVE_SKU,

    -- $ of variant-unique inventory per T12 revenue $ (lower = healthy
    -- cost coverage; > 0.25 means a quarter of revenue is parked as
    -- single-SKU inventory).
    CAST(SUM(ISNULL(b.VARIANT_UNIQUE_VALUE, 0))
         / NULLIF(SUM(ISNULL(s.T12_REVENUE, 0)), 0)
         AS decimal(10,4))                                       AS VARIANT_INVENTORY_PER_REVENUE_DOLLAR,

    -- Total allocated inventory $ per active SKU (full carrying cost
    -- attributable to one SKU on average).
    CAST(SUM(ISNULL(b.VARIANT_UNIQUE_VALUE, 0)
             + ISNULL(b.FAMILY_LIMITED_ALLOC_VALUE, 0)
             + ISNULL(b.PLATFORM_SHARED_ALLOC_VALUE, 0))
         / NULLIF(SUM(CASE WHEN ISNULL(s.T12_UNITS, 0) > 0 THEN 1 ELSE 0 END), 0)
         AS decimal(23,2))                                       AS TOTAL_INVENTORY_PER_ACTIVE_SKU
FROM   top_with_family twf
LEFT   JOIN sales_t12       s  ON s.SITE_ID  = twf.SITE_ID AND s.TOP_PART_ID  = twf.TOP_PART_ID
LEFT   JOIN production_t12  p  ON p.SITE_ID  = twf.SITE_ID AND p.TOP_PART_ID  = twf.TOP_PART_ID
LEFT   JOIN sku_bom_rollup  b  ON b.SITE_ID  = twf.SITE_ID AND b.TOP_PART_ID  = twf.TOP_PART_ID
LEFT   JOIN stagnant_per_sku st ON st.SITE_ID = twf.SITE_ID AND st.TOP_PART_ID = twf.TOP_PART_ID
GROUP  BY twf.SITE_ID, twf.GROUP_VALUE
ORDER  BY SUM(ISNULL(b.VARIANT_UNIQUE_VALUE, 0)) DESC
OPTION (MAXRECURSION 0);
