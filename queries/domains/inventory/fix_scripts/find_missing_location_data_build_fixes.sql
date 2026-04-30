SELECT DISTINCT
    'INSERT INTO location (id, warehouse_id, description, type) VALUES ('''
    + i.location_id + ''', '''
    + i.warehouse_id + ''', ''DELETED LOCATION'', ''R'');' AS insert_stmt
FROM inventory_trans i
WHERE i.warehouse_id IS NOT NULL
  AND i.location_id IS NOT NULL
  AND i.part_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM location p
      WHERE p.warehouse_id = i.warehouse_id
        AND p.id = i.location_id
  );

SELECT
    'INSERT INTO part_location (
        part_id,
        warehouse_id,
        location_id,
        description,
        qty,
        status,
        locked,
        transit,
        last_count_date,
        purge_qty,
        def_backflush_loc,
        auto_issue_loc,
        def_inspect_loc
    ) VALUES ('''
    + REPLACE(i.part_id, '''', '''''') + ''', '''
    + REPLACE(i.warehouse_id, '''', '''''') + ''', '''
    + REPLACE(i.location_id, '''', '''''') + ''', '''
    + REPLACE(ISNULL(loc.description, 'DELETED LOCATION'), '''', '''''') + ''', '
    + '0, ''U'', ''Y'', ''N'', NULL, NULL, ''N'', ''N'', ''N'');'
FROM (
    SELECT DISTINCT part_id, warehouse_id, location_id
    FROM inventory_trans
    WHERE warehouse_id IS NOT NULL
      AND location_id IS NOT NULL
      AND part_id IS NOT NULL
) i
LEFT JOIN location loc
    ON loc.warehouse_id = i.warehouse_id
   AND loc.id = i.location_id
WHERE
    NOT EXISTS (
        SELECT 1
        FROM part p
        WHERE p.id = i.part_id
          AND p.status = 'O'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM part_location p
        WHERE p.warehouse_id = i.warehouse_id
          AND p.location_id = i.location_id
          AND p.part_id = i.part_id
    )
ORDER BY
    i.part_id,
    i.warehouse_id,
    i.location_id;