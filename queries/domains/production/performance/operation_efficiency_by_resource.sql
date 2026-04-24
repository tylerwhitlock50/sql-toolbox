/*
===============================================================================
Query Name: operation_efficiency_by_resource.sql

Purpose:
    Per shop-resource (work center) earned-hours efficiency scorecard.
    Shows whether each work center is running at, above, or below
    engineered standard, and how much rework (BAD_QTY) is coming off it.

Business Use:
    - Weekly production manager review: who is running hot / cold?
    - Identify work centers with chronic setup overruns
    - Quantify rework volume by resource
    - Feed capacity planning with actual vs standard hours trend

Grain:
    One row per (SITE_ID, RESOURCE_ID) for the evaluation window.
    Window is driven by OPERATION.CLOSE_DATE (when the op completed).
    Operations that closed inside the window count toward the scorecard.

Key calculations:
    standard_hours_earned
        SUM(SETUP_HRS + RUN_HRS) on closed operations in window.
        This is the engineered "should have taken" hours for the qty
        completed.

    actual_hours_spent
        SUM(ACT_SETUP_HRS + ACT_RUN_HRS) on the same operations.

    efficiency_pct
        standard_hours_earned / actual_hours_spent * 100.
        100% = ran exactly to standard. >100% = faster than standard.

    setup_efficiency_pct
        SETUP_HRS / ACT_SETUP_HRS * 100.

    clock_hours
        SUM(HOURS_WORKED) from LABOR_TICKET charged to operations
        that closed in the window. This is the "door-to-door" time
        charged, independent of the op's ACT_ hours rollup.

    rework_pct
        SUM(BAD_QTY) / SUM(GOOD_QTY + BAD_QTY) * 100 from LABOR_TICKET.

Notes / Assumptions:
    - Operations are identified as closed via STATUS='C' and CLOSE_DATE.
    - LABOR_TICKET rows are linked by the 5-part WO key + OPERATION_SEQ_NO.
    - INDIRECT_CODE='Y' labor tickets (indirect labor) are excluded from
      the direct-hours calc.
    - This is a backward-looking view. For load / utilization vs capacity
      see schedule_health_by_operation.sql.

Potential Enhancements:
    - Break out setup vs run efficiency separately (partially done)
    - Add a "labor dollars" view using LABOR_TICKET.ACT_LABOR_COST
    - Join SHOP_RESOURCE_SITE for capacity (SHIFT_1_CAPACITY etc.) and
      compute utilization vs scheduled capacity
    - Add a trend lag (current window vs prior window)
===============================================================================
*/

DECLARE @Site     nvarchar(15) = NULL;
DECLARE @FromDate datetime     = DATEADD(day, -90, GETDATE());
DECLARE @ToDate   datetime     = GETDATE();

;WITH closed_ops AS (
    SELECT
        wo.SITE_ID,
        o.RESOURCE_ID,
        o.WORKORDER_TYPE, o.WORKORDER_BASE_ID, o.WORKORDER_LOT_ID,
        o.WORKORDER_SPLIT_ID, o.WORKORDER_SUB_ID,
        o.SEQUENCE_NO,
        o.CLOSE_DATE,
        o.COMPLETED_QTY,
        o.DEVIATED_QTY,
        COALESCE(o.SETUP_HRS, 0)       AS std_setup_hrs,
        COALESCE(o.RUN_HRS, 0)         AS std_run_hrs,
        COALESCE(o.ACT_SETUP_HRS, 0)   AS act_setup_hrs,
        COALESCE(o.ACT_RUN_HRS, 0)     AS act_run_hrs,
        (COALESCE(o.EST_ATL_LAB_COST, 0)
         + COALESCE(o.EST_ATL_BUR_COST, 0)
         + COALESCE(o.EST_ATL_SER_COST, 0)) AS est_cost_at_op,
        (COALESCE(o.ACT_ATL_LAB_COST, 0)
         + COALESCE(o.ACT_ATL_BUR_COST, 0)
         + COALESCE(o.ACT_ATL_SER_COST, 0)) AS act_cost_at_op
    FROM OPERATION o
    INNER JOIN WORK_ORDER wo
        ON wo.TYPE      = o.WORKORDER_TYPE
       AND wo.BASE_ID   = o.WORKORDER_BASE_ID
       AND wo.LOT_ID    = o.WORKORDER_LOT_ID
       AND wo.SPLIT_ID  = o.WORKORDER_SPLIT_ID
       AND wo.SUB_ID    = o.WORKORDER_SUB_ID
    WHERE o.STATUS = 'C'
      AND o.CLOSE_DATE >= @FromDate
      AND o.CLOSE_DATE <  @ToDate
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
),

-- LABOR_TICKET hours & qty for the same closed operations, direct labor only
labor AS (
    SELECT
        c.SITE_ID,
        c.RESOURCE_ID,
        c.WORKORDER_TYPE, c.WORKORDER_BASE_ID, c.WORKORDER_LOT_ID,
        c.WORKORDER_SPLIT_ID, c.WORKORDER_SUB_ID, c.SEQUENCE_NO,
        SUM(COALESCE(lt.HOURS_WORKED, 0))   AS clock_hours,
        SUM(COALESCE(lt.GOOD_QTY, 0))       AS good_qty,
        SUM(COALESCE(lt.BAD_QTY, 0))        AS bad_qty,
        SUM(COALESCE(lt.ACT_LABOR_COST, 0)) AS labor_cost,
        COUNT(DISTINCT lt.EMPLOYEE_ID)      AS unique_employees
    FROM closed_ops c
    INNER JOIN LABOR_TICKET lt
        ON lt.WORKORDER_TYPE     = c.WORKORDER_TYPE
       AND lt.WORKORDER_BASE_ID  = c.WORKORDER_BASE_ID
       AND lt.WORKORDER_LOT_ID   = c.WORKORDER_LOT_ID
       AND lt.WORKORDER_SPLIT_ID = c.WORKORDER_SPLIT_ID
       AND lt.WORKORDER_SUB_ID   = c.WORKORDER_SUB_ID
       AND lt.OPERATION_SEQ_NO   = c.SEQUENCE_NO
    WHERE ISNULL(lt.INDIRECT_CODE, 'N') = 'N'
    GROUP BY
        c.SITE_ID, c.RESOURCE_ID,
        c.WORKORDER_TYPE, c.WORKORDER_BASE_ID, c.WORKORDER_LOT_ID,
        c.WORKORDER_SPLIT_ID, c.WORKORDER_SUB_ID, c.SEQUENCE_NO
)

SELECT
    c.SITE_ID,
    c.RESOURCE_ID,
    sr.DESCRIPTION                                         AS resource_description,
    sr.DEPARTMENT_ID,
    sr.TYPE                                                AS resource_type,

    COUNT(*)                                               AS ops_completed,
    COUNT(DISTINCT
          c.WORKORDER_TYPE     + '|' + c.WORKORDER_BASE_ID + '|'
        + c.WORKORDER_LOT_ID   + '|' + c.WORKORDER_SPLIT_ID+ '|'
        + c.WORKORDER_SUB_ID)                              AS wos_touched,
    SUM(c.COMPLETED_QTY)                                   AS completed_qty,
    SUM(c.DEVIATED_QTY)                                    AS deviated_qty,

    -- Standard vs actual hours
    CAST(SUM(c.std_setup_hrs) AS decimal(14,2))            AS std_setup_hrs,
    CAST(SUM(c.std_run_hrs)   AS decimal(14,2))            AS std_run_hrs,
    CAST(SUM(c.std_setup_hrs + c.std_run_hrs) AS decimal(14,2)) AS std_total_hrs,

    CAST(SUM(c.act_setup_hrs) AS decimal(14,2))            AS act_setup_hrs,
    CAST(SUM(c.act_run_hrs)   AS decimal(14,2))            AS act_run_hrs,
    CAST(SUM(c.act_setup_hrs + c.act_run_hrs) AS decimal(14,2)) AS act_total_hrs,

    CAST(100.0 * SUM(c.std_setup_hrs + c.std_run_hrs)
         / NULLIF(SUM(c.act_setup_hrs + c.act_run_hrs), 0)
        AS decimal(7,2))                                   AS efficiency_pct,

    CAST(100.0 * SUM(c.std_setup_hrs)
         / NULLIF(SUM(c.act_setup_hrs), 0)
        AS decimal(7,2))                                   AS setup_efficiency_pct,

    CAST(100.0 * SUM(c.std_run_hrs)
         / NULLIF(SUM(c.act_run_hrs), 0)
        AS decimal(7,2))                                   AS run_efficiency_pct,

    -- Cost performance
    SUM(c.est_cost_at_op)                                  AS est_cost_at_op,
    SUM(c.act_cost_at_op)                                  AS act_cost_at_op,
    (SUM(c.act_cost_at_op) - SUM(c.est_cost_at_op))        AS cost_var_amount,
    CAST(100.0 * (SUM(c.act_cost_at_op) - SUM(c.est_cost_at_op))
         / NULLIF(SUM(c.est_cost_at_op), 0)
        AS decimal(7,2))                                   AS cost_var_pct,

    -- Labor-ticket-derived metrics
    CAST(SUM(COALESCE(l.clock_hours, 0)) AS decimal(14,2)) AS clock_hours,
    SUM(COALESCE(l.labor_cost, 0))                         AS labor_cost,
    SUM(COALESCE(l.good_qty, 0))                           AS good_qty,
    SUM(COALESCE(l.bad_qty,  0))                           AS bad_qty,
    CAST(100.0 * SUM(COALESCE(l.bad_qty, 0))
         / NULLIF(SUM(COALESCE(l.good_qty, 0) + COALESCE(l.bad_qty, 0)), 0)
        AS decimal(7,2))                                   AS rework_pct,
    SUM(COALESCE(l.unique_employees, 0))                   AS employee_contact_count,

    -- Tier tag for a quick glance
    CASE
        WHEN 100.0 * SUM(c.std_setup_hrs + c.std_run_hrs)
             / NULLIF(SUM(c.act_setup_hrs + c.act_run_hrs), 0) >= 95 THEN 'A - at/ahead of std'
        WHEN 100.0 * SUM(c.std_setup_hrs + c.std_run_hrs)
             / NULLIF(SUM(c.act_setup_hrs + c.act_run_hrs), 0) >= 80 THEN 'B - slightly behind'
        WHEN 100.0 * SUM(c.std_setup_hrs + c.std_run_hrs)
             / NULLIF(SUM(c.act_setup_hrs + c.act_run_hrs), 0) >= 60 THEN 'C - behind'
        ELSE                                                             'D - chronically behind'
    END                                                    AS efficiency_tier
FROM closed_ops c
LEFT JOIN labor l
    ON l.SITE_ID            = c.SITE_ID
   AND l.RESOURCE_ID        = c.RESOURCE_ID
   AND l.WORKORDER_TYPE     = c.WORKORDER_TYPE
   AND l.WORKORDER_BASE_ID  = c.WORKORDER_BASE_ID
   AND l.WORKORDER_LOT_ID   = c.WORKORDER_LOT_ID
   AND l.WORKORDER_SPLIT_ID = c.WORKORDER_SPLIT_ID
   AND l.WORKORDER_SUB_ID   = c.WORKORDER_SUB_ID
   AND l.SEQUENCE_NO        = c.SEQUENCE_NO
LEFT JOIN SHOP_RESOURCE sr
    ON sr.ID = c.RESOURCE_ID
GROUP BY c.SITE_ID, c.RESOURCE_ID, sr.DESCRIPTION, sr.DEPARTMENT_ID, sr.TYPE
ORDER BY SUM(c.act_setup_hrs + c.act_run_hrs) DESC;
