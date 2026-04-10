select

Turns.ID,
Turns.QTY_ON_HAND,
Turns.Yearly_QTY,
Turns.Half_Year_QTY,
Turns.Quarter_Year_Qty,
isnull(isnull(Turns.Yearly_QTY,0)/isnull(Turns.QTY_ON_HAND,1),0) as Yearly_Turns,
isnull(isnull(Turns.Half_Year_QTY,0)/isnull(Turns.QTY_ON_HAND,1),0) as Biannual_Turns,
isnull(isnull(Turns.Quarter_Year_Qty,0)/isnull(Turns.QTY_ON_HAND,1),0) as Quarterly_Turns




from(
Select
part.ID,
PART.QTY_ON_HAND,
Yearly.Qty as Yearly_QTY,
half.qty as Half_Year_QTY,
quarter.qty as Quarter_Year_Qty

from
veca.dbo.part  

left join
(

--365 Days Back
select
inventory_trans.part_ID,
sum(inventory_trans.qty) as QTY

from VECA.dbo.INVENTORY_TRANS INVENTORY_TRANS
where inventory_trans.transaction_date > getdate() - 365 and inventory_trans.type ='O' and inventory_trans.class = 'I'
group by
inventory_trans.part_ID) as Yearly  on part.id = yearly.part_ID

left join(
--180 Days Back
select
inventory_trans.part_ID,
sum(inventory_trans.qty) as QTY
from VECA.dbo.INVENTORY_TRANS INVENTORY_TRANS
where inventory_trans.transaction_date > getdate() - 180 and inventory_trans.type ='O' and inventory_trans.class = 'I'
group by
inventory_trans.part_ID) as half on half.part_iD = yearly.Part_iD


left join(
--180 Days Back
select
inventory_trans.part_ID,
sum(inventory_trans.qty) as QTY
from VECA.dbo.INVENTORY_TRANS INVENTORY_TRANS
where inventory_trans.transaction_date > getdate() - 90 and inventory_trans.type ='O' and inventory_trans.class = 'I'
group by
inventory_trans.part_ID) as quarter on quarter.part_iD = yearly.Part_iD

) as Turns





