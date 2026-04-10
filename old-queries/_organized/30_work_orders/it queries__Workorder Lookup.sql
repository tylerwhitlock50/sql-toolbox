use veca
select w.base_id as workorder_base_id,  w.part_id, w.create_date, w.PRODUCT_CODE, w.COMMODITY_CODE, w.STATUS_EFF_DATE, dsl.DEMAND_BASE_ID, sum(r.issued_qty) as req_issued_qty, sum(r.CALC_QTY) as req_calc_qty 
from work_order w  
left join requirement r on w.BASE_ID = r.WORKORDER_BASE_ID 
left join DEMAND_SUPPLY_LINK dsl on w.BASE_ID = dsl.SUPPLY_BASE_ID
where w.status not in ('X', 'C') 
and w.type = 'W'
group by w.base_id, w.PART_ID,  w.PRODUCT_CODE, w.COMMODITY_CODE,  dsl.DEMAND_BASE_ID, w.create_date, w.STATUS_EFF_DATE
--having sum(r.issued_qty) = 0
order by create_date asc

select * from part_location where part_id = '801-06443-00'



select top 1 * from cust_order_line


select top 1 * from DEMAND_SUPPLY_LINK

select w.base_id as workorder_base_id, w.create_date, w.PRODUCT_CODE, w.COMMODITY_CODE, w.STATUS_EFF_DATE, w.part_id, sum(r.issued_qty) as issued_qty, sum(r.CALC_QTY) as calc_qty 
from work_order w  
inner join requirement r on w.BASE_ID = r.WORKORDER_BASE_ID 
where w.status not in ('X', 'C') 
and w.type = 'W'
and create_date < '03-01-2024'
group by w.base_id, w.create_date, w.PRODUCT_CODE, w.COMMODITY_CODE, w.STATUS_EFF_DATE, w.PART_ID
--having sum(r.issued_qty) = 0
order by create_date asc


