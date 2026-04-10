select a.serial_number from ATF_SN as a left join ATF_CNT_TBL as b on a.serial_number = b.serial_number where a.atf_audit_period_id = 29 and b.serial_number is null;


select serial_number into #duplicatetemp from [VECA].[dbo].[ATF_CNT_TBL] where [ATF_AUDIT_PERIOD_ID] = 29 group by [serial_number] having count(*) > 1;
select * from [VECA].[dbo].[ATF_CNT_TBL] where serial_number in (select * from #duplicatetemp) and ATF_AUDIT_PERIOD_ID = 31 order by serial_number; drop table #duplicatetemp

select * from ATF_AUDIT_PERIOD

select top 1 * from inventory_trans order by create_date desc

delete w from ATF_SN w inner join ATF_AUDIT_PERIOD on w.ATF_AUDIT_PERIOD_ID = ATF_AUDIT_PERIOD.ID where ATF_AUDIT_PERIOD.IS_ACTIVE = 0
delete from ATF_AUDIT_PERIOD where is_active = 0
use VECA select ID, DESCRIPTION, case when id = 'c2' or id = 'rma' or id = 'engineering' or id = 'marketing' then 'ASSEMBLED GUN' when id = 'C3' or id = 'p-assy' or id = 'p-sassy' or id = 'p-pnt1' or id = 'p-pnt2' then 'SUBASSEMBLY' else 'RCVR/FRM/LWR' end as STATE from LOCATION where warehouse_id in ('main','shipping','fulfillment') and description not like '%***%' order by state asc