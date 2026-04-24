/*
===============================================================================
Query Name: fg_completion_forecast.sql

Purpose:
    For every open work order, project a realistic completion date so the
    sales / customer-service team can give credible ship dates and the
    CEO can see WIP-to-finished-goods conversion.

    Combines three signals:
      (1) ERP-scheduled finish date (OPERATION.SCHED_FINISH_DATE max).
      (2) Naive labor-projected finish: today + (remaining hours / 8h day),
          assuming a single shift of one resource; coarse but useful when
          ERP scheduling hasn't been refreshed.
      (3) Component-readiness gate: if any REQUIREMENT line is short of
          on-hand by (CALC_QTY - ISSUED_QTY), flag the WO as blocked.

    FORECAST_FINISH_DATE = max(ERP date, naive labor date, today). If
    components are blocked, append a flag and advise re-promise.

Grain:
    One row per open WO (TYPE='W', STATUS NOT IN ('X','C')).

Output:
    WO key, part, qty, status, ERP sched dates, naive labor date,
    forecast finish date, variance vs need, component readiness, the
    customer order(s) potentially consuming this WO (direct PART_ID match
    only -- not a full pegging tree).

Notes:
    Compat-safe. SO linkage is direct PART_ID match (top-level FG); use
    so_fulfillment_risk.sql for true SO-line-to-WO pegging through BOM.
===============================================================================
*/

DECLARE @Site nvarchar(15) = NULL;
DECLARE @HoursPerDay decimal(5,2) = 8.0;

;WITH
open_wo AS (
    SELECT
        wo.SITE_ID,
        wo.TYPE, wo.BASE_ID, wo.LOT_ID, wo.SPLIT_ID, wo.SUB_ID,
        wo.TYPE + '/' + wo.BASE_ID + '/' + wo.LOT_ID
            + '/' + wo.SPLIT_ID + '/' + wo.SUB_ID            AS WO_KEY,
        wo.PART_ID,
        wo.DESIRED_QTY,
        wo.RECEIVED_QTY,
        wo.DESIRED_QTY - wo.RECEIVED_QTY                     AS OPEN_QTY,
        wo.STATUS                                             AS WO_STATUS,
        wo.CREATE_DATE,
        wo.SCHED_START_DATE,
        wo.SCHED_FINISH_DATE,
        wo.DESIRED_WANT_DATE,
        ISNULL(wo.ACT_MATERIAL_COST,0)
            + ISNULL(wo.ACT_LABOR_COST,0)
            + ISNULL(wo.ACT_BURDEN_COST,0)
            + ISNULL(wo.ACT_SERVICE_COST,0)                   AS WIP_VALUE,
        ISNULL(wo.REM_MATERIAL_COST,0)
            + ISNULL(wo.REM_LABOR_COST,0)
            + ISNULL(wo.REM_BURDEN_COST,0)
            + ISNULL(wo.REM_SERVICE_COST,0)                   AS REMAINING_COST
    FROM WORK_ORDER wo
    WHERE wo.TYPE = 'W'
      AND ISNULL(wo.STATUS,'') NOT IN ('X','C')
      AND wo.DESIRED_QTY > wo.RECEIVED_QTY
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
),

-- Per WO: remaining labor hours and op date envelope
op_summary AS (
    SELECT
        wo.WO_KEY,
        SUM(CASE WHEN ISNULL(op.SETUP_HRS,0) > ISNULL(op.ACT_SETUP_HRS,0)
                 THEN ISNULL(op.SETUP_HRS,0) - ISNULL(op.ACT_SETUP_HRS,0) ELSE 0 END
          + CASE WHEN ISNULL(op.RUN_HRS,0)   > ISNULL(op.ACT_RUN_HRS,0)
                 THEN ISNULL(op.RUN_HRS,0)   - ISNULL(op.ACT_RUN_HRS,0)   ELSE 0 END)
            AS REMAINING_LABOR_HRS,
        SUM(ISNULL(op.SETUP_HRS,0) + ISNULL(op.RUN_HRS,0))    AS TOTAL_LABOR_HRS,
        SUM(ISNULL(op.ACT_SETUP_HRS,0) + ISNULL(op.ACT_RUN_HRS,0)) AS ACTUAL_LABOR_HRS,
        MIN(op.SCHED_START_DATE)                              AS FIRST_OP_START,
        MAX(op.SCHED_FINISH_DATE)                             AS LAST_OP_FINISH,
        SUM(CASE WHEN ISNULL(op.STATUS,'') NOT IN ('X','C','F') THEN 1 ELSE 0 END)
            AS OPS_OPEN,
        COUNT(*)                                              AS TOTAL_OPS
    FROM open_wo wo
    LEFT JOIN OPERATION op
        ON op.WORKORDER_TYPE     = wo.TYPE
       AND op.WORKORDER_BASE_ID  = wo.BASE_ID
       AND op.WORKORDER_LOT_ID   = wo.LOT_ID
       AND op.WORKORDER_SPLIT_ID = wo.SPLIT_ID
       AND op.WORKORDER_SUB_ID   = wo.SUB_ID
    GROUP BY wo.WO_KEY
),

-- Per WO: component readiness check (requirement vs on-hand)
component_check AS (
    SELECT
        wo.WO_KEY,
        wo.SITE_ID,
        COUNT(*)                                                          AS REQ_COUNT,
        SUM(CASE
                WHEN rq.CALC_QTY - rq.ISSUED_QTY <= ISNULL(psv.QTY_ON_HAND, 0) THEN 0
                ELSE 1
            END)                                                          AS REQS_SHORT,
        SUM(CASE
                WHEN rq.CALC_QTY - rq.ISSUED_QTY > ISNULL(psv.QTY_ON_HAND, 0)
                THEN (rq.CALC_QTY - rq.ISSUED_QTY - ISNULL(psv.QTY_ON_HAND, 0))
                     * ISNULL(psv.UNIT_MATERIAL_COST,0)
                ELSE 0
            END)                                                          AS COMPONENT_SHORTAGE_VALUE
    FROM open_wo wo
    INNER JOIN REQUIREMENT rq
        ON rq.WORKORDER_TYPE     = wo.TYPE
       AND rq.WORKORDER_BASE_ID  = wo.BASE_ID
       AND rq.WORKORDER_LOT_ID   = wo.LOT_ID
       AND rq.WORKORDER_SPLIT_ID = wo.SPLIT_ID
       AND rq.WORKORDER_SUB_ID   = wo.SUB_ID
    LEFT JOIN PART_SITE_VIEW psv
        ON psv.SITE_ID = wo.SITE_ID AND psv.PART_ID = rq.PART_ID
    WHERE rq.STATUS = 'U'
      AND rq.PART_ID IS NOT NULL
      AND rq.CALC_QTY > rq.ISSUED_QTY
    GROUP BY wo.WO_KEY, wo.SITE_ID
),

-- Direct SO linkage by part (best-effort: top-level FG matches a customer-order line)
so_match AS (
    SELECT
        wo.SITE_ID, wo.PART_ID,
        COUNT(*)                                              AS OPEN_SO_LINES_FOR_PART,
        SUM(col.ORDER_QTY - col.TOTAL_SHIPPED_QTY)            AS OPEN_SO_QTY_FOR_PART,
        SUM((col.ORDER_QTY - col.TOTAL_SHIPPED_QTY) * col.UNIT_PRICE) AS OPEN_SO_VALUE_FOR_PART,
        MIN(COALESCE(col.PROMISE_DATE, col.DESIRED_SHIP_DATE,
                     co.DESIRED_SHIP_DATE))                   AS EARLIEST_SO_NEED_DATE
    FROM open_wo wo
    INNER JOIN CUST_ORDER_LINE col
        ON col.SITE_ID = wo.SITE_ID AND col.PART_ID = wo.PART_ID
    INNER JOIN CUSTOMER_ORDER co ON co.ID = col.CUST_ORDER_ID
    WHERE co.STATUS IN ('R','F') AND col.LINE_STATUS='A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
    GROUP BY wo.SITE_ID, wo.PART_ID
)

SELECT
    w.SITE_ID,
    w.WO_KEY,
    w.PART_ID,
    psv.DESCRIPTION                          AS PART_DESCRIPTION,
    psv.PRODUCT_CODE,
    w.WO_STATUS,
    w.DESIRED_QTY,
    w.RECEIVED_QTY,
    w.OPEN_QTY,
    CAST(
        CASE WHEN w.DESIRED_QTY = 0 THEN NULL
             ELSE 100.0 * w.RECEIVED_QTY / w.DESIRED_QTY
        END AS decimal(6,2)) AS PCT_COMPLETE_QTY,

    w.CREATE_DATE,
    w.SCHED_START_DATE                       AS WO_SCHED_START,
    w.SCHED_FINISH_DATE                      AS WO_SCHED_FINISH,
    w.DESIRED_WANT_DATE                      AS WO_NEED_DATE,
    os.FIRST_OP_START                        AS FIRST_OP_SCHED_START,
    os.LAST_OP_FINISH                        AS LAST_OP_SCHED_FINISH,

    os.TOTAL_LABOR_HRS,
    os.ACTUAL_LABOR_HRS,
    os.REMAINING_LABOR_HRS,
    os.OPS_OPEN,
    os.TOTAL_OPS,

    -- Component readiness
    ISNULL(cc.REQ_COUNT, 0)                  AS REQ_COUNT,
    ISNULL(cc.REQS_SHORT, 0)                 AS REQS_SHORT,
    CAST(ISNULL(cc.COMPONENT_SHORTAGE_VALUE,0) AS decimal(23,2)) AS COMPONENT_SHORTAGE_VALUE,
    CASE WHEN ISNULL(cc.REQS_SHORT, 0) = 0 THEN 'Y' ELSE 'N' END AS COMPONENTS_READY,

    -- Naive labor-only finish: today + remaining_hrs / 8h day
    CASE
        WHEN ISNULL(os.REMAINING_LABOR_HRS, 0) <= 0 THEN CAST(GETDATE() AS date)
        ELSE DATEADD(day,
                     CEILING(os.REMAINING_LABOR_HRS / @HoursPerDay),
                     CAST(GETDATE() AS date))
    END                                      AS NAIVE_LABOR_FINISH,

    -- Combined forecast: max of (ERP sched finish, naive labor, today)
    -- and add 7 days of slack if components aren't ready (re-promise needed)
    CASE
        WHEN ISNULL(cc.REQS_SHORT, 0) > 0
            THEN DATEADD(day, 7,
                 CASE
                    WHEN COALESCE(w.SCHED_FINISH_DATE, os.LAST_OP_FINISH) IS NULL THEN
                        CASE WHEN ISNULL(os.REMAINING_LABOR_HRS,0) <= 0 THEN CAST(GETDATE() AS date)
                             ELSE DATEADD(day, CEILING(os.REMAINING_LABOR_HRS / @HoursPerDay),
                                          CAST(GETDATE() AS date)) END
                    WHEN COALESCE(w.SCHED_FINISH_DATE, os.LAST_OP_FINISH) <
                         DATEADD(day,
                                 CASE WHEN ISNULL(os.REMAINING_LABOR_HRS,0) <= 0 THEN 0
                                      ELSE CEILING(os.REMAINING_LABOR_HRS / @HoursPerDay) END,
                                 CAST(GETDATE() AS date))
                        THEN DATEADD(day,
                                     CASE WHEN ISNULL(os.REMAINING_LABOR_HRS,0) <= 0 THEN 0
                                          ELSE CEILING(os.REMAINING_LABOR_HRS / @HoursPerDay) END,
                                     CAST(GETDATE() AS date))
                    ELSE COALESCE(w.SCHED_FINISH_DATE, os.LAST_OP_FINISH)
                 END)
        ELSE
            CASE
                WHEN COALESCE(w.SCHED_FINISH_DATE, os.LAST_OP_FINISH) IS NULL THEN
                    CASE WHEN ISNULL(os.REMAINING_LABOR_HRS,0) <= 0 THEN CAST(GETDATE() AS date)
                         ELSE DATEADD(day, CEILING(os.REMAINING_LABOR_HRS / @HoursPerDay),
                                      CAST(GETDATE() AS date)) END
                WHEN COALESCE(w.SCHED_FINISH_DATE, os.LAST_OP_FINISH) <
                     DATEADD(day,
                             CASE WHEN ISNULL(os.REMAINING_LABOR_HRS,0) <= 0 THEN 0
                                  ELSE CEILING(os.REMAINING_LABOR_HRS / @HoursPerDay) END,
                             CAST(GETDATE() AS date))
                    THEN DATEADD(day,
                                 CASE WHEN ISNULL(os.REMAINING_LABOR_HRS,0) <= 0 THEN 0
                                      ELSE CEILING(os.REMAINING_LABOR_HRS / @HoursPerDay) END,
                                 CAST(GETDATE() AS date))
                ELSE COALESCE(w.SCHED_FINISH_DATE, os.LAST_OP_FINISH)
            END
    END                                      AS FORECAST_FINISH_DATE,

    -- WIP / cost
    CAST(w.WIP_VALUE       AS decimal(23,2)) AS WIP_VALUE,
    CAST(w.REMAINING_COST  AS decimal(23,2)) AS REMAINING_COST,

    -- SO linkage (direct PART_ID match -- top-level FG)
    ISNULL(sm.OPEN_SO_LINES_FOR_PART, 0)     AS OPEN_SO_LINES_FOR_PART,
    ISNULL(sm.OPEN_SO_QTY_FOR_PART, 0)       AS OPEN_SO_QTY_FOR_PART,
    CAST(ISNULL(sm.OPEN_SO_VALUE_FOR_PART,0) AS decimal(23,2)) AS OPEN_SO_VALUE_FOR_PART,
    sm.EARLIEST_SO_NEED_DATE,

    CASE
        WHEN ISNULL(cc.REQS_SHORT, 0) > 0   THEN 'BLOCKED (COMPONENTS SHORT)'
        WHEN COALESCE(w.SCHED_FINISH_DATE, os.LAST_OP_FINISH) < CAST(GETDATE() AS date)
                                            THEN 'PAST SCHEDULED FINISH'
        WHEN os.OPS_OPEN = 0                THEN 'OPS COMPLETE - PENDING RECEIPT'
        WHEN sm.EARLIEST_SO_NEED_DATE IS NOT NULL
             AND COALESCE(w.SCHED_FINISH_DATE, os.LAST_OP_FINISH) > sm.EARLIEST_SO_NEED_DATE
                                            THEN 'WILL MISS SO PROMISE'
        ELSE                                     'ON TRACK'
    END AS COMPLETION_STATUS

FROM open_wo w
LEFT JOIN op_summary       os ON os.WO_KEY  = w.WO_KEY
LEFT JOIN component_check  cc ON cc.WO_KEY  = w.WO_KEY
LEFT JOIN PART_SITE_VIEW   psv
    ON psv.SITE_ID=w.SITE_ID AND psv.PART_ID=w.PART_ID
LEFT JOIN so_match         sm ON sm.SITE_ID=w.SITE_ID AND sm.PART_ID=w.PART_ID
ORDER BY
    CASE
        WHEN ISNULL(cc.REQS_SHORT,0) > 0 THEN 1
        WHEN COALESCE(w.SCHED_FINISH_DATE, os.LAST_OP_FINISH) < CAST(GETDATE() AS date) THEN 2
        ELSE 3
    END,
    sm.EARLIEST_SO_NEED_DATE,
    w.SCHED_FINISH_DATE;
