/*
================================================================================
  DIAGNOSE EXCHANGE SUBSCRIPTIONS - The Definitive Overlap Map
================================================================================
  Uses the Infor Visual Exchange metadata in the LSA database to answer:
    "Which VECA tables flow into VFIN via sync, and which are standalone?"

  Run these diagnostics in order. Each section builds on the last.
================================================================================
*/

--------------------------------------------------------------------------------
-- DIAGNOSTIC 1: All database instances configured in Exchange
-- Identifies the exact instance names (e.g., VECA_PROD, VFIN_PROD).
-- You'll use these instance names as filters in the queries below.
--------------------------------------------------------------------------------
SELECT
    DI.INSTANCE_NAME,
    DI.DESCRIPTION,
    DI.APPLICATION_ID,
    A.DESCRIPTION      AS APPLICATION_DESCRIPTION,
    DI.DATASOURCE,
    DI.SERVER_NAME
FROM LSA.dbo.EXCHANGE_DATABASE_INSTANCE DI
LEFT JOIN LSA.dbo.EXCHANGE_APPLICATION A ON DI.APPLICATION_ID = A.ID
ORDER BY DI.APPLICATION_ID, DI.INSTANCE_NAME;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 2: All active subscriptions VECA -> VFIN
-- THIS IS THE KEY ANSWER. Shows exactly which documents flow from
-- a VECA instance to a VFIN instance, with the underlying table names.
--------------------------------------------------------------------------------
SELECT
    S.ID                    AS SUBSCRIPTION_ID,
    S.DESCRIPTION           AS SUBSCRIPTION_DESC,
    S.PUB_INSTANCE_NAME     AS PUB_INSTANCE,
    S.PUB_DOCUMENT_ID       AS PUB_DOCUMENT,
    PD.ROOT_TABLE_NAME      AS PUB_TABLE,
    PD.DESCRIPTION          AS PUB_DOC_DESC,
    S.SUB_INSTANCE_NAME     AS SUB_INSTANCE,
    S.SUB_DOCUMENT_ID       AS SUB_DOCUMENT,
    SD.ROOT_TABLE_NAME      AS SUB_TABLE,
    SD.DESCRIPTION          AS SUB_DOC_DESC,
    S.TRANSFORMATION_ID,
    S.ACTIVE,
    S.SCHEDULE_EXPR
FROM LSA.dbo.EXCHANGE_SUBSCRIPTION S
LEFT JOIN LSA.dbo.EXCHANGE_DOCUMENT PD ON S.PUB_DOCUMENT_ID = PD.ID
LEFT JOIN LSA.dbo.EXCHANGE_DOCUMENT SD ON S.SUB_DOCUMENT_ID = SD.ID
WHERE S.PUB_INSTANCE_NAME LIKE '%VECA%'   -- or 'VMFG%' - adjust to match your instance naming
   OR S.SUB_INSTANCE_NAME LIKE '%VFIN%'
ORDER BY S.ACTIVE DESC, S.PUB_DOCUMENT_ID;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 3: All subscriptions going in the REVERSE direction (VFIN -> VECA)
-- Some data may flow from VFIN back to VECA (e.g., customer updates).
-- Good to know about these too.
--------------------------------------------------------------------------------
SELECT
    S.ID                    AS SUBSCRIPTION_ID,
    S.DESCRIPTION,
    S.PUB_INSTANCE_NAME,
    S.PUB_DOCUMENT_ID,
    PD.ROOT_TABLE_NAME      AS PUB_TABLE,
    S.SUB_INSTANCE_NAME,
    S.SUB_DOCUMENT_ID,
    SD.ROOT_TABLE_NAME      AS SUB_TABLE,
    S.ACTIVE
FROM LSA.dbo.EXCHANGE_SUBSCRIPTION S
LEFT JOIN LSA.dbo.EXCHANGE_DOCUMENT PD ON S.PUB_DOCUMENT_ID = PD.ID
LEFT JOIN LSA.dbo.EXCHANGE_DOCUMENT SD ON S.SUB_DOCUMENT_ID = SD.ID
WHERE S.PUB_INSTANCE_NAME LIKE '%VFIN%'
  AND S.SUB_INSTANCE_NAME LIKE '%VECA%'
ORDER BY S.ACTIVE DESC, S.PUB_DOCUMENT_ID;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 4: All subscriptions regardless of direction
-- In case our instance naming guess above is wrong, this shows EVERY
-- subscription. Look for the patterns in INSTANCE_NAME columns.
--------------------------------------------------------------------------------
SELECT
    S.ID                    AS SUBSCRIPTION_ID,
    S.PUB_INSTANCE_NAME,
    S.PUB_DOCUMENT_ID,
    PD.ROOT_TABLE_NAME      AS PUB_TABLE,
    S.SUB_INSTANCE_NAME,
    S.SUB_DOCUMENT_ID,
    SD.ROOT_TABLE_NAME      AS SUB_TABLE,
    S.ACTIVE
FROM LSA.dbo.EXCHANGE_SUBSCRIPTION S
LEFT JOIN LSA.dbo.EXCHANGE_DOCUMENT PD ON S.PUB_DOCUMENT_ID = PD.ID
LEFT JOIN LSA.dbo.EXCHANGE_DOCUMENT SD ON S.SUB_DOCUMENT_ID = SD.ID
ORDER BY S.PUB_INSTANCE_NAME, S.SUB_INSTANCE_NAME, S.PUB_DOCUMENT_ID;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 5: Column mappings for any GL-related subscription
-- For each subscription that involves RECEIVABLE, PAYABLE, PAYMENT, or
-- journal-related documents, show the column-level mapping.
--------------------------------------------------------------------------------
SELECT
    S.ID                    AS SUBSCRIPTION_ID,
    S.PUB_DOCUMENT_ID,
    M.PUB_TABLE_NAME,
    M.PUB_COLUMN_NAME,
    S.SUB_DOCUMENT_ID,
    M.SUB_TABLE_NAME,
    M.SUB_COLUMN_NAME,
    M.EXPRESSION
FROM LSA.dbo.EXCHANGE_SUBSCRIPTION S
INNER JOIN LSA.dbo.EXCHANGE_TRANSFORMATION T ON S.TRANSFORMATION_ID = T.ID
INNER JOIN LSA.dbo.EXCHANGE_TRANSFORM_MAP M ON T.TRANSFORM_ID = M.TRANSFORM_ID
WHERE (S.PUB_DOCUMENT_ID LIKE '%RECEIV%'
    OR S.PUB_DOCUMENT_ID LIKE '%PAYABLE%'
    OR S.PUB_DOCUMENT_ID LIKE '%PAYMENT%'
    OR S.PUB_DOCUMENT_ID LIKE '%JOURNAL%'
    OR S.PUB_DOCUMENT_ID LIKE '%BANK%'
    OR S.PUB_DOCUMENT_ID LIKE '%GL%')
ORDER BY S.ID, M.PUB_TABLE_NAME, M.PUB_COLUMN_NAME;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 6: Recent exchange activity (last 7 days)
-- Shows what's actually been syncing. Confirms the subscriptions are live
-- and shows the volume of activity.
--------------------------------------------------------------------------------
SELECT TOP 100
    A.SUBSCRIPTION_ID,
    A.PUB_INSTANCE_NAME,
    A.PUB_DOCUMENT_ID,
    A.PUB_KEY_DATA,
    A.SUB_INSTANCE_NAME,
    A.SUB_DOCUMENT_ID,
    A.STATUS,
    A.RECORD_CREATED,
    A.MESSAGE
FROM LSA.dbo.EXCHANGE_ACTIVITY A
WHERE A.RECORD_CREATED >= DATEADD(day, -7, GETDATE())
ORDER BY A.RECORD_CREATED DESC;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 7: Activity stats by subscription (daily counts)
-- Shows which subscriptions are most active. Use this to know which data
-- flows matter most.
--------------------------------------------------------------------------------
SELECT
    ST.SUBSCRIPTION_ID,
    ST.PUB_INSTANCE_NAME,
    ST.PUB_DOCUMENT_ID,
    ST.SUB_INSTANCE_NAME,
    ST.SUB_DOCUMENT_ID,
    SUM(ST.COMPLETE_COUNT) AS TOTAL_COMPLETED,
    SUM(ST.ERROR_COUNT)    AS TOTAL_ERRORS,
    SUM(ST.WARNING_COUNT)  AS TOTAL_WARNINGS,
    MIN(ST.ACTIVITY_DATE)  AS FIRST_ACTIVITY,
    MAX(ST.ACTIVITY_DATE)  AS LAST_ACTIVITY
FROM LSA.dbo.EXCHANGE_ACTIVITY_STATS ST
WHERE ST.ACTIVITY_DATE >= DATEADD(day, -30, GETDATE())
GROUP BY ST.SUBSCRIPTION_ID, ST.PUB_INSTANCE_NAME, ST.PUB_DOCUMENT_ID,
         ST.SUB_INSTANCE_NAME, ST.SUB_DOCUMENT_ID
ORDER BY TOTAL_COMPLETED DESC;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 7B: Error drill-down for one subscription/document pair
-- Query 7 is aggregate-only; use this to see the actual failing records.
-- Set one or more filters below from your Query 7 row.
--------------------------------------------------------------------------------
DECLARE @DiagSubscriptionId nvarchar(128) = 'VECA_VFIN_RECV_INVOICE'; -- from Query 7 SUBSCRIPTION_ID (NULL to ignore)
DECLARE @DiagPubDocument   nvarchar(128) = 'VMFG_RECEIVABLE';         -- from Query 7 PUB_DOCUMENT_ID (NULL to ignore)
DECLARE @DiagSubDocument   nvarchar(128) = 'VFIN_RECV_INVOICE';       -- from Query 7 SUB_DOCUMENT_ID (NULL to ignore)
DECLARE @DiagDaysBack      int           = 30;                        -- lookback window

SELECT TOP 200
    A.SUBSCRIPTION_ID,
    A.PUB_INSTANCE_NAME,
    A.PUB_DOCUMENT_ID,
    A.PUB_KEY_DATA,
    A.SUB_INSTANCE_NAME,
    A.SUB_DOCUMENT_ID,
    A.STATUS,
    A.RECORD_CREATED,
    A.MESSAGE
FROM LSA.dbo.EXCHANGE_ACTIVITY A
WHERE A.RECORD_CREATED >= DATEADD(day, -@DiagDaysBack, GETDATE())
  AND (@DiagSubscriptionId IS NULL OR @DiagSubscriptionId = '' OR A.SUBSCRIPTION_ID = @DiagSubscriptionId)
  AND (@DiagPubDocument   IS NULL OR @DiagPubDocument   = '' OR A.PUB_DOCUMENT_ID = @DiagPubDocument)
  AND (@DiagSubDocument   IS NULL OR @DiagSubDocument   = '' OR A.SUB_DOCUMENT_ID = @DiagSubDocument)
  AND (A.STATUS LIKE '%ERR%' OR A.STATUS LIKE '%FAIL%' OR ISNULL(A.MESSAGE, '') <> '')
ORDER BY A.RECORD_CREATED DESC;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 7C: Error summary by status/message for same subscription
-- Helps identify the dominant failure mode quickly.
--------------------------------------------------------------------------------
SELECT
    A.STATUS,
    LEFT(ISNULL(A.MESSAGE, '(no message)'), 300) AS MESSAGE_SAMPLE,
    COUNT(*) AS HIT_COUNT,
    MIN(A.RECORD_CREATED) AS FIRST_SEEN,
    MAX(A.RECORD_CREATED) AS LAST_SEEN
FROM LSA.dbo.EXCHANGE_ACTIVITY A
WHERE A.RECORD_CREATED >= DATEADD(day, -@DiagDaysBack, GETDATE())
  AND (@DiagSubscriptionId IS NULL OR @DiagSubscriptionId = '' OR A.SUBSCRIPTION_ID = @DiagSubscriptionId)
  AND (@DiagPubDocument   IS NULL OR @DiagPubDocument   = '' OR A.PUB_DOCUMENT_ID = @DiagPubDocument)
  AND (@DiagSubDocument   IS NULL OR @DiagSubDocument   = '' OR A.SUB_DOCUMENT_ID = @DiagSubDocument)
  AND (A.STATUS LIKE '%ERR%' OR A.STATUS LIKE '%FAIL%' OR ISNULL(A.MESSAGE, '') <> '')
GROUP BY A.STATUS, LEFT(ISNULL(A.MESSAGE, '(no message)'), 300)
ORDER BY HIT_COUNT DESC, LAST_SEEN DESC;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 7D: Transform + settings required by the subscription
-- Use this when message says "constant not set" to find missing VALUE rows.
--------------------------------------------------------------------------------
SELECT
    S.ID AS SUBSCRIPTION_ID,
    S.PUB_INSTANCE_NAME,
    S.PUB_DOCUMENT_ID,
    S.SUB_INSTANCE_NAME,
    S.SUB_DOCUMENT_ID,
    S.TRANSFORMATION_ID,
    X.SEQ_NO,
    X.TRANSFORM_ID,
    T.DESCRIPTION AS TRANSFORM_DESC,
    T.CLASS_NAME,
    TS.NAME  AS SETTING_NAME,
    TS.VALUE AS SETTING_VALUE
FROM LSA.dbo.EXCHANGE_SUBSCRIPTION S
LEFT JOIN LSA.dbo.EXCHANGE_TRANSFORMATION X
    ON S.TRANSFORMATION_ID = X.ID
LEFT JOIN LSA.dbo.EXCHANGE_TRANSFORM T
    ON X.TRANSFORM_ID = T.ID
LEFT JOIN LSA.dbo.EXCHANGE_TRANSFORM_SETTINGS TS
    ON TS.TRANSFORM_ID = X.TRANSFORM_ID
   AND TS.PUB_INSTANCE_NAME = S.PUB_INSTANCE_NAME
   AND TS.SUB_INSTANCE_NAME = S.SUB_INSTANCE_NAME
WHERE (@DiagSubscriptionId IS NULL OR @DiagSubscriptionId = '' OR S.ID = @DiagSubscriptionId)
  AND (@DiagPubDocument   IS NULL OR @DiagPubDocument   = '' OR S.PUB_DOCUMENT_ID = @DiagPubDocument)
  AND (@DiagSubDocument   IS NULL OR @DiagSubDocument   = '' OR S.SUB_DOCUMENT_ID = @DiagSubDocument)
ORDER BY S.ID, X.SEQ_NO, TS.NAME;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 7E: Suspected missing/blank setting values
-- Focus list for "constant not set" errors.
--------------------------------------------------------------------------------
SELECT
    S.ID AS SUBSCRIPTION_ID,
    X.SEQ_NO,
    X.TRANSFORM_ID,
    TS.NAME  AS SETTING_NAME,
    TS.VALUE AS SETTING_VALUE
FROM LSA.dbo.EXCHANGE_SUBSCRIPTION S
INNER JOIN LSA.dbo.EXCHANGE_TRANSFORMATION X
    ON S.TRANSFORMATION_ID = X.ID
LEFT JOIN LSA.dbo.EXCHANGE_TRANSFORM_SETTINGS TS
    ON TS.TRANSFORM_ID = X.TRANSFORM_ID
   AND TS.PUB_INSTANCE_NAME = S.PUB_INSTANCE_NAME
   AND TS.SUB_INSTANCE_NAME = S.SUB_INSTANCE_NAME
WHERE (@DiagSubscriptionId IS NULL OR @DiagSubscriptionId = '' OR S.ID = @DiagSubscriptionId)
  AND (@DiagPubDocument   IS NULL OR @DiagPubDocument   = '' OR S.PUB_DOCUMENT_ID = @DiagPubDocument)
  AND (@DiagSubDocument   IS NULL OR @DiagSubDocument   = '' OR S.SUB_DOCUMENT_ID = @DiagSubDocument)
  AND (TS.NAME IS NULL OR TS.VALUE IS NULL OR LTRIM(RTRIM(TS.VALUE)) = '')
ORDER BY S.ID, X.SEQ_NO, TS.NAME;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 7F: Compare sibling receivable transform settings
-- Helps identify setting names present on related transforms but absent here.
--------------------------------------------------------------------------------
WITH TARGET AS (
    SELECT TOP 1
        S.ID AS SUBSCRIPTION_ID,
        S.PUB_INSTANCE_NAME,
        S.SUB_INSTANCE_NAME,
        X.TRANSFORM_ID,
        T.CLASS_NAME
    FROM LSA.dbo.EXCHANGE_SUBSCRIPTION S
    INNER JOIN LSA.dbo.EXCHANGE_TRANSFORMATION X
        ON S.TRANSFORMATION_ID = X.ID
    LEFT JOIN LSA.dbo.EXCHANGE_TRANSFORM T
        ON X.TRANSFORM_ID = T.ID
    WHERE (@DiagSubscriptionId IS NULL OR @DiagSubscriptionId = '' OR S.ID = @DiagSubscriptionId)
      AND (@DiagPubDocument   IS NULL OR @DiagPubDocument   = '' OR S.PUB_DOCUMENT_ID = @DiagPubDocument)
      AND (@DiagSubDocument   IS NULL OR @DiagSubDocument   = '' OR S.SUB_DOCUMENT_ID = @DiagSubDocument)
),
TARGET_SETTINGS AS (
    SELECT TS.NAME
    FROM TARGET TG
    INNER JOIN LSA.dbo.EXCHANGE_TRANSFORM_SETTINGS TS
      ON TS.TRANSFORM_ID = TG.TRANSFORM_ID
     AND TS.PUB_INSTANCE_NAME = TG.PUB_INSTANCE_NAME
     AND TS.SUB_INSTANCE_NAME = TG.SUB_INSTANCE_NAME
),
SIBLING_SETTINGS AS (
    SELECT
        X2.TRANSFORM_ID,
        TS2.NAME,
        TS2.VALUE
    FROM TARGET TG
    INNER JOIN LSA.dbo.EXCHANGE_TRANSFORM T2
      ON T2.CLASS_NAME = TG.CLASS_NAME
    INNER JOIN LSA.dbo.EXCHANGE_TRANSFORMATION X2
      ON X2.TRANSFORM_ID = T2.ID
    INNER JOIN LSA.dbo.EXCHANGE_TRANSFORM_SETTINGS TS2
      ON TS2.TRANSFORM_ID = X2.TRANSFORM_ID
     AND TS2.PUB_INSTANCE_NAME = TG.PUB_INSTANCE_NAME
     AND TS2.SUB_INSTANCE_NAME = TG.SUB_INSTANCE_NAME
)
SELECT DISTINCT
    SS.TRANSFORM_ID          AS SIBLING_TRANSFORM_ID,
    SS.NAME                  AS SETTING_NAME,
    SS.VALUE                 AS SIBLING_SETTING_VALUE,
    CASE WHEN TS.NAME IS NULL THEN 1 ELSE 0 END AS MISSING_ON_TARGET
FROM SIBLING_SETTINGS SS
LEFT JOIN TARGET_SETTINGS TS
  ON TS.NAME = SS.NAME
ORDER BY MISSING_ON_TARGET DESC, SS.NAME, SS.TRANSFORM_ID;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 7G: Same transform settings across all instance pairs
-- If another instance pair has an extra required setting name/value, copy it.
--------------------------------------------------------------------------------
SELECT
    TS.TRANSFORM_ID,
    TS.PUB_INSTANCE_NAME,
    TS.SUB_INSTANCE_NAME,
    TS.NAME  AS SETTING_NAME,
    TS.VALUE AS SETTING_VALUE
FROM LSA.dbo.EXCHANGE_TRANSFORM_SETTINGS TS
WHERE TS.TRANSFORM_ID IN (
    SELECT X.TRANSFORM_ID
    FROM LSA.dbo.EXCHANGE_SUBSCRIPTION S
    INNER JOIN LSA.dbo.EXCHANGE_TRANSFORMATION X
        ON S.TRANSFORMATION_ID = X.ID
    WHERE (@DiagSubscriptionId IS NULL OR @DiagSubscriptionId = '' OR S.ID = @DiagSubscriptionId)
      AND (@DiagPubDocument   IS NULL OR @DiagPubDocument   = '' OR S.PUB_DOCUMENT_ID = @DiagPubDocument)
      AND (@DiagSubDocument   IS NULL OR @DiagSubDocument   = '' OR S.SUB_DOCUMENT_ID = @DiagSubDocument)
)
ORDER BY TS.TRANSFORM_ID, TS.NAME, TS.PUB_INSTANCE_NAME, TS.SUB_INSTANCE_NAME;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 7H: Candidate "existing invoice" settings anywhere in Exchange
-- Fast keyword hunt when error references a constant name not shown in 7D/7F.
--------------------------------------------------------------------------------
SELECT
    TS.TRANSFORM_ID,
    TS.PUB_INSTANCE_NAME,
    TS.SUB_INSTANCE_NAME,
    TS.NAME  AS SETTING_NAME,
    TS.VALUE AS SETTING_VALUE
FROM LSA.dbo.EXCHANGE_TRANSFORM_SETTINGS TS
WHERE TS.NAME  LIKE '%exist%'
   OR TS.NAME  LIKE '%invoice%'
   OR TS.VALUE LIKE '%exist%'
   OR TS.VALUE LIKE '%invoice%'
ORDER BY TS.TRANSFORM_ID, TS.NAME, TS.PUB_INSTANCE_NAME, TS.SUB_INSTANCE_NAME;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 7I: Transform internals (class/script + map expressions)
-- Surfaces expression tokens that may reference hidden constants.
--------------------------------------------------------------------------------
SELECT
    X.TRANSFORM_ID,
    T.DESCRIPTION AS TRANSFORM_DESC,
    T.CLASS_NAME,
    T.SCRIPT_NAME,
    M.PUB_TABLE_NAME,
    M.PUB_COLUMN_NAME,
    M.SUB_TABLE_NAME,
    M.SUB_COLUMN_NAME,
    M.EXPRESSION
FROM LSA.dbo.EXCHANGE_SUBSCRIPTION S
INNER JOIN LSA.dbo.EXCHANGE_TRANSFORMATION X
    ON S.TRANSFORMATION_ID = X.ID
LEFT JOIN LSA.dbo.EXCHANGE_TRANSFORM T
    ON X.TRANSFORM_ID = T.ID
LEFT JOIN LSA.dbo.EXCHANGE_TRANSFORM_MAP M
    ON M.TRANSFORM_ID = X.TRANSFORM_ID
WHERE (@DiagSubscriptionId IS NULL OR @DiagSubscriptionId = '' OR S.ID = @DiagSubscriptionId)
  AND (@DiagPubDocument   IS NULL OR @DiagPubDocument   = '' OR S.PUB_DOCUMENT_ID = @DiagPubDocument)
  AND (@DiagSubDocument   IS NULL OR @DiagSubDocument   = '' OR S.SUB_DOCUMENT_ID = @DiagSubDocument)
ORDER BY X.TRANSFORM_ID, M.PUB_TABLE_NAME, M.PUB_COLUMN_NAME, M.SUB_TABLE_NAME, M.SUB_COLUMN_NAME;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 7J: Failed-invoice prerequisite checks (for BeforeAll null errors)
-- Pulls recent failed invoice IDs and validates key upstream references.
--------------------------------------------------------------------------------
DECLARE @DiagTopFailed int = 100; -- number of recent failed invoices to inspect

WITH RECENT_FAILED AS (
    SELECT TOP (@DiagTopFailed)
        LTRIM(RTRIM(REPLACE(REPLACE(A.PUB_KEY_DATA, '"', ''), '''', ''))) AS INVOICE_ID,
        MAX(A.RECORD_CREATED) AS LAST_ERROR_AT
    FROM LSA.dbo.EXCHANGE_ACTIVITY A
    WHERE A.RECORD_CREATED >= DATEADD(day, -@DiagDaysBack, GETDATE())
      AND (@DiagSubscriptionId IS NULL OR @DiagSubscriptionId = '' OR A.SUBSCRIPTION_ID = @DiagSubscriptionId)
      AND (@DiagPubDocument   IS NULL OR @DiagPubDocument   = '' OR A.PUB_DOCUMENT_ID = @DiagPubDocument)
      AND (@DiagSubDocument   IS NULL OR @DiagSubDocument   = '' OR A.SUB_DOCUMENT_ID = @DiagSubDocument)
      AND (A.STATUS LIKE '%ERR%' OR A.MESSAGE LIKE '%BeforeAll%' OR A.MESSAGE LIKE '%not valid for exchange%')
      AND ISNULL(A.PUB_KEY_DATA, '') <> ''
    GROUP BY LTRIM(RTRIM(REPLACE(REPLACE(A.PUB_KEY_DATA, '"', ''), '''', '')))
    ORDER BY MAX(A.RECORD_CREATED) DESC
)
SELECT
    F.INVOICE_ID,
    F.LAST_ERROR_AT,
    R.CUSTOMER_ID,
    R.STATUS AS INVOICE_STATUS,
    R.POSTING_DATE,
    R.CURRENCY_ID,
    CASE WHEN R.INVOICE_ID IS NULL THEN 1 ELSE 0 END AS MISSING_RECEIVABLE_HEADER,
    CASE WHEN RL.LINE_COUNT IS NULL OR RL.LINE_COUNT = 0 THEN 1 ELSE 0 END AS MISSING_RECEIVABLE_LINES,
    RL.LINE_COUNT,
    CASE WHEN VC.ID IS NULL THEN 1 ELSE 0 END AS CUSTOMER_MISSING_IN_VECA_CUSTOMER,
    CASE WHEN VFRC.ID IS NULL THEN 1 ELSE 0 END AS CUSTOMER_MISSING_IN_VFIN_RECEIVABLES_CUSTOMER
FROM RECENT_FAILED F
LEFT JOIN VECA.dbo.RECEIVABLE R
    ON R.INVOICE_ID = F.INVOICE_ID
LEFT JOIN (
    SELECT INVOICE_ID, COUNT(*) AS LINE_COUNT
    FROM VECA.dbo.RECEIVABLE_LINE
    GROUP BY INVOICE_ID
) RL
    ON RL.INVOICE_ID = F.INVOICE_ID
LEFT JOIN VECA.dbo.CUSTOMER VC
    ON VC.ID = R.CUSTOMER_ID
LEFT JOIN VFIN.dbo.RECEIVABLES_CUSTOMER VFRC
    ON VFRC.ID = R.CUSTOMER_ID
ORDER BY F.LAST_ERROR_AT DESC, F.INVOICE_ID;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 7K: Are failed invoices already present in VFIN?
-- Error text references "Existing Receivable Invoice"; this checks for that.
--------------------------------------------------------------------------------
WITH RECENT_FAILED AS (
    SELECT TOP (@DiagTopFailed)
        LTRIM(RTRIM(REPLACE(REPLACE(A.PUB_KEY_DATA, '"', ''), '''', ''))) AS INVOICE_ID,
        MAX(A.RECORD_CREATED) AS LAST_ERROR_AT
    FROM LSA.dbo.EXCHANGE_ACTIVITY A
    WHERE A.RECORD_CREATED >= DATEADD(day, -@DiagDaysBack, GETDATE())
      AND (@DiagSubscriptionId IS NULL OR @DiagSubscriptionId = '' OR A.SUBSCRIPTION_ID = @DiagSubscriptionId)
      AND (@DiagPubDocument   IS NULL OR @DiagPubDocument   = '' OR A.PUB_DOCUMENT_ID = @DiagPubDocument)
      AND (@DiagSubDocument   IS NULL OR @DiagSubDocument   = '' OR A.SUB_DOCUMENT_ID = @DiagSubDocument)
      AND (A.STATUS LIKE '%ERR%' OR A.MESSAGE LIKE '%Existing Receivable Invoice%' OR A.MESSAGE LIKE '%BeforeAll%')
      AND ISNULL(A.PUB_KEY_DATA, '') <> ''
    GROUP BY LTRIM(RTRIM(REPLACE(REPLACE(A.PUB_KEY_DATA, '"', ''), '''', '')))
    ORDER BY MAX(A.RECORD_CREATED) DESC
)
SELECT
    F.INVOICE_ID,
    F.LAST_ERROR_AT,
    VR.INVOICE_ID AS VFIN_INVOICE_ID,
    VR.ENTITY_ID  AS VFIN_ENTITY_ID,
    VR.INVOICE_STATUS AS VFIN_INVOICE_STATUS,
    VR.INVOICE_DATE   AS VFIN_INVOICE_DATE,
    CASE WHEN VR.INVOICE_ID IS NULL THEN 0 ELSE 1 END AS EXISTS_IN_VFIN_RECEIVABLE,
    ISNULL(VRL.LINE_COUNT, 0) AS VFIN_LINE_COUNT,
    ISNULL(VRD.DIST_COUNT, 0) AS VFIN_DIST_COUNT
FROM RECENT_FAILED F
LEFT JOIN VFIN.dbo.RECEIVABLES_RECEIVABLE VR
    ON VR.INVOICE_ID = F.INVOICE_ID
LEFT JOIN (
    SELECT INVOICE_ID, COUNT(*) AS LINE_COUNT
    FROM VFIN.dbo.RECEIVABLES_RECEIVABLE_LINE
    GROUP BY INVOICE_ID
) VRL
    ON VRL.INVOICE_ID = F.INVOICE_ID
LEFT JOIN (
    SELECT INVOICE_ID, COUNT(*) AS DIST_COUNT
    FROM VFIN.dbo.RECEIVABLES_RECEIVABLE_DIST
    GROUP BY INVOICE_ID
) VRD
    ON VRD.INVOICE_ID = F.INVOICE_ID
ORDER BY F.LAST_ERROR_AT DESC, F.INVOICE_ID;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 7L: Single-invoice deep dive (focus case)
-- Use this for one invoice that still fails while others already exist in VFIN.
--------------------------------------------------------------------------------
DECLARE @FocusInvoiceId nvarchar(15) = 'INV-275213';

-- 7L-1) Recent exchange activity + task queue rows for this invoice
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
WHERE (@DiagSubscriptionId IS NULL OR @DiagSubscriptionId = '' OR A.SUBSCRIPTION_ID = @DiagSubscriptionId)
  AND A.PUB_KEY_DATA LIKE '%' + @FocusInvoiceId + '%'

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
WHERE (@DiagSubscriptionId IS NULL OR @DiagSubscriptionId = '' OR T.SUBSCRIPTION_ID = @DiagSubscriptionId)
  AND T.PUB_KEY_DATA LIKE '%' + @FocusInvoiceId + '%'
ORDER BY EVENT_TS DESC;


-- 7L-2) VECA header/line/dist snapshot for invoice
SELECT
    R.INVOICE_ID,
    R.CUSTOMER_ID,
    R.STATUS,
    R.POSTING_DATE,
    R.CURRENCY_ID,
    R.RECV_GL_ACCT_ID
FROM VECA.dbo.RECEIVABLE R
WHERE R.INVOICE_ID = @FocusInvoiceId;

SELECT
    COUNT(*) AS VECA_LINE_COUNT,
    SUM(CASE WHEN RL.QTY IS NULL THEN 1 ELSE 0 END) AS VECA_LINES_WITH_NULL_QTY,
    SUM(CASE WHEN RL.GL_ACCOUNT_ID IS NULL OR LTRIM(RTRIM(RL.GL_ACCOUNT_ID)) = '' THEN 1 ELSE 0 END) AS VECA_LINES_WITH_BLANK_GL
FROM VECA.dbo.RECEIVABLE_LINE RL
WHERE RL.INVOICE_ID = @FocusInvoiceId;

SELECT
    COUNT(*) AS VECA_DIST_COUNT,
    SUM(CASE WHEN RD.GL_ACCOUNT_ID IS NULL OR LTRIM(RTRIM(RD.GL_ACCOUNT_ID)) = '' THEN 1 ELSE 0 END) AS VECA_DIST_WITH_BLANK_GL
FROM VECA.dbo.RECEIVABLE_DIST RD
WHERE RD.INVOICE_ID = @FocusInvoiceId;


-- 7L-3) VFIN presence check for same invoice
SELECT
    RR.INVOICE_ID,
    RR.ENTITY_ID,
    RR.CUSTOMER_ID,
    RR.INVOICE_STATUS,
    RR.INVOICE_DATE,
    RR.CURRENCY_ID
FROM VFIN.dbo.RECEIVABLES_RECEIVABLE RR
WHERE RR.INVOICE_ID = @FocusInvoiceId;

SELECT COUNT(*) AS VFIN_LINE_COUNT
FROM VFIN.dbo.RECEIVABLES_RECEIVABLE_LINE RL
WHERE RL.INVOICE_ID = @FocusInvoiceId;

SELECT COUNT(*) AS VFIN_DIST_COUNT
FROM VFIN.dbo.RECEIVABLES_RECEIVABLE_DIST RD
WHERE RD.INVOICE_ID = @FocusInvoiceId;


-- 7L-4) Customer/entity readiness for this invoice
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
WHERE R.INVOICE_ID = @FocusInvoiceId;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 8: Cross-database foreign key relationships from LSA metadata
-- These are declared cross-database FKs. If you see a row where
-- DATASPACE_NAME <> PARENT_DATASPACE_NAME, that's a cross-DB relationship.
--------------------------------------------------------------------------------
SELECT
    DATASPACE_NAME          AS CHILD_DB,
    TABLE_NAME              AS CHILD_TABLE,
    RELATIONSHIP_NAME,
    PARENT_DATASPACE_NAME   AS PARENT_DB,
    PARENT_TABLE_NAME       AS PARENT_TABLE,
    COLUMN_1, COLUMN_2, COLUMN_3, COLUMN_4,
    DOCUMENTATION
FROM LSA.dbo.LSA_RELATIONSHIP
WHERE DATASPACE_NAME <> PARENT_DATASPACE_NAME
   OR PARENT_DATASPACE_NAME IN ('VECA', 'VFIN', 'LSA')
ORDER BY DATASPACE_NAME, TABLE_NAME, RELATIONSHIP_NAME;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 9: LSA_SITE - maps site IDs to VECA instances
-- Shows how VFIN entity+site combinations map to VECA instances.
-- This is the key for tying VFIN.PAYABLES_PAYABLE.SITE_ID back to a
-- specific VECA database.
--------------------------------------------------------------------------------
SELECT
    ENTITY_ID,
    SITE_ID,
    NAME,
    VMFG_INSTANCE_NAME  AS VECA_INSTANCE,
    VQ_INSTANCE_NAME    AS VQ_INSTANCE,
    VTA_INSTANCE_NAME   AS VTA_INSTANCE
FROM LSA.dbo.LSA_SITE
ORDER BY ENTITY_ID, SITE_ID;


--------------------------------------------------------------------------------
-- DIAGNOSTIC 10: LSA_SYNC recent activity by table
-- Shows which VECA/VFIN tables have had the most sync activity recently.
-- Confirms which tables are being actively synchronized.
--------------------------------------------------------------------------------
SELECT TOP 50
    DATASPACE_NAME,
    TABLE_NAME,
    SYNC_COMMAND,
    COUNT(*) AS SYNC_COUNT,
    MAX(SYNC_DATE) AS MOST_RECENT
FROM LSA.dbo.LSA_SYNC
WHERE SYNC_DATE >= DATEADD(day, -30, GETDATE())
GROUP BY DATASPACE_NAME, TABLE_NAME, SYNC_COMMAND
ORDER BY SYNC_COUNT DESC;


--------------------------------------------------------------------------------
-- NEXT STEPS
--------------------------------------------------------------------------------
-- 1. Run Diagnostic 1 to confirm actual instance names (replace VECA/VFIN
--    in Diagnostic 2 if needed)
-- 2. Review Diagnostic 2 - this is the DEFINITIVE list of what flows from
--    VECA to VFIN via sync. Any table pair in the result set is a potential
--    duplicate (same data in both DBs).
-- 3. For each duplicate pair, decide which is the source of truth for
--    reporting (typically the subscriber / VFIN).
-- 4. Update gl_posting_map.sql to exclude the VECA side of any confirmed
--    duplicate pair.
-- 5. Save the result of Diagnostic 2 somewhere - it's the definitive
--    overlap map for your environment.
