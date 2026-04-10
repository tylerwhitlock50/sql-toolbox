# Organized queries (working set)

This `_organized/` tree is a **working set** structure for the `old-queries/` dump.

Principles:

- Prefer **copy/move** into `_organized/` over editing query logic during cleanup.
- Anything that **writes** (`UPDATE`/`DELETE`/`DROP`/etc.) should go in `99_write_scripts_review/` until it's confirmed safe and still relevant.
- Keep domain folders small and purposeful; if something doesn't clearly belong, put it in `90_misc/` and tag it in the index.

See `old-queries/_analysis/inventory.csv` for a best-effort machine inventory (DB references, write flag, and rough domain guess).

