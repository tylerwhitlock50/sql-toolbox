-- Declare the variable with a specific data type

DECLARE @part_id NVARCHAR(50);

SET @part_id = '801-12015-00';
 
-- Use a Common Table Expression (CTE)

WITH pq AS (

    SELECT 

        i.location_id,

        SUM(CASE WHEN i.type = 'I' THEN i.qty ELSE -i.qty END) AS inv_qty

    FROM INVENTORY_TRANS i 

    WHERE i.part_id = @part_id

    GROUP BY i.location_id

)
 
-- Main query

SELECT 

    i.location_id, 

    pq.inv_qty,

    SUM(t.qty) AS trace_qty,

    pl.qty AS part_loc_qty

FROM INVENTORY_TRANS i 

LEFT JOIN TRACE_INV_TRANS t ON t.TRANSACTION_ID = i.TRANSACTION_ID 

LEFT JOIN part_location pl ON pl.part_id = i.part_id AND i.LOCATION_ID = pl.LOCATION_ID

LEFT JOIN pq ON pq.location_id = i.LOCATION_ID

WHERE i.PART_ID = @part_id

GROUP BY 

    i.location_id, 

    pq.inv_qty,

    pl.qty

ORDER BY 

    i.location_id DESC;

 
DECLARE @part_id NVARCHAR(50);

SET @part_id = '801-12015-00';
 
with i as(

select distinct transaction_id as id from INVENTORY_TRANS where part_id = @part_id),

t as (

select distinct transaction_id as id from trace_inv_trans where part_id = @part_id)
 
select i.id as inv_trans, t.id as trace_trans from i full outer join t on i.id = t.id

where t.id  is null

 