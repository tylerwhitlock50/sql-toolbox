# SQL Toolbox - Canonical Queries

This folder is the source of truth for production-ready queries.

## Folder Layout

- `domains/gl/` - General ledger and accounting queries
- `domains/sales/` - Sales reporting and customer-order analytics
- `domains/supply_chain/` - Inventory, material flow, and supply-chain analysis
- `domains/purchasing/` - Purchasing and vendor/AP-adjacent operational queries
- `domains/scheduling/` - Planning and scheduling analysis
- `domains/shipping/` - Shipping, fulfillment, and logistics queries
- `domains/diagnostics/` - System/data diagnostics and integration checks

## Current Canonical Inventory

| Domain | Query | Purpose |
|---|---|---|
| GL | `domains/gl/gl_posting_map.sql` | Unified VECA + VFIN posting detail |
| GL | `domains/gl/gl_posting_map_enriched.sql` | Posting detail + account classification |
| GL | `domains/gl/gl_posting_today.sql` | Daily posting audit |
| GL | `domains/gl/trial_balance.sql` | Trial balance as-of date |
| GL | `domains/gl/gl_balance_export.sql` | Period balance export |
| GL | `domains/gl/chart_of_accounts.sql` | Chart of accounts + mapping checks |
| Diagnostics | `domains/diagnostics/diagnose_veca_vfin_overlap.sql` | Data overlap diagnostics |
| Diagnostics | `domains/diagnostics/diagnose_exchange_subscriptions.sql` | Exchange subscription diagnostics |

## Canonical Rules

- Keep canonical queries in domain folders only (not at `queries/` root).
- File names should be lowercase snake_case and end in `.sql`.
- Start each query with a clear parameter block (`DECLARE ...`) and inline comments for each parameter.
- Add a short header block in each query with: purpose, inputs, expected output shape, and caveats.
- If a query is exploratory/temporary, keep it outside this folder until stabilized.

## Add-a-Query Checklist

1. Choose the correct domain folder under `queries/domains/`.
2. Name file in lowercase snake_case.
3. Include parameter block and short usage examples.
4. Update this README inventory table in the same commit.

## Migration Note

Existing links/docs that referenced old paths at `queries/*.sql` should be updated to `queries/domains/...`.
