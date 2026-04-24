/*
===============================================================================
Query Name: make_plan_weekly.sql

Purpose:
    Companion to purchasing_plan.sql, for FABRICATED parts.

    For each fabricated part with a net requirement, recommend:
        * WO_RELEASE_DATE   = need date - PLANNING_LEADTIME (mfg cycle)
        * ORDER_QTY         = net req snapped to MOQ / multiple / fixed
        * COMPONENT_STATUS  = whether its 1-level-down components are on hand
                              to actually start the build

    Output is the production-planner equivalent of purchasing_plan.sql.

Grain:
    One row per (SITE_ID, FAB_PART, BUCKET_NO) where net requirement > 0.

Component readiness:
    Walks ONE level of the part's engineering-master REQUIREMENT (not the
    full BOM -- this is "can I start the WO?", not "is the entire chain
    available?"). Sub-assemblies that are themselves fabricated need their
    own row in this report (which they will, via the same BOM walk in the
    demand CTE).

    TOP3_SHORT_COMPONENTS = CSV of the 3 most-short level-1 components.
    READY_TO_RELEASE      = Y if all level-1 components have on-hand >=
                            (qty-per * order_qty), else N.

Action flag:
    RELEASE NOW          : recommend release date <= today AND ready
    RELEASE NOW (BLOCKED): recommend release date <= today AND not ready
    FUTURE RELEASE       : recommend release date in future
    BLOCKED              : not ready and components have no inbound supply
===============================================================================
*/

DECLARE @Site     nvarchar(15) = NULL;
DECLARE @Horizon  int          = 26;
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
    SELECT parent.BOM_LEVEL + 1, parent.SITE_ID, parent.NEED_DATE, rq.PART_ID,
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

projected_fab AS (
    SELECT g1.SITE_ID, g1.PART_ID, g1.BUCKET_NO, g1.BUCKET_START,
           psv.PLANNER_USER_ID,
           psv.PLANNING_LEADTIME,
           psv.SAFETY_STOCK_QTY,
           psv.MINIMUM_ORDER_QTY,
           psv.MULTIPLE_ORDER_QTY,
           psv.FIXED_ORDER_QTY,
           psv.UNIT_MATERIAL_COST,
           psv.DESCRIPTION,
           psv.ENGINEERING_MSTR,
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
    WHERE psv.FABRICATED = 'Y'
      AND psv.ENGINEERING_MSTR IS NOT NULL
    GROUP BY g1.SITE_ID, g1.PART_ID, g1.BUCKET_NO, g1.BUCKET_START,
             psv.PLANNER_USER_ID, psv.PLANNING_LEADTIME, psv.SAFETY_STOCK_QTY,
             psv.MINIMUM_ORDER_QTY, psv.MULTIPLE_ORDER_QTY, psv.FIXED_ORDER_QTY,
             psv.UNIT_MATERIAL_COST, psv.DESCRIPTION, psv.ENGINEERING_MSTR,
             psv.QTY_ON_HAND
),

-- Level-1 components for each fab part (one BOM step down)
l1_components AS (
    SELECT
        psv.SITE_ID,
        psv.PART_ID                                         AS FAB_PART_ID,
        rq.PART_ID                                          AS COMPONENT_PART_ID,
        rq.CALC_QTY / NULLIF(wo.DESIRED_QTY, 0)             AS QTY_PER,
        ISNULL(comp_psv.QTY_ON_HAND, 0)                     AS COMP_ON_HAND,
        comp_psv.PURCHASED                                  AS COMP_PURCHASED,
        comp_psv.FABRICATED                                 AS COMP_FABRICATED
    FROM PART_SITE_VIEW psv
    JOIN WORK_ORDER wo
        ON wo.TYPE='M' AND wo.BASE_ID=psv.PART_ID
        AND wo.LOT_ID=CAST(psv.ENGINEERING_MSTR AS nvarchar(3))
        AND wo.SPLIT_ID='0' AND wo.SUB_ID='0' AND wo.SITE_ID=psv.SITE_ID
    JOIN REQUIREMENT rq
        ON rq.WORKORDER_TYPE=wo.TYPE AND rq.WORKORDER_BASE_ID=wo.BASE_ID
        AND rq.WORKORDER_LOT_ID=wo.LOT_ID AND rq.WORKORDER_SPLIT_ID=wo.SPLIT_ID
        AND rq.WORKORDER_SUB_ID=wo.SUB_ID
    LEFT JOIN PART_SITE_VIEW comp_psv
        ON comp_psv.SITE_ID=psv.SITE_ID AND comp_psv.PART_ID=rq.PART_ID
    WHERE psv.FABRICATED='Y'
      AND psv.ENGINEERING_MSTR IS NOT NULL
      AND rq.PART_ID IS NOT NULL
      AND rq.STATUS='U'
      AND (@Site IS NULL OR psv.SITE_ID = @Site)
)

-- Final: rounded order qty + component readiness
SELECT
    p.SITE_ID,
    p.PART_ID                                          AS FAB_PART_ID,
    p.DESCRIPTION,
    p.PLANNER_USER_ID,
    p.BUCKET_NO,
    p.BUCKET_START                                     AS NEED_BY_DATE,
    DATEADD(day, -ISNULL(p.PLANNING_LEADTIME,0), p.BUCKET_START) AS RECOMMENDED_RELEASE_DATE,
    p.PLANNING_LEADTIME                                AS LT_DAYS,

    p.NET_REQUIREMENT                                  AS BASE_NET_REQ,

    CASE
        WHEN p.NET_REQUIREMENT <= 0 THEN 0
        WHEN p.FIXED_ORDER_QTY > 0
            THEN p.FIXED_ORDER_QTY * CEILING(p.NET_REQUIREMENT / p.FIXED_ORDER_QTY)
        WHEN p.MULTIPLE_ORDER_QTY > 0 AND p.MINIMUM_ORDER_QTY > 0
            THEN CASE WHEN p.NET_REQUIREMENT < p.MINIMUM_ORDER_QTY THEN p.MINIMUM_ORDER_QTY
                      ELSE p.MULTIPLE_ORDER_QTY * CEILING(p.NET_REQUIREMENT / p.MULTIPLE_ORDER_QTY)
                 END
        WHEN p.MULTIPLE_ORDER_QTY > 0
            THEN p.MULTIPLE_ORDER_QTY * CEILING(p.NET_REQUIREMENT / p.MULTIPLE_ORDER_QTY)
        WHEN p.MINIMUM_ORDER_QTY > 0 AND p.NET_REQUIREMENT < p.MINIMUM_ORDER_QTY
            THEN p.MINIMUM_ORDER_QTY
        ELSE p.NET_REQUIREMENT
    END                                                AS RECOMMENDED_BUILD_QTY,

    p.MINIMUM_ORDER_QTY,
    p.MULTIPLE_ORDER_QTY,
    p.FIXED_ORDER_QTY,

    -- Component readiness: how many builds the binding component supports
    rl.MIN_BUILDS_FROM_L1_COMPONENTS,
    rl.L1_COMPONENT_COUNT,
    rl.L1_COMPONENTS_AT_ZERO,

    -- Top-3 short L1 components
    sc.TOP3_SHORT_L1_COMPONENTS,

    CAST(p.NET_REQUIREMENT * ISNULL(p.UNIT_MATERIAL_COST,0) AS decimal(23,2)) AS BUILD_VALUE_AT_STD,

    CASE
        WHEN p.NET_REQUIREMENT <= 0 THEN 'OK'
        WHEN DATEADD(day, -ISNULL(p.PLANNING_LEADTIME,0), p.BUCKET_START) <= CAST(GETDATE() AS date)
             AND ISNULL(rl.MIN_BUILDS_FROM_L1_COMPONENTS, 0) >= p.NET_REQUIREMENT
            THEN 'RELEASE NOW'
        WHEN DATEADD(day, -ISNULL(p.PLANNING_LEADTIME,0), p.BUCKET_START) <= CAST(GETDATE() AS date)
             AND ISNULL(rl.MIN_BUILDS_FROM_L1_COMPONENTS, 0) > 0
            THEN 'RELEASE NOW (PARTIAL)'
        WHEN DATEADD(day, -ISNULL(p.PLANNING_LEADTIME,0), p.BUCKET_START) <= CAST(GETDATE() AS date)
            THEN 'RELEASE NOW (BLOCKED)'
        WHEN ISNULL(rl.MIN_BUILDS_FROM_L1_COMPONENTS, 0) = 0
            THEN 'BLOCKED'
        ELSE 'FUTURE RELEASE'
    END                                                AS ACTION_STATUS
FROM projected_fab p

-- Aggregate component readiness
LEFT JOIN (
    SELECT
        c.SITE_ID, c.FAB_PART_ID,
        MIN(CASE WHEN c.QTY_PER > 0 THEN c.COMP_ON_HAND / c.QTY_PER ELSE 0 END)
            AS MIN_BUILDS_FROM_L1_COMPONENTS,
        COUNT(*) AS L1_COMPONENT_COUNT,
        SUM(CASE WHEN c.COMP_ON_HAND <= 0 THEN 1 ELSE 0 END) AS L1_COMPONENTS_AT_ZERO
    FROM l1_components c
    GROUP BY c.SITE_ID, c.FAB_PART_ID
) rl
    ON rl.SITE_ID=p.SITE_ID AND rl.FAB_PART_ID=p.PART_ID

-- Top-3 short L1 components CSV
LEFT JOIN (
    SELECT
        s.SITE_ID, s.FAB_PART_ID,
        STUFF((
            SELECT ', ' + s2.COMPONENT_PART_ID
                   + ' (oh ' + CAST(CAST(s2.COMP_ON_HAND  AS decimal(20,2)) AS nvarchar(40))
                   + ' / qty_per ' + CAST(CAST(s2.QTY_PER AS decimal(20,4)) AS nvarchar(40))
                   + ')'
            FROM (
                SELECT c.*,
                       ROW_NUMBER() OVER (
                           PARTITION BY c.SITE_ID, c.FAB_PART_ID
                           ORDER BY CASE WHEN c.QTY_PER > 0 THEN c.COMP_ON_HAND / c.QTY_PER
                                         ELSE 0 END ASC,
                                    c.COMPONENT_PART_ID
                       ) AS RNK
                FROM l1_components c
            ) s2
            WHERE s2.SITE_ID=s.SITE_ID AND s2.FAB_PART_ID=s.FAB_PART_ID AND s2.RNK <= 3
            ORDER BY s2.RNK
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)'), 1, 2, '') AS TOP3_SHORT_L1_COMPONENTS
    FROM (SELECT DISTINCT SITE_ID, FAB_PART_ID FROM l1_components) s
) sc
    ON sc.SITE_ID=p.SITE_ID AND sc.FAB_PART_ID=p.PART_ID

WHERE p.NET_REQUIREMENT > 0
ORDER BY
    CASE
        WHEN DATEADD(day, -ISNULL(p.PLANNING_LEADTIME,0), p.BUCKET_START) < CAST(GETDATE() AS date) THEN 1
        ELSE 2
    END,
    p.BUCKET_NO,
    p.SITE_ID,
    p.PART_ID
OPTION (MAXRECURSION 0);
