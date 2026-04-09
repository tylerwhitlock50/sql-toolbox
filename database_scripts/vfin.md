# VFIN Database Reference (Infor Visual Financials)

Financial/accounting database. Covers General Ledger, Accounts Receivable, Accounts Payable, Cash Management, and shared configuration. Use this as a quick reference to avoid scanning DDL scripts for context.

**Key design patterns across all VFIN tables:**
- **Surrogate PK:** Every table uses `RECORD_IDENTITY nvarchar(12)` as its clustered primary key. Logical/business keys are noted below.
- **No declared FKs:** All relationships are enforced at the application layer via naming convention. FKs listed are inferred.
- **Audit columns on every table:** `RECORD_CREATED`, `RECORD_MODIFIED`, `RECORD_USER`, `RECORD_MODIFY_USER`, `RECORD_VERSION` (omitted from column listings).
- **Entity-scoped:** Most tables are scoped by `ENTITY_ID`, supporting multi-company operations in one database.
- **Multi-currency:** Amounts are in specific currencies; exchange rates stored in separate `_CURR` tables; user overrides in `_USRCURR` tables.

---

## 1. General Ledger

### LEDGER_ACCOUNT
Master chart of accounts. Each row is a GL account within an entity.

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)**. Business entity |
| **ACCOUNT_ID** | nvarchar(30) | **Logical key (composite)**. Full composite account (segments joined by separator) |
| DESCRIPTION | nvarchar(128) | Account description |
| ACCOUNT_CLASS | nvarchar(32) | Classification (Asset, Liability, Equity, Revenue, Expense) |
| ACCOUNT_CAT_ID | nvarchar(15) | FK to LEDGER_ACCOUNT_CATEGORY |
| CURRENCY_ID | nvarchar(15) | FK to SHARED_CURRENCY |
| NATURAL_ACCOUNT_ID | nvarchar(10) | First segment of account. FK to LEDGER_NATURAL_ACCOUNT |
| SEGMENT_VALUE_2..6 | nvarchar(10) | Additional segment values |
| TRANS_CAT_REQUIRED | int | Whether transaction category is required |
| TRANS_CAT_LIST_ID | nvarchar(15) | FK to LEDGER_TRANS_CATEGORY_LIST |
| TAX_GROUP_ID | nvarchar(15) | FK to SHARED_TAX_GROUP |
| ACTIVE_FLAG | int | Active/inactive |
| POSTING_LEVEL | int | Posting level control |
| SECURITY_LEVEL | smallint | Access security level |
| REVALUE_TYPE | nvarchar(32) | Currency revaluation type |

**Account structure:** Accounts are built from NATURAL_ACCOUNT_ID (segment 1) + up to 5 additional segments, joined by a separator character defined in LEDGER_ACCOUNT_CTL.

### LEDGER_ACCOUNT_BALANCE
Period balances broken out by source module. One row per account/currency/posting date/trans category.

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **ACCOUNT_ID** | nvarchar(30) | **Logical key (composite)** |
| **CURRENCY_ID** | nvarchar(15) | **Logical key (composite)** |
| **POSTING_DATE** | datetime | **Logical key (composite)**. Period posting date |
| TRANS_CAT_ID | nvarchar(15) | Transaction category |
| ACCOUNT_CAT_ID | nvarchar(15) | Account category |
| DEBIT_AMOUNT / CREDIT_AMOUNT | decimal(20,3) | Total period amounts |
| ADJ_DEBIT_AMOUNT / ADJ_CREDIT_AMOUNT | decimal(20,3) | Adjustment amounts |
| GEN_DEBIT_AMOUNT / GEN_CREDIT_AMOUNT | decimal(20,3) | General journal amounts |
| RECV_DEBIT_AMOUNT / RECV_CREDIT_AMOUNT | decimal(20,3) | Receivables amounts |
| PAYB_DEBIT_AMOUNT / PAYB_CREDIT_AMOUNT | decimal(20,3) | Payables amounts |
| CASH_DEBIT_AMOUNT / CASH_CREDIT_AMOUNT | decimal(20,3) | Cash management amounts |
| BADJ_DEBIT_AMOUNT / BADJ_CREDIT_AMOUNT | decimal(20,3) | Bank adjustment amounts |
| DIR_DEBIT_AMOUNT / DIR_CREDIT_AMOUNT | decimal(20,3) | Direct journal amounts |

### LEDGER_ACCOUNT_BAL_FWD
Balance forward (beginning-of-year) amounts. Same source-module breakdown as LEDGER_ACCOUNT_BALANCE but keyed by POSTING_YEAR instead of date.

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **ACCOUNT_ID** | nvarchar(30) | **Logical key (composite)** |
| **CURRENCY_ID** | nvarchar(15) | **Logical key (composite)** |
| **POSTING_YEAR** | smallint | **Logical key (composite)**. Fiscal year |
| *(same debit/credit columns as LEDGER_ACCOUNT_BALANCE)* | | Per-module bal fwd amounts |

### LEDGER_GEN_JOURNAL
Header for general journal entries.

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **GEN_JOURNAL_ID** | nvarchar(15) | **Logical key (composite)** |
| DOCUMENT_TYPE_ID | nvarchar(15) | FK to SHARED_DOCUMENT_TYPE |
| DISPOSITION_ID | nvarchar(15) | Workflow disposition |
| CURRENCY_ID | nvarchar(15) | Journal currency |
| DESCRIPTION | nvarchar(80) | Description |
| ENTRY_DATE | datetime | Entry date |
| CREDIT_AMOUNT / DEBIT_AMOUNT | decimal(20,3) | Journal totals |
| POSTED | int | Posted to GL flag |
| ADJUSTMENT | int | Adjustment flag |
| VOID | int | Void flag |
| REVERSING_ENTRY | int | Reversing entry flag |
| RCR_JOURNAL_ID | nvarchar(15) | Recurring journal source |
| SITE_ID | nvarchar(15) | Originating site |

**Journal pattern:** Journals follow a 3-tier structure: Header (GEN_JOURNAL) -> user-entered Lines (GEN_JOURN_LINE) -> system-generated Distributions (GEN_JOURN_DIST). Distributions are what actually post to GL balances.

### LEDGER_GEN_JOURN_LINE
User-entered line items for general journals.

| Column | Type | Notes |
|---|---|---|
| **GEN_JOURNAL_ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **GEN_JOURNAL_ID** | nvarchar(15) | **Logical key (composite)** |
| **LINE_NO** | int | **Logical key (composite)** |
| ENTITY_ID | nvarchar(15) | Target entity |
| ACCOUNT_ID | nvarchar(30) | GL account |
| CURRENCY_ID | nvarchar(15) | Line currency |
| CREDIT_AMOUNT / DEBIT_AMOUNT | decimal(20,3) | Converted amounts (base currency) |
| USER_CREDIT_AMOUNT / USER_DEBIT_AMOUNT | decimal(20,3) | User-entered amounts (line currency) |
| XCHG_RATE | decimal(15,8) | Exchange rate used |
| TRANS_CAT_ID | nvarchar(15) | Transaction category |
| REFERENCE | nvarchar(80) | Reference text |
| PROJECT_ID / WBS / PROJ_DEPT_ID / PROJ_COST_CAT_ID | nvarchar | Project tracking fields |

### LEDGER_GEN_JOURN_DIST
Posted GL distribution records for general journals.

| Column | Type | Notes |
|---|---|---|
| **GEN_JOURNAL_ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **GEN_JOURNAL_ID** | nvarchar(15) | **Logical key (composite)** |
| **DIST_NO** | smallint | **Logical key (composite)** |
| **ENTRY_NO** | smallint | **Logical key (composite)** |
| **CURRENCY_ID** | nvarchar(15) | **Logical key (composite)** |
| ENTITY_ID | nvarchar(15) | Target entity |
| ACCOUNT_ID | nvarchar(30) | GL account |
| CREDIT_AMOUNT / DEBIT_AMOUNT | decimal(20,3) | Posting amounts |
| DISTRIBUTION_TYPE | nvarchar(32) | Type (Original, Tax, Rounding, etc.) |
| POSTING_DATE | datetime | GL posting date |
| TRANS_CAT_ID | nvarchar(15) | Transaction category |
| TAX_ID | nvarchar(15) | Tax code (if tax-related) |
| REFERENCE | nvarchar(80) | Reference |

### LEDGER_DIRECT_JOURNAL
Header for direct journal entries (system-generated postings from sub-ledgers like VECA). Same structure as GEN_JOURNAL but for automated feeds.

**Logical key:** ENTITY_ID + DIRECT_JOURNAL_ID

Child tables: LEDGER_DIRECT_JOURN_LINE, LEDGER_DIRECT_JOURN_DIST (same patterns as GEN_JOURN_LINE/DIST).

### LEDGER_NATURAL_ACCOUNT
Natural account master -- the primary segment of the chart of accounts.

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **NATURAL_ACCOUNT_ID** | nvarchar(10) | **Logical key (composite)**. First segment code |
| DESCRIPTION | nvarchar(128) | Account description |
| ACCOUNT_CAT_ID | nvarchar(15) | Default account category |
| CURRENCY_ID | nvarchar(15) | Default currency |
| SEGMENT_ID_2..6 | nvarchar(10) | Default segment types for positions 2-6 |
| ACTIVE_FLAG | int | Active/inactive |

### LEDGER_SEGMENT / LEDGER_SEGMENT_VALUE
Segment type definitions and their valid values (e.g., Department, Division, Location).

- **LEDGER_SEGMENT** logical key: ENTITY_ID + SEGMENT_ID
- **LEDGER_SEGMENT_VALUE** logical key: ENTITY_ID + SEGMENT_ID + SEGMENT_VALUE

### LEDGER_ACCOUNT_CATEGORY
Hierarchical account categories for financial reporting grouping. Self-referencing via PARENT_ACCT_CAT_ID.

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(15) | **Logical key** |
| DESCRIPTION | nvarchar(80) | Description |
| PARENT_ACCT_CAT_ID | nvarchar(15) | Parent category (self-ref hierarchy) |
| ACCOUNT_CLASS | nvarchar(32) | Account class (Asset, Liability, etc.) |
| SEQ_NO | smallint | Display sequence |

### LEDGER_ACCOUNT_PERIOD
Fiscal period definitions within a calendar.

| Column | Type | Notes |
|---|---|---|
| **CALENDAR_ID** | nvarchar(15) | **Logical key (composite)**. FK to LEDGER_ACCOUNT_CALENDAR |
| **ACCT_YEAR** | int | **Logical key (composite)** |
| **ACCT_PERIOD** | int | **Logical key (composite)** |
| NAME | nvarchar(50) | Period name (e.g., "January") |
| BEGIN_DATE / END_DATE | datetime | Period boundaries |
| QTR_IN_YEAR | int | Quarter number |
| LOCKED | int | Whether period is locked for posting |

### LEDGER_ACCOUNT_BUDGET
Budget amounts by account and period.

**Logical key:** ENTITY_ID + BUDGET_ID + ACCOUNT_ID + CURRENCY_ID + POSTING_DATE

Parent: LEDGER_BUDGET (ENTITY_ID + BUDGET_ID, with DESCRIPTION and BUDGET_STATUS).

### LEDGER_TRANS_CATEGORY
Transaction category master for sub-classifying journal entries.

**Logical key:** ENTITY_ID + TRANS_CAT_ID

Grouped by: LEDGER_TRANS_CATEGORY_LIST -> LEDGER_TRANS_CAT_LIST_MBR.

### LEDGER_RCR_GEN_JOURNAL
Recurring journal templates for automatic periodic generation. Contains trigger schedule (TRIGGER_FREQ, TRIGGER_INTERVAL, TRIGGER_MAX, TRIGGER_EFFECTIVE_DATE, TRIGGER_DISCONTINUE_DATE).

**Logical key:** ENTITY_ID + RCR_GEN_JOURNAL_ID

### LEDGER_ACCOUNT_CTL
Singleton GL configuration. Contains SEPARATOR_CHAR (the character separating account segments, e.g., "-").

### Key Ledger Views

| View | Purpose |
|---|---|
| **LEDGER_ALL_DISTRIBUTIONS** | Unified view of all posted GL distributions across all journal types (GEN, PAYB, RECV, PAYMENT, BANKADJ, DIRECT). Key columns: JOURNAL_TYPE, JOURNAL_ENTITY_ID, JOURNAL_ID, ACCOUNT_ID, DEBIT_AMOUNT, CREDIT_AMOUNT, POSTING_DATE |
| **LEDGER_ALL_ACCOUNTS** | Union of every account reference across all modules. Used for validation/cross-reference |
| **LEDGER_RECV_DISTRIBUTIONS** | Receivables-focused distributions with customer context |
| **LEDGER_PAYB_DISTRIBUTIONS** | Payables-focused distributions with supplier context |

---

## 2. Receivables (AR)

### RECEIVABLES_RECEIVABLE
Invoice/receivable header. One row per AR invoice.

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **INVOICE_ID** | nvarchar(15) | **Logical key (composite)** |
| CUSTOMER_ID | nvarchar(15) | FK to RECEIVABLES_CUSTOMER |
| BILL_TO_CUST_ID | nvarchar(15) | Bill-to customer (if different) |
| CURRENCY_ID | nvarchar(15) | Invoice currency |
| DOCUMENT_TYPE_ID | nvarchar(15) | Document type |
| DISPOSITION_ID | nvarchar(15) | Disposition/workflow |
| INVOICE_DATE | datetime | Invoice date |
| INVOICE_STATUS | nvarchar(32) | Status (Open, Paid, etc.) |
| INVOICE_TYPE | nvarchar(32) | Type (Invoice, Credit Memo, Debit Memo) |
| TERMS_RULE_ID | nvarchar(15) | Payment terms |
| TAX_GROUP_ID | nvarchar(15) | Tax group |
| TOTAL_AMOUNT | decimal(20,3) | Total invoice amount |
| TOTAL_NET_AMOUNT | decimal(20,3) | Net amount |
| TOTAL_TAX_AMOUNT | decimal(20,3) | Total tax |
| TOTAL_FRGHT_AMOUNT | decimal(20,3) | Total freight |
| TOTAL_PAID_AMOUNT | decimal(20,3) | Total paid |
| TOTAL_FIN_CHARGE | decimal(20,3) | Total finance charges |
| WRITEOFF_APPLIED | decimal(20,3) | Write-off amount |
| DISCOUNT_GIVEN | decimal(20,3) | Discount applied |
| RECV_ACCOUNT_ID | nvarchar(30) | Receivables GL account |
| POSTED | int | Posted to GL flag |
| LAST_PAID_DATE | datetime | Last payment date |
| PAYMENT_METHOD_ID | nvarchar(15) | Payment method |
| BANK_ACCOUNT_ID | nvarchar(15) | Company bank account |
| SYS_CURR_SALES_AMT / SYS_CURR_TOTAL_AMT | decimal(20,3) | System currency amounts |
| INV_CURR_SALES_AMT | decimal(20,3) | Sales in invoice currency |
| SHIPPER_GENERATED | int | Generated from shipper flag |

### RECEIVABLES_RECEIVABLE_LINE
Invoice line items.

| Column | Type | Notes |
|---|---|---|
| **INVOICE_ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **INVOICE_ID** | nvarchar(15) | **Logical key (composite)** |
| **LINE_NO** | smallint | **Logical key (composite)** |
| QTY | decimal(20,8) | Quantity |
| AMOUNT | decimal(20,3) | Line amount |
| UNIT_PRICE | decimal(22,8) | Unit price |
| CURRENCY_ID | nvarchar(15) | Line currency |
| XCHG_RATE | decimal(15,8) | Exchange rate |
| ENTITY_ID | nvarchar(15) | Revenue entity |
| ACCOUNT_ID | nvarchar(30) | Revenue GL account |
| SALESREP_ID | nvarchar(15) | Sales rep |
| TERRITORY_ID | nvarchar(15) | Sales territory |
| COMMISSION_PCT | decimal(6,3) | Commission % |
| COMMISSION_AMOUNT | decimal(20,3) | Commission amount |
| CUST_ORDER_ID | nvarchar(15) | Source customer order |
| CUST_ORDER_LINE_NO | smallint | Source order line |
| SHIPPER_ID | nvarchar(15) | Source shipper |
| TAX_GROUP_ID | nvarchar(15) | Tax group |
| TERMS_RULE_ID | nvarchar(15) | Terms override |
| CUSTOMER_PO_REF | nvarchar(40) | Customer PO reference |
| FREIGHT_LINE | int | Is freight line flag |

### RECEIVABLES_RECEIVABLE_DIST
GL distribution entries for receivables.

| Column | Type | Notes |
|---|---|---|
| **INVOICE_ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **INVOICE_ID** | nvarchar(15) | **Logical key (composite)** |
| **DIST_NO** | smallint | **Logical key (composite)** |
| **ENTRY_NO** | smallint | **Logical key (composite)** |
| **CURRENCY_ID** | nvarchar(15) | **Logical key (composite)** |
| ENTITY_ID | nvarchar(15) | GL entity |
| ACCOUNT_ID | nvarchar(30) | GL account |
| DEBIT_AMOUNT / CREDIT_AMOUNT | decimal(20,3) | Amounts |
| DISTRIBUTION_TYPE | nvarchar(32) | Type (Revenue, Tax, Freight, Discount, etc.) |
| POSTING_DATE | datetime | GL posting date |

### RECEIVABLES_RECEIVABLE_SCHED
Payment schedule (installments) for a receivable.

**Logical key:** INVOICE_ENTITY_ID + INVOICE_ID + LINE_NO

Key columns: DUE_DATE, AMOUNT, TERMS_RULE_ID, PAYMENT_METHOD_ID.

### RECEIVABLES_RECEIVABLE_AGING
Aging detail per receivable.

**Logical key:** INVOICE_ENTITY_ID + INVOICE_ID + LINE_NO

Key columns: NET_DUE_DATE, DISCOUNT_DATE, AMOUNT, DISC_PERCENT, DISCOUNT_AMOUNT, FIN_CHG_AMOUNT.

### RECEIVABLES_RECEIVABLE_TAX
Tax detail lines per receivable.

**Logical key:** INVOICE_ENTITY_ID + INVOICE_ID + LINE_NO

Key columns: TAX_ID, TAX_AMOUNT, RCV_AMOUNT, BASIS_AMOUNT, ACC_ACCOUNT_ID, RCV_ACCOUNT_ID, EXP_ACCOUNT_ID.

### Other Receivable Child Tables

| Table | Logical Key | Purpose |
|---|---|---|
| RECEIVABLES_RECEIVABLE_CURR | ENTITY + INVOICE + FROM/TO_CURRENCY + DATE | Exchange rate snapshots |
| RECEIVABLES_RECEIVABLE_USRCURR | ENTITY + INVOICE + CURRENCY | User rate overrides |
| RECEIVABLES_RECEIVABLE_COMM | ENTITY + INVOICE + SALESREP | Commission tracking per sales rep |
| RECEIVABLES_RECEIVABLE_FIN_CHG | ENTITY + INVOICE + DATE + LINE | Finance charge detail |
| RECEIVABLES_RECEIVABLE_SHARE | ENTITY + INVOICE + ORDER_REP + SHARE_REP | Commission sharing between reps |
| RECEIVABLES_RECEIVABLE_WRITEOF | ENTITY + INVOICE + LINE | Write-off detail |

### RECEIVABLES_RECEIVABLE_CTL
Singleton module configuration. Defines aging bucket boundaries (AGING_BUCKET1..4) and MULTI_ENTITY_WARNING flag.

### RECEIVABLES_CUSTOMER
Customer master record.

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(15) | **Logical key**. Customer identifier |
| NAME | nvarchar(50) | Customer name |
| ADDR_1 / ADDR_2 / ADDR_3 | nvarchar(50) | Address lines |
| CITY / STATE / POSTALCODE / COUNTRY | nvarchar | Address fields |
| CUSTOMER_PHONE / CUSTOMER_FAX / EMAIL / MOBILE_PHONE | nvarchar | Contact info |
| WEB_URL | nvarchar(128) | Website |
| TERRITORY_ID | nvarchar(15) | Sales territory |
| PARENT_CUSTOMER_ID | nvarchar(15) | Parent customer (hierarchy, self-ref) |
| LINK_SUPPLIER_ID | nvarchar(15) | Linked supplier ID (if also a vendor) |
| INDUSTRY_ID | nvarchar(15) | Industry classification |
| TAX_REGISTRATION | nvarchar(25) | Tax registration number |
| LAST_ORDER_DATE | datetime | Date of last order |
| OPEN_DATE | datetime | Account open date |

### RECEIVABLES_CUSTOMER_ENTITY
Customer-per-entity configuration. One row per customer-entity combination. Contains billing address, banking, credit management, finance charge settings, invoice generation rules, and email configuration.

| Column | Type | Notes |
|---|---|---|
| **CUSTOMER_ID** | nvarchar(15) | **Logical key (composite)** |
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| ACTIVE_FLAG | int | Active/inactive |
| RECV_ACCOUNT_ID / REV_ACCOUNT_ID | nvarchar(30) | Default GL accounts |
| CURRENCY_ID | nvarchar(15) | Default currency |
| TERMS_RULE_ID | nvarchar(15) | Default payment terms |
| TAX_GROUP_ID | nvarchar(15) | Default tax group |
| SALESREP_ID | nvarchar(15) | Default sales rep |
| PAYMENT_METHOD_ID | nvarchar(15) | Default payment method |
| CREDIT_LIMIT_AMT | decimal(20,3) | Credit limit |
| CREDIT_STATUS | nvarchar(32) | Credit status (Good, Hold, etc.) |
| OPEN_ORDER_AMOUNT / OPEN_ORDER_COUNT | mixed | Open order totals |
| OPEN_RECV_AMOUNT / OPEN_RECV_COUNT | mixed | Open receivable totals |
| FIN_CHG_EXEMPT | int | Finance charge exempt flag |
| FIN_CHG_PERCENT | decimal(6,3) | Finance charge rate |
| DUNNING_LETTERS | int | Send dunning letters flag |
| BILL_TO_NAME / BILL_TO_ADDR_1..3 / BILL_TO_CITY / BILL_TO_STATE / BILL_TO_POSTCODE | nvarchar | Bill-to address |
| CUST_BANK_ID / CUST_BANK_ACCT_NO / CUST_BANK_NAME / CUST_BANK_SWIFT / CUST_BANK_IBAN | nvarchar | Default bank info |

### Other Customer Tables

| Table | Logical Key | Purpose |
|---|---|---|
| RECEIVABLES_CUSTOMER_CONTACT | CUSTOMER_ID + CONTACT_NO | Contact records per customer |
| RECEIVABLES_CUSTOMER_BANK | CUSTOMER_ID + ENTITY_ID + CUST_BANK_ID | Customer bank accounts |
| RECEIVABLES_CUSTOMER_GROUP | ID | Customer group definitions |
| RECEIVABLES_CUSTOMER_GROUP_MBR | GROUP_ID + CUSTOMER_ID | Group membership (many-to-many) |
| RECEIVABLES_CUSTOMER_TURNOVER | CUSTOMER_ID + ENTITY_ID + CURRENCY_ID + YEAR_NO + IS_SYSTEM_CURR | Annual turnover totals |

### RECEIVABLES_CUSTOMER_ORDER
Customer order header in VFIN (financial view of orders).

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **CUST_ORDER_ID** | nvarchar(15) | **Logical key (composite)** |
| CUSTOMER_ID | nvarchar(15) | Customer |
| CURRENCY_ID | nvarchar(15) | Order currency |
| ORDER_DATE | datetime | Order date |
| ORDER_STATUS | nvarchar(32) | Status |
| TOTAL_ORDERED / TOTAL_TAX / TOTAL_FREIGHT | decimal(20,3) | Order totals |
| CUSTOMER_PO_REF | nvarchar(40) | Customer PO reference |
| TERMS_RULE_ID | nvarchar(15) | Payment terms |
| TAX_GROUP_ID | nvarchar(15) | Tax group |
| SITE_ID | nvarchar(15) | Manufacturing site |

Child tables: RECEIVABLES_CUST_ORDER_LINE, RECEIVABLES_CUST_ORDER_BILLING (progress billing), RECEIVABLES_CUST_ORDER_COMM (commissions), RECEIVABLES_CUST_ORDER_PRICE (pricing), RECEIVABLES_CUST_ORDER_SHARE (commission sharing).

### RECEIVABLES_SHIPPER
Shipment header. Tracks shipments that generate invoices.

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **SHIPPER_ID** | nvarchar(15) | **Logical key (composite)** |
| CUSTOMER_ID | nvarchar(15) | Customer |
| CURRENCY_ID | nvarchar(15) | Shipment currency |
| SHIPPED_DATE | datetime | Ship date |
| INVOICE_ENTITY_ID / INVOICE_ID | nvarchar(15) | Generated invoice reference |
| SHIP_TO_NAME / SHIP_TO_ADDR_1..3 / SHIP_TO_CITY / SHIP_TO_STATE / SHIP_TO_POSTCODE | nvarchar | Ship-to address |
| TERMS_RULE_ID | nvarchar(15) | Payment terms |
| VOID | int | Void flag |

Child: RECEIVABLES_SHIPPER_LINE (line items with qty, price, amount, freight, commission, GL account).

### RECEIVABLES_RCR_RECEIVABLE
Recurring receivable template. Defines invoices generated on a schedule.

**Logical key:** ENTITY_ID + RCR_RECEIVABLE_ID

Key columns: CUSTOMER_ID, CURRENCY_ID, TOTAL_AMOUNT, TRIGGER_FREQ, TRIGGER_INTERVAL, TRIGGER_MAX, TRIGGER_EFFECTIVE_DATE, TRIGGER_DISCONTINUE_DATE.

Child: RECEIVABLES_RCR_RECV_LINE (template line items).

---

## 3. Payables (AP)

### PAYABLES_PAYABLE
Core invoice/payable header. One row per supplier invoice.

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **INVOICE_ID** | nvarchar(15) | **Logical key (composite)** |
| SUPPLIER_ID | nvarchar(15) | FK to PAYABLES_SUPPLIER |
| SUPP_INVOICE_ID | nvarchar(15) | Supplier's own invoice number |
| CURRENCY_ID | nvarchar(15) | Transaction currency |
| DOCUMENT_TYPE_ID | nvarchar(15) | Document type |
| DISPOSITION_ID | nvarchar(15) | Disposition/workflow |
| INVOICE_DATE | datetime | Supplier invoice date |
| INVOICE_STATUS | nvarchar(32) | Status (Open, Paid, Voided, etc.) |
| INVOICE_TYPE | nvarchar(32) | Type (Invoice, Credit Memo, Debit Memo) |
| TERMS_RULE_ID | nvarchar(15) | Payment terms |
| TAX_GROUP_ID | nvarchar(15) | Tax group |
| TOTAL_AMOUNT | decimal(20,3) | Total invoice amount |
| TOTAL_TAX_AMOUNT | decimal(20,3) | Total tax |
| TOTAL_FRGHT_AMOUNT | decimal(20,3) | Total freight |
| TOTAL_PAID_AMOUNT | decimal(20,3) | Total paid |
| TOTAL_WITHHELD_AMOUNT | decimal(20,3) | Total withholding withheld |
| DISCOUNT_TAKEN | decimal(20,3) | Discount taken on payment |
| PAYB_ACCOUNT_ID | nvarchar(30) | AP control GL account |
| POSTED | int | Posted to GL flag |
| PAYMENT_DATE | datetime | Scheduled/actual payment date |
| PAYMENT_METHOD_ID | nvarchar(15) | Payment method |
| LAST_PAID_DATE | datetime | Last payment date |
| RCR_PAYABLE_ID | nvarchar(15) | Recurring payable template source |
| REMIT_TO_SUPP_ID | nvarchar(15) | Alternate remit-to supplier |
| SUPP_BANK_ID / SUPP_BANK_ACCT_NO | nvarchar | Supplier bank info |
| WH_TAX_GROUP_ID | nvarchar(15) | Withholding tax group |
| USER_HOLD | int | User hold flag |
| USER_DISPUTED | int | Disputed flag |
| SITE_ID | nvarchar(15) | Multi-site identifier |

### PAYABLES_PAYABLE_LINE
Invoice line items. Each line is a charge (expense, freight, PO match, etc.).

| Column | Type | Notes |
|---|---|---|
| **INVOICE_ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **INVOICE_ID** | nvarchar(15) | **Logical key (composite)** |
| **LINE_NO** | smallint | **Logical key (composite)** |
| QTY | decimal(20,8) | Invoiced quantity |
| AMOUNT | decimal(20,3) | Line amount |
| UNIT_PRICE | decimal(22,8) | Unit price |
| CURRENCY_ID | nvarchar(15) | Line currency |
| XCHG_RATE | decimal(15,8) | Exchange rate |
| ENTITY_ID | nvarchar(15) | Expense entity |
| ACCOUNT_ID | nvarchar(30) | Expense GL account |
| PURC_ORDER_ID | nvarchar(15) | Linked purchase order |
| PURC_ORDER_LINE_NO | smallint | PO line number |
| RECEIVER_ID | nvarchar(15) | Linked receiver |
| RECEIVER_LINE_NO | smallint | Receiver line number |
| MATCHED | int | Matched to PO/receiver flag |
| TAX_GROUP_ID | nvarchar(15) | Tax group |
| TERMS_RULE_ID | nvarchar(15) | Terms override |
| CODE_1099_ID / CODE_1099_DIST | nvarchar(15) | 1099 reporting codes |
| PROJECT_ID / WBS / PROJ_COST_CAT_ID / PROJ_DEPT_ID | nvarchar | Project tracking |
| FREIGHT_LINE | int | Freight line flag |

### PAYABLES_PAYABLE_DIST
GL distribution lines for payables (same pattern as RECEIVABLES_RECEIVABLE_DIST).

**Logical key:** INVOICE_ENTITY_ID + INVOICE_ID + DIST_NO + ENTRY_NO + CURRENCY_ID

### Other Payable Child Tables

| Table | Logical Key | Purpose |
|---|---|---|
| PAYABLES_PAYABLE_AGING | ENTITY + INVOICE + LINE | Aging schedule (due dates, discounts) |
| PAYABLES_PAYABLE_SCHED | ENTITY + INVOICE + LINE | Payment schedule (installments) |
| PAYABLES_PAYABLE_TAX | ENTITY + INVOICE + LINE | Tax detail lines |
| PAYABLES_PAYABLE_CURR | ENTITY + INVOICE + FROM/TO_CURRENCY + DATE | Exchange rate snapshots |
| PAYABLES_PAYABLE_USRCURR | ENTITY + INVOICE + CURRENCY | User rate overrides |
| PAYABLES_PAYABLE_CTL | (singleton) | Module config (aging buckets) |

### PAYABLES_SUPPLIER
Supplier master.

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(15) | **Logical key**. Supplier identifier |
| NAME | nvarchar(50) | Supplier name |
| ADDR_1 / ADDR_2 / ADDR_3 | nvarchar(50) | Address lines |
| CITY / STATE / POSTALCODE / COUNTRY | nvarchar | Address fields |
| SUPPLIER_PHONE / SUPPLIER_FAX / EMAIL / MOBILE_PHONE | nvarchar | Contact info |
| WEB_URL | nvarchar(128) | Website |
| PARENT_SUPPLIER_ID | nvarchar(15) | Parent supplier (hierarchy, self-ref) |
| LINK_CUSTOMER_ID | nvarchar(15) | Linked AR customer |
| BUYER | nvarchar(15) | Default buyer |
| PAYMENT_PRIORITY | int | Payment priority ranking |
| LAST_ORDER_DATE | datetime | Last PO date |
| OPEN_DATE | datetime | Account open date |

### PAYABLES_SUPPLIER_ENTITY
Supplier-per-entity configuration. One row per supplier-entity combination. Contains AP accounts, terms, matching rules, bank info, remittance address, status, 1099 settings.

| Column | Type | Notes |
|---|---|---|
| **SUPPLIER_ID** | nvarchar(15) | **Logical key (composite)** |
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| ACTIVE_FLAG | int | Active/inactive |
| SUPPLIER_STATUS | nvarchar(32) | Status (Active, Inactive, Hold) |
| PAYB_ACCOUNT_ID | nvarchar(30) | AP control GL account |
| EXP_ACCOUNT_ID | nvarchar(30) | Default expense GL account |
| PURC_ACCR_ACCT_ID | nvarchar(30) | Purchase accrual GL account |
| PPV_ACCOUNT_ID | nvarchar(30) | Purchase price variance GL account |
| CURRENCY_ID | nvarchar(15) | Default currency |
| TERMS_RULE_ID | nvarchar(15) | Default payment terms |
| TAX_GROUP_ID | nvarchar(15) | Default tax group |
| PAYMENT_METHOD_ID | nvarchar(15) | Default payment method |
| CREDIT_LIMIT_AMT | decimal(20,3) | Credit limit |
| MATCH_TYPE | nvarchar(32) | Match type (2-way, 3-way) |
| MATCH_HIGH_PCT / MATCH_LOW_PCT | decimal(6,3) | Match tolerance % |
| CODE_1099_ID / CODE_1099_DIST | nvarchar(15) | Default 1099 codes |
| TAX_ID_NUMBER | nvarchar(25) | Tax ID / EIN |
| OPEN_ORDER_AMOUNT / OPEN_PAYB_AMOUNT | decimal(20,3) | Open totals |
| REMIT_NAME / REMIT_ADDR_1..3 / REMIT_CITY / REMIT_STATE / REMIT_POSTALCODE | nvarchar | Remittance address |
| SUPP_BANK_ID / SUPP_BANK_ACCT_NO / SUPP_BANK_NAME / SUPP_BANK_SWIFT / SUPP_BANK_IBAN | nvarchar | Default bank info |
| AUTO_INVOICE_FROM_RECEIVER | int | Auto-create invoice from receiver flag |

### Other Supplier Tables

| Table | Logical Key | Purpose |
|---|---|---|
| PAYABLES_SUPPLIER_CONTACT | SUPPLIER_ID + CONTACT_NO | Contact records |
| PAYABLES_SUPPLIER_BANK | SUPPLIER_ID + ENTITY_ID + SUPP_BANK_ID | Bank accounts |
| PAYABLES_SUPPLIER_GROUP | ID | Supplier group definitions |
| PAYABLES_SUPPLIER_GROUP_MBR | GROUP_ID + SUPPLIER_ID | Group membership |
| PAYABLES_SUPPLIER_TURNOVER | SUPPLIER_ID + ENTITY_ID + CURRENCY_ID + YEAR_NO + IS_SYSTEM_CURR | Annual spend totals |
| PAYABLES_SUP_ALT_REM_ADDR | SUPPLIER_ID + REMIT_ALT_ADDR_NO | Alternate remittance addresses |

### PAYABLES_PURCHASE_ORDER
Purchase order header (financial view).

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **PURC_ORDER_ID** | nvarchar(15) | **Logical key (composite)** |
| SUPPLIER_ID | nvarchar(15) | Supplier |
| CURRENCY_ID | nvarchar(15) | PO currency |
| ORDER_DATE | datetime | PO date |
| ORDER_STATUS | nvarchar(32) | Status |
| TOTAL_ORDERED / TOTAL_TAX / TOTAL_FREIGHT | decimal(20,3) | PO totals |
| TERMS_RULE_ID | nvarchar(15) | Payment terms |
| SITE_ID | nvarchar(15) | Site |

Child: PAYABLES_PURC_ORDER_LINE (line items with product, qty, amounts, project refs).

### PAYABLES_RECEIVER
Goods receipt header.

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **RECEIVER_ID** | nvarchar(15) | **Logical key (composite)** |
| SUPPLIER_ID | nvarchar(15) | Supplier |
| PURC_ORDER_ID | nvarchar(15) | Related PO |
| RECEIVED_DATE | datetime | Receipt date |
| CLOSED | int | Closed flag |
| SITE_ID | nvarchar(15) | Site |

Child: PAYABLES_RECEIVER_LINE (line items with qty, prices, matched amounts, GL accounts).

### PAYABLES_RCR_PAYABLE
Recurring payable template. Same trigger pattern as RECEIVABLES_RCR_RECEIVABLE.

**Logical key:** ENTITY_ID + RCR_PAYABLE_ID

Child: PAYABLES_RCR_PAYB_LINE (template line items).

### PAYABLES_CODES_1099 / PAYABLES_DISTRIBUTIONS_1099
1099 reporting code lookup tables. CODES_1099 defines form/threshold, DISTRIBUTIONS_1099 defines box-level distribution categories.

---

## 4. Cash Management

### CASHMGMT_BANK_ACCOUNT
Bank accounts used for payments, deposits, and reconciliation.

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **BANK_ACCOUNT_ID** | nvarchar(15) | **Logical key (composite)** |
| BANK_ID | nvarchar(30) | Bank identifier |
| ACCOUNT_NO | nvarchar(30) | External bank account number |
| ACCOUNT_ID | nvarchar(30) | GL account for this bank account |
| ADJ_ACCOUNT_ID | nvarchar(30) | GL account for adjustments |
| ACCOUNT_TYPE | nvarchar(32) | Account type |
| NAME | nvarchar(50) | Bank name |
| ADDR_1..3 / CITY / STATE / POSTALCODE / COUNTRY | nvarchar | Bank address |
| ROUTING_NUMBER | nvarchar(20) | ACH routing number |
| IBAN | nvarchar(30) | IBAN |
| SWIFT | nvarchar(30) | SWIFT/BIC code |
| BALANCE_RESERVE | decimal(20,3) | Minimum reserve balance |
| ACTIVE_FLAG | int | Active/inactive |
| ALLOW_MULTI_CURR | int | Multi-currency flag |
| PAYMENT_METHOD_ID | nvarchar(15) | Default payment method |

### CASHMGMT_PAYMENT
Individual payment header (checks, EFTs, receipts). Handles both outbound (to suppliers) and inbound (from customers).

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **PAYMENT_ID** | nvarchar(15) | **Logical key (composite)** |
| BANK_ACCOUNT_ID | nvarchar(15) | Bank account used |
| CUSTOMER_ID | nvarchar(15) | Customer (for receipts) |
| SUPPLIER_ID | nvarchar(15) | Supplier (for disbursements) |
| CHECK_NO | nvarchar(15) | Check number |
| CURRENCY_ID | nvarchar(15) | Payment currency |
| AMOUNT | decimal(20,3) | Total payment amount |
| AMOUNT_APPLIED | decimal(20,3) | Amount applied to invoices |
| TAX_AMOUNT | decimal(20,3) | Tax amount |
| WITHHOLDING_AMOUNT | decimal(20,3) | Withholding tax |
| PAYMENT_STATUS | nvarchar(32) | Status |
| PAYMENT_TYPE | nvarchar(32) | Type (receipt, disbursement) |
| PAYMENT_METHOD_ID | nvarchar(15) | Payment method |
| PAYMENT_DATE | datetime | Payment date |
| POSTED | int | Posted to GL flag |
| CLEARED_DATE | datetime | Date cleared at bank |
| STATEMENT_DATE | datetime | Bank statement date |
| DEPOSIT_ID | nvarchar(15) | Related deposit |
| PAY_RUN_ID | nvarchar(15) | Originating payment run |
| VOID_DATE | datetime | Date voided |
| REMIT_TO_NAME / REMIT_TO_ADDR_1..3 / REMIT_TO_CITY / REMIT_TO_STATE / REMIT_TO_POSTALCODE | nvarchar | Remit-to address |

### CASHMGMT_PAYMENT_LINE
Line-level detail showing which invoices a payment is applied to.

| Column | Type | Notes |
|---|---|---|
| **PAYMENT_ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **PAYMENT_ID** | nvarchar(15) | **Logical key (composite)** |
| **LINE_NO** | smallint | **Logical key (composite)** |
| AMOUNT | decimal(20,3) | Amount applied |
| DISCOUNT_APPLIED | decimal(20,3) | Discount applied |
| FIN_CHG_APPLIED | decimal(20,3) | Finance charge applied |
| DEPOSIT_APPLIED | decimal(20,3) | Deposit applied |
| ENTITY_ID | nvarchar(15) | Invoice entity |
| RECV_INVOICE_ID | nvarchar(15) | Receivable invoice being paid |
| PAYB_INVOICE_ID | nvarchar(15) | Payable invoice being paid |
| CUSTOMER_ORDER_ID / PURCHASE_ORDER_ID | nvarchar(15) | Related orders |
| ACCOUNT_ID | nvarchar(30) | GL account |
| CODE_1099_ID / DIST_1099_ID | nvarchar(15) | 1099 codes |

### CASHMGMT_PAYMENT_DIST
GL distributions for payments.

**Logical key:** PAYMENT_ENTITY_ID + PAYMENT_ID + DIST_NO + ENTRY_NO + CURRENCY_ID

Key columns: ENTITY_ID, ACCOUNT_ID, DEBIT_AMOUNT, CREDIT_AMOUNT, DISTRIBUTION_TYPE, POSTING_DATE, RECV_INVOICE_ID, PAYB_INVOICE_ID.

### Other Payment Tables

| Table | Logical Key | Purpose |
|---|---|---|
| CASHMGMT_PAYMENT_CURR | ENTITY + PAYMENT + FROM/TO_CURRENCY | System exchange rates |
| CASHMGMT_PAYMENT_USRCURR | ENTITY + PAYMENT + CURRENCY | User rate overrides |
| CASHMGMT_PAYMENT_TAX | ENTITY + PAYMENT + LINE | Tax detail |

### CASHMGMT_BANK_DEPOSIT
Bank deposit header grouping one or more payment receipts.

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **DEPOSIT_ID** | nvarchar(15) | **Logical key (composite)** |
| BANK_ACCOUNT_ID | nvarchar(15) | Bank account deposited to |
| AMOUNT | decimal(20,3) | Total deposit amount |
| DEPOSIT_DATE | datetime | Deposit date |
| STATEMENT_DATE | datetime | Statement date |

Child: CASHMGMT_BANK_DEP_LINE (individual receipts: amount, currency, payment ID, customer/supplier, check number).

### CASHMGMT_BANK_PAY_RUN
Payment run header (batch of payments processed together).

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **PAY_RUN_ID** | nvarchar(15) | **Logical key (composite)** |
| BANK_ACCOUNT_ID | nvarchar(15) | Bank account |
| PAYMENT_METHOD_ID | nvarchar(15) | Payment method |
| RUN_DATE | datetime | Run date |
| PAY_THRU_DATE | datetime | Pay invoices due through this date |
| PAY_RUN_STATUS | nvarchar(32) | Status |
| FUNDS_AVAILABLE / FUNDS_REQUIRED | decimal(20,3) | Funding info |

Children:
- **CASHMGMT_BANK_PAY_RUN_LINE** - payee lines (supplier/customer, amount, remit-to address)
- **CASHMGMT_BANK_PAY_RUN_LINE_DET** - invoice-level detail per payee (which invoices, discounts, withholding)
- **CASHMGMT_BANK_PAY_RUN_TAX** - tax detail per line

### CASHMGMT_BANK_ADJUSTMENT
Bank adjustment header (corrections not tied to normal payments/deposits).

**Logical key:** ENTITY_ID + ADJUSTMENT_ID

Key columns: BANK_ACCOUNT_ID, ADJUSTMENT_STATUS, DEBIT_AMOUNT, CREDIT_AMOUNT, TRANSACTION_DATE, CLEARED_DATE, POSTED, VOID_DATE.

Children: BANK_ADJ_LINE (detail lines), BANK_ADJ_DIST (GL distributions), BANK_ADJ_CURR (system rates), BANK_ADJ_USRCURR (user rates).

### CASHMGMT_BANK_STATEMENT
Bank statement for reconciliation.

| Column | Type | Notes |
|---|---|---|
| **ENTITY_ID** | nvarchar(15) | **Logical key (composite)** |
| **BANK_ACCOUNT_ID** | nvarchar(15) | **Logical key (composite)** |
| **STATEMENT_DATE** | datetime | **Logical key (composite)** |
| STARTING_BALANCE / ENDING_BALANCE | decimal(20,3) | Statement balances |
| GL_ACCOUNT_BALANCE | decimal(20,3) | GL book balance |
| TOTAL_OPEN_DEBITS / TOTAL_OPEN_CREDITS | decimal(20,3) | Outstanding items |
| TOTAL_BANK_ADJUSTMENTS | decimal(20,3) | Bank-side adjustments |
| RECONCILIATION_VARIANCE | decimal(20,3) | Unreconciled variance |

### CASHMGMT_CASH_PLAN
Cash flow planning/forecasting. Configures how AR, AP, CO, PO data feeds into projections.

**Logical key:** ENTITY_ID + CASH_PLAN_ID

Children:
- **CASHMGMT_CASH_PLAN_LINE** - cash flow categories (LINE_TYPE, CLASS, CATEGORY)
- **CASHMGMT_CASH_PLAN_ACCOUNT** - GL accounts per line
- **CASHMGMT_CASH_PLAN_AMOUNT** - period-level debit/credit amounts (YEAR, PERIOD)

### CASHMGMT_WRITEOFF_CATEGORY / CASHMGMT_WRITEOFF_ENTITY
Write-off category definitions and their entity-level GL account mappings.

---

## 5. Shared / Reference Tables

### SHARED_ENTITY
Core entity (company/business unit) configuration. Each row represents a financial entity that owns ledgers, payables, receivables, etc.

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(15) | **Logical key** |
| NAME | nvarchar(50) | Entity name |
| CURRENCY_ID | nvarchar(15) | Base currency |
| CALENDAR_ID | nvarchar(15) | Fiscal calendar |
| COSTING_METHOD | nvarchar(32) | Costing method |
| ALLOW_MULTI_CURR | int | Multi-currency flag |
| FIN_CHG_PERCENT | decimal(6,3) | Default finance charge rate |
| FIN_CHG_GRACE_DAYS | smallint | Grace days |
| SUPPORT_1099 | int | 1099 reporting enabled |
| INVOICE_AGE_BASIS | nvarchar(32) | How aging is calculated |

Related: SHARED_ENTITY_ADDRESS (addresses), SHARED_ENTITY_CURRENCY (currency-level GL accounts for gains/losses/rounding), SHARED_ENTITY_ACCOUNT (default GL accounts by context).

### SHARED_CURRENCY
Currency master.

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(15) | **Logical key** |
| NAME | nvarchar(40) | Full currency name |
| ISO_CODE | nvarchar(5) | ISO 4217 code (USD, EUR, etc.) |
| ACTIVE_FLAG | int | Active flag |

### SHARED_CURRENCY_EXCHANGE
Exchange rate history. One row per currency pair per effective date.

**Logical key:** FROM_CURRENCY_ID + TO_CURRENCY_ID + EFFECTIVE_DATE

Key columns: XCHG_RATE decimal(15,8).

### SHARED_TERMS_RULE
Payment terms definitions (e.g., Net 30, 2/10 Net 30).

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(15) | **Logical key** |
| DESCRIPTION | nvarchar(80) | Description |
| DISC_PERCENT | decimal(6,3) | Early-payment discount % |
| DISC_DAYS | smallint | Days for discount |
| NET_DAYS | smallint | Net due days |
| NET_TYPE | nvarchar(32) | Net type (days from invoice, day of month, etc.) |
| ACTIVE_FLAG | int | Active flag |

### SHARED_TAX / SHARED_TAX_GROUP / SHARED_TAX_GROUP_TAX
- **SHARED_TAX** - Individual tax definitions (ID, DESCRIPTION, TAX_TYPE, TAX_RANK, EXCLUSIVE_FLAG)
- **SHARED_TAX_GROUP** - Tax groups (ID, DESCRIPTION)
- **SHARED_TAX_GROUP_TAX** - Junction table (TAX_GROUP_ID + TAX_ID)
- **SHARED_TAX_PCT** - Tax rate history with graduated bracket support (TAX_ID + EFFECTIVE_DATE)

### SHARED_PAYMENT_METHOD
Payment method definitions (check, EFT, wire, etc.).

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(15) | **Logical key** |
| DESCRIPTION | nvarchar(50) | Description |
| PAYMENT_MEDIA | nvarchar(32) | Media type (CHECK, EFT, WIRE) |
| EFT_FILE_FORMAT_ID | nvarchar(30) | EFT file format |

### SHARED_DOCUMENT_TYPE
Document type definitions per entity. Controls numbering, posting, approval workflow.

**Logical key:** ENTITY_ID + DOCUMENT_TYPE_ID

Key columns: DESCRIPTION, POST_IMMEDIATELY, JOURNAL_TYPE, NUMBERING_TYPE, DISPOSITION_ID, APPROVAL_DISP_ID, REJECTION_DISP_ID, ACTIVE_FLAG.

### SHARED_DISPOSITION
Status/disposition lookup (Open, Approved, Rejected, Posted, Void, etc.).

**Logical key:** ID

### Other Shared Tables

| Table | Logical Key | Purpose |
|---|---|---|
| SHARED_COMPANY_CTL | (singleton) | Company name and address |
| SHARED_PRODUCT | ID | Product/product-line lookup |
| SHARED_SALES_REP | ID | Sales rep master (name, contact, territory) |
| SHARED_TERRITORY | ID | Sales territory definitions |
| SHARED_COMMODITY | ID | Commodity code definitions |
| SHARED_COUNTRY_CODE | ID | Country code lookup |
| SHARED_STATE_PROVINCE | (composite) | State/province lookup |
| SHARED_FOB | ID | FOB point definitions |
| SHARED_SHIP_VIA | ID | Shipping method definitions |
| SHARED_INSTALLMENT_RULE | ID | Installment payment rules |
| SHARED_NOTATION | (composite) | Notation/notes records |
| SHARED_UOM | ID | Unit of measure definitions |

---

---

## 6. GL Posting Architecture (Cross-Database)

### How Postings Flow Between VECA and VFIN

VECA (manufacturing ERP) and VFIN (financial accounting) share a single chart of accounts but post GL entries through separate distribution table systems with different structures.

**VECA dist tables** store manufacturing/operational postings (WIP, shipments, inventory, purchasing). These use:
- Single `AMOUNT` column + `AMOUNT_TYPE` ('DR'/'CR')
- `GL_ACCOUNT_ID` for the account
- `POSTING_STATUS` ('U'=Unposted, 'P'=Posted)
- `BATCH_ID` linking to JOURNAL_BATCH for posting control
- `SITE_ID` for multi-site scoping

**VFIN dist tables** store financial postings (AR invoices, AP invoices, payments, journal entries). These use:
- Separate `DEBIT_AMOUNT` / `CREDIT_AMOUNT` columns
- `ACCOUNT_ID` for the account
- No explicit posting status (existence implies posted)
- `ENTITY_ID` for multi-entity scoping

**The bridge: LEDGER_DIRECT_JOURNAL.** When VECA journal batches are posted to Visual Financials, they create LEDGER_DIRECT_JOURNAL entries in VFIN. This is the mechanism by which VECA operational postings appear in VFIN's general ledger. The DIRECT_JOURNAL entries are summarized versions of the VECA detail.

### Distribution Tables by Volume

| DB | Table | Row Count | Source Document |
|---|---|---|---|
| VECA | WIP_ISSUE_DIST | ~7.2M | Work orders (material/labor/burden issues) |
| VECA | WIP_RECEIPT_DIST | ~6.2M | Work orders (finished goods receipts) |
| VECA | SHIPMENT_DIST | ~1.3M | Customer orders (COGS on shipment) |
| VFIN | RECEIVABLES_RECEIVABLE_DIST | ~552K | AR invoices |
| VECA | RECEIVABLE_DIST | ~536K | AR invoices (VECA side) |
| VFIN | CASHMGMT_PAYMENT_DIST | ~529K | Payments (receipts + disbursements) |
| VFIN | PAYABLES_PAYABLE_DIST | ~234K | AP invoices |
| VECA | PURCHASE_DIST | ~192K | Purchase orders (receipt accruals) |
| VFIN | LEDGER_GEN_JOURN_DIST | ~179K | General journal entries |
| VECA | ADJUSTMENT_DIST | ~131K | Inventory adjustments |
| VFIN | CASHMGMT_BANK_ADJ_DIST | ~13K | Bank adjustments |
| VECA | INDIRECT_DIST | ~3.9K | Indirect cost transactions |
| VFIN | LEDGER_DIRECT_JOURN_DIST | ~172 | System-generated (VECA batch posts) |
| VECA | GJ_DIST | ~108 | General journal entries |

**Excluded:** INV_TRANS_DIST (~15M rows) and INV_RECEIPT_DIST (~127K rows) track cost/qty distributions, not GL debit/credit postings.

### Key Views

- **VFIN `LEDGER_ALL_DISTRIBUTIONS`** - Built-in view unioning all 6 VFIN dist tables with a JOURNAL_TYPE discriminator ('GEN', 'PAYB', 'RECV', 'PAYMENT', 'BANKADJ', 'DIRECT'). Joins to parent header tables for REFERENCE and DOCUMENT_TYPE_ID.
- **VFIN `LEDGER_RECV_DISTRIBUTIONS`** - Receivables-focused view with customer context
- **VFIN `LEDGER_PAYB_DISTRIBUTIONS`** - Payables-focused view with supplier context

### Account Classification

`VECA.dbo.Z_GL_MAPPING` is a custom table that classifies GL accounts for financial reporting:
- `FS` - Financial statement (BS or IS)
- `FS_CAT` - Statement category (e.g., "Revenue", "Accrued Expenses")
- `FS_DET` - Detail category
- `CATEGORY` - Reporting category
- `CC_CAT` - Cost center category
- `BREAK_CAT` - Breakout category
- `EFFECTIVE_START_DATE` / `EFFECTIVE_END_DATE` - Date-effective account classification

### Consolidated Queries

See `queries/` directory:
- **`gl_posting_map.sql`** - Master union of all dist tables across both databases, normalized to common columns
- **`gl_posting_map_enriched.sql`** - Same plus Z_GL_MAPPING account classification
- **`gl_posting_today.sql`** - Daily audit: summary by type, balance check, and detail with account classification

---

## Common Patterns

- **Document flow (AR):** Customer Order -> Shipper -> Receivable (Invoice). Recurring templates generate receivables on a schedule.
- **Document flow (AP):** Purchase Order -> Receiver -> Payable (Invoice). Recurring templates generate payables on a schedule.
- **3-way matching (AP):** PAYABLES_PAYABLE_LINE links to PURCHASE_ORDER and RECEIVER for PO/receipt/invoice matching.
- **Journal pattern:** Header -> Lines (user-entered) -> Distributions (system-generated GL postings). Applies to GEN_JOURNAL, DIRECT_JOURNAL, RECEIVABLE, PAYABLE, PAYMENT, BANK_ADJUSTMENT.
- **Entity-level config:** Most master records (Customer, Supplier) have a base table + `_ENTITY` table with per-entity overrides (accounts, terms, banking, status).
- **Status fields** use nvarchar(32) enums (e.g., 'Open', 'Paid', 'Void', 'Closed') rather than single-char codes.
- **RECORD_IDENTITY** is the physical PK everywhere; logical/business keys are enforced by the application, not by unique constraints.
- **Exchange rate tables:** Most transaction headers have companion `_CURR` (system rates) and `_USRCURR` (user overrides) tables.
- **Commission tracking:** AR invoices and customer orders have `_COMM` (per-rep tracking) and `_SHARE` (rep-to-rep sharing) tables.
- **Use LEDGER_ALL_DISTRIBUTIONS** view for cross-module GL distribution queries -- it unions GEN, PAYB, RECV, PAYMENT, BANKADJ, and DIRECT journals.
