BEGIN TRANSACTION;

IF OBJECT_ID('tempdb..#qty_recon') IS NOT NULL
    DROP TABLE #qty_recon;

IF OBJECT_ID('tempdb..#site_counts') IS NOT NULL
    DROP TABLE #site_counts;

WITH trans AS (
    SELECT
        it.part_id,
        SUM(CASE WHEN it.type = 'I' THEN it.qty ELSE -it.qty END) AS trans_qty_on_hand
    FROM INVENTORY_TRANS it
    GROUP BY it.part_id
),
site_sum AS (
    SELECT
        ps.part_id,
        SUM(COALESCE(ps.qty_on_hand, 0)) AS part_site_total_qty_on_hand
    FROM PART_SITE ps
    GROUP BY ps.part_id
)
SELECT
    p.id AS part_id,
    COALESCE(p.qty_on_hand, 0) AS part_qty_on_hand,
    COALESCE(ss.part_site_total_qty_on_hand, 0) AS part_site_total_qty_on_hand,
    COALESCE(t.trans_qty_on_hand, 0) AS trans_qty_on_hand,
    COALESCE(p.qty_on_hand, 0) - COALESCE(t.trans_qty_on_hand, 0) AS part_vs_trans_diff,
    COALESCE(ss.part_site_total_qty_on_hand, 0) - COALESCE(t.trans_qty_on_hand, 0) AS site_vs_trans_diff,
    CASE
        WHEN COALESCE(p.qty_on_hand, 0) = COALESCE(t.trans_qty_on_hand, 0)
         AND COALESCE(ss.part_site_total_qty_on_hand, 0) <> COALESCE(t.trans_qty_on_hand, 0)
            THEN 'PART_SITE appears wrong'
        WHEN COALESCE(p.qty_on_hand, 0) <> COALESCE(t.trans_qty_on_hand, 0)
         AND COALESCE(ss.part_site_total_qty_on_hand, 0) = COALESCE(t.trans_qty_on_hand, 0)
            THEN 'PART appears wrong'
        WHEN COALESCE(p.qty_on_hand, 0) <> COALESCE(t.trans_qty_on_hand, 0)
         AND COALESCE(ss.part_site_total_qty_on_hand, 0) <> COALESCE(t.trans_qty_on_hand, 0)
            THEN 'Both PART and PART_SITE differ from transactions'
        ELSE 'No issue'
    END AS likely_issue
INTO #qty_recon
FROM PART p
LEFT JOIN trans t
    ON t.part_id = p.id
LEFT JOIN site_sum ss
    ON ss.part_id = p.id
WHERE
    COALESCE(p.qty_on_hand, 0) <> COALESCE(t.trans_qty_on_hand, 0)
    OR COALESCE(ss.part_site_total_qty_on_hand, 0) <> COALESCE(t.trans_qty_on_hand, 0);

SELECT
    ps.part_id,
    COUNT(*) AS site_count
INTO #site_counts
FROM PART_SITE ps
GROUP BY ps.part_id;

-- Review what will be touched
SELECT *
FROM #qty_recon
ORDER BY ABS(site_vs_trans_diff) DESC, part_id;

SELECT
    likely_issue,
    COUNT(*) AS row_count
FROM #qty_recon
GROUP BY likely_issue
ORDER BY row_count DESC;

SELECT
    sc.site_count,
    COUNT(*) AS part_count
FROM #qty_recon qr
JOIN #site_counts sc
    ON sc.part_id = qr.part_id
GROUP BY sc.site_count
ORDER BY sc.site_count;



--------------------------------------------------
-- STEP 2: Update PART_SITE only for single-site parts
--------------------------------------------------
select 'part_site'
UPDATE ps
SET ps.qty_on_hand = qr.trans_qty_on_hand
FROM PART_SITE ps
JOIN #qty_recon qr
    ON qr.part_id = ps.part_id
JOIN #site_counts sc
    ON sc.part_id = ps.part_id
WHERE sc.site_count = 1
  AND COALESCE(ps.qty_on_hand, 0) <> qr.trans_qty_on_hand;

SELECT @@ROWCOUNT AS part_site_rows_updated_single_site_only;


--------------------------------------------------
-- STEP 1: Update PART from transaction total
--------------------------------------------------
select 'part' 

UPDATE p
SET p.qty_on_hand = qr.trans_qty_on_hand
FROM PART p
JOIN #qty_recon qr
    ON qr.part_id = p.id
WHERE COALESCE(p.qty_on_hand, 0) <> qr.trans_qty_on_hand;

SELECT @@ROWCOUNT AS part_rows_updated;

--------------------------------------------------
-- VALIDATION
--------------------------------------------------
WITH trans AS (
    SELECT
        it.part_id,
        SUM(CASE WHEN it.type = 'I' THEN it.qty ELSE -it.qty END) AS trans_qty_on_hand
    FROM INVENTORY_TRANS it
    GROUP BY it.part_id
),
site_sum AS (
    SELECT
        ps.part_id,
        SUM(COALESCE(ps.qty_on_hand, 0)) AS part_site_total_qty_on_hand
    FROM PART_SITE ps
    GROUP BY ps.part_id
)
SELECT
    p.id AS part_id,
    COALESCE(p.qty_on_hand, 0) AS part_qty_on_hand,
    COALESCE(ss.part_site_total_qty_on_hand, 0) AS part_site_total_qty_on_hand,
    COALESCE(t.trans_qty_on_hand, 0) AS trans_qty_on_hand,
    COALESCE(p.qty_on_hand, 0) - COALESCE(t.trans_qty_on_hand, 0) AS part_vs_trans_diff,
    COALESCE(ss.part_site_total_qty_on_hand, 0) - COALESCE(t.trans_qty_on_hand, 0) AS site_vs_trans_diff
FROM PART p
LEFT JOIN trans t
    ON t.part_id = p.id
LEFT JOIN site_sum ss
    ON ss.part_id = p.id
WHERE
    COALESCE(p.qty_on_hand, 0) <> COALESCE(t.trans_qty_on_hand, 0)
    OR COALESCE(ss.part_site_total_qty_on_hand, 0) <> COALESCE(t.trans_qty_on_hand, 0)
ORDER BY ABS(COALESCE(ss.part_site_total_qty_on_hand, 0) - COALESCE(t.trans_qty_on_hand, 0)) DESC,
         p.id;

--COMMIT;
--ROLLBACK;

SELECT @@TRANCOUNT AS open_transactions;