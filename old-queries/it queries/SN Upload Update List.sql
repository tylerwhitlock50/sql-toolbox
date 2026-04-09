use veca
--SELECT [RowID]
--      ,[SN]
--      ,[uploaded]
--      ,[PRODUCT_CODE]
--  FROM [VECA].[dbo].[_SN_UPLOAD] --where product_code is null

  select * from _SN_UPLOAD left join (
SELECT
TRACE_ID
,ROW_NUMBER() over (PARTITION by TRACE_INV_TRANS.TRACE_ID order by TRACE_INV_TRANS.CREATE_DATE desc) as TRACE_RANK

FROM
SHIPPER
INNER JOIN SHIPPER_LINE
ON SHIPPER.PACKLIST_ID = SHIPPER_LINE.PACKLIST_ID
INNER JOIN TRACE_INV_TRANS
ON SHIPPER_LINE.TRANSACTION_ID=TRACE_INV_TRANS.TRANSACTION_ID
INNER JOIN PART
on TRACE_INV_TRANS.PART_ID = PART.ID
 )t1
 on _SN_UPLOAD.SN = t1.TRACE_ID
 where t1.TRACE_ID is null
 /*
 update _SN_UPLOAD set _SN_UPLOAD.PRODUCT_CODE = t2.PRODUCT_CODE
 from (
 select TRACE_ID, product_code from (
 select 
 trace_inv_trans.*, part.PRODUCT_CODE,
 ROW_NUMBER() over (PARTITION by TRACE_INV_TRANS.TRACE_ID order by TRACE_INV_TRANS.CREATE_DATE desc) as TRACE_RANK
 from trace_inv_Trans 
 inner join _sn_upload on _sn_upload.sn = trace_inv_trans.TRACE_ID 
 inner join part on trace_inv_trans.part_id = part.ID
 where _sn_upload.PRODUCT_CODE is null
 )t1
 where t1.TRACE_RANK =1
 )t2
 where _sn_upload.SN = t2.TRACE_ID

 */