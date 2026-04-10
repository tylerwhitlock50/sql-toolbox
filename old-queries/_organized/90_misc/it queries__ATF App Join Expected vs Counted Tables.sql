select a.*
from [VECA].[dbo].[ATF_SN] as a 
left join [VECA].[dbo].ATF_CNT_TBL as b 
on a.serial_number = b.serial_number 
where a.atf_audit_period_id = 29 and b.serial_number is null;