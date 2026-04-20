/*
===============================================================================
Query Name: so_header_and_lines.sql

Purpose:
    Provides a full, unfiltered view of customer orders joined to their
    corresponding line items.

    This serves as a base dataset (or semantic layer) for downstream queries
    such as:
        - Open order aging
        - Shipment planning
        - Revenue analysis
        - Customer order reporting

Business Use:
    This query combines header-level order data with line-level detail,
    allowing analysis at the most granular level (one row per order line).

    It intentionally does NOT apply filters so it can be reused across
    multiple reporting and analytical use cases.

Grain:
    One row per customer order line (header fields repeated per line).

Join Logic:
    customer_order.id = cust_order_line.cust_order_id

    LEFT JOIN is used to preserve all order headers, even if they do not
    currently have associated line records.

Key Concepts:
    - Header fields describe the overall order.
    - Line fields describe specific items within the order.
    - Line-level values override header values when appropriate (e.g. dates).

Assumptions:
    - TOTAL_SHIPPED_QTY represents the total quantity shipped for the line.
    - ORDER_QTY represents the ordered quantity for the line.
    - PART_ID being NULL may indicate non-shippable rows (notes/services/etc).

Key Calculated Fields:

    OPEN_QTY
        ORDER_QTY - TOTAL_SHIPPED_QTY
        Raw difference between ordered and shipped quantities.
        May be negative if over-shipped.

    TO_SHIP_QTY
        Remaining quantity to ship, floored at zero.
        Prevents negative values from appearing in operational reporting.

    DESIRED_SHIP_DATE / PROMISE_DATE / PROMISE_DEL_DATE
        Line-level values override header-level values using COALESCE.

Notes:
    - This query is intentionally unfiltered.
    - Downstream queries should apply business logic filters such as:
        * Open status filtering
        * Active line filtering
        * Part-only filtering
        * Positive open quantity filtering

===============================================================================
*/

SELECT
    ------------------------------------------------------------
    -- Order header fields
    ------------------------------------------------------------
    h.id AS order_id,
    h.customer_id,
    h.customer_po_ref,
    h.status AS order_status,
    h.order_date,
    h.create_date,
    h.revision_id,

    ------------------------------------------------------------
    -- Order line fields
    ------------------------------------------------------------
    l.line_no,
    l.part_id,
    l.line_status,
    l.unit_price,
    l.misc_reference,
    l.product_code,
    l.commodity_code,
    l.last_shipped_date,
    l.service_charge_id,
    l.warehouse_id,
    l.fulfilled_qty,
    l.order_qty,
    l.total_shipped_qty,

    ------------------------------------------------------------
    -- Quantity calculations
    ------------------------------------------------------------
    l.order_qty - l.total_shipped_qty AS open_qty,

    CASE
        WHEN l.order_qty - l.total_shipped_qty < 0 THEN 0
        ELSE l.order_qty - l.total_shipped_qty
    END AS to_ship_qty,

    ------------------------------------------------------------
    -- Effective dates (line overrides header)
    ------------------------------------------------------------
    COALESCE(l.desired_ship_date, h.desired_ship_date) AS desired_ship_date,
    COALESCE(l.promise_date, h.promise_date) AS promise_date,
    COALESCE(l.promise_del_date, h.promise_del_date) AS promise_del_date

FROM customer_order h
LEFT JOIN cust_order_line l
    ON h.id = l.cust_order_id;