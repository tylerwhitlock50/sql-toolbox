
use veca
select work_order.base_id, trace_id, work_order.desired_qty, work_order.received_qty, Inventory_trans.type, inventory_Trans.class, Inventory_Trans.qty from work_order
left join inventory_trans 
ON inventory_trans.workorder_base_id = work_order.base_id
left JOIN trace_inv_trans 
ON TRACE_INV_TRANS.TRANSACTION_ID = INVENTORY_TRANS.transaction_id  where trace_id = '4M07685'
and work_order.status = 'C'

group by base_id, trace_id, work_order.desired_qty, work_order.received_qty
HAVING 
    work_order.received_qty <> COALESCE(SUM(inventory_trans.qty), 0);

	SELECT 
    work_order.base_id, 
    --trace_id, 
    work_order.desired_qty, 
    work_order.received_qty,
	inventory_Trans.transaction_id,
	inventory_Trans.qty,
	inventory_trans.type,
	inventory_trans.class
   -- COALESCE(SUM(inventory_trans.qty), 0) AS total_inventory_qty
FROM 
    work_order
LEFT JOIN 
    inventory_trans ON inventory_trans.workorder_base_id = work_order.base_id
    AND inventory_trans.type = 'I'
    AND inventory_trans.class = 'R'
	where work_order.base_id in ('555171','563342','589669')
LEFT JOIN 
    trace_inv_trans ON trace_inv_trans.transaction_id = inventory_trans.transaction_id 
WHERE 
    trace_id = '4M07661'
    AND work_order.status = 'C'
GROUP BY 
    work_order.base_id, 
    trace_id, 
    work_order.desired_qty, 
    work_order.received_qty
HAVING 
    work_order.received_qty <> COALESCE(SUM(inventory_trans.qty), 0);


	select * from inventory_trans where workorder_base_id = '589667'     AND inventory_trans.type = 'I'
    AND inventory_trans.class = 'R'

	SELECT 
    work_order.base_id, 
    work_order.desired_qty, 
    work_order.received_qty, 
    COALESCE(SUM(inventory_trans.qty), 0) AS total_inventory_qty
FROM 
    work_order
LEFT JOIN 
    inventory_trans ON inventory_trans.workorder_base_id = work_order.base_id
    AND inventory_trans.type = 'I'
    AND inventory_trans.class = 'R'
WHERE 
    work_order.status = 'C'
GROUP BY 
    work_order.base_id, 
    work_order.desired_qty, 
    work_order.received_qty
HAVING 
    work_order.received_qty <> COALESCE(SUM(inventory_trans.qty), 0)
order by base_id desc
use veca
SELECT 
    work_order.base_id, 
    work_order.desired_qty, 
    work_order.received_qty, 
    COALESCE(SUM(inventory_trans.qty), 0) AS total_inventory_qty,
    MAX(inventory_trans.create_date) AS last_transaction_date
FROM 
    work_order
LEFT JOIN 
    inventory_trans ON inventory_trans.workorder_base_id = work_order.base_id
    AND inventory_trans.type = 'I'
    AND inventory_trans.class = 'R'
WHERE 
    work_order.status = 'C'
GROUP BY 
    work_order.base_id, 
    work_order.desired_qty, 
    work_order.received_qty
HAVING 
    work_order.received_qty <> COALESCE(SUM(inventory_trans.qty), 0)
ORDER BY 
    last_transaction_date DESC;