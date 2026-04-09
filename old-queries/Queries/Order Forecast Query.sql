select 
orders.C_GROUP,
orders.PART_ID,
orders.PRODUCT_CODE,
orders.QTY,
ORders.PRICE,
orders.ORDER_DATE,
orders.family,
orders.amount,
case 
when orders.family = 'Ridgeline' then 'Rem700'
when orders.family = 'Mesa' then 'Rem700'
when orders.family = 'MPR' then 'Rem700'
when orders.family = 'BA/ELR' then 'Rem700'
when orders.family = 'TIER1' then 'Rem700'
when orders.family = 'MSR' then 'MSR'
when orders.family = 'RANGER' then 'Rimfire'
else orders.family
end as platform


from(
SELECT
orders.C_GROUP,
orders.PART_ID,
orders.PRODUCT_CODE,
orders.QTY,
ORders.PRICE,
orders.ORDER_DATE,
	case 								
when 	ORDERS.PRODUCT_CODE 	=	'RIDGELINE'	then	'RIDGELINE'
when 	ORDERS.PRODUCT_CODE 	=	'MESA'	then	'MESA'
when 	ORDERS.PRODUCT_CODE 	=	'MPR'	then	'MPR'
when 	ORDERS.PRODUCT_CODE 	=	'MESA-LR'	then	'MESA'
when 	ORDERS.PRODUCT_CODE 	=	'TRAVERSE'	then	'RIDGELINE'
when 	ORDERS.PRODUCT_CODE 	=	'RIDGELINE FFT'	then	'RIDGELINE'
when 	ORDERS.PRODUCT_CODE 	=	'BA TACTICAL'	then	'BA/ELR'
when 	ORDERS.PRODUCT_CODE 	=	'CLASSIC'	then	'RIDGELINE'
when 	ORDERS.PRODUCT_CODE 	=	'CA-15 G2'	then	'MSR'
when 	ORDERS.PRODUCT_CODE 	=	'ELR'	then	'BA/ELR'
when 	ORDERS.PRODUCT_CODE 	=	'CA-10 DMR'	then	'MSR'
when 	ORDERS.PRODUCT_CODE 	=	'RANGER 22'	then	'RANGER'
when 	ORDERS.PRODUCT_CODE 	=	'SUMMIT'	then	'TIER1'
when 	ORDERS.PRODUCT_CODE 	=	'RIDGELINE TI'	then	'RIDGELINE'
when 	ORDERS.PRODUCT_CODE 	=	'MSP'	then	'MSR'
when 	ORDERS.PRODUCT_CODE 	=	'MSR'	then	'MSR'
when 	ORDERS.PRODUCT_CODE 	=	'MPR-STEEL'	then	'MPR'
when 	ORDERS.PRODUCT_CODE 	=	'CA-10 G2'	then	'MSR'
when 	ORDERS.PRODUCT_CODE 	=	'MESA FFT'	then	'MESA'
when 	ORDERS.PRODUCT_CODE 	=	'MESA TI'	then	'MESA'
when 	ORDERS.PRODUCT_CODE 	=	'TFM'	then	'TIER1'
when 	ORDERS.PRODUCT_CODE 	=	'CA-15 VTAC'	then	'MSR'
when 	ORDERS.PRODUCT_CODE 	=	'MPP'	then	'MPR'
when 	ORDERS.PRODUCT_CODE 	=	'RIDGELINE SCOUT'	then	'RIDGELINE'
when 	ORDERS.PRODUCT_CODE 	=	'PCC'	then	'MSR'
when 	ORDERS.PRODUCT_CODE 	=	'CA-15 3G'	then	'MSR'
when 	ORDERS.PRODUCT_CODE 	=	'MPR PRO'	then	'MPR'
	else 'EXCLUDE' end	as FAMILY,

orders.qty * orders.price as Amount	

from(
SELECT  
CUSTOMER_CARMS.CUSTOMER_GROUP as C_GROUP, 
CUST_ORDER_LINE.PART_ID, 
PART.PRODUCT_CODE, 
sum(CUST_ORDER_LINE.ORDER_QTY) as QTY,
cust_order_line.unit_price * ((100-CUST_ORDER_LINE.TRADE_DISC_PERCENT)/100) as PRICE,
CUSTOMER_ORDER.ORDER_DATE

FROM 
VECA.dbo.CUSTOMER_ORDER CUSTOMER_ORDER
inner join VECA.dbo.CUST_ORDER_LINE CUST_ORDER_LINE on CUSTOMER_ORDER.ID = CUST_ORDER_LINE.CUST_ORDER_ID 

inner join 
VECA.dbo.CUSTOMER_CARMS CUSTOMER_CARMS on CUSTOMER_ORDER.CUSTOMER_ID = CUSTOMER_CARMS.ID

inner join 
VECA.dbo.PART PART on CUST_ORDER_LINE.PART_ID = PART.ID

WHERE   ((CUST_ORDER_LINE.PART_ID Is Not Null) AND (CUSTOMER_ORDER.ORDER_DATE>={ts '2010-01-01 00:00:00'})) and customer_order.status <> 'X'
and customer_order.order_date < getdate()+1

group by 
CUSTOMER_CARMS.CUSTOMER_GROUP, 
CUST_ORDER_LINE.PART_ID, 
PART.PRODUCT_CODE,
cust_order_line.unit_price * ((100-CUST_ORDER_LINE.TRADE_DISC_PERCENT)/100),
CUSTOMER_ORDER.ORDER_DATE) as orders) as orders