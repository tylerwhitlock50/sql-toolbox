/*
===============================================================================
Query Name: wo_otd_and_cycle_time.sql

Purpose:
    Closed work-order performance window. Answers:
        "For WOs we closed in this window, how did we do on:
             - hitting the want date (OTD)
             - cycle time from release -> close
             - cost vs estimate
             - yield (received vs desired)?"

Business Use:
    - Production KPI dashboard / management review
    - Spot product codes / parts that consistently miss plan
    - Quantify cost variance (actual vs estimated) as a PPV-style signal
    - Track cycle-time trend month over month

Grain:
    One row per closed work order (5-part key) in the window.
    Aggregate upstream in reporting for product_code / part / month.

Window:
    @FromDate / @ToDate default to trailing 365 days on CLOSE_DATE.

WO status codes (per WORK_ORDER check constraint):
    U=Unreleased, F=Firmed, R=Released, C=Closed, X=Cancelled.
    This query focuses on STATUS='C' with CLOSE_DATE in window.

Key metrics:
    on_time_flag
        CLOSE_DATE <= DESIRED_WANT_DATE -> 1, else 0.
        Uses CLOSE_DATE vs DESIRED_WANT_DATE (the promised completion
        date on the WO header).

    days_late
        DATEDIFF(day, DESIRED_WANT_DATE, CLOSE_DATE).
        Negative = finished early.

    cycle_days_release_to_close
        DATEDIFF(day, DESIRED_RLS_DATE, CLOSE_DATE).

    cycle_days_create_to_close
        DATEDIFF(day, CREATE_DATE, CLOSE_DATE).

    yield_pct
        RECEIVED_QTY / DESIRED_QTY * 100. Under 100 = short closure.

    est_total_cost / act_total_cost / cost_var_pct
        EST_* and ACT_* columns on WORK_ORDER header.

Notes / Assumptions:
    - Only includes costed/closed WOs (STATUS='C' and CLOSE_DATE set).
    - Excludes cancelled (STATUS='X') WOs.
    - DESIRED_WANT_DATE missing -> OTD metrics are NULL for that row.
    - Does NOT filter on TYPE; master records (TYPE='M') typically will
      not have CLOSE_DATE and are filtered naturally.

Potential Enhancements:
    - Add WIP balance (if a residual exists after close)
    - Add linked SO info via WBS_CUST_ORDER_ID where populated
    - Add planned vs actual hours roll-up from OPERATION
===============================================================================
*/

DECLARE @Site     nvarchar(15) = NULL;
DECLARE @FromDate datetime     = DATEADD(day, -365, GETDATE());
DECLARE @ToDate   datetime     = GETDATE();

;WITH closed_wo AS (
    SELECT
        wo.SITE_ID,
        wo.TYPE, wo.BASE_ID, wo.LOT_ID, wo.SPLIT_ID, wo.SUB_ID,
        wo.PART_ID,
        wo.PRODUCT_CODE,
        wo.COMMODITY_CODE,
        wo.WAREHOUSE_ID,
        wo.CREATE_DATE,
        wo.DESIRED_RLS_DATE,
        wo.DESIRED_WANT_DATE,
        wo.SCHED_START_DATE,
        wo.SCHED_FINISH_DATE,
        wo.CLOSE_DATE,
        wo.STATUS,
        wo.DESIRED_QTY,
        wo.RECEIVED_QTY,
        (wo.EST_MATERIAL_COST + wo.EST_LABOR_COST
         + wo.EST_BURDEN_COST + wo.EST_SERVICE_COST) AS est_total_cost,
        (wo.ACT_MATERIAL_COST + wo.ACT_LABOR_COST
         + wo.ACT_BURDEN_COST + wo.ACT_SERVICE_COST) AS act_total_cost,
        wo.EST_MATERIAL_COST,
        wo.ACT_MATERIAL_COST,
        wo.EST_LABOR_COST,
        wo.ACT_LABOR_COST,
        wo.EST_BURDEN_COST,
        wo.ACT_BURDEN_COST,
        wo.WBS_CUST_ORDER_ID
    FROM WORK_ORDER wo
    WHERE wo.STATUS = 'C'
      AND wo.CLOSE_DATE >= @FromDate
      AND wo.CLOSE_DATE <  @ToDate
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
),

op_roll AS (
    SELECT
        o.WORKORDER_TYPE    AS TYPE,
        o.WORKORDER_BASE_ID AS BASE_ID,
        o.WORKORDER_LOT_ID  AS LOT_ID,
        o.WORKORDER_SPLIT_ID AS SPLIT_ID,
        o.WORKORDER_SUB_ID  AS SUB_ID,
        SUM(COALESCE(o.SETUP_HRS, 0) + COALESCE(o.RUN_HRS, 0))         AS est_total_hrs,
        SUM(COALESCE(o.ACT_SETUP_HRS, 0) + COALESCE(o.ACT_RUN_HRS, 0)) AS act_total_hrs,
        COUNT(*)                                                        AS op_count
    FROM OPERATION o
    GROUP BY
        o.WORKORDER_TYPE,  o.WORKORDER_BASE_ID, o.WORKORDER_LOT_ID,
        o.WORKORDER_SPLIT_ID, o.WORKORDER_SUB_ID
)

SELECT
    w.SITE_ID,
    w.TYPE + '-' + w.BASE_ID + '/' + w.LOT_ID + '/' + w.SPLIT_ID + '/' + w.SUB_ID AS wo_key,
    w.TYPE, w.BASE_ID, w.LOT_ID, w.SPLIT_ID, w.SUB_ID,
    w.PART_ID,
    psv.DESCRIPTION                                   AS part_description,
    w.PRODUCT_CODE,
    w.COMMODITY_CODE,
    w.WAREHOUSE_ID,
    w.WBS_CUST_ORDER_ID,

    w.DESIRED_QTY,
    w.RECEIVED_QTY,
    CAST(100.0 * w.RECEIVED_QTY / NULLIF(w.DESIRED_QTY, 0)
         AS decimal(7,2))                             AS yield_pct,

    w.CREATE_DATE,
    w.DESIRED_RLS_DATE,
    w.DESIRED_WANT_DATE,
    w.SCHED_START_DATE,
    w.SCHED_FINISH_DATE,
    w.CLOSE_DATE,

    -- OTD
    CASE
        WHEN w.DESIRED_WANT_DATE IS NULL THEN NULL
        WHEN w.CLOSE_DATE <= w.DESIRED_WANT_DATE THEN 1
        ELSE 0
    END                                                AS on_time_flag,
    DATEDIFF(day, w.DESIRED_WANT_DATE, w.CLOSE_DATE)   AS days_late,

    -- Cycle time
    DATEDIFF(day, w.DESIRED_RLS_DATE, w.CLOSE_DATE)    AS cycle_days_release_to_close,
    DATEDIFF(day, w.CREATE_DATE,      w.CLOSE_DATE)    AS cycle_days_create_to_close,
    DATEDIFF(day, w.SCHED_START_DATE, w.CLOSE_DATE)    AS cycle_days_sched_start_to_close,

    -- Costs
    w.est_total_cost,
    w.act_total_cost,
    (w.act_total_cost - w.est_total_cost)              AS cost_var_amount,
    CAST(100.0 * (w.act_total_cost - w.est_total_cost)
         / NULLIF(w.est_total_cost, 0)
         AS decimal(7,2))                              AS cost_var_pct,

    w.EST_MATERIAL_COST, w.ACT_MATERIAL_COST,
    w.EST_LABOR_COST,    w.ACT_LABOR_COST,
    w.EST_BURDEN_COST,   w.ACT_BURDEN_COST,

    -- Hours from operations
    orl.op_count,
    orl.est_total_hrs,
    orl.act_total_hrs,
    CAST(100.0 * orl.act_total_hrs / NULLIF(orl.est_total_hrs, 0)
         AS decimal(7,2))                              AS hours_actual_vs_est_pct,

    -- Convenience bucket
    CASE
        WHEN w.DESIRED_WANT_DATE IS NULL                        THEN 'NO_TARGET'
        WHEN w.CLOSE_DATE <= w.DESIRED_WANT_DATE                THEN 'ON_TIME'
        WHEN DATEDIFF(day, w.DESIRED_WANT_DATE, w.CLOSE_DATE) <= 7   THEN 'LATE_1_7'
        WHEN DATEDIFF(day, w.DESIRED_WANT_DATE, w.CLOSE_DATE) <= 30  THEN 'LATE_8_30'
        ELSE                                                          'LATE_30_PLUS'
    END                                                AS otd_bucket
FROM closed_wo w
LEFT JOIN PART_SITE_VIEW psv
    ON psv.SITE_ID = w.SITE_ID
   AND psv.PART_ID = w.PART_ID
LEFT JOIN op_roll orl
    ON orl.TYPE     = w.TYPE
   AND orl.BASE_ID  = w.BASE_ID
   AND orl.LOT_ID   = w.LOT_ID
   AND orl.SPLIT_ID = w.SPLIT_ID
   AND orl.SUB_ID   = w.SUB_ID
ORDER BY w.CLOSE_DATE DESC, w.BASE_ID;
