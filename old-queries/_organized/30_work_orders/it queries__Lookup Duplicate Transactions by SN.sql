use VECA

---------- Lookup issues Serial Numbers where there's duplicate items in the shipping area (based on transaction by location)
SELECT trace_id, SUM(TRACE_INV_TRANS.qty) AS total
FROM trace_inv_trans
INNER JOIN INVENTORY_TRANS ON TRACE_INV_TRANS.TRANSACTION_ID = INVENTORY_TRANS.transaction_id  
INNER JOIN part ON inventory_trans.part_id = part.id
WHERE part.commodity_code LIKE '%gun%' and warehouse_id = 'SHIPPING'
GROUP BY trace_id
HAVING SUM(TRACE_INV_TRANS.qty) > 1 or sum(TRACE_INV_TRANS.qty) <0;

----------- Lookup by trace ----------------------
select * 
from inventory_trans inner join trace_inv_trans 
on inventory_trans.transaction_id = trace_inv_trans.TRANSACTION_ID 
where trace_id = 'A95M00486' 
order by inventory_trans.create_date
 
 ----------- Lookup by WO ------------------------
 -- This one helps if a serial number was added out of standard flow to a work order
 select * 
from inventory_trans inner join trace_inv_trans 
on inventory_trans.transaction_id = trace_inv_trans.TRANSACTION_ID 
where workorder_base_id = '594056'
order by inventory_trans.create_date

--------------- Lookup trace by specific location and part ------------------
-- Use this one to get the transaction ID if you find duplicate transactions (such as 2 negative adjustments)
select inventory_trans.transaction_id, trace_inv_trans.trace_id, inventory_trans.create_date, description, inventory_Trans.LOCATION_ID, TRACE_INV_TRANS.qty, inventory_trans.part_id 
from inventory_trans left JOIN trace_inv_trans
ON TRACE_INV_TRANS.TRANSACTION_ID = INVENTORY_TRANS.transaction_id  
where inventory_Trans.part_id = '801-14003-00' and location_id = 'R06S2B10' and trace_id = '19M23M00061'
order by create_Date desc
------------- Lookup info on Work Orders ---------------------
select * from work_order where base_id = '594056'

