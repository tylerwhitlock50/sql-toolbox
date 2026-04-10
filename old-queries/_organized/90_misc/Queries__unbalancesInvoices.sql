/*
This Script identifies all the AP entries that are unbalanced and selects the 2105 account (non document controlled) to be adjusted.  The Net Amount is the unbalanced amount.  This was verified at the invoice level.

The Record Identity is the Key Field in the table. 

*/
select
PAYABLES_PAYABLE_DIST.RECORD_IDENTITY,
PAYABLES_PAYABLE_DIST.DEBIT_AMOUNT,
PAYABLES_PAYABLE_DIST.CREDIT_AMOUNT,
PAYABLES_PAYABLE_DIST.ACCOUNT_ID,
errors.INVOICE_ID,
PAYABLES_PAYABLE_DIST.ENTRY_NO,
errors.net_Amount,
errors.DIST_NO
from 
(select
invoice_id,
dist_no,
sum(debit_amount - credit_amount) as net_Amount
from
vfin.dbo.payables_payable_dist
group by 
invoice_id
,dist_no
having sum(debit_amount - credit_amount) <> 0) as errors

left join
vfin.dbo.PAYABLES_PAYABLE_DIST on errors.INVOICE_ID = PAYABLES_PAYABLE_DIST.INVOICE_ID
where PAYABLES_PAYABLE_DIST.DIST_NO = 1 and 
PAYABLES_PAYABLE_DIST.ACCOUNT_ID = '2105'

and PAYABLES_PAYABLE_DIST.RECORD_IDENTITY not in ('KZDXRA6QSHWH', 'KW57I0UHMZP3', 'KODY01INUJEV', 'KVHT3GFOXB31', 'KYDQUBUIPJ2Y', 'KTOQB0MX2MI6', 'KSBLO3KZEKEG', 'KWMTJP0UYZVB')