/*
===============================================================================
Query Name: net_requirements_weekly.sql

Purpose:
    Time-phased MRP grid. For each (SITE_ID, PART_ID), produce one row per
    weekly bucket showing:

        * GROSS_REQ           - exploded gross demand falling in the bucket
        * OPEN_PO_QTY         - inbound PO receipts expected in the bucket
        * OPEN_WO_QTY         - inbound work-order completions in the bucket
                                (for fabricated parts -- their own master WO
                                 production, NOT requirements off other WOs)
        * PLANNED_ORDER_QTY   - PLANNED_ORDER row qty in the bucket
        * SCHEDULED_RECEIPTS  - sum of the three supply columns
        * PROJECTED_ON_HAND   - running on-hand: start + cumulative
                                (SCHEDULED_RECEIPTS - GROSS_REQ)
        * NET_REQUIREMENT     - max(0, -projected_on_hand) when negative

    Past-due gross demand (NEED_DATE < this Monday) lands in bucket 0 so it
    surfaces immediately rather than disappearing.

Grain:
    One row per (SITE_ID, PART_ID, BUCKET_NO).
    BUCKET_NO 0..@Horizon-1, anchored on the Monday of the current week.

Design decisions (locked in plan file):
    * Compute net requirements from RAW demand + supply. Do not depend on
      Visual MRP being run.
    * Read demand from MASTER_SCHEDULE (firmed=Y/N) AND DEMAND_FORECAST AND
      open sales orders. Forecast tables may be empty today -- safe.
    * Default @Site = NULL (all sites), @Horizon = 26 weeks.
    * BOM walk inline (same logic as exploded_gross_demand.sql) so the
      query is self-contained.

Notes:
    * Compat-level safe: no SUM() OVER ORDER BY frames. Running on-hand is
      computed via a self-join on the bucket grid.
    * Limited to parts with at least one demand or supply row in the
      horizon (avoids 100% of the part master).
    * Open-PO qty here is in ORDER UM (PURC_ORDER_LINE.ORDER_QTY -
      TOTAL_RECEIVED_QTY); for parts where STOCK_UM = PURCHASE_UM this is
      fine. For mixed UM cases prefer open_and_planned_supply_detail.sql
      which does full UOM normalization.
===============================================================================
*/

DECLARE @Site     nvarchar(15) = NULL;
DECLARE @Horizon  int          = 26;
DECLARE @MaxDepth int          = 20;

-- Anchor: Monday of the current week
DECLARE @WeekStart date =
    DATEADD(day,
            -((DATEPART(weekday, CAST(GETDATE() AS date)) + @@DATEFIRST - 2) % 7),
            CAST(GETDATE() AS date));

;WITH
-- ============================================================
-- 1) Week spine (bucket 0..@Horizon-1)
-- ============================================================
buckets AS (
    SELECT 0 AS BUCKET_NO,
           CAST(@WeekStart AS date)             AS BUCKET_START,
           DATEADD(day, 7, CAST(@WeekStart AS date)) AS BUCKET_END
    UNION ALL
    SELECT BUCKET_NO + 1,
           DATEADD(week, 1, BUCKET_START),
           DATEADD(week, 1, BUCKET_END)
    FROM buckets
    WHERE BUCKET_NO + 1 < @Horizon
),

-- ============================================================
-- 2) Demand union (sales backorder + master schedule + forecast)
-- ============================================================
demand AS (
    SELECT
        col.SITE_ID,
        col.PART_ID,
        COALESCE(col.PROMISE_DATE, col.DESIRED_SHIP_DATE, co.DESIRED_SHIP_DATE) AS NEED_DATE,
        col.ORDER_QTY - col.TOTAL_SHIPPED_QTY AS DEMAND_QTY
    FROM CUST_ORDER_LINE col
    INNER JOIN CUSTOMER_ORDER co ON co.ID = col.CUST_ORDER_ID
    WHERE co.STATUS    IN ('R','F')
      AND col.LINE_STATUS = 'A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
      AND col.PART_ID  IS NOT NULL
      AND (@Site IS NULL OR col.SITE_ID = @Site)

    UNION ALL

    SELECT ms.SITE_ID, ms.PART_ID, ms.WANT_DATE, ms.ORDER_QTY
    FROM MASTER_SCHEDULE ms
    WHERE ms.ORDER_QTY > 0
      AND (@Site IS NULL OR ms.SITE_ID = @Site)

    UNION ALL

    SELECT df.SITE_ID, df.PART_ID, df.REQUIRED_DATE, df.REQUIRED_QTY
    FROM DEMAND_FORECAST df
    WHERE df.REQUIRED_QTY > 0
      AND (@Site IS NULL OR df.SITE_ID = @Site)
),

demand_agg AS (
    SELECT SITE_ID, PART_ID, NEED_DATE, SUM(DEMAND_QTY) AS DEMAND_QTY
    FROM demand
    GROUP BY SITE_ID, PART_ID, NEED_DATE
),

-- ============================================================
-- 3) BOM explosion of demand to component-level gross requirements
--    (mirrors exploded_gross_demand.sql logic; emits both the top
--    fabricated part and its components.)
-- ============================================================
bom AS (
    -- Anchor: level 0 = the demanded part itself
    SELECT
        CAST(0 AS int)                          AS BOM_LEVEL,
        d.SITE_ID,
        d.NEED_DATE,
        d.PART_ID                               AS COMPONENT_PART_ID,
        CAST(d.DEMAND_QTY AS decimal(28,8))     AS GROSS_QTY,
        CAST('/' + d.PART_ID + '/' AS nvarchar(4000)) AS PATH
    FROM demand_agg d

    UNION ALL

    -- Recursive: explode fabricated components that have masters
    SELECT
        parent.BOM_LEVEL + 1,
        parent.SITE_ID,
        parent.NEED_DATE,
        rq.PART_ID,
        CAST(parent.GROSS_QTY * (rq.CALC_QTY / NULLIF(wo.DESIRED_QTY, 0)) AS decimal(28,8)),
        CAST(parent.PATH + rq.PART_ID + '/' AS nvarchar(4000))
    FROM bom parent
    JOIN PART_SITE_VIEW psv
         ON  psv.PART_ID = parent.COMPONENT_PART_ID
         AND psv.SITE_ID = parent.SITE_ID
         AND psv.FABRICATED = 'Y'
         AND psv.ENGINEERING_MSTR IS NOT NULL
    JOIN WORK_ORDER wo
         ON  wo.TYPE     = 'M'
         AND wo.BASE_ID  = psv.PART_ID
         AND wo.LOT_ID   = CAST(psv.ENGINEERING_MSTR AS nvarchar(3))
         AND wo.SPLIT_ID = '0'
         AND wo.SUB_ID   = '0'
         AND wo.SITE_ID  = psv.SITE_ID
    JOIN REQUIREMENT rq
         ON  rq.WORKORDER_TYPE     = wo.TYPE
         AND rq.WORKORDER_BASE_ID  = wo.BASE_ID
         AND rq.WORKORDER_LOT_ID   = wo.LOT_ID
         AND rq.WORKORDER_SPLIT_ID = wo.SPLIT_ID
         AND rq.WORKORDER_SUB_ID   = wo.SUB_ID
    WHERE rq.PART_ID IS NOT NULL
      AND rq.STATUS  = 'U'
      AND parent.BOM_LEVEL < @MaxDepth
      AND CHARINDEX('/' + rq.PART_ID + '/', parent.PATH) = 0
),

-- ============================================================
-- 4) Bucket the gross requirements
--    Past-due demand (NEED_DATE < @WeekStart) lands in bucket 0.
-- ============================================================
gross_in_buckets AS (
    SELECT
        b.SITE_ID,
        b.COMPONENT_PART_ID                              AS PART_ID,
        CASE WHEN b.NEED_DATE < @WeekStart THEN 0
             ELSE DATEDIFF(week, @WeekStart, b.NEED_DATE)
        END                                              AS BUCKET_NO,
        SUM(b.GROSS_QTY)                                 AS GROSS_REQ
    FROM bom b
    WHERE
        -- past-due lands in bucket 0; future capped at horizon
        b.NEED_DATE < DATEADD(week, @Horizon, @WeekStart)
    GROUP BY
        b.SITE_ID, b.COMPONENT_PART_ID,
        CASE WHEN b.NEED_DATE < @WeekStart THEN 0
             ELSE DATEDIFF(week, @WeekStart, b.NEED_DATE)
        END
),

-- ============================================================
-- 5) Open PO supply (by DESIRED_RECV_DATE)
-- ============================================================
po_supply AS (
    SELECT
        p.SITE_ID,
        pl.PART_ID,
        CASE WHEN COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE) < @WeekStart THEN 0
             ELSE DATEDIFF(week, @WeekStart,
                           COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE))
        END                                              AS BUCKET_NO,
        SUM(pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY)        AS OPEN_PO_QTY
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl ON pl.PURC_ORDER_ID = p.ID
    WHERE ISNULL(p.STATUS, '')        NOT IN ('X','C')
      AND ISNULL(pl.LINE_STATUS, '')  NOT IN ('X','C')
      AND pl.PART_ID IS NOT NULL
      AND pl.ORDER_QTY > pl.TOTAL_RECEIVED_QTY
      AND COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE)
            < DATEADD(week, @Horizon, @WeekStart)
      AND (@Site IS NULL OR p.SITE_ID = @Site)
    GROUP BY
        p.SITE_ID, pl.PART_ID,
        CASE WHEN COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE) < @WeekStart THEN 0
             ELSE DATEDIFF(week, @WeekStart,
                           COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE))
        END
),

-- ============================================================
-- 6) Open work-order supply (fabricated parts produced by W-type WOs)
--    Outstanding qty = DESIRED_QTY - RECEIVED_QTY.
-- ============================================================
wo_supply AS (
    SELECT
        wo.SITE_ID,
        wo.PART_ID,
        CASE WHEN COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE) < @WeekStart THEN 0
             ELSE DATEDIFF(week, @WeekStart,
                           COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE))
        END                                              AS BUCKET_NO,
        SUM(wo.DESIRED_QTY - wo.RECEIVED_QTY)            AS OPEN_WO_QTY
    FROM WORK_ORDER wo
    WHERE wo.TYPE = 'W'                              -- exclude masters (TYPE='M')
      AND ISNULL(wo.STATUS, '') NOT IN ('X','C')
      AND wo.DESIRED_QTY > wo.RECEIVED_QTY
      AND wo.PART_ID IS NOT NULL
      AND COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE)
            < DATEADD(week, @Horizon, @WeekStart)
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
    GROUP BY
        wo.SITE_ID, wo.PART_ID,
        CASE WHEN COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE) < @WeekStart THEN 0
             ELSE DATEDIFF(week, @WeekStart,
                           COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE))
        END
),

-- ============================================================
-- 7) Planned order supply (Visual MRP output)
-- ============================================================
plan_supply AS (
    SELECT
        po.SITE_ID,
        po.PART_ID,
        CASE WHEN po.WANT_DATE < @WeekStart THEN 0
             ELSE DATEDIFF(week, @WeekStart, po.WANT_DATE)
        END                                              AS BUCKET_NO,
        SUM(po.ORDER_QTY)                                AS PLANNED_ORDER_QTY
    FROM PLANNED_ORDER po
    WHERE po.WANT_DATE IS NOT NULL
      AND po.WANT_DATE < DATEADD(week, @Horizon, @WeekStart)
      AND (@Site IS NULL OR po.SITE_ID = @Site)
    GROUP BY
        po.SITE_ID, po.PART_ID,
        CASE WHEN po.WANT_DATE < @WeekStart THEN 0
             ELSE DATEDIFF(week, @WeekStart, po.WANT_DATE)
        END
),

-- ============================================================
-- 8) All (site, part) pairs that have any activity in the horizon
-- ============================================================
parts_in_play AS (
    SELECT DISTINCT SITE_ID, PART_ID FROM gross_in_buckets
    UNION
    SELECT DISTINCT SITE_ID, PART_ID FROM po_supply
    UNION
    SELECT DISTINCT SITE_ID, PART_ID FROM wo_supply
    UNION
    SELECT DISTINCT SITE_ID, PART_ID FROM plan_supply
),

-- ============================================================
-- 9) Cross with the bucket spine, fill in gross/supply, compute net change
-- ============================================================
grid AS (
    SELECT
        pip.SITE_ID,
        pip.PART_ID,
        bk.BUCKET_NO,
        bk.BUCKET_START,
        bk.BUCKET_END,
        ISNULL(g.GROSS_REQ,            0) AS GROSS_REQ,
        ISNULL(po.OPEN_PO_QTY,         0) AS OPEN_PO_QTY,
        ISNULL(w.OPEN_WO_QTY,          0) AS OPEN_WO_QTY,
        ISNULL(pl.PLANNED_ORDER_QTY,   0) AS PLANNED_ORDER_QTY,
        ISNULL(po.OPEN_PO_QTY,         0)
          + ISNULL(w.OPEN_WO_QTY,      0)
          + ISNULL(pl.PLANNED_ORDER_QTY, 0)
          - ISNULL(g.GROSS_REQ,        0)  AS NET_CHANGE
    FROM parts_in_play pip
    CROSS JOIN buckets bk
    LEFT JOIN gross_in_buckets g
        ON g.SITE_ID = pip.SITE_ID AND g.PART_ID = pip.PART_ID AND g.BUCKET_NO = bk.BUCKET_NO
    LEFT JOIN po_supply po
        ON po.SITE_ID = pip.SITE_ID AND po.PART_ID = pip.PART_ID AND po.BUCKET_NO = bk.BUCKET_NO
    LEFT JOIN wo_supply w
        ON w.SITE_ID = pip.SITE_ID AND w.PART_ID = pip.PART_ID AND w.BUCKET_NO = bk.BUCKET_NO
    LEFT JOIN plan_supply pl
        ON pl.SITE_ID = pip.SITE_ID AND pl.PART_ID = pip.PART_ID AND pl.BUCKET_NO = bk.BUCKET_NO
)

-- ============================================================
-- 10) Final: running projected on-hand via self-join, NET_REQ on shortfall
-- ============================================================
SELECT
    g1.SITE_ID,
    g1.PART_ID,
    psv.DESCRIPTION,
    psv.STOCK_UM,
    psv.FABRICATED,
    psv.PURCHASED,
    CASE
        WHEN psv.PURCHASED  = 'Y' AND ISNULL(psv.FABRICATED,'N') <> 'Y' THEN 'BUY'
        WHEN psv.FABRICATED = 'Y'                                       THEN 'MAKE'
        WHEN psv.DETAIL_ONLY = 'Y'                                      THEN 'PHANTOM'
        ELSE 'OTHER'
    END AS MAKE_OR_BUY,
    psv.PLANNER_USER_ID,
    psv.BUYER_USER_ID,
    psv.PREF_VENDOR_ID,
    psv.ABC_CODE,
    psv.PLANNING_LEADTIME,
    psv.SAFETY_STOCK_QTY,
    psv.MINIMUM_ORDER_QTY,
    psv.MULTIPLE_ORDER_QTY,
    psv.FIXED_ORDER_QTY,
    ISNULL(psv.QTY_ON_HAND, 0)               AS STARTING_ON_HAND,

    g1.BUCKET_NO,
    g1.BUCKET_START,
    g1.BUCKET_END,

    g1.GROSS_REQ,
    g1.OPEN_PO_QTY,
    g1.OPEN_WO_QTY,
    g1.PLANNED_ORDER_QTY,
    (g1.OPEN_PO_QTY + g1.OPEN_WO_QTY + g1.PLANNED_ORDER_QTY) AS SCHEDULED_RECEIPTS,

    -- Cumulative net change at and before this bucket
    ISNULL(SUM(g2.NET_CHANGE), 0)            AS CUM_NET_CHANGE,

    -- Projected on-hand = starting on-hand + cumulative net change
    ISNULL(psv.QTY_ON_HAND, 0) + ISNULL(SUM(g2.NET_CHANGE), 0)
                                             AS PROJECTED_ON_HAND,

    -- Net requirement = how much short of safety stock we are after netting
    CASE
        WHEN ISNULL(psv.QTY_ON_HAND, 0) + ISNULL(SUM(g2.NET_CHANGE), 0)
             < ISNULL(psv.SAFETY_STOCK_QTY, 0)
        THEN ISNULL(psv.SAFETY_STOCK_QTY, 0)
             - (ISNULL(psv.QTY_ON_HAND, 0) + ISNULL(SUM(g2.NET_CHANGE), 0))
        ELSE 0
    END                                      AS NET_REQUIREMENT,

    CASE
        WHEN ISNULL(psv.QTY_ON_HAND, 0) + ISNULL(SUM(g2.NET_CHANGE), 0) < 0
            THEN 'SHORTAGE'
        WHEN ISNULL(psv.QTY_ON_HAND, 0) + ISNULL(SUM(g2.NET_CHANGE), 0)
             < ISNULL(psv.SAFETY_STOCK_QTY, 0)
            THEN 'BELOW_SAFETY'
        ELSE 'OK'
    END                                      AS BUCKET_STATUS

FROM grid g1
LEFT JOIN grid g2
    ON  g2.SITE_ID   = g1.SITE_ID
    AND g2.PART_ID   = g1.PART_ID
    AND g2.BUCKET_NO <= g1.BUCKET_NO
LEFT JOIN PART_SITE_VIEW psv
    ON  psv.SITE_ID = g1.SITE_ID
    AND psv.PART_ID = g1.PART_ID
GROUP BY
    g1.SITE_ID, g1.PART_ID,
    psv.DESCRIPTION, psv.STOCK_UM, psv.FABRICATED, psv.PURCHASED, psv.DETAIL_ONLY,
    psv.PLANNER_USER_ID, psv.BUYER_USER_ID, psv.PREF_VENDOR_ID, psv.ABC_CODE,
    psv.PLANNING_LEADTIME, psv.SAFETY_STOCK_QTY,
    psv.MINIMUM_ORDER_QTY, psv.MULTIPLE_ORDER_QTY, psv.FIXED_ORDER_QTY,
    psv.QTY_ON_HAND,
    g1.BUCKET_NO, g1.BUCKET_START, g1.BUCKET_END,
    g1.GROSS_REQ, g1.OPEN_PO_QTY, g1.OPEN_WO_QTY, g1.PLANNED_ORDER_QTY
ORDER BY
    g1.SITE_ID, g1.PART_ID, g1.BUCKET_NO
OPTION (MAXRECURSION 0);
