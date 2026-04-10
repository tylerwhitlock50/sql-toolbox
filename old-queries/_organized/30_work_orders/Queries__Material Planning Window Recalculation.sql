--Material Planning Window Recreation

--updated 11/19/2021


/* This query pulls information from the following Sources
	customer orders
	purchase orders
	planned material requirements
	planned orders
	part on hand reports
	Actual requirements of released work orders
	
The identifier field represents the applicable related document / line number / delivery schedule line NUMBER
the transaction date is the date MRP is using to calculate the date of the transaction.  This query does not account for past due transactions
MRP takes these transactions and moves them to the current date.
The kind represents the document type that the line relates to.

Part id is the anticipated part to be transacted.
Qty represents the in + / out - of each anticipated part. */


SELECT 
concat(PURCHASE_ORDER.ID ,'/', PURC_ORDER_LINE.LINE_NO , '/' , PURC_LINE_DEL.DEL_SCHED_LINE_NO) as Identifier, 
case 
	when PURC_LINE_DEL.DESIRED_RECV_DATE is not null then PURC_LINE_DEL.DESIRED_RECV_DATE
	when PURC_ORDER_LINE.DESIRED_RECV_DATE is not null then PURC_ORDER_LINE.DESIRED_RECV_DATE
	else PURCHASE_ORDER.DESIRED_RECV_DATE end as Transation_date,

'Purchase Order' as Kind,	
purc_order_line.part_id as Part_ID,

case
	WHEN PURC_LINE_DEL.ORDER_QTY is not null then PURC_LINE_DEL.ORDER_QTY - PURC_LINE_DEL.RECEIVED_QTY

	else PURC_ORDER_LINE.ORDER_QTY - PURC_ORDER_LINE.TOTAL_RECEIVED_QTY end as Qty

FROM 
VECA.dbo.PURCHASE_ORDER PURCHASE_ORDER left join VECA.dbo.PURC_ORDER_LINE PURC_ORDER_LINE
	on PURC_ORDER_LINE.PURC_ORDER_ID = PURCHASE_ORDER.ID

left join VECA.dbo.PURC_LINE_DEL PURC_LINE_DEL 
	on PURC_ORDER_LINE.PURC_ORDER_ID = PURC_LINE_DEL.PURC_ORDER_ID AND PURC_ORDER_LINE.LINE_NO = PURC_LINE_DEL.PURC_ORDER_LINE_NO
	
where PURC_ORDER_LINE.PART_ID is not null  and purchase_order.status = 'R' and PURC_ORDER_LINE.LINE_STATUS = 'A'

union all 

SELECT 
CONCAT(PLANNED_MATL_REQ.PARENT_PART_ID,'/', PLANNED_MATL_REQ.PARENT_SEQ_NO,'/', PLANNED_MATL_REQ.REQ_NO) as Identifier,
PLANNED_MATL_REQ.REQUIRED_DATE, 
'Planned_Matl_Req' as Kind,
PLANNED_MATL_REQ.REQUIRED_PART_ID, 
-PLANNED_MATL_REQ.REQUIRED_QTY as Qty
FROM VECA.dbo.PLANNED_MATL_REQ PLANNED_MATL_REQ

union all 

SELECT 
'Planned Order' as Identifier,
PLANNED_ORDER.WANT_DATE, 
'Planned Order' as Kind,
PLANNED_ORDER.PART_ID, 
PLANNED_ORDER.ORDER_QTY
FROM VECA.dbo.PLANNED_ORDER PLANNED_ORDER

union ALL

SELECT 
concat(REQUIREMENT.WORKORDER_BASE_ID,'/', REQUIREMENT.OPERATION_SEQ_NO,'/', REQUIREMENT.PIECE_NO) as Identifier, 
REQUIREMENT.REQUIRED_DATE,
'Work_orders' as kind,
 REQUIREMENT.PART_ID, 
 -(REQUIREMENT.CALC_QTY- REQUIREMENT.ISSUED_QTY) as Qty
FROM VECA.dbo.REQUIREMENT REQUIREMENT
WHERE (REQUIREMENT.WORKORDER_TYPE='W') AND (REQUIREMENT.STATUS='R') AND (REQUIREMENT.PART_ID Is Not Null)

union all
SELECT 
'Beginning Balance' as Identifier,
getdate() as 'Date',
'Beginning Balance' as Kind,
PART.ID, 
PART.QTY_ON_HAND
FROM VECA.dbo.PART PART

union all

 SELECT 
 concat(CUSTOMER_ORDER.ID,'/', CUST_ORDER_LINE.LINE_NO,'/', CUST_LINE_DEL.DEL_SCHED_LINE_NO) as Identifier, 
 
 CASE
	when CUST_LINE_DEL.DESIRED_SHIP_DATE is not null then  CUST_LINE_DEL.DESIRED_SHIP_DATE
	when CUST_ORDER_LINE.DESIRED_SHIP_DATE is not null then CUST_ORDER_LINE.DESIRED_SHIP_DATE
	else  CUSTOMER_ORDER.DESIRED_SHIP_DATE end as Transaction_date,

'Customer Orders' as Kind,
 CUST_ORDER_LINE.PART_ID, 
 
case 
	when CUST_LINE_DEL.ORDER_QTY is not null then   CUST_LINE_DEL.ORDER_QTY - CUST_LINE_DEL.SHIPPED_QTY
	else CUST_ORDER_LINE.ORDER_QTY - CUST_ORDER_LINE.TOTAL_SHIPPED_QTY end *-1as Qty

 
FROM 
VECA.dbo.CUSTOMER_ORDER CUSTOMER_ORDER left join VECA.dbo.CUST_ORDER_LINE CUST_ORDER_LINE 
	on CUSTOMER_ORDER.ID = CUST_ORDER_LINE.CUST_ORDER_ID

left join VECA.dbo.CUST_LINE_DEL CUST_LINE_DEL 
	on CUST_ORDER_LINE.CUST_ORDER_ID = CUST_LINE_DEL.CUST_ORDER_ID AND CUST_ORDER_LINE.LINE_NO = CUST_LINE_DEL.DEL_SCHED_LINE_NO

WHERE  CUST_ORDER_LINE.PART_ID is not null and customer_order.status = 'R' and cust_order_line.LINE_STATUS = 'A'

union ALL

SELECT 
WORK_ORDER.BASE_ID, 
WORK_ORDER.DESIRED_WANT_DATE,
'Manufacturing' as kind,
WORK_ORDER.PART_ID, 
WORK_ORDER.DESIRED_QTY - WORK_ORDER.RECEIVED_QTY AS QTY 
 

FROM VECA.dbo.WORK_ORDER WORK_ORDER
WHERE (WORK_ORDER.TYPE='W') AND (WORK_ORDER.STATUS In ('F','R')) and work_order.part_ID is not null


union all

select
'Master Schedule' as Identifier,
master_schedule.want_date,
'Master Schedule' as Kind,
master_Schedule.part_id,
-master_schedule.order_Qty

from veca.dbo.master_schedule master_schedule


























