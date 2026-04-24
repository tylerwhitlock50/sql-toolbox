/*
===============================================================================
Query Name: vendor_scorecard_360.sql

Purpose:
    One-row-per-vendor consolidated scorecard. Combines:
        * Spend (trailing N months, all sites)
        * Order activity (PO count, line count, receipts count)
        * On-time delivery (vs PROMISE_DATE)
        * Lead time -- mean and variability
        * Price trend -- share of parts with >10% YoY inflation
        * Open exposure -- # past-due POs, $ at risk
        * Health flag

    Companion to vendor_otd_scorecard.sql (which is OTD-focused).
    Companion to vendor_lead_time_history.sql (which is per-part).

Grain:
    One row per VENDOR_ID. Optional @Site filter narrows the spend window.

Health flag (composite):
    GREEN  : OTD >= 95%, LT CV < 25%, no past-due POs, no inflation flags
    YELLOW : OTD 80-95% OR moderate variability OR inflation present
    RED    : OTD < 80% OR significant past-due POs OR severe inflation
    UNKNOWN: < 5 receipts in window

Notes:
    Compat-safe (no PERCENTILE_CONT). Uses STDEV() and AVG() across receipt
    observations. Past-due defined as DESIRED_RECV_DATE < today on an open
    PO line.
===============================================================================
*/

DECLARE @Site            nvarchar(15) = NULL;
DECLARE @LookbackMonths  int          = 12;

;WITH receipts AS (
    SELECT
        p.VENDOR_ID,
        it.SITE_ID,
        it.PART_ID,
        it.PURC_ORDER_ID,
        it.TRANSACTION_DATE                                         AS RECEIPT_DATE,
        p.ORDER_DATE,
        p.PROMISE_DATE,
        DATEDIFF(day, p.ORDER_DATE, it.TRANSACTION_DATE)            AS LT_DAYS,
        CASE WHEN p.PROMISE_DATE IS NOT NULL
              AND it.TRANSACTION_DATE <= p.PROMISE_DATE THEN 1 ELSE 0 END AS ON_TIME_FLAG,
        it.QTY,
        it.ACT_MATERIAL_COST
    FROM INVENTORY_TRANS it
    INNER JOIN PURCHASE_ORDER p ON p.ID = it.PURC_ORDER_ID
    WHERE it.TYPE='I' AND it.CLASS='R'
      AND it.PURC_ORDER_ID IS NOT NULL
      AND it.PART_ID IS NOT NULL
      AND p.ORDER_DATE IS NOT NULL
      AND it.QTY > 0
      AND it.TRANSACTION_DATE >= DATEADD(month, -@LookbackMonths, GETDATE())
      AND DATEDIFF(day, p.ORDER_DATE, it.TRANSACTION_DATE) BETWEEN 0 AND 365
      AND (@Site IS NULL OR it.SITE_ID = @Site)
),

vendor_receipts AS (
    SELECT
        VENDOR_ID,
        COUNT(*)                                              AS RECEIPT_COUNT,
        COUNT(DISTINCT PURC_ORDER_ID)                         AS PO_COUNT,
        COUNT(DISTINCT PART_ID)                               AS PARTS_RECEIVED,
        SUM(QTY)                                              AS QTY_RECEIVED,
        SUM(ACT_MATERIAL_COST)                                AS SPEND,
        SUM(ON_TIME_FLAG)                                     AS ON_TIME_RECEIPTS,
        SUM(CASE WHEN PROMISE_DATE IS NULL THEN 0 ELSE 1 END) AS RECEIPTS_WITH_PROMISE,
        CAST(AVG(CAST(LT_DAYS AS decimal(10,2))) AS decimal(10,2)) AS MEAN_LT_DAYS,
        CAST(STDEV(LT_DAYS) AS decimal(10,2))                  AS STDDEV_LT_DAYS,
        MIN(RECEIPT_DATE)                                     AS FIRST_RECEIPT,
        MAX(RECEIPT_DATE)                                     AS LAST_RECEIPT
    FROM receipts
    GROUP BY VENDOR_ID
),

-- Open / past-due exposure
open_pos AS (
    SELECT
        p.VENDOR_ID,
        COUNT(DISTINCT p.ID)                                  AS OPEN_PO_COUNT,
        SUM(pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY)             AS OPEN_QTY,
        SUM((pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY) * pl.UNIT_PRICE) AS OPEN_VALUE,
        SUM(CASE
                WHEN COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE)
                     < CAST(GETDATE() AS date) THEN 1 ELSE 0
            END)                                              AS PAST_DUE_LINES,
        SUM(CASE
                WHEN COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE)
                     < CAST(GETDATE() AS date)
                THEN (pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY) * pl.UNIT_PRICE
                ELSE 0
            END)                                              AS PAST_DUE_VALUE
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl ON pl.PURC_ORDER_ID = p.ID
    WHERE ISNULL(p.STATUS,'') NOT IN ('X','C')
      AND ISNULL(pl.LINE_STATUS,'') NOT IN ('X','C')
      AND pl.PART_ID IS NOT NULL
      AND pl.ORDER_QTY > pl.TOTAL_RECEIVED_QTY
      AND (@Site IS NULL OR p.SITE_ID = @Site)
    GROUP BY p.VENDOR_ID
),

-- Price trend per (vendor, part): YoY weighted-avg cost compare
monthly_cost AS (
    SELECT
        p.VENDOR_ID,
        it.SITE_ID,
        it.PART_ID,
        DATEADD(month, DATEDIFF(month, 0, it.TRANSACTION_DATE), 0) AS YM,
        SUM(it.ACT_MATERIAL_COST) / NULLIF(SUM(it.QTY),0) AS WTD_AVG_UNIT_COST
    FROM INVENTORY_TRANS it
    INNER JOIN PURCHASE_ORDER p ON p.ID = it.PURC_ORDER_ID
    WHERE it.TYPE='I' AND it.CLASS='R'
      AND it.PURC_ORDER_ID IS NOT NULL AND it.PART_ID IS NOT NULL
      AND it.QTY > 0 AND it.ACT_MATERIAL_COST > 0
      AND it.TRANSACTION_DATE >= DATEADD(month, -24, GETDATE())
      AND (@Site IS NULL OR it.SITE_ID = @Site)
    GROUP BY p.VENDOR_ID, it.SITE_ID, it.PART_ID,
             DATEFROMPARTS(YEAR(it.TRANSACTION_DATE), MONTH(it.TRANSACTION_DATE), 1)
),

vendor_part_yoy AS (
    SELECT
        m1.VENDOR_ID,
        m1.SITE_ID,
        m1.PART_ID,
        MAX(m1.WTD_AVG_UNIT_COST)                              AS RECENT_COST,
        MAX(m2.WTD_AVG_UNIT_COST)                              AS YEAR_AGO_COST
    FROM monthly_cost m1
    LEFT JOIN monthly_cost m2
        ON m2.VENDOR_ID=m1.VENDOR_ID AND m2.SITE_ID=m1.SITE_ID AND m2.PART_ID=m1.PART_ID
       AND m2.YM = DATEADD(month, -12, m1.YM)
    WHERE m1.YM >= DATEADD(month, -3, GETDATE())   -- "recent" = last 3 months
    GROUP BY m1.VENDOR_ID, m1.SITE_ID, m1.PART_ID
),

inflation_flags AS (
    SELECT
        VENDOR_ID,
        COUNT(*)                                               AS PARTS_WITH_YOY,
        SUM(CASE WHEN YEAR_AGO_COST IS NOT NULL
                  AND YEAR_AGO_COST > 0
                  AND (RECENT_COST - YEAR_AGO_COST)/YEAR_AGO_COST > 0.10
                 THEN 1 ELSE 0 END)                            AS PARTS_INFLATING_GT_10PCT,
        SUM(CASE WHEN YEAR_AGO_COST IS NOT NULL
                  AND YEAR_AGO_COST > 0
                  AND (RECENT_COST - YEAR_AGO_COST)/YEAR_AGO_COST > 0.25
                 THEN 1 ELSE 0 END)                            AS PARTS_INFLATING_GT_25PCT,
        AVG(CASE WHEN YEAR_AGO_COST IS NOT NULL AND YEAR_AGO_COST > 0
                 THEN (RECENT_COST - YEAR_AGO_COST)/YEAR_AGO_COST * 100
                 ELSE NULL END)                                AS AVG_YOY_PCT
    FROM vendor_part_yoy
    GROUP BY VENDOR_ID
)

SELECT
    v.ID                                                AS VENDOR_ID,
    v.NAME                                              AS VENDOR_NAME,
    v.BUYER                                             AS PRIMARY_BUYER,
    v.ACTIVE_FLAG,
    v.LAST_ORDER_DATE,
    v.CURRENCY_ID,
    v.PRIORITY,
    v.VENDOR_GROUP_ID,

    -- Activity
    ISNULL(vr.RECEIPT_COUNT, 0)                         AS RECEIPTS_TRAILING,
    ISNULL(vr.PO_COUNT,      0)                         AS POS_TRAILING,
    ISNULL(vr.PARTS_RECEIVED,0)                         AS PARTS_RECEIVED_TRAILING,
    ISNULL(vr.QTY_RECEIVED,  0)                         AS QTY_RECEIVED_TRAILING,
    CAST(ISNULL(vr.SPEND, 0) AS decimal(23,2))          AS SPEND_TRAILING,
    vr.FIRST_RECEIPT,
    vr.LAST_RECEIPT,

    -- OTD
    vr.ON_TIME_RECEIPTS,
    vr.RECEIPTS_WITH_PROMISE,
    CAST(
        CASE WHEN ISNULL(vr.RECEIPTS_WITH_PROMISE,0) = 0 THEN NULL
             ELSE 100.0 * vr.ON_TIME_RECEIPTS / vr.RECEIPTS_WITH_PROMISE
        END AS decimal(6,2)
    )                                                   AS OTD_PCT,

    -- Lead time
    vr.MEAN_LT_DAYS,
    vr.STDDEV_LT_DAYS,
    CAST(
        CASE WHEN ISNULL(vr.MEAN_LT_DAYS,0) = 0 THEN NULL
             ELSE 100.0 * vr.STDDEV_LT_DAYS / vr.MEAN_LT_DAYS
        END AS decimal(10,2)
    )                                                   AS LT_CV_PCT,

    -- Price trend
    ISNULL(infl.PARTS_WITH_YOY, 0)                      AS PARTS_WITH_YOY_DATA,
    ISNULL(infl.PARTS_INFLATING_GT_10PCT, 0)            AS PARTS_INFLATING_GT_10PCT,
    ISNULL(infl.PARTS_INFLATING_GT_25PCT, 0)            AS PARTS_INFLATING_GT_25PCT,
    CAST(infl.AVG_YOY_PCT AS decimal(10,2))             AS AVG_YOY_PCT,

    -- Open exposure
    ISNULL(op.OPEN_PO_COUNT, 0)                         AS OPEN_PO_COUNT,
    CAST(ISNULL(op.OPEN_QTY,    0) AS decimal(20,4))    AS OPEN_QTY,
    CAST(ISNULL(op.OPEN_VALUE,  0) AS decimal(23,2))    AS OPEN_VALUE,
    ISNULL(op.PAST_DUE_LINES, 0)                        AS PAST_DUE_PO_LINES,
    CAST(ISNULL(op.PAST_DUE_VALUE, 0) AS decimal(23,2)) AS PAST_DUE_VALUE,

    -- Composite health
    CASE
        WHEN ISNULL(vr.RECEIPT_COUNT,0) < 5
            THEN 'UNKNOWN'
        WHEN ISNULL(100.0 * vr.ON_TIME_RECEIPTS
                    / NULLIF(vr.RECEIPTS_WITH_PROMISE,0), 100) < 80
          OR ISNULL(infl.PARTS_INFLATING_GT_25PCT, 0) > 0
          OR ISNULL(op.PAST_DUE_VALUE, 0) > 50000
            THEN 'RED'
        WHEN ISNULL(100.0 * vr.ON_TIME_RECEIPTS
                    / NULLIF(vr.RECEIPTS_WITH_PROMISE,0), 100) < 95
          OR (ISNULL(vr.MEAN_LT_DAYS,0) > 0
              AND 100.0 * vr.STDDEV_LT_DAYS / vr.MEAN_LT_DAYS > 25)
          OR ISNULL(infl.PARTS_INFLATING_GT_10PCT, 0) > 0
          OR ISNULL(op.PAST_DUE_LINES, 0) > 0
            THEN 'YELLOW'
        ELSE 'GREEN'
    END                                                 AS HEALTH

FROM VENDOR v
LEFT JOIN vendor_receipts vr ON vr.VENDOR_ID = v.ID
LEFT JOIN open_pos        op ON op.VENDOR_ID = v.ID
LEFT JOIN inflation_flags infl ON infl.VENDOR_ID = v.ID
WHERE
    -- Show vendors with any activity in or open exposure to the window
    ISNULL(vr.RECEIPT_COUNT, 0) > 0
 OR ISNULL(op.OPEN_PO_COUNT, 0)  > 0
ORDER BY
    CASE
        WHEN ISNULL(vr.RECEIPT_COUNT,0) < 5 THEN 4
        WHEN (
            ISNULL(100.0 * vr.ON_TIME_RECEIPTS / NULLIF(vr.RECEIPTS_WITH_PROMISE,0), 100) < 80
            OR ISNULL(infl.PARTS_INFLATING_GT_25PCT,0) > 0
            OR ISNULL(op.PAST_DUE_VALUE,0) > 50000
        ) THEN 1
        WHEN (
            ISNULL(100.0 * vr.ON_TIME_RECEIPTS / NULLIF(vr.RECEIPTS_WITH_PROMISE,0), 100) < 95
            OR (ISNULL(vr.MEAN_LT_DAYS,0) > 0
                AND 100.0 * vr.STDDEV_LT_DAYS / vr.MEAN_LT_DAYS > 25)
            OR ISNULL(infl.PARTS_INFLATING_GT_10PCT,0) > 0
            OR ISNULL(op.PAST_DUE_LINES,0) > 0
        ) THEN 2
        ELSE 3
    END,
    ISNULL(vr.SPEND, 0) DESC,
    v.NAME;
