select
part.id,
case when part.qty  >0 then 'Available' else 'Unavailable' end as Status

from(

select
part.ID,
sum(part.qty) as Qty

from(
SELECT
 PART.ID, 
 PART.QTY_ON_HAND as Qty
FROM VECA.dbo.PART PART


Union all

select
WORK_ORDER.PART_ID,
WORK_ORDER.DESIRED_QTY - WORK_ORDER.RECEIVED_QTY as Qty

from
veca.dbo.work_order work_order
where 

WORK_ORDER.STATUS = 'R') as Part

where part.id is not null

group by part.id) as Part

