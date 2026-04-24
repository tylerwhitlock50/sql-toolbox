/*
===============================================================================
Query Name: past_due_po_aging.sql

Purpose:
    Line-level expediting list of open purchase-order lines, bucketed by how
    far past their target receive date they are.

    Designed to be the daily/weekly "what do I need to chase" report for
    buyers and the supply chain manager.

Grain:
    One row per open PO line (delivery schedule if present).
    Open = line/header status not ('X','C') AND ORDER_QTY > RECEIVED_QTY.

Target date precedence:
    1. Delivery schedule DESIRED_RECV_DATE (most specific)
    2. PO line DESIRED_RECV_DATE
    3. PO header PROMISE_DATE
    4. PO header DESIRED_RECV_DATE

Aging buckets (days past @AsOfDate):
    NOT_DUE            (target >= today)
    0-7                (1-7 days past)
    8-14
    15-30
    31-60
    61+

Business Use:
    - Daily expediting list
    - "Value at risk" by aging bucket - where to focus calls
    - Feed supply-chain standup meeting

Notes:
    - Uses PO unit_price for value (in purchase UOM). For stock-UOM-normalized
      pricing / standard-cost comparison, use open_and_planned_supply_detail.sql.
    - Includes an is_sales_linked flag to help prioritize:
      lines whose parts are on open sales orders should be expedited first.

Potential Enhancements:
    - Join to VENDOR to pull phone / contact for one-click outreach
    - Add commodity_code / product_code filters
    - Add "last receipt against this PO" date to show whether the vendor
      has been responsive at all
===============================================================================
*/

DECLARE @Site     nvarchar(15) = NULL;
DECLARE @AsOfDate datetime     = GETDATE();

;WITH open_po AS (
    SELECT
        p.SITE_ID,
        p.ID                       AS po_id,
        p.VENDOR_ID,
        COALESCE(NULLIF(LTRIM(RTRIM(p.BUYER)), ''), '(unassigned)') AS buyer,
        p.ORDER_DATE,
        pl.LINE_NO,
        pl.PART_ID,
        pl.PURCHASE_UM,
        pl.UNIT_PRICE               AS po_unit_price,
        COALESCE(pd.DEL_SCHED_LINE_NO, 0)             AS del_sched_line_no,

        COALESCE(pd.ORDER_QTY,    pl.ORDER_QTY, 0)    AS sched_order_qty,
        COALESCE(pd.RECEIVED_QTY, 0)                  AS sched_received_qty,

        COALESCE(
            pd.DESIRED_RECV_DATE,
            pl.DESIRED_RECV_DATE,
            p.PROMISE_DATE,
            p.DESIRED_RECV_DATE
        )                           AS target_recv_date
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl
        ON pl.PURC_ORDER_ID = p.ID
    LEFT JOIN PURC_LINE_DEL pd
        ON pd.PURC_ORDER_ID      = pl.PURC_ORDER_ID
       AND pd.PURC_ORDER_LINE_NO = pl.LINE_NO
    WHERE ISNULL(p.STATUS, '')        NOT IN ('X','C')
      AND ISNULL(pl.LINE_STATUS, '')  NOT IN ('X','C')
      AND pl.PART_ID IS NOT NULL
      AND (@Site IS NULL OR p.SITE_ID = @Site)
),

open_qty AS (
    SELECT
        o.*,
        (o.sched_order_qty - o.sched_received_qty) AS open_qty_purchase_um
    FROM open_po o
    WHERE (o.sched_order_qty - o.sched_received_qty) > 0
),

-- Parts that are currently on any open sales order line (for prioritization flag)
sales_linked_parts AS (
    SELECT DISTINCT
        col.SITE_ID,
        col.PART_ID
    FROM CUST_ORDER_LINE col
    INNER JOIN CUSTOMER_ORDER co
        ON co.ID = col.CUST_ORDER_ID
    -- Canonical open-order filter (see so_header_and_lines_open_orders.sql):
    -- header STATUS IN ('R','F') and line LINE_STATUS = 'A'.
    WHERE co.STATUS IN ('R', 'F')
      AND col.LINE_STATUS = 'A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
),

aged AS (
    SELECT
        o.*,
        DATEDIFF(day, o.target_recv_date, @AsOfDate) AS days_past_due,
        CASE
            WHEN o.target_recv_date >= @AsOfDate                                       THEN 'NOT_DUE'
            WHEN DATEDIFF(day, o.target_recv_date, @AsOfDate) BETWEEN 1  AND  7        THEN '0-7'
            WHEN DATEDIFF(day, o.target_recv_date, @AsOfDate) BETWEEN 8  AND 14        THEN '8-14'
            WHEN DATEDIFF(day, o.target_recv_date, @AsOfDate) BETWEEN 15 AND 30        THEN '15-30'
            WHEN DATEDIFF(day, o.target_recv_date, @AsOfDate) BETWEEN 31 AND 60        THEN '31-60'
            ELSE '61+'
        END AS aging_bucket
    FROM open_qty o
)

SELECT
    a.SITE_ID,
    a.po_id,
    a.LINE_NO,
    a.del_sched_line_no,
    a.buyer,
    a.VENDOR_ID,
    v.NAME                                            AS vendor_name,
    a.PART_ID,
    psv.DESCRIPTION                                   AS part_description,
    psv.PRODUCT_CODE,
    psv.COMMODITY_CODE,

    a.ORDER_DATE,
    a.target_recv_date,
    a.days_past_due,
    a.aging_bucket,

    a.PURCHASE_UM,
    a.sched_order_qty,
    a.sched_received_qty,
    a.open_qty_purchase_um,

    a.po_unit_price,
    (a.open_qty_purchase_um * a.po_unit_price)        AS open_value,

    CASE WHEN slp.PART_ID IS NOT NULL THEN 1 ELSE 0 END AS is_on_open_sales_order,

    -- Suggested priority: on a sales order AND past due = P1, past due = P2,
    -- not due but on sales order = P3, everything else = P4
    CASE
        WHEN a.days_past_due > 0 AND slp.PART_ID IS NOT NULL THEN 'P1 - expedite, SO demand'
        WHEN a.days_past_due > 0                              THEN 'P2 - past due'
        WHEN slp.PART_ID IS NOT NULL                          THEN 'P3 - due soon, SO demand'
        ELSE                                                       'P4 - normal'
    END                                               AS priority
FROM aged a
LEFT JOIN VENDOR v
    ON v.ID = a.VENDOR_ID
LEFT JOIN PART_SITE_VIEW psv
    ON psv.SITE_ID = a.SITE_ID
   AND psv.PART_ID = a.PART_ID
LEFT JOIN sales_linked_parts slp
    ON slp.SITE_ID = a.SITE_ID
   AND slp.PART_ID = a.PART_ID
ORDER BY
    CASE a.aging_bucket
        WHEN '61+'     THEN 1
        WHEN '31-60'   THEN 2
        WHEN '15-30'   THEN 3
        WHEN '8-14'    THEN 4
        WHEN '0-7'     THEN 5
        ELSE                6
    END,
    (a.open_qty_purchase_um * a.po_unit_price) DESC;
