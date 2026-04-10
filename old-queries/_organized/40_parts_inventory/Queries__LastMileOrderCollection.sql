/*
====================================================
Author: Tyler Whitlock 
Create Date: 12/2/2022
Title: Customer Order Transfer to LastMile 

NOTES: This script is intended to be used to select the orders that need
to be sent to a 3rd party fulfillment warehouse, and to perform basic
data cleansing.

Change Log ---------------------

Data			Description																	BY
12/2/2022		File Created and Sent to Chance Young for addition to transfer program.		Tyler W
12/7/2022		Updated to Include the Email, phone, and UPC/BARCODE						Tyler W

====================================================
*/

SELECT
--Get the basic sales order information from the customer_order and line tables

CUST_ORDER_LINE.PART_ID as SKU, -- Our PART ID
Cust_order_line.CUSTOMER_PART_ID as CUSTOMER_PART_ID, -- Drop Shippers Part ID
CUST_ORDER_LINE.MISC_REFERENCE as SKU_DESCRIPTION,
cust_order_line.line_no as LINE_NO,
CUST_ORDER_LINE.CUST_ORDER_ID as ORDER_NUMBER, -- Our Internal Order ID	
CUSTOMER_ORDER.CREATE_DATE as ORDER_DATE, -- based on create date to eliminate chance for missed orders
cust_order_line.product_code as COST_CENTER,
CUST_ORDER_LINE.ORDER_QTY as QUANTITY,
customer_order.customer_po_ref as CUSTOMER_PO_NUMBER, -- This should reference the PO number placed by the customer
customer_order.user_2 as DROPSHIP_ORDER_ID, -- This is the order number that needs to go on the pack list

--Get the customer Address Information from the cust_address and customer table if cust_addr is not available
ISNULL(CUST_ADDRESS.name, customer.name) as Name,
isnull(CUST_ADDRESS.addr_1, customer.addr_1) as ADDR_1,
isnull(CUST_ADDRESS.addr_2, customer.addr_2) as ADDR_2,
isnull(CUST_ADDRESS.addr_3, customer.addr_3) as ADDR_3,
isnull(CUST_ADDRESS.city, customer.city) as CITY,
isnull(CUST_ADDRESS.state, customer.state) as state,
isnull(CUST_ADDRESS.ZIPCODE, customer.ZIPCODE) as ZIPCODE,
isnull(CUST_ADDRESS.COUNTRY, customer.COUNTRY) as COUNTRY,

--Get the Customer Phone and email information for the order
isnull (cust_address.user_1, customer.CONTACT_EMAIL) as EMAIL,
isnull (cust_address.user_2, customer.CONTACT_PHONE) as PHONE,

--Get The BARCODE
part.user_6 as BARCODE


FROM
VECA.dbo.CUST_ORDER_LINE CUST_ORDER_LINE
    inner join VECA.dbo.CUSTOMER_ORDER CUSTOMER_ORDER
        on CUST_ORDER_LINE.CUST_ORDER_ID = CUSTOMER_ORDER.ID
    inner join veca.dbo.customer customer
        on customer.id = customer_order.customer_ID
    left join veca.dbo.cust_address cust_address
        on customer_order.customer_id = cust_address.customer_id
            and customer_order.shipto_ID = cust_address.shipto_ID
	left join veca.dbo.part part on part.id = cust_order_line.part_ID

--Limit It down to just the orders that have user defined fields checked        
    inner join VECA.dbo.USER_DEF_FIELDS USER_DEF_FIELDS
        on USER_DEF_FIELDS.DOCUMENT_ID = customer_order.id
    
WHERE
USER_DEF_FIELDS.id = 'UDF-0000056'
and USER_DEF_FIELDS.bool_val = 1
