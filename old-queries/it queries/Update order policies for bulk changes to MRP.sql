use veca
select * from part where id like ('%-M')

select * from part_location where warehouse_id = 'MAIN' and location_id = 'R05SFB09'

select * from warehouse_locati

select * from part where order_policy = 'M'
/*
update part set order_policy = 'D' where order_policy = 'M'
update part_site set order_policy = 'D' where order_policy = 'M'
*/