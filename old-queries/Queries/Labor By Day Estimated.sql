select *

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
 
FROM [dbo].[LABOR_EMPLOYEE_PAY_RATE] [LABOR_EMPLOYEE_PAY_RATE]) as rates)) as rates

on rates.employee_id_rate = hours.employee_id
where hours.start_date > rates.rate_effective and hours.start_date < rates.Rate_End_date
and hours.start_date > department.date_effective and hours.start_date < department.end_Date
and hours.start_date < getdate()-1