/*
===============================================================================
Query Name: commodity_spend_rollup.sql

Purpose:
    Roll PO spend up to COMMODITY_CODE for sourcing strategy. Show:

        * Total $ spent in the commodity (trailing N months)
        * # parts and # vendors used
        * Top vendor name and their share %
        * HHI concentration index (10000 = single supplier, low = diverse)
        * T3 vs T6 trend (recent activity vs medium term)
        * Open PO exposure $ (cash committed but not yet received)
        * # parts inflating > 10% YoY (supplier-driven price pressure)

    This is the input to commodity-sourcing decisions:
        - Which commodities are concentrated (high HHI) and at supplier risk?
        - Which are inflating fast and need contract negotiation?
        - Which are big enough $ that consolidation could move the needle?

Grain:
    One row per (SITE_ID, COMMODITY_CODE) over the lookback window.
    Plus a "_TOTAL_" rollup row per site at the bottom.

Notes:
    Compat-safe. Uses correlated subqueries / window aggregates without
    ORDER-BY frames.
    HHI = sum over vendors of (share_pct)^2. Conventional bands:
        > 2500    Highly concentrated (single dominant supplier)
        1500-2500 Moderately concentrated
        < 1500    Competitive
    Parts with NULL COMMODITY_CODE are bucketed as '_NO_COMMODITY_'.
===============================================================================
*/

DECLARE @Site            nvarchar(15) = NULL;
DECLARE @LookbackMonths  int          = 12;

;WITH receipts AS (
    SELECT
        it.SITE_ID,
        it.PART_ID,
        p.VENDOR_ID,
        it.TRANSACTION_DATE,
        DATEADD(month, DATEDIFF(month, 0, it.TRANSACTION_DATE), 0) AS YEAR_MONTH,
        it.QTY,
        it.ACT_MATERIAL_COST AS SPEND
    FROM INVENTORY_TRANS it
    INNER JOIN PURCHASE_ORDER p ON p.ID = it.PURC_ORDER_ID
    WHERE it.TYPE='I' AND it.CLASS='R'
      AND it.PURC_ORDER_ID IS NOT NULL
      AND it.PART_ID IS NOT NULL
      AND it.QTY > 0
      AND it.ACT_MATERIAL_COST > 0
      AND it.TRANSACTION_DATE >= DATEADD(month, -@LookbackMonths, GETDATE())
      AND (@Site IS NULL OR it.SITE_ID = @Site)
),

receipts_tagged AS (
    SELECT
        r.SITE_ID,
        ISNULL(psv.COMMODITY_CODE, '_NO_COMMODITY_') AS COMMODITY_CODE,
        r.PART_ID,
        r.VENDOR_ID,
        r.YEAR_MONTH,
        r.QTY,
        r.SPEND
    FROM receipts r
    LEFT JOIN PART_SITE_VIEW psv
        ON psv.SITE_ID = r.SITE_ID AND psv.PART_ID = r.PART_ID
),

-- Per (commodity, vendor): vendor share of commodity spend
commodity_vendor AS (
    SELECT
        SITE_ID, COMMODITY_CODE, VENDOR_ID,
        SUM(SPEND) AS VENDOR_SPEND
    FROM receipts_tagged
    GROUP BY SITE_ID, COMMODITY_CODE, VENDOR_ID
),

commodity_total AS (
    SELECT
        SITE_ID, COMMODITY_CODE,
        SUM(VENDOR_SPEND)         AS TOTAL_SPEND,
        COUNT(*)                  AS VENDOR_COUNT
    FROM commodity_vendor
    GROUP BY SITE_ID, COMMODITY_CODE
),

-- Vendor share + HHI components
shares AS (
    SELECT
        cv.SITE_ID, cv.COMMODITY_CODE, cv.VENDOR_ID, cv.VENDOR_SPEND,
        ct.TOTAL_SPEND,
        CASE WHEN ct.TOTAL_SPEND = 0 THEN 0
             ELSE 100.0 * cv.VENDOR_SPEND / ct.TOTAL_SPEND
        END AS VENDOR_SHARE_PCT
    FROM commodity_vendor cv
    INNER JOIN commodity_total ct
        ON ct.SITE_ID = cv.SITE_ID AND ct.COMMODITY_CODE = cv.COMMODITY_CODE
),

hhi AS (
    SELECT
        SITE_ID, COMMODITY_CODE,
        SUM(VENDOR_SHARE_PCT * VENDOR_SHARE_PCT) AS HHI_INDEX
    FROM shares
    GROUP BY SITE_ID, COMMODITY_CODE
),

-- Top vendor per commodity (highest spend share)
top_vendor AS (
    SELECT SITE_ID, COMMODITY_CODE, VENDOR_ID, VENDOR_SPEND, VENDOR_SHARE_PCT,
           ROW_NUMBER() OVER (
               PARTITION BY SITE_ID, COMMODITY_CODE
               ORDER BY VENDOR_SPEND DESC, VENDOR_ID
           ) AS RNK
    FROM shares
),

top_3_csv AS (
    SELECT
        s.SITE_ID, s.COMMODITY_CODE,
        STUFF((
            SELECT ', ' + ISNULL(s2.VENDOR_ID,'(none)')
                   + ' (' + CAST(CAST(s2.VENDOR_SHARE_PCT AS decimal(5,1)) AS nvarchar(20)) + '%)'
            FROM top_vendor s2
            WHERE s2.SITE_ID=s.SITE_ID AND s2.COMMODITY_CODE=s.COMMODITY_CODE
              AND s2.RNK <= 3
            ORDER BY s2.RNK
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)'), 1, 2, '') AS TOP3_VENDORS_CSV
    FROM (SELECT DISTINCT SITE_ID, COMMODITY_CODE FROM top_vendor) s
),

-- Per-commodity stats (parts, monthly trend)
commodity_stats AS (
    SELECT
        SITE_ID, COMMODITY_CODE,
        COUNT(DISTINCT PART_ID)                          AS PART_COUNT,
        COUNT(DISTINCT VENDOR_ID)                        AS VENDOR_COUNT,
        COUNT(*)                                         AS RECEIPT_COUNT,
        SUM(QTY)                                         AS TOTAL_QTY,
        SUM(SPEND)                                       AS TOTAL_SPEND,
        -- T3 vs T6 trend: average monthly spend in the last 3 months
        -- compared to the prior 3 months.
        SUM(CASE WHEN YEAR_MONTH >= DATEADD(month, -3, DATEADD(month, DATEDIFF(month,0,GETDATE()), 0))
                 THEN SPEND ELSE 0 END) / 3.0            AS AVG_T3_MONTHLY_SPEND,
        SUM(CASE WHEN YEAR_MONTH >= DATEADD(month, -6, DATEADD(month, DATEDIFF(month,0,GETDATE()), 0))
                  AND YEAR_MONTH < DATEADD(month, -3, DATEADD(month, DATEDIFF(month,0,GETDATE()), 0))
                 THEN SPEND ELSE 0 END) / 3.0            AS AVG_PRIOR3_MONTHLY_SPEND
    FROM receipts_tagged
    GROUP BY SITE_ID, COMMODITY_CODE
),

-- Open PO exposure per commodity
open_po_per_commodity AS (
    SELECT
        p.SITE_ID,
        ISNULL(psv.COMMODITY_CODE, '_NO_COMMODITY_') AS COMMODITY_CODE,
        SUM((pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY) * pl.UNIT_PRICE) AS OPEN_PO_VALUE,
        COUNT(*) AS OPEN_PO_LINES,
        SUM(CASE WHEN COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE) < CAST(GETDATE() AS date)
                 THEN (pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY) * pl.UNIT_PRICE
                 ELSE 0 END) AS PAST_DUE_PO_VALUE
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl ON pl.PURC_ORDER_ID = p.ID
    LEFT JOIN PART_SITE_VIEW psv
        ON psv.SITE_ID = p.SITE_ID AND psv.PART_ID = pl.PART_ID
    WHERE ISNULL(p.STATUS,'') NOT IN ('X','C')
      AND ISNULL(pl.LINE_STATUS,'') NOT IN ('X','C')
      AND pl.PART_ID IS NOT NULL
      AND pl.ORDER_QTY > pl.TOTAL_RECEIVED_QTY
      AND (@Site IS NULL OR p.SITE_ID = @Site)
    GROUP BY p.SITE_ID, ISNULL(psv.COMMODITY_CODE, '_NO_COMMODITY_')
),

-- Inflation: per (site, commodity) count of parts with > 10% YoY price growth
monthly_part_cost AS (
    SELECT
        rt.SITE_ID, rt.COMMODITY_CODE, rt.PART_ID, rt.YEAR_MONTH,
        SUM(rt.SPEND) / NULLIF(SUM(rt.QTY),0) AS WTD_AVG_UNIT_COST
    FROM receipts_tagged rt
    GROUP BY rt.SITE_ID, rt.COMMODITY_CODE, rt.PART_ID, rt.YEAR_MONTH
),

inflation_per_part AS (
    SELECT
        m1.SITE_ID, m1.COMMODITY_CODE, m1.PART_ID,
        MAX(m1.WTD_AVG_UNIT_COST)              AS RECENT_COST,
        MAX(m2.WTD_AVG_UNIT_COST)              AS YEAR_AGO_COST
    FROM monthly_part_cost m1
    LEFT JOIN monthly_part_cost m2
        ON m2.SITE_ID=m1.SITE_ID AND m2.COMMODITY_CODE=m1.COMMODITY_CODE
       AND m2.PART_ID=m1.PART_ID
       AND m2.YEAR_MONTH = DATEADD(month, -12, m1.YEAR_MONTH)
    WHERE m1.YEAR_MONTH >= DATEADD(month, -3, GETDATE())
    GROUP BY m1.SITE_ID, m1.COMMODITY_CODE, m1.PART_ID
),

inflation_summary AS (
    SELECT
        SITE_ID, COMMODITY_CODE,
        SUM(CASE WHEN YEAR_AGO_COST > 0
                  AND (RECENT_COST - YEAR_AGO_COST)/YEAR_AGO_COST > 0.10
                 THEN 1 ELSE 0 END)            AS PARTS_INFLATING_GT_10PCT,
        AVG(CASE WHEN YEAR_AGO_COST > 0
                 THEN (RECENT_COST - YEAR_AGO_COST)/YEAR_AGO_COST * 100
                 ELSE NULL END)                AS AVG_YOY_PCT
    FROM inflation_per_part
    GROUP BY SITE_ID, COMMODITY_CODE
)

SELECT
    cs.SITE_ID,
    cs.COMMODITY_CODE,
    cm.DESCRIPTION                            AS COMMODITY_DESCRIPTION,
    cs.PART_COUNT,
    cs.VENDOR_COUNT,
    cs.RECEIPT_COUNT,
    CAST(cs.TOTAL_QTY      AS decimal(20,2))  AS TOTAL_QTY_RECEIVED,
    CAST(cs.TOTAL_SPEND    AS decimal(23,2))  AS TOTAL_SPEND,

    -- Top vendor + share
    tv.VENDOR_ID                              AS TOP_VENDOR_ID,
    v.NAME                                    AS TOP_VENDOR_NAME,
    CAST(tv.VENDOR_SHARE_PCT AS decimal(6,2)) AS TOP_VENDOR_SHARE_PCT,
    t3.TOP3_VENDORS_CSV,

    -- Concentration
    CAST(h.HHI_INDEX AS decimal(10,2))        AS HHI_INDEX,
    CASE
        WHEN h.HHI_INDEX > 2500 THEN 'HIGH (single-supplier risk)'
        WHEN h.HHI_INDEX > 1500 THEN 'MODERATE'
        ELSE                          'COMPETITIVE'
    END                                       AS CONCENTRATION_BAND,

    -- Trend
    CAST(cs.AVG_T3_MONTHLY_SPEND      AS decimal(23,2)) AS AVG_T3_MONTHLY_SPEND,
    CAST(cs.AVG_PRIOR3_MONTHLY_SPEND  AS decimal(23,2)) AS AVG_PRIOR3_MONTHLY_SPEND,
    CAST(
        CASE WHEN cs.AVG_PRIOR3_MONTHLY_SPEND = 0 THEN NULL
             ELSE 100.0 * (cs.AVG_T3_MONTHLY_SPEND - cs.AVG_PRIOR3_MONTHLY_SPEND)
                  / cs.AVG_PRIOR3_MONTHLY_SPEND
        END AS decimal(10,2)) AS T3_VS_PRIOR3_PCT,

    -- Open PO exposure
    ISNULL(op.OPEN_PO_LINES, 0)               AS OPEN_PO_LINES,
    CAST(ISNULL(op.OPEN_PO_VALUE, 0)    AS decimal(23,2)) AS OPEN_PO_VALUE,
    CAST(ISNULL(op.PAST_DUE_PO_VALUE, 0) AS decimal(23,2)) AS PAST_DUE_PO_VALUE,

    -- Inflation
    ISNULL(i.PARTS_INFLATING_GT_10PCT, 0)     AS PARTS_INFLATING_GT_10PCT,
    CAST(i.AVG_YOY_PCT AS decimal(10,2))      AS AVG_YOY_PCT,

    -- Composite sourcing flag
    CASE
        WHEN h.HHI_INDEX > 2500 AND cs.TOTAL_SPEND > 50000
                                                  THEN 'DIVERSIFY: high concentration, big spend'
        WHEN ISNULL(i.PARTS_INFLATING_GT_10PCT, 0) >= 3
                                                  THEN 'NEGOTIATE: multi-part inflation'
        WHEN cs.AVG_PRIOR3_MONTHLY_SPEND > 0
             AND cs.AVG_T3_MONTHLY_SPEND
                 > cs.AVG_PRIOR3_MONTHLY_SPEND * 1.5
                                                  THEN 'WATCH: spend ramping fast'
        WHEN cs.VENDOR_COUNT >= 5 AND h.HHI_INDEX < 1500
                                                  THEN 'COMPETITIVE: consolidation candidate'
        ELSE                                           'OK'
    END                                       AS SOURCING_FLAG

FROM commodity_stats cs
LEFT JOIN COMMODITY     cm
    ON cm.CODE = cs.COMMODITY_CODE
LEFT JOIN top_vendor    tv
    ON tv.SITE_ID=cs.SITE_ID AND tv.COMMODITY_CODE=cs.COMMODITY_CODE AND tv.RNK=1
LEFT JOIN VENDOR        v
    ON v.ID = tv.VENDOR_ID
LEFT JOIN top_3_csv     t3
    ON t3.SITE_ID=cs.SITE_ID AND t3.COMMODITY_CODE=cs.COMMODITY_CODE
LEFT JOIN hhi           h
    ON h.SITE_ID=cs.SITE_ID AND h.COMMODITY_CODE=cs.COMMODITY_CODE
LEFT JOIN open_po_per_commodity op
    ON op.SITE_ID=cs.SITE_ID AND op.COMMODITY_CODE=cs.COMMODITY_CODE
LEFT JOIN inflation_summary i
    ON i.SITE_ID=cs.SITE_ID AND i.COMMODITY_CODE=cs.COMMODITY_CODE

ORDER BY
    cs.SITE_ID,
    cs.TOTAL_SPEND DESC,
    cs.COMMODITY_CODE;
