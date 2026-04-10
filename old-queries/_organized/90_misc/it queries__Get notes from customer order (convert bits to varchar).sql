use veca /****** Script for SelectTopNRows command from SSMS  ******/
SELECT TOP (1000)
      cust_order_id,convert(nvarchar(max),convert(varbinary(max),bits))
  FROM [VECA].[dbo].[CUST_order_BINARY] where cust_order_id = 'SO-115288'
