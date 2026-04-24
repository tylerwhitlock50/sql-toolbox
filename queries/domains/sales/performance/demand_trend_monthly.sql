/*
===============================================================================
Query Name: demand_trend_monthly.sql

Purpose:
    Show monthly sales velocity per part with trend signals so the
    forecasting team can:
        * spot rising / falling demand
        * tune master schedule and forecast
        * reclass parts (Pareto ABC by trailing-12 revenue)
        * find new parts and dying parts

Grain:
    One row per (SITE_ID, PART_ID, YEAR_MONTH) for any month in the
    lookback window with a shipment.
    Trend signals (T3, T6, T12 averages, MoM, YoY, growth flag,
    Pareto ABC) are repeated on each row so any month can be analyzed
    in isolation.

Source:
    CUST_LINE_DEL (delivery schedule with ACTUAL_SHIP_DATE) joined back
    to CUST_ORDER_LINE for unit price. This is the truth of WHAT shipped
    WHEN, regardless of when the order was booked.

Notes:
    Compat-safe (no DATEFROMPARTS / PERCENTILE_CONT / SUM OVER frames).
    Trailing averages use a self-join across the prior 11 months.
    Pareto ABC: rank parts by trailing-12 revenue, A = top 80%, B = next
    15%, C = bottom 5%.
===============================================================================
*/

DECLARE @Site            nvarchar(15) = NULL;
DECLARE @LookbackMonths  int          = 36;

;WITH shipments AS (
    SELECT
        col.SITE_ID,
        col.PART_ID,
        DATEADD(month, DATEDIFF(month, 0, cld.ACTUAL_SHIP_DATE), 0) AS YEAR_MONTH,
        cld.SHIPPED_QTY                                             AS QTY,
        cld.SHIPPED_QTY * col.UNIT_PRICE                            AS REVENUE,
        col.CUST_ORDER_ID                                           AS SO_ID,
        co.CUSTOMER_ID
    FROM CUST_LINE_DEL cld
    INNER JOIN CUST_ORDER_LINE col
        ON  col.CUST_ORDER_ID = cld.CUST_ORDER_ID
        AND col.LINE_NO       = cld.CUST_ORDER_LINE_NO
    INNER JOIN CUSTOMER_ORDER co ON co.ID = col.CUST_ORDER_ID
    WHERE cld.ACTUAL_SHIP_DATE IS NOT NULL
      AND cld.SHIPPED_QTY > 0
      AND col.PART_ID IS NOT NULL
      AND cld.ACTUAL_SHIP_DATE >= DATEADD(month, -@LookbackMonths, GETDATE())
      AND (@Site IS NULL OR col.SITE_ID = @Site)
),

monthly AS (
    SELECT
        SITE_ID, PART_ID, YEAR_MONTH,
        SUM(QTY)                          AS QTY_SHIPPED,
        SUM(REVENUE)                      AS REVENUE_SHIPPED,
        COUNT(DISTINCT SO_ID)             AS DISTINCT_SOS,
        COUNT(DISTINCT CUSTOMER_ID)       AS DISTINCT_CUSTOMERS,
        COUNT(*)                          AS DELIVERY_LINE_COUNT
    FROM shipments
    GROUP BY SITE_ID, PART_ID, YEAR_MONTH
),

ordered AS (
    SELECT
        m.*,
        ROW_NUMBER() OVER (PARTITION BY m.SITE_ID, m.PART_ID ORDER BY m.YEAR_MONTH) AS RN
    FROM monthly m
),

-- Trailing-N averages: for each (part, month), avg qty/revenue over the
-- last N months (inclusive). Uses self-join.
trailing AS (
    SELECT
        o1.SITE_ID, o1.PART_ID, o1.YEAR_MONTH,

        SUM(CASE WHEN o2.YEAR_MONTH BETWEEN DATEADD(month, -2,  o1.YEAR_MONTH) AND o1.YEAR_MONTH
                 THEN o2.QTY_SHIPPED ELSE 0 END) / 3.0          AS T3_AVG_QTY,
        SUM(CASE WHEN o2.YEAR_MONTH BETWEEN DATEADD(month, -2,  o1.YEAR_MONTH) AND o1.YEAR_MONTH
                 THEN o2.REVENUE_SHIPPED ELSE 0 END) / 3.0       AS T3_AVG_REVENUE,

        SUM(CASE WHEN o2.YEAR_MONTH BETWEEN DATEADD(month, -5,  o1.YEAR_MONTH) AND o1.YEAR_MONTH
                 THEN o2.QTY_SHIPPED ELSE 0 END) / 6.0          AS T6_AVG_QTY,

        SUM(CASE WHEN o2.YEAR_MONTH BETWEEN DATEADD(month, -11, o1.YEAR_MONTH) AND o1.YEAR_MONTH
                 THEN o2.QTY_SHIPPED ELSE 0 END) / 12.0         AS T12_AVG_QTY,
        SUM(CASE WHEN o2.YEAR_MONTH BETWEEN DATEADD(month, -11, o1.YEAR_MONTH) AND o1.YEAR_MONTH
                 THEN o2.REVENUE_SHIPPED ELSE 0 END)             AS T12_REVENUE,
        STDEV(CASE WHEN o2.YEAR_MONTH BETWEEN DATEADD(month, -11, o1.YEAR_MONTH) AND o1.YEAR_MONTH
                   THEN o2.QTY_SHIPPED ELSE NULL END)            AS T12_STDDEV_QTY,
        SUM(CASE WHEN o2.YEAR_MONTH BETWEEN DATEADD(month, -11, o1.YEAR_MONTH) AND o1.YEAR_MONTH
                 THEN 1 ELSE 0 END)                              AS T12_MONTHS_WITH_DATA
    FROM ordered o1
    -- Self-join across the same part to gather trailing window
    LEFT JOIN ordered o2
        ON  o2.SITE_ID = o1.SITE_ID AND o2.PART_ID = o1.PART_ID
        AND o2.YEAR_MONTH <= o1.YEAR_MONTH
    GROUP BY o1.SITE_ID, o1.PART_ID, o1.YEAR_MONTH
),

-- Latest-month T12 revenue per part for Pareto ABC
latest_per_part AS (
    SELECT
        SITE_ID, PART_ID,
        MAX(YEAR_MONTH) AS LATEST_MONTH,
        MAX(RN)         AS LATEST_RN
    FROM ordered
    GROUP BY SITE_ID, PART_ID
),

latest_t12 AS (
    SELECT
        lp.SITE_ID, lp.PART_ID,
        t.T12_REVENUE
    FROM latest_per_part lp
    INNER JOIN trailing t
        ON t.SITE_ID = lp.SITE_ID AND t.PART_ID = lp.PART_ID
       AND t.YEAR_MONTH = lp.LATEST_MONTH
),

-- Pareto rank by latest T12 revenue.
-- Compat-safe: SUM OVER (no ORDER BY frame) for site total, correlated
-- subquery for cumulative.
pareto AS (
    SELECT
        lt.SITE_ID, lt.PART_ID, lt.T12_REVENUE,
        SUM(lt.T12_REVENUE) OVER (PARTITION BY lt.SITE_ID) AS SITE_TOTAL_T12_REV,
        (SELECT ISNULL(SUM(lt2.T12_REVENUE), 0)
         FROM latest_t12 lt2
         WHERE lt2.SITE_ID = lt.SITE_ID
           AND (lt2.T12_REVENUE > lt.T12_REVENUE
                OR (lt2.T12_REVENUE = lt.T12_REVENUE AND lt2.PART_ID <= lt.PART_ID))
        ) AS CUM_REV
    FROM latest_t12 lt
    WHERE lt.T12_REVENUE > 0
)

SELECT
    o.SITE_ID,
    o.PART_ID,
    psv.DESCRIPTION,
    psv.PRODUCT_CODE,
    psv.COMMODITY_CODE,
    psv.STOCK_UM,
    psv.FABRICATED,
    psv.PURCHASED,
    psv.ABC_CODE                              AS ERP_ABC_CODE,
    psv.PLANNER_USER_ID,

    o.YEAR_MONTH,
    YEAR(o.YEAR_MONTH)                        AS YR,
    MONTH(o.YEAR_MONTH)                       AS MO,

    o.QTY_SHIPPED,
    CAST(o.REVENUE_SHIPPED AS decimal(23,2))  AS REVENUE_SHIPPED,
    o.DISTINCT_SOS,
    o.DISTINCT_CUSTOMERS,
    o.DELIVERY_LINE_COUNT,

    -- Trailing averages
    CAST(t.T3_AVG_QTY     AS decimal(20,2))   AS T3_AVG_QTY,
    CAST(t.T3_AVG_REVENUE AS decimal(23,2))   AS T3_AVG_REVENUE,
    CAST(t.T6_AVG_QTY     AS decimal(20,2))   AS T6_AVG_QTY,
    CAST(t.T12_AVG_QTY    AS decimal(20,2))   AS T12_AVG_QTY,
    CAST(t.T12_REVENUE    AS decimal(23,2))   AS T12_REVENUE,
    CAST(t.T12_STDDEV_QTY AS decimal(20,2))   AS T12_STDDEV_QTY,
    t.T12_MONTHS_WITH_DATA,

    -- Coefficient of variation (volatility / seasonality proxy)
    CAST(
        CASE WHEN t.T12_MONTHS_WITH_DATA < 4 OR t.T12_AVG_QTY = 0 THEN NULL
             ELSE 100.0 * t.T12_STDDEV_QTY / t.T12_AVG_QTY
        END AS decimal(10,2)) AS DEMAND_CV_PCT_T12,

    -- Trend: T3 vs T6 ratio (recent burst or fade)
    CAST(
        CASE WHEN t.T6_AVG_QTY = 0 THEN NULL
             ELSE 100.0 * (t.T3_AVG_QTY - t.T6_AVG_QTY) / t.T6_AVG_QTY
        END AS decimal(10,2)) AS T3_VS_T6_PCT,

    -- MoM and YoY for the row's month
    CAST(
        CASE WHEN prev_m.QTY_SHIPPED IS NULL OR prev_m.QTY_SHIPPED = 0 THEN NULL
             ELSE 100.0 * (o.QTY_SHIPPED - prev_m.QTY_SHIPPED) / prev_m.QTY_SHIPPED
        END AS decimal(10,2)) AS QTY_MOM_PCT,
    CAST(
        CASE WHEN yo.QTY_SHIPPED IS NULL OR yo.QTY_SHIPPED = 0 THEN NULL
             ELSE 100.0 * (o.QTY_SHIPPED - yo.QTY_SHIPPED) / yo.QTY_SHIPPED
        END AS decimal(10,2)) AS QTY_YOY_PCT,

    -- Pareto ABC for the row's part (computed from latest-month T12)
    pa.T12_REVENUE                            AS PARETO_T12_REVENUE,
    CAST(
        CASE WHEN pa.SITE_TOTAL_T12_REV = 0 THEN NULL
             ELSE 100.0 * pa.CUM_REV / pa.SITE_TOTAL_T12_REV
        END AS decimal(7,2)) AS PARETO_CUM_PCT,
    CASE
        WHEN pa.T12_REVENUE IS NULL OR pa.SITE_TOTAL_T12_REV = 0 THEN NULL
        WHEN 100.0 * pa.CUM_REV / pa.SITE_TOTAL_T12_REV <= 80    THEN 'A'
        WHEN 100.0 * pa.CUM_REV / pa.SITE_TOTAL_T12_REV <= 95    THEN 'B'
        ELSE                                                          'C'
    END AS PARETO_ABC_CODE,

    -- Trend flag (compares T3 vs T6 with seasonality awareness)
    CASE
        WHEN t.T12_MONTHS_WITH_DATA < 3                       THEN 'TOO NEW'
        WHEN t.T6_AVG_QTY = 0                                 THEN 'EMERGING'
        WHEN t.T3_AVG_QTY = 0                                 THEN 'DYING'
        WHEN 100.0 * (t.T3_AVG_QTY - t.T6_AVG_QTY) / t.T6_AVG_QTY > 25
                                                              THEN 'GROWING FAST'
        WHEN 100.0 * (t.T3_AVG_QTY - t.T6_AVG_QTY) / t.T6_AVG_QTY > 5
                                                              THEN 'GROWING'
        WHEN 100.0 * (t.T3_AVG_QTY - t.T6_AVG_QTY) / t.T6_AVG_QTY < -25
                                                              THEN 'DECLINING FAST'
        WHEN 100.0 * (t.T3_AVG_QTY - t.T6_AVG_QTY) / t.T6_AVG_QTY < -5
                                                              THEN 'DECLINING'
        ELSE                                                       'STABLE'
    END AS TREND_FLAG,

    CASE
        WHEN t.T12_MONTHS_WITH_DATA < 4 OR t.T12_AVG_QTY = 0 THEN NULL
        WHEN 100.0 * t.T12_STDDEV_QTY / t.T12_AVG_QTY > 75   THEN 'HIGH (LUMPY)'
        WHEN 100.0 * t.T12_STDDEV_QTY / t.T12_AVG_QTY > 35   THEN 'MODERATE'
        ELSE                                                      'LOW (SMOOTH)'
    END AS SEASONALITY_BAND

FROM ordered o
LEFT JOIN trailing t
    ON t.SITE_ID=o.SITE_ID AND t.PART_ID=o.PART_ID AND t.YEAR_MONTH=o.YEAR_MONTH
LEFT JOIN ordered prev_m
    ON prev_m.SITE_ID=o.SITE_ID AND prev_m.PART_ID=o.PART_ID
   AND prev_m.RN = o.RN - 1
LEFT JOIN monthly yo
    ON yo.SITE_ID=o.SITE_ID AND yo.PART_ID=o.PART_ID
   AND yo.YEAR_MONTH = DATEADD(month, -12, o.YEAR_MONTH)
LEFT JOIN PART_SITE_VIEW psv
    ON psv.SITE_ID=o.SITE_ID AND psv.PART_ID=o.PART_ID
LEFT JOIN pareto pa
    ON pa.SITE_ID=o.SITE_ID AND pa.PART_ID=o.PART_ID
ORDER BY
    o.SITE_ID,
    o.PART_ID,
    o.YEAR_MONTH;
