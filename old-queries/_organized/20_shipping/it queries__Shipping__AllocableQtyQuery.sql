WITH OpenOrders AS (
    SELECT
		ORD.ID,
        ORD.CREATE_DATE,
		ORD.STATUS,
        OL.LINE_NO,
        OL.PART_ID,
        OL.ORDER_QTY,
        COALESCE(dsl.desired_del_ship_date, ol.desired_ship_date, ord.desired_ship_date) AS SHIP_BY_DATE
    FROM
        CUSTOMER_ORDER ORD
        INNER JOIN CUST_ORDER_LINE OL ON ORD.ID = OL.CUST_ORDER_ID
		LEFT JOIN IRP_DELIVERY_SCHEDULE_LINE_SHIP_DATE DSL ON OL.CUST_ORDER_ID = DSL.CUST_ORDER_ID and OL.LINE_NO = DSL.CUST_ORDER_LINE_NO
    WHERE
        ORD.STATUS = 'R'
        AND OL.LINE_STATUS = 'A'
        AND  COALESCE(dsl.desired_del_ship_date, ol.desired_ship_date, ord.desired_ship_date)  <= getDate()
),
Stock AS (
    SELECT
        PART_ID,
		PRODUCT_CODE,
        SUM(QTY) AS AVAILABLE_QTY
    FROM VS_TRACE_LOCATION_QTY
	where Warehouse_ID = 'SHIPPING' and QTY > 0 and TRACE_ID not in (SELECT TRACE_ID FROM CY_FULFILLMENT)
	GROUP BY PART_ID, PRODUCT_CODE
),
Allocations AS (
    SELECT
        O.ID,
        O.SHIP_BY_DATE,
		O.STATUS,
        O.LINE_NO,
        O.PART_ID,
        O.ORDER_QTY,
        S.AVAILABLE_QTY,
		S.PRODUCT_CODE,
        -- Cumulative required qty for FIFO allocation
        SUM(O.ORDER_QTY) OVER (PARTITION BY O.PART_ID ORDER BY O.SHIP_BY_DATE, O.ID, O.LINE_NO) AS "CumulativeRequired",
        -- Remaining qty available AFTER this line's allocation
        S.AVAILABLE_QTY - 
        SUM(O.ORDER_QTY) OVER (PARTITION BY O.PART_ID ORDER BY O.SHIP_BY_DATE, O.ID, O.LINE_NO) AS "RemainingQty"
    FROM
        OpenOrders O
        INNER JOIN Stock S ON O.PART_ID = S.PART_ID
)
SELECT
    A.ID,
    A.SHIP_BY_DATE,
	A.STATUS,
    A.LINE_NO,
    A.PART_ID,
	A.PRODUCT_CODE,
    A.ORDER_QTY,
    A.AVAILABLE_QTY,
    A."CumulativeRequired",
    A."RemainingQty",
    -- How much you can assign on this line
    CASE
        WHEN A."RemainingQty" >= 0 THEN A.ORDER_QTY                                 -- Fully allocatable
        WHEN A."CumulativeRequired" - A.AVAILABLE_QTY < A.ORDER_QTY THEN           -- Partial allocation
            A.ORDER_QTY - (A."CumulativeRequired" - A.AVAILABLE_QTY)
        ELSE 0                                                                      -- No allocation
    END AS "AllocatableQty"
 
FROM
    Allocations A
Where (    CASE
        WHEN A."RemainingQty" >= 0 THEN A.ORDER_QTY                                 -- Fully allocatable
        WHEN A."CumulativeRequired" - A.AVAILABLE_QTY < A.ORDER_QTY THEN           -- Partial allocation
            A.ORDER_QTY - (A."CumulativeRequired" - A.AVAILABLE_QTY)
        ELSE 0                                                                      -- No allocation
    END) > 0
ORDER BY
	A.SHIP_BY_DATE,
	A.PRODUCT_CODE,
    A.PART_ID,
    A.ID,
    A.LINE_NO


-- What does this give us?
-- The amount of inventory that is currently in the cage that could be allocated to a given order line that is released and active
-- What this doesnt tell us:
--


--Orders that are new and not on hold for some reason or another
WITH OpenOrders AS (
    SELECT
        ORD.ID,
        ORD.CREATE_DATE,
        ORD.STATUS,
        OL.LINE_NO,
        OL.PART_ID,
        OL.ORDER_QTY,
        COALESCE(dsl.desired_del_ship_date, ol.desired_ship_date, ord.desired_ship_date) AS SHIP_BY_DATE
    FROM CUSTOMER_ORDER ORD
    INNER JOIN CUST_ORDER_LINE OL ON ORD.ID = OL.CUST_ORDER_ID
    LEFT JOIN IRP_DELIVERY_SCHEDULE_LINE_SHIP_DATE DSL 
        ON OL.CUST_ORDER_ID = DSL.CUST_ORDER_ID 
        AND OL.LINE_NO = DSL.CUST_ORDER_LINE_NO
    WHERE ORD.STATUS = 'R'
    AND OL.LINE_STATUS = 'A'
    AND COALESCE(dsl.desired_del_ship_date, ol.desired_ship_date, ord.desired_ship_date) <= GETDATE()
	AND ORD.CUSTOMER_PO_REF not like '%RMA%'
	AND ORD.SALESREP_ID not like '%RMA%'
),
--All Unassigned Stock
Stock AS (
    SELECT
        PART_ID,
        PRODUCT_CODE,
        SUM(QTY) AS AVAILABLE_QTY
    FROM VS_TRACE_LOCATION_QTY
    WHERE Warehouse_ID = 'SHIPPING' 
    AND QTY > 0 
    AND TRACE_ID NOT IN (SELECT TRACE_ID FROM CY_FULFILLMENT)
    GROUP BY PART_ID, PRODUCT_CODE
),
--Quantities that exist on Packlists
ShippedQty AS (
    SELECT
        SL.CUST_ORDER_ID AS ID,
        SL.CUST_ORDER_LINE_NO AS LINE_NO,
        SUM(SL.SHIPPED_QTY) AS TOTAL_SHIPPED_QTY
    FROM SHIPPER_LINE SL
    INNER JOIN SHIPPER SH ON SL.PACKLIST_ID = SH.PACKLIST_ID
    GROUP BY SL.CUST_ORDER_ID, SL.CUST_ORDER_LINE_NO
),
 Fulfilled AS (
    SELECT
        ORDER_ID,
        LINE_NO,
        PART_ID,
        COUNT(*) AS TOTAL_ALLOCATED_QTY  -- Each row represents one reserved gun
    FROM CY_FULFILLMENT
    GROUP BY ORDER_ID, LINE_NO, PART_ID
),
--
Allocations AS (
    SELECT
        O.ID,
        O.SHIP_BY_DATE,
        O.STATUS,
        O.LINE_NO,
        O.PART_ID,
        O.ORDER_QTY,
        COALESCE(F.TOTAL_ALLOCATED_QTY, 0) AS TOTAL_ALLOCATED_QTY,
        COALESCE(SQ.TOTAL_SHIPPED_QTY, 0) AS SHIPPED_QTY,
        O.ORDER_QTY - COALESCE(SQ.TOTAL_SHIPPED_QTY, 0) - COALESCE(F.TOTAL_ALLOCATED_QTY, 0) AS "RemainingOrderQty",
        S.AVAILABLE_QTY,
        S.PRODUCT_CODE,
        SUM(O.ORDER_QTY - COALESCE(SQ.TOTAL_SHIPPED_QTY, 0) - COALESCE(F.TOTAL_ALLOCATED_QTY, 0)) 
        OVER (PARTITION BY O.PART_ID ORDER BY O.SHIP_BY_DATE, O.ID, O.LINE_NO) AS "CumulativeRequired",
        S.AVAILABLE_QTY - 
        SUM(O.ORDER_QTY - COALESCE(SQ.TOTAL_SHIPPED_QTY, 0) - COALESCE(F.TOTAL_ALLOCATED_QTY, 0)) 
        OVER (PARTITION BY O.PART_ID ORDER BY O.SHIP_BY_DATE, O.ID, O.LINE_NO) AS "RemainingQty"
    FROM OpenOrders O
    INNER JOIN Stock S ON O.PART_ID = S.PART_ID
    LEFT JOIN ShippedQty SQ ON O.ID = SQ.ID AND O.LINE_NO = SQ.LINE_NO 
    LEFT JOIN Fulfilled F ON O.ID = F.ORDER_ID AND O.LINE_NO = F.LINE_NO
)

SELECT
    A.ID,
    A.SHIP_BY_DATE,
    A.STATUS,
    A.LINE_NO,
    A.PART_ID,
    A.PRODUCT_CODE,
    A.ORDER_QTY,
    A.SHIPPED_QTY,
    A.TOTAL_ALLOCATED_QTY,
    A.RemainingOrderQty,
    A.AVAILABLE_QTY,
    A."CumulativeRequired",
    A."RemainingQty",
    -- How much you can assign on this line
    CASE
        WHEN A."RemainingQty" >= 0 THEN 
            CASE 
                WHEN A.ORDER_QTY - A.SHIPPED_QTY - A.TOTAL_ALLOCATED_QTY > 0 
                THEN A.ORDER_QTY - A.SHIPPED_QTY - A.TOTAL_ALLOCATED_QTY 
                ELSE 0 
            END
        WHEN A."CumulativeRequired" - A.AVAILABLE_QTY < A.ORDER_QTY THEN
            CASE 
                WHEN A.ORDER_QTY - A.SHIPPED_QTY - (A."CumulativeRequired" - A.AVAILABLE_QTY) - A.TOTAL_ALLOCATED_QTY > 0 
                THEN A.ORDER_QTY - A.SHIPPED_QTY - (A."CumulativeRequired" - A.AVAILABLE_QTY) - A.TOTAL_ALLOCATED_QTY 
                ELSE 0 
            END
        ELSE 0
    END AS "AllocatableQty"
FROM Allocations A
WHERE 
    -- Ensure we’re only looking at lines that can still be allocated
    A.ORDER_QTY - A.SHIPPED_QTY - A.TOTAL_ALLOCATED_QTY > 0
ORDER BY
    A.SHIP_BY_DATE,
    A.PRODUCT_CODE,
    A.PART_ID,
    A.ID,
    A.LINE_NO;


SELECT ord.ID, ord.CUSTOMER_ID, STATUS, CREDIT_STATUS, CUSTOMER_TYPE, ord.ORDER_TYPE, 
 ord.ACCEPT_EARLY, ord.DAYS_EARLY
FROM CUSTOMER_ORDER ord
inner join CUSTOMER_ENTITY on ord.CUSTOMER_ID = CUSTOMER_ENTITY.CUSTOMER_ID
inner join CUSTOMER_SITE on ord.CUSTOMER_ID = CUSTOMER_SITE.CUSTOMER_ID
WHERE STATUS NOT IN ('C','X')

--FOR EACH

select * from CUST_ORDER_LINE
SELECT 
COALESCE(dsl.desired_del_ship_date, ol.desired_ship_date, ord.desired_ship_date) AS SHIP_BY_DATE
FROM CUST_ORDER_LINE ol
inner join CUSTOMER_ORDER ord on ord.id = ol.cust_order_id 
left join IRP_DELIVERY_SCHEDULE_LINE_SHIP_DATE dsl on ol.cust_order_id = dsl.CUST_ORDER_ID and ol.line_no = dsl.CUST_ORDER_LINE_NO
where ol.CUST_ORDER_ID = '1'

select * from CUSTOMER_ENTITY

select * from IRP_DELIVERY_SCHEDULE_LINE_SHIP_DATE 

SELECT ord.ID, ord.CUSTOMER_ID, STATUS, CREDIT_STATUS, CUSTOMER_TYPE, ord.ORDER_TYPE, ord.ACCEPT_EARLY, ord.DAYS_EARLY
FROM CUSTOMER_ORDER ord
inner join CUSTOMER_ENTITY on ord.CUSTOMER_ID = CUSTOMER_ENTITY.CUSTOMER_ID
inner join CUSTOMER_SITE on ord.CUSTOMER_ID = CUSTOMER_SITE.CUSTOMER_ID
WHERE STATUS NOT IN ('C','X')
Order by CUSTOMER_ID

