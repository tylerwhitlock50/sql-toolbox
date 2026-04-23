/*
===============================================================================
Query Name: open_and_planned_supply_detail.sql

Purpose:
    Produces a unified supply detail report that combines:
        1. Open purchase orders
        2. Planned purchase orders

    The query normalizes supply quantities and pricing into the part's
    stock unit of measure so that open PO supply and planned supply can
    be compared on a common basis.

Business Use:
    - Review all expected inbound purchased supply in one place
    - Compare actual PO pricing to standard / inventory-side cost
    - Estimate planned order dollar value before a PO exists
    - Support weekly or date-based supply value rollups
    - Identify unusual supply spikes, missing conversions, or pricing issues

Grain:
    One row per supply line.

    Specifically:
    - Open PO rows are at the purchase-order-line / delivery-schedule level
    - Planned order rows are at the planned-order sequence level

High-Level Logic:
    - Pull stock UOM and unit cost from PART_SITE_VIEW
    - Pull open PO quantities from PURCHASE_ORDER / PURC_ORDER_LINE /
      PURC_LINE_DEL
    - Convert PO quantities and prices from PURCHASE_UM to STOCK_UM
    - Pull planned orders from PLANNED_ORDER for purchased parts only
    - Union both supply sources into one shared output structure
    - Calculate expected supply value on both transaction and stock bases

-------------------------------------------------------------------------------

CTE Breakdown

1. part_site
    Source:
        PART_SITE_VIEW

    Purpose:
        Provides the part/site reference attributes needed for normalization:
        - STOCK_UM
        - PURCHASED flag
        - Inventory-side unit cost

    Cost Logic:
        part_site_unit_price =
            UNIT_MATERIAL_COST
          + UNIT_SERVICE_COST
          + UNIT_BURDEN_COST
          + UNIT_LABOR_COST

2. line_sched
    Sources:
        PURCHASE_ORDER
        PURC_ORDER_LINE
        PURC_LINE_DEL

    Purpose:
        Builds the detailed open purchase-order base set, including:
        - PO number
        - Vendor
        - Order date
        - Due date / supply date
        - Ordered quantity
        - Received quantity
        - PO line unit price

    Date Logic:
        supply_date =
            COALESCE(
                delivery schedule desired date,
                line desired date,
                header desired date
            )

    Filters:
        - Excludes PO statuses X and C
        - Excludes line statuses X and C
        - Keeps rows where either:
            - PART_ID is present
            - or SERVICE_ID is present

3. open_lines
    Purpose:
        Converts the raw PO schedule rows into open supply rows.

    Open Quantity Logic:
        open_qty_purchase_um =
            sched_order_qty - sched_received_qty

    Filter:
        Keep only rows where open quantity > 0

4. uom_match
    Purpose:
        Resolves the unit-of-measure conversion needed to move PO quantities
        and prices from PURCHASE_UM into STOCK_UM.

    Conversion Priority:
        1. If PURCHASE_UM = STOCK_UM, use 1.0
        2. Use PART_UNITS_CONV if a part-specific conversion exists
        3. Use UNITS_CONVERSION if a default conversion exists
        4. Otherwise leave conversion as NULL

    Important Note:
        Service-only rows do not participate in part-based UOM conversion.

5. open_po_supply
    Purpose:
        Shapes open purchase-order rows into the common output structure.

    Additional Derived Fields:
        - supply_type = 'OPEN_PO'
        - line_item_type = 'PART' or 'SERVICE'
        - report_item_id
        - open_qty_stock_um
        - calc_unit_price_stock_um

    report_item_id Logic:
        - SERVICE_ID + ' | ' + PART_ID if both exist
        - SERVICE_ID if only service exists
        - PART_ID otherwise

6. planned_order_supply
    Source:
        PLANNED_ORDER

    Purpose:
        Adds planned inbound supply for purchased parts.

    Join / Filter:
        Joined to PART_SITE_VIEW through part_site CTE
        Includes only:
            PURCHASED = 'Y'

    Assumptions:
        Planned order quantity is already expressed in the stock/planning UOM,
        so:
            PURCHASE_UM = STOCK_UM
            conversion_factor = 1.0
            open_qty_stock_um = ORDER_QTY

    Pricing Logic:
        Planned rows do not have an actual PO price yet, so:
            po_unit_price = NULL
            calc_unit_price_stock_um = part_site_unit_price

7. combined_supply
    Purpose:
        UNION ALL of:
            - open_po_supply
            - planned_order_supply

    Result:
        A single, shared supply-detail structure that can be used for:
        - detailed supply review
        - weekly rollups
        - price comparison
        - demand vs supply analysis

-------------------------------------------------------------------------------

Key Output Columns

Identity / Source:
    supply_type
        OPEN_PO or PLANNED_ORDER

    doc_no
        PO number for OPEN_PO
        PLANNED_ORDER ROWID for planned rows

    line_item_type
        PART or SERVICE

    report_item_id
        Human-readable identifier for the row

Dates:
    ORDER_DATE
        Actual PO order date for open PO rows
        NULL for planned rows

    supply_date
        Expected receipt / need date for supply

Units / Quantity:
    PURCHASE_UM
        Transaction-level UOM

    STOCK_UM
        Inventory / normalized UOM

    open_qty_purchase_um
        Open quantity in transaction/purchase UOM

    conversion_factor
        Quantity multiplier to convert PURCHASE_UM to STOCK_UM

    open_qty_stock_um
        Open quantity expressed in STOCK_UM

Pricing:
    po_unit_price
        Actual PO line unit price if available

    part_site_unit_price
        Inventory-side / standard-ish unit cost from PART_SITE_VIEW

    calc_unit_price_stock_um
        Effective unit price expressed in STOCK_UM

        For OPEN_PO:
            po_unit_price / conversion_factor
            (or po_unit_price directly if purchase UOM = stock UOM)

        For PLANNED_ORDER:
            part_site_unit_price

Expected Value:
    expected_amount_po_um
        Supply value on the transaction basis.

        Logic:
            open_qty_purchase_um
            * COALESCE(po_unit_price, calc_unit_price_stock_um)

        Why COALESCE is used:
            Planned rows do not have a real PO unit price, so this falls back
            to calc_unit_price_stock_um to avoid NULL expected values.

    expected_amount_stock_um
        Supply value on the stock-UOM basis.

        Logic:
            open_qty_stock_um * calc_unit_price_stock_um

Price Comparison:
    stock_um_price_diff
        Difference between:
            calc_unit_price_stock_um
            minus
            part_site_unit_price

        This only applies when a real PO price exists.

-------------------------------------------------------------------------------

Business Rules / Assumptions

1. Open PO Status Filtering
    Rows with PO or line status in ('X', 'C') are excluded.

2. Planned Orders Included
    Only planned rows for purchased parts are included:
        PURCHASED = 'Y'

3. Service Lines
    Service rows can appear on open POs.
    These rows may not have STOCK_UM-based conversion logic if they do not
    tie to a valid PART_ID.

4. UOM Conversion Definition
    CONVERSION_FACTOR is assumed to represent:
        FROM_UM -> TO_UM multiplier

    Therefore:
        quantity_in_stock_um = quantity_in_purchase_um * conversion_factor
        price_in_stock_um    = price_in_purchase_um / conversion_factor

5. Missing Conversions
    If PURCHASE_UM <> STOCK_UM and no conversion exists, normalized stock
    quantity and stock-basis price remain NULL.

6. Planned Order Valuation
    Planned rows are valued using part_site_unit_price because there is no
    actual PO price yet.

-------------------------------------------------------------------------------

Common Uses

- Sort by expected_amount_stock_um descending to find the largest inbound
  supply commitments or planned buys
- Aggregate by week_start to visualize total inbound spend by week
- Filter to PART rows only for purchased material analysis
- Filter to SERVICE rows to isolate non-inventory charges on open POs
- Compare expected_amount_po_um vs expected_amount_stock_um to validate
  conversion logic and pricing consistency

-------------------------------------------------------------------------------

Potential Enhancements

- Add week_start directly in this query for easier rollups
- Add vendor name / part description
- Add planner / buyer from PART_SITE_VIEW
- Add explicit missing-conversion flag
- Add price variance percent:
      (calc_unit_price_stock_um / part_site_unit_price) - 1
- Add grouped versions:
      by week
      by vendor
      by part
      by supply_type

===============================================================================
*/

WITH part_site AS (
    SELECT
        ps.SITE_ID,
        ps.PART_ID,
        ps.STOCK_UM,
        ps.PURCHASED,
        ps.UNIT_MATERIAL_COST
        + ps.UNIT_SERVICE_COST
        + ps.UNIT_BURDEN_COST
        + ps.UNIT_LABOR_COST AS part_site_unit_price
    FROM PART_SITE_VIEW ps
),

/* ---------------------------------------------------------------------------
   OPEN PURCHASE ORDERS
--------------------------------------------------------------------------- */
line_sched AS (
    SELECT
        p.ID AS supply_doc_no,
        p.VENDOR_ID,
        p.ORDER_DATE,
        p.SITE_ID,
        p.STATUS AS doc_status,
        pl.LINE_NO,
        pl.PART_ID,
        pl.SERVICE_ID,
        pl.PURCHASE_UM,
        pl.LINE_STATUS,
        COALESCE(pd.DESIRED_RECV_DATE, pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE) AS supply_date,

        COALESCE(pd.ORDER_QTY, pl.ORDER_QTY, 0) AS sched_order_qty,
        COALESCE(pd.RECEIVED_QTY, 0) AS sched_received_qty,

        pl.UNIT_PRICE AS po_unit_price
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl
        ON pl.PURC_ORDER_ID = p.ID
    LEFT JOIN PURC_LINE_DEL pd
        ON pd.PURC_ORDER_ID = pl.PURC_ORDER_ID
       AND pd.PURC_ORDER_LINE_NO = pl.LINE_NO
    WHERE ISNULL(p.STATUS, '') NOT IN ('X', 'C')
      AND ISNULL(pl.LINE_STATUS, '') NOT IN ('X', 'C')
      AND (
            pl.PART_ID IS NOT NULL
            OR NULLIF(LTRIM(RTRIM(pl.SERVICE_ID)), '') IS NOT NULL
          )
),

open_lines AS (
    SELECT
        ls.supply_doc_no,
        ls.VENDOR_ID,
        ls.ORDER_DATE,
        ls.SITE_ID,
        ls.doc_status,
        ls.LINE_NO,
        ls.PART_ID,
        ls.SERVICE_ID,
        ls.PURCHASE_UM,
        ls.LINE_STATUS,
        ls.supply_date,
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

open_po_supply AS (
    SELECT
        'OPEN_PO' AS supply_type,
        um.SITE_ID,
        um.supply_doc_no AS doc_no,
        um.VENDOR_ID,
        um.ORDER_DATE,
        um.supply_date,
        um.LINE_NO,

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

        um.SERVICE_ID,
        um.PART_ID,
        um.PURCHASE_UM,
        um.STOCK_UM,

        um.open_qty_purchase_um,
        um.conversion_factor,

        CASE
            WHEN um.PART_ID IS NULL THEN NULL
            WHEN um.PURCHASE_UM = um.STOCK_UM THEN um.open_qty_purchase_um
            WHEN um.conversion_factor IS NOT NULL THEN um.open_qty_purchase_um * um.conversion_factor
            ELSE NULL
        END AS open_qty_stock_um,

        um.po_unit_price,
        um.part_site_unit_price,

        CASE
            WHEN um.PART_ID IS NULL THEN NULL
            WHEN um.PURCHASE_UM = um.STOCK_UM THEN um.po_unit_price
            WHEN um.conversion_factor IS NOT NULL AND um.conversion_factor <> 0
                THEN um.po_unit_price / um.conversion_factor
            ELSE NULL
        END AS calc_unit_price_stock_um

    FROM uom_match um
),

/* ---------------------------------------------------------------------------
   PLANNED ORDERS
--------------------------------------------------------------------------- */
planned_order_supply AS (
    SELECT
        'PLANNED_ORDER' AS supply_type,
        po.SITE_ID,
        CAST(po.ROWID AS varchar(50)) AS doc_no,
        NULL AS VENDOR_ID,
        NULL AS ORDER_DATE,
        po.WANT_DATE AS supply_date,
        po.SEQ_NO AS LINE_NO,

        'PART' AS line_item_type,
        po.PART_ID AS report_item_id,

        NULL AS SERVICE_ID,
        po.PART_ID,
        ps.STOCK_UM AS PURCHASE_UM,
        ps.STOCK_UM,

        po.ORDER_QTY AS open_qty_purchase_um,
        1.0 AS conversion_factor,
        po.ORDER_QTY AS open_qty_stock_um,

        NULL AS po_unit_price,
        ps.part_site_unit_price,
        ps.part_site_unit_price AS calc_unit_price_stock_um

    FROM PLANNED_ORDER po
    INNER JOIN part_site ps
        ON ps.SITE_ID = po.SITE_ID
       AND ps.PART_ID = po.PART_ID
    WHERE ISNULL(ps.PURCHASED, 'N') = 'Y'
),

/* ---------------------------------------------------------------------------
   COMBINED SUPPLY
--------------------------------------------------------------------------- */
combined_supply AS (
    SELECT
        supply_type,
        SITE_ID,
        doc_no,
        VENDOR_ID,
        ORDER_DATE,
        supply_date,
        LINE_NO,
        line_item_type,
        report_item_id,
        SERVICE_ID,
        PART_ID,
        PURCHASE_UM,
        STOCK_UM,
        open_qty_purchase_um,
        conversion_factor,
        open_qty_stock_um,
        po_unit_price,
        part_site_unit_price,
        calc_unit_price_stock_um
    FROM open_po_supply

    UNION ALL

    SELECT
        supply_type,
        SITE_ID,
        doc_no,
        VENDOR_ID,
        ORDER_DATE,
        supply_date,
        LINE_NO,
        line_item_type,
        report_item_id,
        SERVICE_ID,
        PART_ID,
        PURCHASE_UM,
        STOCK_UM,
        open_qty_purchase_um,
        conversion_factor,
        open_qty_stock_um,
        po_unit_price,
        part_site_unit_price,
        calc_unit_price_stock_um
    FROM planned_order_supply
)

SELECT
    c.supply_type,
    c.SITE_ID,
    c.doc_no,
    c.VENDOR_ID,
    c.ORDER_DATE,
    c.supply_date,
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

    CASE
        WHEN c.open_qty_purchase_um IS NOT NULL
         AND COALESCE(c.po_unit_price, c.calc_unit_price_stock_um) IS NOT NULL
        THEN c.open_qty_purchase_um * COALESCE(c.po_unit_price, c.calc_unit_price_stock_um)
        ELSE NULL
    END AS expected_amount_po_um,

    CASE
        WHEN c.open_qty_stock_um IS NOT NULL
         AND c.calc_unit_price_stock_um IS NOT NULL
        THEN c.open_qty_stock_um * c.calc_unit_price_stock_um
        ELSE NULL
    END AS expected_amount_stock_um,

    CASE
        WHEN c.part_site_unit_price IS NOT NULL
         AND c.calc_unit_price_stock_um IS NOT NULL
         AND c.po_unit_price IS NOT NULL
        THEN c.calc_unit_price_stock_um - c.part_site_unit_price
        ELSE NULL
    END AS stock_um_price_diff

FROM combined_supply c
--where CASE
--        WHEN c.open_qty_stock_um IS NOT NULL
--         AND c.calc_unit_price_stock_um IS NOT NULL
--        THEN c.open_qty_stock_um * c.calc_unit_price_stock_um
--        ELSE NULL
--    END <= 0
ORDER BY
    CASE
        WHEN c.open_qty_stock_um IS NOT NULL
         AND c.calc_unit_price_stock_um IS NOT NULL
        THEN c.open_qty_stock_um * c.calc_unit_price_stock_um
        ELSE NULL
    END DESC;