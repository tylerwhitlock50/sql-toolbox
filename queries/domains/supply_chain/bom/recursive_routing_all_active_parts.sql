-- =========================================================================
-- Recursive routing explosion for all "active" sales parts
-- =========================================================================
-- Same walk logic as recursive_routing_from_masters.sql, but driven off
-- every part that has appeared on more than one CO line since 2020-01-01.
--
-- Every row carries a TOP_PART_ID so you can aggregate per finished good:
--     SELECT TOP_PART_ID, SUM(EXTENDED_HRS) AS TOTAL_STD_HRS
--     FROM   (<this query>) x
--     GROUP BY TOP_PART_ID
--
-- See siblings:
--   * recursive_bom_from_masters.sql
--   * recursive_bom_all_active_parts.sql
--   * recursive_routing_from_masters.sql
-- See memory:  veca_engineering_master_linkage, veca_requirement_status_codes
-- =========================================================================

DECLARE @Site          nvarchar(15) = 'TDJ';
DECLARE @MaxDepth      int          = 20;
DECLARE @OrderMinDate  datetime     = '2020-01-01';
DECLARE @MinOrderCount int          = 2;

;WITH top_parts AS
(
    SELECT   col.PART_ID
    FROM     CUST_ORDER_LINE col
    WHERE    col.STATUS_EFF_DATE > @OrderMinDate
      AND    col.PART_ID IS NOT NULL
      AND    col.PART_ID NOT IN ('repair-bg','rma repair')
    GROUP BY col.PART_ID
    HAVING   COUNT(*) >= @MinOrderCount
),
bom_asm AS
(
    -- ---- Anchor: level 0 = each top part itself ----
    SELECT
        top_psv.PART_ID                      AS TOP_PART_ID,
        0                                    AS BOM_LEVEL,
        top_psv.PART_ID                      AS ASSEMBLY_PART_ID,
        top_wo.TYPE                          AS WO_TYPE,
        top_wo.BASE_ID                       AS WO_BASE_ID,
        top_wo.LOT_ID                        AS WO_LOT_ID,
        top_wo.SPLIT_ID                      AS WO_SPLIT_ID,
        top_wo.SUB_ID                        AS WO_SUB_ID,
        CAST(1 AS decimal(28,8))             AS ASSEMBLY_QTY_PER_TOP,
        top_wo.DESIRED_QTY                   AS MASTER_DESIRED_QTY,
        CAST('/' + top_psv.PART_ID + '/' AS nvarchar(4000)) AS PATH
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

    UNION ALL

    -- ---- Recursive: walk REQ to reach each fabricated sub-assembly ----
    SELECT
        parent.TOP_PART_ID,
        parent.BOM_LEVEL + 1,
        child_wo.PART_ID,
        child_wo.TYPE,
        child_wo.BASE_ID,
        child_wo.LOT_ID,
        child_wo.SPLIT_ID,
        child_wo.SUB_ID,
        CAST(parent.ASSEMBLY_QTY_PER_TOP * (req.CALC_QTY / NULLIF(parent.MASTER_DESIRED_QTY, 0)) AS decimal(28,8)),
        child_wo.DESIRED_QTY,
        CAST(parent.PATH + req.PART_ID + '/' AS nvarchar(4000))
    FROM   bom_asm parent
    JOIN   REQUIREMENT req
           ON  req.WORKORDER_TYPE     = parent.WO_TYPE
           AND req.WORKORDER_BASE_ID  = parent.WO_BASE_ID
           AND req.WORKORDER_LOT_ID   = parent.WO_LOT_ID
           AND req.WORKORDER_SPLIT_ID = parent.WO_SPLIT_ID
           AND req.WORKORDER_SUB_ID   = parent.WO_SUB_ID
    JOIN   PART_SITE_VIEW child_psv
           ON  child_psv.PART_ID    = req.PART_ID
           AND child_psv.SITE_ID    = @Site
           AND child_psv.FABRICATED = 'Y'
    JOIN   WORK_ORDER child_wo
           ON  child_wo.TYPE     = 'M'
           AND child_wo.BASE_ID  = child_psv.PART_ID
           AND child_wo.LOT_ID   = CAST(child_psv.ENGINEERING_MSTR AS nvarchar(3))
           AND child_wo.SPLIT_ID = '0'
           AND child_wo.SUB_ID   = '0'
           AND child_wo.SITE_ID  = child_psv.SITE_ID
    WHERE  req.PART_ID IS NOT NULL
      AND  req.STATUS   = 'U'
      AND  parent.BOM_LEVEL < @MaxDepth
      AND  CHARINDEX('/' + req.PART_ID + '/', parent.PATH) = 0
)

-- =========================================================================
-- Final projection: one row per (top x assembly x op)
-- =========================================================================
SELECT
    asm.TOP_PART_ID,
    asm.BOM_LEVEL,
    asm.ASSEMBLY_PART_ID,
    asm.ASSEMBLY_QTY_PER_TOP,
    asm.PATH,

    op.SEQUENCE_NO,
    op.RESOURCE_ID,
    op.RUN_TYPE,
    op.RUN                                                    AS RUN_RATE,
    op.SETUP_HRS,
    op.RUN_HRS,
    op.MOVE_HRS,
    op.VENDOR_ID                                              AS OUTSIDE_VENDOR_ID,
    op.SERVICE_ID                                             AS OUTSIDE_SERVICE_ID,
    op.SETUP_COST_PER_HR,
    op.RUN_COST_PER_HR,
    op.BUR_PER_HR_SETUP,
    op.BUR_PER_HR_RUN,

    wo.DESIRED_QTY                                            AS MASTER_DESIRED_QTY,
    wo.STATUS                                                 AS WO_STATUS,
    wo.PRODUCT_CODE                                           AS WO_PRODUCT_CODE,
    wo.COMMODITY_CODE                                         AS WO_COMMODITY_CODE,
    wo.ENGINEERED_BY,
    wo.ENGINEERED_DATE,

    CAST(
        (ISNULL(op.SETUP_HRS,0) + ISNULL(op.RUN_HRS,0) + ISNULL(op.MOVE_HRS,0))
        / NULLIF(wo.DESIRED_QTY, 0)
    AS decimal(18,6)) AS HRS_PER_PIECE,

    CAST(ISNULL(op.SETUP_HRS,0) / NULLIF(wo.DESIRED_QTY, 0) AS decimal(18,6)) AS SETUP_HRS_PER_PIECE,
    CAST(ISNULL(op.RUN_HRS,0)   / NULLIF(wo.DESIRED_QTY, 0) AS decimal(18,6)) AS RUN_HRS_PER_PIECE,
    CAST(ISNULL(op.MOVE_HRS,0)  / NULLIF(wo.DESIRED_QTY, 0) AS decimal(18,6)) AS MOVE_HRS_PER_PIECE,

    CAST(
        (ISNULL(op.SETUP_HRS,0) + ISNULL(op.RUN_HRS,0) + ISNULL(op.MOVE_HRS,0))
        / NULLIF(wo.DESIRED_QTY, 0)
        * asm.ASSEMBLY_QTY_PER_TOP
    AS decimal(18,6)) AS EXTENDED_HRS,

    CAST(
        (ISNULL(op.SETUP_HRS,0)
         + (ISNULL(op.RUN_HRS,0) + ISNULL(op.MOVE_HRS,0))
             / NULLIF(wo.DESIRED_QTY, 0)
             * asm.ASSEMBLY_QTY_PER_TOP)
    AS decimal(18,6)) AS EXTENDED_HRS_SETUP_ONCE,

    psv.DESCRIPTION       AS ASSEMBLY_DESCRIPTION,
    psv.PRODUCT_CODE      AS PSV_PRODUCT_CODE,
    psv.PLANNING_LEADTIME,
    psv.UNIT_MATERIAL_COST,
    psv.UNIT_LABOR_COST,
    psv.UNIT_BURDEN_COST
FROM   bom_asm asm
LEFT JOIN OPERATION op
       ON  op.WORKORDER_TYPE     = asm.WO_TYPE
       AND op.WORKORDER_BASE_ID  = asm.WO_BASE_ID
       AND op.WORKORDER_LOT_ID   = asm.WO_LOT_ID
       AND op.WORKORDER_SPLIT_ID = asm.WO_SPLIT_ID
       AND op.WORKORDER_SUB_ID   = asm.WO_SUB_ID
LEFT JOIN WORK_ORDER wo
       ON  wo.TYPE     = asm.WO_TYPE
       AND wo.BASE_ID  = asm.WO_BASE_ID
       AND wo.LOT_ID   = asm.WO_LOT_ID
       AND wo.SPLIT_ID = asm.WO_SPLIT_ID
       AND wo.SUB_ID   = asm.WO_SUB_ID
       AND wo.SITE_ID  = @Site
LEFT JOIN PART_SITE_VIEW psv
       ON  psv.PART_ID = asm.ASSEMBLY_PART_ID
       AND psv.SITE_ID = @Site
ORDER BY asm.TOP_PART_ID, asm.PATH, op.SEQUENCE_NO
OPTION (MAXRECURSION 0);
