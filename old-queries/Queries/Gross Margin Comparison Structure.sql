select			
P1.Code as P1_Code,			
P2.Code as P2_Code,			
Product.REV_GL_ACCT_ID,			
(P1.Qty * P1.ASP) as P1_Rev,			
(P2.Qty * P2.ASP) as P2_Rev,			
(isnull((P2.Qty * P2.ASP),0) - isnull((P1.Qty * P1.ASP),0) ) as Rev_Var,			
P1.Qty as P1_Qty,			
P2.Qty as P2_Qty,			
(isnull(P2.Qty,0) - isnull(P1.Qty,0)) as Qty_Var,			
P1.ASP as P1_ASP,			
P2.ASP as P2_ASP,			
(isnull(P2.ASP,0) - isnull(P1.ASP,0)) as Asp_Var,			
((isnull(P2.Qty,0) - isnull(P1.Qty,0))*isnull(P2.ASP,0)) as Volume_Var,			
((isnull(P2.ASP,0) - isnull(P1.ASP,0))*isnull(P1.Qty,0)) as Price_Var,			
			
(P1.Cost * P1.Qty) as P1_Total_Cost,			
(P2.Cost * P2.Qty) as P2_Total_Cost,			
(isnull((P2.Cost * P2.Qty),0)-isnull(P1.Cost * P1.Qty),0)) as Cost_Var,			
P1.Cost as P1_AC,			
P2.Cost as P2_AC,			
(isnull(P2.Cost,0)-isnull(P1.Cost,0)) as AC_VAR,			
((Isnull(P2.Qty,0) - Isnull(P1.Qty,0))*isnull(P2.Cost,0)) as Cost_Vol_Var,			
((isnull(P2.Cost,0)-isnull(P1.Cost,0))*isnull(P1.Qty,0)) as Cost_Var			
			
			
from			
(	SELECT revenue.product_code as Code, revenue.total_shipped as QTY, (revenue.Revenue / revenue.total_shipped) as ASP, (cost.total_cost / revenue.total_shipped) as COST  from( SELECT cust_order_line.product_code, sum(shipper_line.shipped_qty) as total_shipped, sum(shipper_line.unit_price * shipper_line.shipped_qty * ((100-shipper_Line.trade_disc_percent)/100)) as Revenue  from veca.dbo.shipper_Line shipper_Line  inner join veca.dbo.cust_order_line cust_order_line on (shipper_line.cust_order_line_no = cust_order_line.line_no and shipper_Line.cust_order_id = CUST_ORDER_LINE.CUST_ORDER_ID) inner join veca.dbo.shipper on shipper.packlist_id = shipper_Line.packlist_id  where shipper.shipped_Date Between {ts '2021-01-01 00:00:00'} And {ts '2021-01-31 00:00:00'} and shipper_Line.shipped_qty > 0 and cust_order_line.product_code is not null  group by  cust_order_line.product_code) as Revenue  full outer join (  SELECT  cust_order_line.product_code, sum(INVENTORY_TRANS.QTY) as Qty,   sum( INVENTORY_TRANS.ACT_MATERIAL_COST + INVENTORY_TRANS.ACT_LABOR_COST + INVENTORY_TRANS.ACT_BURDEN_COST +  INVENTORY_TRANS.ACT_SERVICE_COST) as Total_Cost  FROM VECA.dbo.INVENTORY_TRANS INVENTORY_TRANS  inner join VECA.dbo.cust_order_line on cust_order_line.line_no = INVENTORY_TRANS.CUST_ORDER_LINE_NO and cust_order_line.cust_order_id = INVENTORY_TRANS.CUST_ORDER_ID   WHERE  (INVENTORY_TRANS.TYPE='O') AND (INVENTORY_TRANS.CLASS='I') AND (INVENTORY_TRANS.CUST_ORDER_ID Is Not Null) AND (INVENTORY_TRANS.PART_ID Is Not Null) AND (INVENTORY_TRANS.TRANSACTION_DATE Between {ts '2021-01-01 00:00:00'} And {ts '2021-01-31 00:00:00'}) and cust_order_line.product_code is not null  group by  cust_order_line.product_code) as cost on cost.product_code = revenue.product_code	)	as P1
			
full outer join			
			
(	SELECT revenue.product_code as Code, revenue.total_shipped as QTY, (revenue.Revenue / revenue.total_shipped) as ASP, (cost.total_cost / revenue.total_shipped) as COST  from( SELECT cust_order_line.product_code, sum(shipper_line.shipped_qty) as total_shipped, sum(shipper_line.unit_price * shipper_line.shipped_qty * ((100-shipper_Line.trade_disc_percent)/100)) as Revenue  from veca.dbo.shipper_Line shipper_Line  inner join veca.dbo.cust_order_line cust_order_line on (shipper_line.cust_order_line_no = cust_order_line.line_no and shipper_Line.cust_order_id = CUST_ORDER_LINE.CUST_ORDER_ID) inner join veca.dbo.shipper on shipper.packlist_id = shipper_Line.packlist_id  where shipper.shipped_Date Between {ts '2022-01-01 00:00:00'} And {ts '2022-01-31 00:00:00'} and shipper_Line.shipped_qty > 0 and cust_order_line.product_code is not null  group by  cust_order_line.product_code) as Revenue  full outer join (  SELECT  cust_order_line.product_code, sum(INVENTORY_TRANS.QTY) as Qty,   sum( INVENTORY_TRANS.ACT_MATERIAL_COST + INVENTORY_TRANS.ACT_LABOR_COST + INVENTORY_TRANS.ACT_BURDEN_COST +  INVENTORY_TRANS.ACT_SERVICE_COST) as Total_Cost  FROM VECA.dbo.INVENTORY_TRANS INVENTORY_TRANS  inner join VECA.dbo.cust_order_line on cust_order_line.line_no = INVENTORY_TRANS.CUST_ORDER_LINE_NO and cust_order_line.cust_order_id = INVENTORY_TRANS.CUST_ORDER_ID   WHERE  (INVENTORY_TRANS.TYPE='O') AND (INVENTORY_TRANS.CLASS='I') AND (INVENTORY_TRANS.CUST_ORDER_ID Is Not Null) AND (INVENTORY_TRANS.PART_ID Is Not Null) AND (INVENTORY_TRANS.TRANSACTION_DATE Between {ts '2022-01-01 00:00:00'} And {ts '2022-01-31 00:00:00'}) and cust_order_line.product_code is not null  group by  cust_order_line.product_code) as cost on cost.product_code = revenue.product_code	)	as P2
			
on 	P1.Code = P2.Code		
			
left join	veca.dbo.product		
on			
	isnull(p1.code,p2.code) = product.CODE		
			
where 			
	left(Product.REV_GL_ACCT_ID,4) = '4000'		
			
