SELECT 
    part_id,
	part.product_code,
    SUM(act_material_cost + act_labor_cost + act_burden_cost + act_service_cost) AS total_cost,
    COUNT(base_id) AS row_count,
    SUM(act_material_cost + act_labor_cost + act_burden_cost + act_service_cost) / COUNT(base_id) AS avg_cost_per_part
FROM 
    work_order inner join part on work_order.PART_ID = part.id 
	where part.id = '801-03075-00-M' and work_order.STATUS = 'C' and work_order.close_date > DATEADD(DAY, -180, GETDATE())
GROUP BY 
    part_id, part.PRODUCT_CODE;