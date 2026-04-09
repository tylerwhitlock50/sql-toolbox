select 
user_def_fields.document_id,
user_def_fields.string_val as Tracking_Number
FROM
veca.dbo.user_def_fields user_def_fields

where user_def_fields.id = 'UDF-0000028'

https://www.ups.com/track?loc=null&tracknum=&requester=WT/


SELECT
customer_order.ID,
customer_order.customer_id,
customer_order.customer_po_ref,
customer_order.order_date,
shipper.packlist_id,
shipper.invoice_id,
shipper.shipped_date,
cust_address.name,
cust_address.addr_1,
cust_address.addr_2,
cust_address.city,
cust_address.state,
cust_address.zipcode,
user_def_fields.document_id,
user_def_fields.string_val as Tracking_Number,
RECEIVABLES_RECEIVABLE.INVOICE_STATUS,
CUSTOMER.NAME as Customer_Name,
CUSTOMER.ADDR_1 as Customer_ADDR_1,
CUSTOMER.ADDR_2 as Customer_ADDR_2,
CUSTOMER.ADDR_3 as Customer_ADDR_3,
CUSTOMER.CITY as Customer_ADDR_City,
CUSTOMER.STATE as Customer_ADDR_State,
CUSTOMER.SALESREP_ID



FROM
VECA.dbo.customer_order customer_order 
	inner join VECA.dbo.shipper shipper on customer_order.id = shipper.CUST_ORDER_ID
	inner join VFIN.dbo.RECEIVABLES_RECEIVABLE RECEIVABLES_RECEIVABLE on RECEIVABLES_RECEIVABLE.INVOICE_ID = shipper.invoice_id
	left join VECA.dbo.cust_address on 
		(customer_order.customer_id = Cust_address.customer_id and customer_order.ship_to_addr_no = cust_address.addr_no)
	left join 	VECA.dbo.user_def_fields user_def_fields on shipper.packlist_id = user_def_fields.document_id
	inner join VECA.dbo.CUSTOMER CUSTOMER on customer.id = customer_order.customer_id

	
where 
user_def_fields.id = 'UDF-0000028'
and (shipper.shipped_date >  (getdate()-120) or RECEIVABLES_RECEIVABLE.INVOICE_STATUS = 'OPEN')

