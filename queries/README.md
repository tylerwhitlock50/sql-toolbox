# SQL Toolbox - Query Guide

## Quick Start

All queries are parameterized. Open in SSMS, update the `DECLARE` variables at the top, and run.

```sql
-- Example: every query starts with a parameter block like this
DECLARE @DateFrom     date        = '2026-01-01';   -- <-- change these
DECLARE @DateTo       date        = '2026-04-09';
DECLARE @PostedOnly   bit         = 1;
```

---

## Query Inventory

| Query | Purpose | Replaces |
|---|---|---|
| `gl_posting_map.sql` | All GL postings across VECA + VFIN (raw) | New |
| `gl_posting_map_enriched.sql` | Same + Z_GL_MAPPING account classification | `old-finance-scripts/gl_detail.sql` |
| `gl_posting_today.sql` | Daily posting audit (summary + balance check + detail) | New |
| `trial_balance.sql` | Trial balance as of a date | `old-finance-scripts/tb-export.sql` |
| `gl_balance_export.sql` | Period balances with source module breakdown | `old-finance-scripts/GL-import.sql` |
| `chart_of_accounts.sql` | Full chart of accounts with Z_GL_MAPPING | `old-finance-scripts/chart_of_accounts.sql` (was empty) |

---

## How to Run Each Query

### 1. gl_posting_map.sql - Raw Posting Detail

**When to use:** You need to see every individual GL distribution line across both databases with full source document traceability.

**Parameters:**
| Parameter | Type | Default | Description |
|---|---|---|---|
| `@DateFrom` | date | `'2026-01-01'` | Start of posting date range |
| `@DateTo` | date | `'2026-04-09'` | End of posting date range |
| `@PostedOnly` | bit | `1` | 1 = posted only, 0 = include unposted VECA entries |
| `@SourceDB` | nvarchar(4) | `NULL` | NULL = both databases, `'VECA'` or `'VFIN'` |
| `@JournalType` | nvarchar(20) | `NULL` | NULL = all types, or a specific type (see list below) |
| `@AccountID` | nvarchar(30) | `NULL` | NULL = all accounts, or specific GL account |

**Common examples:**
```sql
-- Everything posted in March 2026
SET @DateFrom = '2026-03-01';
SET @DateTo   = '2026-03-31';

-- Only VFIN payment distributions
SET @JournalType = 'VFIN_PAYMENT';

-- Only postings to account 4100
SET @AccountID = '4100';

-- Only VECA manufacturing postings
SET @SourceDB = 'VECA';
```

**Journal Types:**
| Code | Source | What It Is |
|---|---|---|
| `VECA_WIP_ISSUE` | WIP_ISSUE_DIST | Material/labor/burden issued to work orders |
| `VECA_WIP_RCPT` | WIP_RECEIPT_DIST | Finished goods received from work orders |
| `VECA_SHIPMENT` | SHIPMENT_DIST | Cost of goods shipped to customers |
| `VECA_RECV` | RECEIVABLE_DIST | AR invoice postings (VECA side) |
| `VECA_PURCHASE` | PURCHASE_DIST | PO receipt accruals |
| `VECA_ADJUST` | ADJUSTMENT_DIST | Inventory adjustments |
| `VECA_INDIRECT` | INDIRECT_DIST | Indirect cost postings |
| `VECA_GJ` | GJ_DIST | General journal entries (VECA) |
| `VFIN_RECV` | RECEIVABLES_RECEIVABLE_DIST | AR invoice postings (VFIN) |
| `VFIN_PAYB` | PAYABLES_PAYABLE_DIST | AP invoice postings |
| `VFIN_PAYMENT` | CASHMGMT_PAYMENT_DIST | Cash receipts and disbursements |
| `VFIN_GEN` | LEDGER_GEN_JOURN_DIST | General journal entries (VFIN) |
| `VFIN_BANKADJ` | CASHMGMT_BANK_ADJ_DIST | Bank adjustments |
| `VFIN_DIRECT` | LEDGER_DIRECT_JOURN_DIST | System-generated (VECA batch posts to VFIN) |

**Tracing back to source documents:**
The `DOCUMENT_ID` column tells you what triggered the posting. Use `JOURNAL_TYPE` to know which table to look in:

- `VECA_WIP_ISSUE` / `VECA_WIP_RCPT`: Use the `WO_TYPE`, `WO_BASE_ID`, `WO_LOT_ID`, `WO_SPLIT_ID`, `WO_SUB_ID` columns to join to `VECA.dbo.WORK_ORDER`.
- `VECA_SHIPMENT`: `DOCUMENT_ID` = `CUST_ORDER_ID` in `VECA.dbo.CUSTOMER_ORDER`.
- `VECA_RECV`: `DOCUMENT_ID` = `INVOICE_ID` in `VECA.dbo.RECEIVABLE`.
- `VECA_PURCHASE`: `DOCUMENT_ID` = `PURC_ORDER_ID` in `VECA.dbo.PURCHASE_ORDER`.
- `VFIN_RECV`: `DOCUMENT_ID` = `INVOICE_ID` in `VFIN.dbo.RECEIVABLES_RECEIVABLE`.
- `VFIN_PAYB`: `DOCUMENT_ID` = `INVOICE_ID` in `VFIN.dbo.PAYABLES_PAYABLE`.
- `VFIN_PAYMENT`: `DOCUMENT_ID` = `PAYMENT_ID` in `VFIN.dbo.CASHMGMT_PAYMENT`. The `LINKED_INVOICE_ID` shows which AR or AP invoice the payment was applied to.
- `VFIN_GEN`: `DOCUMENT_ID` = `GEN_JOURNAL_ID` in `VFIN.dbo.LEDGER_GEN_JOURNAL`.

---

### 2. gl_posting_map_enriched.sql - Posting Detail + Account Classification

**When to use:** Same as gl_posting_map but you need the Z_GL_MAPPING columns (FS, FS_CAT, CATEGORY, etc.) for financial reporting context.

**Extra parameter:**
| Parameter | Type | Default | Description |
|---|---|---|---|
| `@FSType` | nvarchar(10) | `NULL` | NULL = all, `'IS'` = Income Statement, `'BS'` = Balance Sheet |

All other parameters same as gl_posting_map.sql.

**Common examples:**
```sql
-- Income Statement detail for Q1
SET @DateFrom = '2026-01-01';
SET @DateTo   = '2026-03-31';
SET @FSType   = 'IS';

-- All revenue postings in March
SET @DateFrom = '2026-03-01';
SET @DateTo   = '2026-03-31';
SET @FSType   = 'IS';
-- Then filter results in Excel by CATEGORY = 'Revenue'
```

---

### 3. gl_posting_today.sql - Daily Posting Audit

**When to use:** End-of-day check on what posted. Runs three result sets in one execution.

**Parameters:**
| Parameter | Type | Default | Description |
|---|---|---|---|
| `@AsOfDate` | date | `GETDATE()` | The date to audit (defaults to today) |
| `@PostedOnly` | bit | `1` | 1 = posted only, 0 = include unposted |

**Result sets returned:**
1. **Summary by Journal Type** - Row counts, document counts, total debits/credits per source
2. **Balance Check** - Debits vs credits per database. Non-zero OUT_OF_BALANCE = problem
3. **Detail with Account Classification** - Every posting row with Z_GL_MAPPING enrichment

**Common examples:**
```sql
-- Audit yesterday
SET @AsOfDate = DATEADD(day, -1, GETDATE());

-- Audit a specific date
SET @AsOfDate = '2026-04-01';
```

---

### 4. trial_balance.sql - Trial Balance

**When to use:** Generate a trial balance as of a specific date for month-end/quarter-end/year-end.

**Parameters:**
| Parameter | Type | Default | Description |
|---|---|---|---|
| `@CutoffDate` | date | `'2026-03-31'` | Trial balance as-of date |
| `@FiscalYearStart` | date | `'2026-01-01'` | First day of fiscal year |

**How it works:**
- Balance Sheet accounts (1xxx-3xxx): Cumulative balance from beginning of time through `@CutoffDate`
- Income Statement accounts (4xxx+): YTD balance from `@FiscalYearStart` through `@CutoffDate`

This matches standard accounting treatment: BS carries forward, IS resets at year start.

**Common examples:**
```sql
-- March 2026 month-end
SET @CutoffDate      = '2026-03-31';
SET @FiscalYearStart = '2026-01-01';

-- December 2025 year-end
SET @CutoffDate      = '2025-12-31';
SET @FiscalYearStart = '2025-01-01';

-- June 2025 mid-year
SET @CutoffDate      = '2025-06-30';
SET @FiscalYearStart = '2025-01-01';
```

---

### 5. gl_balance_export.sql - Period Balance Export

**When to use:** Export period-level GL balances for importing into Excel or BI tools. Includes source module breakdown (how much came from Receivables vs Payables vs Cash Mgmt, etc.).

**Parameters:**
| Parameter | Type | Default | Description |
|---|---|---|---|
| `@DateFrom` | date | `'2026-01-01'` | Period start |
| `@DateTo` | date | `'2026-04-09'` | Period end |
| `@FSType` | nvarchar(10) | `NULL` | NULL = all, `'IS'` or `'BS'` |
| `@AccountID` | nvarchar(30) | `NULL` | NULL = all, or specific account |

**Source module columns returned:**
- `GEN_JOURNAL_NET` - General journal entries
- `RECEIVABLES_NET` - AR invoice postings
- `PAYABLES_NET` - AP invoice postings
- `CASH_MGMT_NET` - Cash management (payments)
- `BANK_ADJ_NET` - Bank adjustments
- `DIRECT_JOURN_NET` - Direct journals (VECA batch posts)
- `ADJUSTMENT_NET` - Adjustment entries

---

### 6. chart_of_accounts.sql - Chart of Accounts

**When to use:** Review the full chart of accounts, check Z_GL_MAPPING coverage, find unmapped or mismatched accounts.

**Parameters:**
| Parameter | Type | Default | Description |
|---|---|---|---|
| `@ActiveOnly` | bit | `1` | 1 = active accounts only, 0 = include inactive |
| `@FSType` | nvarchar(10) | `NULL` | NULL = all, `'IS'` or `'BS'` |
| `@AccountClass` | nvarchar(32) | `NULL` | NULL = all, or `'Asset'`, `'Liability'`, `'Equity'`, `'Revenue'`, `'Expense'` |
| `@AsOfDate` | date | `GETDATE()` | Date for Z_GL_MAPPING effective lookup |

**MAPPING_STATUS column:**
- `OK` - Account exists in both LEDGER_ACCOUNT and Z_GL_MAPPING, descriptions match
- `NO MAPPING` - Account exists in VFIN but has no Z_GL_MAPPING entry
- `DESC MISMATCH` - Account exists in both but descriptions differ

---

## Migration from Old Scripts

| Old Script | New Script | What Changed |
|---|---|---|
| `old-finance-scripts/tb-export.sql` | `trial_balance.sql` | Parameterized dates, Z_GL_MAPPING with date-effective join, removed hardcoded +8 suspense adjustment |
| `old-finance-scripts/GL-import.sql` | `gl_balance_export.sql` | Parameterized, date-effective Z_GL_MAPPING join (fixes row duplication), added source module breakdown, removed hardcoded suspense row |
| `old-finance-scripts/gl_detail.sql` | `gl_posting_map_enriched.sql` | Added VECA dist tables (8 more sources), JOURNAL_TYPE labels, PAYMENT_ID preserved (was lost), date-effective Z_GL_MAPPING, parameterized |
| `old-finance-scripts/chart_of_accounts.sql` | `chart_of_accounts.sql` | Created from scratch (old file was empty) |

### Data Coverage Comparison

| Data | Old Scripts | New Scripts |
|---|---|---|
| VFIN Receivable Dists | gl_detail.sql | gl_posting_map.sql (VFIN_RECV) |
| VFIN Payable Dists | gl_detail.sql | gl_posting_map.sql (VFIN_PAYB) |
| VFIN Payment Dists | gl_detail.sql (via PAYB_INVOICE_ID only) | gl_posting_map.sql (VFIN_PAYMENT + LINKED_INVOICE_ID) |
| VFIN Gen Journal Dists | gl_detail.sql | gl_posting_map.sql (VFIN_GEN) |
| VFIN Bank Adj Dists | gl_detail.sql | gl_posting_map.sql (VFIN_BANKADJ) |
| VFIN Direct Journal Dists | gl_detail.sql | gl_posting_map.sql (VFIN_DIRECT) |
| VECA WIP Issue Dists | **not covered** | gl_posting_map.sql (VECA_WIP_ISSUE) |
| VECA WIP Receipt Dists | **not covered** | gl_posting_map.sql (VECA_WIP_RCPT) |
| VECA Shipment Dists | **not covered** | gl_posting_map.sql (VECA_SHIPMENT) |
| VECA Receivable Dists | **not covered** | gl_posting_map.sql (VECA_RECV) |
| VECA Purchase Dists | **not covered** | gl_posting_map.sql (VECA_PURCHASE) |
| VECA Adjustment Dists | **not covered** | gl_posting_map.sql (VECA_ADJUST) |
| VECA Indirect Dists | **not covered** | gl_posting_map.sql (VECA_INDIRECT) |
| VECA GJ Dists | **not covered** | gl_posting_map.sql (VECA_GJ) |
| GL Period Balances | GL-import.sql | gl_balance_export.sql |
| Trial Balance | tb-export.sql | trial_balance.sql |
| Chart of Accounts | (empty) | chart_of_accounts.sql |

**No data is lost.** The new queries are a strict superset of the old ones. The old scripts only covered VFIN distribution tables; the new scripts add all 8 VECA distribution tables.

### Suspense Account 2195 Note

Both `tb-export.sql` and `GL-import.sql` had a hardcoded +$8.00 adjustment to account 2195 (Suspense). The new queries do **not** include this adjustment. If this correction is still needed, it should be addressed as a journal entry in the system rather than baked into reporting queries.

---

## Tips

- **Performance:** The full `gl_posting_map.sql` with no filters touches ~16M+ VECA rows. Always set a date range.
- **SSMS Results to Grid vs Text:** Use Results to Grid (Ctrl+D) for these queries. For exports, use Results to File (Ctrl+Shift+F) or copy/paste to Excel.
- **Excel export:** Run the query, click the top-left cell in the results grid, Ctrl+A to select all, Ctrl+C to copy, paste into Excel.
- **NULL parameters = no filter:** Setting any parameter to NULL means "give me everything" for that dimension. Only set what you need.
