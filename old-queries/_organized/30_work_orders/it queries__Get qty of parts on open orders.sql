use veca
SELECT 
    work_order.part_id,
    SUM(work_order.desired_qty - work_order.received_qty) AS qty
FROM work_order
INNER JOIN 
    (
		            -- Step 1: Get Open Order IDs
            SELECT 
                cl.part_id
            FROM cust_order_line CL 
            INNER JOIN customer_order CO ON CO.id = CL.cust_order_id 
            INNER JOIN customer_entity CE ON CE.customer_id = CO.customer_id
            WHERE 
                CL.line_status = 'A'                            -- Active order lines
                AND CO.status = 'R'                             -- Released orders
                AND CE.credit_status = 'A'                      -- Customers with active credit status
                AND ISNULL(CL.desired_ship_date, CO.desired_ship_date) < GETDATE() + 10  -- Ship date within 10 days
            GROUP BY cl.part_id
    ) AS oco ON oco.PART_ID = work_order.PART_ID
WHERE work_order.create_date > GETDATE() - 30
AND work_order.type = 'W'
AND work_order.status = 'R'
AND work_order.part_id IS NOT NULL

GROUP BY 
    work_order.part_id;