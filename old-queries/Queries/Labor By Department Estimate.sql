
select 
cast(hours.time_card_id as nvarchar(15)) as TRANSACTION_ID, -- Transaction_ID,
hours.start_date as TRANSACTION_DATE,
hours.employee_id as RESOURCE_EMPLOYEE, --Resource
hours.Reg_Hours  as CLOCKED_HOURS,
hours.Reg_Hours  as IMPLIED_HOURS,


department.DEPARTMENT_ID,
rates.PAY_RATE,

rates.pay_rate * hours.reg_hours as CLOCKED_COST,
rates.pay_rate * hours.reg_hours as Implied_cost,

0 as COMPLETED_QTY,
0 as DEVIATED_QTY,
'' as PART_ID,
'' as PRODUCT_CODE,
'' as COMMODITY_CODE,
'' as TYSON_CATEGORY,
'VTA' as SOURCE

from  
(select

labor_time_entry.time_card_id,
labor_time_entry.start_date,
labor_time_card.employee_id,

case 
when  
sum(convert(decimal(10,4),LABOR_TIME_ENTRY.END_DATE) - convert(decimal(10,4),LABOR_TIME_ENTRY.START_DATE)) *24 > 12  then 12  
else sum(convert(decimal(10,4),LABOR_TIME_ENTRY.END_DATE) - convert(decimal(10,4),LABOR_TIME_ENTRY.START_DATE))*24 end as Reg_Hours

from
vta.dbo.labor_time_entry labor_time_entry inner join vta.dbo.labor_time_card labor_time_card
	on labor_time_card.time_card_id = labor_time_entry.time_card_id

group by 
labor_time_entry.time_card_id,
labor_time_entry.start_date,
labor_time_card.employee_id) as hours

inner join
((SELECT 
      [EMPLOYEE_ID] as employee_id_department
      ,[DATE_EFFECTIVE]
	  , lag([DATE_EFFECTIVE],1,getdate()) over (PARTITION by Employee_ID order by DATE_EFFECTIVE desc) as End_Date
	  , rank()
		over (PARTITION by Employee_ID order by DATE_EFFECTIVE asc) as OrderRank
      ,[DEPARTMENT_ID]

  FROM [VTA].[dbo].[LABOR_EMPLOYEE_DEPARTMENT])) as department
  
  on department.employee_id_department = hours.employee_id

  
inner join
  ((select 
rates.PAY_RATE,
rates.employee_id as employee_id_rate,
rates.date_effective as rate_effective,
lag(rates.date_effective,1,getdate()) 
	over (PARTITION by rates.employee_id order by rates.date_effective desc) as Rate_End_date

from(
SELECT 
  case 
	when LABOR_EMPLOYEE_PAY_RATE.BASE_PAY_RATE_PER = 'HOUR' then LABOR_EMPLOYEE_PAY_RATE.BASE_PAY_RATE
	when LABOR_EMPLOYEE_PAY_RATE.BASE_PAY_RATE_PER  = 'YEAR' then LABOR_EMPLOYEE_PAY_RATE.BASE_PAY_RATE/2080 
		end as PAY_RATE,
  
  LABOR_EMPLOYEE_PAY_RATE.EMPLOYEE_ID,
  LABOR_EMPLOYEE_PAY_RATE.DATE_EFFECTIVE
 
FROM vta.[dbo].[LABOR_EMPLOYEE_PAY_RATE] [LABOR_EMPLOYEE_PAY_RATE]) as rates)) as rates

on rates.employee_id_rate = hours.employee_id
where hours.start_date > rates.rate_effective and hours.start_date < rates.Rate_End_date
and hours.start_date > department.date_effective and hours.start_date < department.end_Date
and hours.start_date < getdate()-1 and rates.PAY_RATE is not null

union all


SELECT 
concat(OPERATION.WORKORDER_BASE_ID,'/',
OPERATION.WORKORDER_LOT_ID, '/',
OPERATION.WORKORDER_SPLIT_ID, '/',
OPERATION.WORKORDER_SUB_ID, '/',
OPERATION.SEQUENCE_NO) as WORKORDER_ID, --Transaction ID

OPERATION.CLOSE_DATE, --Transaction Date

OPERATION.RESOURCE_ID, -- Employee ID

OPERATION.ACT_SETUP_HRS + OPERATION.ACT_RUN_HRS as  CLOCKED_HOURS, -- Clocked hours
OPERATION.SETUP_HRS + OPERATION.RUN_HRS as IMPLIED_HOURS, --Implied Hours 

SHOP_RESOURCE.DEPARTMENT_ID, --Department_ID

OPERATION.RUN_COST_PER_HR as Pay_Rate, 

OPERATION.ACT_ATL_LAB_COST as CLOCKED_COST, 
OPERATION.EST_ATL_LAB_COST - OPERATION.REM_ATL_LAB_COST as IMPLIED_COST,


OPERATION.COMPLETED_QTY,
OPERATION.DEVIATED_QTY, 
WORK_ORDER.PART_ID, 
PART.PRODUCT_CODE, 
PART.COMMODITY_CODE, 
PART.USER_2 as TYSON_CAT,
'VECA' as SOURCE

FROM 
VECA.dbo.OPERATION OPERATION, 
VECA.dbo.PART PART, 
VECA.dbo.SHOP_RESOURCE SHOP_RESOURCE, 
VECA.dbo.WORK_ORDER WORK_ORDER

WHERE OPERATION.RESOURCE_ID = SHOP_RESOURCE.ID AND OPERATION.WORKORDER_BASE_ID = WORK_ORDER.BASE_ID AND WORK_ORDER.LOT_ID = OPERATION.WORKORDER_LOT_ID AND WORK_ORDER.SPLIT_ID = OPERATION.WORKORDER_SPLIT_ID AND WORK_ORDER.SUB_ID = OPERATION.WORKORDER_SUB_ID AND WORK_ORDER.TYPE = OPERATION.WORKORDER_TYPE AND WORK_ORDER.PART_ID = PART.ID AND ((OPERATION.WORKORDER_TYPE='W'))

