-- CTEs to simplify the query
WITH t1 AS (
    SELECT
        customer_order.ID AS order_id,
        cust_order_line.line_no,
        customer_order.customer_id AS customer_id,
        customer_order.CUSTOMER_PO_REF AS customer_po_ref,
        ISNULL(cust_order_line.desired_ship_date, customer_order.desired_ship_date) AS due_date,
        part.product_code,
        cust_order_line.order_qty AS order_qty,
        cust_order_line.PART_ID AS part_id,
        cust_order_line.TOTAL_SHIPPED_QTY AS shipped_qty
    FROM veca.dbo.customer_order customer_order
    INNER JOIN veca.dbo.cust_order_line cust_order_line
        ON cust_order_line.cust_order_id = customer_order.id
    INNER JOIN veca.dbo.part
        ON part.id = cust_order_line.part_id
    INNER JOIN veca.dbo.customer_entity customer_entity
        ON customer_entity.customer_id = customer_order.customer_id
    LEFT JOIN veca.dbo.demand_supply_link
        ON demand_supply_link.demand_base_id = cust_order_line.cust_order_id
        AND demand_supply_link.[DEMAND_SEQ_NO] = cust_order_line.line_no
    WHERE customer_order.status = 'R'
      AND cust_order_line.line_status = 'A'
      AND cust_order_line.order_qty - cust_order_line.TOTAL_SHIPPED_QTY > 0
      AND ISNULL(cust_order_line.desired_ship_date, customer_order.desired_ship_date) < GETDATE() + 10
      AND customer_order.SALESREP_ID <> 'RMA'
      AND customer_entity.credit_status = 'A'
      AND customer_order.customer_po_ref NOT LIKE ('%RMA%')
      AND customer_order.customer_id <> 'CA MARK'
      AND demand_supply_link.[SUPPLY_BASE_ID] IS NULL -- Not linked to a work order
      AND part.product_code <> 'EVOKE'
      AND customer_order.customer_id NOT IN (
          'ital sport', 'VINCK CO', 'BRYC ADAM', 'JAE HER', 'TODD VAND', 'WOLV SUPP',
          'CORL SPOR', 'SYLV SPOR', 'CORL SPO1', 'CALG SHOO', 'JEFF BRAD',
          'ANDY STUM', 'ACT AERO', 'TANY SAMP', 'ODLE'
      )
),
t2 AS (
    SELECT
        customer_order.ID AS order_id,
        cust_order_line.line_no,
        customer_order.customer_id AS customer_id,
        customer_order.CUSTOMER_PO_REF AS customer_po_ref,
        ISNULL(cust_order_line.desired_ship_date, customer_order.desired_ship_date) AS due_date,
        part.product_code,
        cust_order_line.order_qty AS order_qty,
        cust_order_line.PART_ID AS part_id,
        cust_order_line.TOTAL_SHIPPED_QTY AS shipped_qty
    FROM veca.dbo.customer_order customer_order
    INNER JOIN veca.dbo.cust_order_line cust_order_line
        ON cust_order_line.cust_order_id = customer_order.id
    INNER JOIN veca.dbo.part
        ON part.id = cust_order_line.part_id
    INNER JOIN veca.dbo.customer_entity customer_entity
        ON customer_entity.customer_id = customer_order.customer_id
    LEFT JOIN veca.dbo.demand_supply_link
        ON demand_supply_link.demand_base_id = cust_order_line.cust_order_id
        AND demand_supply_link.[DEMAND_SEQ_NO] = cust_order_line.line_no
    WHERE customer_order.status = 'R'
	and cust_order_line.product_code <> 'WARRANTY'
	AND cust_order_line.line_status = 'A'
    AND cust_order_line.order_qty - cust_order_line.TOTAL_SHIPPED_QTY > 0
    AND ISNULL(cust_order_line.desired_ship_date, customer_order.desired_ship_date) < GETDATE() + 10
	and cust_order_line.product_code <> 'EVOKE'
	      AND demand_supply_link.[SUPPLY_BASE_ID] IS NULL -- Not linked to a work order

)
-- Anti-join: Select rows in t2 not in t1
SELECT t2.*
FROM t2
LEFT JOIN t1
    ON t2.order_id = t1.order_id
   AND t2.line_no = t1.line_no
WHERE t1.order_id IS NULL;