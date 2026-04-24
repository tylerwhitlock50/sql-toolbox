/*
===============================================================================
Query Name: open_wo_aging_and_wip.sql

Purpose:
    Snapshot of all open work orders, aged by how far past their desired
    want date they are, with WIP value and linkage back to any open
    customer-order demand driving them.

    Intended as the daily / weekly "what's behind on the floor" report
    for the production manager.

Grain:
    One row per open work order (5-part WO key).
    Open = STATUS in ('F','R')  -- Firmed or Released.
    (Canonical "active" for VECA WOs is F or R; U is not-yet-planned,
     C is closed, X is cancelled.)

Aging buckets (days past @AsOfDate vs DESIRED_WANT_DATE):
    NOT_DUE
    0-7
    8-14
    15-30
    31-60
    61+

Key columns:
    remaining_qty
        DESIRED_QTY - RECEIVED_QTY (the qty still to complete).

    wip_value_actual
        ACT_MATERIAL_COST + ACT_LABOR_COST + ACT_BURDEN_COST + ACT_SERVICE_COST
        minus cost of qty already received (approximated using the part's
        standard cost on PART_SITE_VIEW). This is a rough WIP balance,
        not a ledger WIP — use for operational insight, not GL close.

    rem_cost_total
        REM_MATERIAL_COST + REM_LABOR_COST + REM_BURDEN_COST + REM_SERVICE_COST
        straight from WORK_ORDER. VISUAL's own view of cost still to post.

    pct_received
        RECEIVED_QTY / DESIRED_QTY * 100.

    linked_so_value
        Open SO $ for the WO's PART_ID at the same site (direct match
        only; does not walk BOM upward).

Notes / Assumptions:
    - Master records (TYPE='M') are excluded; they are templates, not
      production WOs.
    - WIP value is approximate (see above). For audit WIP, query
      WIP_BALANCE.
    - Linked SO uses the canonical open-SO definition
      (STATUS IN ('R','F') / LINE_STATUS = 'A').

Potential Enhancements:
    - Use WBS_CUST_ORDER_ID on WO to pull the specific SO the WO
      references, when populated
    - Add count of open operations and next operation resource
    - Add overdue material flag (any open requirement behind schedule)
===============================================================================
*/

DECLARE @Site     nvarchar(15) = NULL;
DECLARE @AsOfDate datetime     = GETDATE();

;WITH open_wo AS (
    SELECT
        wo.SITE_ID,
        wo.TYPE, wo.BASE_ID, wo.LOT_ID, wo.SPLIT_ID, wo.SUB_ID,
        wo.PART_ID,
        wo.PRODUCT_CODE,
        wo.COMMODITY_CODE,
        wo.WAREHOUSE_ID,
        wo.STATUS,
        wo.CREATE_DATE,
        wo.DESIRED_RLS_DATE,
        wo.DESIRED_WANT_DATE,
        wo.SCHED_START_DATE,
        wo.SCHED_FINISH_DATE,
        wo.DESIRED_QTY,
        wo.RECEIVED_QTY,
        (wo.DESIRED_QTY - wo.RECEIVED_QTY)                        AS remaining_qty,
        (wo.ACT_MATERIAL_COST + wo.ACT_LABOR_COST
         + wo.ACT_BURDEN_COST + wo.ACT_SERVICE_COST)              AS act_total_cost,
        (wo.REM_MATERIAL_COST + wo.REM_LABOR_COST
         + wo.REM_BURDEN_COST + wo.REM_SERVICE_COST)              AS rem_cost_total,
        (wo.EST_MATERIAL_COST + wo.EST_LABOR_COST
         + wo.EST_BURDEN_COST + wo.EST_SERVICE_COST)              AS est_total_cost,
        wo.WBS_CUST_ORDER_ID
    FROM WORK_ORDER wo
    WHERE wo.STATUS IN ('F','R')
      AND wo.TYPE <> 'M'
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
),

op_summary AS (
    SELECT
        o.WORKORDER_TYPE,     o.WORKORDER_BASE_ID,
        o.WORKORDER_LOT_ID,   o.WORKORDER_SPLIT_ID,
        o.WORKORDER_SUB_ID,
        COUNT(*)                                                  AS total_ops,
        SUM(CASE WHEN o.STATUS = 'C' THEN 1 ELSE 0 END)           AS closed_ops,
        SUM(CASE WHEN o.STATUS IN ('F','R') THEN 1 ELSE 0 END)    AS open_ops,
        MIN(CASE WHEN o.STATUS IN ('F','R') THEN o.SEQUENCE_NO END) AS next_open_seq
    FROM OPERATION o
    GROUP BY
        o.WORKORDER_TYPE,  o.WORKORDER_BASE_ID,
        o.WORKORDER_LOT_ID,o.WORKORDER_SPLIT_ID,
        o.WORKORDER_SUB_ID
),

next_op AS (
    SELECT
        o.WORKORDER_TYPE,     o.WORKORDER_BASE_ID,
        o.WORKORDER_LOT_ID,   o.WORKORDER_SPLIT_ID,
        o.WORKORDER_SUB_ID,
        o.SEQUENCE_NO,
        o.RESOURCE_ID,
        o.SCHED_START_DATE,
        o.SCHED_FINISH_DATE
    FROM OPERATION o
),

-- Direct linkage to open SOs for the WO's part (canonical open filter)
linked_so AS (
    SELECT
        col.SITE_ID,
        col.PART_ID,
        SUM(col.ORDER_QTY - col.TOTAL_SHIPPED_QTY)                    AS linked_so_open_qty,
        SUM((col.ORDER_QTY - col.TOTAL_SHIPPED_QTY) * col.UNIT_PRICE
             * (100.0 - COALESCE(col.TRADE_DISC_PERCENT, 0)) / 100.0) AS linked_so_value,
        MIN(col.PROMISE_DATE)                                         AS earliest_so_promise
    FROM CUST_ORDER_LINE col
    INNER JOIN CUSTOMER_ORDER co
        ON co.ID = col.CUST_ORDER_ID
    WHERE co.STATUS IN ('R','F')
      AND col.LINE_STATUS = 'A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
    GROUP BY col.SITE_ID, col.PART_ID
)

SELECT
    w.SITE_ID,
    w.TYPE + '-' + w.BASE_ID + '/' + w.LOT_ID + '/' + w.SPLIT_ID + '/' + w.SUB_ID AS wo_key,
    w.TYPE, w.BASE_ID, w.LOT_ID, w.SPLIT_ID, w.SUB_ID,
    w.STATUS,
    w.PART_ID,
    psv.DESCRIPTION                                          AS part_description,
    w.PRODUCT_CODE,
    w.COMMODITY_CODE,
    w.WAREHOUSE_ID,
    w.WBS_CUST_ORDER_ID,

    w.DESIRED_QTY,
    w.RECEIVED_QTY,
    w.remaining_qty,
    CAST(100.0 * w.RECEIVED_QTY / NULLIF(w.DESIRED_QTY, 0)
         AS decimal(7,2))                                    AS pct_received,

    -- Dates + aging
    w.CREATE_DATE,
    w.DESIRED_RLS_DATE,
    w.DESIRED_WANT_DATE,
    w.SCHED_START_DATE,
    w.SCHED_FINISH_DATE,
    DATEDIFF(day, w.DESIRED_WANT_DATE, @AsOfDate)            AS days_past_want,
    CASE
        WHEN w.DESIRED_WANT_DATE IS NULL                                 THEN 'NO_TARGET'
        WHEN w.DESIRED_WANT_DATE >= @AsOfDate                            THEN 'NOT_DUE'
        WHEN DATEDIFF(day, w.DESIRED_WANT_DATE, @AsOfDate) BETWEEN 1  AND  7 THEN '0-7'
        WHEN DATEDIFF(day, w.DESIRED_WANT_DATE, @AsOfDate) BETWEEN 8  AND 14 THEN '8-14'
        WHEN DATEDIFF(day, w.DESIRED_WANT_DATE, @AsOfDate) BETWEEN 15 AND 30 THEN '15-30'
        WHEN DATEDIFF(day, w.DESIRED_WANT_DATE, @AsOfDate) BETWEEN 31 AND 60 THEN '31-60'
        ELSE                                                                 '61+'
    END                                                       AS aging_bucket,

    -- Cost + WIP
    w.est_total_cost,
    w.act_total_cost,
    w.rem_cost_total,
    -- Rough WIP: actuals booked to WO minus value of qty already received
    -- (approximated at part's current standard cost). Can go negative on
    -- yield-favourable WOs.
    CAST(
        w.act_total_cost
        - w.RECEIVED_QTY * (psv.UNIT_MATERIAL_COST
                          + psv.UNIT_LABOR_COST
                          + psv.UNIT_BURDEN_COST
                          + psv.UNIT_SERVICE_COST)
        AS decimal(23,2))                                    AS wip_value_approx,

    -- Ops snapshot
    COALESCE(os.total_ops, 0)                                AS total_ops,
    COALESCE(os.closed_ops, 0)                               AS closed_ops,
    COALESCE(os.open_ops, 0)                                 AS open_ops,
    no_op.SEQUENCE_NO                                        AS next_open_op_seq,
    no_op.RESOURCE_ID                                        AS next_open_op_resource,
    no_op.SCHED_START_DATE                                   AS next_open_op_sched_start,

    -- SO linkage
    COALESCE(ls.linked_so_open_qty, 0)                       AS linked_so_open_qty,
    COALESCE(ls.linked_so_value, 0)                          AS linked_so_value,
    ls.earliest_so_promise,

    CASE
        WHEN w.DESIRED_WANT_DATE < @AsOfDate
         AND COALESCE(ls.linked_so_value, 0) > 0            THEN 'P1 - late, SO demand'
        WHEN w.DESIRED_WANT_DATE < @AsOfDate                THEN 'P2 - late'
        WHEN COALESCE(ls.linked_so_value, 0) > 0            THEN 'P3 - SO demand'
        ELSE                                                     'P4 - normal'
    END                                                      AS priority
FROM open_wo w
LEFT JOIN PART_SITE_VIEW psv
    ON psv.SITE_ID = w.SITE_ID
   AND psv.PART_ID = w.PART_ID
LEFT JOIN op_summary os
    ON os.WORKORDER_TYPE     = w.TYPE
   AND os.WORKORDER_BASE_ID  = w.BASE_ID
   AND os.WORKORDER_LOT_ID   = w.LOT_ID
   AND os.WORKORDER_SPLIT_ID = w.SPLIT_ID
   AND os.WORKORDER_SUB_ID   = w.SUB_ID
LEFT JOIN next_op no_op
    ON no_op.WORKORDER_TYPE     = w.TYPE
   AND no_op.WORKORDER_BASE_ID  = w.BASE_ID
   AND no_op.WORKORDER_LOT_ID   = w.LOT_ID
   AND no_op.WORKORDER_SPLIT_ID = w.SPLIT_ID
   AND no_op.WORKORDER_SUB_ID   = w.SUB_ID
   AND no_op.SEQUENCE_NO        = os.next_open_seq
LEFT JOIN linked_so ls
    ON ls.SITE_ID = w.SITE_ID
   AND ls.PART_ID = w.PART_ID
ORDER BY
    CASE
        WHEN w.DESIRED_WANT_DATE IS NULL                           THEN 6
        WHEN DATEDIFF(day, w.DESIRED_WANT_DATE, @AsOfDate) > 60    THEN 1
        WHEN DATEDIFF(day, w.DESIRED_WANT_DATE, @AsOfDate) > 30    THEN 2
        WHEN DATEDIFF(day, w.DESIRED_WANT_DATE, @AsOfDate) > 14    THEN 3
        WHEN DATEDIFF(day, w.DESIRED_WANT_DATE, @AsOfDate) > 0     THEN 4
        ELSE                                                            5
    END,
    w.rem_cost_total DESC;
