/*
================================================================================
  GL POSTING MAP - Consolidated Distribution Query (VECA + VFIN)
================================================================================
  Unions all GL distribution tables across both databases into a single
  normalized result set. Use this to answer: "What posted, from where,
  and what source document triggered it?"

  ⚠ CRITICAL: VECA/VFIN OVERLAP - DIAGNOSED AND HANDLED VIA @DedupeMode
  ------------------------------------------------------------------
  Visual Exchange pushes VECA activity into VFIN as follows:
    - AR invoices: copied row-for-row into VFIN.RECEIVABLES_RECEIVABLE_DIST
      (REFERENCE = 'Updated by Exchange')
    - VECA manufacturing (WIP, SHIPMENT, PURCHASE, ADJUST, INDIRECT): each
      VECA batch summarized into VFIN.LEDGER_GEN_JOURN_DIST as batch-level
      general journal entries (REFERENCE = 'Updated by Exchange')
    - AP/Payments/Bank Adj/Direct Journals: VFIN-native (no VECA equivalent)
    - Manual VFIN entries (not from Exchange): REFERENCE is NULL, other text,
      or a user-entered reference

  The REFERENCE field value 'Updated by Exchange' is the definitive marker
  that identifies a VFIN row as an echo of a VECA entry.

  @DedupeMode options:
    'HYBRID'  = VECA for detail + VFIN-native only (recommended default)
                Includes all VECA dists PLUS VFIN rows where REFERENCE is
                NOT 'Updated by Exchange'. Gives you detail from VECA and
                VFIN-only entries without double-counting.
    'VFIN'    = VFIN only (GL-view only, summarized for manufacturing)
                Includes all VFIN dists. Excludes all VECA dists. Use when
                you want to match VFIN's GL totals exactly.
    'VECA'    = VECA only (detail-view for operations)
                Includes all VECA dists. Excludes all VFIN dists. Use when
                you only care about VECA-sourced operational activity.
    'NONE'    = Include everything (WILL DOUBLE-COUNT - diagnostic only)

  Columns:
    SOURCE_DB        - 'VECA' or 'VFIN'
    JOURNAL_TYPE     - Short code identifying the posting source
    DOCUMENT_ID      - Primary source document ID
    WO_TYPE          - Work order TYPE (VECA WO dists only)
    WO_BASE_ID       - Work order BASE_ID (VECA WO dists only)
    WO_LOT_ID        - Work order LOT_ID (VECA WO dists only)
    WO_SPLIT_ID      - Work order SPLIT_ID (VECA WO dists only)
    WO_SUB_ID        - Work order SUB_ID (VECA WO dists only)
    LINKED_INVOICE_ID - For payments: the AR/AP invoice being paid
    GL_ACCOUNT_ID    - GL account
    DEBIT_AMOUNT     - Normalized debit
    CREDIT_AMOUNT    - Normalized credit
    NET_AMOUNT       - Debit minus Credit
    POSTING_DATE     - GL posting date
    CREATED_DATE     - When the dist row was created
    REFERENCE        - Reference/description text
    SITE_OR_ENTITY   - SITE_ID (VECA) or ENTITY_ID (VFIN)
    CURRENCY_ID      - Currency code
    POSTING_STATUS   - 'P'=Posted, 'U'=Unposted (VECA), always 'P' (VFIN)
    DIST_NO          - Distribution sequence number
    ENTRY_NO         - Entry number within distribution

  Source Document Lookup Guide:
    VECA_WIP_ISSUE   -> VECA.dbo.WORK_ORDER (join on WO composite key)
    VECA_WIP_RCPT    -> VECA.dbo.WORK_ORDER (join on WO composite key)
    VECA_SHIPMENT    -> VECA.dbo.CUSTOMER_ORDER (DOCUMENT_ID = CUST_ORDER_ID)
    VECA_RECV        -> VECA.dbo.RECEIVABLE (DOCUMENT_ID = INVOICE_ID)
    VECA_PURCHASE    -> VECA.dbo.PURCHASE_ORDER (DOCUMENT_ID = PURC_ORDER_ID)
    VECA_ADJUST      -> VECA.dbo.INVENTORY_TRANS (DOCUMENT_ID = TRANSACTION_ID)
    VECA_INDIRECT    -> VECA.dbo.INDIRECT_DIST source (DOCUMENT_ID = TRANSACTION_ID)
    VECA_GJ          -> VECA.dbo.GJ (DOCUMENT_ID = GJ_ID)
    VFIN_RECV        -> VFIN.dbo.RECEIVABLES_RECEIVABLE (DOCUMENT_ID = INVOICE_ID)
    VFIN_PAYB        -> VFIN.dbo.PAYABLES_PAYABLE (DOCUMENT_ID = INVOICE_ID)
    VFIN_PAYMENT     -> VFIN.dbo.CASHMGMT_PAYMENT (DOCUMENT_ID = PAYMENT_ID)
    VFIN_GEN         -> VFIN.dbo.LEDGER_GEN_JOURNAL (DOCUMENT_ID = GEN_JOURNAL_ID)
    VFIN_BANKADJ     -> VFIN.dbo.CASHMGMT_BANK_ADJUSTMENT (DOCUMENT_ID = ADJUSTMENT_ID)
    VFIN_DIRECT      -> VFIN.dbo.LEDGER_DIRECT_JOURNAL (DOCUMENT_ID = DIRECT_JOURNAL_ID)

  Usage:
    - Set parameters below, then run
    - See gl_posting_today.sql for daily audit with summary + balance check
    - See gl_posting_map_enriched.sql for version with Z_GL_MAPPING account classification
================================================================================
*/

--------------------------------------------------------------------------------
-- PARAMETERS: Update these before running
--------------------------------------------------------------------------------
DECLARE @DateFrom     date         = '2026-01-01';  -- Start of date range (inclusive)
DECLARE @DateTo       date         = '2026-04-09';  -- End of date range (inclusive)
DECLARE @DedupeMode   nvarchar(10) = 'HYBRID';      -- 'HYBRID'|'VFIN'|'VECA'|'NONE' (see header)
DECLARE @PostedOnly   bit          = 1;             -- 1 = posted only, 0 = include unposted VECA
DECLARE @SourceDB     nvarchar(4)  = NULL;          -- NULL = both, 'VECA', or 'VFIN' (secondary filter)
DECLARE @JournalType  nvarchar(20) = NULL;          -- NULL = all, or specific type like 'VFIN_PAYMENT'
DECLARE @AccountID    nvarchar(30) = NULL;          -- NULL = all, or specific GL account like '4100'
DECLARE @ExchangeMark nvarchar(40) = 'Updated by Exchange';  -- Marker in VFIN REFERENCE for Exchange-sourced rows
--------------------------------------------------------------------------------

SELECT * FROM (

--------------------------------------------------------------------------------
-- VECA: WIP Issue Distributions (material/labor/burden/service issues to WOs)
-- Source: WORK_ORDER (5-part composite key)
-- ~7.2M rows
--------------------------------------------------------------------------------
SELECT
    'VECA'                       AS SOURCE_DB,
    'VECA_WIP_ISSUE'             AS JOURNAL_TYPE,
    NULL                         AS DOCUMENT_ID,
    WORKORDER_TYPE               AS WO_TYPE,
    WORKORDER_BASE_ID            AS WO_BASE_ID,
    WORKORDER_LOT_ID             AS WO_LOT_ID,
    WORKORDER_SPLIT_ID           AS WO_SPLIT_ID,
    WORKORDER_SUB_ID             AS WO_SUB_ID,
    NULL                         AS LINKED_INVOICE_ID,
    GL_ACCOUNT_ID,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END AS DEBIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END AS CREDIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END AS NET_AMOUNT,
    POSTING_DATE,
    CREATE_DATE                  AS CREATED_DATE,
    NULL                         AS REFERENCE,
    SITE_ID                      AS SITE_OR_ENTITY,
    CURRENCY_ID,
    POSTING_STATUS,
    DIST_NO,
    ENTRY_NO
FROM VECA.dbo.WIP_ISSUE_DIST

UNION ALL

--------------------------------------------------------------------------------
-- VECA: WIP Receipt Distributions (finished goods receipts from WOs)
-- Source: WORK_ORDER (5-part composite key)
-- ~6.2M rows
--------------------------------------------------------------------------------
SELECT
    'VECA'                       AS SOURCE_DB,
    'VECA_WIP_RCPT'              AS JOURNAL_TYPE,
    NULL                         AS DOCUMENT_ID,
    WORKORDER_TYPE               AS WO_TYPE,
    WORKORDER_BASE_ID            AS WO_BASE_ID,
    WORKORDER_LOT_ID             AS WO_LOT_ID,
    WORKORDER_SPLIT_ID           AS WO_SPLIT_ID,
    WORKORDER_SUB_ID             AS WO_SUB_ID,
    NULL                         AS LINKED_INVOICE_ID,
    GL_ACCOUNT_ID,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END AS DEBIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END AS CREDIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END AS NET_AMOUNT,
    POSTING_DATE,
    CREATE_DATE                  AS CREATED_DATE,
    NULL                         AS REFERENCE,
    SITE_ID                      AS SITE_OR_ENTITY,
    CURRENCY_ID,
    POSTING_STATUS,
    DIST_NO,
    ENTRY_NO
FROM VECA.dbo.WIP_RECEIPT_DIST

UNION ALL

--------------------------------------------------------------------------------
-- VECA: Shipment Distributions (cost of goods shipped to customers)
-- Source: CUSTOMER_ORDER via CUST_ORDER_ID
-- ~1.3M rows
--------------------------------------------------------------------------------
SELECT
    'VECA'                       AS SOURCE_DB,
    'VECA_SHIPMENT'              AS JOURNAL_TYPE,
    CUST_ORDER_ID                AS DOCUMENT_ID,
    NULL                         AS WO_TYPE,
    NULL                         AS WO_BASE_ID,
    NULL                         AS WO_LOT_ID,
    NULL                         AS WO_SPLIT_ID,
    NULL                         AS WO_SUB_ID,
    NULL                         AS LINKED_INVOICE_ID,
    GL_ACCOUNT_ID,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END AS DEBIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END AS CREDIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END AS NET_AMOUNT,
    POSTING_DATE,
    CREATE_DATE                  AS CREATED_DATE,
    NULL                         AS REFERENCE,
    SITE_ID                      AS SITE_OR_ENTITY,
    CURRENCY_ID,
    POSTING_STATUS,
    DIST_NO,
    ENTRY_NO
FROM VECA.dbo.SHIPMENT_DIST

UNION ALL

--------------------------------------------------------------------------------
-- VECA: Receivable Distributions (AR invoice postings in VECA)
-- Source: RECEIVABLE via INVOICE_ID
-- ~536K rows
--------------------------------------------------------------------------------
SELECT
    'VECA'                       AS SOURCE_DB,
    'VECA_RECV'                  AS JOURNAL_TYPE,
    INVOICE_ID                   AS DOCUMENT_ID,
    NULL                         AS WO_TYPE,
    NULL                         AS WO_BASE_ID,
    NULL                         AS WO_LOT_ID,
    NULL                         AS WO_SPLIT_ID,
    NULL                         AS WO_SUB_ID,
    NULL                         AS LINKED_INVOICE_ID,
    GL_ACCOUNT_ID,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END AS DEBIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END AS CREDIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END AS NET_AMOUNT,
    POSTING_DATE,
    CREATE_DATE                  AS CREATED_DATE,
    NULL                         AS REFERENCE,
    SITE_ID                      AS SITE_OR_ENTITY,
    CURRENCY_ID,
    POSTING_STATUS,
    DIST_NO,
    ENTRY_NO
FROM VECA.dbo.RECEIVABLE_DIST

UNION ALL

--------------------------------------------------------------------------------
-- VECA: Purchase Distributions (PO receipt accruals)
-- Source: PURCHASE_ORDER via PURC_ORDER_ID
-- ~192K rows
--------------------------------------------------------------------------------
SELECT
    'VECA'                       AS SOURCE_DB,
    'VECA_PURCHASE'              AS JOURNAL_TYPE,
    PURC_ORDER_ID                AS DOCUMENT_ID,
    NULL                         AS WO_TYPE,
    NULL                         AS WO_BASE_ID,
    NULL                         AS WO_LOT_ID,
    NULL                         AS WO_SPLIT_ID,
    NULL                         AS WO_SUB_ID,
    NULL                         AS LINKED_INVOICE_ID,
    GL_ACCOUNT_ID,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END AS DEBIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END AS CREDIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END AS NET_AMOUNT,
    POSTING_DATE,
    CREATE_DATE                  AS CREATED_DATE,
    NULL                         AS REFERENCE,
    SITE_ID                      AS SITE_OR_ENTITY,
    CURRENCY_ID,
    POSTING_STATUS,
    DIST_NO,
    ENTRY_NO
FROM VECA.dbo.PURCHASE_DIST

UNION ALL

--------------------------------------------------------------------------------
-- VECA: Adjustment Distributions (inventory adjustments)
-- Source: INVENTORY_TRANS via TRANSACTION_ID
-- ~131K rows
--------------------------------------------------------------------------------
SELECT
    'VECA'                       AS SOURCE_DB,
    'VECA_ADJUST'                AS JOURNAL_TYPE,
    CAST(TRANSACTION_ID AS nvarchar(30)) AS DOCUMENT_ID,
    NULL                         AS WO_TYPE,
    NULL                         AS WO_BASE_ID,
    NULL                         AS WO_LOT_ID,
    NULL                         AS WO_SPLIT_ID,
    NULL                         AS WO_SUB_ID,
    NULL                         AS LINKED_INVOICE_ID,
    GL_ACCOUNT_ID,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END AS DEBIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END AS CREDIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END AS NET_AMOUNT,
    POSTING_DATE,
    CREATE_DATE                  AS CREATED_DATE,
    NULL                         AS REFERENCE,
    SITE_ID                      AS SITE_OR_ENTITY,
    CURRENCY_ID,
    POSTING_STATUS,
    DIST_NO,
    ENTRY_NO
FROM VECA.dbo.ADJUSTMENT_DIST

UNION ALL

--------------------------------------------------------------------------------
-- VECA: Indirect Distributions (indirect cost postings)
-- Source: Indirect cost transactions via TRANSACTION_ID
-- ~3.9K rows
--------------------------------------------------------------------------------
SELECT
    'VECA'                       AS SOURCE_DB,
    'VECA_INDIRECT'              AS JOURNAL_TYPE,
    CAST(TRANSACTION_ID AS nvarchar(30)) AS DOCUMENT_ID,
    NULL                         AS WO_TYPE,
    NULL                         AS WO_BASE_ID,
    NULL                         AS WO_LOT_ID,
    NULL                         AS WO_SPLIT_ID,
    NULL                         AS WO_SUB_ID,
    NULL                         AS LINKED_INVOICE_ID,
    GL_ACCOUNT_ID,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END AS DEBIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END AS CREDIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END AS NET_AMOUNT,
    POSTING_DATE,
    CREATE_DATE                  AS CREATED_DATE,
    NULL                         AS REFERENCE,
    SITE_ID                      AS SITE_OR_ENTITY,
    CURRENCY_ID,
    POSTING_STATUS,
    DIST_NO,
    ENTRY_NO
FROM VECA.dbo.INDIRECT_DIST

UNION ALL

--------------------------------------------------------------------------------
-- VECA: General Journal Distributions
-- Source: GJ (general journal) via GJ_ID
-- ~108 rows
--------------------------------------------------------------------------------
SELECT
    'VECA'                       AS SOURCE_DB,
    'VECA_GJ'                    AS JOURNAL_TYPE,
    GJ_ID                        AS DOCUMENT_ID,
    NULL                         AS WO_TYPE,
    NULL                         AS WO_BASE_ID,
    NULL                         AS WO_LOT_ID,
    NULL                         AS WO_SPLIT_ID,
    NULL                         AS WO_SUB_ID,
    NULL                         AS LINKED_INVOICE_ID,
    GL_ACCOUNT_ID,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE 0 END AS DEBIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'CR' THEN AMOUNT ELSE 0 END AS CREDIT_AMOUNT,
    CASE WHEN AMOUNT_TYPE = 'DR' THEN AMOUNT ELSE -AMOUNT END AS NET_AMOUNT,
    POSTING_DATE,
    CREATE_DATE                  AS CREATED_DATE,
    NULL                         AS REFERENCE,
    SITE_ID                      AS SITE_OR_ENTITY,
    CURRENCY_ID,
    POSTING_STATUS,
    DIST_NO,
    ENTRY_NO
FROM VECA.dbo.GJ_DIST

UNION ALL

--------------------------------------------------------------------------------
-- VFIN: Receivable Distributions (AR invoice postings)
-- Source: RECEIVABLES_RECEIVABLE via INVOICE_ENTITY_ID + INVOICE_ID
-- ~552K rows
--------------------------------------------------------------------------------
SELECT
    'VFIN'                       AS SOURCE_DB,
    'VFIN_RECV'                  AS JOURNAL_TYPE,
    D.INVOICE_ID                 AS DOCUMENT_ID,
    NULL                         AS WO_TYPE,
    NULL                         AS WO_BASE_ID,
    NULL                         AS WO_LOT_ID,
    NULL                         AS WO_SPLIT_ID,
    NULL                         AS WO_SUB_ID,
    NULL                         AS LINKED_INVOICE_ID,
    D.ACCOUNT_ID                 AS GL_ACCOUNT_ID,
    ISNULL(D.DEBIT_AMOUNT, 0)    AS DEBIT_AMOUNT,
    ISNULL(D.CREDIT_AMOUNT, 0)   AS CREDIT_AMOUNT,
    ISNULL(D.DEBIT_AMOUNT, 0) - ISNULL(D.CREDIT_AMOUNT, 0) AS NET_AMOUNT,
    D.POSTING_DATE,
    D.RECORD_CREATED             AS CREATED_DATE,
    ISNULL(D.REFERENCE, R.CUSTOMER_ID) AS REFERENCE,
    D.INVOICE_ENTITY_ID          AS SITE_OR_ENTITY,
    D.CURRENCY_ID,
    'P'                          AS POSTING_STATUS,
    D.DIST_NO,
    D.ENTRY_NO
FROM VFIN.dbo.RECEIVABLES_RECEIVABLE_DIST D
JOIN VFIN.dbo.RECEIVABLES_RECEIVABLE R
    ON D.INVOICE_ENTITY_ID = R.ENTITY_ID
    AND D.INVOICE_ID = R.INVOICE_ID

UNION ALL

--------------------------------------------------------------------------------
-- VFIN: Payable Distributions (AP invoice postings)
-- Source: PAYABLES_PAYABLE via INVOICE_ENTITY_ID + INVOICE_ID
-- ~234K rows
--------------------------------------------------------------------------------
SELECT
    'VFIN'                       AS SOURCE_DB,
    'VFIN_PAYB'                  AS JOURNAL_TYPE,
    D.INVOICE_ID                 AS DOCUMENT_ID,
    NULL                         AS WO_TYPE,
    NULL                         AS WO_BASE_ID,
    NULL                         AS WO_LOT_ID,
    NULL                         AS WO_SPLIT_ID,
    NULL                         AS WO_SUB_ID,
    NULL                         AS LINKED_INVOICE_ID,
    D.ACCOUNT_ID                 AS GL_ACCOUNT_ID,
    ISNULL(D.DEBIT_AMOUNT, 0)    AS DEBIT_AMOUNT,
    ISNULL(D.CREDIT_AMOUNT, 0)   AS CREDIT_AMOUNT,
    ISNULL(D.DEBIT_AMOUNT, 0) - ISNULL(D.CREDIT_AMOUNT, 0) AS NET_AMOUNT,
    D.POSTING_DATE,
    D.RECORD_CREATED             AS CREATED_DATE,
    ISNULL(D.REFERENCE, P.SUPPLIER_ID) AS REFERENCE,
    D.INVOICE_ENTITY_ID          AS SITE_OR_ENTITY,
    D.CURRENCY_ID,
    'P'                          AS POSTING_STATUS,
    D.DIST_NO,
    D.ENTRY_NO
FROM VFIN.dbo.PAYABLES_PAYABLE_DIST D
JOIN VFIN.dbo.PAYABLES_PAYABLE P
    ON D.INVOICE_ENTITY_ID = P.ENTITY_ID
    AND D.INVOICE_ID = P.INVOICE_ID

UNION ALL

--------------------------------------------------------------------------------
-- VFIN: Payment Distributions (cash receipts and disbursements)
-- Source: CASHMGMT_PAYMENT via PAYMENT_ENTITY_ID + PAYMENT_ID
-- Also links to AR/AP invoices via RECV_INVOICE_ID / PAYB_INVOICE_ID
-- ~529K rows
--------------------------------------------------------------------------------
SELECT
    'VFIN'                       AS SOURCE_DB,
    'VFIN_PAYMENT'               AS JOURNAL_TYPE,
    D.PAYMENT_ID                 AS DOCUMENT_ID,
    NULL                         AS WO_TYPE,
    NULL                         AS WO_BASE_ID,
    NULL                         AS WO_LOT_ID,
    NULL                         AS WO_SPLIT_ID,
    NULL                         AS WO_SUB_ID,
    COALESCE(D.RECV_INVOICE_ID, D.PAYB_INVOICE_ID) AS LINKED_INVOICE_ID,
    D.ACCOUNT_ID                 AS GL_ACCOUNT_ID,
    ISNULL(D.DEBIT_AMOUNT, 0)    AS DEBIT_AMOUNT,
    ISNULL(D.CREDIT_AMOUNT, 0)   AS CREDIT_AMOUNT,
    ISNULL(D.DEBIT_AMOUNT, 0) - ISNULL(D.CREDIT_AMOUNT, 0) AS NET_AMOUNT,
    D.POSTING_DATE,
    D.RECORD_CREATED             AS CREATED_DATE,
    ISNULL(D.REFERENCE, PM.REFERENCE) AS REFERENCE,
    D.PAYMENT_ENTITY_ID          AS SITE_OR_ENTITY,
    D.CURRENCY_ID,
    'P'                          AS POSTING_STATUS,
    D.DIST_NO,
    D.ENTRY_NO
FROM VFIN.dbo.CASHMGMT_PAYMENT_DIST D
JOIN VFIN.dbo.CASHMGMT_PAYMENT PM
    ON D.PAYMENT_ENTITY_ID = PM.ENTITY_ID
    AND D.PAYMENT_ID = PM.PAYMENT_ID

UNION ALL

--------------------------------------------------------------------------------
-- VFIN: General Journal Distributions
-- Source: LEDGER_GEN_JOURNAL via GEN_JOURNAL_ENTITY_ID + GEN_JOURNAL_ID
-- ~179K rows
--------------------------------------------------------------------------------
SELECT
    'VFIN'                       AS SOURCE_DB,
    'VFIN_GEN'                   AS JOURNAL_TYPE,
    D.GEN_JOURNAL_ID             AS DOCUMENT_ID,
    NULL                         AS WO_TYPE,
    NULL                         AS WO_BASE_ID,
    NULL                         AS WO_LOT_ID,
    NULL                         AS WO_SPLIT_ID,
    NULL                         AS WO_SUB_ID,
    NULL                         AS LINKED_INVOICE_ID,
    D.ACCOUNT_ID                 AS GL_ACCOUNT_ID,
    ISNULL(D.DEBIT_AMOUNT, 0)    AS DEBIT_AMOUNT,
    ISNULL(D.CREDIT_AMOUNT, 0)   AS CREDIT_AMOUNT,
    ISNULL(D.DEBIT_AMOUNT, 0) - ISNULL(D.CREDIT_AMOUNT, 0) AS NET_AMOUNT,
    D.POSTING_DATE,
    D.RECORD_CREATED             AS CREATED_DATE,
    ISNULL(D.REFERENCE, G.DESCRIPTION) AS REFERENCE,
    D.GEN_JOURNAL_ENTITY_ID      AS SITE_OR_ENTITY,
    D.CURRENCY_ID,
    'P'                          AS POSTING_STATUS,
    D.DIST_NO,
    D.ENTRY_NO
FROM VFIN.dbo.LEDGER_GEN_JOURN_DIST D
JOIN VFIN.dbo.LEDGER_GEN_JOURNAL G
    ON D.GEN_JOURNAL_ENTITY_ID = G.ENTITY_ID
    AND D.GEN_JOURNAL_ID = G.GEN_JOURNAL_ID

UNION ALL

--------------------------------------------------------------------------------
-- VFIN: Bank Adjustment Distributions
-- Source: CASHMGMT_BANK_ADJUSTMENT via BANK_ADJ_ENTITY_ID + ADJUSTMENT_ID
-- ~13K rows
--------------------------------------------------------------------------------
SELECT
    'VFIN'                       AS SOURCE_DB,
    'VFIN_BANKADJ'               AS JOURNAL_TYPE,
    D.ADJUSTMENT_ID              AS DOCUMENT_ID,
    NULL                         AS WO_TYPE,
    NULL                         AS WO_BASE_ID,
    NULL                         AS WO_LOT_ID,
    NULL                         AS WO_SPLIT_ID,
    NULL                         AS WO_SUB_ID,
    NULL                         AS LINKED_INVOICE_ID,
    D.ACCOUNT_ID                 AS GL_ACCOUNT_ID,
    ISNULL(D.DEBIT_AMOUNT, 0)    AS DEBIT_AMOUNT,
    ISNULL(D.CREDIT_AMOUNT, 0)   AS CREDIT_AMOUNT,
    ISNULL(D.DEBIT_AMOUNT, 0) - ISNULL(D.CREDIT_AMOUNT, 0) AS NET_AMOUNT,
    D.POSTING_DATE,
    D.RECORD_CREATED             AS CREATED_DATE,
    ISNULL(D.REFERENCE, A.REFERENCE) AS REFERENCE,
    D.BANK_ADJ_ENTITY_ID         AS SITE_OR_ENTITY,
    D.CURRENCY_ID,
    'P'                          AS POSTING_STATUS,
    D.DIST_NO,
    D.ENTRY_NO
FROM VFIN.dbo.CASHMGMT_BANK_ADJ_DIST D
JOIN VFIN.dbo.CASHMGMT_BANK_ADJUSTMENT A
    ON D.BANK_ADJ_ENTITY_ID = A.ENTITY_ID
    AND D.ADJUSTMENT_ID = A.ADJUSTMENT_ID

UNION ALL

--------------------------------------------------------------------------------
-- VFIN: Direct Journal Distributions (system-generated from sub-ledgers like VECA)
-- Source: LEDGER_DIRECT_JOURNAL via DIR_JOURN_ENTITY_ID + DIRECT_JOURNAL_ID
-- ~172 rows
-- NOTE: This is how VECA postings flow into VFIN's GL. The DIRECT_JOURNAL
--       entries are created when VECA batches are posted to Visual Financials.
--------------------------------------------------------------------------------
SELECT
    'VFIN'                       AS SOURCE_DB,
    'VFIN_DIRECT'                AS JOURNAL_TYPE,
    D.DIRECT_JOURNAL_ID          AS DOCUMENT_ID,
    NULL                         AS WO_TYPE,
    NULL                         AS WO_BASE_ID,
    NULL                         AS WO_LOT_ID,
    NULL                         AS WO_SPLIT_ID,
    NULL                         AS WO_SUB_ID,
    NULL                         AS LINKED_INVOICE_ID,
    D.ACCOUNT_ID                 AS GL_ACCOUNT_ID,
    ISNULL(D.DEBIT_AMOUNT, 0)    AS DEBIT_AMOUNT,
    ISNULL(D.CREDIT_AMOUNT, 0)   AS CREDIT_AMOUNT,
    ISNULL(D.DEBIT_AMOUNT, 0) - ISNULL(D.CREDIT_AMOUNT, 0) AS NET_AMOUNT,
    D.POSTING_DATE,
    D.RECORD_CREATED             AS CREATED_DATE,
    ISNULL(D.REFERENCE, J.DESCRIPTION) AS REFERENCE,
    D.DIR_JOURN_ENTITY_ID        AS SITE_OR_ENTITY,
    D.CURRENCY_ID,
    'P'                          AS POSTING_STATUS,
    D.DIST_NO,
    D.ENTRY_NO
FROM VFIN.dbo.LEDGER_DIRECT_JOURN_DIST D
JOIN VFIN.dbo.LEDGER_DIRECT_JOURNAL J
    ON D.DIR_JOURN_ENTITY_ID = J.ENTITY_ID
    AND D.DIRECT_JOURNAL_ID = J.DIRECT_JOURNAL_ID

--------------------------------------------------------------------------------
-- COMMENTED OUT: VECA dist tables with 0 rows (no DDL exports exist)
-- Uncomment if data appears in these tables.
--------------------------------------------------------------------------------

-- UNION ALL
-- -- VECA: Payable Distributions (AP postings in VECA - currently 0 rows)
-- SELECT 'VECA', 'VECA_PAYABLE', INVOICE_ID, NULL, NULL, NULL, NULL, NULL, NULL,
--        GL_ACCOUNT_ID, CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='CR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE -AMOUNT END,
--        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS, DIST_NO, ENTRY_NO
-- FROM VECA.dbo.PAYABLE_DIST

-- UNION ALL
-- -- VECA: Bank Adjustment Distributions (currently 0 rows)
-- SELECT 'VECA', 'VECA_BANKADJ', ADJUSTMENT_ID, NULL, NULL, NULL, NULL, NULL, NULL,
--        GL_ACCOUNT_ID, CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='CR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE -AMOUNT END,
--        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS, DIST_NO, ENTRY_NO
-- FROM VECA.dbo.BANK_ADJ_DIST

-- UNION ALL
-- -- VECA: Cash Disburse Distributions (currently 0 rows)
-- SELECT 'VECA', 'VECA_CASH_DISB', PAYMENT_ID, NULL, NULL, NULL, NULL, NULL, NULL,
--        GL_ACCOUNT_ID, CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='CR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE -AMOUNT END,
--        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS, DIST_NO, ENTRY_NO
-- FROM VECA.dbo.CASH_DISBURSE_DIST

-- UNION ALL
-- -- VECA: Cash Receipt Distributions (currently 0 rows)
-- SELECT 'VECA', 'VECA_CASH_RCPT', RECEIPT_ID, NULL, NULL, NULL, NULL, NULL, NULL,
--        GL_ACCOUNT_ID, CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='CR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE -AMOUNT END,
--        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS, DIST_NO, ENTRY_NO
-- FROM VECA.dbo.CASH_RECEIPT_DIST

-- UNION ALL
-- -- VECA: Burden Distributions (currently 0 rows)
-- SELECT 'VECA', 'VECA_BURDEN', TRANSACTION_ID, NULL, NULL, NULL, NULL, NULL, NULL,
--        GL_ACCOUNT_ID, CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='CR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE -AMOUNT END,
--        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS, DIST_NO, ENTRY_NO
-- FROM VECA.dbo.BURDEN_DIST

-- UNION ALL
-- -- VECA: V_Payable Distributions (currently 0 rows)
-- SELECT 'VECA', 'VECA_V_PAYABLE', INVOICE_ID, NULL, NULL, NULL, NULL, NULL, NULL,
--        GL_ACCOUNT_ID, CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='CR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE -AMOUNT END,
--        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS, DIST_NO, ENTRY_NO
-- FROM VECA.dbo.V_PAYABLE_DIST

-- UNION ALL
-- -- VECA: V_Recv Distributions (currently 0 rows)
-- SELECT 'VECA', 'VECA_V_RECV', INVOICE_ID, NULL, NULL, NULL, NULL, NULL, NULL,
--        GL_ACCOUNT_ID, CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='CR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE -AMOUNT END,
--        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS, DIST_NO, ENTRY_NO
-- FROM VECA.dbo.V_RECV_DIST

-- UNION ALL
-- -- VECA: Revalue Distributions (currently 0 rows)
-- SELECT 'VECA', 'VECA_REVALUE', TRANSACTION_ID, NULL, NULL, NULL, NULL, NULL, NULL,
--        GL_ACCOUNT_ID, CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='CR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE -AMOUNT END,
--        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS, DIST_NO, ENTRY_NO
-- FROM VECA.dbo.REVALUE_DIST

-- UNION ALL
-- -- VECA: Revenue Distributions (currently 0 rows)
-- SELECT 'VECA', 'VECA_REVENUE', INVOICE_ID, NULL, NULL, NULL, NULL, NULL, NULL,
--        GL_ACCOUNT_ID, CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='CR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE -AMOUNT END,
--        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS, DIST_NO, ENTRY_NO
-- FROM VECA.dbo.REVENUE_DIST

-- UNION ALL
-- -- VECA: Project Distributions (currently 0 rows)
-- SELECT 'VECA', 'VECA_PROJECT', PROJECT_ID, NULL, NULL, NULL, NULL, NULL, NULL,
--        GL_ACCOUNT_ID, CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='CR' THEN AMOUNT ELSE 0 END,
--        CASE WHEN AMOUNT_TYPE='DR' THEN AMOUNT ELSE -AMOUNT END,
--        POSTING_DATE, CREATE_DATE, NULL, SITE_ID, CURRENCY_ID, POSTING_STATUS, DIST_NO, ENTRY_NO
-- FROM VECA.dbo.PROJECT_DIST

) AS GL_POSTING_MAP

WHERE POSTING_DATE >= @DateFrom
  AND POSTING_DATE <= @DateTo
  AND (@PostedOnly = 0 OR POSTING_STATUS = 'P')
  AND (@SourceDB IS NULL OR SOURCE_DB = @SourceDB)
  AND (@JournalType IS NULL OR JOURNAL_TYPE = @JournalType)
  AND (@AccountID IS NULL OR GL_ACCOUNT_ID = @AccountID)
  -- De-duplication logic based on @DedupeMode
  AND (
         @DedupeMode = 'NONE'
      OR (@DedupeMode = 'VECA' AND SOURCE_DB = 'VECA')
      OR (@DedupeMode = 'VFIN' AND SOURCE_DB = 'VFIN')
      -- HYBRID: all VECA rows + VFIN rows that are NOT Exchange-sourced
      OR (@DedupeMode = 'HYBRID' AND (
              SOURCE_DB = 'VECA'
              OR (SOURCE_DB = 'VFIN' AND (REFERENCE IS NULL OR REFERENCE <> @ExchangeMark))
         ))
      )

ORDER BY POSTING_DATE, SOURCE_DB, JOURNAL_TYPE;
