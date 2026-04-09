# SQL Toolbox

A working repository for managing, versioning, and developing SQL queries against our ERP databases. This is not an application — it's a toolkit for faster query writing, data diagnosis, and analysis.

## Purpose

- Write and iterate on SQL queries faster with AI assistance
- Diagnose data issues and trace problems across related tables
- Version control queries so they don't get lost in SSMS tabs
- Build up database documentation so we don't have to re-learn schema context every session

## Databases

### VECA (Infor VISUAL Manufacturing)
The core ERP database. Manufacturing, sales, purchasing, inventory, and accounting.
- Schema reference: `database_scripts/veca.md`
- DDL scripts: `database_scripts/veca/` (table DDLs exported from SQL Server)
- Key views: `database_scripts/veca/useful_views/`

### VFIN (Visual Financials)
Financial/accounting database. *(Documentation TBD)*

### Others
Additional databases may be added as needed.

## Repository Structure

```
database_scripts/
  veca.md              # VECA schema quick-reference
  veca/                # VECA table DDL scripts
  veca/useful_views/   # VECA view definitions worth keeping handy
```

## Working With This Repo

- **Schema docs** (`database_scripts/<db>.md`) are the go-to reference for understanding tables, keys, and relationships. Read these before writing queries against a database.
- **DDL scripts** are the raw CREATE TABLE/VIEW exports from SQL Server. Use these when the schema doc doesn't have enough detail on a specific column or constraint.
- The DDL files use UTF-16 encoding (exported from SSMS) — they read fine but have wide character spacing when viewed raw.
- **Prefer views over manual joins** where site-level views exist (e.g., PART_SITE_VIEW over joining PART + PART_SITE).
- VECA uses multi-site architecture — most transactional tables have a SITE_ID column.
- Work order tables use a 5-part composite key: TYPE, BASE_ID, LOT_ID, SPLIT_ID, SUB_ID.
