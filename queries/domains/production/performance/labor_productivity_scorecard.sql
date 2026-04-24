/*
===============================================================================
Query Name: labor_productivity_scorecard.sql

Purpose:
    Per-employee (or per-department) labor productivity scorecard from
    LABOR_TICKET history. Shows clock hours, direct vs indirect split,
    earned hours vs clocked hours, good / bad output, and rework %.

Business Use:
    - Production supervisor weekly reviews
    - Identify employees / departments with high rework
    - Quantify indirect-labor leakage
    - Spot unusual hours patterns (excessive OT, low direct %)

Grain:
    One row per (SITE_ID, DEPARTMENT_ID, EMPLOYEE_ID) for the window.

Window:
    @FromDate / @ToDate default to trailing 90 days on
    LABOR_TICKET.TRANSACTION_DATE.

Key metrics:
    clock_hours
        SUM of HOURS_WORKED across all tickets.

    direct_hours / indirect_hours
        Split by LABOR_TICKET.INDIRECT_CODE ('N' = direct, 'Y' = indirect).

    earned_hours
        SUM of engineered standard hours for the GOOD_QTY reported on
        each direct ticket. Computed as:
            GOOD_QTY * (op.SETUP_HRS + op.RUN_HRS) / op.LOAD_SIZE_QTY
        when LOAD_SIZE_QTY is populated; otherwise proportional to
        the COMPLETED_QTY on the op (fallback).

        Because this is an approximation, use for trend direction, not
        for pay calculations.

    productivity_pct
        earned_hours / direct_hours * 100.

    good_qty / bad_qty / rework_pct
        SUM of GOOD_QTY and BAD_QTY.

    distinct_days_worked
        Count of distinct TRANSACTION_DATE values (density/attendance).

Notes / Assumptions:
    - Employees show under the DEPARTMENT_ID recorded on their tickets;
      if an employee worked across departments you get one row per
      (emp, dept) combo.
    - Indirect-labor tickets (INDIRECT_CODE='Y') contribute to
      clock_hours but NOT to earned_hours (by design — indirect work
      has no piece-rate standard).
    - earned_hours is approximate. Don't use for payroll.

Potential Enhancements:
    - Join to SYS_USER / EMPLOYEE for human name
    - Add per-resource split (employees who cover multiple work centers)
    - Add shift indicator from SHIFT_DATE
    - Compare current window vs prior window for trend
===============================================================================
*/

DECLARE @Site     nvarchar(15) = NULL;
DECLARE @FromDate datetime     = DATEADD(day, -90, GETDATE());
DECLARE @ToDate   datetime     = GETDATE();

;WITH op_std AS (
    SELECT
        o.WORKORDER_TYPE, o.WORKORDER_BASE_ID, o.WORKORDER_LOT_ID,
        o.WORKORDER_SPLIT_ID, o.WORKORDER_SUB_ID, o.SEQUENCE_NO,
        o.RESOURCE_ID,
        (COALESCE(o.SETUP_HRS, 0) + COALESCE(o.RUN_HRS, 0)) AS std_total_hrs,
        o.LOAD_SIZE_QTY,
        o.COMPLETED_QTY
    FROM OPERATION o
),

tickets AS (
    SELECT
        wo.SITE_ID,
        lt.EMPLOYEE_ID,
        lt.DEPARTMENT_ID,
        lt.RESOURCE_ID,
        lt.TRANSACTION_DATE,
        lt.INDIRECT_CODE,
        lt.TYPE                                         AS ticket_type,
        COALESCE(lt.HOURS_WORKED, 0)                    AS hours_worked,
        COALESCE(lt.GOOD_QTY, 0)                        AS good_qty,
        COALESCE(lt.BAD_QTY,  0)                        AS bad_qty,
        COALESCE(lt.ACT_LABOR_COST, 0)                  AS labor_cost,
        os.std_total_hrs,
        os.LOAD_SIZE_QTY,
        os.COMPLETED_QTY                                AS op_completed_qty,

        -- Approximate earned hours
        CASE
            WHEN ISNULL(lt.INDIRECT_CODE, 'N') = 'Y'     THEN 0
            WHEN os.std_total_hrs IS NULL                 THEN 0
            WHEN os.LOAD_SIZE_QTY IS NOT NULL
             AND os.LOAD_SIZE_QTY <> 0
                THEN COALESCE(lt.GOOD_QTY, 0) * os.std_total_hrs / os.LOAD_SIZE_QTY
            WHEN os.COMPLETED_QTY IS NOT NULL
             AND os.COMPLETED_QTY <> 0
                THEN COALESCE(lt.GOOD_QTY, 0) * os.std_total_hrs / os.COMPLETED_QTY
            ELSE 0
        END                                             AS earned_hours
    FROM LABOR_TICKET lt
    -- WO site lookup (LABOR_TICKET does not carry SITE_ID directly)
    LEFT JOIN WORK_ORDER wo
        ON wo.TYPE      = lt.WORKORDER_TYPE
       AND wo.BASE_ID   = lt.WORKORDER_BASE_ID
       AND wo.LOT_ID    = lt.WORKORDER_LOT_ID
       AND wo.SPLIT_ID  = lt.WORKORDER_SPLIT_ID
       AND wo.SUB_ID    = lt.WORKORDER_SUB_ID
    LEFT JOIN op_std os
        ON os.WORKORDER_TYPE     = lt.WORKORDER_TYPE
       AND os.WORKORDER_BASE_ID  = lt.WORKORDER_BASE_ID
       AND os.WORKORDER_LOT_ID   = lt.WORKORDER_LOT_ID
       AND os.WORKORDER_SPLIT_ID = lt.WORKORDER_SPLIT_ID
       AND os.WORKORDER_SUB_ID   = lt.WORKORDER_SUB_ID
       AND os.SEQUENCE_NO        = lt.OPERATION_SEQ_NO
    WHERE lt.TRANSACTION_DATE >= @FromDate
      AND lt.TRANSACTION_DATE <  @ToDate
      AND (@Site IS NULL OR wo.SITE_ID = @Site OR wo.SITE_ID IS NULL)
)

SELECT
    t.SITE_ID,
    t.DEPARTMENT_ID,
    t.EMPLOYEE_ID,

    COUNT(*)                                              AS ticket_count,
    COUNT(DISTINCT CAST(t.TRANSACTION_DATE AS date))      AS distinct_days_worked,
    COUNT(DISTINCT t.RESOURCE_ID)                         AS distinct_resources,

    -- Hours
    CAST(SUM(t.hours_worked) AS decimal(14,2))            AS clock_hours,
    CAST(SUM(CASE WHEN ISNULL(t.INDIRECT_CODE, 'N') = 'N'
                  THEN t.hours_worked ELSE 0 END)
         AS decimal(14,2))                                AS direct_hours,
    CAST(SUM(CASE WHEN ISNULL(t.INDIRECT_CODE, 'N') = 'Y'
                  THEN t.hours_worked ELSE 0 END)
         AS decimal(14,2))                                AS indirect_hours,
    CAST(100.0 * SUM(CASE WHEN ISNULL(t.INDIRECT_CODE, 'N') = 'N'
                          THEN t.hours_worked ELSE 0 END)
         / NULLIF(SUM(t.hours_worked), 0)
         AS decimal(5,2))                                 AS direct_pct,

    CAST(SUM(t.earned_hours) AS decimal(14,2))            AS earned_hours,
    CAST(100.0 * SUM(t.earned_hours)
         / NULLIF(SUM(CASE WHEN ISNULL(t.INDIRECT_CODE, 'N') = 'N'
                           THEN t.hours_worked ELSE 0 END), 0)
         AS decimal(7,2))                                 AS productivity_pct,

    -- Output
    SUM(t.good_qty)                                       AS good_qty,
    SUM(t.bad_qty)                                        AS bad_qty,
    CAST(100.0 * SUM(t.bad_qty)
         / NULLIF(SUM(t.good_qty + t.bad_qty), 0)
         AS decimal(7,2))                                 AS rework_pct,

    -- Cost
    SUM(t.labor_cost)                                     AS labor_cost,
    CAST(SUM(t.labor_cost) / NULLIF(SUM(t.hours_worked), 0)
         AS decimal(14,2))                                AS avg_effective_hourly_rate,

    -- Attention flag
    CASE
        WHEN SUM(t.bad_qty) / NULLIF(SUM(t.good_qty + t.bad_qty), 0) > 0.05
                                                                          THEN 'ATTENTION - rework'
        WHEN SUM(CASE WHEN ISNULL(t.INDIRECT_CODE, 'N') = 'N'
                      THEN t.hours_worked ELSE 0 END)
             / NULLIF(SUM(t.hours_worked), 0) < 0.60
                                                                          THEN 'ATTENTION - low direct'
        WHEN 100.0 * SUM(t.earned_hours)
             / NULLIF(SUM(CASE WHEN ISNULL(t.INDIRECT_CODE, 'N') = 'N'
                               THEN t.hours_worked ELSE 0 END), 0) < 60
                                                                          THEN 'ATTENTION - productivity'
        ELSE 'OK'
    END                                                   AS flag
FROM tickets t
GROUP BY t.SITE_ID, t.DEPARTMENT_ID, t.EMPLOYEE_ID
ORDER BY SUM(t.hours_worked) DESC;
