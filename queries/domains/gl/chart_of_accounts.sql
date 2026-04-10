/*
================================================================================
  CHART OF ACCOUNTS
================================================================================
  Full chart of accounts combining VFIN's LEDGER_ACCOUNT with Z_GL_MAPPING
  account classification. Shows all posting-level accounts with their
  segment breakdown and reporting categories.

  Replaces: database_scripts/old-finance-scripts/chart_of_accounts.sql (was empty)
================================================================================
*/

--------------------------------------------------------------------------------
-- PARAMETERS: Update these before running
--------------------------------------------------------------------------------
DECLARE @ActiveOnly   bit         = 1;       -- 1 = active accounts only, 0 = all
DECLARE @FSType       nvarchar(10)= NULL;    -- NULL = all, 'IS' = Income Statement, 'BS' = Balance Sheet
DECLARE @AccountClass nvarchar(32)= NULL;    -- NULL = all, or 'Asset','Liability','Equity','Revenue','Expense'
DECLARE @AsOfDate     date        = GETDATE(); -- Date for Z_GL_MAPPING effective lookup
--------------------------------------------------------------------------------

SELECT
    A.ACCOUNT_ID,
    A.DESCRIPTION                AS ACCT_DESCRIPTION_VFIN,
    A.ACCOUNT_CLASS              AS ACCT_CLASS_VFIN,
    A.ACCOUNT_CAT_ID,
    A.NATURAL_ACCOUNT_ID,
    A.SEGMENT_VALUE_2,
    A.SEGMENT_VALUE_3,
    A.SEGMENT_VALUE_4,
    A.SEGMENT_VALUE_5,
    A.SEGMENT_VALUE_6,
    A.CURRENCY_ID,
    A.ACTIVE_FLAG,
    A.POSTING_LEVEL,
    A.REVALUE_TYPE,
    -- Z_GL_MAPPING enrichment
    G.DESCRIPTION                AS ACCT_DESCRIPTION_MAP,
    G.ACCOUNT_CLASS              AS ACCT_CLASS_MAP,
    G.FS,
    G.FS_CAT,
    G.FS_COND,
    G.FS_DET,
    G.CATEGORY,
    G.CC_CAT,
    G.BREAK_CAT,
    -- Flag mismatches between VFIN and Z_GL_MAPPING
    CASE WHEN G.ACCOUNT_ID IS NULL THEN 'NO MAPPING'
         WHEN A.DESCRIPTION <> G.DESCRIPTION THEN 'DESC MISMATCH'
         ELSE 'OK'
    END                          AS MAPPING_STATUS

FROM VFIN.dbo.LEDGER_ACCOUNT A

LEFT JOIN VECA.dbo.Z_GL_MAPPING G
    ON A.ACCOUNT_ID = G.ACCOUNT_ID
    AND @AsOfDate >= G.EFFECTIVE_START_DATE
    AND @AsOfDate < G.EFFECTIVE_END_DATE

WHERE A.ENTITY_ID = (SELECT TOP 1 ID FROM VFIN.dbo.SHARED_ENTITY)
  AND A.POSTING_LEVEL = 1
  AND (@ActiveOnly = 0 OR A.ACTIVE_FLAG = 1)
  AND (@FSType IS NULL OR G.FS = @FSType)
  AND (@AccountClass IS NULL OR G.ACCOUNT_CLASS = @AccountClass)

ORDER BY A.ACCOUNT_ID;
