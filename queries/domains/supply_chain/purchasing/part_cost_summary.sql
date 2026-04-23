-- =========================================================================
-- Part cost summary — last purchase, current weighted avg, standard cost
-- =========================================================================
-- One row per part at a site with:
--   * Standard cost from PART_SITE (what accounting thinks the part costs)
--   * Current weighted-average cost from the full INVENTORY_TRANS history
--     (net $ in/out divided by net qty in/out — the "book value per unit"
--     remaining on the shelf)
--   * Last PO receipt (date, PO, qty, unit cost)
--   * Lifetime receipt stats (count, total qty, lifetime weighted avg)
--   * Variance of current weighted avg vs. standard material cost
--
-- Pair with purchase_price_history_yearly.sql for a yearly breakdown.
--
-- Current cost math (per the user's formula):
--   net_value = SUM(CASE WHEN type='I' THEN tot_cost ELSE -tot_cost END)
--   net_qty   = SUM(CASE WHEN type='I' THEN qty      ELSE -qty      END)
--   current_unit_cost = net_value / net_qty
--   tot_cost = act_material + act_labor + act_burden + act_service
--
-- Caveat: this is a moving-average snapshot computed from scratch. For most
-- purchased parts it matches PART_SITE.UNIT_MATERIAL_COST closely. Big
-- divergences usually mean (a) a pending cost roll, (b) a receipt that was
-- costed differently than the standard, or (c) a data issue worth chasing.
-- =========================================================================

DECLARE @Site nvarchar(15) = 'TDJ';   -- set to NULL for all sites

;WITH net_cost AS
(
    -- All-time net inventory $ and qty per (part, site)
    SELECT
        it.PART_ID,
        it.SITE_ID,
        SUM(CASE WHEN it.TYPE = 'I'
                 THEN it.ACT_MATERIAL_COST + it.ACT_LABOR_COST
                    + it.ACT_BURDEN_COST   + it.ACT_SERVICE_COST
                 ELSE -(it.ACT_MATERIAL_COST + it.ACT_LABOR_COST
                      + it.ACT_BURDEN_COST   + it.ACT_SERVICE_COST)
            END)                                        AS NET_VALUE,
        SUM(CASE WHEN it.TYPE = 'I' THEN it.QTY ELSE -it.QTY END) AS NET_QTY
    FROM   INVENTORY_TRANS it
    WHERE  it.PART_ID IS NOT NULL
      AND  (@Site IS NULL OR it.SITE_ID = @Site)
    GROUP BY it.PART_ID, it.SITE_ID
),
receipt_ranked AS
(
    -- All PO receipts, numbered newest-first per (part, site)
    SELECT
        it.PART_ID,
        it.SITE_ID,
        it.TRANSACTION_DATE,
        it.PURC_ORDER_ID,
        it.PURC_ORDER_LINE_NO,
        it.QTY,
        it.ACT_MATERIAL_COST,
        CAST(it.ACT_MATERIAL_COST / it.QTY AS decimal(22,8)) AS UNIT_COST,
        ROW_NUMBER() OVER (
            PARTITION BY it.PART_ID, it.SITE_ID
            ORDER BY it.TRANSACTION_DATE DESC, it.ROWID DESC
        )                                               AS RN
    FROM   INVENTORY_TRANS it
    WHERE  it.TYPE            = 'I'
      AND  it.CLASS           = 'R'
      AND  it.PURC_ORDER_ID  IS NOT NULL
      AND  it.PART_ID        IS NOT NULL
      AND  it.QTY                 > 0
      AND  it.ACT_MATERIAL_COST   > 0
      AND  (@Site IS NULL OR it.SITE_ID = @Site)
),
receipt_stats AS
(
    -- Lifetime PO-receipt stats per (part, site)
    SELECT
        PART_ID,
        SITE_ID,
        MIN(TRANSACTION_DATE)                           AS FIRST_RECEIPT_DATE,
        COUNT(*)                                        AS TOTAL_RECEIPTS,
        SUM(QTY)                                        AS TOTAL_QTY_RECEIVED,
        SUM(ACT_MATERIAL_COST)                          AS TOTAL_RECEIVED_VALUE
    FROM   receipt_ranked
    GROUP BY PART_ID, SITE_ID
)
SELECT
    psv.SITE_ID,
    psv.PART_ID,
    psv.DESCRIPTION,
    psv.PRODUCT_CODE,
    psv.FABRICATED,
    psv.PURCHASED,
    psv.STOCKED,
    psv.ABC_CODE,

    -- ---- Standard costs (PART_SITE) ----
    psv.UNIT_MATERIAL_COST                              AS STD_MATERIAL_COST,
    psv.UNIT_LABOR_COST                                 AS STD_LABOR_COST,
    psv.UNIT_BURDEN_COST                                AS STD_BURDEN_COST,
    psv.UNIT_SERVICE_COST                               AS STD_SERVICE_COST,
    (psv.UNIT_MATERIAL_COST + psv.UNIT_LABOR_COST
     + psv.UNIT_BURDEN_COST + psv.UNIT_SERVICE_COST)    AS STD_TOTAL_COST,

    -- ---- On-hand qty for reference ----
    psv.QTY_ON_HAND,

    -- ---- Current weighted-average cost (from INVENTORY_TRANS net flow) ----
    nc.NET_VALUE                                        AS CURRENT_NET_VALUE,
    nc.NET_QTY                                          AS CURRENT_NET_QTY,
    CAST(nc.NET_VALUE / NULLIF(nc.NET_QTY, 0) AS decimal(22,8))
                                                        AS CURRENT_UNIT_COST,

    -- Variance: current vs. standard material cost
    CAST(
        (CAST(nc.NET_VALUE / NULLIF(nc.NET_QTY, 0) AS decimal(22,8))
         - psv.UNIT_MATERIAL_COST)
        / NULLIF(psv.UNIT_MATERIAL_COST, 0) * 100
    AS decimal(10,2))                                   AS CURRENT_VS_STD_MAT_PCT,

    -- ---- Last PO receipt ----
    lr.TRANSACTION_DATE                                 AS LAST_RECEIPT_DATE,
    lr.PURC_ORDER_ID                                    AS LAST_PO_ID,
    lr.PURC_ORDER_LINE_NO                               AS LAST_PO_LINE_NO,
    lr.QTY                                              AS LAST_RECEIPT_QTY,
    lr.UNIT_COST                                        AS LAST_UNIT_COST,

    -- Variance: last PO price vs. standard
    CAST(
        (lr.UNIT_COST - psv.UNIT_MATERIAL_COST)
        / NULLIF(psv.UNIT_MATERIAL_COST, 0) * 100
    AS decimal(10,2))                                   AS LAST_VS_STD_MAT_PCT,

    -- ---- Lifetime receipt stats ----
    rs.FIRST_RECEIPT_DATE,
    rs.TOTAL_RECEIPTS,
    rs.TOTAL_QTY_RECEIVED,
    rs.TOTAL_RECEIVED_VALUE,
    CAST(rs.TOTAL_RECEIVED_VALUE / NULLIF(rs.TOTAL_QTY_RECEIVED, 0) AS decimal(22,8))
                                                        AS LIFETIME_WTD_AVG_UNIT_COST
FROM   PART_SITE_VIEW psv
LEFT   JOIN net_cost      nc ON nc.PART_ID = psv.PART_ID AND nc.SITE_ID = psv.SITE_ID
LEFT   JOIN receipt_ranked lr ON lr.PART_ID = psv.PART_ID AND lr.SITE_ID = psv.SITE_ID AND lr.RN = 1
LEFT   JOIN receipt_stats  rs ON rs.PART_ID = psv.PART_ID AND rs.SITE_ID = psv.SITE_ID
WHERE  (@Site IS NULL OR psv.SITE_ID = @Site)
  -- Only rows that have either inventory activity or PO history
  AND  (nc.NET_QTY IS NOT NULL OR rs.PART_ID IS NOT NULL)
ORDER BY psv.PART_ID;
