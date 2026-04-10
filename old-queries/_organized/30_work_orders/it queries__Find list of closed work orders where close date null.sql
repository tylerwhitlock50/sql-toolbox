use veca
  select work_order.base_id, work_order.part_id, work_order.create_date, work_order.close_date, work_order.status, work_order.desired_qty, work_order.received_qty, 
  
  inventory_trans.description from work_order inner join inventory_trans 
  on work_order.base_id = inventory_trans.workorder_base_id 
  where status = 'C' 
	and work_order.close_date is null 
	and work_order.create_date > '01-01-23' 
	and inventory_trans.description is null 
  group by base_id,work_order.part_id, work_order.create_date, work_order.close_date, work_order.status, work_order.desired_qty, work_order.received_qty, inventory_trans.description 
  order by  work_order.create_date desc 

 -- select * from inventory_trans where workorder_base_id = '574943'