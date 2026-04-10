-- =========================================================================
-- Recursive routing (OPERATION) explosion from engineering masters (VECA)
-- =========================================================================
-- Companion to recursive_bom_from_masters.sql. Same walk logic — recurse
-- through REQUIREMENT into any fabricated-with-master sub-assembly — but
-- at each assembly we emit its OPERATION rows instead of the REQ rows,
-- and compute the standard hours required to build ONE of the top part.
--
-- Row shape:
--   One row per (assembly reached) x (operation step on that assembly).
--   Level 0 rows = operations on the top part's own master
--   Level N>0    = operations on a sub-assembly's master, scaled by the
--                  cumulative qty of that sub-assembly needed per top part
--
-- Hour normalization:
--   Setup and run on a master WO are stored for the master's DESIRED_QTY.
--   Per-piece hours      = (SETUP_HRS + RUN_HRS + MOVE_HRS) / DESIRED_QTY
--   Extended-per-top     = per-piece * ASSEMBLY_QTY_PER_TOP
--   Sum EXTENDED_HRS     across all rows for a TOP_PART_ID to get the
--                        full standard labor time to build 1 finished good.
--
-- Notes:
--   * Assumes setup is amortized per piece (typical cost-roll convention).
--     If you'd rather charge setup once per sub-assembly regardless of qty,
--     see the SETUP_HRS_ALT column and swap EXTENDED_HRS accordingly.
--   * Outside services (RUN_TYPE carries a non-hours unit) will still
--     get a RUN_HRS value from VISUAL — trust it. Vendor/service rows
--     surface via OP.VENDOR_ID / OP.SERVICE_ID.
--
-- See sibling: recursive_bom_from_masters.sql
-- See memory:  veca_engineering_master_linkage, veca_requirement_status_codes
-- =========================================================================

DECLARE @TopPart  nvarchar(30) = '801-09003-01';
DECLARE @Site     nvarchar(15) = 'TDJ';
DECLARE @MaxDepth int          = 20;

;WITH bom_asm AS
(
    -- ---- Anchor: level 0 = the top part itself, 1 needed per top part ----
    SELECT
        0                                    AS BOM_LEVEL,
        top_psv.PART_ID                      AS ASSEMBLY_PART_ID,
        top_wo.TYPE                          AS WO_TYPE,
        top_wo.BASE_ID                       AS WO_BASE_ID,
        top_wo.LOT_ID                        AS WO_LOT_ID,
        top_wo.SPLIT_ID                      AS WO_SPLIT_ID,
        top_wo.SUB_ID                        AS WO_SUB_ID,
        CAST(1 AS decimal(28,8))             AS ASSEMBLY_QTY_PER_TOP,
        CAST('/' + top_psv.PART_ID + '/' AS nvarchar(4000)) AS PATH
    FROM   PART_SITE_VIEW top_psv
    JOIN   WORK_ORDER     top_wo
           ON  top_wo.TYPE     = 'M'
           AND top_wo.BASE_ID  = top_psv.PART_ID
           AND top_wo.LOT_ID   = CAST(top_psv.ENGINEERING_MSTR AS nvarchar(3))
           AND top_wo.SPLIT_ID = '0'
           AND top_wo.SUB_ID   = '0'
           AND top_wo.SITE_ID  = top_psv.SITE_ID
    WHERE  top_psv.PART_ID = @TopPart
      AND  top_psv.SITE_ID = @Site

    UNION ALL

    -- ---- Recursive: walk REQUIREMENT to reach fabricated sub-assemblies ----
    SELECT
        parent.BOM_LEVEL + 1,
        child_wo.PART_ID                                               AS ASSEMBLY_PART_ID,
        child_wo.TYPE,
        child_wo.BASE_ID,
        child_wo.LOT_ID,
        child_wo.SPLIT_ID,
        child_wo.SUB_ID,
        CAST(parent.ASSEMBLY_QTY_PER_TOP * req.CALC_QTY AS decimal(28,8)),
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
      AND  req.STATUS   = 'U'                              -- current master REQ
      AND  parent.BOM_LEVEL < @MaxDepth
      AND  CHARINDEX('/' + req.PART_ID + '/', parent.PATH) = 0   -- cycle guard
)

-- =========================================================================
-- Final projection: one row per (assembly visited) x (operation step)
-- =========================================================================
SELECT
    asm.BOM_LEVEL,
    asm.ASSEMBLY_PART_ID,
    asm.ASSEMBLY_QTY_PER_TOP,
    asm.PATH,

    -- ---- OPERATION fields ----
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

    -- ---- Master WO context ----
    wo.DESIRED_QTY                                            AS MASTER_DESIRED_QTY,
    wo.STATUS                                                 AS WO_STATUS,
    wo.PRODUCT_CODE                                           AS WO_PRODUCT_CODE,
    wo.COMMODITY_CODE                                         AS WO_COMMODITY_CODE,
    wo.ENGINEERED_BY,
    wo.ENGINEERED_DATE,

    -- ---- Hours normalized per piece and extended to 1 top part ----
    -- Per-piece = (setup + run + move) / master desired qty
    CAST(
        (ISNULL(op.SETUP_HRS,0) + ISNULL(op.RUN_HRS,0) + ISNULL(op.MOVE_HRS,0))
        / NULLIF(wo.DESIRED_QTY, 0)
    AS decimal(18,6)) AS HRS_PER_PIECE,

    CAST(ISNULL(op.SETUP_HRS,0) / NULLIF(wo.DESIRED_QTY, 0) AS decimal(18,6)) AS SETUP_HRS_PER_PIECE,
    CAST(ISNULL(op.RUN_HRS,0)   / NULLIF(wo.DESIRED_QTY, 0) AS decimal(18,6)) AS RUN_HRS_PER_PIECE,
    CAST(ISNULL(op.MOVE_HRS,0)  / NULLIF(wo.DESIRED_QTY, 0) AS decimal(18,6)) AS MOVE_HRS_PER_PIECE,

    -- Extended to 1 top part = per-piece * assembly qty-per-top
    CAST(
        (ISNULL(op.SETUP_HRS,0) + ISNULL(op.RUN_HRS,0) + ISNULL(op.MOVE_HRS,0))
        / NULLIF(wo.DESIRED_QTY, 0)
        * asm.ASSEMBLY_QTY_PER_TOP
    AS decimal(18,6)) AS EXTENDED_HRS,

    -- Alternative: setup charged once regardless of qty, run amortized
    CAST(
        (ISNULL(op.SETUP_HRS,0)
         + (ISNULL(op.RUN_HRS,0) + ISNULL(op.MOVE_HRS,0))
             / NULLIF(wo.DESIRED_QTY, 0)
             * asm.ASSEMBLY_QTY_PER_TOP)
    AS decimal(18,6)) AS EXTENDED_HRS_SETUP_ONCE,

    -- ---- PART_SITE_VIEW on the assembly ----
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
ORDER BY asm.PATH, op.SEQUENCE_NO
OPTION (MAXRECURSION 0);
