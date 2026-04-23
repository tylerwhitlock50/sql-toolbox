BEGIN TRANSACTION;

IF OBJECT_ID('tempdb..#demand_recon') IS NOT NULL
    DROP TABLE #demand_recon;

IF OBJECT_ID('tempdb..#site_counts') IS NOT NULL
    DROP TABLE #site_counts;

WITH open_sales_orders AS (
    SELECT
        l.part_id,
        SUM(
            CASE
                WHEN COALESCE(l.order_qty, 0) - COALESCE(l.total_shipped_qty, 0) > 0
                    THEN COALESCE(l.order_qty, 0) - COALESCE(l.total_shipped_qty, 0)
                ELSE 0
            END
        ) AS sales_order_demand
    FROM customer_order h
    JOIN cust_order_line l
        ON h.id = l.cust_order_id
    WHERE h.status IN ('R', 'F')
      AND l.line_status = 'A'
      AND l.part_id IS NOT NULL
      AND COALESCE(l.order_qty, 0) - COALESCE(l.total_shipped_qty, 0) > 0
    GROUP BY l.part_id
),
open_requirements AS (
    SELECT
        r.part_id,
        SUM(
            CASE
                WHEN COALESCE(r.calc_qty, 0) - COALESCE(r.issued_qty, 0) > 0
                    THEN COALESCE(r.calc_qty, 0) - COALESCE(r.issued_qty, 0)
                ELSE 0
            END
        ) AS requirement_demand
    FROM requirement r
    JOIN work_order w
        ON w.base_id  = r.workorder_base_id
       AND w.lot_id   = r.workorder_lot_id
       AND w.split_id = r.workorder_split_id
       AND w.sub_id   = r.workorder_sub_id
    WHERE w.type = 'W'
      AND w.status IN ('F', 'R')
      AND r.status IN ('F', 'R')
      AND r.part_id IS NOT NULL
    GROUP BY r.part_id
),
total_demand AS (
    SELECT
        COALESCE(so.part_id, req.part_id) AS part_id,
        COALESCE(so.sales_order_demand, 0) AS sales_order_demand,
        COALESCE(req.requirement_demand, 0) AS requirement_demand,
        COALESCE(so.sales_order_demand, 0) + COALESCE(req.requirement_demand, 0) AS calc_total_demand
    FROM open_sales_orders so
    FULL OUTER JOIN open_requirements req
        ON req.part_id = so.part_id
),
site_demand_sum AS (
    SELECT
        ps.part_id,
        SUM(COALESCE(ps.qty_in_demand, 0)) AS part_site_total_qty_in_demand
    FROM part_site ps
    GROUP BY ps.part_id
)
SELECT
    p.id AS part_id,
    COALESCE(p.qty_in_demand, 0) AS part_qty_in_demand,
    COALESCE(sds.part_site_total_qty_in_demand, 0) AS part_site_total_qty_in_demand,
    COALESCE(td.sales_order_demand, 0) AS sales_order_demand,
    COALESCE(td.requirement_demand, 0) AS requirement_demand,
    COALESCE(td.calc_total_demand, 0) AS calc_total_demand,
    COALESCE(p.qty_in_demand, 0) - COALESCE(td.calc_total_demand, 0) AS part_vs_calc_diff,
    COALESCE(sds.part_site_total_qty_in_demand, 0) - COALESCE(td.calc_total_demand, 0) AS site_vs_calc_diff,
    CASE
        WHEN COALESCE(p.qty_in_demand, 0) = COALESCE(td.calc_total_demand, 0)
         AND COALESCE(sds.part_site_total_qty_in_demand, 0) <> COALESCE(td.calc_total_demand, 0)
            THEN 'PART_SITE appears wrong'
        WHEN COALESCE(p.qty_in_demand, 0) <> COALESCE(td.calc_total_demand, 0)
         AND COALESCE(sds.part_site_total_qty_in_demand, 0) = COALESCE(td.calc_total_demand, 0)
            THEN 'PART appears wrong'
        WHEN COALESCE(p.qty_in_demand, 0) <> COALESCE(td.calc_total_demand, 0)
         AND COALESCE(sds.part_site_total_qty_in_demand, 0) <> COALESCE(td.calc_total_demand, 0)
            THEN 'Both PART and PART_SITE differ from calculated demand'
        ELSE 'No issue'
    END AS likely_issue
INTO #demand_recon
FROM part p
LEFT JOIN total_demand td
    ON td.part_id = p.id
LEFT JOIN site_demand_sum sds
    ON sds.part_id = p.id
WHERE
    COALESCE(p.qty_in_demand, 0) <> COALESCE(td.calc_total_demand, 0)
    OR COALESCE(sds.part_site_total_qty_in_demand, 0) <> COALESCE(td.calc_total_demand, 0);

SELECT
    ps.part_id,
    COUNT(*) AS site_count
INTO #site_counts
FROM part_site ps
GROUP BY ps.part_id;

-- Review mismatches
SELECT *
FROM #demand_recon
ORDER BY ABS(site_vs_calc_diff) DESC, part_id;

SELECT
    likely_issue,
    COUNT(*) AS row_count
FROM #demand_recon
GROUP BY likely_issue
ORDER BY row_count DESC;

SELECT
    sc.site_count,
    COUNT(*) AS part_count
FROM #demand_recon dr
JOIN #site_counts sc
    ON sc.part_id = dr.part_id
GROUP BY sc.site_count
ORDER BY sc.site_count;

--------------------------------------------------
-- STEP 1: Update PART_SITE first, but only for single-site parts
--------------------------------------------------
UPDATE ps
SET ps.qty_in_demand = dr.calc_total_demand
FROM part_site ps
JOIN #demand_recon dr
    ON dr.part_id = ps.part_id
JOIN #site_counts sc
    ON sc.part_id = ps.part_id
WHERE sc.site_count = 1
  AND COALESCE(ps.qty_in_demand, 0) <> dr.calc_total_demand;

SELECT @@ROWCOUNT AS part_site_rows_updated_single_site_only;

--------------------------------------------------
-- STEP 2: Update PART
--------------------------------------------------
UPDATE p
SET p.qty_in_demand = dr.calc_total_demand
FROM part p
JOIN #demand_recon dr
    ON dr.part_id = p.id
WHERE COALESCE(p.qty_in_demand, 0) <> dr.calc_total_demand;

SELECT @@ROWCOUNT AS part_rows_updated;

--------------------------------------------------
-- VALIDATION
--------------------------------------------------
WITH open_sales_orders AS (
    SELECT
        l.part_id,
        SUM(
            CASE
                WHEN COALESCE(l.order_qty, 0) - COALESCE(l.total_shipped_qty, 0) > 0
                    THEN COALESCE(l.order_qty, 0) - COALESCE(l.total_shipped_qty, 0)
                ELSE 0
            END
        ) AS sales_order_demand
    FROM customer_order h
    JOIN cust_order_line l
        ON h.id = l.cust_order_id
    WHERE h.status IN ('R', 'F')
      AND l.line_status = 'A'
      AND l.part_id IS NOT NULL
      AND COALESCE(l.order_qty, 0) - COALESCE(l.total_shipped_qty, 0) > 0
    GROUP BY l.part_id
),
open_requirements AS (
    SELECT
        r.part_id,
        SUM(
            CASE
                WHEN COALESCE(r.calc_qty, 0) - COALESCE(r.issued_qty, 0) > 0
                    THEN COALESCE(r.calc_qty, 0) - COALESCE(r.issued_qty, 0)
                ELSE 0
            END
        ) AS requirement_demand
    FROM requirement r
    JOIN work_order w
        ON w.base_id  = r.workorder_base_id
       AND w.lot_id   = r.workorder_lot_id
       AND w.split_id = r.workorder_split_id
       AND w.sub_id   = r.workorder_sub_id
       AND w.type = r.workorder_type
    WHERE w.type = 'W'
      AND w.status IN ('F', 'R')
      AND r.status IN ('F', 'R')
      AND r.part_id IS NOT NULL
    GROUP BY r.part_id
),
total_demand AS (
    SELECT
        COALESCE(so.part_id, req.part_id) AS part_id,
        COALESCE(so.sales_order_demand, 0) AS sales_order_demand,
        COALESCE(req.requirement_demand, 0) AS requirement_demand,
        COALESCE(so.sales_order_demand, 0) + COALESCE(req.requirement_demand, 0) AS calc_total_demand
    FROM open_sales_orders so
    FULL OUTER JOIN open_requirements req
        ON req.part_id = so.part_id
),
site_demand_sum AS (
    SELECT
        ps.part_id,
        SUM(COALESCE(ps.qty_in_demand, 0)) AS part_site_total_qty_in_demand
    FROM part_site ps
    GROUP BY ps.part_id
)
SELECT
    p.id AS part_id,
    COALESCE(p.qty_in_demand, 0) AS part_qty_in_demand,
    COALESCE(sds.part_site_total_qty_in_demand, 0) AS part_site_total_qty_in_demand,
    COALESCE(td.sales_order_demand, 0) AS sales_order_demand,
    COALESCE(td.requirement_demand, 0) AS requirement_demand,
    COALESCE(td.calc_total_demand, 0) AS calc_total_demand,
    COALESCE(p.qty_in_demand, 0) - COALESCE(td.calc_total_demand, 0) AS part_vs_calc_diff,
    COALESCE(sds.part_site_total_qty_in_demand, 0) - COALESCE(td.calc_total_demand, 0) AS site_vs_calc_diff
FROM part p
LEFT JOIN total_demand td
    ON td.part_id = p.id
LEFT JOIN site_demand_sum sds
    ON sds.part_id = p.id
WHERE
    COALESCE(p.qty_in_demand, 0) <> COALESCE(td.calc_total_demand, 0)
    OR COALESCE(sds.part_site_total_qty_in_demand, 0) <> COALESCE(td.calc_total_demand, 0)
ORDER BY ABS(COALESCE(sds.part_site_total_qty_in_demand, 0) - COALESCE(td.calc_total_demand, 0)) DESC,
         p.id;

-- COMMIT;
-- ROLLBACK;

SELECT @@TRANCOUNT AS open_transactions;
SELECT XACT_STATE() AS transaction_state;