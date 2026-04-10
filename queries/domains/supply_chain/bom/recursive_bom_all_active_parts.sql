-- =========================================================================
-- Recursive BOM explosion — driven by "active" sales parts
-- =========================================================================
-- Runs the engineering-master BOM explosion for every part that has shown
-- up on more than one customer order line since 2020-01-01. Parts that
-- don't have an engineering master at the target site will simply not
-- appear (the anchor JOIN skips them) — that's intentional, not a bug.
--
-- Every row carries a TOP_PART_ID so you can GROUP BY / filter by which
-- finished good it rolled up from.
--
-- See sibling: recursive_bom_from_masters.sql (single-part version)
-- See memory:  veca_engineering_master_linkage, veca_requirement_status_codes
-- =========================================================================

DECLARE @Site          nvarchar(15) = 'TDJ';
DECLARE @MaxDepth      int          = 20;
DECLARE @OrderMinDate  datetime     = '2020-01-01';
DECLARE @MinOrderCount int          = 2;   -- HAVING COUNT(*) > 1

;WITH top_parts AS
(
    -- Parts that have appeared on more than one CO line since @OrderMinDate
    SELECT   col.PART_ID
    FROM     CUST_ORDER_LINE col
    WHERE    col.STATUS_EFF_DATE > @OrderMinDate
      AND    col.PART_ID IS NOT NULL
      AND    col.PART_ID NOT IN ('repair-bg','rma repair')
    GROUP BY col.PART_ID
    HAVING   COUNT(*) >= @MinOrderCount
),
bom AS
(
    -- ---- Anchor: level 1 rows = REQs from each top part's master WO ----
    SELECT
        top_psv.PART_ID                      AS TOP_PART_ID,
        1                                    AS BOM_LEVEL,
        top_wo.PART_ID                       AS BUILD_PART_ID,
        top_wo.TYPE                          AS WO_TYPE,
        top_wo.BASE_ID                       AS WO_BASE_ID,
        top_wo.LOT_ID                        AS WO_LOT_ID,
        top_wo.SPLIT_ID                      AS WO_SPLIT_ID,
        top_wo.SUB_ID                        AS WO_SUB_ID,
        req.OPERATION_SEQ_NO,
        req.PIECE_NO,
        req.PART_ID                          AS COMPONENT_PART_ID,
        req.CALC_QTY                         AS QTY_PER,
        CAST(req.CALC_QTY AS decimal(28,8))  AS EXTENDED_QTY,
        req.SCRAP_PERCENT,
        req.STATUS                           AS REQ_STATUS,
        CAST('/' + top_wo.PART_ID + '/' + req.PART_ID + '/' AS nvarchar(4000)) AS PATH
    FROM   top_parts        tp
    JOIN   PART_SITE_VIEW   top_psv
           ON  top_psv.PART_ID = tp.PART_ID
           AND top_psv.SITE_ID = @Site
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
      AND  req.STATUS   = 'U'        -- current master requirement (not 'A')

    UNION ALL

    -- ---- Recursive: explode each fabricated component that has a master ----
    SELECT
        parent.TOP_PART_ID,
        parent.BOM_LEVEL + 1,
        child_wo.PART_ID,
        child_wo.TYPE,
        child_wo.BASE_ID,
        child_wo.LOT_ID,
        child_wo.SPLIT_ID,
        child_wo.SUB_ID,
        child_req.OPERATION_SEQ_NO,
        child_req.PIECE_NO,
        child_req.PART_ID,
        child_req.CALC_QTY,
        CAST(parent.EXTENDED_QTY * child_req.CALC_QTY AS decimal(28,8)),
        child_req.SCRAP_PERCENT,
        child_req.STATUS,
        CAST(parent.PATH + child_req.PART_ID + '/' AS nvarchar(4000))
    FROM   bom parent
    JOIN   PART_SITE_VIEW child_psv
           ON  child_psv.PART_ID    = parent.COMPONENT_PART_ID
           AND child_psv.SITE_ID    = @Site
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
      AND  CHARINDEX('/' + child_req.PART_ID + '/', parent.PATH) = 0   -- cycle guard
)

-- =========================================================================
-- Final projection (same column list as the single-part version, plus
-- TOP_PART_ID as the first column so results group cleanly).
-- Level-0 synthetic rows are injected for every top part that has a master.
-- =========================================================================
SELECT
    x.TOP_PART_ID,
    x.BOM_LEVEL,
    x.BUILD_PART_ID,
    x.COMPONENT_PART_ID,
    x.OPERATION_SEQ_NO,
    x.PIECE_NO,
    x.QTY_PER,
    x.EXTENDED_QTY,
    x.SCRAP_PERCENT,
    x.REQ_STATUS,
    CASE
        WHEN x.COMPONENT_PART_ID IS NULL                           THEN 'TOP'
        WHEN comp_psv.FABRICATED = 'Y' AND comp_wo.BASE_ID IS NULL THEN 'FABRICATED_NO_MASTER'
        WHEN comp_psv.FABRICATED = 'Y'                             THEN 'FABRICATED_EXPLODED'
        WHEN comp_psv.PURCHASED  = 'Y'                             THEN 'PURCHASED_LEAF'
        ELSE                                                            'OTHER_LEAF'
    END AS COMPONENT_CLASS,
    x.PATH,

    -- ---- WORK_ORDER (master being exploded at this level) ----
    wo.GLOBAL_RANK,
    wo.DESIRED_QTY        AS WO_DESIRED_QTY,
    wo.CREATE_DATE        AS WO_CREATE_DATE,
    wo.STATUS             AS WO_STATUS,
    wo.ENGINEERED_BY,
    wo.ENGINEERED_DATE,
    wo.DRAWING_ID         AS WO_DRAWING_ID,
    wo.DRAWING_REV_NO     AS WO_DRAWING_REV_NO,
    wo.PRODUCT_CODE       AS WO_PRODUCT_CODE,
    wo.COMMODITY_CODE     AS WO_COMMODITY_CODE,
    wo.MAT_GL_ACCT_ID, wo.LAB_GL_ACCT_ID, wo.BUR_GL_ACCT_ID, wo.SER_GL_ACCT_ID,
    wo.VARIABLE_TABLE, wo.SCHEDULE_GROUP_ID,
    wo.SCHED_START_DATE, wo.SCHED_FINISH_DATE, wo.COULD_FINISH_DATE,
    wo.STATUS_EFF_DATE    AS WO_STATUS_EFF_DATE,
    wo.ENTERED_BY         AS WO_ENTERED_BY,

    -- ---- PART_SITE_VIEW (subject of the row) ----
    psv.SITE_ID,
    psv.PART_ID           AS PSV_PART_ID,
    psv.ENGINEERING_MSTR,
    psv.UNIT_PRICE, psv.UNIT_MATERIAL_COST,
    psv.DESCRIPTION,
    psv.PLANNING_LEADTIME, psv.ORDER_POLICY, psv.ORDER_POINT, psv.ORDER_UP_TO_QTY,
    psv.SAFETY_STOCK_QTY, psv.FIXED_ORDER_QTY, psv.DAYS_OF_SUPPLY,
    psv.MINIMUM_ORDER_QTY, psv.MAXIMUM_ORDER_QTY,
    psv.PRODUCT_CODE      AS PSV_PRODUCT_CODE,
    psv.FABRICATED, psv.PURCHASED, psv.STOCKED,
    psv.PLANNER_USER_ID, psv.BUYER_USER_ID, psv.ABC_CODE,
    psv.QTY_ON_HAND, psv.QTY_AVAILABLE_ISS, psv.QTY_AVAILABLE_MRP,
    psv.QTY_ON_ORDER, psv.QTY_IN_DEMAND, psv.QTY_COMMITTED,
    psv.STATUS            AS PSV_STATUS,
    psv.STATUS_EFF_DATE   AS PSV_STATUS_EFF_DATE,
    psv.MULTIPLE_ORDER_QTY, psv.LAST_IMPLODE_DATE, psv.UDF_LAYOUT_ID,
    psv.USER_1, psv.USER_2, psv.USER_3, psv.USER_4, psv.USER_5,
    psv.USER_6, psv.USER_7, psv.USER_8, psv.USER_9, psv.USER_10,
    psv.CREATE_DATE       AS PSV_CREATE_DATE,
    psv.MODIFY_DATE       AS PSV_MODIFY_DATE
FROM
(
    -- Synthetic level-0 row for every top part that actually has a master
    -- (top parts without a master at @Site get no rows at all, matching
    --  the behavior of the recursive anchor)
    SELECT
        tp.PART_ID                     AS TOP_PART_ID,
        0                              AS BOM_LEVEL,
        tp.PART_ID                     AS BUILD_PART_ID,
        CAST(NULL AS nvarchar(30))     AS COMPONENT_PART_ID,
        CAST(NULL AS smallint)         AS OPERATION_SEQ_NO,
        CAST(NULL AS smallint)         AS PIECE_NO,
        CAST(1 AS decimal(28,8))       AS QTY_PER,
        CAST(1 AS decimal(28,8))       AS EXTENDED_QTY,
        CAST(NULL AS decimal(5,2))     AS SCRAP_PERCENT,
        CAST(NULL AS nchar(1))         AS REQ_STATUS,
        CAST('M' AS nchar(1))          AS WO_TYPE,
        tp.PART_ID                     AS WO_BASE_ID,
        CAST(ps.ENGINEERING_MSTR AS nvarchar(3)) AS WO_LOT_ID,
        CAST('0' AS nvarchar(3))       AS WO_SPLIT_ID,
        CAST('0' AS nvarchar(3))       AS WO_SUB_ID,
        CAST('/' + tp.PART_ID + '/' AS nvarchar(4000)) AS PATH
    FROM  (SELECT   col.PART_ID
           FROM     CUST_ORDER_LINE col
           WHERE    col.STATUS_EFF_DATE > @OrderMinDate
             AND    col.PART_ID IS NOT NULL
             AND    col.PART_ID NOT IN ('repair-bg','rma repair')
           GROUP BY col.PART_ID
           HAVING   COUNT(*) >= @MinOrderCount) tp
    JOIN   PART_SITE ps
           ON ps.PART_ID = tp.PART_ID
          AND ps.SITE_ID = @Site
    -- Only emit a level-0 row for top parts that actually have a matching master
    WHERE  EXISTS (
               SELECT 1
               FROM   WORK_ORDER wo0
               WHERE  wo0.TYPE     = 'M'
                 AND  wo0.BASE_ID  = tp.PART_ID
                 AND  wo0.LOT_ID   = CAST(ps.ENGINEERING_MSTR AS nvarchar(3))
                 AND  wo0.SPLIT_ID = '0'
                 AND  wo0.SUB_ID   = '0'
                 AND  wo0.SITE_ID  = @Site
           )

    UNION ALL

    SELECT TOP_PART_ID, BOM_LEVEL, BUILD_PART_ID, COMPONENT_PART_ID, OPERATION_SEQ_NO,
           PIECE_NO, QTY_PER, EXTENDED_QTY, SCRAP_PERCENT, REQ_STATUS,
           WO_TYPE, WO_BASE_ID, WO_LOT_ID, WO_SPLIT_ID, WO_SUB_ID, PATH
    FROM   bom
) x
LEFT JOIN WORK_ORDER wo
       ON  wo.TYPE     = x.WO_TYPE
       AND wo.BASE_ID  = x.WO_BASE_ID
       AND wo.LOT_ID   = x.WO_LOT_ID
       AND wo.SPLIT_ID = x.WO_SPLIT_ID
       AND wo.SUB_ID   = x.WO_SUB_ID
       AND wo.SITE_ID  = @Site
LEFT JOIN PART_SITE_VIEW psv
       ON  psv.PART_ID = COALESCE(x.COMPONENT_PART_ID, x.BUILD_PART_ID)
       AND psv.SITE_ID = @Site
LEFT JOIN PART_SITE_VIEW comp_psv
       ON  comp_psv.PART_ID = x.COMPONENT_PART_ID
       AND comp_psv.SITE_ID = @Site
LEFT JOIN WORK_ORDER comp_wo
       ON  comp_wo.TYPE     = 'M'
       AND comp_wo.BASE_ID  = comp_psv.PART_ID
       AND comp_wo.LOT_ID   = CAST(comp_psv.ENGINEERING_MSTR AS nvarchar(3))
       AND comp_wo.SPLIT_ID = '0'
       AND comp_wo.SUB_ID   = '0'
       AND comp_wo.SITE_ID  = @Site
ORDER BY x.TOP_PART_ID, x.PATH, x.OPERATION_SEQ_NO, x.PIECE_NO
OPTION (MAXRECURSION 0);
