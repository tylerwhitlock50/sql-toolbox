/*
===============================================================================
Query Name: purchasing_plan_by_buyer_summary.sql

Purpose:
    Roll up purchasing_plan.sql to BUYER × WEEK so each buyer can see their
    weekly action backlog at a glance:

        * # parts to order this week
        * $ to spend at std cost
        * # past-due actions (recommended-order-date already gone)
        * # parts missing a preferred vendor (sourcing risk)
        * Top 5 dollar parts in the week

    Designed for the buying team's Monday standup.

Grain:
    One row per (SITE_ID, BUYER_USER_ID, BUCKET_NO) covering @Horizon
    weeks. Adds a synthetic "_TOTAL_" bucket per buyer.

Differences vs purchasing_plan.sql:
    * Uses PLANNING_LEADTIME only (not the 3-source effective LT) -- this
      is a summary, not actionable PO suggestions.
    * Uses std unit material cost ($ at std), not historical PO weighted
      avg. Run purchasing_plan.sql for the precise $ per recommended PO.
    * Does NOT round to MOQ / multiple / fixed -- it reports raw net
      requirement. Order-qty rounding is the operational query's job.

Notes:
    Compat-safe. No DATEFROMPARTS / PERCENTILE_CONT. STUFF + FOR XML for
    top-5 parts CSV.
===============================================================================
*/

DECLARE @Site     nvarchar(15) = NULL;
DECLARE @Horizon  int          = 12;
DECLARE @MaxDepth int          = 20;

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

-- Demand union (sales backorder + master schedule + forecast)
demand AS (
    SELECT col.SITE_ID, col.PART_ID,
           COALESCE(col.PROMISE_DATE, col.DESIRED_SHIP_DATE, co.DESIRED_SHIP_DATE) AS NEED_DATE,
           col.ORDER_QTY - col.TOTAL_SHIPPED_QTY AS DEMAND_QTY
    FROM CUST_ORDER_LINE col INNER JOIN CUSTOMER_ORDER co ON co.ID = col.CUST_ORDER_ID
    WHERE co.STATUS IN ('R','F') AND col.LINE_STATUS='A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY AND col.PART_ID IS NOT NULL
      AND (@Site IS NULL OR col.SITE_ID = @Site)
    UNION ALL
    SELECT ms.SITE_ID, ms.PART_ID, ms.WANT_DATE, ms.ORDER_QTY
    FROM MASTER_SCHEDULE ms
    WHERE ms.ORDER_QTY > 0 AND (@Site IS NULL OR ms.SITE_ID = @Site)
    UNION ALL
    SELECT df.SITE_ID, df.PART_ID, df.REQUIRED_DATE, df.REQUIRED_QTY
    FROM DEMAND_FORECAST df
    WHERE df.REQUIRED_QTY > 0 AND (@Site IS NULL OR df.SITE_ID = @Site)
),
demand_agg AS (
    SELECT SITE_ID, PART_ID, NEED_DATE, SUM(DEMAND_QTY) AS DEMAND_QTY
    FROM demand GROUP BY SITE_ID, PART_ID, NEED_DATE
),

bom AS (
    SELECT CAST(0 AS int) AS BOM_LEVEL, d.SITE_ID, d.NEED_DATE,
           d.PART_ID AS COMPONENT_PART_ID,
           CAST(d.DEMAND_QTY AS decimal(28,8)) AS GROSS_QTY,
           CAST('/' + d.PART_ID + '/' AS nvarchar(4000)) AS PATH
    FROM demand_agg d
    UNION ALL
    SELECT parent.BOM_LEVEL + 1, parent.SITE_ID, parent.NEED_DATE,
           rq.PART_ID,
           CAST(parent.GROSS_QTY * (rq.CALC_QTY / NULLIF(wo.DESIRED_QTY,0)) AS decimal(28,8)),
           CAST(parent.PATH + rq.PART_ID + '/' AS nvarchar(4000))
    FROM bom parent
    JOIN PART_SITE_VIEW psv
         ON psv.PART_ID=parent.COMPONENT_PART_ID AND psv.SITE_ID=parent.SITE_ID
         AND psv.FABRICATED='Y' AND psv.ENGINEERING_MSTR IS NOT NULL
    JOIN WORK_ORDER wo
         ON wo.TYPE='M' AND wo.BASE_ID=psv.PART_ID
         AND wo.LOT_ID=CAST(psv.ENGINEERING_MSTR AS nvarchar(3))
         AND wo.SPLIT_ID='0' AND wo.SUB_ID='0' AND wo.SITE_ID=psv.SITE_ID
    JOIN REQUIREMENT rq
         ON rq.WORKORDER_TYPE=wo.TYPE AND rq.WORKORDER_BASE_ID=wo.BASE_ID
         AND rq.WORKORDER_LOT_ID=wo.LOT_ID AND rq.WORKORDER_SPLIT_ID=wo.SPLIT_ID
         AND rq.WORKORDER_SUB_ID=wo.SUB_ID
    WHERE rq.PART_ID IS NOT NULL AND rq.STATUS='U'
      AND parent.BOM_LEVEL < @MaxDepth
      AND CHARINDEX('/' + rq.PART_ID + '/', parent.PATH) = 0
),

gross_in_buckets AS (
    SELECT b.SITE_ID, b.COMPONENT_PART_ID AS PART_ID,
           CASE WHEN b.NEED_DATE < @WeekStart THEN 0
                ELSE DATEDIFF(week, @WeekStart, b.NEED_DATE) END AS BUCKET_NO,
           SUM(b.GROSS_QTY) AS GROSS_REQ
    FROM bom b
    WHERE b.NEED_DATE < DATEADD(week, @Horizon, @WeekStart)
    GROUP BY b.SITE_ID, b.COMPONENT_PART_ID,
             CASE WHEN b.NEED_DATE < @WeekStart THEN 0
                  ELSE DATEDIFF(week, @WeekStart, b.NEED_DATE) END
),

po_supply AS (
    SELECT p.SITE_ID, pl.PART_ID,
           CASE WHEN COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE) < @WeekStart THEN 0
                ELSE DATEDIFF(week, @WeekStart,
                              COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE)) END AS BUCKET_NO,
           SUM(pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY) AS OPEN_PO_QTY
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl ON pl.PURC_ORDER_ID = p.ID
    WHERE ISNULL(p.STATUS,'') NOT IN ('X','C')
      AND ISNULL(pl.LINE_STATUS,'') NOT IN ('X','C')
      AND pl.PART_ID IS NOT NULL AND pl.ORDER_QTY > pl.TOTAL_RECEIVED_QTY
      AND COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE)
            < DATEADD(week, @Horizon, @WeekStart)
      AND (@Site IS NULL OR p.SITE_ID = @Site)
    GROUP BY p.SITE_ID, pl.PART_ID,
             CASE WHEN COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE) < @WeekStart THEN 0
                  ELSE DATEDIFF(week, @WeekStart,
                                COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE)) END
),

wo_supply AS (
    SELECT wo.SITE_ID, wo.PART_ID,
           CASE WHEN COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE) < @WeekStart THEN 0
                ELSE DATEDIFF(week, @WeekStart,
                              COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE)) END AS BUCKET_NO,
           SUM(wo.DESIRED_QTY - wo.RECEIVED_QTY) AS OPEN_WO_QTY
    FROM WORK_ORDER wo
    WHERE wo.TYPE='W' AND ISNULL(wo.STATUS,'') NOT IN ('X','C')
      AND wo.DESIRED_QTY > wo.RECEIVED_QTY AND wo.PART_ID IS NOT NULL
      AND COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE)
            < DATEADD(week, @Horizon, @WeekStart)
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
    GROUP BY wo.SITE_ID, wo.PART_ID,
             CASE WHEN COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE) < @WeekStart THEN 0
                  ELSE DATEDIFF(week, @WeekStart,
                                COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE)) END
),

parts_in_play AS (
    SELECT DISTINCT SITE_ID, PART_ID FROM gross_in_buckets
    UNION SELECT DISTINCT SITE_ID, PART_ID FROM po_supply
    UNION SELECT DISTINCT SITE_ID, PART_ID FROM wo_supply
),

grid AS (
    SELECT pip.SITE_ID, pip.PART_ID, bk.BUCKET_NO, bk.BUCKET_START,
           ISNULL(g.GROSS_REQ,0) AS GROSS_REQ,
           ISNULL(po.OPEN_PO_QTY,0) AS OPEN_PO_QTY,
           ISNULL(w.OPEN_WO_QTY,0) AS OPEN_WO_QTY,
           ISNULL(po.OPEN_PO_QTY,0)+ISNULL(w.OPEN_WO_QTY,0)-ISNULL(g.GROSS_REQ,0) AS NET_CHANGE
    FROM parts_in_play pip
    CROSS JOIN buckets bk
    LEFT JOIN gross_in_buckets g
        ON g.SITE_ID=pip.SITE_ID AND g.PART_ID=pip.PART_ID AND g.BUCKET_NO=bk.BUCKET_NO
    LEFT JOIN po_supply po
        ON po.SITE_ID=pip.SITE_ID AND po.PART_ID=pip.PART_ID AND po.BUCKET_NO=bk.BUCKET_NO
    LEFT JOIN wo_supply w
        ON w.SITE_ID=pip.SITE_ID AND w.PART_ID=pip.PART_ID AND w.BUCKET_NO=bk.BUCKET_NO
),

projected AS (
    SELECT g1.SITE_ID, g1.PART_ID, g1.BUCKET_NO, g1.BUCKET_START,
           psv.BUYER_USER_ID,
           psv.PREF_VENDOR_ID,
           psv.UNIT_MATERIAL_COST,
           psv.PLANNING_LEADTIME,
           psv.SAFETY_STOCK_QTY,
           psv.DESCRIPTION,
           CASE
               WHEN ISNULL(psv.QTY_ON_HAND,0) + ISNULL(SUM(g2.NET_CHANGE),0)
                    < ISNULL(psv.SAFETY_STOCK_QTY,0)
               THEN ISNULL(psv.SAFETY_STOCK_QTY,0)
                    - (ISNULL(psv.QTY_ON_HAND,0) + ISNULL(SUM(g2.NET_CHANGE),0))
               ELSE 0
           END AS NET_REQUIREMENT
    FROM grid g1
    LEFT JOIN grid g2
        ON g2.SITE_ID=g1.SITE_ID AND g2.PART_ID=g1.PART_ID
        AND g2.BUCKET_NO <= g1.BUCKET_NO
    JOIN PART_SITE_VIEW psv
        ON psv.SITE_ID=g1.SITE_ID AND psv.PART_ID=g1.PART_ID
    WHERE psv.PURCHASED='Y' AND ISNULL(psv.FABRICATED,'N')<>'Y'
    GROUP BY g1.SITE_ID, g1.PART_ID, g1.BUCKET_NO, g1.BUCKET_START,
             psv.BUYER_USER_ID, psv.PREF_VENDOR_ID, psv.UNIT_MATERIAL_COST,
             psv.PLANNING_LEADTIME, psv.SAFETY_STOCK_QTY, psv.DESCRIPTION,
             psv.QTY_ON_HAND
),

-- Action records (only rows that need a buy)
actions AS (
    SELECT
        p.SITE_ID,
        ISNULL(p.BUYER_USER_ID, '_UNASSIGNED_') AS BUYER_USER_ID,
        p.BUCKET_NO,
        p.BUCKET_START                                                AS NEED_BY_DATE,
        DATEADD(day, -ISNULL(p.PLANNING_LEADTIME,0), p.BUCKET_START)  AS RECOMMENDED_ORDER_DATE,
        p.PART_ID,
        p.DESCRIPTION,
        p.PREF_VENDOR_ID,
        p.NET_REQUIREMENT,
        CAST(p.NET_REQUIREMENT * ISNULL(p.UNIT_MATERIAL_COST,0) AS decimal(23,2)) AS LINE_VALUE_AT_STD
    FROM projected p
    WHERE p.NET_REQUIREMENT > 0
),

-- Top-5 parts CSV per buyer × bucket
top_parts_ranked AS (
    SELECT
        a.SITE_ID, a.BUYER_USER_ID, a.BUCKET_NO,
        a.PART_ID, a.LINE_VALUE_AT_STD,
        ROW_NUMBER() OVER (
            PARTITION BY a.SITE_ID, a.BUYER_USER_ID, a.BUCKET_NO
            ORDER BY a.LINE_VALUE_AT_STD DESC, a.PART_ID
        ) AS RNK
    FROM actions a
),
top_parts_csv AS (
    SELECT
        t.SITE_ID, t.BUYER_USER_ID, t.BUCKET_NO,
        STUFF((
            SELECT ', ' + t2.PART_ID
                   + ' ($' + CAST(CAST(t2.LINE_VALUE_AT_STD AS decimal(15,0)) AS nvarchar(20)) + ')'
            FROM top_parts_ranked t2
            WHERE t2.SITE_ID=t.SITE_ID AND t2.BUYER_USER_ID=t.BUYER_USER_ID
              AND t2.BUCKET_NO=t.BUCKET_NO AND t2.RNK <= 5
            ORDER BY t2.RNK
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)'), 1, 2, '') AS TOP5_PARTS
    FROM (SELECT DISTINCT SITE_ID, BUYER_USER_ID, BUCKET_NO FROM top_parts_ranked) t
),

-- Per buyer × bucket aggregate
per_bucket AS (
    SELECT
        a.SITE_ID,
        a.BUYER_USER_ID,
        a.BUCKET_NO,
        MIN(a.NEED_BY_DATE)                                           AS BUCKET_START,
        COUNT(DISTINCT a.PART_ID)                                     AS PARTS_TO_ORDER,
        SUM(CASE WHEN a.RECOMMENDED_ORDER_DATE < CAST(GETDATE() AS date)
                 THEN 1 ELSE 0 END)                                   AS PARTS_PAST_DUE,
        SUM(CASE WHEN a.PREF_VENDOR_ID IS NULL THEN 1 ELSE 0 END)     AS PARTS_NO_VENDOR,
        SUM(a.NET_REQUIREMENT)                                        AS TOTAL_QTY,
        SUM(a.LINE_VALUE_AT_STD)                                      AS TOTAL_VALUE_AT_STD,
        SUM(CASE WHEN a.RECOMMENDED_ORDER_DATE < CAST(GETDATE() AS date)
                 THEN a.LINE_VALUE_AT_STD ELSE 0 END)                 AS PAST_DUE_VALUE_AT_STD
    FROM actions a
    GROUP BY a.SITE_ID, a.BUYER_USER_ID, a.BUCKET_NO
)

SELECT
    pb.SITE_ID,
    pb.BUYER_USER_ID,
    pb.BUCKET_NO,
    pb.BUCKET_START,
    pb.PARTS_TO_ORDER,
    pb.PARTS_PAST_DUE,
    pb.PARTS_NO_VENDOR,
    CAST(pb.TOTAL_QTY            AS decimal(20,2)) AS TOTAL_QTY,
    CAST(pb.TOTAL_VALUE_AT_STD   AS decimal(23,2)) AS TOTAL_VALUE_AT_STD,
    CAST(pb.PAST_DUE_VALUE_AT_STD AS decimal(23,2)) AS PAST_DUE_VALUE_AT_STD,
    tp.TOP5_PARTS,
    CASE
        WHEN pb.PARTS_PAST_DUE > 0   THEN 'PAST DUE ACTION'
        WHEN pb.PARTS_NO_VENDOR > 0  THEN 'SOURCING NEEDED'
        WHEN pb.PARTS_TO_ORDER > 10  THEN 'HEAVY WEEK'
        ELSE                              'OK'
    END AS BUCKET_FLAG
FROM per_bucket pb
LEFT JOIN top_parts_csv tp
    ON tp.SITE_ID=pb.SITE_ID AND tp.BUYER_USER_ID=pb.BUYER_USER_ID
   AND tp.BUCKET_NO=pb.BUCKET_NO

UNION ALL

-- Per-buyer "_TOTAL_" rollup row across the horizon
SELECT
    SITE_ID, BUYER_USER_ID, -1, NULL,
    SUM(PARTS_TO_ORDER), SUM(PARTS_PAST_DUE), SUM(PARTS_NO_VENDOR),
    CAST(SUM(TOTAL_QTY)            AS decimal(20,2)),
    CAST(SUM(TOTAL_VALUE_AT_STD)   AS decimal(23,2)),
    CAST(SUM(PAST_DUE_VALUE_AT_STD) AS decimal(23,2)),
    CAST('(rollup)' AS nvarchar(max)),
    CASE WHEN SUM(PARTS_PAST_DUE) > 0 THEN 'PAST DUE ACTION' ELSE 'OK' END
FROM per_bucket
GROUP BY SITE_ID, BUYER_USER_ID

ORDER BY
    SITE_ID,
    BUYER_USER_ID,
    BUCKET_NO    -- -1 sorts first, giving the rollup row at the top of each buyer block
OPTION (MAXRECURSION 0);
