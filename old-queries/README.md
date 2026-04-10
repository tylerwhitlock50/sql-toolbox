# Old queries (incoming dump)

This folder is an **incoming dump** of SQL scripts from IT + Accounting. Many are useful, many are one-off fixes, and some are **dangerous write scripts** (`UPDATE`/`DELETE`/`DROP`/etc).

## How this folder is organized (proposed)

- `old-queries/_analysis/`: machine-generated inventory to speed up cleanup
- `old-queries/`: original dump layout (kept intact for now)

## Inventory

See `old-queries/_analysis/inventory.csv` for:

- which DBs a script references (best-effort, e.g. VECA/VFIN)
- whether it appears to do **writes**
- a rough domain guess (work orders, shipping, parts/inventory, etc.)

## Safety

If a script contains `UPDATE`/`DELETE`/`DROP`/`ALTER`/`CREATE`, treat it as **review required** before running.

