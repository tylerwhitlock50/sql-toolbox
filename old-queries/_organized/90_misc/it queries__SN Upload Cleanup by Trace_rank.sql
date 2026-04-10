use veca
SELECT [SN],
	  count(*)
  FROM [VECA].[dbo].[_SN_UPLOAD] group by SN
  HAVING COUNT(*) >1
/*
 delete from _SN_UPLOAD where RowID in (
select rowID

from (
select RowID, SN,ROW_NUMBER() over (PARTITION by SN order by rowID desc) as TRACE_RANK 
from
 _SN_UPLOAD group by SN, RowID
 ) t1
where t1.TRACE_RANK = 2
)
*/