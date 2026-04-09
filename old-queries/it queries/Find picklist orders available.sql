select
customer_order.ID as order_id,
cust_order_line.line_no,
customer_order.customer_id as customer_id,
customer_order.CUSTOMER_PO_REF as customer_po_ref,
isnull(cust_order_line.desired_ship_date, customer_order.desired_ship_date) as due_date,
part.product_code,
cust_order_line.order_qty as order_qty,
cust_order_line.PART_ID as part_id,
cust_order_line.TOTAL_SHIPPED_QTY as shipped_qty

from 
veca.dbo.customer_order customer_order inner join
    veca.dbo.cust_order_line cust_order_line on cust_order_line.cust_order_id = customer_order.id
    inner join veca.dbo.part on part.id = cust_order_line.part_id

	inner join veca.dbo.customer_entity customer_entity on customer_entity.customer_id = customer_order.customer_id
    left join veca.dbo.demand_supply_link on demand_supply_link.demand_base_id = cust_order_line.cust_order_id and 
        demand_supply_link.[DEMAND_SEQ_NO] = cust_order_line.line_no

where customer_order.status = 'R'
and cust_order_line.line_status = 'A'
and cust_order_line.order_qty - cust_order_line.TOTAL_SHIPPED_QTY > 0
and isnull(cust_order_line.desired_ship_date, customer_order.desired_ship_date) < GetDate() +10
--and customer_order.SALESREP_ID <> 'Inside Sales'
--and customer_order.SALESREP_ID <> 'HUNT WHIT'
and customer_order.SALESREP_ID <> 'RMA'
--and customer_entity.credit_status = 'A'
and customer_order.customer_id <> 'CA MARK'
and demand_supply_link.[SUPPLY_BASE_ID] is null
and customer_order.customer_id not in ('ital sport','VINCK CO','DUNK LEWI',
'BRYC ADAM','JAE HER','ODLE','SPORTCO','TODD VAND','WOLV SUPP','CORL SPOR',
'SYLV SPOR','CORL SPO1', 'CALG SHOO','JEFF BRAD','ANDY STUM','ACT AERO','TANY SAMP','MSSM','PMI SALES')
and customer_order.customer_po_ref <> 'PRO STAFF'