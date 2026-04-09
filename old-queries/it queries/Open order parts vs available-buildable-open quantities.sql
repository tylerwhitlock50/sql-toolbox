use veca
SELECT DISTINCT
    open_orders.part_id AS open_order_part_id,              -- Open order part ID
    p.product_code,                                         -- Product code for the open order part
    available_inventory.part_id AS available_part_id,       -- Component part ID from available inventory
    available_inventory.available_qty / requirement.Calc_Qty AS buildable_qty, -- Calculated buildable quantity
	open_orders.open_qty AS open_qty
FROM 
    (
        -- Step 1: Get Open Order IDs
        SELECT 
            cl.part_id,
			sum(cl.order_qty - cl.total_shipped_qty) as open_qty
        FROM cust_order_line CL 
        INNER JOIN customer_order CO ON CO.id = CL.cust_order_id 
        INNER JOIN customer_entity CE ON CE.customer_id = CO.customer_id
        WHERE 
            CL.line_status = 'A'                            -- Active order lines
            AND CO.status = 'R'                             -- Released orders
            AND CE.credit_status = 'A'                      -- Customers with active credit status
            AND ISNULL(CL.desired_ship_date, CO.desired_ship_date) < GETDATE() + 10  -- Ship date within 10 days
        GROUP BY cl.part_id
    ) open_orders
-- Step 2: Join with REQUIREMENT table to get the components needed to build each Open Order ID
INNER JOIN REQUIREMENT requirement 
    ON requirement.workorder_base_id = open_orders.part_id
    AND requirement.workorder_type = 'M'                    -- Manufacturing work orders
    AND requirement.status = 'U'                            -- Unfulfilled requirements
    AND requirement.Calc_Qty > 0                            -- Positive required quantity
-- Step 3: Replace `part_site` with `PART_LOCATION` to get available inventory for each component part
LEFT JOIN (
    SELECT 
        PART_LOCATION.PART_ID AS part_id,
        SUM(PART_LOCATION.QTY) AS available_qty             -- Calculate available inventory for each component using the updated logic
    FROM PART_LOCATION
    WHERE PART_LOCATION.STATUS = 'A'                        -- Active part locations
    AND PART_LOCATION.WAREHOUSE_ID = 'MAIN'                 -- Limit to the 'MAIN' warehouse
	and  PART_LOCATION.LOCATION_ID not in ('P-SAND','RMA','STORES','P-ASSY','C2-ALLOCATED')
    GROUP BY PART_LOCATION.PART_ID
) available_inventory ON available_inventory.part_id = requirement.part_id
-- Step 4: Join with the PART table to get the product code and commodity code of the open order part
INNER JOIN part p ON p.id = open_orders.part_id
-- Step 5: Subquery to find the minimum buildable_qty for each open_order_part_id
INNER JOIN (
    SELECT 
        open_orders.part_id AS open_order_part_id,
        MIN(available_inventory_sub.available_qty / requirement_sub.Calc_Qty) AS min_buildable_qty
    FROM 
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
        ) open_orders
    -- Step 2: Join with REQUIREMENT table to get the components needed to build each Open Order ID
    INNER JOIN REQUIREMENT requirement_sub 
        ON requirement_sub.workorder_base_id = open_orders.part_id
        AND requirement_sub.workorder_type = 'M'
        AND requirement_sub.status = 'U'
        AND requirement_sub.Calc_Qty > 0
    -- Step 3: Replace `part_site` with `PART_LOCATION` to get available inventory for each component part
    LEFT JOIN (
        SELECT 
            PART_LOCATION.PART_ID AS part_id,
            SUM(PART_LOCATION.QTY) AS available_qty             -- Calculate available inventory for each component using the updated logic
        FROM PART_LOCATION
        WHERE PART_LOCATION.STATUS = 'A'                        -- Active part locations
        AND PART_LOCATION.WAREHOUSE_ID = 'MAIN'                 -- Limit to the 'MAIN' warehouse
		and PART_LOCATION.LOCATION_ID not in ('P-SAND','RMA','STORES','P-ASSY','C2-ALLOCATED')
        GROUP BY PART_LOCATION.PART_ID
    ) available_inventory_sub ON available_inventory_sub.part_id = requirement_sub.part_id
    GROUP BY open_orders.part_id
) min_qty ON min_qty.open_order_part_id = open_orders.part_id
AND available_inventory.available_qty / requirement.Calc_Qty = min_qty.min_buildable_qty
-- Filter by commodity code
WHERE p.commodity_code LIKE '%GUN%' and open_qty <> 0