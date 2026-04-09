use veca
--select * from RMA where type = 'C'
--select * from RMA_LINE_BINARY

--select * from part_location where location_id = 'R05S2B07' and part_id = '801-12021-00'

SELECT location_id, trace_id, part.id, SUM(TRACE_INV_TRANS.qty) AS total
FROM trace_inv_trans
INNER JOIN INVENTORY_TRANS ON TRACE_INV_TRANS.TRANSACTION_ID = INVENTORY_TRANS.transaction_id  
INNER JOIN part ON inventory_trans.part_id = part.id
WHERE part.commodity_code LIKE '%gun%' and warehouse_id = 'SHIPPING'
GROUP BY location_id, trace_id, part.id
HAVING SUM(TRACE_INV_TRANS.qty) > 1 or sum(TRACE_INV_TRANS.qty) <0;


--select * from part where id = '801-11001-00'

--SELECT location_id, trace_id, part.id, SUM(inventory_Trans.qty) AS total
--FROM trace_inv_trans
--INNER JOIN INVENTORY_TRANS ON TRACE_INV_TRANS.TRANSACTION_ID = INVENTORY_TRANS.transaction_id  
--INNER JOIN part ON inventory_trans.part_id = part.id
--WHERE class = 'A' AND part.commodity_code LIKE '%gun%'
--GROUP BY location_id, trace_id, part.id
--HAVING SUM(inventory_Trans.qty) <> 0;

--select * from inventory_trans where transaction_id in ( '13593966')

--delete from trace_inv_trans where transaction_id in ('13593966')
--select *

--select * from customer_order
select * from part_location where part_id = 'RMA REPAIR'
select * from inventory_trans where transaction_id = '13628695'
select inventory_trans.part_id, inventory_trans.transaction_id, trace_inv_trans.trace_id, inventory_trans.create_date, description, inventory_Trans.LOCATION_ID, TRACE_INV_TRANS.qty 
from inventory_trans left JOIN trace_inv_trans ON TRACE_INV_TRANS.TRANSACTION_ID = INVENTORY_TRANS.transaction_id  where inventory_Trans.part_id = 'RMA REPAIR' and  trace_id = '7M25381'
order by create_Date desc

------- not by part -----------
select inventory_trans.part_id, inventory_trans.transaction_id, trace_inv_trans.trace_id, inventory_trans.create_date, description, inventory_Trans.LOCATION_ID, TRACE_INV_TRANS.qty 
from inventory_trans left JOIN trace_inv_trans ON TRACE_INV_TRANS.TRANSACTION_ID = INVENTORY_TRANS.transaction_id  where workorder_base_id = '589667'
order by create_Date desc

--select * from inventory_trans where inventory_Trans.part_id = '801-01079-00' and location_id = 'R03S2B10'

select * from inventory_trans left JOIN trace_inv_trans 
ON Inventory_trans.TRANSACTION_ID = trace_inv_trans.transaction_id  where trace_id in ('14m22440')
order by INVENTORY_tRANS.create_date desc


select * from inventory_trans left JOIN trace_inv_trans 
ON TRACE_INV_TRANS.TRANSACTION_ID = INVENTORY_TRANS.transaction_id  
--where trace_id = '4M07661'
where workorder_base_id = '592880'
order by INVENTORY_tRANS.create_date desc

--------------------------
select * from work_order where base_id = '589667'
update work_order set Received_qty = 0 where base_id = '597883'

update work_order set Received_qty = 0 where base_id = '589667'

select * from trace where id = '14M22284'
select * from trace_inv_trans where trace_id = '14M22284'

select * from 
select workorder_base_id, inventory_trans.transaction_id, trace_inv_trans.trace_id, inventory_trans.create_date, description, inventory_trans.part_id, inventory_Trans.LOCATION_ID, TRACE_INV_TRANS.qty 
from inventory_trans left JOIN trace_inv_trans ON TRACE_INV_TRANS.TRANSACTION_ID = INVENTORY_TRANS.transaction_id  where trace_id in ('4M07685', 'CV99556','4M07661','RB413106')
order by create_Date desc

select * from work_order where base_id in ('589667',
'589669',
'589669',
'594056',
'589667',
'589668',
'589669',
'563342',
'563342',
'563342',
'563342',
'555171',
'551602',
'501704',
'503336',
'503336',
'501704',
'463091',
'463091')

