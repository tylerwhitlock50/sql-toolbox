-- =========================================================================
-- Recursive BOM explosion from engineering masters (VECA)
-- =========================================================================
-- Walks an engineering master BOM for a single top part at a single site,
-- recursing into any component that is FABRICATED='Y' AND has its own master.
--
-- Key linkage:
--   PART_SITE.ENGINEERING_MSTR (int) -> WORK_ORDER.LOT_ID (nvarchar(3))
--   Master WOs are TYPE='M', BASE_ID=PART_ID, SPLIT_ID='0', SUB_ID='0'.
--
-- Master REQUIREMENT rows use STATUS='U' (NOT 'A').  'A' returns zero rows.
-- See memory: veca_engineering_master_linkage, veca_requirement_status_codes
--
-- Output row shape: parent + component per row.
--   Level 0       = synthetic header row for the top part (no component)
--   Level 1..N    = one row per REQUIREMENT line being consumed, with:
--                     BUILD_PART_ID     = the part the WO is producing
--                     COMPONENT_PART_ID = the REQ part being consumed
--                     EXTENDED_QTY      = parent.EXTENDED_QTY * CALC_QTY
--                     COMPONENT_CLASS   = TOP / FABRICATED_EXPLODED /
--                                         FABRICATED_NO_MASTER / PURCHASED_LEAF /
--                                         OTHER_LEAF
--
-- Cycle guard: PATH string + CHARINDEX check. MaxDepth defaults to 20.
-- =========================================================================

DECLARE @TopPart  nvarchar(30) = '801-09003-01';
DECLARE @Site     nvarchar(15) = 'TDJ';
DECLARE @MaxDepth int          = 20;

WITH bom AS
(
    -- ---- Anchor: level 1 rows = REQs from the top part's master WO ----
    SELECT
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
        req.QTY_PER                                                               AS QTY_PER,
        req.USAGE_UM                                                              AS USAGE_UM,
        req.CALC_QTY / NULLIF(top_wo.DESIRED_QTY, 0)                              AS STOCK_QTY_PER,
        CAST(req.CALC_QTY / NULLIF(top_wo.DESIRED_QTY, 0) AS decimal(28,8))       AS EXTENDED_QTY,
        req.SCRAP_PERCENT,
        req.STATUS                           AS REQ_STATUS,
        CAST('/' + top_wo.PART_ID + '/' + req.PART_ID + '/' AS nvarchar(4000)) AS PATH
    FROM   PART_SITE_VIEW top_psv
    JOIN   WORK_ORDER     top_wo
           ON  top_wo.TYPE     = 'M'
           AND top_wo.BASE_ID  = top_psv.PART_ID
           AND top_wo.LOT_ID   = CAST(top_psv.ENGINEERING_MSTR AS nvarchar(3))
           AND top_wo.SPLIT_ID = '0'
           AND top_wo.SUB_ID   = '0'
           AND top_wo.SITE_ID  = top_psv.SITE_ID
    JOIN   REQUIREMENT req
           ON  req.WORKORDER_TYPE     = top_wo.TYPE
           AND req.WORKORDER_BASE_ID  = top_wo.BASE_ID
           AND req.WORKORDER_LOT_ID   = top_wo.LOT_ID
           AND req.WORKORDER_SPLIT_ID = top_wo.SPLIT_ID
           AND req.WORKORDER_SUB_ID   = top_wo.SUB_ID
    WHERE  top_psv.PART_ID = @TopPart
      AND  top_psv.SITE_ID = @Site
      AND  req.PART_ID    IS NOT NULL
      AND  req.STATUS      = 'U'     -- current master requirement (not 'A')

    UNION ALL

    -- ---- Recursive: explode each fabricated component that has a master ----
    SELECT
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
        child_req.QTY_PER,
        child_req.USAGE_UM,
        child_req.CALC_QTY / NULLIF(child_wo.DESIRED_QTY, 0),
        CAST(parent.EXTENDED_QTY * (child_req.CALC_QTY / NULLIF(child_wo.DESIRED_QTY, 0)) AS decimal(28,8)),
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
-- Final projection:
--   * Level 0 synthetic row for the top part
--   * All recursive rows
--   * WO fields = master WO being exploded at that level
--   * PSV fields = the component on the row (top part on level 0)
--   * COMPONENT_CLASS flags fabricated-but-no-master leaves for diagnosis
-- =========================================================================
SELECT
    x.BOM_LEVEL,
    x.BUILD_PART_ID,
    x.COMPONENT_PART_ID,
    x.OPERATION_SEQ_NO,
    x.PIECE_NO,
    x.QTY_PER,                                                       -- raw REQ.QTY_PER in USAGE_UM
    x.USAGE_UM,                                                      -- unit the engineer entered QTY_PER in
    x.STOCK_QTY_PER,                                                 -- per-assembly yield in the component's STOCK_UM
    psv.STOCK_UM,                                                    -- UM for STOCK_QTY_PER / EXTENDED_QTY
    x.EXTENDED_QTY,                                                  -- cumulative STOCK_QTY_PER chain (stock UM)
    CAST(x.EXTENDED_QTY * psv.UNIT_MATERIAL_COST AS decimal(18,4))
        AS EXTENDED_MATERIAL_COST,                                   -- $ per 1 top assembly
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
    -- Synthetic level-0 row for the top part
    SELECT
        0                              AS BOM_LEVEL,
        @TopPart                       AS BUILD_PART_ID,
        CAST(NULL AS nvarchar(30))     AS COMPONENT_PART_ID,
        CAST(NULL AS smallint)         AS OPERATION_SEQ_NO,
        CAST(NULL AS smallint)         AS PIECE_NO,
        CAST(1 AS decimal(20,8))       AS QTY_PER,
        CAST(NULL AS nvarchar(15))     AS USAGE_UM,
        CAST(1 AS decimal(28,8))       AS STOCK_QTY_PER,
        CAST(1 AS decimal(28,8))       AS EXTENDED_QTY,
        CAST(NULL AS decimal(5,2))     AS SCRAP_PERCENT,
        CAST(NULL AS nchar(1))         AS REQ_STATUS,
        CAST('M' AS nchar(1))          AS WO_TYPE,
        @TopPart                       AS WO_BASE_ID,
        (SELECT CAST(ENGINEERING_MSTR AS nvarchar(3))
           FROM PART_SITE
          WHERE PART_ID = @TopPart AND SITE_ID = @Site) AS WO_LOT_ID,
        CAST('0' AS nvarchar(3))       AS WO_SPLIT_ID,
        CAST('0' AS nvarchar(3))       AS WO_SUB_ID,
        CAST('/' + @TopPart + '/' AS nvarchar(4000)) AS PATH

    UNION ALL

    SELECT BOM_LEVEL, BUILD_PART_ID, COMPONENT_PART_ID, OPERATION_SEQ_NO,
           PIECE_NO, QTY_PER, USAGE_UM, STOCK_QTY_PER, EXTENDED_QTY, SCRAP_PERCENT, REQ_STATUS,
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
ORDER BY x.PATH, x.OPERATION_SEQ_NO, x.PIECE_NO
OPTION (MAXRECURSION 0);
