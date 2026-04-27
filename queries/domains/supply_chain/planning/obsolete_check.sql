DECLARE @SiteID VARCHAR(10) = NULL;  -- NULL = all sites

WITH last_inv_trans AS (
    SELECT
        part_id,
        MAX(transaction_date) AS last_inv_trans
    FROM inventory_trans
    WHERE class <> 'A'
    GROUP BY part_id
)
SELECT DISTINCT
    psv.part_id,
    psv.site_id,
    psv.description,
    psv.status,
    psv.product_code,
    psv.commodity_code,
    psv.fabricated,
    psv.purchased,
    psv.consumable,
    psv.detail_only,
    psv.drawing_rev_no,
    psv.planner_user_id,
    psv.buyer_user_id,
    psv.create_date,
    psv.qty_on_hand,
    lit.last_inv_trans
FROM part_site_view psv
LEFT JOIN last_inv_trans lit
    ON lit.part_id = psv.part_id
WHERE (@SiteID IS NULL OR psv.site_id = @SiteID)

-- active / usable parts only
  AND ISNULL(psv.status, 'A') <> 'O'
  AND ISNULL(psv.consumable, 'N') = 'N'

-- no quantity anywhere for this part
  AND NOT EXISTS (
        SELECT 1
        FROM part_site_view qty_check
        WHERE qty_check.part_id = psv.part_id
          AND COALESCE(qty_check.qty_on_hand, 0) <> 0
  )

-- no open purchase orders
  AND NOT EXISTS (
        SELECT 1
        FROM purchase_order po
        INNER JOIN purc_order_line pol
            ON po.id = pol.purc_order_id
        WHERE pol.part_id = psv.part_id
          AND po.status IN ('R', 'H', 'F')
  )

-- no purchase orders created in last 365 days
  AND NOT EXISTS (
        SELECT 1
        FROM purchase_order po
        INNER JOIN purc_order_line pol
            ON po.id = pol.purc_order_id
        WHERE pol.part_id = psv.part_id
          AND po.create_date >= DATEADD(DAY, -365, GETDATE())
  )

-- no open customer orders
  AND NOT EXISTS (
        SELECT 1
        FROM customer_order co
        INNER JOIN cust_order_line col
            ON co.id = col.cust_order_id
        WHERE col.part_id = psv.part_id
          AND co.status IN ('R', 'H', 'F')
          AND col.line_status = 'A'
          AND COALESCE(col.order_qty, 0) - COALESCE(col.total_shipped_qty, 0) > 0
  )

-- no shipments in last 365 days
  AND NOT EXISTS (
        SELECT 1
        FROM shipper_line sl
        INNER JOIN shipper s
            ON sl.packlist_id = s.packlist_id
        INNER JOIN cust_order_line col
            ON col.cust_order_id = sl.cust_order_id
           AND col.line_no = sl.cust_order_line_no
        WHERE col.part_id = psv.part_id
          AND s.create_date >= DATEADD(DAY, -365, GETDATE())
  )

-- no open RFQs
  AND NOT EXISTS (
        SELECT 1
        FROM request_for_quote rfq
        INNER JOIN rfq_line rfql
            ON rfq.id = rfql.rfq_id
        WHERE rfql.part_id = psv.part_id
          AND rfq.status = 'A'
  )

-- no open inter-branch transfers
  AND NOT EXISTS (
        SELECT 1
        FROM ibt ibt
        INNER JOIN ibt_line ibtl
            ON ibt.id = ibtl.ibt_id
        WHERE ibtl.part_id = psv.part_id
          AND ibt.status IN ('F', 'R', 'S')
  )

-- no open RMAs
  AND NOT EXISTS (
        SELECT 1
        FROM rma rma
        INNER JOIN rma_line rmal
            ON rma.id = rmal.rma_id
        INNER JOIN cust_order_line col
            ON rma.org_cust_order_id = col.cust_order_id
           AND rmal.org_order_line_no = col.line_no
        WHERE col.part_id = psv.part_id
          AND rma.status IN ('R', 'O', 'H')
  )

-- no open engineering changes
  AND NOT EXISTS (
        SELECT 1
        FROM ec e
        INNER JOIN ec_line l
            ON e.id = l.ec_id
        WHERE l.part_id = psv.part_id
          AND e.status IN ('U', 'P', 'I', 'H')
          AND l.status = 'O'
  )

-- not currently being built on an open W-type work order
  AND NOT EXISTS (
        SELECT 1
        FROM work_order wo
        WHERE wo.type = 'W'
          AND wo.part_id = psv.part_id
          AND wo.site_id = psv.site_id
          AND wo.status IN ('U', 'F', 'R')
  )

-- not a co-product on an open W-type work order
  AND NOT EXISTS (
        SELECT 1
        FROM co_product cp
        INNER JOIN work_order wo
            ON cp.workorder_type = wo.type
           AND cp.workorder_base_id = wo.base_id
           AND cp.workorder_lot_id = wo.lot_id
           AND cp.workorder_split_id = wo.split_id
           AND cp.workorder_sub_id = wo.sub_id
        WHERE cp.part_id = psv.part_id
          AND wo.type = 'W'
          AND wo.site_id = psv.site_id
          AND wo.status IN ('U', 'F', 'R')
  )

-- not required by an open W-type work order
  AND NOT EXISTS (
        SELECT 1
        FROM requirement rq
        INNER JOIN work_order wo
            ON rq.workorder_type = wo.type
           AND rq.workorder_base_id = wo.base_id
           AND rq.workorder_lot_id = wo.lot_id
           AND rq.workorder_split_id = wo.split_id
        WHERE rq.part_id = psv.part_id
          AND wo.type = 'W'
          AND wo.site_id = psv.site_id
          AND wo.status IN ('U', 'F', 'R')
  )

-- not on any M-type engineering master / BOM requirement
  AND NOT EXISTS (
        SELECT 1
        FROM requirement rq
        WHERE rq.part_id = psv.part_id
          AND rq.workorder_type = 'M'
  )

-- does not itself have an active M-type master
  AND NOT EXISTS (
        SELECT 1
        FROM work_order wo
        WHERE wo.part_id = psv.part_id
          AND wo.site_id = psv.site_id
          AND wo.type = 'M'
          AND wo.inactive = 'N'
  )

-- not a requirement on an active M-type master,
-- unless the parent master part is obsolete
  AND NOT EXISTS (
        SELECT 1
        FROM requirement rq
        INNER JOIN work_order wo
            ON rq.workorder_type = wo.type
           AND rq.workorder_base_id = wo.base_id
           AND rq.workorder_lot_id = wo.lot_id
           AND rq.workorder_split_id = wo.split_id
           AND rq.workorder_sub_id = wo.sub_id
           AND wo.site_id = psv.site_id
        LEFT JOIN part_site_view parent_psv
            ON parent_psv.part_id = wo.part_id
           AND parent_psv.site_id = wo.site_id
        WHERE rq.part_id = psv.part_id
          AND wo.type = 'M'
          AND wo.inactive = 'N'
          AND (parent_psv.status <> 'O' OR parent_psv.status IS NULL)
  )

-- not a co-product on an active M-type master,
-- unless the parent master part is obsolete
  AND NOT EXISTS (
        SELECT 1
        FROM co_product cp
        INNER JOIN work_order wo
            ON cp.workorder_type = wo.type
           AND cp.workorder_base_id = wo.base_id
           AND cp.workorder_lot_id = wo.lot_id
           AND cp.workorder_split_id = wo.split_id
           AND cp.workorder_sub_id = wo.sub_id
           AND wo.site_id = psv.site_id
        LEFT JOIN part_site_view parent_psv
            ON parent_psv.part_id = wo.part_id
           AND parent_psv.site_id = wo.site_id
        WHERE cp.part_id = psv.part_id
          AND wo.type = 'M'
          AND wo.inactive = 'N'
          AND (parent_psv.status <> 'O' OR parent_psv.status IS NULL)
  )

ORDER BY
    psv.part_id,
    psv.site_id;