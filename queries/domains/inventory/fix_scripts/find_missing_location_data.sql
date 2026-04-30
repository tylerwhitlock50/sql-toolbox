use veca;
--1
select part_id, transaction_id
 from inventory_trans i
 where i.part_id is not null
 and not exists 
 (select * from part p
 where i.part_id = p.id);
--2
select distinct(warehouse_id)
 from location
 where warehouse_id not in
(select id from warehouse);
--3
select warehouse_id from inventory_trans i 
 where i.part_id is not NULL
 and i.warehouse_id not in 
 (select w.id from warehouse w
 where i.warehouse_id = w.id)
 order by i.warehouse_id;
--4
select distinct i.warehouse_id, i.location_id
 from inventory_trans i
 where i.part_id is not null
 and not exists 
 (select * from warehouse w
 where w.id = i.warehouse_id);
 --5
select distinct warehouse_id, location_id
 from inventory_trans i
 where i.warehouse_id is not NULL 
 and i.location_id is not NULL
 and part_id is not NULL 
 and not exists
 (select  * from location p
 where i.warehouse_id = p.warehouse_id 
 and p.id = i.location_id);
--6
select distinct part_id, warehouse_id, location_id
 from inventory_trans i
 where i.warehouse_id is not NULL 
 and i.location_id is not NULL
 and part_id is not NULL 
 and not exists 
 (select id from part
 where status = 'O' 
 and part.id = part_id)
 and  not exists
 (select  * from part_location p
 where i.warehouse_id = p.warehouse_id 
 and p.location_id = i.location_id
 and i.part_id = p.part_id);


-- part_warehouse
-- part_location
--select * from location
--select * from warehouse
--select * from part_warehouse
--select top 20 * from part_location where part_id = '801-01008-00'

--select * from location

select * from part_location where part_id = '801-01008-00'