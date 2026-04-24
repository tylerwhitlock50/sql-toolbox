/*
===============================================================================
Query Name: material_shortage_vs_open_demand.sql

Purpose:
    Show which purchased materials are short against open work-order
    requirements, and tie those shortages back to the customer orders they
    are supporting. This answers:

        "Which sales orders are at risk of slipping because purchasing
         hasn't covered the material yet?"

    Complements the existing supply-side queries
    (open_and_planned_supply_detail.sql) by joining demand back up to the
    customer order.

Grain:
    One row per (PART_ID, SITE_ID) with shortage. Aggregates:
      * open demand across active work-order requirements
      * on-hand + open supply (PO + planned)
      * linked open sales-order demand (count, qty, $)

Logic:
    1. Collect open WO requirements:
         STATUS = 'U' (per VECA convention; 'A' returns 0 rows)
         Remaining req qty = CALC_QTY - ISSUED_QTY
    2. Collect open PO + planned supply, normalized to stock UOM
    3. On-hand from PART_SITE_VIEW.QTY_ON_HAND (site-level)
    4. Projected position = on_hand + open_supply - open_req_qty
    5. A shortage exists when projected_position < 0
    6. Tie back to open customer-order lines for the same PART_ID at the
       same site (direct demand) so you can see $ of orders at risk.

Notes / Assumptions:
    - Does NOT walk the BOM upward. If PART X is short and is a component
      of a sub-assembly that feeds a sales order, X will not show demand
      on the SO side. To get that full picture, layer this against
      recursive_bom_from_masters.sql results. This query focuses on
      purchased parts, which are the supply-chain team's direct
      responsibility.
    - Uses REQUIREMENT.STATUS = 'U' (unfulfilled) per project convention.
    - Direct CO linkage only: SO lines where PART_ID directly matches.
      For top-level assemblies this is fine; for purchased sub-assemblies
      it is under-counting.

Business Use:
    - Daily "shortages that will break shipments" review
    - Drive buyer callouts to specific vendors with specific dates
    - Quantify cost of delay to the commercial team
===============================================================================
*/

DECLARE @Site nvarchar(15) = NULL;

;WITH part_site AS (
    SELECT
        psv.SITE_ID,
        psv.PART_ID,
        psv.DESCRIPTION,
        psv.STOCK_UM,
        psv.PRODUCT_CODE,
        psv.COMMODITY_CODE,
        psv.PURCHASED,
        psv.FABRICATED,
        psv.BUYER_USER_ID,
        psv.PLANNER_USER_ID,
        psv.PLANNING_LEADTIME,
        psv.QTY_ON_HAND,
        psv.SAFETY_STOCK_QTY,
        (psv.UNIT_MATERIAL_COST
         + psv.UNIT_LABOR_COST
         + psv.UNIT_BURDEN_COST
         + psv.UNIT_SERVICE_COST) AS std_unit_cost
    FROM PART_SITE_VIEW psv
    WHERE (@Site IS NULL OR psv.SITE_ID = @Site)
),

-- Open material requirements from active work orders
open_req AS (
    SELECT
        wo.SITE_ID,
        rq.PART_ID,
        SUM(COALESCE(rq.CALC_QTY, 0) - COALESCE(rq.ISSUED_QTY, 0)) AS open_req_qty,
        MIN(rq.REQUIRED_DATE)                                      AS earliest_required_date,
        COUNT(DISTINCT
              rq.WORKORDER_TYPE    + '|'
            + rq.WORKORDER_BASE_ID + '|'
            + rq.WORKORDER_LOT_ID  + '|'
            + rq.WORKORDER_SPLIT_ID+ '|'
            + rq.WORKORDER_SUB_ID)                                 AS open_wos
    FROM REQUIREMENT rq
    INNER JOIN WORK_ORDER wo
        ON wo.TYPE      = rq.WORKORDER_TYPE
       AND wo.BASE_ID   = rq.WORKORDER_BASE_ID
       AND wo.LOT_ID    = rq.WORKORDER_LOT_ID
       AND wo.SPLIT_ID  = rq.WORKORDER_SPLIT_ID
       AND wo.SUB_ID    = rq.WORKORDER_SUB_ID
    WHERE rq.STATUS      = 'U'
      AND ISNULL(wo.STATUS, '') NOT IN ('X','C')
      AND rq.PART_ID IS NOT NULL
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
      AND (COALESCE(rq.CALC_QTY, 0) - COALESCE(rq.ISSUED_QTY, 0)) > 0
    GROUP BY wo.SITE_ID, rq.PART_ID
),

-- Open PO supply (stock-UOM, using conversion factor logic)
open_po_supply AS (
    SELECT
        p.SITE_ID,
        pl.PART_ID,
        SUM(
            (pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY) *
            CASE
                WHEN pl.PURCHASE_UM = ps.STOCK_UM            THEN 1.0
                WHEN puc.CONVERSION_FACTOR IS NOT NULL       THEN puc.CONVERSION_FACTOR
                WHEN duc.CONVERSION_FACTOR IS NOT NULL       THEN duc.CONVERSION_FACTOR
                ELSE 1.0
            END
        )                                                    AS open_po_qty_stock_um,
        MIN(COALESCE(pl.DESIRED_RECV_DATE,
                     p.PROMISE_DATE,
                     p.DESIRED_RECV_DATE))                   AS earliest_po_recv_date
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl
        ON pl.PURC_ORDER_ID = p.ID
    LEFT JOIN part_site ps
        ON ps.SITE_ID = p.SITE_ID
       AND ps.PART_ID = pl.PART_ID
    LEFT JOIN PART_UNITS_CONV puc
        ON puc.PART_ID = pl.PART_ID
       AND puc.FROM_UM = pl.PURCHASE_UM
       AND puc.TO_UM   = ps.STOCK_UM
    LEFT JOIN UNITS_CONVERSION duc
        ON duc.FROM_UM = pl.PURCHASE_UM
       AND duc.TO_UM   = ps.STOCK_UM
    WHERE ISNULL(p.STATUS, '')        NOT IN ('X','C')
      AND ISNULL(pl.LINE_STATUS, '')  NOT IN ('X','C')
      AND pl.PART_ID IS NOT NULL
      AND pl.ORDER_QTY > pl.TOTAL_RECEIVED_QTY
      AND (@Site IS NULL OR p.SITE_ID = @Site)
    GROUP BY p.SITE_ID, pl.PART_ID
),

planned_supply AS (
    SELECT
        po.SITE_ID,
        po.PART_ID,
        SUM(po.ORDER_QTY) AS planned_qty_stock_um
    FROM PLANNED_ORDER po
    WHERE (@Site IS NULL OR po.SITE_ID = @Site)
    GROUP BY po.SITE_ID, po.PART_ID
),

-- Open customer-order demand for the same part (direct linkage only)
open_so_demand AS (
    SELECT
        col.SITE_ID,
        col.PART_ID,
        COUNT(*)                                                    AS open_so_lines,
        COUNT(DISTINCT col.CUST_ORDER_ID)                           AS open_so_count,
        SUM(col.ORDER_QTY - col.TOTAL_SHIPPED_QTY)                  AS open_so_qty,
        SUM((col.ORDER_QTY - col.TOTAL_SHIPPED_QTY) * col.UNIT_PRICE)
                                                                    AS open_so_value,
        MIN(col.DESIRED_SHIP_DATE)                                  AS earliest_so_ship_date
    FROM CUST_ORDER_LINE col
    INNER JOIN CUSTOMER_ORDER co
        ON co.ID = col.CUST_ORDER_ID
    -- Canonical open-order filter (see so_header_and_lines_open_orders.sql):
    -- header STATUS IN ('R','F') and line LINE_STATUS = 'A'.
    WHERE co.STATUS IN ('R', 'F')
      AND col.LINE_STATUS = 'A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
      AND (@Site IS NULL OR col.SITE_ID = @Site)
    GROUP BY col.SITE_ID, col.PART_ID
),

combined AS (
    SELECT
        ps.SITE_ID,
        ps.PART_ID,
        ps.DESCRIPTION,
        ps.PRODUCT_CODE,
        ps.COMMODITY_CODE,
        ps.PURCHASED,
        ps.FABRICATED,
        ps.BUYER_USER_ID,
        ps.PLANNER_USER_ID,
        ps.PLANNING_LEADTIME,
        ps.STOCK_UM,
        ps.std_unit_cost,

        COALESCE(ps.QTY_ON_HAND,           0)  AS qty_on_hand,
        COALESCE(ps.SAFETY_STOCK_QTY,      0)  AS safety_stock,
        COALESCE(orq.open_req_qty,         0)  AS open_wo_req_qty,
        orq.earliest_required_date,
        COALESCE(orq.open_wos,             0)  AS open_wos,
        COALESCE(ops.open_po_qty_stock_um, 0)  AS open_po_qty,
        ops.earliest_po_recv_date,
        COALESCE(pls.planned_qty_stock_um, 0)  AS planned_qty,
        COALESCE(sod.open_so_lines,        0)  AS open_so_lines,
        COALESCE(sod.open_so_count,        0)  AS open_so_count,
        COALESCE(sod.open_so_qty,          0)  AS open_so_qty,
        COALESCE(sod.open_so_value,        0)  AS open_so_value_at_risk,
        sod.earliest_so_ship_date
    FROM part_site ps
    LEFT JOIN open_req         orq ON orq.SITE_ID = ps.SITE_ID AND orq.PART_ID = ps.PART_ID
    LEFT JOIN open_po_supply   ops ON ops.SITE_ID = ps.SITE_ID AND ops.PART_ID = ps.PART_ID
    LEFT JOIN planned_supply   pls ON pls.SITE_ID = ps.SITE_ID AND pls.PART_ID = ps.PART_ID
    LEFT JOIN open_so_demand   sod ON sod.SITE_ID = ps.SITE_ID AND sod.PART_ID = ps.PART_ID
    WHERE
        -- only parts with something going on
        (COALESCE(orq.open_req_qty, 0) > 0
         OR COALESCE(sod.open_so_qty, 0) > 0)
)

SELECT
    c.SITE_ID,
    c.PART_ID,
    c.DESCRIPTION,
    c.PRODUCT_CODE,
    c.COMMODITY_CODE,
    c.PURCHASED,
    c.FABRICATED,
    c.BUYER_USER_ID,
    c.PLANNER_USER_ID,
    c.PLANNING_LEADTIME,

    c.STOCK_UM,
    c.qty_on_hand,
    c.safety_stock,
    c.open_wos,
    c.open_wo_req_qty,
    c.earliest_required_date,

    c.open_po_qty,
    c.earliest_po_recv_date,
    c.planned_qty,

    (c.qty_on_hand + c.open_po_qty + c.planned_qty
     - c.open_wo_req_qty)                           AS projected_position,

    CASE
        WHEN (c.qty_on_hand + c.open_po_qty + c.planned_qty - c.open_wo_req_qty) < 0
            THEN ABS(c.qty_on_hand + c.open_po_qty + c.planned_qty - c.open_wo_req_qty)
        ELSE 0
    END                                             AS shortage_qty,

    CASE
        WHEN (c.qty_on_hand + c.open_po_qty + c.planned_qty - c.open_wo_req_qty) < 0
            THEN ABS(c.qty_on_hand + c.open_po_qty + c.planned_qty - c.open_wo_req_qty)
                 * c.std_unit_cost
        ELSE 0
    END                                             AS shortage_value_at_std,

    -- Days late vs earliest required date (negative = we still have time)
    DATEDIFF(day, c.earliest_po_recv_date, c.earliest_required_date)
                                                    AS po_recv_vs_required_gap_days,

    c.open_so_count,
    c.open_so_qty,
    c.open_so_value_at_risk,
    c.earliest_so_ship_date,

    CASE
        WHEN (c.qty_on_hand + c.open_po_qty + c.planned_qty - c.open_wo_req_qty) < 0
         AND c.open_so_value_at_risk > 0                THEN 'CRITICAL - short + SO demand'
        WHEN (c.qty_on_hand + c.open_po_qty + c.planned_qty - c.open_wo_req_qty) < 0
                                                        THEN 'SHORT'
        WHEN c.earliest_po_recv_date > c.earliest_required_date
                                                        THEN 'PO LATE FOR NEED'
        WHEN c.open_po_qty = 0 AND c.planned_qty = 0
         AND c.open_wo_req_qty > c.qty_on_hand           THEN 'NO COVERAGE PLANNED'
        ELSE                                                 'OK'
    END                                             AS status
FROM combined c
ORDER BY
    CASE
        WHEN (c.qty_on_hand + c.open_po_qty + c.planned_qty - c.open_wo_req_qty) < 0
         AND c.open_so_value_at_risk > 0 THEN 1
        WHEN (c.qty_on_hand + c.open_po_qty + c.planned_qty - c.open_wo_req_qty) < 0 THEN 2
        ELSE 3
    END,
    c.open_so_value_at_risk DESC,
    c.PART_ID;
