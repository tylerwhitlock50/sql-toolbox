/*
===============================================================================
Query Name: part_price_volatility.sql

Purpose:
    Monthly-grain extension of purchase_price_history_yearly.sql. For each
    purchased part, show price by year-month plus:

        * MoM %Δ        (vs prior month with receipts)
        * YoY %Δ        (vs same month one year earlier)
        * trailing-12-month stddev / mean        (coefficient of variation)
        * inflation_status flag

    Use this to:
        - spot parts where purchase price has drifted materially
        - feed the EXPECTED_UNIT_COST in purchasing_plan.sql
        - prioritize contract negotiations on top-spend / volatile parts

Grain:
    One row per (SITE_ID, PART_ID, YEAR_MONTH) where there was at least
    one PO receipt that month.

Source filter (mirrors purchase_price_history_yearly):
    INVENTORY_TRANS where TYPE='I', CLASS='R', PURC_ORDER_ID NOT NULL,
    QTY > 0, ACT_MATERIAL_COST > 0.

Notes:
    * Quantities in INVENTORY_TRANS are in stocking UM, so cross-receipt
      unit costs are directly comparable.
    * Trailing-12 stddev/mean is computed via self-join across the prior
      11 monthly rows; rows with fewer than 4 months of history have
      CV_TRAILING_12 = NULL.
    * MoM is "vs the most recent prior month that has a receipt" -- not
      strictly the calendar prior month. This is more useful when receipts
      are sparse.
===============================================================================
*/

DECLARE @Site            nvarchar(15) = NULL;
DECLARE @LookbackMonths  int          = 36;

;WITH receipts AS (
    SELECT
        it.SITE_ID,
        it.PART_ID,
        DATEADD(month, DATEDIFF(month, 0, it.TRANSACTION_DATE), 0) AS YEAR_MONTH,
        it.QTY,
        it.ACT_MATERIAL_COST
    FROM INVENTORY_TRANS it
    WHERE it.TYPE='I' AND it.CLASS='R'
      AND it.PURC_ORDER_ID IS NOT NULL
      AND it.PART_ID IS NOT NULL
      AND it.QTY > 0
      AND it.ACT_MATERIAL_COST > 0
      AND it.TRANSACTION_DATE >= DATEADD(month, -@LookbackMonths, GETDATE())
      AND (@Site IS NULL OR it.SITE_ID = @Site)
),

monthly AS (
    SELECT
        SITE_ID, PART_ID, YEAR_MONTH,
        COUNT(*)                                          AS RECEIPT_COUNT,
        SUM(QTY)                                          AS QTY_RECEIVED,
        SUM(ACT_MATERIAL_COST)                            AS VALUE_RECEIVED,
        CAST(SUM(ACT_MATERIAL_COST) / NULLIF(SUM(QTY),0) AS decimal(22,8)) AS WTD_AVG_UNIT_COST
    FROM receipts
    GROUP BY SITE_ID, PART_ID, YEAR_MONTH
),

-- Number rows per part by month asc; lets us self-join to "prior with data"
ordered AS (
    SELECT
        m.*,
        ROW_NUMBER() OVER (PARTITION BY m.SITE_ID, m.PART_ID ORDER BY m.YEAR_MONTH) AS RN
    FROM monthly m
),

-- Trailing-12 stats: for each (part, month) average over the 12 most recent
-- months on or before this one (inclusive).
trailing AS (
    SELECT
        o1.SITE_ID, o1.PART_ID, o1.YEAR_MONTH,
        COUNT(*)                                              AS T12_OBS,
        CAST(AVG(o2.WTD_AVG_UNIT_COST) AS decimal(22,8))      AS T12_MEAN,
        CAST(STDEV(o2.WTD_AVG_UNIT_COST) AS decimal(22,8))    AS T12_STDDEV
    FROM ordered o1
    INNER JOIN ordered o2
        ON  o2.SITE_ID = o1.SITE_ID AND o2.PART_ID = o1.PART_ID
        AND o2.YEAR_MONTH BETWEEN DATEADD(month, -11, o1.YEAR_MONTH) AND o1.YEAR_MONTH
    GROUP BY o1.SITE_ID, o1.PART_ID, o1.YEAR_MONTH
)

SELECT
    o.SITE_ID,
    o.PART_ID,
    psv.DESCRIPTION,
    psv.PRODUCT_CODE,
    psv.COMMODITY_CODE,
    psv.STOCK_UM,
    psv.PREF_VENDOR_ID,
    psv.BUYER_USER_ID,
    psv.ABC_CODE,
    psv.UNIT_MATERIAL_COST                              AS STD_UNIT_MATERIAL_COST,

    o.YEAR_MONTH,
    YEAR(o.YEAR_MONTH)                                  AS YR,
    MONTH(o.YEAR_MONTH)                                 AS MO,

    o.RECEIPT_COUNT,
    o.QTY_RECEIVED,
    CAST(o.VALUE_RECEIVED AS decimal(23,2))             AS VALUE_RECEIVED,
    o.WTD_AVG_UNIT_COST,

    -- MoM: prior row by RN ordering (most recent month with receipts)
    prev_m.WTD_AVG_UNIT_COST                            AS PRIOR_UNIT_COST,
    prev_m.YEAR_MONTH                                   AS PRIOR_YEAR_MONTH,
    CAST(
        CASE WHEN prev_m.WTD_AVG_UNIT_COST IS NULL OR prev_m.WTD_AVG_UNIT_COST = 0 THEN NULL
             ELSE 100.0 * (o.WTD_AVG_UNIT_COST - prev_m.WTD_AVG_UNIT_COST)
                  / prev_m.WTD_AVG_UNIT_COST
        END AS decimal(10,2)) AS MOM_PCT,

    -- YoY: same month one year earlier
    yo.WTD_AVG_UNIT_COST                                AS YEAR_AGO_UNIT_COST,
    CAST(
        CASE WHEN yo.WTD_AVG_UNIT_COST IS NULL OR yo.WTD_AVG_UNIT_COST = 0 THEN NULL
             ELSE 100.0 * (o.WTD_AVG_UNIT_COST - yo.WTD_AVG_UNIT_COST)
                  / yo.WTD_AVG_UNIT_COST
        END AS decimal(10,2)) AS YOY_PCT,

    -- Trailing-12 volatility (coefficient of variation = stddev / mean)
    t.T12_OBS,
    t.T12_MEAN,
    t.T12_STDDEV,
    CAST(
        CASE WHEN t.T12_OBS < 4 OR t.T12_MEAN IS NULL OR t.T12_MEAN = 0 THEN NULL
             ELSE 100.0 * t.T12_STDDEV / t.T12_MEAN
        END AS decimal(10,2)) AS CV_TRAILING_12_PCT,

    -- Drift from standard
    CAST(
        CASE WHEN psv.UNIT_MATERIAL_COST IS NULL OR psv.UNIT_MATERIAL_COST = 0 THEN NULL
             ELSE 100.0 * (o.WTD_AVG_UNIT_COST - psv.UNIT_MATERIAL_COST)
                  / psv.UNIT_MATERIAL_COST
        END AS decimal(10,2)) AS VS_STD_PCT,

    CASE
        WHEN yo.WTD_AVG_UNIT_COST IS NULL                          THEN 'NEW (NO YOY BASELINE)'
        WHEN 100.0 * (o.WTD_AVG_UNIT_COST - yo.WTD_AVG_UNIT_COST)
             / NULLIF(yo.WTD_AVG_UNIT_COST,0) > 15                  THEN 'INFLATING'
        WHEN 100.0 * (o.WTD_AVG_UNIT_COST - yo.WTD_AVG_UNIT_COST)
             / NULLIF(yo.WTD_AVG_UNIT_COST,0) < -10                 THEN 'DEFLATING'
        WHEN t.T12_OBS >= 4
         AND t.T12_MEAN > 0
         AND 100.0 * t.T12_STDDEV / t.T12_MEAN > 25                 THEN 'VOLATILE'
        ELSE 'STABLE'
    END AS PRICE_TREND_FLAG

FROM ordered o
LEFT JOIN ordered prev_m
       ON  prev_m.SITE_ID=o.SITE_ID AND prev_m.PART_ID=o.PART_ID
       AND prev_m.RN = o.RN - 1
LEFT JOIN monthly yo
       ON  yo.SITE_ID=o.SITE_ID AND yo.PART_ID=o.PART_ID
       AND yo.YEAR_MONTH = DATEADD(month, -12, o.YEAR_MONTH)
LEFT JOIN trailing t
       ON  t.SITE_ID=o.SITE_ID AND t.PART_ID=o.PART_ID AND t.YEAR_MONTH=o.YEAR_MONTH
LEFT JOIN PART_SITE_VIEW psv
       ON  psv.SITE_ID=o.SITE_ID AND psv.PART_ID=o.PART_ID
ORDER BY
    o.SITE_ID,
    o.PART_ID,
    o.YEAR_MONTH;
