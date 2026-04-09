/*
================================================================================
  GL POSTING MAP - ENRICHED (with Z_GL_MAPPING Account Classification)
================================================================================
  Wraps gl_posting_map.sql and joins to VECA.dbo.Z_GL_MAPPING for account
  classification. Adds financial statement groupings, categories, and
  reporting hierarchies to every posting row.

  Z_GL_MAPPING columns added:
    ACCT_DESCRIPTION   - GL account description
    ACCOUNT_CLASS      - Asset, Liability, Equity, Revenue, Expense
    ACCOUNT_CAT_ID     - Account category ID
    POSTING_LEVEL      - Whether account is a posting-level account
    FS                 - Financial statement (BS or IS)
    FS_CAT             - Financial statement category
    FS_COND            - Financial statement condensed category
    FS_DET             - Financial statement detail category
    CATEGORY           - Reporting category
    CC_CAT             - Cost center category
    BREAK_CAT          - Breakout category

  Replaces: old-queries/Queries/GL Posting Level Detail.sql
            database_scripts/old-finance-scripts/gl_detail.sql
================================================================================
*/

--------------------------------------------------------------------------------
-- PARAMETERS: Update these before running
--------------------------------------------------------------------------------
DECLARE @DateFrom     date        = '2026-01-01';  -- Start of date range (inclusive)
DECLARE @DateTo       date        = '2026-04-09';  -- End of date range (inclusive)
DECLARE @PostedOnly   bit         = 1;             -- 1 = posted only, 0 = include unposted VECA
DECLARE @SourceDB     nvarchar(4) = NULL;          -- NULL = both, 'VECA', or 'VFIN'
DECLARE @JournalType  nvarchar(20)= NULL;          -- NULL = all, or specific type like 'VFIN_RECV'
DECLARE @AccountID    nvarchar(30)= NULL;          -- NULL = all, or specific GL account
DECLARE @FSType       nvarchar(10)= NULL;          -- NULL = all, 'IS' = Income Statement, 'BS' = Balance Sheet
--------------------------------------------------------------------------------

SELECT
    M.SOURCE_DB,
    M.JOURNAL_TYPE,
    M.DOCUMENT_ID,
    M.WO_TYPE,
    M.WO_BASE_ID,
    M.WO_LOT_ID,
    M.WO_SPLIT_ID,
    M.WO_SUB_ID,
    M.LINKED_INVOICE_ID,
    M.GL_ACCOUNT_ID,
    ROUND(M.DEBIT_AMOUNT, 2)    AS DEBIT_AMOUNT,
    ROUND(M.CREDIT_AMOUNT, 2)   AS CREDIT_AMOUNT,
    ROUND(M.NET_AMOUNT, 2)      AS NET_AMOUNT,
    M.POSTING_DATE,
    M.CREATED_DATE,
    M.REFERENCE,
    M.SITE_OR_ENTITY,
    M.CURRENCY_ID,
    M.POSTING_STATUS,
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

FROM (
    -- Paste or reference gl_posting_map.sql inner query here.
    -- For maintainability, consider creating this as a view on the server.
    -- Below is the full inline version:

    ----------------------------------------------------------------------------
    -- VECA: WIP Issue Distributions
    ----------------------------------------------------------------------------
    SELECT
        'VECA' AS SOURCE_DB, 'VECA_WIP_ISSUE' AS JOURNAL_TYPE,
        NULL AS DOCUMENT_ID,
        WORKORDER_TYPE AS WO_TYPE, WORKORDER_BASE_ID AS WO_BASE_ID,
        WORKORDER_LOT_ID AS WO_LOT_ID, WORKORDER_SPLIT_ID AS WO_SPLIT_ID,
        WORKORDER_SUB_ID AS WO_SUB_ID, NULL AS LINKED_INVOICE_ID,
        GL_ACCOUNT_ID,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END AS DEBIT_AMOUNT,
        CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END AS CREDIT_AMOUNT,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END AS NET_AMOUNT,
        POSTING_DATE, CREATE_DATE AS CREATED_DATE, NULL AS REFERENCE,
        SITE_ID AS SITE_OR_ENTITY, CURRENCY_ID, POSTING_STATUS
    FROM VECA.dbo.WIP_ISSUE_DIST

    UNION ALL

    ----------------------------------------------------------------------------
    -- VECA: WIP Receipt Distributions
    ----------------------------------------------------------------------------
    SELECT
        'VECA', 'VECA_WIP_RCPT', NULL,
        WORKORDER_TYPE, WORKORDER_BASE_ID, WORKORDER_LOT_ID,
        WORKORDER_SPLIT_ID, WORKORDER_SUB_ID, NULL,
        GL_ACCOUNT_ID,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END,
        CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END,
        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS
    FROM VECA.dbo.WIP_RECEIPT_DIST

    UNION ALL

    ----------------------------------------------------------------------------
    -- VECA: Shipment Distributions
    ----------------------------------------------------------------------------
    SELECT
        'VECA', 'VECA_SHIPMENT', CUST_ORDER_ID,
        NULL, NULL, NULL, NULL, NULL, NULL,
        GL_ACCOUNT_ID,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END,
        CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END,
        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS
    FROM VECA.dbo.SHIPMENT_DIST

    UNION ALL

    ----------------------------------------------------------------------------
    -- VECA: Receivable Distributions
    ----------------------------------------------------------------------------
    SELECT
        'VECA', 'VECA_RECV', INVOICE_ID,
        NULL, NULL, NULL, NULL, NULL, NULL,
        GL_ACCOUNT_ID,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END,
        CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END,
        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS
    FROM VECA.dbo.RECEIVABLE_DIST

    UNION ALL

    ----------------------------------------------------------------------------
    -- VECA: Purchase Distributions
    ----------------------------------------------------------------------------
    SELECT
        'VECA', 'VECA_PURCHASE', PURC_ORDER_ID,
        NULL, NULL, NULL, NULL, NULL, NULL,
        GL_ACCOUNT_ID,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END,
        CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END,
        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS
    FROM VECA.dbo.PURCHASE_DIST

    UNION ALL

    ----------------------------------------------------------------------------
    -- VECA: Adjustment Distributions
    ----------------------------------------------------------------------------
    SELECT
        'VECA', 'VECA_ADJUST', CAST(TRANSACTION_ID AS nvarchar(30)),
        NULL, NULL, NULL, NULL, NULL, NULL,
        GL_ACCOUNT_ID,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END,
        CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END,
        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS
    FROM VECA.dbo.ADJUSTMENT_DIST

    UNION ALL

    ----------------------------------------------------------------------------
    -- VECA: Indirect Distributions
    ----------------------------------------------------------------------------
    SELECT
        'VECA', 'VECA_INDIRECT', CAST(TRANSACTION_ID AS nvarchar(30)),
        NULL, NULL, NULL, NULL, NULL, NULL,
        GL_ACCOUNT_ID,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END,
        CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END,
        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS
    FROM VECA.dbo.INDIRECT_DIST

    UNION ALL

    ----------------------------------------------------------------------------
    -- VECA: General Journal Distributions
    ----------------------------------------------------------------------------
    SELECT
        'VECA', 'VECA_GJ', GJ_ID,
        NULL, NULL, NULL, NULL, NULL, NULL,
        GL_ACCOUNT_ID,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END,
        CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END,
        CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END,
        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS
    FROM VECA.dbo.GJ_DIST

    UNION ALL

    ----------------------------------------------------------------------------
    -- VFIN: Receivable Distributions
    ----------------------------------------------------------------------------
    SELECT
        'VFIN', 'VFIN_RECV', D.INVOICE_ID,
        NULL, NULL, NULL, NULL, NULL, NULL,
        D.ACCOUNT_ID,
        ISNULL(D.DEBIT_AMOUNT, 0), ISNULL(D.CREDIT_AMOUNT, 0),
        ISNULL(D.DEBIT_AMOUNT, 0) - ISNULL(D.CREDIT_AMOUNT, 0),
        D.POSTING_DATE, D.RECORD_CREATED,
        ISNULL(D.REFERENCE, R.CUSTOMER_ID),
        D.INVOICE_ENTITY_ID, D.CURRENCY_ID, 'P'
    FROM VFIN.dbo.RECEIVABLES_RECEIVABLE_DIST D
    JOIN VFIN.dbo.RECEIVABLES_RECEIVABLE R
        ON D.INVOICE_ENTITY_ID = R.ENTITY_ID AND D.INVOICE_ID = R.INVOICE_ID

    UNION ALL

    ----------------------------------------------------------------------------
    -- VFIN: Payable Distributions
    ----------------------------------------------------------------------------
    SELECT
        'VFIN', 'VFIN_PAYB', D.INVOICE_ID,
        NULL, NULL, NULL, NULL, NULL, NULL,
        D.ACCOUNT_ID,
        ISNULL(D.DEBIT_AMOUNT, 0), ISNULL(D.CREDIT_AMOUNT, 0),
        ISNULL(D.DEBIT_AMOUNT, 0) - ISNULL(D.CREDIT_AMOUNT, 0),
        D.POSTING_DATE, D.RECORD_CREATED,
        ISNULL(D.REFERENCE, P.SUPPLIER_ID),
        D.INVOICE_ENTITY_ID, D.CURRENCY_ID, 'P'
    FROM VFIN.dbo.PAYABLES_PAYABLE_DIST D
    JOIN VFIN.dbo.PAYABLES_PAYABLE P
        ON D.INVOICE_ENTITY_ID = P.ENTITY_ID AND D.INVOICE_ID = P.INVOICE_ID

    UNION ALL

    ----------------------------------------------------------------------------
    -- VFIN: Payment Distributions
    ----------------------------------------------------------------------------
    SELECT
        'VFIN', 'VFIN_PAYMENT', D.PAYMENT_ID,
        NULL, NULL, NULL, NULL, NULL,
        COALESCE(D.RECV_INVOICE_ID, D.PAYB_INVOICE_ID),
        D.ACCOUNT_ID,
        ISNULL(D.DEBIT_AMOUNT, 0), ISNULL(D.CREDIT_AMOUNT, 0),
        ISNULL(D.DEBIT_AMOUNT, 0) - ISNULL(D.CREDIT_AMOUNT, 0),
        D.POSTING_DATE, D.RECORD_CREATED,
        ISNULL(D.REFERENCE, PM.REFERENCE),
        D.PAYMENT_ENTITY_ID, D.CURRENCY_ID, 'P'
    FROM VFIN.dbo.CASHMGMT_PAYMENT_DIST D
    JOIN VFIN.dbo.CASHMGMT_PAYMENT PM
        ON D.PAYMENT_ENTITY_ID = PM.ENTITY_ID AND D.PAYMENT_ID = PM.PAYMENT_ID

    UNION ALL

    ----------------------------------------------------------------------------
    -- VFIN: General Journal Distributions
    ----------------------------------------------------------------------------
    SELECT
        'VFIN', 'VFIN_GEN', D.GEN_JOURNAL_ID,
        NULL, NULL, NULL, NULL, NULL, NULL,
        D.ACCOUNT_ID,
        ISNULL(D.DEBIT_AMOUNT, 0), ISNULL(D.CREDIT_AMOUNT, 0),
        ISNULL(D.DEBIT_AMOUNT, 0) - ISNULL(D.CREDIT_AMOUNT, 0),
        D.POSTING_DATE, D.RECORD_CREATED,
        ISNULL(D.REFERENCE, G.DESCRIPTION),
        D.GEN_JOURNAL_ENTITY_ID, D.CURRENCY_ID, 'P'
    FROM VFIN.dbo.LEDGER_GEN_JOURN_DIST D
    JOIN VFIN.dbo.LEDGER_GEN_JOURNAL G
        ON D.GEN_JOURNAL_ENTITY_ID = G.ENTITY_ID AND D.GEN_JOURNAL_ID = G.GEN_JOURNAL_ID

    UNION ALL

    ----------------------------------------------------------------------------
    -- VFIN: Bank Adjustment Distributions
    ----------------------------------------------------------------------------
    SELECT
        'VFIN', 'VFIN_BANKADJ', D.ADJUSTMENT_ID,
        NULL, NULL, NULL, NULL, NULL, NULL,
        D.ACCOUNT_ID,
        ISNULL(D.DEBIT_AMOUNT, 0), ISNULL(D.CREDIT_AMOUNT, 0),
        ISNULL(D.DEBIT_AMOUNT, 0) - ISNULL(D.CREDIT_AMOUNT, 0),
        D.POSTING_DATE, D.RECORD_CREATED,
        ISNULL(D.REFERENCE, A.REFERENCE),
        D.BANK_ADJ_ENTITY_ID, D.CURRENCY_ID, 'P'
    FROM VFIN.dbo.CASHMGMT_BANK_ADJ_DIST D
    JOIN VFIN.dbo.CASHMGMT_BANK_ADJUSTMENT A
        ON D.BANK_ADJ_ENTITY_ID = A.ENTITY_ID AND D.ADJUSTMENT_ID = A.ADJUSTMENT_ID

    UNION ALL

    ----------------------------------------------------------------------------
    -- VFIN: Direct Journal Distributions
    ----------------------------------------------------------------------------
    SELECT
        'VFIN', 'VFIN_DIRECT', D.DIRECT_JOURNAL_ID,
        NULL, NULL, NULL, NULL, NULL, NULL,
        D.ACCOUNT_ID,
        ISNULL(D.DEBIT_AMOUNT, 0), ISNULL(D.CREDIT_AMOUNT, 0),
        ISNULL(D.DEBIT_AMOUNT, 0) - ISNULL(D.CREDIT_AMOUNT, 0),
        D.POSTING_DATE, D.RECORD_CREATED,
        ISNULL(D.REFERENCE, J.DESCRIPTION),
        D.DIR_JOURN_ENTITY_ID, D.CURRENCY_ID, 'P'
    FROM VFIN.dbo.LEDGER_DIRECT_JOURN_DIST D
    JOIN VFIN.dbo.LEDGER_DIRECT_JOURNAL J
        ON D.DIR_JOURN_ENTITY_ID = J.ENTITY_ID AND D.DIRECT_JOURNAL_ID = J.DIRECT_JOURNAL_ID

) AS M

LEFT JOIN VECA.dbo.Z_GL_MAPPING G
    ON M.GL_ACCOUNT_ID = G.ACCOUNT_ID
    AND M.POSTING_DATE >= G.EFFECTIVE_START_DATE
    AND M.POSTING_DATE < G.EFFECTIVE_END_DATE

WHERE M.POSTING_DATE >= @DateFrom
  AND M.POSTING_DATE <= @DateTo
  AND (@PostedOnly = 0 OR M.POSTING_STATUS = 'P')
  AND (@SourceDB IS NULL OR M.SOURCE_DB = @SourceDB)
  AND (@JournalType IS NULL OR M.JOURNAL_TYPE = @JournalType)
  AND (@AccountID IS NULL OR M.GL_ACCOUNT_ID = @AccountID)
  AND (@FSType IS NULL OR G.FS = @FSType)

ORDER BY M.POSTING_DATE, M.SOURCE_DB, M.JOURNAL_TYPE;
