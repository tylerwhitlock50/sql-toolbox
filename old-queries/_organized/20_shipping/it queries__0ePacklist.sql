use veca

select * from (SELECT s.status, s.shipped_date, case when c.customer_po_ref like '%web%order%' then 'Web' else 'Std' end as type, count(s.packlist_id) as rCnt from shipper s inner join customer_order c on s.cust_order_id=c.id where s.invoice_id is null group by s.status, case when c.customer_po_ref like '%web%order%' then 'Web' else 'Std' end, s.shipped_date) as SourceTable
	PIVOT(AVG(rCnt) for status in ([A],[1],[2],[3],[S])) as pivottable;
select * from (SELECT s.status, case when c.customer_po_ref like '%web%order%' then 'Web' else 'Std' end as type, count(s.packlist_id) as rCnt from shipper s inner join customer_order c on s.cust_order_id=c.id where s.invoice_id is not null group by s.status, case when c.customer_po_ref like '%web%order%' then 'Web' else 'Std' end) as SourceTable
	PIVOT(AVG(rCnt) for status in ([A],[1],[2],[3],[S])) as pivottable;
select * from shipper where invoice_id is null and status='a' order by create_date;

/*
--Put primay packlists back into approved status
update shipper set status='A' where status='2' AND INVOICE_ID IS NULL;

--Put primary packlists on hold
UPDATE SHIPPER SET STATUS='2' WHERE STATUS='A' AND INVOICE_ID IS NULL;
*/
/*
--Move shipped status, primarily RMAs, to approved status for invoicing
update shipper set status='A' WHERE STATUS='S' AND INVOICE_ID IS NULL AND SHIPPED_DATE>='2020-02-01';
*/



select * from LOCATION where id like '%mrk%'
select * from part_location where part_id = '330-11278-00'

select * from part where id= '330-11278-00'
/*select * from (SELECT status, count(packlist_id) as rCnt from shipper where invoice_id is null group by status) as SourceTable
	PIVOT(AVG(rCnt) for status in ([A],[1],[2],[3],[S])) as pivottable;*/

--select * from shipper where invoice_id is null and status='1' order by create_date;
--select * from shipper where invoice_id is null and status='2' order by create_date;
--select * from shipper where invoice_id is null and status='3' order by create_date;
--select * from shipper where invoice_id is null and status='S' order by create_date;
--select customer_order.customer_po_ref, shipper.* from shipper inner join customer_order on shipper.cust_order_id=customer_order.id 
--where shipper.invoice_id is null and shipper.status='A' and customer_order.customer_po_ref like '%WEB%';
--select customer_order.customer_id, * from shipper inner join customer_order on shipper.cust_order_id=customer_order.id left outer join receivable on shipper.invoice_id=receivable.invoice_id where shipper.create_date>'2020-04-02' and shipper.invoice_id is not null and shipper.status<>'A' order by shipper.create_date;
/*


--Move approved weborder packlists to review 1
UPDATE SHIPPER SET STATUS='1' FROM SHIPPER INNER JOIN CUSTOMER_ORDER ON SHIPPER.CUST_ORDER_ID=CUSTOMER_ORDER.ID 
WHERE SHIPPER.STATUS='A' AND SHIPPER.INVOICE_ID IS NULL AND CUSTOMER_ORDER.CUSTOMER_PO_REF LIKE '%WEB%'
*/


/*
select * from shipper where invoice_id is null and status='S' AND shipped_date>='2020-02-01';
*/