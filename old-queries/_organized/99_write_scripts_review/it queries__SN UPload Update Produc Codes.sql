---------------------------------------------------------------------------------
use veca

--INSERT INTO 
--_SN_UPLOAD(SN,PRODUCT_CODE)
update _SN_UPLOAD set _SN_UPLOAD.PRODUCT_CODE = t1.PRODUCT_CODE
--select TRACE_ID, PRODUCT_CODE\
from
(
SELECT distinct
TRACE_ID,
ROW_NUMBER() over (PARTITION by TRACE_ID order by TRACE_INV_TRANS.CREATE_DATE desc) as TRACE_RANK

FROM
SHIPPER
INNER JOIN SHIPPER_LINE
ON SHIPPER.PACKLIST_ID = SHIPPER_LINE.PACKLIST_ID
INNER JOIN TRACE_INV_TRANS
ON SHIPPER_LINE.TRANSACTION_ID=TRACE_INV_TRANS.TRANSACTION_ID
INNER JOIN PART
on TRACE_INV_TRANS.PART_ID = PART.ID
) t1
where t1.TRACE_RANK = 1 and t1.TRACE_ID = _SN_UPLOAD.SN

--and not EXISTS (SELECT 1 FROM _SN_UPLOAD where SN = TRACE_ID)

--if we have problems with distinct not covering all duplicates, we can always just use a group by instead
--group by TRACE_ID, PRODUCT_CODE

select * from _SN_UPLOAD where uploaded=0



select SN from _SN_UPLOAD 
/*

---------------------------------------------------------------------------------
--Push the items to mysql
Create Table #MyTempTable (
    serial_number varchar(30)
);
insert into #MyTempTable
select cast(serial_number as varchar(30)) from MYSQL...snvalidation

insert into MYSQL...snvalidation (serial_number)
SELECT SN from _SN_UPLOAD t1 where not exists (select t2.serial_number from #MyTempTable t2 where t2.serial_number = t1.SN) and t1.uploaded=0
drop table #MyTempTable

---------------------------------------------------------------------------------
--Update the items to being uploaded

update _SN_UPLOAD SET uploaded=1 where uploaded=0

---------------------------------------------------------------------------------
*/