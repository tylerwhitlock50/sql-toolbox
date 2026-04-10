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
