BEGIN TRANSACTION;

-- Preview mismatches first
SELECT
    w.base_id,
    w.lot_id,
    w.split_id,
    w.sub_id,
    w.status AS work_order_status,
    r.part_id,
    r.status AS requirement_status
FROM work_order w
JOIN requirement r
    ON r.workorder_base_id = w.base_id
   AND r.workorder_lot_id  = w.lot_id
   AND r.workorder_split_id = w.split_id
   AND r.workorder_sub_id   = w.sub_id
WHERE r.status = 'R'
  AND w.status <> 'R'
ORDER BY
    w.status,
    w.base_id,
    w.lot_id,
    w.split_id,
    w.sub_id;

-- Update requirement status to match work order status
UPDATE r
SET r.status =
    CASE
        WHEN w.status IN ('C', 'X') THEN w.status
        WHEN w.status <> 'R' THEN w.status
        ELSE r.status
    END
FROM requirement r
JOIN work_order w
    ON r.workorder_base_id = w.base_id
   AND r.workorder_lot_id  = w.lot_id
   AND r.workorder_split_id = w.split_id
   AND r.workorder_sub_id   = w.sub_id
WHERE r.status = 'R'
  AND w.status <> 'R'
  AND r.status <> w.status;

SELECT @@ROWCOUNT AS requirement_rows_updated;

-- Validate
SELECT
    w.status AS work_order_status,
    r.status AS requirement_status,
    COUNT(*) AS row_count
FROM work_order w
JOIN requirement r
    ON r.workorder_base_id = w.base_id
   AND r.workorder_lot_id  = w.lot_id
   AND r.workorder_split_id = w.split_id
   AND r.workorder_sub_id   = w.sub_id
WHERE w.status <> 'R'
GROUP BY
    w.status,
    r.status
ORDER BY
    w.status,
    r.status;

-- COMMIT;
-- ROLLBACK;