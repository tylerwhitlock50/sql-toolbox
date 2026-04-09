--This should link to the 7CARMS test server


SELECT 
PLANNED_MATL_REQ.REQUIRED_PART_ID as Part_ID, 
PLANNED_MATL_REQ.REQUIRED_DATE as Required_Date, 
'Forecast' as Source,
sum(PLANNED_MATL_REQ.REQUIRED_QTY) as QTY

FROM VECA.dbo.PLANNED_MATL_REQ PLANNED_MATL_REQ

group by 
PLANNED_MATL_REQ.REQUIRED_PART_ID, 
PLANNED_MATL_REQ.REQUIRED_DATE


union all 
(
select 
inventory_trans.part_id,
inventory_trans.transaction_date,
'Historical' as Source,
sum(inventory_trans.qty) as Qty

from veca.dbo.inventory_trans inventory_trans

where 
inventory_trans.type = 'O' and inventory_trans.class = 'I' and inventory_trans.transaction_date > getdate()-180

group by 
inventory_trans.part_id,
inventory_trans.transaction_date)


