/*
===============================================================================
Query Name: so_header_and_lines_open_orders.sql
Purpose:
    Returns open customer order lines for shippable part items, combining
    customer order header data with line-level detail.

Business Use:
    This query is intended to support open order aging and shipping review.
    It identifies order lines that still have quantity left to ship and
    calculates the number of days relative to the desired ship date.

Logic Summary:
    1. Join customer order header records to customer order line records.
    2. Keep only open/relevant orders and active line items.
    3. Exclude non-part/service-style rows by requiring PART_ID.
    4. Calculate remaining quantity to ship using ordered quantity less
       total shipped quantity.
    5. Use line-level dates when present; otherwise fall back to header dates.
    6. Age the line based on desired ship date, since desired ship date is
       the primary planning/MRP date.

Assumptions:
    - Header status 'R' and 'F' represent open/relevant order states.
    - Line status 'A' represents an active/open line.
    - Header desired_ship_date is required, so COALESCE on desired ship date
      will always return a value.
    - TOTAL_SHIPPED_QTY is the best available shipped quantity field for
      determining what remains to ship.
    - PART_ID IS NOT NULL is used to limit the result to real shippable items.

Key Output Fields:
    OPEN_QTY_RAW
        Simple arithmetic difference between ordered quantity and shipped
        quantity. May go negative if shipped quantity exceeds order quantity.

    TO_SHIP_QTY
        Remaining quantity to ship, floored at zero so negative quantities
        do not appear in operational reporting.

    AGING_DAYS
        Number of days between desired ship date and today.
            > 0  = past due
            = 0  = due today
            < 0  = due in the future

Notes:
    - Desired ship date drives MRP, so aging is based on desired_ship_date
      instead of promise_date.
    - Line dates override header dates when line-level values are populated.
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
    l.order_qty - l.total_shipped_qty AS open_qty_raw,

    CASE
        WHEN l.order_qty - ISNULL(l.total_shipped_qty, 0) < 0 THEN 0
        ELSE l.order_qty - ISNULL(l.total_shipped_qty, 0)
    END AS to_ship_qty,

    ------------------------------------------------------------
    -- Aging calculation
    -- Uses desired ship date because that is the planning/MRP date.
    -- Line desired ship date overrides header desired ship date.
    ------------------------------------------------------------
    DATEDIFF(
        DAY,
        COALESCE(l.desired_ship_date, h.desired_ship_date),
        CAST(GETDATE() AS DATE)
    ) AS aging_days,

    ------------------------------------------------------------
    -- Effective dates
    -- Line-level dates override header dates when available.
    ------------------------------------------------------------
    COALESCE(l.desired_ship_date, h.desired_ship_date) AS desired_ship_date,
    COALESCE(l.promise_date, h.promise_date) AS promise_date,
    COALESCE(l.promise_del_date, h.promise_del_date) AS promise_del_date

FROM customer_order h
JOIN cust_order_line l
    ON h.id = l.cust_order_id

WHERE
    ------------------------------------------------------------
    -- Keep only open/relevant customer orders
    ------------------------------------------------------------
    h.status IN ('R', 'F')

    ------------------------------------------------------------
    -- Keep only active/open line items
    ------------------------------------------------------------
    AND l.line_status = 'A'

    ------------------------------------------------------------
    -- Keep only lines with remaining quantity to ship
    ------------------------------------------------------------
    AND l.order_qty - ISNULL(l.total_shipped_qty, 0) > 0

    ------------------------------------------------------------
    -- Exclude non-part/service/comment-style rows
    ------------------------------------------------------------
    AND l.part_id IS NOT NULL;