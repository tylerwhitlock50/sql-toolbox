/*
===============================================================================
Query Name: purchasing_plan.sql

Purpose:
    Emit a time-phased PURCHASING PLAN for purchased parts. This is the
    actionable output the buying team can use to place orders week by week.

    For each (site, purchased part, bucket) where the projected position
    drops below safety stock, recommend a PO with:

        * RECOMMENDED_ORDER_DATE  -- need date minus the worst-case lead time
        * VENDOR_ID               -- preferred vendor or vendor-part fallback
        * ORDER_QTY               -- net requirement, snapped to MOQ/multiple
        * EXPECTED_UNIT_COST      -- weighted-avg of last 6 months of PO receipts
        * EXPECTED_TOTAL          -- ORDER_QTY * EXPECTED_UNIT_COST
        * COVERS_DEMAND_THROUGH   -- bucket end date

Lead time policy (locked in plan):
    Surface 3 lead-time signals side-by-side and use the WORST one for the
    order-by-date math (so we never under-buy time):

        LT_ERP_PART       PART_SITE_VIEW.PLANNING_LEADTIME
        LT_VENDOR_PART    VENDOR_PART.LEADTIME_BUFFER (preferred vendor)
        LT_ACTUAL_P50     median actual receipt-vs-PO-date over last 12mo

    EFFECTIVE_LT = max( ISNULL(LT_ERP_PART,0),
                        ISNULL(LT_VENDOR_PART,0),
                        ISNULL(LT_ACTUAL_P50,0) ).

Order qty policy:
    base_qty = NET_REQUIREMENT
    if FIXED_ORDER_QTY > 0  -> ceil(base / FIXED) * FIXED
    if MIN_ORDER_QTY  > 0   -> max(base_qty, MIN)
    if MULTIPLE_ORDER_QTY > 0 -> round-up to multiple
    if MAX_ORDER_QTY  > 0   -> capped (and we add a flag note)

Notes:
    * Output is one row per recommended PO (one bucket = one PO suggestion).
      A part with multiple buckets in shortfall will get one row per bucket.
    * Lead time math: RECOMMENDED_ORDER_DATE = BUCKET_START - EFFECTIVE_LT.
      If RECOMMENDED_ORDER_DATE is in the past, action_status = 'ORDER NOW
      (PAST DUE)'.
    * Self-contained: re-uses the same demand/BOM/supply CTEs as
      net_requirements_weekly.sql.
    * Compat-level safe: median is computed manually with ROW_NUMBER+COUNT.
===============================================================================
*/

DECLARE @Site               nvarchar(15) = NULL;
DECLARE @Horizon            int          = 26;
DECLARE @MaxDepth           int          = 20;
DECLARE @PriceLookbackMonths int         = 6;
DECLARE @LeadTimeLookbackMonths int      = 12;

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
    FROM CUST_ORDER_LINE col
    INNER JOIN CUSTOMER_ORDER co ON co.ID = col.CUST_ORDER_ID
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
         ON  psv.PART_ID = parent.COMPONENT_PART_ID AND psv.SITE_ID = parent.SITE_ID
         AND psv.FABRICATED = 'Y' AND psv.ENGINEERING_MSTR IS NOT NULL
    JOIN WORK_ORDER wo
         ON  wo.TYPE='M' AND wo.BASE_ID=psv.PART_ID
         AND wo.LOT_ID=CAST(psv.ENGINEERING_MSTR AS nvarchar(3))
         AND wo.SPLIT_ID='0' AND wo.SUB_ID='0' AND wo.SITE_ID=psv.SITE_ID
    JOIN REQUIREMENT rq
         ON  rq.WORKORDER_TYPE=wo.TYPE AND rq.WORKORDER_BASE_ID=wo.BASE_ID
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
      AND pl.PART_ID IS NOT NULL
      AND pl.ORDER_QTY > pl.TOTAL_RECEIVED_QTY
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
    WHERE wo.TYPE = 'W' AND ISNULL(wo.STATUS,'') NOT IN ('X','C')
      AND wo.DESIRED_QTY > wo.RECEIVED_QTY AND wo.PART_ID IS NOT NULL
      AND COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE)
            < DATEADD(week, @Horizon, @WeekStart)
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
    GROUP BY wo.SITE_ID, wo.PART_ID,
             CASE WHEN COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE) < @WeekStart THEN 0
                  ELSE DATEDIFF(week, @WeekStart,
                                COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE)) END
),

plan_supply AS (
    SELECT po.SITE_ID, po.PART_ID,
           CASE WHEN po.WANT_DATE < @WeekStart THEN 0
                ELSE DATEDIFF(week, @WeekStart, po.WANT_DATE) END AS BUCKET_NO,
           SUM(po.ORDER_QTY) AS PLANNED_ORDER_QTY
    FROM PLANNED_ORDER po
    WHERE po.WANT_DATE IS NOT NULL
      AND po.WANT_DATE < DATEADD(week, @Horizon, @WeekStart)
      AND (@Site IS NULL OR po.SITE_ID = @Site)
    GROUP BY po.SITE_ID, po.PART_ID,
             CASE WHEN po.WANT_DATE < @WeekStart THEN 0
                  ELSE DATEDIFF(week, @WeekStart, po.WANT_DATE) END
),

parts_in_play AS (
    SELECT DISTINCT SITE_ID, PART_ID FROM gross_in_buckets
    UNION SELECT DISTINCT SITE_ID, PART_ID FROM po_supply
    UNION SELECT DISTINCT SITE_ID, PART_ID FROM wo_supply
    UNION SELECT DISTINCT SITE_ID, PART_ID FROM plan_supply
),

grid AS (
    SELECT pip.SITE_ID, pip.PART_ID, bk.BUCKET_NO, bk.BUCKET_START, bk.BUCKET_END,
           ISNULL(g.GROSS_REQ,            0) AS GROSS_REQ,
           ISNULL(po.OPEN_PO_QTY,         0) AS OPEN_PO_QTY,
           ISNULL(w.OPEN_WO_QTY,          0) AS OPEN_WO_QTY,
           ISNULL(pl.PLANNED_ORDER_QTY,   0) AS PLANNED_ORDER_QTY,
           ISNULL(po.OPEN_PO_QTY,0) + ISNULL(w.OPEN_WO_QTY,0)
              + ISNULL(pl.PLANNED_ORDER_QTY,0) - ISNULL(g.GROSS_REQ,0) AS NET_CHANGE
    FROM parts_in_play pip
    CROSS JOIN buckets bk
    LEFT JOIN gross_in_buckets g
        ON g.SITE_ID=pip.SITE_ID AND g.PART_ID=pip.PART_ID AND g.BUCKET_NO=bk.BUCKET_NO
    LEFT JOIN po_supply po
        ON po.SITE_ID=pip.SITE_ID AND po.PART_ID=pip.PART_ID AND po.BUCKET_NO=bk.BUCKET_NO
    LEFT JOIN wo_supply w
        ON w.SITE_ID=pip.SITE_ID AND w.PART_ID=pip.PART_ID AND w.BUCKET_NO=bk.BUCKET_NO
    LEFT JOIN plan_supply pl
        ON pl.SITE_ID=pip.SITE_ID AND pl.PART_ID=pip.PART_ID AND pl.BUCKET_NO=bk.BUCKET_NO
),

-- ============================================================
-- Net requirements per bucket (with running on-hand from PSV)
-- Filtered to PURCHASED parts only -- buy plan is for buy parts.
-- ============================================================
projected AS (
    SELECT
        g1.SITE_ID, g1.PART_ID, g1.BUCKET_NO, g1.BUCKET_START, g1.BUCKET_END,
        g1.GROSS_REQ, g1.OPEN_PO_QTY, g1.OPEN_WO_QTY, g1.PLANNED_ORDER_QTY,
        ISNULL(psv.QTY_ON_HAND,0)        AS STARTING_ON_HAND,
        ISNULL(psv.SAFETY_STOCK_QTY,0)   AS SAFETY_STOCK_QTY,
        ISNULL(psv.MINIMUM_ORDER_QTY,0)  AS MOQ,
        ISNULL(psv.MULTIPLE_ORDER_QTY,0) AS MULT,
        ISNULL(psv.FIXED_ORDER_QTY,0)    AS FOQ,
        ISNULL(psv.MAXIMUM_ORDER_QTY,0)  AS MAX_OQ,
        psv.PLANNING_LEADTIME            AS LT_ERP_PART,
        psv.PREF_VENDOR_ID,
        psv.UNIT_MATERIAL_COST,
        psv.STOCK_UM,
        psv.DESCRIPTION,
        psv.PRODUCT_CODE,
        psv.COMMODITY_CODE,
        psv.BUYER_USER_ID,
        psv.PLANNER_USER_ID,
        psv.ABC_CODE,
        ISNULL(psv.QTY_ON_HAND,0) + ISNULL(SUM(g2.NET_CHANGE),0)
                                         AS PROJECTED_ON_HAND
    FROM grid g1
    LEFT JOIN grid g2
        ON  g2.SITE_ID=g1.SITE_ID AND g2.PART_ID=g1.PART_ID
        AND g2.BUCKET_NO <= g1.BUCKET_NO
    JOIN PART_SITE_VIEW psv
        ON psv.SITE_ID=g1.SITE_ID AND psv.PART_ID=g1.PART_ID
    WHERE psv.PURCHASED = 'Y'
      AND ISNULL(psv.FABRICATED,'N') <> 'Y'
    GROUP BY
        g1.SITE_ID, g1.PART_ID, g1.BUCKET_NO, g1.BUCKET_START, g1.BUCKET_END,
        g1.GROSS_REQ, g1.OPEN_PO_QTY, g1.OPEN_WO_QTY, g1.PLANNED_ORDER_QTY,
        psv.QTY_ON_HAND, psv.SAFETY_STOCK_QTY, psv.MINIMUM_ORDER_QTY,
        psv.MULTIPLE_ORDER_QTY, psv.FIXED_ORDER_QTY, psv.MAXIMUM_ORDER_QTY,
        psv.PLANNING_LEADTIME, psv.PREF_VENDOR_ID, psv.UNIT_MATERIAL_COST,
        psv.STOCK_UM, psv.DESCRIPTION, psv.PRODUCT_CODE, psv.COMMODITY_CODE,
        psv.BUYER_USER_ID, psv.PLANNER_USER_ID, psv.ABC_CODE
),

-- ============================================================
-- Recent PO receipts -> weighted-avg unit cost (last N months)
-- ============================================================
recent_receipts AS (
    SELECT
        it.PART_ID, it.SITE_ID,
        SUM(it.ACT_MATERIAL_COST) / NULLIF(SUM(it.QTY), 0) AS RECENT_WTD_AVG_UNIT_COST,
        SUM(it.QTY)                                        AS RECENT_QTY_RECEIVED,
        COUNT(*)                                           AS RECENT_RECEIPT_COUNT,
        MAX(it.TRANSACTION_DATE)                           AS LAST_RECEIPT_DATE
    FROM INVENTORY_TRANS it
    WHERE it.TYPE='I' AND it.CLASS='R'
      AND it.PURC_ORDER_ID IS NOT NULL
      AND it.QTY > 0 AND it.ACT_MATERIAL_COST > 0
      AND it.TRANSACTION_DATE >= DATEADD(month, -@PriceLookbackMonths, GETDATE())
      AND (@Site IS NULL OR it.SITE_ID = @Site)
    GROUP BY it.PART_ID, it.SITE_ID
),

-- ============================================================
-- Historical lead time per (site, part): median over last N months
-- Compat-safe manual median.
-- ============================================================
lt_observations AS (
    SELECT
        it.SITE_ID, it.PART_ID,
        DATEDIFF(day, p.ORDER_DATE, it.TRANSACTION_DATE) AS LT_DAYS,
        ROW_NUMBER() OVER (PARTITION BY it.SITE_ID, it.PART_ID
                           ORDER BY DATEDIFF(day, p.ORDER_DATE, it.TRANSACTION_DATE)) AS RN,
        COUNT(*)     OVER (PARTITION BY it.SITE_ID, it.PART_ID) AS CNT
    FROM INVENTORY_TRANS it
    INNER JOIN PURCHASE_ORDER p ON p.ID = it.PURC_ORDER_ID
    WHERE it.TYPE='I' AND it.CLASS='R'
      AND it.PURC_ORDER_ID IS NOT NULL
      AND it.PART_ID IS NOT NULL
      AND it.QTY > 0
      AND it.TRANSACTION_DATE >= DATEADD(month, -@LeadTimeLookbackMonths, GETDATE())
      AND p.ORDER_DATE IS NOT NULL
      AND DATEDIFF(day, p.ORDER_DATE, it.TRANSACTION_DATE) BETWEEN 0 AND 365
      AND (@Site IS NULL OR it.SITE_ID = @Site)
),
lt_p50 AS (
    SELECT SITE_ID, PART_ID,
           CAST(AVG(CAST(LT_DAYS AS decimal(10,2))) AS decimal(10,2)) AS LT_ACTUAL_P50
    FROM lt_observations
    WHERE RN IN ((CNT+1)/2, (CNT+2)/2)
    GROUP BY SITE_ID, PART_ID
),

-- ============================================================
-- Pick the preferred vendor and its LT buffer
-- ============================================================
preferred_vendor AS (
    SELECT
        psv.SITE_ID, psv.PART_ID,
        psv.PREF_VENDOR_ID,
        vp.LEADTIME_BUFFER AS LT_VENDOR_PART
    FROM PART_SITE_VIEW psv
    LEFT JOIN VENDOR_PART vp
        ON  vp.PART_ID   = psv.PART_ID
        AND vp.SITE_ID   = psv.SITE_ID
        AND vp.VENDOR_ID = psv.PREF_VENDOR_ID
    WHERE psv.PURCHASED = 'Y'
      AND ISNULL(psv.FABRICATED,'N') <> 'Y'
      AND (@Site IS NULL OR psv.SITE_ID = @Site)
),

-- ============================================================
-- Final assembly: only buckets that need a buy
-- ============================================================
buy_buckets AS (
    SELECT
        p.*,
        rr.RECENT_WTD_AVG_UNIT_COST,
        rr.RECENT_QTY_RECEIVED,
        rr.RECENT_RECEIPT_COUNT,
        rr.LAST_RECEIPT_DATE,
        pv.LT_VENDOR_PART,
        lp.LT_ACTUAL_P50,
        v.NAME AS VENDOR_NAME,
        v.BUYER AS VENDOR_BUYER,

        -- Effective lead time = worst (largest) of the three
        CASE
            WHEN ISNULL(p.LT_ERP_PART,0)
                 >= ISNULL(pv.LT_VENDOR_PART,0)
             AND ISNULL(p.LT_ERP_PART,0)
                 >= ISNULL(lp.LT_ACTUAL_P50,0)
                THEN ISNULL(p.LT_ERP_PART,0)
            WHEN ISNULL(pv.LT_VENDOR_PART,0)
                 >= ISNULL(lp.LT_ACTUAL_P50,0)
                THEN ISNULL(pv.LT_VENDOR_PART,0)
            ELSE
                CAST(ISNULL(lp.LT_ACTUAL_P50,0) AS int)
        END AS EFFECTIVE_LT_DAYS,

        -- Net requirement = how much we need above safety stock at end of bucket
        CASE
            WHEN p.PROJECTED_ON_HAND < p.SAFETY_STOCK_QTY
                THEN p.SAFETY_STOCK_QTY - p.PROJECTED_ON_HAND
            ELSE 0
        END AS NET_REQUIREMENT
    FROM projected p
    LEFT JOIN preferred_vendor pv
        ON pv.SITE_ID=p.SITE_ID AND pv.PART_ID=p.PART_ID
    LEFT JOIN VENDOR v
        ON v.ID = p.PREF_VENDOR_ID
    LEFT JOIN lt_p50 lp
        ON lp.SITE_ID=p.SITE_ID AND lp.PART_ID=p.PART_ID
    LEFT JOIN recent_receipts rr
        ON rr.SITE_ID=p.SITE_ID AND rr.PART_ID=p.PART_ID
)

SELECT
    b.SITE_ID,
    b.PART_ID,
    b.DESCRIPTION,
    b.STOCK_UM,
    b.PRODUCT_CODE,
    b.COMMODITY_CODE,
    b.ABC_CODE,
    b.BUYER_USER_ID,
    b.PLANNER_USER_ID,

    b.BUCKET_NO,
    b.BUCKET_START                         AS NEED_BY_DATE,
    b.BUCKET_END                           AS COVERS_DEMAND_THROUGH,

    b.GROSS_REQ                            AS BUCKET_GROSS_REQ,
    b.OPEN_PO_QTY                          AS BUCKET_OPEN_PO_QTY,
    b.OPEN_WO_QTY                          AS BUCKET_OPEN_WO_QTY,
    b.PLANNED_ORDER_QTY                    AS BUCKET_PLANNED_QTY,
    b.PROJECTED_ON_HAND                    AS PROJECTED_ON_HAND_END_OF_BUCKET,
    b.SAFETY_STOCK_QTY,
    b.NET_REQUIREMENT                      AS BASE_NET_REQ,

    -- Round-up / MOQ / multiple logic
    CASE
        WHEN b.NET_REQUIREMENT <= 0 THEN 0
        WHEN b.FOQ > 0
            THEN b.FOQ
                 * CEILING(b.NET_REQUIREMENT / b.FOQ)
        WHEN b.MULT > 0 AND b.MOQ > 0
            THEN CASE WHEN b.NET_REQUIREMENT < b.MOQ THEN b.MOQ
                      ELSE b.MULT
                           * CEILING(b.NET_REQUIREMENT / b.MULT)
                 END
        WHEN b.MULT > 0
            THEN b.MULT
                 * CEILING(b.NET_REQUIREMENT / b.MULT)
        WHEN b.MOQ > 0 AND b.NET_REQUIREMENT < b.MOQ
            THEN b.MOQ
        ELSE b.NET_REQUIREMENT
    END AS RECOMMENDED_ORDER_QTY,

    b.MOQ                                  AS MIN_ORDER_QTY,
    b.MULT                                 AS MULTIPLE_ORDER_QTY,
    b.FOQ                                  AS FIXED_ORDER_QTY,
    b.MAX_OQ                               AS MAX_ORDER_QTY,

    -- Vendor & sourcing
    b.PREF_VENDOR_ID                       AS VENDOR_ID,
    b.VENDOR_NAME,
    b.VENDOR_BUYER,

    -- Lead time (3 sources side-by-side + the one we used)
    b.LT_ERP_PART,
    b.LT_VENDOR_PART,
    b.LT_ACTUAL_P50,
    b.EFFECTIVE_LT_DAYS,
    DATEADD(day, -b.EFFECTIVE_LT_DAYS, b.BUCKET_START) AS RECOMMENDED_ORDER_DATE,

    -- Pricing (recent weighted-avg vs std)
    b.RECENT_WTD_AVG_UNIT_COST,
    b.UNIT_MATERIAL_COST                   AS STD_UNIT_MATERIAL_COST,
    CASE
        WHEN b.UNIT_MATERIAL_COST IS NULL OR b.UNIT_MATERIAL_COST = 0 THEN NULL
        WHEN b.RECENT_WTD_AVG_UNIT_COST IS NULL THEN NULL
        ELSE CAST((b.RECENT_WTD_AVG_UNIT_COST - b.UNIT_MATERIAL_COST)
                  / b.UNIT_MATERIAL_COST * 100 AS decimal(10,2))
    END AS RECENT_VS_STD_PCT,
    b.LAST_RECEIPT_DATE,
    b.RECENT_RECEIPT_COUNT,
    b.RECENT_QTY_RECEIVED,

    -- Expected $$
    CAST(
        CASE
            WHEN b.NET_REQUIREMENT <= 0 THEN 0
            WHEN b.FOQ > 0
                THEN b.FOQ * CEILING(b.NET_REQUIREMENT / b.FOQ)
            WHEN b.MULT > 0 AND b.MOQ > 0
                THEN CASE WHEN b.NET_REQUIREMENT < b.MOQ THEN b.MOQ
                          ELSE b.MULT * CEILING(b.NET_REQUIREMENT / b.MULT) END
            WHEN b.MULT > 0
                THEN b.MULT * CEILING(b.NET_REQUIREMENT / b.MULT)
            WHEN b.MOQ > 0 AND b.NET_REQUIREMENT < b.MOQ THEN b.MOQ
            ELSE b.NET_REQUIREMENT
        END
        * COALESCE(b.RECENT_WTD_AVG_UNIT_COST, b.UNIT_MATERIAL_COST, 0)
    AS decimal(23,4)) AS EXPECTED_TOTAL_COST,

    -- Action flag
    CASE
        WHEN b.NET_REQUIREMENT <= 0
            THEN 'OK'
        WHEN DATEADD(day, -b.EFFECTIVE_LT_DAYS, b.BUCKET_START) < CAST(GETDATE() AS date)
            THEN 'ORDER NOW (PAST DUE)'
        WHEN b.PREF_VENDOR_ID IS NULL
            THEN 'NO PREFERRED VENDOR'
        ELSE 'PLAN ORDER'
    END AS ACTION_STATUS

FROM buy_buckets b
WHERE b.NET_REQUIREMENT > 0
ORDER BY
    CASE
        WHEN DATEADD(day, -b.EFFECTIVE_LT_DAYS, b.BUCKET_START) < CAST(GETDATE() AS date) THEN 1
        ELSE 2
    END,
    b.BUCKET_NO,
    b.SITE_ID,
    b.PART_ID
OPTION (MAXRECURSION 0);
