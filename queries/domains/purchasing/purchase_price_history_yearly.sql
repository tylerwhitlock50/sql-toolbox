-- =========================================================================
-- Purchase price history by year (from INVENTORY_TRANS PO receipts)
-- =========================================================================
-- One row per (PART_ID, year) with min / max / avg / median / weighted-avg
-- unit cost, plus receipt count and total qty received.
--
-- Source filter:
--   type  = 'I'   (inbound to inventory)
--   class = 'R'   (receipt)
--   purc_order_id IS NOT NULL  (only PO receipts, not WO completions)
--   qty > 0 AND act_material_cost > 0
--
-- Notes:
--   * Quantities in INVENTORY_TRANS are always in the part's stocking UOM,
--     so unit_cost = act_material_cost / qty is directly comparable across
--     receipts for the same part.
--   * SQL Server doesn't have a MEDIAN aggregate, and PERCENTILE_CONT
--     requires compat level 110+ (which this DB isn't on). Instead we
--     compute the median manually with ROW_NUMBER + COUNT and average the
--     middle one or two rows per (PART_ID, YR).
--   * `weighted_avg_unit_cost` is the $/qty weighted average for the year
--     (dollar-weighted, NOT the simple average of per-receipt unit prices).
--     For most purposes this is the "real" blended year price.
--
-- Companion: part_cost_summary.sql (one-row-per-part summary)
-- =========================================================================

DECLARE @Site        nvarchar(15) = 'TDJ';   -- set to NULL for all sites
DECLARE @FromYear    int          = 2020;    -- inclusive

;WITH receipts AS
(
    SELECT
        it.PART_ID,
        it.SITE_ID,
        YEAR(it.TRANSACTION_DATE)           AS YR,
        it.TRANSACTION_DATE,
        it.QTY,
        it.ACT_MATERIAL_COST,
        CAST(it.ACT_MATERIAL_COST / it.QTY AS decimal(22,8)) AS UNIT_COST
    FROM   INVENTORY_TRANS it
    WHERE  it.TYPE = 'I'
      AND  it.CLASS = 'R'
      AND  it.PURC_ORDER_ID IS NOT NULL
      AND  it.PART_ID       IS NOT NULL
      AND  it.QTY               > 0
      AND  it.ACT_MATERIAL_COST > 0
      AND  YEAR(it.TRANSACTION_DATE) >= @FromYear
      AND  (@Site IS NULL OR it.SITE_ID = @Site)
),
-- Manual median: number each row within (PART_ID, YR) by UNIT_COST asc,
-- then pick the middle one (odd count) or average the two middle ones (even).
ranked AS
(
    SELECT
        r.PART_ID,
        r.YR,
        r.UNIT_COST,
        ROW_NUMBER() OVER (PARTITION BY r.PART_ID, r.YR ORDER BY r.UNIT_COST) AS RN,
        COUNT(*)     OVER (PARTITION BY r.PART_ID, r.YR)                      AS CNT
    FROM receipts r
),
median_per_group AS
(
    SELECT
        PART_ID,
        YR,
        AVG(UNIT_COST) AS MEDIAN_UNIT_COST
    FROM   ranked
    WHERE  RN IN ((CNT + 1) / 2, (CNT + 2) / 2)
    GROUP BY PART_ID, YR
)
SELECT
    r.PART_ID,
    psv.DESCRIPTION,
    psv.PRODUCT_CODE,
    r.YR,
    COUNT(*)                                            AS RECEIPT_COUNT,
    SUM(r.QTY)                                          AS TOTAL_QTY_RECEIVED,
    SUM(r.ACT_MATERIAL_COST)                            AS TOTAL_RECEIVED_VALUE,
    CAST(MIN(r.UNIT_COST)    AS decimal(22,8))          AS MIN_UNIT_COST,
    CAST(MAX(r.UNIT_COST)    AS decimal(22,8))          AS MAX_UNIT_COST,
    CAST(AVG(r.UNIT_COST)    AS decimal(22,8))          AS AVG_UNIT_COST,       -- simple avg of receipts
    CAST(MIN(m.MEDIAN_UNIT_COST) AS decimal(22,8))      AS MEDIAN_UNIT_COST,     -- constant within group
    CAST(SUM(r.ACT_MATERIAL_COST) / NULLIF(SUM(r.QTY),0) AS decimal(22,8))
                                                        AS WEIGHTED_AVG_UNIT_COST,
    MIN(r.TRANSACTION_DATE)                             AS FIRST_RECEIPT_IN_YEAR,
    MAX(r.TRANSACTION_DATE)                             AS LAST_RECEIPT_IN_YEAR
FROM   receipts r
LEFT   JOIN median_per_group m
       ON  m.PART_ID = r.PART_ID
       AND m.YR      = r.YR
LEFT   JOIN PART_SITE_VIEW psv
       ON  psv.PART_ID = r.PART_ID
       AND (@Site IS NULL OR psv.SITE_ID = @Site)
GROUP BY r.PART_ID, psv.DESCRIPTION, psv.PRODUCT_CODE, r.YR
ORDER BY r.PART_ID, r.YR;
