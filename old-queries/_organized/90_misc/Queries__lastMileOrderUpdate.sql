/*
====================================================
Author: Tyler Whitlock 
Create Date: 12/8/2022
Title: Get Response Object from LastMile 

NOTES: This script is intended to be used to select the orders that need
to be have a status check by a 3rd party fulfillment center.

Change Log ---------------------

Data			Description														BY
12/8/2022		File Created.													Tyler W


====================================================
*/

SELECT
--Get the basic sales order information from the customer_order
customer_order.customer_po_ref as CUSTOMER_PO_NUMBER, -- This should reference the PO number placed by the customer
customer_order.user_2 as DROPSHIP_ORDER_ID -- This is the order number that needs to go on the pack list

FROM
VECA.dbo.CUSTOMER_ORDER CUSTOMER_ORDER
--Limit It down to just the orders that have user defined fields checked        
    inner join VECA.dbo.USER_DEF_FIELDS USER_DEF_FIELDS
        on USER_DEF_FIELDS.DOCUMENT_ID = customer_order.id
    
WHERE
USER_DEF_FIELDS.id = 'UDF-0000056'
and USER_DEF_FIELDS.bool_val = 1

--Limit it to just the orders that are still released
--Ready to be shipped in the system.  Once an order is closed
--we shouldn't need to request a status update.
and customer_order.status = 'R'
