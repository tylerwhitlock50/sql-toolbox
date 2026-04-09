/*
================================================================================
  GL BALANCE EXPORT - Period Balances with Account Classification
================================================================================
  Exports GL account balances from LEDGER_ACCOUNT_BALANCE with Z_GL_MAPPING
  enrichment. Returns one row per account per posting period.

  Use this for:
    - Importing GL data into Excel/BI tools
    - Period-over-period balance analysis
    - Feeding external reporting systems

  Replaces: database_scripts/old-finance-scripts/GL-import.sql
  Fixes:    - Parameterized (no hardcoded dates)
            - Z_GL_MAPPING date-effective join (no row duplication)
            - Removed hardcoded suspense adjustment
================================================================================
*/

--------------------------------------------------------------------------------
-- PARAMETERS: Update these before running
--------------------------------------------------------------------------------
DECLARE @DateFrom   date        = '2026-01-01';  -- Period start (inclusive)
DECLARE @DateTo     date        = '2026-04-09';  -- Period end (inclusive)
DECLARE @FSType     nvarchar(10)= NULL;          -- NULL = all, 'IS' = Income Statement, 'BS' = Balance Sheet
DECLARE @AccountID  nvarchar(30)= NULL;          -- NULL = all, or specific GL account
--------------------------------------------------------------------------------

SELECT
    BAL.ACCOUNT_ID,
    BAL.POSTING_DATE,
    ROUND(BAL.DEBIT_AMOUNT, 2)                             AS DEBIT_AMOUNT,
    ROUND(BAL.CREDIT_AMOUNT, 2)                            AS CREDIT_AMOUNT,
    ROUND(BAL.DEBIT_AMOUNT - BAL.CREDIT_AMOUNT, 2)        AS NET_AMOUNT,
    -- Source module breakdown
    ROUND(BAL.GEN_DEBIT_AMOUNT - BAL.GEN_CREDIT_AMOUNT, 2)   AS GEN_JOURNAL_NET,
    ROUND(BAL.RECV_DEBIT_AMOUNT - BAL.RECV_CREDIT_AMOUNT, 2) AS RECEIVABLES_NET,
    ROUND(BAL.PAYB_DEBIT_AMOUNT - BAL.PAYB_CREDIT_AMOUNT, 2) AS PAYABLES_NET,
    ROUND(BAL.CASH_DEBIT_AMOUNT - BAL.CASH_CREDIT_AMOUNT, 2) AS CASH_MGMT_NET,
    ROUND(BAL.BADJ_DEBIT_AMOUNT - BAL.BADJ_CREDIT_AMOUNT, 2) AS BANK_ADJ_NET,
    ROUND(BAL.DIR_DEBIT_AMOUNT - BAL.DIR_CREDIT_AMOUNT, 2)   AS DIRECT_JOURN_NET,
    ROUND(BAL.ADJ_DEBIT_AMOUNT - BAL.ADJ_CREDIT_AMOUNT, 2)   AS ADJUSTMENT_NET,
    -- Z_GL_MAPPING enrichment
    G.DESCRIPTION                AS ACCT_DESCRIPTION,
    G.ACCOUNT_CLASS,
    G.ACCOUNT_CAT_ID,
    G.POSTING_LEVEL,
    G.FS,
    G.FS_CAT,
    G.FS_COND,
    G.FS_DET,
    G.CATEGORY,
    G.CC_CAT,
    G.BREAK_CAT

FROM VFIN.dbo.LEDGER_ACCOUNT_BALANCE BAL
INNER JOIN VFIN.dbo.LEDGER_ACCOUNT ACCT
    ON ACCT.ACCOUNT_ID = BAL.ACCOUNT_ID
LEFT JOIN VECA.dbo.Z_GL_MAPPING G
    ON BAL.ACCOUNT_ID = G.ACCOUNT_ID
    AND BAL.POSTING_DATE >= G.EFFECTIVE_START_DATE
    AND BAL.POSTING_DATE < G.EFFECTIVE_END_DATE

WHERE ACCT.POSTING_LEVEL = 1
  AND BAL.POSTING_DATE >= @DateFrom
  AND BAL.POSTING_DATE <= @DateTo
  AND (@FSType IS NULL OR G.FS = @FSType)
  AND (@AccountID IS NULL OR BAL.ACCOUNT_ID = @AccountID)

ORDER BY BAL.ACCOUNT_ID, BAL.POSTING_DATE;
