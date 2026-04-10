/*
================================================================================
  DIAGNOSE VECA/VFIN OVERLAP
================================================================================
  Diagnostic queries to identify how VECA and VFIN distribution tables overlap.
  Run these against a small date range first, then use the findings to choose
  the right @DedupeMode in gl_posting_map.sql.

  The script runs several diagnostic result sets in order. Look at each one.
================================================================================
*/

DECLARE @DateFrom date = '2026-03-01';  -- Small window for diagnostics
DECLARE @DateTo   date = '2026-03-31';

--------------------------------------------------------------------------------
-- DIAGNOSTIC 1: DISTRIBUTION_CONTEXT value distribution in VFIN
-- What values does DISTRIBUTION_CONTEXT actually take? This field is the most
-- likely indicator of "came from exchange" vs "native VFIN entry"
--------------------------------------------------------------------------------
SELECT 'VFIN_RECV' AS TABLE_NAME, DISTRIBUTION_CONTEXT, COUNT(*) AS ROW_COUNT
FROM VFIN.dbo.RECEIVABLES_RECEIVABLE_DIST
WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
GROUP BY DISTRIBUTION_CONTEXT
UNION ALL
SELECT 'VFIN_PAYB', DISTRIBUTION_CONTEXT, COUNT(*)
FROM VFIN.dbo.PAYABLES_PAYABLE_DIST
WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
GROUP BY DISTRIBUTION_CONTEXT
UNION ALL
SELECT 'VFIN_PAYMENT', DISTRIBUTION_CONTEXT, COUNT(*)
FROM VFIN.dbo.CASHMGMT_PAYMENT_DIST
WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
GROUP BY DISTRIBUTION_CONTEXT
UNION ALL
SELECT 'VFIN_GEN', DISTRIBUTION_CONTEXT, COUNT(*)
FROM VFIN.dbo.LEDGER_GEN_JOURN_DIST
WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
GROUP BY DISTRIBUTION_CONTEXT
UNION ALL
SELECT 'VFIN_BANKADJ', DISTRIBUTION_CONTEXT, COUNT(*)
FROM VFIN.dbo.CASHMGMT_BANK_ADJ_DIST
WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
GROUP BY DISTRIBUTION_CONTEXT
UNION ALL
SELECT 'VFIN_DIRECT', DISTRIBUTION_CONTEXT, COUNT(*)
FROM VFIN.dbo.LEDGER_DIRECT_JOURN_DIST
WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
GROUP BY DISTRIBUTION_CONTEXT
ORDER BY TABLE_NAME, DISTRIBUTION_CONTEXT;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 2: AR Invoice overlap - same INVOICE_IDs in both databases?
-- If this returns rows, those AR invoices exist in BOTH VECA and VFIN.
-- This confirms whether VECA.RECEIVABLE_DIST and VFIN.RECEIVABLES_RECEIVABLE_DIST
-- are duplicate data for the same invoices.
--------------------------------------------------------------------------------
SELECT TOP 20
    V.INVOICE_ID,
    V.POSTING_DATE AS VECA_POSTING_DATE,
    F.POSTING_DATE AS VFIN_POSTING_DATE,
    V.GL_ACCOUNT_ID AS VECA_ACCOUNT,
    F.ACCOUNT_ID AS VFIN_ACCOUNT,
    CASE WHEN V.AMOUNT_TYPE='DR' THEN V.AMOUNT ELSE -V.AMOUNT END AS VECA_NET,
    ISNULL(F.DEBIT_AMOUNT,0) - ISNULL(F.CREDIT_AMOUNT,0) AS VFIN_NET,
    F.DISTRIBUTION_CONTEXT AS VFIN_DIST_CONTEXT,
    F.REFERENCE AS VFIN_REFERENCE
FROM VECA.dbo.RECEIVABLE_DIST V
INNER JOIN VFIN.dbo.RECEIVABLES_RECEIVABLE_DIST F
    ON V.INVOICE_ID = F.INVOICE_ID
    AND V.GL_ACCOUNT_ID = F.ACCOUNT_ID
    AND V.DIST_NO = F.DIST_NO
    AND V.ENTRY_NO = F.ENTRY_NO
WHERE V.POSTING_DATE BETWEEN @DateFrom AND @DateTo
ORDER BY V.INVOICE_ID;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 3: AR Invoice counts - how much of each side is unique?
-- Shows: invoices only in VECA, only in VFIN, or in both.
--------------------------------------------------------------------------------
WITH VECA_INV AS (
    SELECT DISTINCT INVOICE_ID
    FROM VECA.dbo.RECEIVABLE_DIST
    WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
),
VFIN_INV AS (
    SELECT DISTINCT INVOICE_ID
    FROM VFIN.dbo.RECEIVABLES_RECEIVABLE_DIST
    WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
)
SELECT
    'In both VECA and VFIN' AS OVERLAP_STATUS,
    COUNT(*) AS INVOICE_COUNT
FROM VECA_INV V
INNER JOIN VFIN_INV F ON V.INVOICE_ID = F.INVOICE_ID
UNION ALL
SELECT 'Only in VECA', COUNT(*)
FROM VECA_INV V
WHERE NOT EXISTS (SELECT 1 FROM VFIN_INV F WHERE F.INVOICE_ID = V.INVOICE_ID)
UNION ALL
SELECT 'Only in VFIN', COUNT(*)
FROM VFIN_INV F
WHERE NOT EXISTS (SELECT 1 FROM VECA_INV V WHERE V.INVOICE_ID = F.INVOICE_ID);


--------------------------------------------------------------------------------
-- DIAGNOSTIC 4: Are VECA manufacturing postings ALSO in VFIN?
-- This checks if WIP/SHIPMENT/PURCHASE type data shows up in VFIN anywhere.
-- Compares total dollars by account from each source for the date range.
--------------------------------------------------------------------------------
WITH VECA_TOTALS AS (
    SELECT GL_ACCOUNT_ID AS ACCT,
           SUM(CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE -AMOUNT END) AS VECA_NET
    FROM (
        SELECT GL_ACCOUNT_ID, AMOUNT_TYPE, AMOUNT FROM VECA.dbo.WIP_ISSUE_DIST WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
        UNION ALL SELECT GL_ACCOUNT_ID, AMOUNT_TYPE, AMOUNT FROM VECA.dbo.WIP_RECEIPT_DIST WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
        UNION ALL SELECT GL_ACCOUNT_ID, AMOUNT_TYPE, AMOUNT FROM VECA.dbo.SHIPMENT_DIST WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
        UNION ALL SELECT GL_ACCOUNT_ID, AMOUNT_TYPE, AMOUNT FROM VECA.dbo.PURCHASE_DIST WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
        UNION ALL SELECT GL_ACCOUNT_ID, AMOUNT_TYPE, AMOUNT FROM VECA.dbo.ADJUSTMENT_DIST WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
        UNION ALL SELECT GL_ACCOUNT_ID, AMOUNT_TYPE, AMOUNT FROM VECA.dbo.INDIRECT_DIST WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
    ) X
    GROUP BY GL_ACCOUNT_ID
),
VFIN_BAL AS (
    SELECT ACCOUNT_ID AS ACCT,
           SUM(DEBIT_AMOUNT - CREDIT_AMOUNT) AS VFIN_BAL_NET,
           SUM(GEN_DEBIT_AMOUNT - GEN_CREDIT_AMOUNT) AS VFIN_GEN_NET,
           SUM(DIR_DEBIT_AMOUNT - DIR_CREDIT_AMOUNT) AS VFIN_DIR_NET
    FROM VFIN.dbo.LEDGER_ACCOUNT_BALANCE
    WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
    GROUP BY ACCOUNT_ID
)
SELECT TOP 50
    COALESCE(V.ACCT, F.ACCT) AS ACCOUNT_ID,
    ROUND(V.VECA_NET, 2)     AS VECA_MFG_NET,
    ROUND(F.VFIN_BAL_NET, 2) AS VFIN_BALANCE_NET,
    ROUND(F.VFIN_GEN_NET, 2) AS VFIN_GEN_JOURNAL_NET,
    ROUND(F.VFIN_DIR_NET, 2) AS VFIN_DIRECT_JOURNAL_NET,
    ROUND(ISNULL(V.VECA_NET,0) - ISNULL(F.VFIN_BAL_NET,0), 2) AS DIFFERENCE
FROM VECA_TOTALS V
FULL OUTER JOIN VFIN_BAL F ON V.ACCT = F.ACCT
WHERE ABS(ISNULL(V.VECA_NET,0)) > 0.01 OR ABS(ISNULL(F.VFIN_BAL_NET,0)) > 0.01
ORDER BY ABS(ISNULL(V.VECA_NET,0)) DESC;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 5: Sample VFIN RECEIVABLES rows showing REFERENCE patterns
-- Look at actual REFERENCE values to find the pattern that indicates
-- "exchanged from VECA" entries.
--------------------------------------------------------------------------------
SELECT TOP 30
    INVOICE_ID,
    ACCOUNT_ID,
    POSTING_DATE,
    DISTRIBUTION_CONTEXT,
    REFERENCE,
    DEBIT_AMOUNT,
    CREDIT_AMOUNT
FROM VFIN.dbo.RECEIVABLES_RECEIVABLE_DIST
WHERE POSTING_DATE BETWEEN @DateFrom AND @DateTo
ORDER BY POSTING_DATE DESC;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 6: Does VFIN.PAYABLES_PAYABLE have SITE_ID populated?
-- SITE_ID is a VECA concept. If VFIN AP invoices have SITE_ID, they're
-- tied to a VECA site (likely originated there or created per-site).
--------------------------------------------------------------------------------
SELECT
    'VFIN.PAYABLES_PAYABLE'  AS TABLE_NAME,
    SITE_ID,
    COUNT(*) AS INVOICE_COUNT
FROM VFIN.dbo.PAYABLES_PAYABLE
GROUP BY SITE_ID
ORDER BY INVOICE_COUNT DESC;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 7: LEDGER_GEN_JOURNAL SITE_ID distribution
-- Same question for general journals - are most entries site-tagged?
--------------------------------------------------------------------------------
SELECT
    'VFIN.LEDGER_GEN_JOURNAL' AS TABLE_NAME,
    SITE_ID,
    COUNT(*) AS JOURNAL_COUNT
FROM VFIN.dbo.LEDGER_GEN_JOURNAL
GROUP BY SITE_ID
ORDER BY JOURNAL_COUNT DESC;
