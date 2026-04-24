/*
===============================================================================
Query Name: past_due_so_aging.sql

Purpose:
    Line-level aging report of open sales-order lines, bucketed by how far
    past the target ship date they are.

    Intended as the daily / weekly "what are we shipping late" report for
    the commercial and ops teams.

Grain:
    One row per open sales-order line (or delivery schedule if present).
    Open = line/header status not cancelled AND ORDER_QTY > TOTAL_SHIPPED_QTY.

Target date precedence:
    1. CUST_LINE_DEL.DESIRED_SHIP_DATE (most specific)
    2. CUST_ORDER_LINE.PROMISE_DATE
    3. CUST_ORDER_LINE.DESIRED_SHIP_DATE
    4. CUSTOMER_ORDER.PROMISE_DATE
    5. CUSTOMER_ORDER.DESIRED_SHIP_DATE

Aging buckets (days past @AsOfDate):
    NOT_DUE            (target >= today)
    0-7                (1-7 days past)
    8-14
    15-30
    31-60
    61+

Business Use:
    - Daily at-risk review
    - Customer-facing visibility ("here's what we owe you")
    - Prioritize production scheduling against the hottest late lines
    - Escalation queue for customer service

Notes / Assumptions:
    - Open value uses CUST_ORDER_LINE UNIT_PRICE and TRADE_DISC_PERCENT
      (i.e. what will be invoiced at list-less-discount).
    - Joins to PART_SITE_VIEW to show on-hand so you can see whether the
      delay is a material issue (no stock) vs production / pick delay.
    - Adds a supply_status flag that mirrors typical expediter thinking:
      "do we have the material?" "is there an open PO?" etc.

Potential Enhancements:
    - Join to WORK_ORDER to show which WO covers the line and its status
    - Add commodity_code / product_code summary rollup
    - Add ship-via / carrier so logistics knows what is queued up
    - Weight priority by customer tier (if you have one)
===============================================================================
*/

DECLARE @Site     nvarchar(15) = NULL;
DECLARE @AsOfDate datetime     = GETDATE();

;WITH open_so AS (
    SELECT
        co.SITE_ID,
        co.ID                                       AS co_id,
        co.CUSTOMER_ID,
        co.SALESREP_ID,
        co.TERRITORY,
        co.ORDER_DATE,
        co.CUSTOMER_PO_REF,
        col.LINE_NO,
        col.PART_ID,
        col.SELLING_UM,
        col.UNIT_PRICE,
        COALESCE(col.TRADE_DISC_PERCENT, 0)         AS trade_disc_pct,

        COALESCE(cld.DEL_SCHED_LINE_NO, 0)          AS del_sched_line_no,

        COALESCE(cld.ORDER_QTY,    col.ORDER_QTY)   AS sched_order_qty,
        COALESCE(cld.SHIPPED_QTY,  0)               AS sched_shipped_qty,

        COALESCE(
            cld.DESIRED_SHIP_DATE,
            col.PROMISE_DATE,
            col.DESIRED_SHIP_DATE,
            co.PROMISE_DATE,
            co.DESIRED_SHIP_DATE
        )                                            AS target_ship_date
    FROM CUSTOMER_ORDER co
    INNER JOIN CUST_ORDER_LINE col
        ON col.CUST_ORDER_ID = co.ID
    LEFT JOIN CUST_LINE_DEL cld
        ON cld.CUST_ORDER_ID      = col.CUST_ORDER_ID
       AND cld.CUST_ORDER_LINE_NO = col.LINE_NO
    -- Open SO = canonical filter per so_header_and_lines_open_orders.sql:
    --   header STATUS IN ('R','F') and line LINE_STATUS = 'A'.
    -- Status 'C' on header or line means the order/line was closed
    -- (possibly short) and must NOT be treated as backlog.
    WHERE co.STATUS IN ('R', 'F')
      AND col.LINE_STATUS = 'A'
      AND col.PART_ID IS NOT NULL
      AND (@Site IS NULL OR co.SITE_ID = @Site)
),

open_qty AS (
    SELECT
        o.*,
        (o.sched_order_qty - o.sched_shipped_qty) AS open_qty
    FROM open_so o
    WHERE (o.sched_order_qty - o.sched_shipped_qty) > 0
),

aged AS (
    SELECT
        o.*,
        DATEDIFF(day, o.target_ship_date, @AsOfDate) AS days_past_due,
        CASE
            WHEN o.target_ship_date >= @AsOfDate                                 THEN 'NOT_DUE'
            WHEN DATEDIFF(day, o.target_ship_date, @AsOfDate) BETWEEN 1  AND  7  THEN '0-7'
            WHEN DATEDIFF(day, o.target_ship_date, @AsOfDate) BETWEEN 8  AND 14  THEN '8-14'
            WHEN DATEDIFF(day, o.target_ship_date, @AsOfDate) BETWEEN 15 AND 30  THEN '15-30'
            WHEN DATEDIFF(day, o.target_ship_date, @AsOfDate) BETWEEN 31 AND 60  THEN '31-60'
            ELSE                                                                        '61+'
        END AS aging_bucket
    FROM open_qty o
),

-- Count any open PO covering the part (any qty, any date)
open_po_cover AS (
    SELECT
        p.SITE_ID,
        pl.PART_ID,
        SUM(pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY) AS open_po_qty,
        MIN(COALESCE(pl.DESIRED_RECV_DATE, p.PROMISE_DATE, p.DESIRED_RECV_DATE))
                                                   AS earliest_po_recv_date
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl
        ON pl.PURC_ORDER_ID = p.ID
    WHERE ISNULL(p.STATUS, '')       NOT IN ('X','C')
      AND ISNULL(pl.LINE_STATUS, '') NOT IN ('X','C')
      AND pl.ORDER_QTY > pl.TOTAL_RECEIVED_QTY
    GROUP BY p.SITE_ID, pl.PART_ID
)

SELECT
    a.SITE_ID,
    a.co_id,
    a.LINE_NO,
    a.del_sched_line_no,

    a.CUSTOMER_ID,
    c.NAME                               AS customer_name,
    a.SALESREP_ID,
    a.TERRITORY,
    a.CUSTOMER_PO_REF,

    a.PART_ID,
    psv.DESCRIPTION                      AS part_description,
    psv.PRODUCT_CODE,
    psv.COMMODITY_CODE,
    COALESCE(psv.QTY_ON_HAND, 0)         AS qty_on_hand,

    a.ORDER_DATE,
    a.target_ship_date,
    a.days_past_due,
    a.aging_bucket,

    a.SELLING_UM,
    a.sched_order_qty,
    a.sched_shipped_qty,
    a.open_qty,

    a.UNIT_PRICE,
    a.trade_disc_pct,
    CAST(a.open_qty * a.UNIT_PRICE
         * (100.0 - a.trade_disc_pct) / 100.0
        AS decimal(23,2))                AS open_value,

    COALESCE(oc.open_po_qty, 0)          AS open_po_cover_qty,
    oc.earliest_po_recv_date,

    CASE
        WHEN COALESCE(psv.QTY_ON_HAND, 0) >= a.open_qty
                                            THEN 'STOCK AVAILABLE - ship issue'
        WHEN oc.open_po_qty IS NOT NULL
         AND oc.earliest_po_recv_date <= a.target_ship_date
                                            THEN 'PO COVERS BEFORE NEED'
        WHEN oc.open_po_qty IS NOT NULL
                                            THEN 'PO LATE FOR NEED'
        WHEN psv.PURCHASED = 'Y'
                                            THEN 'NO PO - BUY NEEDED'
        WHEN psv.FABRICATED = 'Y'
                                            THEN 'MAKE PART - check WO coverage'
        ELSE                                     'REVIEW'
    END                                    AS supply_status,

    CASE
        WHEN a.days_past_due > 14               THEN 'P1 - escalate'
        WHEN a.days_past_due > 0                THEN 'P2 - past due'
        WHEN a.target_ship_date <= DATEADD(day, 7, @AsOfDate)
                                                THEN 'P3 - due this week'
        ELSE                                         'P4 - normal'
    END                                    AS priority
FROM aged a
LEFT JOIN CUSTOMER c
    ON c.ID = a.CUSTOMER_ID
LEFT JOIN PART_SITE_VIEW psv
    ON psv.SITE_ID = a.SITE_ID
   AND psv.PART_ID = a.PART_ID
LEFT JOIN open_po_cover oc
    ON oc.SITE_ID = a.SITE_ID
   AND oc.PART_ID = a.PART_ID
ORDER BY
    CASE a.aging_bucket
        WHEN '61+'     THEN 1
        WHEN '31-60'   THEN 2
        WHEN '15-30'   THEN 3
        WHEN '8-14'    THEN 4
        WHEN '0-7'     THEN 5
        ELSE                6
    END,
    (a.open_qty * a.UNIT_PRICE) DESC;
