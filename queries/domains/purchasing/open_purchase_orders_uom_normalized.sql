/*
===============================================================================
Query Name: open_purchase_orders_uom_normalized.sql

Purpose:
    Produces a detailed open purchase order report with quantities and pricing
    normalized into the part's STOCK unit of measure.

    This query enables consistent comparison between:
        - Purchase order pricing (in purchase UOM)
        - Inventory/standard cost (in stock UOM)
        - Converted PO pricing (in stock UOM)

    It also supports service-based PO lines and distinguishes them from
    inventory-bearing part lines.

Business Use:
    - Open PO reporting by due date
    - Supply planning / MRP validation
    - Cost validation between purchasing and inventory standards
    - Identifying UOM inconsistencies or missing conversions
    - Identifying pricing discrepancies between PO and standard cost

Grain:
    One row per purchase order line per delivery schedule (if present).

    If delivery schedules exist, each schedule is treated as a separate
    expected receipt with its own due date and quantity.

Key Features:
    - Converts open quantities into STOCK_UOM using:
        1. Part-specific conversion (PART_UNITS_CONV)
        2. Default conversion (UNITS_CONVERSION)
    - Calculates price per STOCK_UOM for apples-to-apples comparison
    - Supports both PART and SERVICE lines
    - Computes expected financial amounts in both UOM contexts

-------------------------------------------------------------------------------

CTE Breakdown:

1. part_site
    - Source: PART_SITE_VIEW
    - Provides:
        - STOCK_UM (inventory unit of measure)
        - Aggregated unit cost:
            material + service + burden + labor

2. line_sched
    - Combines:
        PURCHASE_ORDER (header)
        PURC_ORDER_LINE (line)
        PURC_LINE_DEL (delivery schedule)
    - Determines:
        - Due date (priority: schedule → line → header)
        - Scheduled order quantity and received quantity

3. open_lines
    - Filters to only open quantities:
        open_qty = ordered - received
    - Removes fully received lines

4. uom_match
    - Resolves conversion factor between:
        PURCHASE_UM → STOCK_UM
    - Priority:
        1. Exact match → 1.0
        2. Part-specific conversion
        3. Default conversion
    - Leaves NULL if no valid conversion exists

5. calc
    - Derives:
        - line_item_type (PART vs SERVICE)
        - report_item_id (SERVICE_ID | PART_ID formatting)
        - open_qty_stock_um
        - calc_unit_price_stock_um

-------------------------------------------------------------------------------

Key Calculations:

Open Quantity (Purchase UOM):
    open_qty_purchase_um = sched_order_qty - sched_received_qty

Open Quantity (Stock UOM):
    open_qty_stock_um =
        open_qty_purchase_um * conversion_factor

PO Unit Price (Stock UOM):
    calc_unit_price_stock_um =
        po_unit_price / conversion_factor

Expected Amount (PO UOM):
    expected_amount_po_um =
        open_qty_purchase_um * po_unit_price

Expected Amount (Stock UOM):
    expected_amount_stock_um =
        open_qty_stock_um * calc_unit_price_stock_um

Price Difference:
    stock_um_price_diff =
        calc_unit_price_stock_um - part_site_unit_price

-------------------------------------------------------------------------------

Line Type Logic:

    SERVICE:
        SERVICE_ID is populated

    PART:
        SERVICE_ID is NULL

    report_item_id:
        - SERVICE + PART → "SERVICE_ID | PART_ID"
        - SERVICE only   → "SERVICE_ID"
        - PART only      → "PART_ID"

-------------------------------------------------------------------------------

Important Notes / Assumptions:

- Conversion Factor Definition:
    FROM_UM → TO_UM multiplier
    (i.e., multiply quantity, divide price)

- Service Lines:
    - Do NOT participate in inventory UOM conversion
    - STOCK_UM and converted values will be NULL

- Missing Conversions:
    - If PURCHASE_UM ≠ STOCK_UM and no conversion exists,
      stock quantities and prices will be NULL

- Status Filtering:
    - Excludes PO and line statuses of 'X' and 'C'
    - Adjust if your environment uses different status codes

- Delivery Schedules:
    - Preferred over line-level quantities when present
    - Allows proper date-based supply visibility

-------------------------------------------------------------------------------

Potential Enhancements:

- Add variance % for pricing:
    (calc_unit_price_stock_um / part_site_unit_price - 1)

- Aggregate by:
    - PART_ID + due date (MRP-style view)
    - Vendor + month (cash planning)

- Flag missing conversions explicitly

- Filter to purchased parts only if needed:
    join PART_SITE_VIEW.PURCHASED = 'Y'

===============================================================================
*/

WITH part_site AS (
    SELECT
        ps.SITE_ID,
        ps.PART_ID,
        ps.STOCK_UM,
        ps.UNIT_MATERIAL_COST
        + ps.UNIT_SERVICE_COST
        + ps.UNIT_BURDEN_COST
        + ps.UNIT_LABOR_COST AS part_site_unit_price
    FROM PART_SITE_VIEW ps
),

line_sched AS (
    SELECT
        p.ID AS purc_order_id,
        p.VENDOR_ID,
        p.ORDER_DATE,
        p.SITE_ID,
        p.STATUS AS po_status,
        pl.LINE_NO,
        pl.PART_ID,
        pl.SERVICE_ID,
        pl.PURCHASE_UM,
        pl.LINE_STATUS,
        COALESCE(pd.DESIRED_RECV_DATE, pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE) AS desired_recv_date,

        -- use delivery schedule qty if present, otherwise line qty
        COALESCE(pd.ORDER_QTY, pl.ORDER_QTY, 0) AS sched_order_qty,
        COALESCE(pd.RECEIVED_QTY, 0) AS sched_received_qty,

        pl.UNIT_PRICE AS po_unit_price
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl
        ON pl.PURC_ORDER_ID = p.ID
    LEFT JOIN PURC_LINE_DEL pd
        ON pd.PURC_ORDER_ID = pl.PURC_ORDER_ID
       AND pd.PURC_ORDER_LINE_NO = pl.LINE_NO
    WHERE 1 = 1
      AND ISNULL(p.STATUS, '') NOT IN ('X', 'C')
      AND ISNULL(pl.LINE_STATUS, '') NOT IN ('X', 'C')
      AND (
            pl.PART_ID IS NOT NULL
            OR NULLIF(LTRIM(RTRIM(pl.SERVICE_ID)), '') IS NOT NULL
          )
),

open_lines AS (
    SELECT
        ls.purc_order_id,
        ls.VENDOR_ID,
        ls.ORDER_DATE,
        ls.SITE_ID,
        ls.po_status,
        ls.LINE_NO,
        ls.PART_ID,
        ls.SERVICE_ID,
        ls.PURCHASE_UM,
        ls.LINE_STATUS,
        ls.desired_recv_date,
        ls.po_unit_price,
        (ls.sched_order_qty - ls.sched_received_qty) AS open_qty_purchase_um
    FROM line_sched ls
    WHERE (ls.sched_order_qty - ls.sched_received_qty) > 0
),

uom_match AS (
    SELECT
        ol.*,
        ps.STOCK_UM,
        ps.part_site_unit_price,

        puc.CONVERSION_FACTOR AS part_conv_factor,
        duc.CONVERSION_FACTOR AS default_conv_factor,

        CASE
            WHEN ol.PART_ID IS NULL THEN NULL
            WHEN ol.PURCHASE_UM = ps.STOCK_UM THEN 1.0
            WHEN puc.CONVERSION_FACTOR IS NOT NULL THEN puc.CONVERSION_FACTOR
            WHEN duc.CONVERSION_FACTOR IS NOT NULL THEN duc.CONVERSION_FACTOR
            ELSE NULL
        END AS conversion_factor
    FROM open_lines ol
    LEFT JOIN part_site ps
        ON ps.SITE_ID = ol.SITE_ID
       AND ps.PART_ID = ol.PART_ID
    LEFT JOIN PART_UNITS_CONV puc
        ON puc.PART_ID = ol.PART_ID
       AND puc.FROM_UM = ol.PURCHASE_UM
       AND puc.TO_UM = ps.STOCK_UM
    LEFT JOIN UNITS_CONVERSION duc
        ON duc.FROM_UM = ol.PURCHASE_UM
       AND duc.TO_UM = ps.STOCK_UM
),

calc AS (
    SELECT
        um.*,

        CASE
            WHEN NULLIF(LTRIM(RTRIM(um.SERVICE_ID)), '') IS NOT NULL THEN 'SERVICE'
            ELSE 'PART'
        END AS line_item_type,

        CASE
            WHEN NULLIF(LTRIM(RTRIM(um.SERVICE_ID)), '') IS NOT NULL
                 AND NULLIF(LTRIM(RTRIM(um.PART_ID)), '') IS NOT NULL
                THEN um.SERVICE_ID + ' | ' + um.PART_ID
            WHEN NULLIF(LTRIM(RTRIM(um.SERVICE_ID)), '') IS NOT NULL
                THEN um.SERVICE_ID
            ELSE um.PART_ID
        END AS report_item_id,

        CASE
            WHEN um.PART_ID IS NULL THEN NULL
            WHEN um.PURCHASE_UM = um.STOCK_UM THEN um.open_qty_purchase_um
            WHEN um.conversion_factor IS NOT NULL THEN um.open_qty_purchase_um * um.conversion_factor
            ELSE NULL
        END AS open_qty_stock_um,

        CASE
            WHEN um.PART_ID IS NULL THEN NULL
            WHEN um.PURCHASE_UM = um.STOCK_UM THEN um.po_unit_price
            WHEN um.conversion_factor IS NOT NULL AND um.conversion_factor <> 0
                THEN um.po_unit_price / um.conversion_factor
            ELSE NULL
        END AS calc_unit_price_stock_um
    FROM uom_match um
)

SELECT
    c.SITE_ID,
    c.purc_order_id AS po_no,
    c.VENDOR_ID,
    c.ORDER_DATE,
    c.desired_recv_date,
    c.LINE_NO,

    c.line_item_type,
    c.report_item_id,
    c.SERVICE_ID,
    c.PART_ID,

    c.PURCHASE_UM,
    c.STOCK_UM,

    c.open_qty_purchase_um,
    c.conversion_factor,
    c.open_qty_stock_um,

    c.po_unit_price,
    c.part_site_unit_price,
    c.calc_unit_price_stock_um,

    c.open_qty_purchase_um * c.po_unit_price AS expected_amount_po_um,

    CASE
        WHEN c.open_qty_stock_um IS NOT NULL
         AND c.calc_unit_price_stock_um IS NOT NULL
        THEN c.open_qty_stock_um * c.calc_unit_price_stock_um
        ELSE NULL
    END AS expected_amount_stock_um,

    CASE
        WHEN c.part_site_unit_price IS NOT NULL
         AND c.calc_unit_price_stock_um IS NOT NULL
        THEN c.calc_unit_price_stock_um - c.part_site_unit_price
        ELSE NULL
    END AS stock_um_price_diff

FROM calc c
ORDER BY
    c.desired_recv_date,
    c.purc_order_id,
    c.LINE_NO;