/*
===============================================================================
Query Name: vendor_lead_time_history.sql

Purpose:
    Show actual lead-time performance per (vendor, part) so the planner can
    see when ERP/vendor-buffer lead times no longer match reality.

    Companion to vendor_otd_scorecard.sql (which is on-time-vs-promise) by
    answering the upstream question: how long does it ACTUALLY take from
    PO release to dock?

Grain:
    One row per (SITE_ID, PART_ID, VENDOR_ID) over the lookback window.
    Rolls up multiple receipts per PO line (a PO with two deliveries gives
    two observations).

Lead-time computation:
    LT_DAYS = INVENTORY_TRANS.TRANSACTION_DATE - PURCHASE_ORDER.ORDER_DATE
    Only PO receipts (TYPE='I' CLASS='R' PURC_ORDER_ID NOT NULL).
    Drop observations < 0 or > 365 days as data anomalies.

Stats (compat-safe, no PERCENTILE_CONT):
    OBSERVATIONS, MIN, MAX, MEAN, STDDEV
    P50 (median): manual ROW_NUMBER+COUNT pick of middle row(s)
    P90:          manual pick of row at ceil(0.9 * count)
    OTD_PCT:      % of receipts where TRANSACTION_DATE <= PROMISE_DATE

ERP comparison:
    LT_VENDOR_PART       VENDOR_PART.LEADTIME_BUFFER for this vendor+part
    LT_ERP_PART          PART_SITE_VIEW.PLANNING_LEADTIME (any vendor)
    LT_OPTIMISM_DAYS     P50 actual minus the lowest of the two ERP values
                         (positive = ERP is OPTIMISTIC, real LT is longer)

Use:
    - Catch parts where ERP says 14d but actuals run 35d -> raise the buffer
    - Pick reliable vendors when sourcing decisions come up
    - Feed the EFFECTIVE_LT calc in purchasing_plan.sql
===============================================================================
*/

DECLARE @Site            nvarchar(15) = NULL;
DECLARE @LookbackMonths  int          = 18;
DECLARE @MinObservations int          = 2;   -- drop too-thin samples

;WITH receipts AS (
    SELECT
        it.SITE_ID,
        it.PART_ID,
        p.VENDOR_ID,
        it.PURC_ORDER_ID,
        it.TRANSACTION_DATE                                         AS RECEIPT_DATE,
        p.ORDER_DATE                                                AS PO_ORDER_DATE,
        p.PROMISE_DATE                                              AS PO_PROMISE_DATE,
        DATEDIFF(day, p.ORDER_DATE, it.TRANSACTION_DATE)            AS LT_DAYS,
        CASE WHEN p.PROMISE_DATE IS NOT NULL
              AND it.TRANSACTION_DATE <= p.PROMISE_DATE THEN 1 ELSE 0 END AS ON_TIME_FLAG,
        it.QTY,
        it.ACT_MATERIAL_COST
    FROM INVENTORY_TRANS it
    INNER JOIN PURCHASE_ORDER p ON p.ID = it.PURC_ORDER_ID
    WHERE it.TYPE = 'I' AND it.CLASS = 'R'
      AND it.PURC_ORDER_ID IS NOT NULL
      AND it.PART_ID       IS NOT NULL
      AND p.ORDER_DATE     IS NOT NULL
      AND it.QTY > 0
      AND it.TRANSACTION_DATE >= DATEADD(month, -@LookbackMonths, GETDATE())
      AND DATEDIFF(day, p.ORDER_DATE, it.TRANSACTION_DATE) BETWEEN 0 AND 365
      AND (@Site IS NULL OR it.SITE_ID = @Site)
),

ranked AS (
    SELECT
        r.SITE_ID, r.PART_ID, r.VENDOR_ID, r.LT_DAYS,
        ROW_NUMBER() OVER (PARTITION BY r.SITE_ID, r.PART_ID, r.VENDOR_ID
                           ORDER BY r.LT_DAYS) AS RN,
        COUNT(*)     OVER (PARTITION BY r.SITE_ID, r.PART_ID, r.VENDOR_ID) AS CNT
    FROM receipts r
),

p50_per_group AS (
    SELECT SITE_ID, PART_ID, VENDOR_ID,
           AVG(CAST(LT_DAYS AS decimal(10,2))) AS P50_LT
    FROM ranked
    WHERE RN IN ((CNT+1)/2, (CNT+2)/2)
    GROUP BY SITE_ID, PART_ID, VENDOR_ID
),

p90_per_group AS (
    SELECT SITE_ID, PART_ID, VENDOR_ID,
           MIN(LT_DAYS) AS P90_LT
    FROM (
        SELECT r.SITE_ID, r.PART_ID, r.VENDOR_ID, r.LT_DAYS,
               r.RN,
               r.CNT,
               -- ceil(0.9 * cnt) = (90*cnt + 99) / 100 in integer math
               CASE WHEN r.CNT < 10 THEN r.CNT          -- thin samples: max
                    ELSE (90 * r.CNT + 99) / 100 END AS TARGET_RN
        FROM ranked r
    ) x
    WHERE x.RN >= x.TARGET_RN
    GROUP BY SITE_ID, PART_ID, VENDOR_ID
),

agg AS (
    SELECT
        r.SITE_ID, r.PART_ID, r.VENDOR_ID,
        COUNT(*)                                          AS OBSERVATIONS,
        SUM(r.QTY)                                        AS QTY_RECEIVED,
        SUM(r.ACT_MATERIAL_COST)                          AS VALUE_RECEIVED,
        MIN(r.LT_DAYS)                                    AS MIN_LT_DAYS,
        MAX(r.LT_DAYS)                                    AS MAX_LT_DAYS,
        CAST(AVG(CAST(r.LT_DAYS AS decimal(10,2))) AS decimal(10,2)) AS MEAN_LT_DAYS,
        CAST(STDEV(r.LT_DAYS) AS decimal(10,2))           AS STDDEV_LT_DAYS,
        SUM(r.ON_TIME_FLAG)                               AS ON_TIME_RECEIPTS,
        SUM(CASE WHEN r.PO_PROMISE_DATE IS NULL THEN 0 ELSE 1 END) AS RECEIPTS_WITH_PROMISE,
        MIN(r.RECEIPT_DATE)                               AS FIRST_RECEIPT,
        MAX(r.RECEIPT_DATE)                               AS LAST_RECEIPT
    FROM receipts r
    GROUP BY r.SITE_ID, r.PART_ID, r.VENDOR_ID
)

SELECT
    a.SITE_ID,
    a.PART_ID,
    psv.DESCRIPTION,
    psv.PRODUCT_CODE,
    psv.COMMODITY_CODE,
    psv.STOCK_UM,
    psv.PLANNING_LEADTIME                            AS LT_ERP_PART,
    a.VENDOR_ID,
    v.NAME                                           AS VENDOR_NAME,
    v.BUYER                                          AS VENDOR_BUYER,
    vp.LEADTIME_BUFFER                               AS LT_VENDOR_PART,

    a.OBSERVATIONS,
    a.QTY_RECEIVED,
    CAST(a.VALUE_RECEIVED AS decimal(23,2))          AS VALUE_RECEIVED,
    a.FIRST_RECEIPT,
    a.LAST_RECEIPT,

    a.MIN_LT_DAYS,
    a.MAX_LT_DAYS,
    a.MEAN_LT_DAYS,
    a.STDDEV_LT_DAYS,
    p50.P50_LT                                       AS P50_LT_DAYS,
    p90.P90_LT                                       AS P90_LT_DAYS,

    a.ON_TIME_RECEIPTS,
    a.RECEIPTS_WITH_PROMISE,
    CAST(
        CASE
            WHEN a.RECEIPTS_WITH_PROMISE = 0 THEN NULL
            ELSE 100.0 * a.ON_TIME_RECEIPTS / a.RECEIPTS_WITH_PROMISE
        END AS decimal(6,2)
    ) AS OTD_PCT,

    -- ERP-vs-reality gap. Positive = ERP is too optimistic.
    CAST(
        p50.P50_LT
        - CASE
            WHEN ISNULL(vp.LEADTIME_BUFFER,0)      > 0
             AND ISNULL(psv.PLANNING_LEADTIME,0)   > 0
                THEN
                    CASE WHEN vp.LEADTIME_BUFFER < psv.PLANNING_LEADTIME
                         THEN vp.LEADTIME_BUFFER ELSE psv.PLANNING_LEADTIME END
            WHEN ISNULL(vp.LEADTIME_BUFFER,0)    > 0 THEN vp.LEADTIME_BUFFER
            WHEN ISNULL(psv.PLANNING_LEADTIME,0) > 0 THEN psv.PLANNING_LEADTIME
            ELSE 0
        END
    AS decimal(10,2)) AS LT_OPTIMISM_DAYS,

    CASE
        WHEN a.OBSERVATIONS < @MinObservations            THEN 'INSUFFICIENT DATA'
        WHEN p50.P50_LT > 1.5 * COALESCE(NULLIF(vp.LEADTIME_BUFFER,0),
                                         NULLIF(psv.PLANNING_LEADTIME,0), p50.P50_LT)
             AND COALESCE(vp.LEADTIME_BUFFER, psv.PLANNING_LEADTIME) IS NOT NULL
                                                          THEN 'ERP TOO OPTIMISTIC'
        WHEN a.STDDEV_LT_DAYS > a.MEAN_LT_DAYS * 0.5      THEN 'HIGH VARIABILITY'
        WHEN a.OBSERVATIONS >= @MinObservations
         AND COALESCE(
                100.0 * a.ON_TIME_RECEIPTS / NULLIF(a.RECEIPTS_WITH_PROMISE,0),
                100) >= 90                                THEN 'RELIABLE'
        ELSE 'OK'
    END AS LT_HEALTH

FROM agg a
LEFT JOIN p50_per_group p50
    ON  p50.SITE_ID=a.SITE_ID AND p50.PART_ID=a.PART_ID AND p50.VENDOR_ID=a.VENDOR_ID
LEFT JOIN p90_per_group p90
    ON  p90.SITE_ID=a.SITE_ID AND p90.PART_ID=a.PART_ID AND p90.VENDOR_ID=a.VENDOR_ID
LEFT JOIN PART_SITE_VIEW psv
    ON  psv.SITE_ID=a.SITE_ID AND psv.PART_ID=a.PART_ID
LEFT JOIN VENDOR v
    ON  v.ID = a.VENDOR_ID
LEFT JOIN VENDOR_PART vp
    ON  vp.SITE_ID=a.SITE_ID AND vp.PART_ID=a.PART_ID AND vp.VENDOR_ID=a.VENDOR_ID
ORDER BY
    a.SITE_ID,
    LT_OPTIMISM_DAYS DESC,
    a.PART_ID,
    a.VENDOR_ID;
