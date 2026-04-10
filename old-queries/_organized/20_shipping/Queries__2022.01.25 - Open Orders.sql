select
orders.Identifier,
Orders.ID,
Orders.Line_No,
Orders.Del_Sched_line_no,
Orders.Customer_ID,
Orders.Unit_Price,
Orders.trade_disc_Percent,
Orders.Order_date,
Orders.desired_ship_Date,
Orders.Promise_date,
Orders.Qty,
Orders.Part_ID,
Orders.Description,
Orders.Product_Code,

Orders.Early_Flag,
Orders.Customer_Score,
Orders.Date_Score,
orders.multiplier,
(orders.customer_score * .5 + Orders.Date_Score * .5) * isnull(orders.multiplier,1) as Composite_Score

from(

SELECT
orders.Identifier,
Orders.ID,
Orders.Line_No,
Orders.Del_Sched_line_no,
Orders.Customer_ID,
Orders.Unit_Price,
Orders.trade_disc_Percent,
Orders.Order_date,
Orders.desired_ship_Date,
Orders.Promise_date,
Orders.Qty,
Orders.Part_ID,
Part.Description,
Part.Product_Code,
SC.Customer_Score,

case 					
	when Orders.desired_ship_Date	>	Getdate()	then	'Early Shipment'  end	 as Early_Flag,

case							
when	Orders.desired_ship_Date	>	getdate()	+	1	then	0
when	Orders.desired_ship_Date	<	getdate()	-	150	then	0.1
when	Orders.desired_ship_Date	<	getdate()	-	120	then	0.2
when	Orders.desired_ship_Date	<	getdate()	-	100	then	0.3
when	Orders.desired_ship_Date	<	getdate()	-	90	then	0.4
when	Orders.desired_ship_Date	<	getdate()	-	60	then	0.7
when	Orders.desired_ship_Date	<	getdate()	-	45	then	0.6
when	Orders.desired_ship_Date	<	getdate()	-	30	then	0.5
when	Orders.desired_ship_Date	<	getdate()	-	20	then	1
when	Orders.desired_ship_Date	<	getdate()	-	15	then	1
when	Orders.desired_ship_Date	<	getdate()	-	10	then	1
when	Orders.desired_ship_Date	<	getdate()	-	0	then	1
End as Date_Score,	

case when 	Orders.desired_ship_Date > 	Orders.Order_date + 30 then 2 end as Multiplier	

	

from(
SELECT 
 concat(CUSTOMER_ORDER.ID,'/', CUST_ORDER_LINE.LINE_NO,'/', CUST_LINE_DEL.DEL_SCHED_LINE_NO) as Identifier, 
 CUSTOMER_ORDER.ID,
 CUST_ORDER_LINE.LINE_NO,
 CUST_LINE_DEL.DEL_SCHED_LINE_NO,
 customer_order.Customer_ID,
 cust_order_line.unit_Price,
 cust_order_line.trade_disc_Percent,
 customer_Order.Order_date,
 
 CASE
	when CUST_LINE_DEL.DESIRED_SHIP_DATE is not null then  CUST_LINE_DEL.DESIRED_SHIP_DATE
	when CUST_ORDER_LINE.DESIRED_SHIP_DATE is not null then CUST_ORDER_LINE.DESIRED_SHIP_DATE
	else  CUSTOMER_ORDER.DESIRED_SHIP_DATE end as Desired_Ship_Date,

 CASE
	when CUST_LINE_DEL.User_1 is not null then  CUST_LINE_DEL.User_1
	when CUST_ORDER_LINE.Promise_Date is not null then CUST_ORDER_LINE.Promise_Date
	else  CUSTOMER_ORDER.Promise_DATE end as Promise_Date,	
	
 CUST_ORDER_LINE.PART_ID, 
 
 case 
	when CUST_LINE_DEL.ORDER_QTY is not null then   CUST_LINE_DEL.ORDER_QTY - CUST_LINE_DEL.SHIPPED_QTY
	else CUST_ORDER_LINE.ORDER_QTY - CUST_ORDER_LINE.TOTAL_SHIPPED_QTY end as Qty

 
FROM 
VECA.dbo.CUSTOMER_ORDER CUSTOMER_ORDER left join VECA.dbo.CUST_ORDER_LINE CUST_ORDER_LINE 
	on CUSTOMER_ORDER.ID = CUST_ORDER_LINE.CUST_ORDER_ID

left join VECA.dbo.CUST_LINE_DEL CUST_LINE_DEL 
	on CUST_ORDER_LINE.CUST_ORDER_ID = CUST_LINE_DEL.CUST_ORDER_ID AND CUST_ORDER_LINE.LINE_NO = CUST_LINE_DEL.DEL_SCHED_LINE_NO


WHERE  CUST_ORDER_LINE.PART_ID is not null 
and customer_Order.Status = 'R' 
and cust_Order_Line.line_status = 'A'
and 

 case 
	when CUST_LINE_DEL.ORDER_QTY is not null then   CUST_LINE_DEL.ORDER_QTY - CUST_LINE_DEL.SHIPPED_QTY
	else CUST_ORDER_LINE.ORDER_QTY - CUST_ORDER_LINE.TOTAL_SHIPPED_QTY end > 0) as Orders
	
inner join (

SELECT
SC.Customer_ID,
SC.Default_Terms,
SC.Sales_Channel,
SC.Term_Score,
SC.Order_Score,
SC.Revenue,
SC.Cost,
SC.Restock,
SC.Gross_Profit,
SC.Hold_Score,
SC.Payment_Time_Score,
SC.Wallet_Score,

case when SC.Revenue < 0 then .03 else
isnull(SC.Customer_Score,0)  end as Customer_Score

from(
SELECT
stats.Customer_ID,
stats.Default_Terms,
Stats.Sales_Channel,
cast(Stats.Term_Score as decimal) /100 as Term_Score,
isnull(Stats.Order_Score,0) as Order_Score,
isnull(stats.Revenue,0) as Revenue,
isnull(stats.Cost, 0) as Cost,
isnull(stats.restock,0) as restock,
isnull(stats.Gross_Profit,0) as Gross_Profit,
isnull(stats.Hold_Score,0) as Hold_Score,
isnull(Stats.Payment_Time_Score,0) as Payment_Time_Score,

case  -- Shown wallet Scores
when stats.customer_ID = 'Bass Pro' then 1.2
when stats.customer_ID = 'Bill Hick' then .75
when stats.customer_ID = 'Davids' then 1
when stats.customer_ID = 'EURO OPTI' then .75
when stats.customer_ID = 'LIPSEYS' then 1.2
when stats.customer_ID = 'SCHEELS' then 1.2
when stats.customer_ID = 'SPOR WARE' then 1.2
when stats.customer_ID = 'RSR GROU' then 1.2
else 0 end as Wallet_Score,

(isnull(
isnull(stats.order_score, 0) * .3 + 
isnull(stats.Gross_Profit,0) * .2 +
isnull(stats.hold_score, 0) *.05 +
isnull(cast(Stats.Term_Score as decimal) /100,0) * .1 +
isnull(Stats.Payment_Time_Score * .1, 0) +

isnull(isnull(-stats.restock/
CASE WHEN (stats.Revenue - stats.restock) = 0 THEN 1 ELSE (stats.Revenue - stats.restock) END
,0) * .1,0) +

isnull(
case -- Wallet Score Calculation Should match the shown wallet score
when stats.customer_ID = 'Bass Pro' then 1.2
when stats.customer_ID = 'Bill Hick' then .75
when stats.customer_ID = 'Davids' then 1
when stats.customer_ID = 'EURO OPTI' then .75
when stats.customer_ID = 'LIPSEYS' then 1.2
when stats.customer_ID = 'SCHEELS' then 1.2
when stats.customer_ID = 'SPOR WARE' then 1.2
when stats.customer_ID = 'RSR GROU' then 1.2
else 0 end,0) *.15,0) -- Wallet Score to be calculated
 ) as Customer_Score,

isnull(stats.Revenue,0) - isnull(stats.Cost,0) as Profit


from(

SELECT
--Customer Table (import the basic customer information)
customer.id as Customer_ID,
customer.def_Terms_ID as Default_Terms,
ISNULL(customer.Discount_Code, 'OTHER') as Sales_Channel,

--Calculate The Terms scores (This will be divided by 100 in the next step)
case	customer.def_Terms_ID 		
When	'1ST'	then	0
When	'2%10 N30'	then	95
When	'2%15 N30'	then	85
When	'2%30 1%60 N90'	then	60
When	'2%30 N60'	then	70
When	'2%30 N90'	then	65
When	'2%60 N61'	then	50
When	'4%15 NET30'	then	65
When	'4%20 N90'	then	60
When	'10TH'	then	40
When	'COD'	then	20
When	'CRCARD_FREE SHI'	then	20
When	'CREDIT_CARD'	then	20
When	'DUR'	then	20
When	'NET 365'	then	10
When	'NET30'	then	60
When	'NET30 FREE SHIP'	then	60
When	'NET45'	then	55
When	'NET45 FREE SHIP'	then	55
When	'NET60'	then	55
When	'NET60 FREE SHIP'	then	55
When	'NET90'	then	40
When	'NET120'	then	30
When	'NET120 FREE SHI'	then	20
When	'NET365'	then	10
When	'PREPAY'	then	50
Else	0 end as Term_Score,

--Orders from the last 365 days grouped by size 
case
when isnull(orders.Rolling_Year_Total_Ordered, 0) > 1000000 then 1
when isnull(orders.Rolling_Year_Total_Ordered, 0) > 750000 then .9
when isnull(orders.Rolling_Year_Total_Ordered, 0) > 500000 then .8
when isnull(orders.Rolling_Year_Total_Ordered, 0) > 300000 then .75
when isnull(orders.Rolling_Year_Total_Ordered, 0) > 100000 then .5
when isnull(orders.Rolling_Year_Total_Ordered, 0) > 25000 then .25
when isnull(orders.Rolling_Year_Total_Ordered, 0) < 25000 then .1
else .01 
end as Order_Score,

--Bring in the average days to pay an invoice
(100-isnull(pay.resolution_days, 45))/100 as Payment_Time_Score,

--Bring In Hold Items
case when isnull(hold.hold_items,0) > 2 then 0 else 1 end as Hold_Score,

--Bring in Profit Measures
gp.Revenue,
gp.cost,
gp.Gross_Profit,
gp.restock


FROM
VECA.dbo.Customer Customer

left join (
--Order File and Shipment amount Represents all orders from the last year.
select
sum(CUSTOMER_ORDER.TOTAL_AMT_ORDERED) as Rolling_Year_Total_Ordered,
customer_order.Customer_ID


from
VECA.dbo.CUSTOMER_ORDER CUSTOMER_ORDER

where
Customer_order.Order_Date > getdate()-365
and customer_order.status in ('C','R')

Group by 
customer_order.Customer_ID) as Orders on orders.Customer_iD = Customer.ID

left join (

--Average Days to Pay
select
avg(
CONVERT(float,RECEIVABLES_RECEIVABLE.ZERO_DATE) - CONVERT(float,RECEIVABLES_RECEIVABLE.INVOICE_DATE)) as resolution_days,
RECEIVABLES_RECEIVABLE.CUSTOMER_ID

FROM Vfin.dbo.RECEIVABLES_RECEIVABLE RECEIVABLES_RECEIVABLE

where RECEIVABLES_RECEIVABLE.INVOICE_STATUS = 'Closed' and RECEIVABLES_RECEIVABLE.INVOICE_DATE > getdate()-365


group by 
RECEIVABLES_RECEIVABLE.CUSTOMER_ID) as Pay on pay.Customer_ID = Customer.ID

left join (
--Items on Hold
select
CUSTOMER_ORDER.CUSTOMER_ID,
count(CUSTOMER_ORDER.ID) as Hold_Items

from VECA.dbo.CUSTOMER_ORDER CUSTOMER_ORDER

where CUSTOMER_ORDER.STATUS = 'H'

group by 
customer_order.Customer_ID) as Hold on Hold.Customer_ID = Customer.ID

left join(

-- Gross Profit
SELECT
nullif( (gross_profit.revenue - gross_profit.Cost)/gross_profit.revenue,0) as Gross_Profit,
gross_profit.Customer_ID,
gross_profit.revenue,
gross_profit.cost,
gross_profit.Restock

from(
select
sum(SHIPPER_LINE.unit_price * shipper_line.Shipped_QTY * ((100 - shipper_line.Trade_Disc_Percent)/100)) as Revenue,
sum(CASE
inventory_trans.type when 'O' then inventory_trans.act_material_cost + inventory_trans.act_labor_cost + inventory_trans.act_service_cost else -(inventory_trans.act_material_cost + inventory_trans.act_labor_cost + inventory_trans.act_service_cost) end) as Cost,

sum(CASE
when shipper_line.shipped_qty < 0 then 
(SHIPPER_LINE.unit_price * shipper_line.Shipped_QTY * ((100 - shipper_line.Trade_Disc_Percent)/100)) else 0 end) as Restock,


CUSTOMER_ORDER.CUSTOMER_ID



FROM
veca.dbo.shipper shipper inner join veca.dbo.shipper_line on shipper.packlist_id = shipper_line.packlist_id
inner join veca.dbo.inventory_trans on inventory_trans.transaction_id = shipper_line.transaction_id
inner join veca.dbo.customer_Order on Shipper.cust_order_id = Customer_Order.ID

WHERE
shipper.shipped_date > getdate()-365 and SHIPPER_LINE.unit_price * shipper_line.Shipped_QTY * ((100 - shipper_line.Trade_Disc_Percent)/100) <> 0

group by 
CUSTOMER_ORDER.CUSTOMER_ID) as Gross_Profit

where gross_profit.revenue <> 0) as GP on GP.Customer_ID = Customer.ID
) as Stats

) as SC ) as SC

on sc.customer_ID = orders.customer_ID

inner join veca.dbo.part part on part.ID = Orders.Part_ID) as Orders