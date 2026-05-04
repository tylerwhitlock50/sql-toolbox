/*
===============================================================================
Query Name: waste_and_stagnation.sql

Purpose:
    Single multi-category waste/stagnation report for executive review.
    Each row is one issue (one part, one WO, or one PO line) tagged with:

        CATEGORY        -- which waste pattern matched
        DOLLAR_IMPACT   -- $ tied up / at risk
        SUGGESTED_ACTION-- short next step

    Categories:
      1. STAGNANT_INVENTORY  on-hand $ > @MinStagnantValue with no
                             INVENTORY_TRANS in @StagnantMonths months
      2. EXCESS_COVERAGE     on-hand months of supply > @ExcessMonths
                             based on trailing-12 issue history
      3. DEAD_PURCHASED_PART on-hand > 0 AND no open demand AND no open
                             requirement AND no usage in @StagnantMonths
      4. ORPHAN_WO           open WO with no INVENTORY_TRANS / labor in
                             @OrphanWODays days
      5. EARLY_PO            open PO line arriving > @EarlyDays before
                             the earliest related demand need date
                             (cash-flow drag)

Grain:
    One row per issue (mixed grain across categories). Use CATEGORY to
    drill down or filter.

Typical use:
    Quarterly waste review. Sort by DOLLAR_IMPACT desc to attack the
    biggest cash-stuck items first. The executive_supply_chain_kpis.sql
    rollup re-uses the totals via summing this query's output by category.
===============================================================================
*/

DECLARE @Site               nvarchar(15) = NULL;
DECLARE @MinStagnantValue   decimal(15,2) = 1000;   -- ignore noise
DECLARE @StagnantMonths     int           = 12;
DECLARE @ExcessMonths       decimal(5,2)  = 12;
DECLARE @OrphanWODays       int           = 60;
DECLARE @EarlyDays          int           = 30;

;WITH
-- ============================================================
-- Last activity date per (site, part) from INVENTORY_TRANS
-- ============================================================
last_movement AS (
    SELECT it.SITE_ID, it.PART_ID, MAX(it.TRANSACTION_DATE) AS LAST_TRANS_DATE
    FROM INVENTORY_TRANS it
    WHERE it.PART_ID IS NOT NULL
      AND (@Site IS NULL OR it.SITE_ID = @Site)
    GROUP BY it.SITE_ID, it.PART_ID
),

-- ============================================================
-- Trailing-12-month issue qty per (site, part)
-- ============================================================
issue_history AS (
    SELECT it.SITE_ID, it.PART_ID,
           SUM(it.QTY) AS QTY_ISSUED_T12
    FROM INVENTORY_TRANS it
    WHERE it.TYPE = 'O'                -- outbound
      AND it.PART_ID IS NOT NULL
      AND it.TRANSACTION_DATE >= DATEADD(month, -12, GETDATE())
      AND (@Site IS NULL OR it.SITE_ID = @Site)
    GROUP BY it.SITE_ID, it.PART_ID
),

-- ============================================================
-- Open SO direct demand per (site, part)
-- ============================================================
so_demand AS (
    SELECT col.SITE_ID, col.PART_ID,
           SUM(col.ORDER_QTY - col.TOTAL_SHIPPED_QTY) AS OPEN_SO_QTY
    FROM CUST_ORDER_LINE col
    INNER JOIN CUSTOMER_ORDER co ON co.ID = col.CUST_ORDER_ID
    WHERE co.STATUS IN ('R','F') AND col.LINE_STATUS='A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
      AND col.PART_ID IS NOT NULL
      AND (@Site IS NULL OR col.SITE_ID = @Site)
    GROUP BY col.SITE_ID, col.PART_ID
),

-- ============================================================
-- Open WO requirements per (site, part) -- demand for components
-- ============================================================
wo_demand AS (
    SELECT wo.SITE_ID, rq.PART_ID,
           SUM(rq.CALC_QTY - rq.ISSUED_QTY) AS OPEN_REQ_QTY
    FROM REQUIREMENT rq
    INNER JOIN WORK_ORDER wo
        ON wo.TYPE     = rq.WORKORDER_TYPE
       AND wo.BASE_ID  = rq.WORKORDER_BASE_ID
       AND wo.LOT_ID   = rq.WORKORDER_LOT_ID
       AND wo.SPLIT_ID = rq.WORKORDER_SPLIT_ID
       AND wo.SUB_ID   = rq.WORKORDER_SUB_ID
    WHERE rq.STATUS = 'U'
      AND ISNULL(wo.STATUS,'') NOT IN ('X','C')
      AND wo.TYPE = 'W'
      AND rq.PART_ID IS NOT NULL
      AND rq.CALC_QTY > rq.ISSUED_QTY
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
    GROUP BY wo.SITE_ID, rq.PART_ID
),

-- ============================================================
-- Part-level snapshot (joined once for all category checks)
-- ============================================================
part_snapshot AS (
    SELECT
        psv.SITE_ID,
        psv.PART_ID,
        psv.DESCRIPTION,
        psv.PRODUCT_CODE,
        psv.COMMODITY_CODE,
        psv.STOCK_UM,
        psv.FABRICATED, psv.PURCHASED, psv.STOCKED, psv.DETAIL_ONLY,
        psv.PLANNER_USER_ID, psv.BUYER_USER_ID, psv.ABC_CODE,
        ISNULL(psv.QTY_ON_HAND, 0)            AS QTY_ON_HAND,
        ISNULL(psv.UNIT_MATERIAL_COST, 0)     AS UNIT_COST,
        ISNULL(psv.QTY_ON_HAND, 0) * ISNULL(psv.UNIT_MATERIAL_COST, 0) AS ON_HAND_VALUE,
        lm.LAST_TRANS_DATE,
        DATEDIFF(month, lm.LAST_TRANS_DATE, GETDATE()) AS MONTHS_SINCE_MOVE,
        ISNULL(ih.QTY_ISSUED_T12, 0)          AS QTY_ISSUED_T12,
        CASE WHEN ISNULL(ih.QTY_ISSUED_T12, 0) > 0
             THEN ISNULL(psv.QTY_ON_HAND, 0)
                  / (ih.QTY_ISSUED_T12 / 12.0)
             ELSE NULL
        END                                    AS MONTHS_OF_SUPPLY_ON_HAND,
        -- Same calc as MONTHS_OF_SUPPLY_ON_HAND, expressed in weeks so the
        -- excess narrative can present coverage in either unit.
        CASE WHEN ISNULL(ih.QTY_ISSUED_T12, 0) > 0
             THEN ISNULL(psv.QTY_ON_HAND, 0)
                  / (ih.QTY_ISSUED_T12 / 52.0)
             ELSE NULL
        END                                    AS WEEKS_OF_SUPPLY_ON_HAND,
        ISNULL(sd.OPEN_SO_QTY, 0)             AS OPEN_SO_QTY,
        ISNULL(wd.OPEN_REQ_QTY, 0)            AS OPEN_REQ_QTY
    FROM PART_SITE_VIEW psv
    LEFT JOIN last_movement  lm ON lm.SITE_ID=psv.SITE_ID AND lm.PART_ID=psv.PART_ID
    LEFT JOIN issue_history  ih ON ih.SITE_ID=psv.SITE_ID AND ih.PART_ID=psv.PART_ID
    LEFT JOIN so_demand      sd ON sd.SITE_ID=psv.SITE_ID AND sd.PART_ID=psv.PART_ID
    LEFT JOIN wo_demand      wd ON wd.SITE_ID=psv.SITE_ID AND wd.PART_ID=psv.PART_ID
    WHERE (@Site IS NULL OR psv.SITE_ID = @Site)
      AND ISNULL(psv.QTY_ON_HAND, 0) > 0
),

-- ============================================================
-- Category 1: Stagnant inventory
-- ============================================================
stagnant AS (
    SELECT
        CAST('STAGNANT_INVENTORY' AS nvarchar(40)) AS CATEGORY,
        SITE_ID, PART_ID, DESCRIPTION,
        CAST(ON_HAND_VALUE AS decimal(23,2))     AS DOLLAR_IMPACT,
        CAST(NULL AS nvarchar(15))               AS REF_ID,
        CAST(NULL AS smallint)                   AS REF_LINE,
        CAST(NULL AS date)                       AS REF_DATE,
        CONCAT('On-hand $',
               CAST(CAST(ON_HAND_VALUE AS decimal(15,0)) AS nvarchar(20)),
               ', no movement in ',
               CAST(MONTHS_SINCE_MOVE AS nvarchar(10)),
               ' months. Last move: ',
               COALESCE(CONVERT(nvarchar(10), LAST_TRANS_DATE, 23), 'NEVER')) AS DETAIL,
        CAST('Cycle count + scrap/return review.' AS nvarchar(120)) AS SUGGESTED_ACTION,
        ABC_CODE, BUYER_USER_ID, PLANNER_USER_ID
    FROM part_snapshot
    WHERE ON_HAND_VALUE >= @MinStagnantValue
      AND (LAST_TRANS_DATE IS NULL OR
           LAST_TRANS_DATE < DATEADD(month, -@StagnantMonths, GETDATE()))
),

-- ============================================================
-- Category 2: Excess coverage (way more on-hand than needed)
-- ============================================================
excess AS (
    SELECT
        CAST('EXCESS_COVERAGE' AS nvarchar(40)) AS CATEGORY,
        SITE_ID, PART_ID, DESCRIPTION,
        CAST(
            CASE WHEN MONTHS_OF_SUPPLY_ON_HAND IS NULL THEN ON_HAND_VALUE
                 WHEN MONTHS_OF_SUPPLY_ON_HAND <= @ExcessMonths THEN 0
                 ELSE ON_HAND_VALUE
                      * (MONTHS_OF_SUPPLY_ON_HAND - @ExcessMonths)
                      / MONTHS_OF_SUPPLY_ON_HAND
            END AS decimal(23,2)) AS DOLLAR_IMPACT,
        CAST(NULL AS nvarchar(15)) AS REF_ID,
        CAST(NULL AS smallint)     AS REF_LINE,
        CAST(NULL AS date)         AS REF_DATE,
        CONCAT(CAST(CAST(MONTHS_OF_SUPPLY_ON_HAND AS decimal(10,1)) AS nvarchar(20)),
               ' months (~',
               CAST(CAST(WEEKS_OF_SUPPLY_ON_HAND AS decimal(10,1)) AS nvarchar(20)),
               ' weeks) of supply on hand (threshold ',
               CAST(@ExcessMonths AS nvarchar(10)), ' months). T12 issues = ',
               CAST(CAST(QTY_ISSUED_T12 AS decimal(15,2)) AS nvarchar(30))) AS DETAIL,
        CAST('Reduce future buys; consider transfer or excess sale.' AS nvarchar(120)) AS SUGGESTED_ACTION,
        ABC_CODE, BUYER_USER_ID, PLANNER_USER_ID
    FROM part_snapshot
    WHERE MONTHS_OF_SUPPLY_ON_HAND > @ExcessMonths
      AND ON_HAND_VALUE >= @MinStagnantValue
),

-- ============================================================
-- Category 3: Dead purchased parts (no demand at all)
-- ============================================================
dead AS (
    SELECT
        CAST('DEAD_PURCHASED_PART' AS nvarchar(40)) AS CATEGORY,
        SITE_ID, PART_ID, DESCRIPTION,
        CAST(ON_HAND_VALUE AS decimal(23,2)) AS DOLLAR_IMPACT,
        CAST(NULL AS nvarchar(15)) AS REF_ID,
        CAST(NULL AS smallint)     AS REF_LINE,
        CAST(NULL AS date)         AS REF_DATE,
        CONCAT('On-hand $',
               CAST(CAST(ON_HAND_VALUE AS decimal(15,0)) AS nvarchar(20)),
               '. Zero open SO demand, zero open WO requirement, no movement in ',
               CAST(ISNULL(MONTHS_SINCE_MOVE, 999) AS nvarchar(10)),
               ' months.') AS DETAIL,
        CAST('Candidate for scrap, return, or sale-to-vendor.' AS nvarchar(120)) AS SUGGESTED_ACTION,
        ABC_CODE, BUYER_USER_ID, PLANNER_USER_ID
    FROM part_snapshot
    WHERE PURCHASED = 'Y'
      AND ISNULL(FABRICATED,'N') <> 'Y'
      AND ON_HAND_VALUE >= @MinStagnantValue
      AND OPEN_SO_QTY = 0
      AND OPEN_REQ_QTY = 0
      AND (LAST_TRANS_DATE IS NULL OR
           LAST_TRANS_DATE < DATEADD(month, -@StagnantMonths, GETDATE()))
),

-- ============================================================
-- Category 4: Orphan WOs (open but no recent activity)
-- ============================================================
wo_last_activity AS (
    SELECT it.WORKORDER_TYPE, it.WORKORDER_BASE_ID, it.WORKORDER_LOT_ID,
           it.WORKORDER_SPLIT_ID, it.WORKORDER_SUB_ID,
           MAX(it.TRANSACTION_DATE) AS LAST_ACTIVITY
    FROM INVENTORY_TRANS it
    WHERE it.WORKORDER_BASE_ID IS NOT NULL
    GROUP BY it.WORKORDER_TYPE, it.WORKORDER_BASE_ID, it.WORKORDER_LOT_ID,
             it.WORKORDER_SPLIT_ID, it.WORKORDER_SUB_ID
),
orphan AS (
    SELECT
        CAST('ORPHAN_WO' AS nvarchar(40)) AS CATEGORY,
        wo.SITE_ID,
        wo.PART_ID,
        psv.DESCRIPTION,
        CAST(ISNULL(wo.ACT_MATERIAL_COST,0)
             + ISNULL(wo.ACT_LABOR_COST,0)
             + ISNULL(wo.ACT_BURDEN_COST,0)
             + ISNULL(wo.ACT_SERVICE_COST,0) AS decimal(23,2)) AS DOLLAR_IMPACT,
        CAST(wo.BASE_ID AS nvarchar(15))   AS REF_ID,
        CAST(NULL       AS smallint)       AS REF_LINE,
        CAST(wo.CREATE_DATE AS date)       AS REF_DATE,
        CONCAT('WO ', wo.TYPE, '/', wo.BASE_ID, '/', wo.LOT_ID,
               '/', wo.SPLIT_ID, '/', wo.SUB_ID,
               ' open since ',
               CONVERT(nvarchar(10), wo.CREATE_DATE, 23),
               '. Last activity: ',
               COALESCE(CONVERT(nvarchar(10), la.LAST_ACTIVITY, 23), 'NEVER'),
               '. Status: ', wo.STATUS) AS DETAIL,
        CAST('Close, cancel, or reschedule. Free up WIP.' AS nvarchar(120)) AS SUGGESTED_ACTION,
        psv.ABC_CODE,
        CAST(NULL AS nvarchar(20))         AS BUYER_USER_ID,
        psv.PLANNER_USER_ID
    FROM WORK_ORDER wo
    LEFT JOIN wo_last_activity la
        ON la.WORKORDER_TYPE     = wo.TYPE
       AND la.WORKORDER_BASE_ID  = wo.BASE_ID
       AND la.WORKORDER_LOT_ID   = wo.LOT_ID
       AND la.WORKORDER_SPLIT_ID = wo.SPLIT_ID
       AND la.WORKORDER_SUB_ID   = wo.SUB_ID
    LEFT JOIN PART_SITE_VIEW psv
        ON psv.SITE_ID=wo.SITE_ID AND psv.PART_ID=wo.PART_ID
    WHERE wo.TYPE = 'W'
      AND ISNULL(wo.STATUS,'') NOT IN ('X','C','M')
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
      AND (la.LAST_ACTIVITY IS NULL
           OR la.LAST_ACTIVITY < DATEADD(day, -@OrphanWODays, GETDATE()))
      AND wo.CREATE_DATE < DATEADD(day, -@OrphanWODays, GETDATE())
),

-- ============================================================
-- Category 5: Early POs (arriving well before need = cash drag)
-- ============================================================
po_open AS (
    SELECT
        p.SITE_ID, p.ID AS PURC_ORDER_ID, pl.LINE_NO,
        pl.PART_ID,
        COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE) AS RECV_DATE,
        (pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY)              AS OPEN_QTY,
        (pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY) * pl.UNIT_PRICE AS OPEN_VALUE,
        p.VENDOR_ID
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl ON pl.PURC_ORDER_ID = p.ID
    WHERE ISNULL(p.STATUS,'') NOT IN ('X','C')
      AND ISNULL(pl.LINE_STATUS,'') NOT IN ('X','C')
      AND pl.PART_ID IS NOT NULL
      AND pl.ORDER_QTY > pl.TOTAL_RECEIVED_QTY
      AND COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE) IS NOT NULL
      AND (@Site IS NULL OR p.SITE_ID = @Site)
),
earliest_demand_per_part AS (
    SELECT col.SITE_ID, col.PART_ID,
           MIN(COALESCE(col.PROMISE_DATE, col.DESIRED_SHIP_DATE,
                        co.DESIRED_SHIP_DATE)) AS FIRST_DEMAND_DATE
    FROM CUST_ORDER_LINE col
    INNER JOIN CUSTOMER_ORDER co ON co.ID = col.CUST_ORDER_ID
    WHERE co.STATUS IN ('R','F') AND col.LINE_STATUS='A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
      AND col.PART_ID IS NOT NULL
    GROUP BY col.SITE_ID, col.PART_ID

    UNION ALL

    SELECT wo.SITE_ID, rq.PART_ID, MIN(rq.REQUIRED_DATE)
    FROM REQUIREMENT rq
    INNER JOIN WORK_ORDER wo
        ON wo.TYPE=rq.WORKORDER_TYPE AND wo.BASE_ID=rq.WORKORDER_BASE_ID
       AND wo.LOT_ID=rq.WORKORDER_LOT_ID AND wo.SPLIT_ID=rq.WORKORDER_SPLIT_ID
       AND wo.SUB_ID=rq.WORKORDER_SUB_ID
    WHERE rq.STATUS='U'
      AND ISNULL(wo.STATUS,'') NOT IN ('X','C')
      AND wo.TYPE='W'
      AND rq.PART_ID IS NOT NULL
      AND rq.CALC_QTY > rq.ISSUED_QTY
    GROUP BY wo.SITE_ID, rq.PART_ID
),
earliest_demand AS (
    SELECT SITE_ID, PART_ID, MIN(FIRST_DEMAND_DATE) AS FIRST_DEMAND_DATE
    FROM earliest_demand_per_part
    GROUP BY SITE_ID, PART_ID
),
early AS (
    SELECT
        CAST('EARLY_PO' AS nvarchar(40)) AS CATEGORY,
        po.SITE_ID,
        po.PART_ID,
        psv.DESCRIPTION,
        CAST(po.OPEN_VALUE AS decimal(23,2)) AS DOLLAR_IMPACT,
        po.PURC_ORDER_ID                     AS REF_ID,
        po.LINE_NO                           AS REF_LINE,
        CAST(po.RECV_DATE AS date)           AS REF_DATE,
        CONCAT('PO ', po.PURC_ORDER_ID, ' line ', CAST(po.LINE_NO AS nvarchar(10)),
               ' arrives ', CONVERT(nvarchar(10), po.RECV_DATE, 23),
               ' but earliest demand is ',
               COALESCE(CONVERT(nvarchar(10), ed.FIRST_DEMAND_DATE, 23), 'NONE'),
               ' (',
               CAST(DATEDIFF(day, po.RECV_DATE, ed.FIRST_DEMAND_DATE) AS nvarchar(10)),
               ' days early).') AS DETAIL,
        CAST('Push back receipt date or release in waves.' AS nvarchar(120)) AS SUGGESTED_ACTION,
        psv.ABC_CODE,
        psv.BUYER_USER_ID,
        psv.PLANNER_USER_ID
    FROM po_open po
    INNER JOIN earliest_demand ed
        ON ed.SITE_ID = po.SITE_ID AND ed.PART_ID = po.PART_ID
    LEFT JOIN PART_SITE_VIEW psv
        ON psv.SITE_ID=po.SITE_ID AND psv.PART_ID=po.PART_ID
    WHERE DATEDIFF(day, po.RECV_DATE, ed.FIRST_DEMAND_DATE) >= @EarlyDays
      AND po.OPEN_VALUE >= @MinStagnantValue
)

SELECT * FROM stagnant
UNION ALL SELECT * FROM excess
UNION ALL SELECT * FROM dead
UNION ALL SELECT * FROM orphan
UNION ALL SELECT * FROM early
ORDER BY DOLLAR_IMPACT DESC;
