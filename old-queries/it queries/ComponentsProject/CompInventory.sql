WITH wh_totals AS (
  SELECT
    pl.PART_ID,
    pl.WAREHOUSE_ID,
    SUM(CASE WHEN pl.QTY > 0 THEN pl.QTY ELSE 0 END) AS wh_qty
  FROM dbo.PART_LOCATION pl
  GROUP BY pl.PART_ID, pl.WAREHOUSE_ID
),
loc_totals AS (
  SELECT
    pl.PART_ID,
    pl.WAREHOUSE_ID,
    pl.LOCATION_ID,
    SUM(CASE WHEN pl.QTY > 0 THEN pl.QTY ELSE 0 END) AS loc_qty
  FROM dbo.PART_LOCATION pl
  GROUP BY pl.PART_ID, pl.WAREHOUSE_ID, pl.LOCATION_ID
)
SELECT
  p.ID,
  p.DESCRIPTION,
  lt.LOCATION_ID,
  lt.loc_qty       AS LOCATION_QTY
FROM loc_totals lt
JOIN wh_totals wt
  ON wt.PART_ID = lt.PART_ID
 AND wt.WAREHOUSE_ID = lt.WAREHOUSE_ID
JOIN dbo.PART p
  ON p.ID = lt.PART_ID
WHERE lt.WAREHOUSE_ID = 'DISTRIBUTION'   -- warehouse filter
  AND wt.wh_qty > 50                     -- warehouse-level total threshold
  AND lt.loc_qty > 0                     -- hide zero/neg locations
ORDER BY wt.wh_qty DESC, lt.loc_qty DESC, p.ID, lt.LOCATION_ID;
