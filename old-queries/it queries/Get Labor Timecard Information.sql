use vta
SELECT  LABOR_EMPLOYEE.EMPLOYEE_ID,  
LABOR_EMPLOYEE.FIRST_NAME,  
LABOR_EMPLOYEE.LAST_NAME,  
Labor_employee.Employee_type, 
LABOR_TIME_CARD.TIME_CARD_ID,  
LABOR_TIME_CARD.PAY_YEAR,  
LABOR_TIME_CARD.PAY_PERIOD, 
pay_type.pay_type, 
sum (Break_hours.BREAK_Hours) as break_hours, 
sum(convert(decimal(10,4),LABOR_TIME_ENTRY.END_DATE) - convert(decimal(10,4),LABOR_TIME_ENTRY.START_DATE)) as Total_Hours, 
sum(convert(decimal(10,4),LABOR_TIME_ENTRY.END_DATE) - convert(decimal(10,4),LABOR_TIME_ENTRY.START_DATE) - isnull(Break_hours.break_hours,0)) as Paid_Hours, 
DATEADD(week, DATEDIFF(week, 0, labor_time_entry.start_date ), 0) -1 as beg_week, 
case when  sum(convert(decimal(10,4),LABOR_TIME_ENTRY.END_DATE) - 
	convert(decimal(10,4),LABOR_TIME_ENTRY.START_DATE) - 
	isnull(Break_hours.break_hours,0)) *24 > 40  
then 
	40  
else 
	sum(convert(decimal(10,4),LABOR_TIME_ENTRY.END_DATE) - 
	convert(decimal(10,4),LABOR_TIME_ENTRY.START_DATE) - 
	isnull(Break_hours.break_hours,0))*24 end as Reg_Hours, 
case when  sum(convert(decimal(10,4),LABOR_TIME_ENTRY.END_DATE) - 
	convert(decimal(10,4),LABOR_TIME_ENTRY.START_DATE) - 
	isnull(Break_hours.break_hours,0)) *24 > 40  
then 
	sum(convert(decimal(10,4),LABOR_TIME_ENTRY.END_DATE) - 
	convert(decimal(10,4),LABOR_TIME_ENTRY.START_DATE) - 
	isnull(Break_hours.break_hours,0))*24-40  else 0 end 
as OVT_Hours 
FROM  VTA.dbo.LABOR_EMPLOYEE LABOR_EMPLOYEE inner join 
	VTA.dbo.LABOR_TIME_CARD LABOR_TIME_CARD on LABOR_EMPLOYEE.EMPLOYEE_ID = LABOR_TIME_CARD.EMPLOYEE_ID inner join 
	VTA.dbo.LABOR_TIME_ENTRY LABOR_TIME_ENTRY on LABOR_TIME_ENTRY.TIME_CARD_ID = LABOR_TIME_CARD.TIME_CARD_ID  inner join 
	(select labor_employee_pay_rate.employee_id, labor_employee_pay_rate.pay_type from vta.dbo.labor_employee_pay_rate inner join 
	(select labor_employee_pay_rate.employee_id, max (labor_employee_pay_rate.date_effective) as date_effective 
		from vta.dbo.labor_employee_pay_rate 
		group by labor_employee_pay_rate.employee_id) date_effective on date_effective.employee_id = labor_employee_pay_rate.employee_id and date_effective.date_effective = labor_employee_pay_rate.date_effective)  
		as pay_type on pay_type.employee_id = labor_employee.employee_id left outer join  
		(select LABOR_TIME_ENTRY_BREAK.time_card_id, 
			LABOR_TIME_ENTRY_BREAK.line_no, 
			sum (convert(decimal(10,4),labor_time_entry_break.break_end) - convert(decimal(10,4),labor_time_entry_break.break_start)) as Break_Hours 
			from VTA.dbo.LABOR_TIME_ENTRY_BREAK LABOR_TIME_ENTRY_BREAK  
			where LABOR_TIME_ENTRY_BREAK.PAID_FLAG = 0 
			group by LABOR_TIME_ENTRY_BREAK.time_card_id, LABOR_TIME_ENTRY_BREAK.line_no) 
		Break_hours on break_hours.time_card_id = LABOR_TIME_ENTRY.TIME_CARD_ID and break_hours.line_no = LABOR_TIME_ENTRY.LINE_NO 
		WHERE  LABOR_TIME_CARD.PAY_YEAR='2024' AND LABOR_TIME_CARD.PAY_PERIOD='2'
		group by  LABOR_EMPLOYEE.EMPLOYEE_ID,  
			LABOR_EMPLOYEE.FIRST_NAME,  
			LABOR_EMPLOYEE.LAST_NAME,  
			LABOR_TIME_CARD.TIME_CARD_ID,  
			LABOR_TIME_CARD.PAY_YEAR,  
			LABOR_TIME_CARD.PAY_PERIOD, 
			pay_type.pay_type, 
			DATEADD(week, DATEDIFF(week, 0, labor_time_entry.start_date ), 0) -1, 
			Labor_employee.employee_type order by  LABOR_EMPLOYEE.EMPLOYEE_ID