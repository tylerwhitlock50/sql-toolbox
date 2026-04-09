/*
================================================================================
  TRIAL BALANCE
================================================================================
  Produces a trial balance as of a cutoff date with proper BS/IS split:
    - Balance Sheet accounts (1xxx-3xxx): cumulative balance through cutoff
    - Income Statement accounts (4xxx+): YTD balance from fiscal year start

  Includes Z_GL_MAPPING account classification for reporting.

  Replaces: database_scripts/old-finance-scripts/tb-export.sql
  Fixes:    - Parameterized dates (no more hardcoding)
            - Z_GL_MAPPING date-effective join (no row duplication)
            - Removed hardcoded suspense adjustment
================================================================================
*/

--------------------------------------------------------------------------------
-- PARAMETERS: Update these before running
--------------------------------------------------------------------------------
DECLARE @CutoffDate      date = '2026-03-31';  -- Trial balance as-of date
DECLARE @FiscalYearStart date = '2026-01-01';  -- First day of fiscal year (for IS accounts)
--------------------------------------------------------------------------------

SELECT
    TB.ACCOUNT_ID,
    TB.DESCRIPTION,
    ROUND(TB.BALANCE, 2)         AS BALANCE,
    G.ACCOUNT_CLASS,
    G.FS,
    G.FS_CAT,
    G.FS_COND,
    G.FS_DET,
    G.CATEGORY,
    G.CC_CAT,
    G.BREAK_CAT,
    TB.ACCOUNT_TYPE

FROM (
    --------------------------------------------------------------------------
    -- Balance Sheet accounts (account IDs starting with 1, 2, or 3)
    -- Cumulative balance from beginning of time through cutoff date
    --------------------------------------------------------------------------
    SELECT
        BAL.ACCOUNT_ID,
        ACCT.DESCRIPTION,
        SUM(BAL.DEBIT_AMOUNT - BAL.CREDIT_AMOUNT) AS BALANCE,
        'BS' AS ACCOUNT_TYPE
    FROM VFIN.dbo.LEDGER_ACCOUNT_BALANCE BAL
    INNER JOIN VFIN.dbo.LEDGER_ACCOUNT ACCT
        ON ACCT.ACCOUNT_ID = BAL.ACCOUNT_ID
    WHERE ACCT.POSTING_LEVEL = 1
      AND BAL.POSTING_DATE <= @CutoffDate
      AND LEFT(ACCT.ACCOUNT_ID, 1) < '4'
    GROUP BY BAL.ACCOUNT_ID, ACCT.DESCRIPTION

    UNION ALL

    --------------------------------------------------------------------------
    -- Income Statement accounts (account IDs starting with 4+)
    -- YTD balance from fiscal year start through cutoff date
    --------------------------------------------------------------------------
    SELECT
        BAL.ACCOUNT_ID,
        ACCT.DESCRIPTION,
        SUM(BAL.DEBIT_AMOUNT - BAL.CREDIT_AMOUNT) AS BALANCE,
        'IS' AS ACCOUNT_TYPE
    FROM VFIN.dbo.LEDGER_ACCOUNT_BALANCE BAL
    INNER JOIN VFIN.dbo.LEDGER_ACCOUNT ACCT
        ON ACCT.ACCOUNT_ID = BAL.ACCOUNT_ID
    WHERE ACCT.POSTING_LEVEL = 1
      AND BAL.POSTING_DATE <= @CutoffDate
      AND BAL.POSTING_DATE >= @FiscalYearStart
      AND LEFT(ACCT.ACCOUNT_ID, 1) >= '4'
    GROUP BY BAL.ACCOUNT_ID, ACCT.DESCRIPTION

) AS TB

LEFT JOIN VECA.dbo.Z_GL_MAPPING G
    ON TB.ACCOUNT_ID = G.ACCOUNT_ID
    AND @CutoffDate >= G.EFFECTIVE_START_DATE
    AND @CutoffDate < G.EFFECTIVE_END_DATE

ORDER BY TB.ACCOUNT_ID;
