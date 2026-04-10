use veca
/****** Script for SelectTopNRows command from SSMS  ******/
SELECT TOP (1000) [ROWID]
      ,[TYPE]
      ,[OWNER_ID]
      ,[CREATE_DATE]
      ,convert(nvarchar(max),convert(varbinary(max),note))
  FROM [VECA].[dbo].[NOTATION] where owner_id = 'SO-115288'

  select owner_id, n.create_date as note_create_date,
  convert(nvarchar(max),convert(varbinary(max),note)) as note
from  notation n 
