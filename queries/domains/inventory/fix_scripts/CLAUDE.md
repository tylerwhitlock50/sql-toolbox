# CLAUDE.md — inventory / fix_scripts

**These scripts write to the database.** Review and understand each before running.

## Scope

Targeted cleanup scripts that reconcile denormalized inventory / demand fields against their authoritative sources. Not reports, not exploratory — these are **production data-repair utilities**.

## The write-script pattern

Every script follows the same safety shape:

```sql
BEGIN TRAN;

-- Step 1: INSPECT — build a reconciliation query, eyeball the impact
SELECT ... diagnosis_column ...
FROM ...

-- Step 2: UPDATE — apply fixes to one table at a time
-- UPDATE ...
-- SET ...

-- Step 3: VALIDATE — re-run the reconciliation; verify zero mismatches

-- COMMIT;   -- left commented out on purpose
-- ROLLBACK;
```

**Rules:**
1. **Never remove the `BEGIN TRAN`** or uncomment `COMMIT` in the committed file. Commit/rollback happens during the manual run.
2. **Run inspect first.** If diagnostic counts look wrong, stop — the fix is probably misaligned with data state.
3. **Scripts are idempotent.** Safe to re-run; a second run on clean data should report zero changes.
4. **These are single-user operations.** Coordinate with planners — running during active MRP/shipping produces moving-target state.

## Recommended run order

The scripts are numbered because the dependencies matter:

| # | Script | What it does | Depends on |
|---|---|---|---|
| **1** | `1-update_qty_on_hand.sql` | Reconcile `PART.QTY_ON_HAND` and `PART_SITE.QTY_ON_HAND` against `SUM(INVENTORY_TRANS)` | Nothing. Start here. |
| **1.5** | `1.5-Missing_location_parts.sql` | **Diagnostic only** — flags `(part, warehouse, location)` where `PART_LOCATION.QTY` disagrees with `INVENTORY_TRANS`. Manual follow-up. | — |
| **2** | `2-match_requirement_status.sql` | Propagate WO status onto `REQUIREMENT` rows so cancelled/closed WOs stop generating phantom demand | #1 done |
| **3** | `3-update_qty_in_demand.sql` | Reconcile `PART.QTY_IN_DEMAND` and `PART_SITE.QTY_IN_DEMAND` against open SO + open WO requirements | #2 done (requirement statuses must be correct first) |

Why this order:
- #1 establishes physical-qty ground truth.
- #2 makes WO requirement data honest.
- #3 recomputes demand based on corrected requirements.

## Script 1 — `update_qty_on_hand.sql`

**Source of truth:** `SUM(CASE WHEN type='I' THEN qty ELSE -qty END)` from `INVENTORY_TRANS`.

**Diagnosis buckets:**
```sql
CASE
    WHEN part.qty_on_hand = trans_qty AND ps_total <> trans_qty THEN 'PART_SITE appears wrong'
    WHEN part.qty_on_hand <> trans_qty AND ps_total = trans_qty THEN 'PART appears wrong'
    WHEN part.qty_on_hand <> trans_qty AND ps_total <> trans_qty THEN 'Both PART and PART_SITE differ from transactions'
    ELSE 'No issue'
END
```

**What it writes:**
1. `PART_SITE.QTY_ON_HAND = trans_qty` — **only for single-site parts** (lower blast radius). Multi-site mismatches are flagged but not auto-fixed.
2. `PART.QTY_ON_HAND = trans_qty` — the master roll-up.

**Caveat:** this trusts `INVENTORY_TRANS` as truth. If the trans log itself is wrong (unreversed scrap, orphan receipts), you'll propagate the error. Run script 1.5 first to spot-check.

## Script 1.5 — `Missing_location_parts.sql`

**Diagnostic only — no writes.** Flags bin-level discrepancies (`PART_LOCATION.QTY` vs sum of bin-level `INVENTORY_TRANS`). `ORDER BY ABS(qty_diff) DESC` so the biggest problems surface first.

Common causes:
- Orphaned `PART_LOCATION` rows (stock recorded but no trans history)
- Orphan trans (historical data, location since deleted)
- Location transfers recorded one place but not the other
- Manual adjustments recorded in only one table

Fix manually. Script 1 operates at the site level and won't repair bin-level drift.

## Script 2 — `match_requirement_status.sql`

**Problem:** a cancelled WO (`status='X'`) whose `REQUIREMENT` rows are still `'R'` makes MRP double-count demand.

**Rule:** WO status is authoritative. Propagate to requirements.

```sql
UPDATE r
SET r.status =
    CASE
        WHEN w.status IN ('C','X') THEN w.status
        WHEN w.status <> 'R'        THEN w.status
        ELSE r.status
    END
WHERE r.status = 'R' AND w.status <> 'R'
```

**Caveat:** the inspection / update joins need both the 5-part WO composite key AND `WORKORDER_TYPE`. Check line 191 of the file when adapting.

## Script 3 — `update_qty_in_demand.sql`

**Source of truth:** open SO + open WO requirements, using the canonical filters:

```sql
-- Sales side
WHERE h.STATUS IN ('R','F') AND l.LINE_STATUS = 'A'
qty = SUM(ORDER_QTY - ISNULL(TOTAL_SHIPPED_QTY, 0))

-- Manufacturing side (REQUIREMENT must match WO status — script 2 first!)
WHERE w.TYPE = 'W' AND w.STATUS IN ('F','R') AND r.STATUS IN ('F','R')
qty = SUM(ISNULL(r.CALC_QTY, 0) - ISNULL(r.ISSUED_QTY, 0))
```

**Same diagnose → update pattern as script 1**: single-site `PART_SITE` first, then `PART` master.

## Gotchas

- **`@Site` is deliberately not parameterized** — these operate globally. Don't add a site filter unless you know you're only fixing one site.
- **Fix scripts and canonical queries share the same open-demand logic.** If you change the open-SO or WO-requirement filter in one place, change it everywhere (and in the sales + planning CLAUDE.md files).
- **Script 2 must run before script 3.** Otherwise #3 calculates demand including phantom requirements from cancelled WOs.
- **Don't run these concurrently with active shipping/receiving.** The denormalized fields are being updated by the transactional system at the same time; your reconciliation becomes a race.
- **UPDATE on `PART_SITE`** only fires when `site_count = 1` by design. Multi-site mismatches require human investigation (which site is correct?) and a manual fix.
