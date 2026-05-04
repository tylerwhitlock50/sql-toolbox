/*
Purpose
    Explain why parts flagged as potentially obsolete should or should not be retired.

Inputs
    None (no runtime parameters in this version).
    Candidate scope is derived from part metadata:
      - Active parts with description containing '**obs'
      - Active parts with BUYER_USER_ID = 'DO NOT ORDER'

Expected output shape
    One row per candidate (PART_ID, SITE_ID) with:
      - Basic part/site metadata
      - Last non-adjustment inventory transaction date
      - Boolean diagnostic flags (0/1) for open demand, open supply, engineering/master
        dependencies, and manufacturing/BOM usage that may block retirement.

Caveats
    - Candidate matching depends on naming/flagging discipline ('**obs', 'DO NOT ORDER').
    - Some flags are part-level only (not site-specific) where source tables are not site-keyed.
    - This is a diagnostic explainer, not an automated retire/disable action script.
*/

-- Parameter block (none currently). Keep this query parameterless for ad-hoc diagnostics.

-- 1) Candidate parts likely marked obsolete but still active.
WITH candidate_parts AS (
    SELECT DISTINCT
        psv.part_id,
        psv.site_id,
        psv.description,
        psv.status,
        psv.qty_on_hand,
        psv.product_code,
        psv.commodity_code,
        psv.buyer_user_id
    FROM part_site_view psv
    WHERE 
        (
            psv.description LIKE '%**obs%'
            AND psv.status = 'A'
        )
        OR (psv.buyer_user_id = 'DO NOT ORDER' AND psv.status = 'A')
),
-- 2) Last inventory transaction date by part (excluding adjustment class 'A').
last_inv_trans AS (
    SELECT
        part_id,
        MAX(transaction_date) AS last_inv_trans
    FROM inventory_trans
    WHERE class <> 'A'
    GROUP BY part_id
)

-- 3) Diagnostic flags: anything still open/active that suggests "do not fully retire yet".
SELECT
    cp.part_id,
    cp.site_id,
    cp.description,
    cp.status,
    cp.qty_on_hand,
    cp.product_code,
    cp.commodity_code,
    cp.buyer_user_id,
    lit.last_inv_trans,

    -- Inventory still on hand.
    CASE WHEN COALESCE(cp.qty_on_hand, 0) <> 0 THEN 1 ELSE 0 END AS has_qty_on_hand,

    -- Open PO lines still inbound.
    CASE WHEN EXISTS (
        SELECT 1
        FROM purchase_order po
        INNER JOIN purc_order_line pol
            ON po.id = pol.purc_order_id
        WHERE pol.part_id = cp.part_id
          AND po.status IN ('R', 'H', 'F')
    ) THEN 1 ELSE 0 END AS has_open_po,

    -- Open customer demand remains.
    CASE WHEN EXISTS (
        SELECT 1
        FROM customer_order co
        INNER JOIN cust_order_line col
            ON co.id = col.cust_order_id
        WHERE col.part_id = cp.part_id
          AND co.status IN ('R', 'H', 'F')
          AND col.line_status = 'A'
          AND COALESCE(col.order_qty, 0) - COALESCE(col.total_shipped_qty, 0) > 0
    ) THEN 1 ELSE 0 END AS has_open_customer_order,

    -- Active RFQ activity still in process.
    CASE WHEN EXISTS (
        SELECT 1
        FROM request_for_quote rfq
        INNER JOIN rfq_line rfql
            ON rfq.id = rfql.rfq_id
        WHERE rfql.part_id = cp.part_id
          AND rfq.status = 'A'
    ) THEN 1 ELSE 0 END AS has_open_rfq,

    -- Open inter-branch transfer references this part.
    CASE WHEN EXISTS (
        SELECT 1
        FROM ibt ibt
        INNER JOIN ibt_line ibtl
            ON ibt.id = ibtl.ibt_id
        WHERE ibtl.part_id = cp.part_id
          AND ibt.status IN ('F', 'R', 'S')
    ) THEN 1 ELSE 0 END AS has_open_ibt,

    -- Open/held return activity linked to original order line.
    CASE WHEN EXISTS (
        SELECT 1
        FROM rma rma
        INNER JOIN rma_line rmal
            ON rma.id = rmal.rma_id
        INNER JOIN cust_order_line col
            ON rma.org_cust_order_id = col.cust_order_id
           AND rmal.org_order_line_no = col.line_no
        WHERE col.part_id = cp.part_id
          AND rma.status IN ('R', 'O', 'H')
    ) THEN 1 ELSE 0 END AS has_open_rma,

    -- Open engineering changes reference this part.
    CASE WHEN EXISTS (
        SELECT 1
        FROM ec e
        INNER JOIN ec_line l
            ON e.id = l.ec_id
        WHERE l.part_id = cp.part_id
          AND e.status IN ('U', 'P', 'I', 'H')
          AND l.status = 'O'
    ) THEN 1 ELSE 0 END AS has_open_engineering_change,

    -- Part is still the parent/item on an open work order.
    CASE WHEN EXISTS (
        SELECT 1
        FROM work_order wo
        WHERE wo.type = 'W'
          AND wo.part_id = cp.part_id
          AND wo.site_id = cp.site_id
          AND wo.status IN ('U', 'F', 'R')
    ) THEN 1 ELSE 0 END AS is_on_open_work_order,

    -- Part is still a co-product on an open work order.
    CASE WHEN EXISTS (
        SELECT 1
        FROM co_product cop
        INNER JOIN work_order wo
            ON cop.workorder_type = wo.type
           AND cop.workorder_base_id = wo.base_id
           AND cop.workorder_lot_id = wo.lot_id
           AND cop.workorder_split_id = wo.split_id
           AND cop.workorder_sub_id = wo.sub_id
        WHERE cop.part_id = cp.part_id
          AND wo.type = 'W'
          AND wo.site_id = cp.site_id
          AND wo.status IN ('U', 'F', 'R')
    ) THEN 1 ELSE 0 END AS is_coproduct_on_open_work_order,

    -- Part is still required as a component by an open work order.
    CASE WHEN EXISTS (
        SELECT 1
        FROM requirement rq
        INNER JOIN work_order wo
            ON rq.workorder_type = wo.type
           AND rq.workorder_base_id = wo.base_id
           AND rq.workorder_lot_id = wo.lot_id
           AND rq.workorder_split_id = wo.split_id
        WHERE rq.part_id = cp.part_id
          AND wo.type = 'W'
          AND wo.site_id = cp.site_id
          AND wo.status IN ('U', 'F', 'R')
    ) THEN 1 ELSE 0 END AS required_by_open_work_order,

    -- Part exists on a master BOM (M-type requirements).
    CASE WHEN EXISTS (
        SELECT 1
        FROM requirement rq
        WHERE rq.part_id = cp.part_id
          AND rq.workorder_type = 'M'
    ) THEN 1 ELSE 0 END AS is_on_master_bom,

    -- Part has an active master.
    CASE WHEN EXISTS (
        SELECT 1
        FROM work_order wo
        WHERE wo.part_id = cp.part_id
          AND wo.site_id = cp.site_id
          AND wo.type = 'M'
          AND wo.inactive = 'N'
    ) THEN 1 ELSE 0 END AS has_active_master,

    -- Part is a co-product on an active master.
    CASE WHEN EXISTS (
        SELECT 1
        FROM co_product cop
        INNER JOIN work_order wo
            ON cop.workorder_type = wo.type
           AND cop.workorder_base_id = wo.base_id
           AND cop.workorder_lot_id = wo.lot_id
           AND cop.workorder_split_id = wo.split_id
           AND cop.workorder_sub_id = wo.sub_id
        WHERE cop.part_id = cp.part_id
          AND wo.type = 'M'
          AND wo.inactive = 'N'
    ) THEN 1 ELSE 0 END AS is_coproduct_on_active_master

FROM candidate_parts cp
LEFT JOIN last_inv_trans lit
    ON lit.part_id = cp.part_id
ORDER BY
    cp.part_id,
    cp.site_id;