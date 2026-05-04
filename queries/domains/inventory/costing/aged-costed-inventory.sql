Select 
it.type,
it.class,
it.part_id,
p.description,
isnull(ps.product_code, p.product_code) as prod_code,
it.qty,
it.qty - it.costed_qty as costed_qty,
it.warehouse_id,
it.location_id,
it.transaction_date,
datediff(day, it.transaction_date, Getdate()) as age_days,
it.act_material_cost + it.act_labor_cost + it.act_burden_cost + it.act_service_cost as cost,
it.purc_order_id,
v.name

from 
	inventory_trans it
		left join part p on 
		  it.part_id = p.id
		left join part_site ps on 
		  it.part_id = ps.part_id and
		  ps.site_id = 'CCF'
		left join purchase_order po on 
		  it.purc_order_id = po.id
		left join vendor v on 
		  po.vendor_id = v.id
where qty > costed_qty 
and it.part_id is not null
--and it.warehouse_id in (@WHSE)