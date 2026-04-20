/*
This is a diagnostic query to find parts that are missing from the part_location table.
basically if the inventory trans bale and the location table are out of sync the MRP windown will drive
off the sum of the inventory trans and the quantities on hand are not correct.



*/
WITH pl AS (
    SELECT
        part_id,
        warehouse_id,
        location_id,
        SUM(COALESCE(qty, 0)) AS part_location_qty
    FROM part_location
    GROUP BY
        part_id,
        warehouse_id,
        location_id
),
it AS (
    SELECT
        part_id,
        warehouse_id,
        location_id,
        SUM(CASE WHEN type = 'I' THEN qty ELSE -qty END) AS inventory_trans_qty
    FROM inventory_trans
    GROUP BY
        part_id,
        warehouse_id,
        location_id
)
SELECT
    COALESCE(pl.part_id, it.part_id) AS part_id,
    COALESCE(pl.warehouse_id, it.warehouse_id) AS warehouse_id,
    COALESCE(pl.location_id, it.location_id) AS location_id,
    COALESCE(pl.part_location_qty, 0) AS part_location_qty,
    COALESCE(it.inventory_trans_qty, 0) AS inventory_trans_qty,
    COALESCE(pl.part_location_qty, 0) - COALESCE(it.inventory_trans_qty, 0) AS qty_diff
FROM pl
FULL OUTER JOIN it
    ON pl.part_id = it.part_id
   AND pl.warehouse_id = it.warehouse_id
   AND pl.location_id = it.location_id
WHERE COALESCE(pl.part_location_qty, 0) <> COALESCE(it.inventory_trans_qty, 0)  and COALESCE(pl.part_id, it.part_id) is not null
ORDER BY
    ABS(COALESCE(pl.part_location_qty, 0) - COALESCE(it.inventory_trans_qty, 0)) DESC,
    COALESCE(pl.part_id, it.part_id),
    COALESCE(pl.warehouse_id, it.warehouse_id),
    COALESCE(pl.location_id, it.location_id);

--select * from inventory_trans where part_id = '440-00131-01' and location_id = 'p-assy' and warehouse_id = 'main'