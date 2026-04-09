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
errors.net_Amount
from 
(select
invoice_id,
dist_no,
sum(debit_amount - credit_amount) as net_Amount
from
vfin.dbo.payables_payable_dist
group by 
invoice_id,
dist_no
having sum(debit_amount - credit_amount) <> 0) as errors

left join
vfin.dbo.PAYABLES_PAYABLE_DIST on errors.INVOICE_ID = PAYABLES_PAYABLE_DIST.INVOICE_ID
where PAYABLES_PAYABLE_DIST.DIST_NO = 1 and PAYABLES_PAYABLE_DIST.ACCOUNT_ID = '2105'


/*
This Script updates the identified entries and replaces the debit amount with the corrected value from above. We need to update the listing to match the items in the list above
*/
update vfin.dbo.payables_payable_dist set debit_amount = 552 where record_identity = 'I3CI7DAG332R';
update vfin.dbo.payables_payable_dist set debit_amount = 600 where record_identity = 'XRLLXXJEFX4N';
update vfin.dbo.payables_payable_dist set debit_amount = 552 where record_identity = 'WV95MSZLF2H9';
update vfin.dbo.payables_payable_dist set debit_amount = 558 where record_identity = 'U80220I53LMJ';
update vfin.dbo.payables_payable_dist set debit_amount = 600 where record_identity = 'UQ9O1DVXGG8Z';
update vfin.dbo.payables_payable_dist set debit_amount = 600 where record_identity = 'CNWTW3ZFD9FH';
update vfin.dbo.payables_payable_dist set debit_amount = 600 where record_identity = 'WODP86WMIQQV';
update vfin.dbo.payables_payable_dist set debit_amount = 976 where record_identity = 'ULLFOS2WP5MO';
update vfin.dbo.payables_payable_dist set debit_amount = 600 where record_identity = 'ZTWFTZPL3NGX';
update vfin.dbo.payables_payable_dist set debit_amount = 888 where record_identity = 'VY5ZDCM8DUY0';
update vfin.dbo.payables_payable_dist set debit_amount = 594 where record_identity = 'VVQNBIGG3DQK';
update vfin.dbo.payables_payable_dist set debit_amount = 486 where record_identity = '7RCUMJ63MSOS';
update vfin.dbo.payables_payable_dist set debit_amount = 492 where record_identity = 'VD2YAOVWQ1VY';
update vfin.dbo.payables_payable_dist set debit_amount = 600 where record_identity = 'HOTRW2VXPJPY';
update vfin.dbo.payables_payable_dist set debit_amount = 720 where record_identity = 'MNCKKAD0ROP2';
update vfin.dbo.payables_payable_dist set debit_amount = 714 where record_identity = 'TV9RZ4PFCG50';
update vfin.dbo.payables_payable_dist set debit_amount = 588 where record_identity = 'I2GNU9OTL081';
update vfin.dbo.payables_payable_dist set debit_amount = 600 where record_identity = 'GX017VSWV5EJ';
update vfin.dbo.payables_payable_dist set debit_amount = 600 where record_identity = 'TUU29NH4QTB2';
update vfin.dbo.payables_payable_dist set debit_amount = 292.8 where record_identity = 'VOY3UQLZD83K';
update vfin.dbo.payables_payable_dist set debit_amount = 600 where record_identity = 'ZTIRU6IJ7K67';
update vfin.dbo.payables_payable_dist set debit_amount = 600 where record_identity = '7T9TAYMIZVYL';
update vfin.dbo.payables_payable_dist set debit_amount = 570 where record_identity = 'U92ENNVTXFKS';
update vfin.dbo.payables_payable_dist set debit_amount = 546 where record_identity = 'U6XM7VLCXO4F';
update vfin.dbo.payables_payable_dist set debit_amount = 600 where record_identity = 'O78S89AOQJYI';
update vfin.dbo.payables_payable_dist set debit_amount = 516 where record_identity = 'WRD7TK5LABGQ';
update vfin.dbo.payables_payable_dist set debit_amount = 582 where record_identity = 'WW4LFZ7OKUN6';
update vfin.dbo.payables_payable_dist set debit_amount = 660 where record_identity = 'MMVX2X8HZJ7L';


/*
This Script find the dates and entries where the payables items were incorrectly debited to the 2105 account.
*/
select
ledger_account_balance.record_identity,
ledger_account_balance.debit_amount,
ledger_account_balance.PAYB_DEBIT_AMOUNT,
bad_records.net_gl_amount

from vfin.dbo.ledger_account_balance inner join (

select
ledger_account_balance.posting_date,
sum((ledger_account_balance.debit_amount - ledger_account_balance.credit_amount)) as net_gl_amount
from vfin.dbo.ledger_account_balance ledger_account_balance inner join vfin.dbo.ledger_account on ledger_account.account_id = ledger_account_balance.account_id
where ledger_account.posting_level = 1 and ledger_account_balance.posting_date > '12/31/2020'
group by 
ledger_account_balance.posting_date
having 
sum((ledger_account_balance.debit_amount - ledger_account_balance.credit_amount)) <> 0) as bad_records on bad_records.posting_date = ledger_account_balance.posting_date

where ledger_account_balance.account_id = '2105'


/*
This Script Adjusted the Payables account balance table for the bad entries
*/
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 34260 , PAYB_DEBIT_AMOUNT = 34260 where record_identity = 'HIJ2U01AWZLD';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 133215.86 , PAYB_DEBIT_AMOUNT = 133215.86 where record_identity = 'E73QT1U61HDX';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 86442.73 , PAYB_DEBIT_AMOUNT = 86442.73 where record_identity = 'T39AOZOQCFAW';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 102505.17 , PAYB_DEBIT_AMOUNT = 102505.17 where record_identity = 'QOTN80VIZ9UP';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 230883.25 , PAYB_DEBIT_AMOUNT = 230883.25 where record_identity = 'TR11CWRSJD6N';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 85685.45 , PAYB_DEBIT_AMOUNT = 85685.45 where record_identity = 'R9KS4FYIRYDS';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 287144.31 , PAYB_DEBIT_AMOUNT = 287144.31 where record_identity = 'XPX9FUXAKKNL';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 67628.78 , PAYB_DEBIT_AMOUNT = 67628.78 where record_identity = 'WODLYJQEI5AM';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 63593.83 , PAYB_DEBIT_AMOUNT = 63593.83 where record_identity = '7A9TB3FCHL2T';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 26902.35 , PAYB_DEBIT_AMOUNT = 26902.35 where record_identity = 'MITKMB29JI97';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 31736.38 , PAYB_DEBIT_AMOUNT = 31736.38 where record_identity = 'HOTOV2KFWR5P';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 170368.47 , PAYB_DEBIT_AMOUNT = 170368.47 where record_identity = 'CKEBZMQ67RM1';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 181930.89 , PAYB_DEBIT_AMOUNT = 181930.89 where record_identity = 'TYC9CT23H1Y3';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 214696.52 , PAYB_DEBIT_AMOUNT = 214696.52 where record_identity = 'UDKFA9GE32D9';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 41821.62 , PAYB_DEBIT_AMOUNT = 41821.62 where record_identity = 'TTQ759F46PAF';
update vfin.dbo.ledger_account_balance set DEBIT_AMOUNT = 252265.27 , PAYB_DEBIT_AMOUNT = 252265.27 where record_identity = 'L2I9NIOX5AA1';

/*
This Script script updates the $8 error created in 2018 for a receivable that posted incorrectly. 
There was no need to modify parent accounts
*/
update vfin.dbo.ledger_account_balance set credit_amount = 21617.03, RECV_CREDIT_AMOUNT = 110.96 where RECORD_IDENTITY = '679P5V0ZIAKG'

/*
This Script identifies all the AR entries that are unbalanced and selects the 1200 account (document controlled) to be adjusted.  The Net Amount is the unbalanced amount.  This was verified at the invoice level.

The Record Identity is the Key Field in the table. There were no Entries to be corrected, however the ledger account table was never fixed

*/
select
receivables_receivable_dist.RECORD_IDENTITY,
receivables_receivable_dist.DEBIT_AMOUNT,
receivables_receivable_dist.CREDIT_AMOUNT,
receivables_receivable_dist.ACCOUNT_ID,
errors.INVOICE_ID,
receivables_receivable_dist.ENTRY_NO,
errors.net_Amount
from 
(select
invoice_id,
dist_no,
sum(debit_amount - credit_amount) as net_Amount
from
vfin.dbo.receivables_receivable_dist
group by 
invoice_id,
dist_no
having sum(debit_amount - credit_amount) <> 0) as errors

left join
vfin.dbo.receivables_receivable_dist on errors.INVOICE_ID = receivables_receivable_dist.INVOICE_ID
where receivables_receivable_dist.DIST_NO = 2 and receivables_receivable_dist.account_ID = '1200'






