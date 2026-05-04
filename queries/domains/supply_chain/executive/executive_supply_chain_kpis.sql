/*
===============================================================================
Query Name: executive_supply_chain_kpis.sql

Purpose:
    Single-row (per site) snapshot of supply-chain health for executive
    review. Designed to be eyeballed in seconds.

    Pulls from the same logic as the deeper queries in this folder so the
    headline number always matches what you'd see if you drilled in:

        Backlog / Backorder $   <- so_header_and_lines_open_orders
        WIP $                   <- open_wo_aging_and_wip pattern
        Inventory $             <- PART_SITE_VIEW.QTY_ON_HAND * UNIT_MATERIAL_COST
        Inventory turns         <- T12 issue value / avg inventory $
        Open PO $ / Past-due $  <- past_due_po_aging pattern
        Vendor OTD % (T90)      <- vendor_otd_scorecard pattern
        Customer OTD % (T90)    <- customer_otd_scorecard pattern
        Net shortages           <- material_shortage_vs_open_demand pattern
        Stagnant inv $          <- waste_and_stagnation pattern

Grain:
    One row per SITE_ID (or one row total if @Site is set).
    Add an "ALL SITES" rollup at the end when running multi-site.

Notes:
    Self-contained -- aggregates from base tables, no temp/results
    dependencies. Can be run on its own.
===============================================================================
*/

DECLARE @Site       nvarchar(15) = NULL;
DECLARE @AsOfDate   date         = CAST(GETDATE() AS date);
DECLARE @OtdLookbackDays int     = 90;
DECLARE @StagnantMonths  int     = 12;

;WITH
sites AS (
    SELECT DISTINCT SITE_ID
    FROM PART_SITE_VIEW
    WHERE (@Site IS NULL OR SITE_ID = @Site)
),

-- ============================================================
-- Sales backlog (open orders) and past-due
-- ============================================================
backlog AS (
    SELECT
        col.SITE_ID,
        SUM((col.ORDER_QTY - col.TOTAL_SHIPPED_QTY) * col.UNIT_PRICE) AS BACKLOG_VALUE,
        SUM(CASE
            WHEN COALESCE(col.PROMISE_DATE, col.DESIRED_SHIP_DATE,
                          co.DESIRED_SHIP_DATE) < @AsOfDate
            THEN (col.ORDER_QTY - col.TOTAL_SHIPPED_QTY) * col.UNIT_PRICE
            ELSE 0
        END)                                                          AS PAST_DUE_BACKLOG_VALUE,
        COUNT(*)                                                      AS OPEN_LINES,
        SUM(CASE
            WHEN COALESCE(col.PROMISE_DATE, col.DESIRED_SHIP_DATE,
                          co.DESIRED_SHIP_DATE) < @AsOfDate
            THEN 1 ELSE 0
        END)                                                          AS PAST_DUE_LINES
    FROM CUST_ORDER_LINE col
    INNER JOIN CUSTOMER_ORDER co ON co.ID = col.CUST_ORDER_ID
    WHERE co.STATUS IN ('R','F') AND col.LINE_STATUS='A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
      AND col.PART_ID IS NOT NULL
      AND (@Site IS NULL OR col.SITE_ID = @Site)
    GROUP BY col.SITE_ID
),

-- ============================================================
-- WIP $ (open Work Orders, remaining cost)
-- ============================================================
wip AS (
    SELECT
        wo.SITE_ID,
        SUM(ISNULL(wo.ACT_MATERIAL_COST, 0)
            + ISNULL(wo.ACT_LABOR_COST, 0)
            + ISNULL(wo.ACT_BURDEN_COST, 0)
            + ISNULL(wo.ACT_SERVICE_COST, 0)) AS WIP_VALUE,
        COUNT(*)                              AS OPEN_WO_COUNT
    FROM WORK_ORDER wo
    WHERE wo.TYPE = 'W'
      AND ISNULL(wo.STATUS,'') NOT IN ('X','C')
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
    GROUP BY wo.SITE_ID
),

-- ============================================================
-- Inventory $ (current on-hand at standard cost)
-- ============================================================
inventory AS (
    SELECT
        psv.SITE_ID,
        SUM(ISNULL(psv.QTY_ON_HAND, 0) * ISNULL(psv.UNIT_MATERIAL_COST, 0)) AS INVENTORY_VALUE,
        SUM(CASE WHEN psv.QTY_ON_HAND > 0 THEN 1 ELSE 0 END) AS PARTS_WITH_STOCK
    FROM PART_SITE_VIEW psv
    WHERE (@Site IS NULL OR psv.SITE_ID = @Site)
    GROUP BY psv.SITE_ID
),

-- ============================================================
-- Trailing-12mo issue value -> proxy for "annual COGS material" used
-- in turns. Uses cost-of-issue (ACT_*).
-- ============================================================
issue_t12 AS (
    SELECT
        it.SITE_ID,
        SUM(ISNULL(it.ACT_MATERIAL_COST,0)
            + ISNULL(it.ACT_LABOR_COST,0)
            + ISNULL(it.ACT_BURDEN_COST,0)
            + ISNULL(it.ACT_SERVICE_COST,0)) AS ISSUE_VALUE_T12
    FROM INVENTORY_TRANS it
    WHERE it.TYPE='O'
      AND it.TRANSACTION_DATE >= DATEADD(month, -12, GETDATE())
      AND (@Site IS NULL OR it.SITE_ID = @Site)
    GROUP BY it.SITE_ID
),

-- ============================================================
-- Open PO $ + past-due
-- ============================================================
purchasing AS (
    SELECT
        p.SITE_ID,
        SUM((pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY) * pl.UNIT_PRICE) AS OPEN_PO_VALUE,
        SUM(CASE
            WHEN COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE) < @AsOfDate
            THEN (pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY) * pl.UNIT_PRICE
            ELSE 0
        END)                                                         AS PAST_DUE_PO_VALUE,
        COUNT(*)                                                     AS OPEN_PO_LINES,
        SUM(CASE
            WHEN COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE) < @AsOfDate
            THEN 1 ELSE 0
        END)                                                         AS PAST_DUE_PO_LINES
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl ON pl.PURC_ORDER_ID = p.ID
    WHERE ISNULL(p.STATUS,'') NOT IN ('X','C')
      AND ISNULL(pl.LINE_STATUS,'') NOT IN ('X','C')
      AND pl.PART_ID IS NOT NULL
      AND pl.ORDER_QTY > pl.TOTAL_RECEIVED_QTY
      AND (@Site IS NULL OR p.SITE_ID = @Site)
    GROUP BY p.SITE_ID
),

-- ============================================================
-- Vendor OTD trailing-N days
-- ============================================================
vendor_otd AS (
    SELECT
        it.SITE_ID,
        COUNT(*) AS RECV_COUNT,
        SUM(CASE WHEN p.PROMISE_DATE IS NOT NULL
                  AND it.TRANSACTION_DATE <= p.PROMISE_DATE THEN 1 ELSE 0 END) AS RECV_ON_TIME,
        SUM(CASE WHEN p.PROMISE_DATE IS NOT NULL THEN 1 ELSE 0 END) AS RECV_WITH_PROMISE
    FROM INVENTORY_TRANS it
    INNER JOIN PURCHASE_ORDER p ON p.ID = it.PURC_ORDER_ID
    WHERE it.TYPE='I' AND it.CLASS='R' AND it.PURC_ORDER_ID IS NOT NULL
      AND it.QTY > 0
      AND it.TRANSACTION_DATE >= DATEADD(day, -@OtdLookbackDays, GETDATE())
      AND (@Site IS NULL OR it.SITE_ID = @Site)
    GROUP BY it.SITE_ID
),

-- ============================================================
-- Customer OTD trailing-N days (from CUST_LINE_DEL)
-- ============================================================
customer_otd AS (
    SELECT
        cld.WAREHOUSE_ID                            AS X_DUMMY,    -- not used; included to keep grouping clean
        col.SITE_ID,
        COUNT(*)                                    AS SHIPMENT_COUNT,
        SUM(CASE WHEN cld.ACTUAL_SHIP_DATE <= cld.DESIRED_SHIP_DATE THEN 1 ELSE 0 END) AS ON_TIME_SHIPMENTS
    FROM CUST_LINE_DEL cld
    INNER JOIN CUST_ORDER_LINE col
        ON col.CUST_ORDER_ID = cld.CUST_ORDER_ID
       AND col.LINE_NO       = cld.CUST_ORDER_LINE_NO
    WHERE cld.ACTUAL_SHIP_DATE IS NOT NULL
      AND cld.DESIRED_SHIP_DATE IS NOT NULL
      AND cld.ACTUAL_SHIP_DATE >= DATEADD(day, -@OtdLookbackDays, GETDATE())
      AND (@Site IS NULL OR col.SITE_ID = @Site)
    GROUP BY col.SITE_ID, cld.WAREHOUSE_ID
),
customer_otd_rolled AS (
    SELECT SITE_ID,
           SUM(SHIPMENT_COUNT)   AS SHIPMENT_COUNT,
           SUM(ON_TIME_SHIPMENTS) AS ON_TIME_SHIPMENTS
    FROM customer_otd
    GROUP BY SITE_ID
),

-- ============================================================
-- Net shortages: parts where projected (on-hand + open supply
-- - open WO requirements) < 0
-- ============================================================
open_wo_req AS (
    SELECT wo.SITE_ID, rq.PART_ID,
           SUM(rq.CALC_QTY - rq.ISSUED_QTY) AS OPEN_REQ_QTY
    FROM REQUIREMENT rq
    INNER JOIN WORK_ORDER wo
        ON wo.TYPE     = rq.WORKORDER_TYPE
       AND wo.BASE_ID  = rq.WORKORDER_BASE_ID
       AND wo.LOT_ID   = rq.WORKORDER_LOT_ID
       AND wo.SPLIT_ID = rq.WORKORDER_SPLIT_ID
       AND wo.SUB_ID   = rq.WORKORDER_SUB_ID
    WHERE rq.STATUS='U'
      AND ISNULL(wo.STATUS,'') NOT IN ('X','C')
      AND wo.TYPE = 'W'
      AND rq.PART_ID IS NOT NULL
      AND rq.CALC_QTY > rq.ISSUED_QTY
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
    GROUP BY wo.SITE_ID, rq.PART_ID
),
open_po_qty AS (
    SELECT p.SITE_ID, pl.PART_ID,
           SUM(pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY) AS OPEN_PO_QTY
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl ON pl.PURC_ORDER_ID = p.ID
    WHERE ISNULL(p.STATUS,'') NOT IN ('X','C')
      AND ISNULL(pl.LINE_STATUS,'') NOT IN ('X','C')
      AND pl.PART_ID IS NOT NULL
      AND pl.ORDER_QTY > pl.TOTAL_RECEIVED_QTY
      AND (@Site IS NULL OR p.SITE_ID = @Site)
    GROUP BY p.SITE_ID, pl.PART_ID
),
shortages AS (
    SELECT
        psv.SITE_ID,
        SUM(CASE
            WHEN ISNULL(psv.QTY_ON_HAND,0)
                 + ISNULL(po.OPEN_PO_QTY,0)
                 - ISNULL(req.OPEN_REQ_QTY,0) < 0
            THEN 1 ELSE 0
        END) AS PARTS_SHORT,
        SUM(CASE
            WHEN ISNULL(psv.QTY_ON_HAND,0)
                 + ISNULL(po.OPEN_PO_QTY,0)
                 - ISNULL(req.OPEN_REQ_QTY,0) < 0
            THEN ABS(ISNULL(psv.QTY_ON_HAND,0)
                     + ISNULL(po.OPEN_PO_QTY,0)
                     - ISNULL(req.OPEN_REQ_QTY,0))
                 * ISNULL(psv.UNIT_MATERIAL_COST,0)
            ELSE 0
        END) AS SHORTAGE_VALUE
    FROM PART_SITE_VIEW psv
    LEFT JOIN open_po_qty po ON po.SITE_ID=psv.SITE_ID AND po.PART_ID=psv.PART_ID
    LEFT JOIN open_wo_req req ON req.SITE_ID=psv.SITE_ID AND req.PART_ID=psv.PART_ID
    WHERE (@Site IS NULL OR psv.SITE_ID = @Site)
      AND ISNULL(req.OPEN_REQ_QTY, 0) > 0
    GROUP BY psv.SITE_ID
),

-- ============================================================
-- Stagnant inventory $
-- ============================================================
last_movement AS (
    SELECT SITE_ID, PART_ID, MAX(TRANSACTION_DATE) AS LAST_MV
    FROM INVENTORY_TRANS
    WHERE PART_ID IS NOT NULL
      AND (@Site IS NULL OR SITE_ID = @Site)
    GROUP BY SITE_ID, PART_ID
),
stagnant AS (
    SELECT
        psv.SITE_ID,
        SUM(ISNULL(psv.QTY_ON_HAND,0) * ISNULL(psv.UNIT_MATERIAL_COST,0))
            AS STAGNANT_VALUE,
        COUNT(*) AS STAGNANT_PART_COUNT
    FROM PART_SITE_VIEW psv
    LEFT JOIN last_movement lm
        ON lm.SITE_ID=psv.SITE_ID AND lm.PART_ID=psv.PART_ID
    WHERE psv.QTY_ON_HAND > 0
      AND psv.UNIT_MATERIAL_COST > 0
      AND (lm.LAST_MV IS NULL
           OR lm.LAST_MV < DATEADD(month, -@StagnantMonths, GETDATE()))
      AND (@Site IS NULL OR psv.SITE_ID = @Site)
    GROUP BY psv.SITE_ID
),

-- ============================================================
-- Per-site rollup
-- ============================================================
per_site AS (
    SELECT
        s.SITE_ID,

        -- Sales
        ISNULL(b.OPEN_LINES, 0)                                 AS OPEN_SO_LINES,
        ISNULL(b.PAST_DUE_LINES, 0)                             AS PAST_DUE_SO_LINES,
        CAST(ISNULL(b.BACKLOG_VALUE, 0)         AS decimal(23,2)) AS BACKLOG_VALUE,
        CAST(ISNULL(b.PAST_DUE_BACKLOG_VALUE,0) AS decimal(23,2)) AS PAST_DUE_BACKLOG_VALUE,

        -- WIP / Inventory
        ISNULL(w.OPEN_WO_COUNT, 0)                              AS OPEN_WO_COUNT,
        CAST(ISNULL(w.WIP_VALUE, 0)             AS decimal(23,2)) AS WIP_VALUE,
        CAST(ISNULL(i.INVENTORY_VALUE, 0)       AS decimal(23,2)) AS INVENTORY_VALUE,
        ISNULL(i.PARTS_WITH_STOCK, 0)                            AS PARTS_WITH_STOCK,
        CAST(ISNULL(it12.ISSUE_VALUE_T12, 0)    AS decimal(23,2)) AS ISSUE_VALUE_T12,
        CAST(
            CASE WHEN ISNULL(i.INVENTORY_VALUE,0) = 0 THEN NULL
                 ELSE ISNULL(it12.ISSUE_VALUE_T12,0) / i.INVENTORY_VALUE
            END AS decimal(10,2)) AS INVENTORY_TURNS_T12,
        -- Same denominator/numerator as turns, just expressed as duration
        -- of cover so the team can present in turns / weeks / months.
        CAST(
            CASE WHEN ISNULL(it12.ISSUE_VALUE_T12,0) = 0 THEN NULL
                 ELSE 52.0 * i.INVENTORY_VALUE / it12.ISSUE_VALUE_T12
            END AS decimal(10,2)) AS INVENTORY_WEEKS_ON_HAND_T12,
        CAST(
            CASE WHEN ISNULL(it12.ISSUE_VALUE_T12,0) = 0 THEN NULL
                 ELSE 12.0 * i.INVENTORY_VALUE / it12.ISSUE_VALUE_T12
            END AS decimal(10,2)) AS INVENTORY_MONTHS_ON_HAND_T12,

        -- Purchasing
        ISNULL(pu.OPEN_PO_LINES, 0)                              AS OPEN_PO_LINES,
        ISNULL(pu.PAST_DUE_PO_LINES, 0)                          AS PAST_DUE_PO_LINES,
        CAST(ISNULL(pu.OPEN_PO_VALUE, 0)        AS decimal(23,2)) AS OPEN_PO_VALUE,
        CAST(ISNULL(pu.PAST_DUE_PO_VALUE, 0)    AS decimal(23,2)) AS PAST_DUE_PO_VALUE,

        -- Vendor OTD
        ISNULL(vo.RECV_COUNT, 0)                                 AS VENDOR_RECEIPTS_T90,
        CAST(
            CASE WHEN ISNULL(vo.RECV_WITH_PROMISE,0) = 0 THEN NULL
                 ELSE 100.0 * vo.RECV_ON_TIME / vo.RECV_WITH_PROMISE
            END AS decimal(6,2))                                 AS VENDOR_OTD_PCT_T90,

        -- Customer OTD
        ISNULL(co.SHIPMENT_COUNT, 0)                             AS CUSTOMER_SHIPMENTS_T90,
        CAST(
            CASE WHEN ISNULL(co.SHIPMENT_COUNT,0) = 0 THEN NULL
                 ELSE 100.0 * co.ON_TIME_SHIPMENTS / co.SHIPMENT_COUNT
            END AS decimal(6,2))                                 AS CUSTOMER_OTD_PCT_T90,

        -- Net shortages
        ISNULL(sh.PARTS_SHORT, 0)                                AS PARTS_SHORT_COUNT,
        CAST(ISNULL(sh.SHORTAGE_VALUE, 0)       AS decimal(23,2)) AS SHORTAGE_VALUE_AT_STD,

        -- Stagnant inventory
        ISNULL(st.STAGNANT_PART_COUNT, 0)                        AS STAGNANT_PART_COUNT,
        CAST(ISNULL(st.STAGNANT_VALUE, 0)       AS decimal(23,2)) AS STAGNANT_VALUE
    FROM sites s
    LEFT JOIN backlog              b   ON b.SITE_ID  = s.SITE_ID
    LEFT JOIN wip                  w   ON w.SITE_ID  = s.SITE_ID
    LEFT JOIN inventory            i   ON i.SITE_ID  = s.SITE_ID
    LEFT JOIN issue_t12            it12 ON it12.SITE_ID = s.SITE_ID
    LEFT JOIN purchasing           pu  ON pu.SITE_ID = s.SITE_ID
    LEFT JOIN vendor_otd           vo  ON vo.SITE_ID = s.SITE_ID
    LEFT JOIN customer_otd_rolled  co  ON co.SITE_ID = s.SITE_ID
    LEFT JOIN shortages            sh  ON sh.SITE_ID = s.SITE_ID
    LEFT JOIN stagnant             st  ON st.SITE_ID = s.SITE_ID
)

SELECT *
FROM (
    SELECT
        @AsOfDate                            AS AS_OF_DATE,
        SITE_ID,
        -- Sales
        BACKLOG_VALUE,
        PAST_DUE_BACKLOG_VALUE,
        OPEN_SO_LINES,
        PAST_DUE_SO_LINES,
        -- Production
        WIP_VALUE,
        OPEN_WO_COUNT,
        -- Inventory
        INVENTORY_VALUE,
        PARTS_WITH_STOCK,
        ISSUE_VALUE_T12,
        INVENTORY_TURNS_T12,
        INVENTORY_WEEKS_ON_HAND_T12,
        INVENTORY_MONTHS_ON_HAND_T12,
        STAGNANT_VALUE,
        STAGNANT_PART_COUNT,
        -- Purchasing
        OPEN_PO_VALUE,
        PAST_DUE_PO_VALUE,
        OPEN_PO_LINES,
        PAST_DUE_PO_LINES,
        -- OTD
        VENDOR_OTD_PCT_T90,
        VENDOR_RECEIPTS_T90,
        CUSTOMER_OTD_PCT_T90,
        CUSTOMER_SHIPMENTS_T90,
        -- Risk
        PARTS_SHORT_COUNT,
        SHORTAGE_VALUE_AT_STD
    FROM per_site

    UNION ALL

    -- ALL-SITES rollup row (only when not filtered)
    SELECT
        @AsOfDate, '_ALL_SITES_',
        SUM(BACKLOG_VALUE), SUM(PAST_DUE_BACKLOG_VALUE), SUM(OPEN_SO_LINES), SUM(PAST_DUE_SO_LINES),
        SUM(WIP_VALUE), SUM(OPEN_WO_COUNT),
        SUM(INVENTORY_VALUE), SUM(PARTS_WITH_STOCK),
        SUM(ISSUE_VALUE_T12),
        CAST(CASE WHEN SUM(INVENTORY_VALUE) = 0 THEN NULL
                  ELSE SUM(ISSUE_VALUE_T12) / SUM(INVENTORY_VALUE) END AS decimal(10,2)),
        CAST(CASE WHEN SUM(ISSUE_VALUE_T12) = 0 THEN NULL
                  ELSE 52.0 * SUM(INVENTORY_VALUE) / SUM(ISSUE_VALUE_T12) END AS decimal(10,2)),
        CAST(CASE WHEN SUM(ISSUE_VALUE_T12) = 0 THEN NULL
                  ELSE 12.0 * SUM(INVENTORY_VALUE) / SUM(ISSUE_VALUE_T12) END AS decimal(10,2)),
        SUM(STAGNANT_VALUE), SUM(STAGNANT_PART_COUNT),
        SUM(OPEN_PO_VALUE), SUM(PAST_DUE_PO_VALUE), SUM(OPEN_PO_LINES), SUM(PAST_DUE_PO_LINES),
        CAST(CASE WHEN SUM(VENDOR_RECEIPTS_T90) = 0 THEN NULL
                  ELSE 100.0 * SUM(VENDOR_OTD_PCT_T90 * VENDOR_RECEIPTS_T90 / 100.0)
                       / SUM(VENDOR_RECEIPTS_T90)
             END AS decimal(6,2)),
        SUM(VENDOR_RECEIPTS_T90),
        CAST(CASE WHEN SUM(CUSTOMER_SHIPMENTS_T90) = 0 THEN NULL
                  ELSE 100.0 * SUM(CUSTOMER_OTD_PCT_T90 * CUSTOMER_SHIPMENTS_T90 / 100.0)
                       / SUM(CUSTOMER_SHIPMENTS_T90)
             END AS decimal(6,2)),
        SUM(CUSTOMER_SHIPMENTS_T90),
        SUM(PARTS_SHORT_COUNT), SUM(SHORTAGE_VALUE_AT_STD)
    FROM per_site
    WHERE @Site IS NULL    -- only emit rollup when running multi-site
    HAVING COUNT(*) > 1
) AS combined
ORDER BY
    CASE WHEN SITE_ID = '_ALL_SITES_' THEN 1 ELSE 0 END,
    SITE_ID;
