/****** Script for SelectTopNRows command from SSMS  ******/
use vta
SELECT *
  FROM [VTA].[dbo].[LABOR_TIME_ENTRY] inner join LABOR_TIME_CARD on labor_time_entry.RECORD_IDENTITY = labor_Time_entry.RECORD_IDENTITY where employee_id = 'VANCMIKE' and start_date <'2024-09-10' and end_date > '2024-09-09' order by start_date desc
 

 select * from labor_employee where employee_id = 'VANCMIKE'

 select * from labor_time_card where employee_id = 'VANCMIKE'


 select employee_id, labor_time_entry.RECORD_CREATED, START_DATE, END_DATE, CLOCK_IN_MACHINE_ID from labor_time_entry inner join labor_time_card on labor_time_entry.TIME_CARD_ID = labor_time_card.TIME_CARD_ID where employee_id = 'HERNTAYS' order by labor_time_entry.record_created desc