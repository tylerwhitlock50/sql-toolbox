/*
===============================================================================
Query Name: supplemental_supply.sql

Purpose:
    Returns a unified, time-phased view of incoming supply and material
    requirements, used by the shaped-snapshot supplemental-supply layer to
    compute effective on-hand alongside the base inventory snapshot.

Business Use:
    The base inventory snapshot is a single point-in-time on-hand snapshot.
    Real planning needs to see incoming work orders, incoming purchase
    orders, and the requirements those work orders consume. This query
    returns all three, signed appropriately, so the solver can net them
    against on-hand inventory.

Output Contract:
    One row per supply / requirement event. Required columns:

        supply_type      'WORK_ORDER' | 'PURCHASE_ORDER' | 'REQUIREMENT'
        part_id          planning part id; matches snapshot_inventory.part_id
        qty              SIGNED. Positive for WORK_ORDER and PURCHASE_ORDER;
                         negative for REQUIREMENT (it consumes inventory).
        want_date        planning / need date
        reference        WO key string / PO number / requirement parent WO key
        line_no          PO line for PURCHASE_ORDER (unique within reference);
                         requirement PIECE_NO for REQUIREMENT;
                         1 for WORK_ORDER (one row per WO header).
        supplier_id      VENDOR_ID for PURCHASE_ORDER; null otherwise
        status           source-defined status (WO/PO/REQ status code)
        promise_date     supplier promise (PO), scheduled finish (WO),
                         requirement need (REQ)
        linked_reference REQUIREMENT only: the parent WO key
        warehouse_id     target / consuming warehouse
        unit_cost        cost per unit; nullable

    Notes:
    - All three branches are returned via UNION ALL.
    - REQUIREMENT.qty is NEGATIVE. Do not sign-flip downstream.
    - PURCHASE_ORDER (reference, line_no) = (PURCHASE_ORDER.ID,
      PURC_ORDER_LINE.LINE_NO) — guaranteed unique by VECA's PK.
    - Filter is "open / unconsumed" — closed PO/WO and issued requirements
      are already reflected in the inventory snapshot.

VECA schema notes (verified):
    - WO header is WORK_ORDER. 5-part composite key:
      (TYPE, BASE_ID, LOT_ID, SPLIT_ID, SUB_ID). TYPE='W' for production;
      TYPE='M' is engineering master (excluded).
    - WO requirement child is REQUIREMENT, joined on all 5 WO key parts.
      Open / unissued requirements have STATUS='U'. Use CALC_QTY (per-WO
      total) minus ISSUED_QTY for the remaining open material qty.
    - PO header is PURCHASE_ORDER, line is PURC_ORDER_LINE
      (joined on PURC_ORDER_ID = PURCHASE_ORDER.ID). Open qty is
      ORDER_QTY - TOTAL_RECEIVED_QTY.
    - Open status filter: NOT IN ('X','C')  -- canonical for both WO and PO.
      ('X' cancelled, 'C' closed; F=firm, R=released, U=unfirmed.)
    - Site scoping: WO/PO have SITE_ID directly; REQUIREMENT inherits via
      its parent WO.

Parameters:
    @Site   nvarchar(15)   site filter; NULL = all sites
===============================================================================
*/

DECLARE @Site nvarchar(15) = NULL;

------------------------------------------------------------------------------
-- WORK_ORDER: incoming finished assemblies (positive qty)
-- One row per open production WO.
------------------------------------------------------------------------------
SELECT
    CAST('WORK_ORDER' AS varchar(20))                                AS supply_type,
    wo.PART_ID                                                       AS part_id,
    CAST(wo.DESIRED_QTY - ISNULL(wo.RECEIVED_QTY, 0) AS float)       AS qty,
    COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE)             AS want_date,
    CAST(wo.TYPE + '-' + wo.BASE_ID + '/' + wo.LOT_ID
         + '/' + wo.SPLIT_ID + '/' + wo.SUB_ID AS nvarchar(50))      AS reference,
    CAST(1 AS int)                                                   AS line_no,
    CAST(NULL AS nvarchar(15))                                       AS supplier_id,
    wo.STATUS                                                        AS status,
    wo.SCHED_FINISH_DATE                                             AS promise_date,
    CAST(NULL AS nvarchar(50))                                       AS linked_reference,
    wo.WAREHOUSE_ID                                                  AS warehouse_id,
    CAST(NULL AS float)                                              AS unit_cost
FROM WORK_ORDER wo
WHERE wo.TYPE = 'W'                                  -- production WOs only (exclude masters)
  AND ISNULL(wo.STATUS, '') IN ('F','R')             -- firm or released
  AND wo.DESIRED_QTY - ISNULL(wo.RECEIVED_QTY, 0) > 0
  AND wo.PART_ID IS NOT NULL
  AND (@Site IS NULL OR wo.SITE_ID = @Site)

UNION ALL

------------------------------------------------------------------------------
-- REQUIREMENT: materials consumed by the WOs above (NEGATIVE qty).
-- One row per (work order, operation, piece). Joined on the full 5-part WO
-- key. CALC_QTY is the per-WO total requirement (already multiplied by
-- DESIRED_QTY); ISSUED_QTY is what's already been pulled.
------------------------------------------------------------------------------
SELECT
    CAST('REQUIREMENT' AS varchar(20))                                  AS supply_type,
    r.PART_ID                                                           AS part_id,
    -1.0 * CAST(r.CALC_QTY - ISNULL(r.ISSUED_QTY, 0) AS float)          AS qty,
    COALESCE(r.REQUIRED_DATE, wo.SCHED_START_DATE)                      AS want_date,
    CAST(wo.TYPE + '-' + wo.BASE_ID + '/' + wo.LOT_ID
         + '/' + wo.SPLIT_ID + '/' + wo.SUB_ID AS nvarchar(50))         AS reference,
    CAST(r.PIECE_NO AS int)                                             AS line_no,
    CAST(NULL AS nvarchar(15))                                          AS supplier_id,
    wo.STATUS                                                           AS status,
    COALESCE(r.REQUIRED_DATE, wo.SCHED_START_DATE)                      AS promise_date,
    CAST(wo.TYPE + '-' + wo.BASE_ID + '/' + wo.LOT_ID
         + '/' + wo.SPLIT_ID + '/' + wo.SUB_ID AS nvarchar(50))         AS linked_reference,
    r.WAREHOUSE_ID                                                      AS warehouse_id,
    CAST(r.UNIT_MATERIAL_COST AS float)                                 AS unit_cost
FROM REQUIREMENT r
INNER JOIN WORK_ORDER wo
    ON  wo.TYPE     = r.WORKORDER_TYPE
    AND wo.BASE_ID  = r.WORKORDER_BASE_ID
    AND wo.LOT_ID   = r.WORKORDER_LOT_ID
    AND wo.SPLIT_ID = r.WORKORDER_SPLIT_ID
    AND wo.SUB_ID   = r.WORKORDER_SUB_ID
WHERE wo.TYPE = 'W'
  AND ISNULL(wo.STATUS, '') IN ('F','R')
  AND ISNULL(r.STATUS, '')  = 'R'                    -- unissued = open requirement
  AND r.CALC_QTY - ISNULL(r.ISSUED_QTY, 0) > 0
  AND r.PART_ID IS NOT NULL
  AND (@Site IS NULL OR wo.SITE_ID = @Site)

UNION ALL

------------------------------------------------------------------------------
-- PURCHASE_ORDER: incoming buys (positive qty).
-- One row per open PO line. (reference, line_no) = (PO.ID, LINE_NO) is
-- unique by PURC_ORDER_LINE PK and is the override-matching key.
------------------------------------------------------------------------------
SELECT
    CAST('PURCHASE_ORDER' AS varchar(20))                                                AS supply_type,
    pl.PART_ID                                                                           AS part_id,
    CAST(pl.ORDER_QTY - ISNULL(pl.TOTAL_RECEIVED_QTY, 0) AS float)                       AS qty,
    COALESCE(pl.DESIRED_RECV_DATE, pl.PROMISE_DATE,
             p.DESIRED_RECV_DATE,  p.PROMISE_DATE)                                       AS want_date,
    CAST(p.ID AS nvarchar(50))                                                           AS reference,
    CAST(pl.LINE_NO AS int)                                                              AS line_no,
    p.VENDOR_ID                                                                          AS supplier_id,
    p.STATUS                                                                             AS status,
    COALESCE(pl.PROMISE_DATE, p.PROMISE_DATE)                                            AS promise_date,
    CAST(NULL AS nvarchar(50))                                                           AS linked_reference,
    pl.WAREHOUSE_ID                                                                      AS warehouse_id,
    CAST(pl.UNIT_PRICE AS float)                                                         AS unit_cost
FROM PURCHASE_ORDER p
INNER JOIN PURC_ORDER_LINE pl
    ON pl.PURC_ORDER_ID = p.ID
WHERE ISNULL(p.STATUS, '')        NOT IN ('X','C')   -- exclude cancelled / closed
  AND ISNULL(pl.LINE_STATUS, '')  NOT IN ('X','C')
  AND pl.ORDER_QTY - ISNULL(pl.TOTAL_RECEIVED_QTY, 0) > 0
  AND pl.PART_ID IS NOT NULL
  AND (@Site IS NULL OR p.SITE_ID = @Site)
;
