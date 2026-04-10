use veca
select distinct trace_inv_trans.trace_id 
from customer_order  inner join Inventory_trans 
on customer_order.id = inventory_trans.cust_order_id inner join trace_inv_trans 
on trace_inv_trans.TRANSACTION_ID = INVENTORY_TRANS.TRANSACTION_ID 
where customer_id = 'JAYE TIDL'

