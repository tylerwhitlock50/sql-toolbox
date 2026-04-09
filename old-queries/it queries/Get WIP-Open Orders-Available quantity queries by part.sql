use veca-- Calculate what is on Order
SELECT
cl.part_id,
p.product_code,
cl.product_code as Customer_order_product_code,
p.commodity_code,
p.description,
sum(cl.order_qty - cl.total_shipped_qty) as open_qty

from cust_order_line CL inner join customer_order CO on CO.id = CL.cust_order_id inner join customer_entity CE on CE.customer_id = CO.customer_id
inner join part p on p.id = cl.part_id

where 
CL.line_status = 'A'
and co.status = 'R'
and CE.credit_status = 'A'
AND isnull(CL.desired_ship_date, CO.desired_ship_date) < getdate()+10

group by 
cl.part_id,
p.product_code,
cl.product_code,
p.commodity_code,
p.description;

-- Calculate what is in WIP
select
work_order.part_id,
sum(work_order.desired_qty - work_order.received_qty) as qty

from work_order
where work_order.create_date > getdate()-30
and work_order.type = 'W'
and work_order.status = 'R'

group by 
work_order.part_id

-- calculate our inventory balances
select
inventory_trans.part_id,
sum(case when inventory_trans.type = 'I' then inventory_trans.qty else -inventory_trans.qty end) as qty

from veca.dbo.inventory_trans inventory_trans
where inventory_trans.warehouse_id = 'SHIPPING'
group by
inventory_trans.part_id

select * from part_location inner join part on part.id = part_location.part_id where location_id = 'C2-Serialized' and qty > 0 and part.COMMODITY_CODE like '%gun%'

select top 1 * from inventory_trans it inner join trace_inv_Trans tit on it.TRANSACTION_ID = tit.TRANSACTION_ID

SELECT location_id, trace_id, part.id, SUM(TRACE_INV_TRANS.qty) AS total
FROM trace_inv_trans
INNER JOIN INVENTORY_TRANS ON TRACE_INV_TRANS.TRANSACTION_ID = INVENTORY_TRANS.transaction_id  
INNER JOIN part ON inventory_trans.part_id = part.id
WHERE part.commodity_code LIKE '%gun%' and warehouse_id = 'main' and location_id = 'c2-serialized'
GROUP BY location_id, trace_id, part.id
HAVING SUM(TRACE_INV_TRANS.qty) > 0 or sum(TRACE_INV_TRANS.qty) <0;
