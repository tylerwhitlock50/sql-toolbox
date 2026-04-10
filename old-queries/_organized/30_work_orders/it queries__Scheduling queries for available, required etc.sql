use veca
SELECT part.id, REQUIREMENT.PART_ID AS ID, MATL.QTY_AVAILABLE_MRP AS ON_HAND, REQUIREMENT.CALC_QTY AS REQUIRED, MATL.DESCRIPTION, MAIN_OHB.QTY as IN_WAREHOUSE
FROM REQUIREMENT INNER JOIN PART_SITE 
ON REQUIREMENT.WORKORDER_BASE_ID=PART_SITE.PART_ID AND REQUIREMENT.WORKORDER_LOT_ID = PART_SITE.ENGINEERING_MSTR 
INNER JOIN PART ON PART.ID=PART_SITE.PART_ID 
INNER JOIN PART MATL ON MATL.ID=REQUIREMENT.PART_ID 
LEFT OUTER JOIN 
(
	
SELECT PART_LOCATION.PART_ID, Sum(PART_LOCATION.QTY) AS QTY 
FROM PART_LOCATION 
WHERE PART_LOCATION.STATUS='A' AND PART_LOCATION.WAREHOUSE_ID='MAIN' 
GROUP BY PART_LOCATION.PART_ID 
	
) AS MAIN_OHB ON MAIN_OHB.PART_ID=REQUIREMENT.PART_ID 
	
	--WHERE REQUIREMENT.WORKORDER_BASE_ID='801-14003-00' 
	ORDER BY part.id, REQUIREMENT.OPERATION_SEQ_NO, REQUIREMENT.PIECE_NO

	select top 1 * from work_order

	select
work_order.base_id, work_order.part_id,
sum(work_order.desired_qty - work_order.received_qty) as qty
 
from work_order
where work_order.create_date > getdate()-30
and work_order.type = 'W'
and work_order.status = 'R'
 
group by 
work_order.base_id, work_order.part_id

select
inventory_trans.part_id,
sum(case when inventory_trans.type = 'I' then inventory_trans.qty else -inventory_trans.qty end) as qty
 
from veca.dbo.inventory_trans inventory_trans
where inventory_trans.warehouse_id = 'SHIPPING'
group by
inventory_trans.part_id