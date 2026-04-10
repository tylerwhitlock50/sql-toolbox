use veca
select * from inventory_trans where transaction_id = '11747922'
select top 1000 * from inventory_trans inner join TRACE_INV_TRANS on INVENTORY_TRANS.TRANSACTION_ID = TRACE_INV_TRANS.TRANSACTION_ID where trace_id = 'C6TX00206' order by inventory_trans.transaction_id desc-- WHERE TRACE_INV_TRANS.TRANSACTION_ID = '11747922'

SELECT * FROM TRACE_INV_TRANS WHERE TRACE_ID = 'C6TX00206' ORDER BY CREATE_DATE

SELECT * FROM PART WHERE id = '801-03002-02'

SELECT DISTINCT PART.USER_6 AS UPC, PART.ID as SKU, PART.DESCRIPTION, CONVERT(NVARCHAR(MAX),CONVERT(VARBINARY(MAX),PART_CO_BINARY.BITS)) AS LONG_DESC, USER_DEF_FIELDS.STRING_VAL AS PRODUCT, trace_inv_trans.trace_id AS SN, trace_inv_trans.transaction_id 
FROM VECA.dbo.PART 
INNER JOIN VECA.dbo.WORK_ORDER ON PART.ID = CASE WHEN WORK_ORDER.PART_ID IS NULL THEN WORK_ORDER.USER_3 ELSE WORK_ORDER.PART_ID END
LEFT OUTER JOIN VECA.dbo.INVENTORY_TRANS ON WORK_ORDER.BASE_ID = INVENTORY_TRANS.WORKORDER_BASE_ID AND INVENTORY_TRANS.TYPE='O' AND INVENTORY_TRANS.CLASS='I' 
LEFT OUTER JOIN VECA.dbo.TRACE_INV_TRANS ON INVENTORY_TRANS.TRANSACTION_ID = TRACE_INV_TRANS.TRANSACTION_ID 
LEFT OUTER JOIN VECA.dbo.PART_CO_BINARY ON PART_CO_BINARY.PART_ID=PART.ID 
LEFT OUTER JOIN VECA.dbo.USER_DEF_FIELDS ON USER_DEF_FIELDS.DOCUMENT_ID=PART.ID AND USER_DEF_FIELDS.ID='UDF-0000021' 
left outer join veca.dbo.part Part_Comp on part_comp.id = inventory_trans.part_ID 
WHERE WORK_ORDER.SUB_ID=0 AND WORK_ORDER.BASE_ID='506060' AND TRACE_INV_TRANS.TRACE_ID IS NOT NULL and (part_comp.commodity_code like 'act%' or part_comp.commodity_code like '%gun%' or part_comp.commodity_code like '%ass%') 
order by trace_inv_Trans.transaction_id desc

select * from WORK_ORDER where BASE_ID = '506059'
select * from WORK_ORDER where BASE_ID = '539098'

select * from part inner join part_location on part.id = part_location.part_id where part.id like '%801-%' and part_location.LOCATION_ID = 'C2' and part_location.qty > 0

select top 100 trace_inv_trans.transaction_id, inventory_trans.parT_id, part_location.qty as part_loc_qty, TRACE_ID, part_location.location_id from inventory_trans inner join TRACE_INV_TRANS on INVENTORY_TRANS.TRANSACTION_ID = TRACE_INV_TRANS.TRANSACTION_ID  inner join part_location on inventory_trans.part_id = part_location.part_id 
where part_location.qty > 0
order by trace_inv_trans.TRANSACTION_ID desc

select top 1000 inventory_trans.part_id, sum(trace_inv_trans.qty), TRACE_ID, LOCATION_ID from inventory_trans inner join TRACE_INV_TRANS on INVENTORY_TRANS.TRANSACTION_ID = TRACE_INV_TRANS.TRANSACTION_ID where inventory_trans.description = 'TRANSFER Transaction made by the API TOOLKIT' 
group by trace_id, inventory_trans.location_id, inventory_trans.part_id
having sum(trace_inv_Trans.qty)>1 

select top 1000 inventory_trans.part_id, trace_inv_Trans.qty TRACE_ID, LOCATION_ID from inventory_trans inner join TRACE_INV_TRANS on INVENTORY_TRANS.TRANSACTION_ID = TRACE_INV_TRANS.TRANSACTION_ID
where inventory_trans.description = 'TRANSFER Transaction made by the API TOOLKIT' 
group by trace_id, inventory_trans.location_id, inventory_trans.part_id, trace_inv_Trans.qty




select inventory_trans.part_id, sum(trace_inv_trans.qty) as qty, TRACE_ID, LOCATION_ID 

from inventory_trans inner join TRACE_INV_TRANS on INVENTORY_TRANS.TRANSACTION_ID = TRACE_INV_TRANS.TRANSACTION_ID 

where inventory_trans.description = 'TRANSFER Transaction made by the API TOOLKIT' 

group by inventory_trans.part_id,  trace_id, inventory_trans.location_id
having sum(trace_inv_Trans.qty)>1 




select * from TRACE_INV_TRANS where TRANSACTION_ID = '12717959'

select * from trace_inv_trans where trace_id = 'A93M01738' order by transaction_id desc
select sum(qty), transaction_id from trace_inv_trans where trace_id = 'A93M01738' group by qty order by transaction_id desc

select * from inventory_trans inner join trace_inv_Trans on inventory_trans.TRANSACTION_id = trace_inv_trans.TRANSACTION_ID where trace_id= '2M01269' order by inventory_trans.TRANSACTION_ID

select * from trace_inv_trans where trace_id = 'A93M01738'

A93M01738

select * from TRACE_INV_TRANS where TRANSACTION_ID = '12712283'

12712283

select * from inventory_trans where transaction_id = '12712283'

select * from INFORMATION_SCHEMA.columns where table_name = 'PART'