/*
===============================================================================
Query Name: schedule_health_by_operation.sql

Purpose:
    Per-operation view of open work-order progress. Flags operations that
    are behind schedule and estimates whether each open op can finish
    before the work order's want date.

    Answers:
        * "Which operations are late vs their scheduled finish?"
        * "How many remaining hours are needed across the shop at each
          work center?"
        * "Which WOs are at risk of slipping based on remaining work vs
          calendar time to want date?"

Grain:
    One row per open operation on an open work order.
    Open op = STATUS in ('F','R'), on a WO with STATUS in ('F','R').

Key calculations:
    rem_std_hrs
        (SETUP_HRS + RUN_HRS) - (ACT_SETUP_HRS + ACT_RUN_HRS),
        floored at zero. Remaining engineered hours to complete the op.

    days_past_sched_finish
        DATEDIFF(day, SCHED_FINISH_DATE, @AsOfDate).

    calendar_days_to_want
        DATEDIFF(day, @AsOfDate, WO.DESIRED_WANT_DATE).

    load_risk
        Rough indicator of whether there's enough calendar time left
        to burn off remaining hours at one shift. Heuristic only.

Notes / Assumptions:
    - "Remaining hours" uses engineered standard (SETUP + RUN). Past-due
      operations that are still active with 0 remaining hours are usually
      operations that have run over standard and still haven't been
      closed.
    - SCHED_FINISH_DATE is populated by the scheduler (SRP). If scheduling
      hasn't been run recently these dates may be stale.
    - Setup completion is tracked on OPERATION.SETUP_COMPLETED ('Y'/'N').
    - Does not compute utilization vs capacity (use SHOP_RESOURCE_SITE
      capacity columns + OPERATION_SCHED for that).

Potential Enhancements:
    - Join OPERATION_SCHED for shift-level scheduled detail
    - Join to WBS_CUST_ORDER_ID on WO to show SO value at risk
    - Add material availability per op via REQUIREMENT join (STATUS='U')
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
        wo.STATUS                                  AS wo_status,
        wo.DESIRED_QTY,
        wo.RECEIVED_QTY,
        wo.DESIRED_RLS_DATE,
        wo.DESIRED_WANT_DATE,
        wo.SCHED_START_DATE                        AS wo_sched_start,
        wo.SCHED_FINISH_DATE                       AS wo_sched_finish,
        (wo.REM_MATERIAL_COST + wo.REM_LABOR_COST
         + wo.REM_BURDEN_COST + wo.REM_SERVICE_COST) AS wo_rem_cost
    FROM WORK_ORDER wo
    WHERE wo.STATUS IN ('F','R')
      AND wo.TYPE <> 'M'
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
),

open_ops AS (
    SELECT
        w.SITE_ID,
        w.TYPE, w.BASE_ID, w.LOT_ID, w.SPLIT_ID, w.SUB_ID,
        w.PART_ID, w.PRODUCT_CODE,
        w.wo_status, w.DESIRED_QTY, w.RECEIVED_QTY,
        w.DESIRED_RLS_DATE, w.DESIRED_WANT_DATE,
        w.wo_sched_start, w.wo_sched_finish, w.wo_rem_cost,

        o.SEQUENCE_NO,
        o.RESOURCE_ID,
        o.STATUS                                        AS op_status,
        o.SETUP_COMPLETED,
        o.COMPLETED_QTY,
        o.DEVIATED_QTY,
        COALESCE(o.SETUP_HRS, 0)                        AS std_setup_hrs,
        COALESCE(o.RUN_HRS, 0)                          AS std_run_hrs,
        COALESCE(o.ACT_SETUP_HRS, 0)                    AS act_setup_hrs,
        COALESCE(o.ACT_RUN_HRS, 0)                      AS act_run_hrs,
        o.SCHED_START_DATE                              AS op_sched_start,
        o.SCHED_FINISH_DATE                             AS op_sched_finish,
        (COALESCE(o.REM_ATL_LAB_COST, 0)
         + COALESCE(o.REM_ATL_BUR_COST, 0)
         + COALESCE(o.REM_ATL_SER_COST, 0))              AS op_rem_cost,
        -- Floor at zero; if actual already exceeds standard, no more
        -- engineered hours remain even though the op is still open.
        CASE
            WHEN (COALESCE(o.SETUP_HRS, 0) + COALESCE(o.RUN_HRS, 0))
                 - (COALESCE(o.ACT_SETUP_HRS, 0) + COALESCE(o.ACT_RUN_HRS, 0)) < 0
            THEN 0
            ELSE (COALESCE(o.SETUP_HRS, 0) + COALESCE(o.RUN_HRS, 0))
                 - (COALESCE(o.ACT_SETUP_HRS, 0) + COALESCE(o.ACT_RUN_HRS, 0))
        END                                              AS rem_std_hrs
    FROM open_wo w
    INNER JOIN OPERATION o
        ON o.WORKORDER_TYPE     = w.TYPE
       AND o.WORKORDER_BASE_ID  = w.BASE_ID
       AND o.WORKORDER_LOT_ID   = w.LOT_ID
       AND o.WORKORDER_SPLIT_ID = w.SPLIT_ID
       AND o.WORKORDER_SUB_ID   = w.SUB_ID
    WHERE o.STATUS IN ('F','R')
)

SELECT
    op.SITE_ID,
    op.TYPE + '-' + op.BASE_ID + '/' + op.LOT_ID + '/' + op.SPLIT_ID + '/' + op.SUB_ID AS wo_key,
    op.SEQUENCE_NO,
    op.RESOURCE_ID,
    sr.DESCRIPTION                                      AS resource_description,
    sr.DEPARTMENT_ID,

    op.PART_ID,
    psv.DESCRIPTION                                     AS part_description,
    op.PRODUCT_CODE,

    op.wo_status,
    op.op_status,
    op.SETUP_COMPLETED,

    op.DESIRED_QTY,
    op.RECEIVED_QTY,
    op.COMPLETED_QTY                                    AS op_completed_qty,
    op.DEVIATED_QTY                                     AS op_deviated_qty,

    -- Dates
    op.DESIRED_RLS_DATE,
    op.DESIRED_WANT_DATE,
    op.op_sched_start,
    op.op_sched_finish,

    DATEDIFF(day, op.op_sched_finish, @AsOfDate)        AS days_past_op_sched_finish,
    DATEDIFF(day, @AsOfDate, op.DESIRED_WANT_DATE)      AS calendar_days_to_want,

    -- Hours
    CAST(op.std_setup_hrs AS decimal(14,2))             AS std_setup_hrs,
    CAST(op.std_run_hrs   AS decimal(14,2))             AS std_run_hrs,
    CAST(op.act_setup_hrs AS decimal(14,2))             AS act_setup_hrs,
    CAST(op.act_run_hrs   AS decimal(14,2))             AS act_run_hrs,
    CAST(op.rem_std_hrs   AS decimal(14,2))             AS rem_std_hrs,

    op.op_rem_cost,
    op.wo_rem_cost,

    -- Schedule-health flags
    CASE
        WHEN op.op_sched_finish IS NULL                                           THEN 'UNSCHEDULED'
        WHEN op.op_sched_finish <  @AsOfDate AND op.COMPLETED_QTY < op.DESIRED_QTY THEN 'PAST_DUE'
        WHEN op.op_sched_finish <= DATEADD(day, 3, @AsOfDate)
             AND op.SETUP_COMPLETED = 'N'                                          THEN 'STARTING_SOON'
        WHEN op.op_sched_finish <= DATEADD(day, 7, @AsOfDate)                      THEN 'DUE_THIS_WEEK'
        ELSE                                                                           'ON_SCHEDULE'
    END                                                 AS op_schedule_status,

    -- Can it physically fit before want date? (1 shift of ~8 hrs/day)
    CASE
        WHEN op.DESIRED_WANT_DATE IS NULL                                      THEN NULL
        WHEN op.DESIRED_WANT_DATE < @AsOfDate                                  THEN 'WO_ALREADY_LATE'
        WHEN op.rem_std_hrs <= DATEDIFF(day, @AsOfDate, op.DESIRED_WANT_DATE) * 8
                                                                               THEN 'FEASIBLE'
        ELSE                                                                        'AT_RISK_OVERCAPACITY'
    END                                                 AS load_vs_calendar,

    -- Overrun signal
    CAST(
        CASE
            WHEN (op.std_setup_hrs + op.std_run_hrs) > 0
            THEN 100.0 * ((op.act_setup_hrs + op.act_run_hrs)
                          - (op.std_setup_hrs + op.std_run_hrs))
                 / (op.std_setup_hrs + op.std_run_hrs)
            ELSE NULL
        END
    AS decimal(7,2))                                    AS hrs_overrun_pct
FROM open_ops op
LEFT JOIN PART_SITE_VIEW psv
    ON psv.SITE_ID = op.SITE_ID
   AND psv.PART_ID = op.PART_ID
LEFT JOIN SHOP_RESOURCE sr
    ON sr.ID = op.RESOURCE_ID
ORDER BY
    CASE
        WHEN op.DESIRED_WANT_DATE < @AsOfDate                                  THEN 1
        WHEN op.op_sched_finish <  @AsOfDate
             AND op.COMPLETED_QTY < op.DESIRED_QTY                             THEN 2
        WHEN op.rem_std_hrs > DATEDIFF(day, @AsOfDate, op.DESIRED_WANT_DATE) * 8 THEN 3
        ELSE                                                                        4
    END,
    op.DESIRED_WANT_DATE,
    op.BASE_ID, op.SEQUENCE_NO;
