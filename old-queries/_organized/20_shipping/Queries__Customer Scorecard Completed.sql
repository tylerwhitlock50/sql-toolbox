SELECT
stats.Customer_ID,
stats.Default_Terms,
Stats.Sales_Channel,
cast(Stats.Term_Score as decimal) /100 as Term_Score,
Stats.Order_Score,
stats.Revenue,
stats.Cost,
stats.restock,
isnull(stats.Gross_Profit,0) as Gross_Profit,
stats.Hold_Score,
Stats.Payment_Time_Score,

(stats.order_score * .25 +
isnull(stats.Gross_Profit,0) * .25 +
stats.hold_score *.1 +
cast(Stats.Term_Score as decimal) /100 * .25 +
Stats.Payment_Time_Score * .15) as Customer_Score,

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
when isnull(orders.Rolling_Year_Total_Ordered, 0) < 25000 then .01
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

where gross_profit.revenue <> 0) as GP on GP.Customer_ID = Customer.ID) as Stats
