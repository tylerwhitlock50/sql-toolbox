select *
from(



SELECT
QTY.part_id,
Qty.Description,
qty.qty,
qty.UPC,
qty.PRODUCT_CODE,
ROW_NUMBER() over (PARTITION by qty.product_code order by qty.qty desc) as SKU_rank


from(
SELECT 
CUST_ORDER_LINE.PART_ID, 
PART.DESCRIPTION, 
sum(SHIPPER_LINE.SHIPPED_QTY) as Qty, 
PART.USER_6 as UPC, 
PART.PRODUCT_CODE


FROM VECA.dbo.CUST_ORDER_LINE CUST_ORDER_LINE, VECA.dbo.PART PART, VECA.dbo.SHIPPER SHIPPER, VECA.dbo.SHIPPER_LINE SHIPPER_LINE, veca.dbo.customer_order customer_order

WHERE 
SHIPPER.PACKLIST_ID = SHIPPER_LINE.PACKLIST_ID 
AND SHIPPER_LINE.CUST_ORDER_ID = CUST_ORDER_LINE.CUST_ORDER_ID 
AND CUST_ORDER_LINE.LINE_NO = SHIPPER_LINE.CUST_ORDER_LINE_NO 
AND CUST_ORDER_LINE.PART_ID = PART.ID 
AND cust_order_line.cust_order_id = customer_order.ID
AND ((SHIPPER.SHIPPED_DATE Between {ts '2022-01-01 00:00:00'} And {ts '2022-12-31 00:00:00'}) AND (CUST_ORDER_LINE.PART_ID Is Not Null)) and customer_order.customer_id in ('CORL SPOR','GREA NORT','MD CHAR','bart big','Sylv Spor') and 
part.product_code like ('%FFT%')

group by 
CUST_ORDER_LINE.PART_ID,
PART.DESCRIPTION, 
PART.USER_6,
PART.PRODUCT_CODE

) as QTY) as Ranks


--Chambering 
left join 
    (select 
        USER_DEF_FIELDS.DOCUMENT_ID, 
        USER_DEF_FIELDS.STRING_VAL as chambering
    from VECA.dbo.USER_DEF_FIELDS USER_DEF_FIELDS 
     where USER_DEF_FIELDS.ID = 'UDF-0000022') as Chambering 

on Chambering.DOCUMENT_ID = ranks.part_ID

where SKU_Rank <= 10 and ranks.UPC is not null

