/*
================================================================================
  DIAGNOSE SINGLE INVOICE EXCHANGE FAILURE
================================================================================
  Purpose:
    Deep-dive one invoice that is failing in Exchange (VECA -> VFIN), including
    activity/task history, VECA source readiness, VFIN target presence, and
    customer master readiness.

  Inputs:
    @SubscriptionId  - Exchange subscription to inspect (default receivables)
    @InvoiceId       - Single invoice ID to trace
    @DaysBack        - Lookback window for activity/task history

  Output:
    Multiple result sets focused on the one invoice.

  Caveats:
    - Assumes VECA -> VFIN receivables flow.
    - This is an investigation query, not a production reporting dataset.
================================================================================
*/

DECLARE @SubscriptionId nvarchar(64) = 'VECA_VFIN_RECV_INVOICE'; -- subscription under investigation
DECLARE @InvoiceId      nvarchar(15) = 'INV-275213';             -- invoice to trace
DECLARE @DaysBack       int          = 60;                       -- activity/task lookback window

--------------------------------------------------------------------------------
-- 1) Exchange activity + task trail for this invoice
--------------------------------------------------------------------------------
SELECT TOP 200
    'ACTIVITY' AS ROW_SOURCE,
    A.RECORD_CREATED AS EVENT_TS,
    A.SUBSCRIPTION_ID,
    A.PUB_INSTANCE_NAME,
    A.PUB_DOCUMENT_ID,
    A.PUB_RECORD_ID,
    A.PUB_KEY_DATA,
    A.SUB_INSTANCE_NAME,
    A.SUB_DOCUMENT_ID,
    A.STATUS,
    A.MESSAGE
FROM LSA.dbo.EXCHANGE_ACTIVITY A
WHERE A.RECORD_CREATED >= DATEADD(day, -@DaysBack, GETDATE())
  AND (@SubscriptionId IS NULL OR @SubscriptionId = '' OR A.SUBSCRIPTION_ID = @SubscriptionId)
  AND A.PUB_KEY_DATA LIKE '%' + @InvoiceId + '%'

UNION ALL

SELECT TOP 200
    'TASK' AS ROW_SOURCE,
    T.RECORD_CREATED AS EVENT_TS,
    T.SUBSCRIPTION_ID,
    T.PUB_INSTANCE_NAME,
    T.PUB_DOCUMENT_ID,
    T.PUB_RECORD_ID,
    T.PUB_KEY_DATA,
    T.SUB_INSTANCE_NAME,
    T.SUB_DOCUMENT_ID,
    T.STATUS,
    T.MESSAGE
FROM LSA.dbo.EXCHANGE_TASK T
WHERE T.RECORD_CREATED >= DATEADD(day, -@DaysBack, GETDATE())
  AND (@SubscriptionId IS NULL OR @SubscriptionId = '' OR T.SUBSCRIPTION_ID = @SubscriptionId)
  AND T.PUB_KEY_DATA LIKE '%' + @InvoiceId + '%'
ORDER BY EVENT_TS DESC;

--------------------------------------------------------------------------------
-- 2) VECA source readiness: header, line, distribution
--------------------------------------------------------------------------------
SELECT
    R.INVOICE_ID,
    R.CUSTOMER_ID,
    R.STATUS AS INVOICE_STATUS,
    R.POSTING_DATE,
    R.CURRENCY_ID,
    R.RECV_GL_ACCT_ID
FROM VECA.dbo.RECEIVABLE R
WHERE R.INVOICE_ID = @InvoiceId;

SELECT
    COUNT(*) AS VECA_LINE_COUNT,
    SUM(CASE WHEN RL.QTY IS NULL THEN 1 ELSE 0 END) AS VECA_LINES_WITH_NULL_QTY,
    SUM(CASE WHEN RL.GL_ACCOUNT_ID IS NULL OR LTRIM(RTRIM(RL.GL_ACCOUNT_ID)) = '' THEN 1 ELSE 0 END) AS VECA_LINES_WITH_BLANK_GL
FROM VECA.dbo.RECEIVABLE_LINE RL
WHERE RL.INVOICE_ID = @InvoiceId;

SELECT
    COUNT(*) AS VECA_DIST_COUNT,
    SUM(CASE WHEN RD.GL_ACCOUNT_ID IS NULL OR LTRIM(RTRIM(RD.GL_ACCOUNT_ID)) = '' THEN 1 ELSE 0 END) AS VECA_DIST_WITH_BLANK_GL
FROM VECA.dbo.RECEIVABLE_DIST RD
WHERE RD.INVOICE_ID = @InvoiceId;

--------------------------------------------------------------------------------
-- 3) VFIN target presence: header, line, distribution
--------------------------------------------------------------------------------
SELECT
    RR.INVOICE_ID,
    RR.ENTITY_ID,
    RR.CUSTOMER_ID,
    RR.INVOICE_STATUS,
    RR.INVOICE_DATE,
    RR.CURRENCY_ID
FROM VFIN.dbo.RECEIVABLES_RECEIVABLE RR
WHERE RR.INVOICE_ID = @InvoiceId;

SELECT COUNT(*) AS VFIN_LINE_COUNT
FROM VFIN.dbo.RECEIVABLES_RECEIVABLE_LINE RL
WHERE RL.INVOICE_ID = @InvoiceId;

SELECT COUNT(*) AS VFIN_DIST_COUNT
FROM VFIN.dbo.RECEIVABLES_RECEIVABLE_DIST RD
WHERE RD.INVOICE_ID = @InvoiceId;

--------------------------------------------------------------------------------
-- 4) Customer readiness in both systems for this invoice
--------------------------------------------------------------------------------
SELECT
    R.INVOICE_ID,
    R.CUSTOMER_ID,
    CASE WHEN VC.ID IS NULL THEN 1 ELSE 0 END AS CUSTOMER_MISSING_IN_VECA,
    CASE WHEN VFRC.ID IS NULL THEN 1 ELSE 0 END AS CUSTOMER_MISSING_IN_VFIN
FROM VECA.dbo.RECEIVABLE R
LEFT JOIN VECA.dbo.CUSTOMER VC
    ON VC.ID = R.CUSTOMER_ID
LEFT JOIN VFIN.dbo.RECEIVABLES_CUSTOMER VFRC
    ON VFRC.ID = R.CUSTOMER_ID
WHERE R.INVOICE_ID = @InvoiceId;

--------------------------------------------------------------------------------
-- 5) Customer+Entity readiness (specific to "Customer Entity X/Y not found")
--------------------------------------------------------------------------------
SELECT
    R.INVOICE_ID,
    R.CUSTOMER_ID,
    'TDJ' AS EXPECTED_ENTITY_ID, -- inferred from current failure text
    CASE WHEN SE.ID IS NULL THEN 1 ELSE 0 END AS ENTITY_MISSING_IN_VFIN_SHARED_ENTITY,
    CASE WHEN RCE.CUSTOMER_ID IS NULL THEN 1 ELSE 0 END AS CUSTOMER_ENTITY_ROW_MISSING,
    RCE.ACTIVE_FLAG,
    RCE.CURRENCY_ID,
    RCE.TERMS_RULE_ID,
    RCE.RECV_ACCOUNT_ID,
    RCE.REV_ACCOUNT_ID
FROM VECA.dbo.RECEIVABLE R
LEFT JOIN VFIN.dbo.SHARED_ENTITY SE
    ON SE.ID = 'TDJ'
LEFT JOIN VFIN.dbo.RECEIVABLES_CUSTOMER_ENTITY RCE
    ON RCE.CUSTOMER_ID = R.CUSTOMER_ID
   AND RCE.ENTITY_ID = 'TDJ'
WHERE R.INVOICE_ID = @InvoiceId;

--------------------------------------------------------------------------------
-- 6) Account readiness for TDJ (customer defaults + invoice line GL accounts)
--------------------------------------------------------------------------------
SELECT
    R.INVOICE_ID,
    R.CUSTOMER_ID,
    RCE.RECV_ACCOUNT_ID,
    CASE WHEN RCE.RECV_ACCOUNT_ID IS NULL OR LTRIM(RTRIM(RCE.RECV_ACCOUNT_ID)) = '' THEN 1 ELSE 0 END AS RECV_ACCOUNT_IS_BLANK,
    CASE WHEN LRECV.ACCOUNT_ID IS NULL THEN 1 ELSE 0 END AS RECV_ACCOUNT_MISSING_IN_VFIN_LEDGER,
    RCE.REV_ACCOUNT_ID,
    CASE WHEN RCE.REV_ACCOUNT_ID IS NULL OR LTRIM(RTRIM(RCE.REV_ACCOUNT_ID)) = '' THEN 1 ELSE 0 END AS REV_ACCOUNT_IS_BLANK,
    CASE WHEN LREV.ACCOUNT_ID IS NULL AND ISNULL(LTRIM(RTRIM(RCE.REV_ACCOUNT_ID)), '') <> '' THEN 1 ELSE 0 END AS REV_ACCOUNT_MISSING_IN_VFIN_LEDGER
FROM VECA.dbo.RECEIVABLE R
LEFT JOIN VFIN.dbo.RECEIVABLES_CUSTOMER_ENTITY RCE
    ON RCE.CUSTOMER_ID = R.CUSTOMER_ID
   AND RCE.ENTITY_ID = 'TDJ'
LEFT JOIN VFIN.dbo.LEDGER_ACCOUNT LRECV
    ON LRECV.ENTITY_ID = 'TDJ'
   AND LRECV.ACCOUNT_ID = RCE.RECV_ACCOUNT_ID
LEFT JOIN VFIN.dbo.LEDGER_ACCOUNT LREV
    ON LREV.ENTITY_ID = 'TDJ'
   AND LREV.ACCOUNT_ID = RCE.REV_ACCOUNT_ID
WHERE R.INVOICE_ID = @InvoiceId;

SELECT
    RL.GL_ACCOUNT_ID AS VECA_LINE_GL_ACCOUNT_ID,
    COUNT(*) AS VECA_LINE_COUNT,
    CASE WHEN LA.ACCOUNT_ID IS NULL THEN 1 ELSE 0 END AS MISSING_IN_VFIN_LEDGER_ACCOUNT
FROM VECA.dbo.RECEIVABLE_LINE RL
LEFT JOIN VFIN.dbo.LEDGER_ACCOUNT LA
    ON LA.ENTITY_ID = 'TDJ'
   AND LA.ACCOUNT_ID = RL.GL_ACCOUNT_ID
WHERE RL.INVOICE_ID = @InvoiceId
GROUP BY RL.GL_ACCOUNT_ID, CASE WHEN LA.ACCOUNT_ID IS NULL THEN 1 ELSE 0 END
ORDER BY MISSING_IN_VFIN_LEDGER_ACCOUNT DESC, RL.GL_ACCOUNT_ID;

--------------------------------------------------------------------------------
-- 7) Compare account defaults vs other TDJ customers
-- Shows whether this customer/entity setup is an outlier.
--------------------------------------------------------------------------------
WITH TARGET AS (
    SELECT TOP 1
        R.INVOICE_ID,
        R.CUSTOMER_ID
    FROM VECA.dbo.RECEIVABLE R
    WHERE R.INVOICE_ID = @InvoiceId
),
TDJ_CUSTOMERS AS (
    SELECT
        RCE.CUSTOMER_ID,
        RCE.ENTITY_ID,
        RCE.ACTIVE_FLAG,
        RCE.CURRENCY_ID,
        RCE.TERMS_RULE_ID,
        RCE.RECV_ACCOUNT_ID,
        RCE.REV_ACCOUNT_ID
    FROM VFIN.dbo.RECEIVABLES_CUSTOMER_ENTITY RCE
    WHERE RCE.ENTITY_ID = 'TDJ'
)
SELECT
    CASE WHEN C.CUSTOMER_ID = T.CUSTOMER_ID THEN 1 ELSE 0 END AS IS_TARGET_CUSTOMER,
    C.CUSTOMER_ID,
    C.ACTIVE_FLAG,
    C.CURRENCY_ID,
    C.TERMS_RULE_ID,
    C.RECV_ACCOUNT_ID,
    C.REV_ACCOUNT_ID,
    CASE WHEN C.RECV_ACCOUNT_ID IS NULL OR LTRIM(RTRIM(C.RECV_ACCOUNT_ID)) = '' THEN 1 ELSE 0 END AS RECV_ACCOUNT_IS_BLANK,
    CASE WHEN C.REV_ACCOUNT_ID IS NULL OR LTRIM(RTRIM(C.REV_ACCOUNT_ID)) = '' THEN 1 ELSE 0 END AS REV_ACCOUNT_IS_BLANK,
    CASE WHEN LRECV.ACCOUNT_ID IS NULL AND ISNULL(LTRIM(RTRIM(C.RECV_ACCOUNT_ID)), '') <> '' THEN 1 ELSE 0 END AS RECV_ACCOUNT_MISSING_IN_LEDGER,
    CASE WHEN LREV.ACCOUNT_ID IS NULL AND ISNULL(LTRIM(RTRIM(C.REV_ACCOUNT_ID)), '') <> '' THEN 1 ELSE 0 END AS REV_ACCOUNT_MISSING_IN_LEDGER
FROM TDJ_CUSTOMERS C
CROSS JOIN TARGET T
LEFT JOIN VFIN.dbo.LEDGER_ACCOUNT LRECV
    ON LRECV.ENTITY_ID = 'TDJ'
   AND LRECV.ACCOUNT_ID = C.RECV_ACCOUNT_ID
LEFT JOIN VFIN.dbo.LEDGER_ACCOUNT LREV
    ON LREV.ENTITY_ID = 'TDJ'
   AND LREV.ACCOUNT_ID = C.REV_ACCOUNT_ID
ORDER BY IS_TARGET_CUSTOMER DESC, REV_ACCOUNT_IS_BLANK DESC, RECV_ACCOUNT_IS_BLANK DESC, C.CUSTOMER_ID;

-- Quick frequency view of account combos used in TDJ
SELECT
    RCE.RECV_ACCOUNT_ID,
    RCE.REV_ACCOUNT_ID,
    COUNT(*) AS CUSTOMER_COUNT
FROM VFIN.dbo.RECEIVABLES_CUSTOMER_ENTITY RCE
WHERE RCE.ENTITY_ID = 'TDJ'
  AND ISNULL(RCE.ACTIVE_FLAG, 0) = 1
GROUP BY RCE.RECV_ACCOUNT_ID, RCE.REV_ACCOUNT_ID
ORDER BY CUSTOMER_COUNT DESC, RCE.RECV_ACCOUNT_ID, RCE.REV_ACCOUNT_ID;
