# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this repo is

SQL Toolbox is a working repository for managing, versioning, and developing SQL queries against Infor VISUAL ERP databases. **It is not an application** — there is no build, test suite, or runtime. The artifacts are `.sql`, `.md`, `.rdl` (SSRS report definitions), and `.csv`. Queries are executed by humans in SSMS or rendered by SSRS against a live SQL Server.

Primary goals:
- Iterate on SQL against the ERP faster with AI assistance
- Diagnose data issues and trace problems across related tables
- Keep queries version-controlled (not lost in SSMS tabs)
- Build up schema docs so context doesn't have to be rediscovered every session

## Databases covered

| DB | Role | Schema doc | DDL dump |
|---|---|---|---|
| **VECA** | Infor VISUAL Manufacturing — sales, mfg, inventory, purchasing | `database_scripts/veca.md` | `database_scripts/veca/` (+ `useful_views/`) |
| **VFIN** | Visual Financials — GL, AR, AP, Cash | `database_scripts/vfin.md` | `database_scripts/vfin/` |
| **LSA**  | Visual Exchange / sync layer between VECA and VFIN | `database_scripts/lsa.md`  | `database_scripts/lsa/` |

`active_tables.csv` / `active_tables_vfin.csv` list the tables actually being used (row counts, last-modified) — a quick sanity filter when the DDL dump has hundreds of dead tables.

`database_scripts/old-finance-scripts/` and `database_scripts/diagnostics/` hold standalone utilities (GL import, TB export, exchange diagnostics).

## Top-level layout

```
database_scripts/   Schema docs (.md) + raw DDL dumps + active-table CSVs
queries/            Canonical, production-ready queries (source of truth)
  domains/          Organized by business domain (see below)
  fixes/            Write scripts (UPDATE/DELETE cleanup) — review before running
reports/            SSRS .rdl report definitions built on top of canonical queries
old-queries/        Incoming dump from IT/Accounting — triage area, NOT canonical
REPORTING_PROPOSAL.md  Tableau-vs-SSRS strategy doc; cross-references canonical queries
```

## The `queries/` canonical tree

This is the source of truth for production queries. `queries/README.md` has the full inventory table — **update it in the same commit when adding a query.**

Domain folders under `queries/domains/`:

- `gl/` — general ledger, trial balance, chart of accounts
- `sales/order_information/`, `sales/performance/` — customer orders, OTD, customer scorecards, demand trend
- `inventory/part_information/` — part-level planning snapshot, exceptions, stocking policy
- `production/performance/` — WO aging/WIP, OTD, labor, resource efficiency, completion forecast
- `scheduling/` — resource capacity load, bottleneck flags
- `shipping/` — fulfillment/logistics
- `supply_chain/`
  - `bom/` — recursive BOM and routing explosion
  - `demand/` — unified demand views (SO + master schedule + forecast), BOM-exploded gross requirements
  - `planning/` — time-phased net requirements, purchasing plan, build priority, make plan
  - `purchasing/` — open/planned PO supply, price history, cost summaries
  - `performance/` — vendor/buyer scorecards, lead-time history, price volatility, shortages
  - `executive/` — CEO KPI snapshots, waste & stagnation
  - `E&O/` — excess & obsolete analysis
- `diagnostics/` — cross-DB / integration checks (VECA↔VFIN overlap, Exchange subscriptions)

## Conventions for canonical queries

- File names: `lowercase_snake_case.sql`, one query per file, placed in a domain folder (never at `queries/` root).
- **Header block** at the top of every `.sql`: purpose, inputs, expected output shape, caveats (see `queries/domains/supply_chain/planning/purchasing_plan.sql` for the template).
- **Parameter block** right after the header: `DECLARE @Site nvarchar(15) = NULL;` etc., with an inline comment per parameter.
- **Optional-filter pattern** for parameters so blank/null means "all": `(@Param IS NULL OR @Param = '' OR column = @Param)`. SSRS depends on this — see below.
- Exploratory / temporary queries stay **outside** `queries/domains/` until stable.
- `queries/fixes/` is for reviewed write scripts. They follow a "run in `BEGIN TRAN` → inspect counts → rerun with `COMMIT`" pattern — do not rewrite them to commit unconditionally.

## SSRS reports (`reports/`)

12 `.rdl` files, each built on a specific canonical query in `queries/domains/`. The mapping (report → source query → audience → cadence) is in `reports/README.md`.

Working rules:
- SQL is embedded inline in each `.rdl`'s `<CommandText>` CDATA. When the canonical query evolves, copy the updated SQL into the matching RDL **but strip the top-level `DECLARE @Param ...;` lines** — SSRS passes those via `<QueryParameters>` and the `DECLARE`s will conflict.
- Preserve the optional-filter pattern (`@Param IS NULL OR ...`) so blank = "all" still works in the report.
- All 12 reports use the **RDL 2016** schema and reference a shared data source at `/VECA` (no embedded `ConnectString`). When authoring a new report or chasing a deployment error, see [`reports/RDL_2016_CHECKLIST.md`](reports/RDL_2016_CHECKLIST.md) — it documents the five 2010→2016 strictness gotchas (`MustUnderstand="df"` + `df:` namespace, `<rd:ReportID>`, non-empty `<Paragraph>`, `<ReportParametersLayout>` with cell count = param count, shared `DataSourceReference`).
- When adding/removing a report parameter, update `<ReportParameter>`, `<QueryParameter>`, **and** `<ReportParametersLayout>` together — mismatched counts fail at run-time, not at deserialization.
- The BOM-driven reports (`buyer_po_action_list`, `daily_build_priority`, `so_fulfillment_risk`, etc.) re-walk the BOM every run; cache at SSRS or materialize to staging tables for production.

## The `old-queries/` dump

This is **incoming from IT + Accounting** — triage territory, not canonical.

- `old-queries/Queries/` keeps the original dump layout.
- `old-queries/_analysis/inventory.csv` is a machine-generated inventory (DB reference, write flag, rough domain guess).
- `old-queries/_organized/` is the working cleanup set; anything dangerous (`UPDATE`/`DELETE`/`DROP`/`ALTER`/`CREATE`) lives in `_organized/99_write_scripts_review/` until verified.
- **Never run a script from `old-queries/` without checking the write flag.** Do not promote anything into `queries/domains/` without rewriting it to canonical conventions (header + parameter block + optional filters).

## Database quirks to remember when writing queries

### VECA (Visual Manufacturing)
- **Multi-site architecture** — almost every transactional table has `SITE_ID`. Default to filtering by it.
- **Part data is split across PART + PART_SITE.** Use **`PART_SITE_VIEW`** (in `database_scripts/veca/useful_views/`) instead of joining manually — it applies `ISNULL(PART_SITE.col, PART.col)` so site-level overrides fall back to part-level defaults. Similar pattern for `CUSTOMER_SITE_VIEW`, `ACCOUNT_SITE_VIEW`, `EMPLOYEE_SITE_VIEW`, etc. Prefer the `_SITE_VIEW` wherever one exists.
- **Work order composite key** is 5 parts: `TYPE, BASE_ID, LOT_ID, SPLIT_ID, SUB_ID`. All WO-related joins must include all five.
- DDL files were exported from SSMS as **UTF-16** and look wide-spaced when read raw — content is fine.

### VFIN (Visual Financials)
- **Every table has a surrogate clustered PK `RECORD_IDENTITY nvarchar(12)`.** Business keys are logical, not declared — join on the business key columns (e.g., `ENTITY_ID + ACCOUNT_ID`), not on `RECORD_IDENTITY` unless you already have one.
- **No declared foreign keys** — relationships are app-enforced. FKs in `vfin.md` are inferred.
- **Entity-scoped**: most tables filter by `ENTITY_ID` for multi-company support.
- **Audit columns on every table** (`RECORD_CREATED`, `RECORD_MODIFIED`, `RECORD_USER`, `RECORD_MODIFY_USER`, `RECORD_VERSION`) — omitted from schema-doc column lists.
- **Multi-currency**: amounts + rates live in separate `_CURR` / `_USRCURR` tables.

### LSA (Visual Exchange)
- This is the **integration/sync layer** — the source of truth for how data moves between VECA and VFIN. When diagnosing a "why didn't this post?" question, start here (`EXCHANGE_SUBSCRIPTION`, `EXCHANGE_ACTIVITY`, `EXCHANGE_TASK`, `EXCHANGE_TRANSFORMATION`).

## Working approach

- **Read the schema doc first.** `database_scripts/<db>.md` is curated for the tables people actually use — don't start by grepping the DDL dump.
- **Fall back to DDL only for details** the schema doc lacks (column constraints, odd types).
- **Reuse existing canonical queries** before writing new ones — check `queries/README.md`'s inventory table.
- **Keep the inventory in sync.** Adding or moving a query in `queries/domains/` requires an edit to `queries/README.md` in the same commit.
