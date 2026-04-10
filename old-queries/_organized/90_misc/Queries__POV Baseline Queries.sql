select
last_cost.part_id,
avg_cost.part_id,
avg_cost.avg_unit_cost,
last_cost.last_cost

from
--2021 average cost
(select
inventory_trans.part_id,

(sum(INVENTORY_TRANS.ACT_MATERIAL_COST +
INVENTORY_TRANS.ACT_LABOR_COST +
INVENTORY_TRANS.ACT_BURDEN_COST + 
INVENTORY_TRANS.ACT_SERVICE_COST) / sum(inventory_trans.qty)) as Avg_Unit_Cost

from VECA.dbo.INVENTORY_TRANS INVENTORY_TRANS

where inventory_trans.part_id is not null and
inventory_trans.TYPE = 'I' and
inventory_trans.class = 'R' and
INVENTORY_TRANS.PURC_ORDER_ID is not null and
inventory_trans.TRANSACTION_date >= '2021-01-01' and
inventory_trans.TRANSACTION_date <= '2021-12-31' 

group by 
inventory_trans.part_id) as avg_cost

right join (

--Last Purchase Price prior to 2022
select
info.part_ID,
info.last_cost

from(
select
inventory_trans.part_id,

(INVENTORY_TRANS.ACT_MATERIAL_COST +
INVENTORY_TRANS.ACT_LABOR_COST +
INVENTORY_TRANS.ACT_BURDEN_COST + 
INVENTORY_TRANS.ACT_SERVICE_COST)/ inventory_trans.qty as Last_Cost,
inventory_trans.transaction_date,
inventory_trans.transaction_id,

ROW_NUMBER() over (PARTITION by inventory_trans.part_id order by inventory_trans.transaction_id desc) as cost_order

from VECA.dbo.INVENTORY_TRANS INVENTORY_TRANS

where inventory_trans.part_id is not null and
inventory_trans.TYPE = 'I' and
inventory_trans.class = 'R' and
INVENTORY_TRANS.PURC_ORDER_ID is not null and
inventory_trans.TRANSACTION_date <= '2021-12-31' ) as info

where info.cost_order = 1) as last_cost 

on last_cost.part_id = avg_cost.part_ID






