select * from receivable where INVOICE_ID = 'INV-164520'

select * from receivable_line where INVOICE_ID = 'INV-164520'

select * from receivable where STATUS 

select * from cust_order_line where GL_REVENUE_ACCT_ID = '4400'

update cust_order_line set GL_REVENUE_ACCT_ID = '4400-Other' where GL_REVENUE_ACCT_ID = '4400'

select * from receivable_line where GL_ACCOUNT_ID = '1436'

update receivable_line set GL_ACCOUNT_ID = '4400-Other' where GL_ACCOUNT_ID = '4400'

select * from customer where ID = 'BILL WILL'

update customer set ACTIVE_FLAG = 'N' where ID in (
'BILL WILL',
'CABELAS',
'STEV CART',
'FLOR GUN',
'SPOR FORT')