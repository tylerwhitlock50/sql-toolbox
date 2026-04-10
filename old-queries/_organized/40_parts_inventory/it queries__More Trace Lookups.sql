
use veca/****** Script for SelectTopNRows command from SSMS  ******/
SELECT  [ROWID]
      ,[PART_ID]
      ,[TRACE_ID]
      ,[TRANSACTION_ID]
      ,[QTY]
      ,[CREATE_DATE]
      ,[COSTED_QTY]
  FROM [VECA].[dbo].[TRACE_INV_TRANS] 
  where TRACE_ID = 'CV27000'
  /*
  SELECT
      [TRACE_ID]
	, sum(qty) as qty
  FROM [VECA].[dbo].[TRACE_INV_TRANS]
  where TRACE_ID = 'CV27000'
  group by TRACE_ID 
  
  */
  select * from (
  SELECT
      [TRACE_ID]
	, sum(qty) as qty
  FROM [VECA].[dbo].[TRACE_INV_TRANS]
  group by TRACE_ID )as t1 where qty > 0

    SELECT
     *
  FROM [VECA].[dbo].[TRACE_INV_TRANS]



select distinct COMMODITY_CODE from part


select PART_ID, trace.id from trace inner join part on trace.PART_ID = part.ID where IN_QTY > OUT_QTY and (part.COMMODITY_CODE like '%GUN%'  or part.COMMODITY_CODE like '%action%')
