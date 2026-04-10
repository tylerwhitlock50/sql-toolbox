# LSA Database Reference (Infor Visual Exchange / Logical Sync Architecture)

The LSA database is the **integration/synchronization layer** between Infor Visual's various databases (VECA, VFIN, Visual Quality, Visual Trade Admin, etc.). It holds:

1. **Exchange configuration** - what documents flow from where to where
2. **Exchange activity log** - audit trail of every sync event
3. **Column-level transformation rules** between source and target schemas
4. **Cross-database relationship metadata**
5. **Site-to-instance mapping** - which VECA instance serves which site

**This is the definitive source of truth for understanding how data moves between VECA and VFIN.**

---

## Key Concepts

- **Instance** - A named database instance (e.g., `VECA_PROD`, `VFIN_PROD`)
- **Application** - A product (e.g., `VECA` = Visual Manufacturing, `VFIN` = Visual Financials)
- **Document** - A logical record type (e.g., `RECEIVABLE`, `CUSTOMER`, `PAYMENT`)
- **Subscription** - A publisher→subscriber relationship: "When VECA has a new RECEIVABLE, send it to VFIN"
- **Transformation** - The mapping rules used by a subscription (column-by-column)
- **Task** - One queued sync job (one row to be synchronized)
- **Activity** - Completed sync event (audit log entry)
- **Dataspace** - A database name used in metadata (e.g., `VECA`, `VFIN`)

---

## 1. Exchange Configuration (What Syncs Where)

### EXCHANGE_APPLICATION
Master list of participating applications.

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(30) | **Logical key**. e.g., `VECA`, `VFIN` |
| DESCRIPTION | nvarchar(40) | Human-readable name |
| CONNECTOR_ID | nvarchar(15) | FK to EXCHANGE_CONNECTOR |

### EXCHANGE_DATABASE_INSTANCE
Physical database instances (connection details).

| Column | Type | Notes |
|---|---|---|
| **INSTANCE_NAME** | nvarchar(30) | **Logical key**. e.g., `VECA_PROD` |
| APPLICATION_ID | nvarchar(30) | FK to EXCHANGE_APPLICATION |
| DESCRIPTION | nvarchar(40) | Human-readable name |
| DATASOURCE | nvarchar(128) | Server/database name |
| PROVIDER | nvarchar(128) | Database provider (SQL Server, etc.) |
| DRIVER | nvarchar(128) | ODBC/JDBC driver |
| USER_ID | nvarchar(128) | Connection user |
| PASSWORD | nvarchar(128) | Connection password |
| INBOUND_DIRECTORY / OUTBOUND_DIRECTORY | nvarchar(128) | File staging paths |
| SERVER_NAME | nvarchar(32) | Exchange service server |

### EXCHANGE_DOCUMENT
**Critical** - Maps document type IDs to actual database tables.

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(30) | **Logical key**. Document type identifier |
| APPLICATION_ID | nvarchar(30) | Which app owns this document type |
| DESCRIPTION | nvarchar(40) | Description |
| **ROOT_TABLE_NAME** | nvarchar(30) | **Actual database table name** |
| REFERENCE | nvarchar(128) | Reference label |
| LIBRARY_NAME / CLASS_NAME | nvarchar(128) | Handler class |
| CONNECTOR_ID | nvarchar(15) | Connector plugin |

### EXCHANGE_DOCUMENT_FORMAT / EXCHANGE_DOCUMENT_SCHEMA
- `EXCHANGE_DOCUMENT_FORMAT` - XML/file format structure per document
- `EXCHANGE_DOCUMENT_SCHEMA` - Column list per document (TABLE_NAME + COLUMN_NAME with PRIMARY_KEY flag and data type)

### EXCHANGE_SUBSCRIPTION
**The most important table for understanding what flows between databases.**

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(64) | **Logical key**. Subscription identifier |
| DESCRIPTION | nvarchar(40) | Description |
| **PUB_INSTANCE_NAME** | nvarchar(30) | **Publisher instance (source, e.g., `VECA_PROD`)** |
| **PUB_DOCUMENT_ID** | nvarchar(30) | **Document being published** |
| **SUB_INSTANCE_NAME** | nvarchar(30) | **Subscriber instance (destination, e.g., `VFIN_PROD`)** |
| **SUB_DOCUMENT_ID** | nvarchar(30) | **Document received by subscriber** |
| TRANSFORMATION_ID | nvarchar(30) | FK to EXCHANGE_TRANSFORMATION (mapping rules) |
| ACTIVE | int | Subscription active flag |
| SCHEDULE_EXPR | nvarchar(max) | Cron expression |
| INBOUND_FILE_NAME / OUTBOUND_FILE_NAME | nvarchar(250) | File naming patterns |
| SEQ_NO | int | Execution sequence |

**This is where you answer "what flows from VECA to VFIN?"** - query this table with `PUB_INSTANCE_NAME LIKE 'VECA%' AND SUB_INSTANCE_NAME LIKE 'VFIN%'`.

### EXCHANGE_SUB_STAGE_DOC
Links subscriptions to intermediate staging documents for multi-step transforms.

---

## 2. Transformation Rules (Column Mapping)

### EXCHANGE_TRANSFORM
Defines a transformation handler (publisher doc → subscriber doc).

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(30) | Transform identifier |
| DESCRIPTION | nvarchar(40) | Description |
| PUB_DOCUMENT_ID | nvarchar(30) | Source document type |
| SUB_DOCUMENT_ID | nvarchar(30) | Target document type |
| LIBRARY_NAME / CLASS_NAME | nvarchar(128) | Handler class |
| SCRIPT_NAME | nvarchar(128) | Custom script |

### EXCHANGE_TRANSFORMATION
An ordered list of transforms applied by a subscription.

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(30) | **Logical key (composite)** |
| **SEQ_NO** | smallint | **Logical key (composite)**. Execution order |
| TRANSFORM_ID | nvarchar(30) | FK to EXCHANGE_TRANSFORM |

### EXCHANGE_TRANSFORM_MAP
**The column-level mapping.** One row per column mapped from publisher table to subscriber table.

| Column | Type | Notes |
|---|---|---|
| TRANSFORM_ID | nvarchar(30) | FK to EXCHANGE_TRANSFORM |
| **PUB_TABLE_NAME** | nvarchar(30) | Source table |
| **PUB_COLUMN_NAME** | nvarchar(64) | Source column |
| **SUB_TABLE_NAME** | nvarchar(30) | Target table |
| **SUB_COLUMN_NAME** | nvarchar(64) | Target column |
| EXPRESSION | nvarchar(250) | Optional formula/transformation |

**Example use:** To find which VECA column maps to which VFIN column for a given table pair, query this with `PUB_TABLE_NAME = 'RECEIVABLE_DIST' AND SUB_TABLE_NAME = 'RECEIVABLES_RECEIVABLE_DIST'`.

### EXCHANGE_TRANSFORM_SETTINGS
Per-instance configuration overrides for a transform.

---

## 3. Sync Activity (Audit Log)

### EXCHANGE_ACTIVITY
**Master audit trail.** Every sync event produces a row here.

| Column | Type | Notes |
|---|---|---|
| SUBSCRIPTION_ID | nvarchar(64) | FK to EXCHANGE_SUBSCRIPTION |
| **PUB_INSTANCE_NAME** | nvarchar(30) | Source instance |
| **PUB_DOCUMENT_ID** | nvarchar(30) | Document type |
| **PUB_RECORD_ID** | nvarchar(128) | Source record identifier |
| PUB_COMMAND | nvarchar(32) | INSERT / UPDATE / DELETE |
| **PUB_KEY_DATA** | nvarchar(250) | **Composite key values from source row** |
| SUB_INSTANCE_NAME | nvarchar(30) | Target instance |
| SUB_DOCUMENT_ID | nvarchar(30) | Target document type |
| STATUS | nvarchar(32) | PENDING / PROCESSING / COMPLETE / ERROR |
| SOURCE | nvarchar(30) | Source system identifier |
| MESSAGE | nvarchar(250) | Status/error message |
| NOTIFY_PROCESSED | int | Notification flag |

### EXCHANGE_ACTIVITY_STATS
Daily rollup of sync activity by subscription.

| Column | Type | Notes |
|---|---|---|
| SUBSCRIPTION_ID | nvarchar(64) | |
| ACTIVITY_DATE | datetime | |
| PUB_INSTANCE_NAME, SUB_INSTANCE_NAME | nvarchar(30) | |
| PUB_DOCUMENT_ID, SUB_DOCUMENT_ID | nvarchar(30) | |
| COMPLETE_COUNT / ERROR_COUNT / WARNING_COUNT | int | |

### EXCHANGE_TASK
Queued sync tasks (one per row to be synchronized).

| Column | Type | Notes |
|---|---|---|
| SUBSCRIPTION_ID | nvarchar(64) | |
| PUB_INSTANCE_NAME | nvarchar(30) | Source instance |
| PUB_DOCUMENT_ID | nvarchar(30) | Document type |
| PUB_RECORD_ID | nvarchar(128) | Source row identifier |
| **PUB_KEY_COLUMNS** | nvarchar(250) | Names of the key columns |
| **PUB_KEY_DATA** | nvarchar(250) | Composite key values |
| PUB_COMMAND | nvarchar(32) | INSERT / UPDATE / DELETE |
| PUB_DATE | datetime | When published |
| SUB_INSTANCE_NAME | nvarchar(30) | Target instance |
| SUB_DOCUMENT_ID | nvarchar(30) | Target document |
| SCHEDULED_TIME | datetime | When to run |
| STATUS | nvarchar(32) | Processing state |

### EXCHANGE_TASK_STAGING
Intermediate staging records during multi-step transforms.

### EXCHANGE_ERROR_REPORTING
Error logging with object context and notification addresses.

---

## 4. Lower-Level LSA Metadata

### LSA_SYNC
**Row-level sync log.** Every row change is logged here with its composite key.

**PK:** DATASPACE_NAME + TABLE_NAME + DATA_IDENTITY + SYNC_DATE

| Column | Type | Notes |
|---|---|---|
| DATASPACE_NAME | nvarchar(30) | Application/database name |
| TABLE_NAME | nvarchar(30) | Table being synced |
| DATA_IDENTITY | nvarchar(12) | RECORD_IDENTITY of the row |
| SYNC_COMMAND | nvarchar(30) | INSERT / UPDATE / DELETE |
| SYNC_DATE | datetime | When the change happened |
| KEY_COLUMNS | nvarchar(250) | Names of the key columns |
| KEY_DATA | nvarchar(250) | Composite key values |

### LSA_TRANS_LOG
Transaction lifecycle log (start/end/running dates per transaction).

**PK:** START_DATE + TRANSACTION_NAME

### LSA_DATABASE_INSTANCE
Legacy-style database instance registry (similar to EXCHANGE_DATABASE_INSTANCE).

### LSA_TABLE
Metadata registry of synchronized tables.

**PK:** DATASPACE_NAME + TABLE_NAME

| Column | Type | Notes |
|---|---|---|
| DATASPACE_NAME | nvarchar(30) | Database/application |
| TABLE_NAME | nvarchar(30) | Table name |
| DOCUMENTATION | nvarchar(max) | Description |
| SQL_COMMAND | nvarchar(max) | DDL |

### LSA_RELATIONSHIP
**Cross-database foreign key metadata.** Includes PARENT_DATASPACE_NAME so relationships can span databases.

**PK:** DATASPACE_NAME + RELATIONSHIP_NAME + TABLE_NAME

| Column | Type | Notes |
|---|---|---|
| DATASPACE_NAME | nvarchar(30) | Child table's database |
| TABLE_NAME | nvarchar(30) | Child table |
| RELATIONSHIP_NAME | nvarchar(30) | FK identifier |
| INDEX_NAME | nvarchar(30) | Supporting index |
| COLUMN_1..COLUMN_16 | nvarchar(30) | Key columns |
| **PARENT_DATASPACE_NAME** | nvarchar(30) | **Parent database (can be different from child's!)** |
| **PARENT_TABLE_NAME** | nvarchar(30) | **Parent table** |
| DOCUMENTATION | nvarchar(250) | Description |

### LSA_COLUMN / LSA_INDEX / LSA_DOMAIN / LSA_ENUM
Metadata registries for columns, indexes, logical domains, and enum value lists. Used by the framework for validation.

### LSA_AUDIT_DATA / LSA_AUDIT_DEFINITION
Audit trail definitions and captured audit data.

### LSA_NUMBERING
Automatic number generation (sequences).

### LSA_USER / LSA_LOGINS / LSA_LOGIN_CONTEXT / LSA_PASSWORD_LOG / LSA_ROLE / LSA_ROLE_AUTH / LSA_COMMAND_PERMISSION
User authentication and authorization.

### LSA_SETTINGS
Application-wide settings.

### LSA_MESSAGE_LOG
System message log.

### LSA_WORKFLOW
Workflow definitions.

### LSA_FAVORITES
User UI favorites.

### LSA_DATASPACE / LSA_DOMAIN / LSA_ENTITY
Metadata for logical concepts.

---

## 5. Site & Context Mapping

### LSA_SITE
**Important for tying SITE_ID to a database instance.** Maps business entities/sites to the Visual application instance that owns them.

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)**. Parent entity |
| **SITE_ID** | nvarchar(15) | **Logical key (composite)**. Site identifier |
| NAME | nvarchar(40) | Site name |
| **VMFG_INSTANCE_NAME** | nvarchar(30) | **Visual Manufacturing (VECA) instance** |
| VQ_INSTANCE_NAME | nvarchar(30) | Visual Quality instance |
| VTA_INSTANCE_NAME | nvarchar(30) | Visual Trade Admin instance |
| VSCP_INSTANCE_NAME | nvarchar(30) | Visual Supply Chain Planning instance |
| IQM_INSTANCE_NAME | nvarchar(30) | IQM instance |

**Use case:** Given a VFIN record with `ENTITY_ID` and `SITE_ID`, join to `LSA_SITE` to discover which VECA instance holds the manufacturing detail for that site.

### LSA_CONTEXT_INSTANCE
Domain/role-based instance binding (security/routing).

| Column | Type | Notes |
|---|---|---|
| DOMAIN_NAME | nvarchar(30) | Business domain |
| ROLE_NAME | nvarchar(20) | User role |
| INSTANCE_NAME | nvarchar(30) | Which instance provides this role |

---

## 6. Other LSA Tables

### NOTATIONS_NOTATION / NOTATIONS_NOTATION_CTL / NOTATIONS_NOTATION_LINK
Free-text notation attachments that can be linked to any entity.

### ATTACHMENTS_ATTACHMENT
Binary attachments (documents, images) linked to entities.

---

## Practical Queries

### "What flows from VECA to VFIN?"

```sql
SELECT
    S.ID                  AS SUBSCRIPTION_ID,
    S.DESCRIPTION,
    S.PUB_INSTANCE_NAME,
    S.PUB_DOCUMENT_ID,
    PD.ROOT_TABLE_NAME    AS PUB_TABLE,
    S.SUB_INSTANCE_NAME,
    S.SUB_DOCUMENT_ID,
    SD.ROOT_TABLE_NAME    AS SUB_TABLE,
    S.ACTIVE
FROM LSA.dbo.EXCHANGE_SUBSCRIPTION S
LEFT JOIN LSA.dbo.EXCHANGE_DOCUMENT PD ON S.PUB_DOCUMENT_ID = PD.ID
LEFT JOIN LSA.dbo.EXCHANGE_DOCUMENT SD ON S.SUB_DOCUMENT_ID = SD.ID
WHERE S.PUB_INSTANCE_NAME LIKE 'VECA%'
  AND S.SUB_INSTANCE_NAME LIKE 'VFIN%'
ORDER BY S.PUB_DOCUMENT_ID;
```

This is **the definitive answer** to "which VECA tables have VFIN counterparts created by sync."

### "What columns map between two tables?"

```sql
SELECT
    M.TRANSFORM_ID,
    M.PUB_TABLE_NAME,
    M.PUB_COLUMN_NAME,
    M.SUB_TABLE_NAME,
    M.SUB_COLUMN_NAME,
    M.EXPRESSION
FROM LSA.dbo.EXCHANGE_TRANSFORM_MAP M
WHERE M.PUB_TABLE_NAME = 'RECEIVABLE'          -- VECA table
  AND M.SUB_TABLE_NAME = 'RECEIVABLES_RECEIVABLE' -- VFIN table
ORDER BY M.PUB_COLUMN_NAME;
```

### "Was this specific row synced?"

```sql
SELECT TOP 20
    A.SUBSCRIPTION_ID,
    A.PUB_INSTANCE_NAME,
    A.PUB_DOCUMENT_ID,
    A.PUB_KEY_DATA,
    A.SUB_INSTANCE_NAME,
    A.STATUS,
    A.RECORD_CREATED,
    A.MESSAGE
FROM LSA.dbo.EXCHANGE_ACTIVITY A
WHERE A.PUB_INSTANCE_NAME LIKE 'VECA%'
  AND A.PUB_DOCUMENT_ID = 'RECEIVABLE'
  AND A.PUB_KEY_DATA LIKE '%INV-12345%'  -- invoice ID
ORDER BY A.RECORD_CREATED DESC;
```

### "Which VECA instance holds this VFIN site's data?"

```sql
SELECT
    V.ENTITY_ID,
    V.INVOICE_ID,
    V.SITE_ID,                  -- from VFIN.PAYABLES_PAYABLE
    L.VMFG_INSTANCE_NAME        -- the VECA instance
FROM VFIN.dbo.PAYABLES_PAYABLE V
LEFT JOIN LSA.dbo.LSA_SITE L
    ON V.ENTITY_ID = L.ENTITY_ID
    AND V.SITE_ID = L.SITE_ID
WHERE V.INVOICE_ID = 'AP-00001';
```

### "What cross-database FKs exist?"

```sql
SELECT
    DATASPACE_NAME        AS CHILD_DB,
    TABLE_NAME            AS CHILD_TABLE,
    PARENT_DATASPACE_NAME AS PARENT_DB,
    PARENT_TABLE_NAME     AS PARENT_TABLE,
    RELATIONSHIP_NAME,
    COLUMN_1, COLUMN_2, COLUMN_3
FROM LSA.dbo.LSA_RELATIONSHIP
WHERE DATASPACE_NAME <> PARENT_DATASPACE_NAME
ORDER BY CHILD_DB, CHILD_TABLE;
```
