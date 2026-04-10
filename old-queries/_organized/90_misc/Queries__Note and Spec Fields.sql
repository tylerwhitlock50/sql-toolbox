
-- line Specs
SELECT 
PURC_LINE_BINARY.PURC_ORDER_ID, 
PURC_LINE_BINARY.PURC_ORDER_LINE_NO, 
convert(nvarchar(max),convert(varbinary(max),bits)) as Line_Spec

FROM VECA.dbo.PURC_LINE_BINARY PURC_LINE_BINARY

-- Order Specs
SELECT  
PURC_ORDER_BINARY.PURC_ORDER_ID, 
convert(nvarchar(max),convert(varbinary(max),bits)) as Order_Spec

FROM VECA.dbo.PURC_ORDER_BINARY PURC_ORDER_BINARY

--Order Notes
SELECT 
NOTATION.OWNER_ID as PURC_ORDER_ID, 
CONCAT(NOTATION.CREATE_DATE,' - ', 
convert(nvarchar(max),convert(varbinary(max),Note))) as Order_Notes
FROM VECA.dbo.NOTATION NOTATION
where type = 'PO' 

--Vendor Notes
SELECT 
NOTATION.OWNER_ID AS 'VENDOR_ID', 
CONCAT(NOTATION.CREATE_DATE,' - ',convert(nvarchar(max),convert(varbinary(max),Note))) AS 'Vendor_Note'
FROM VECA.dbo.NOTATION NOTATION
WHERE (NOTATION.TYPE In ('V'))

--Customer SPECS
SELECT
customer_Binary.customer_id,
convert(nvarchar(max),convert(varbinary(max),bits)) AS 'Customer_Note'
from VECA.DBO.Customer_Binary Customer_Binary

--Customer Notes
SELECT 
NOTATION.OWNER_ID AS 'Customer_ID', 
CONCAT(NOTATION.CREATE_DATE,' - ',convert(nvarchar(max),convert(varbinary(max),Note))) AS 'Vendor_Note'
FROM VECA.dbo.NOTATION NOTATION
WHERE (NOTATION.TYPE In ('C'))

--Customer Order SPECS

SELECT  
cust_order_BINARY.cust_order_id, 
convert(nvarchar(max),convert(varbinary(max),bits)) as Order_Spec

FROM VECA.dbo.cust_order_binary cust_order_binary


--Customer Notes
SELECT 
NOTATION.OWNER_ID AS 'Order_ID', 
CONCAT(NOTATION.CREATE_DATE,' - ',convert(nvarchar(max),convert(varbinary(max),Note))) AS 'Order_Note'
FROM VECA.dbo.NOTATION NOTATION
WHERE (NOTATION.TYPE In ('SO'))