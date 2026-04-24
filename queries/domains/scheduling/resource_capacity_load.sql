/*
===============================================================================
Query Name: resource_capacity_load.sql

Purpose:
    Per shop resource × week, compare REQUIRED hours (from scheduled work
    orders) against AVAILABLE hours (from SHOP_RESOURCE shift capacity).
    Surface bottlenecks before they break the schedule.

    This is the missing capacity-planning query that pairs with
    purchasing_plan.sql / make_plan_weekly.sql -- buying parts is useless
    if there's no shop floor capacity to convert them into product.

Grain:
    One row per (SITE_ID, RESOURCE_ID, BUCKET_NO) over @Horizon weeks.
    Plus a synthetic "_TOTAL_" row per resource summing the horizon.

Required hours (load):
    Sum of remaining SETUP and RUN hours across open work-order
    OPERATION rows at the resource:
        REM_SETUP = SETUP_HRS    - ACT_SETUP_HRS
        REM_RUN   = RUN_HRS      - ACT_RUN_HRS
        REM_HRS   = REM_SETUP + REM_RUN
    Allocated to the bucket containing OPERATION.SCHED_START_DATE.
    Past-scheduled (SCHED_START < this Monday) is collapsed into bucket 0
    so it surfaces as overdue work.

Available hours (capacity):
    DAILY_CAP_HRS = (SHIFT_1_CAPACITY + SHIFT_2_CAPACITY + SHIFT_3_CAPACITY)
                    * 8                                          (assumed 8h shift)
    WEEKLY_CAP_HRS = DAILY_CAP_HRS * 5                            (5-day week)
    EFFECTIVE_HRS  = WEEKLY_CAP_HRS * EFFICIENCY_FACTOR / 100
                                                                  (or 1.0 if NULL)

Notes:
    * SHOP_RESOURCE doesn't store per-site capacity; we assume global.
      For multi-site companies that genuinely staff resources differently
      per site this is an approximation -- adjust shift columns if needed.
    * Setup-once WOs that are mid-run will show only run remainder; the
      ACT_* columns net out completed labor.
    * Excludes resources where SCHEDULE_NORMALLY = 'N' (not scheduled).
    * Excludes resources where TYPE NOT IN ('W','C') -- only Work Centers
      and Crews are physical capacity. Indirect/group are administrative.

Status flag:
    OK         load < 80% of capacity
    WATCH      80% <= load < 100%
    OVERLOAD   100% <= load < 130%
    CRITICAL   load >= 130%
    PAST DUE   bucket 0 with operations whose SCHED_START is in the past
===============================================================================
*/

DECLARE @Site     nvarchar(15) = NULL;
DECLARE @Horizon  int          = 13;     -- 13 weeks of scheduling visibility
DECLARE @ShiftHours decimal(5,2) = 8.0;
DECLARE @WorkDays   decimal(3,1) = 5.0;

DECLARE @WeekStart date =
    DATEADD(day,
            -((DATEPART(weekday, CAST(GETDATE() AS date)) + @@DATEFIRST - 2) % 7),
            CAST(GETDATE() AS date));

;WITH
buckets AS (
    SELECT 0 AS BUCKET_NO,
           CAST(@WeekStart AS date) AS BUCKET_START,
           DATEADD(day, 7, CAST(@WeekStart AS date)) AS BUCKET_END
    UNION ALL
    SELECT BUCKET_NO + 1, DATEADD(week,1,BUCKET_START), DATEADD(week,1,BUCKET_END)
    FROM buckets WHERE BUCKET_NO + 1 < @Horizon
),

-- Open work-order operations needing capacity
open_ops AS (
    SELECT
        wo.SITE_ID,
        op.RESOURCE_ID,
        wo.TYPE + '/' + wo.BASE_ID + '/' + wo.LOT_ID
            + '/' + wo.SPLIT_ID + '/' + wo.SUB_ID            AS WO_KEY,
        op.SEQUENCE_NO,
        op.SCHED_START_DATE,
        op.SCHED_FINISH_DATE,
        wo.PART_ID,
        wo.DESIRED_QTY,
        wo.RECEIVED_QTY,
        op.STATUS                                              AS OP_STATUS,
        -- Remaining setup/run hours (never negative)
        CASE WHEN ISNULL(op.SETUP_HRS,0) > ISNULL(op.ACT_SETUP_HRS,0)
             THEN ISNULL(op.SETUP_HRS,0) - ISNULL(op.ACT_SETUP_HRS,0) ELSE 0 END AS REM_SETUP_HRS,
        CASE WHEN ISNULL(op.RUN_HRS,0)   > ISNULL(op.ACT_RUN_HRS,0)
             THEN ISNULL(op.RUN_HRS,0)   - ISNULL(op.ACT_RUN_HRS,0)   ELSE 0 END AS REM_RUN_HRS
    FROM WORK_ORDER wo
    INNER JOIN OPERATION op
        ON  op.WORKORDER_TYPE     = wo.TYPE
        AND op.WORKORDER_BASE_ID  = wo.BASE_ID
        AND op.WORKORDER_LOT_ID   = wo.LOT_ID
        AND op.WORKORDER_SPLIT_ID = wo.SPLIT_ID
        AND op.WORKORDER_SUB_ID   = wo.SUB_ID
    WHERE wo.TYPE = 'W'
      AND ISNULL(wo.STATUS,'')   NOT IN ('X','C')
      AND ISNULL(op.STATUS,'')   NOT IN ('X','C')
      AND op.RESOURCE_ID IS NOT NULL
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
      AND op.SCHED_START_DATE IS NOT NULL
),

ops_bucketed AS (
    SELECT
        SITE_ID,
        RESOURCE_ID,
        CASE WHEN SCHED_START_DATE < @WeekStart THEN 0
             ELSE DATEDIFF(week, @WeekStart, SCHED_START_DATE) END AS BUCKET_NO,
        REM_SETUP_HRS + REM_RUN_HRS                                  AS REM_HRS,
        WO_KEY, SEQUENCE_NO,
        SCHED_START_DATE,
        CASE WHEN SCHED_START_DATE < CAST(GETDATE() AS date)
             AND REM_SETUP_HRS + REM_RUN_HRS > 0 THEN 1 ELSE 0 END   AS PAST_DUE_FLAG
    FROM open_ops
    WHERE SCHED_START_DATE < DATEADD(week, @Horizon, @WeekStart)
       OR SCHED_START_DATE < @WeekStart   -- past-due rolls into bucket 0
),

load_per_bucket AS (
    SELECT
        SITE_ID, RESOURCE_ID, BUCKET_NO,
        COUNT(*)                              AS OP_COUNT,
        COUNT(DISTINCT WO_KEY)                AS WO_COUNT,
        SUM(REM_HRS)                          AS REQUIRED_HRS,
        SUM(PAST_DUE_FLAG)                    AS PAST_DUE_OPS
    FROM ops_bucketed
    GROUP BY SITE_ID, RESOURCE_ID, BUCKET_NO
),

-- Resource master: capacity model
schedulable_resources AS (
    SELECT
        sr.ID                                 AS RESOURCE_ID,
        sr.DESCRIPTION,
        sr.TYPE,
        sr.DEPARTMENT_ID,
        sr.SCHEDULE_GROUP_ID,
        sr.SHIFT_1_CAPACITY + sr.SHIFT_2_CAPACITY + sr.SHIFT_3_CAPACITY AS HEADCOUNT,
        ISNULL(sr.EFFICIENCY_FACTOR, 100.0)   AS EFFICIENCY_FACTOR,
        sr.STATUS
    FROM SHOP_RESOURCE sr
    WHERE sr.SCHEDULE_NORMALLY = 'Y'
      AND sr.TYPE IN ('W','C')                -- Work center or Crew
      AND ISNULL(sr.STATUS,'') <> 'I'         -- skip inactive
)

-- Final: cross resource × bucket, fill load, compute capacity
SELECT
    COALESCE(l.SITE_ID, '_ANY_')            AS SITE_ID,
    sr.RESOURCE_ID,
    sr.DESCRIPTION                          AS RESOURCE_DESCRIPTION,
    sr.TYPE                                 AS RESOURCE_TYPE,
    sr.DEPARTMENT_ID,
    sr.SCHEDULE_GROUP_ID,
    sr.HEADCOUNT,
    sr.EFFICIENCY_FACTOR,

    bk.BUCKET_NO,
    bk.BUCKET_START,
    bk.BUCKET_END,

    -- Required hours
    ISNULL(l.OP_COUNT, 0)                   AS OP_COUNT,
    ISNULL(l.WO_COUNT, 0)                   AS WO_COUNT,
    ISNULL(l.PAST_DUE_OPS, 0)               AS PAST_DUE_OPS,
    CAST(ISNULL(l.REQUIRED_HRS,0) AS decimal(15,2)) AS REQUIRED_HRS,

    -- Available hours (assumes 5-day week × 8h × headcount × efficiency)
    CAST(sr.HEADCOUNT * @ShiftHours * @WorkDays
         * sr.EFFICIENCY_FACTOR / 100.0 AS decimal(15,2)) AS WEEKLY_CAPACITY_HRS,

    -- Load %
    CAST(
        CASE
            WHEN sr.HEADCOUNT * @ShiftHours * @WorkDays * sr.EFFICIENCY_FACTOR = 0
                THEN NULL
            ELSE 100.0 * ISNULL(l.REQUIRED_HRS,0)
                 / (sr.HEADCOUNT * @ShiftHours * @WorkDays * sr.EFFICIENCY_FACTOR / 100.0)
        END AS decimal(7,2)
    ) AS LOAD_PCT,

    CASE
        WHEN bk.BUCKET_NO = 0 AND ISNULL(l.PAST_DUE_OPS,0) > 0   THEN 'PAST DUE'
        WHEN sr.HEADCOUNT = 0                                    THEN 'NO CAPACITY DEFINED'
        WHEN ISNULL(l.REQUIRED_HRS,0) = 0                        THEN 'IDLE'
        WHEN 100.0 * ISNULL(l.REQUIRED_HRS,0)
             / (sr.HEADCOUNT * @ShiftHours * @WorkDays * sr.EFFICIENCY_FACTOR / 100.0) >= 130
                                                                 THEN 'CRITICAL'
        WHEN 100.0 * ISNULL(l.REQUIRED_HRS,0)
             / (sr.HEADCOUNT * @ShiftHours * @WorkDays * sr.EFFICIENCY_FACTOR / 100.0) >= 100
                                                                 THEN 'OVERLOAD'
        WHEN 100.0 * ISNULL(l.REQUIRED_HRS,0)
             / (sr.HEADCOUNT * @ShiftHours * @WorkDays * sr.EFFICIENCY_FACTOR / 100.0) >= 80
                                                                 THEN 'WATCH'
        ELSE                                                          'OK'
    END AS LOAD_STATUS

FROM schedulable_resources sr
CROSS JOIN buckets bk
LEFT JOIN load_per_bucket l
    ON l.RESOURCE_ID = sr.RESOURCE_ID AND l.BUCKET_NO = bk.BUCKET_NO

UNION ALL

-- Per-resource horizon rollup (BUCKET_NO = -1)
SELECT
    COALESCE(MIN(l.SITE_ID), '_ANY_'),
    sr.RESOURCE_ID, sr.DESCRIPTION, sr.TYPE,
    sr.DEPARTMENT_ID, sr.SCHEDULE_GROUP_ID,
    sr.HEADCOUNT, sr.EFFICIENCY_FACTOR,
    -1, NULL, NULL,
    SUM(ISNULL(l.OP_COUNT,0)),
    SUM(ISNULL(l.WO_COUNT,0)),
    SUM(ISNULL(l.PAST_DUE_OPS,0)),
    CAST(SUM(ISNULL(l.REQUIRED_HRS,0)) AS decimal(15,2)),
    CAST(@Horizon * sr.HEADCOUNT * @ShiftHours * @WorkDays
         * sr.EFFICIENCY_FACTOR / 100.0 AS decimal(15,2)),
    CAST(
        CASE
            WHEN sr.HEADCOUNT * @ShiftHours * @WorkDays * sr.EFFICIENCY_FACTOR = 0 THEN NULL
            ELSE 100.0 * SUM(ISNULL(l.REQUIRED_HRS,0))
                 / (@Horizon * sr.HEADCOUNT * @ShiftHours * @WorkDays * sr.EFFICIENCY_FACTOR / 100.0)
        END AS decimal(7,2)),
    CASE
        WHEN sr.HEADCOUNT = 0 THEN 'NO CAPACITY DEFINED'
        ELSE 'HORIZON_TOTAL'
    END
FROM schedulable_resources sr
LEFT JOIN load_per_bucket l ON l.RESOURCE_ID = sr.RESOURCE_ID
GROUP BY sr.RESOURCE_ID, sr.DESCRIPTION, sr.TYPE,
         sr.DEPARTMENT_ID, sr.SCHEDULE_GROUP_ID,
         sr.HEADCOUNT, sr.EFFICIENCY_FACTOR

ORDER BY
    RESOURCE_ID,
    BUCKET_NO    -- -1 sorts first per resource: rollup row at top
OPTION (MAXRECURSION 0);
