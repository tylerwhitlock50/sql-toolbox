# CLAUDE.md — scheduling

Rules for resource-capacity-load and bottleneck queries (VECA).

## Scope

Per-resource weekly load vs capacity with bottleneck flags. Same WO / OPERATION tables as production/performance, but viewed along the **resource × week** axis.

## Core tables

| Table | Grain | Notes |
|---|---|---|
| `WORK_ORDER` | 5-part key | Open WO status (F/R), `SITE_ID` |
| `OPERATION` | 5-part key + `SEQUENCE_NO` | `RESOURCE_ID`, `SCHED_START_DATE`, engineered + actual setup/run hrs |
| `SHOP_RESOURCE` | `RESOURCE_ID` | `SHIFT_1_CAPACITY`, `SHIFT_2_CAPACITY`, `SHIFT_3_CAPACITY`, `EFFICIENCY_FACTOR`, `TYPE`, `STATUS`, `SCHEDULE_NORMALLY` |

## The 5-part WO join (same as production)

```sql
FROM WORK_ORDER wo
INNER JOIN OPERATION op
    ON op.WORKORDER_TYPE     = wo.TYPE
   AND op.WORKORDER_BASE_ID  = wo.BASE_ID
   AND op.WORKORDER_LOT_ID   = wo.LOT_ID
   AND op.WORKORDER_SPLIT_ID = wo.SPLIT_ID
   AND op.WORKORDER_SUB_ID   = wo.SUB_ID
WHERE wo.TYPE = 'W'
  AND ISNULL(wo.STATUS,'') NOT IN ('X','C')
  AND ISNULL(op.STATUS,'') NOT IN ('X','C')
  AND op.RESOURCE_ID IS NOT NULL
  AND op.SCHED_START_DATE IS NOT NULL
```

**Unscheduled ops** (`SCHED_START_DATE IS NULL`) are excluded — they don't consume capacity in any week. The master scheduler must assign a date before load shows up.

## Remaining hours (canonical)

```sql
REM_SETUP_HRS = CASE WHEN ISNULL(SETUP_HRS,0) > ISNULL(ACT_SETUP_HRS,0)
                     THEN ISNULL(SETUP_HRS,0) - ISNULL(ACT_SETUP_HRS,0)
                     ELSE 0 END
REM_RUN_HRS   = same pattern for RUN_HRS / ACT_RUN_HRS
REM_HRS       = REM_SETUP_HRS + REM_RUN_HRS
```

**Floored at zero.** A setup that has already exceeded standard shows `REM_SETUP_HRS = 0` — it doesn't "refund" capacity from elsewhere.

## Schedulable resources

```sql
WHERE sr.SCHEDULE_NORMALLY = 'Y'
  AND sr.TYPE IN ('W','C')             -- Work Center or Crew
  AND ISNULL(sr.STATUS,'') <> 'I'      -- exclude inactive
```

Indirect and Group types are filtered out (admin overhead, not production capacity).

## Weekly bucketing

Week starts Monday (derived from `@@DATEFIRST`):

```sql
DECLARE @WeekStart date =
    DATEADD(day,
            -((DATEPART(weekday, CAST(GETDATE() AS date)) + @@DATEFIRST - 2) % 7),
            CAST(GETDATE() AS date));

BUCKET_NO = CASE WHEN SCHED_START_DATE < @WeekStart THEN 0
                 ELSE DATEDIFF(week, @WeekStart, SCHED_START_DATE) END
```

- `BUCKET_NO = 0` → **past-due**, collapsed into current week so it doesn't disappear off the left edge
- `BUCKET_NO = 1..@Horizon` → future weeks (`@Horizon` default 13)
- `BUCKET_NO = -1` → synthetic horizon rollup row per resource

## Capacity model

```sql
HEADCOUNT            = SHIFT_1_CAPACITY + SHIFT_2_CAPACITY + SHIFT_3_CAPACITY
EFFICIENCY_FACTOR    = ISNULL(sr.EFFICIENCY_FACTOR, 100.0)
WEEKLY_CAPACITY_HRS  = HEADCOUNT * 8.0 /*hrs/shift*/ * 5.0 /*days*/ * EFFICIENCY_FACTOR / 100
```

**Hardcoded assumptions:**
- 8-hour shifts (`@ShiftHours = 8.0`)
- 5-day work weeks (`@WorkDays = 5.0`)
- **No holiday calendar** — capacity is uniform week to week
- **Capacity is global per resource, not per-site** — if sites staff differently, this is an approximation. Rollup rows use `SITE_ID = '_ANY_'`.

## Load calculation

```sql
REQUIRED_HRS = SUM(REM_HRS)                              -- grouped by (SITE_ID, RESOURCE_ID, BUCKET_NO)
LOAD_PCT     = 100.0 * REQUIRED_HRS / NULLIF(WEEKLY_CAPACITY_HRS, 0)
```

Load status (canonical tier thresholds):

```
LOAD_STATUS = CASE
    WHEN BUCKET_NO = 0 AND PAST_DUE_OPS > 0 THEN 'PAST DUE'
    WHEN HEADCOUNT = 0                      THEN 'NO CAPACITY DEFINED'
    WHEN REQUIRED_HRS = 0                   THEN 'IDLE'
    WHEN LOAD_PCT >= 130                    THEN 'CRITICAL'
    WHEN LOAD_PCT >= 100                    THEN 'OVERLOAD'
    WHEN LOAD_PCT >= 80                     THEN 'WATCH'
    ELSE                                         'OK'
END
```

## Files in this folder

| File | Purpose |
|---|---|
| `resource_capacity_load.sql` | Per-resource × week: required hrs, capacity, load %, status, past-due flag |

## Gotchas

- **Unscheduled ops are invisible.** `SCHED_START_DATE IS NULL` = dropped from the load. Chase master-scheduler hygiene separately.
- **Past-due collapses into bucket 0** — intentional, so overdue work surfaces instead of scrolling off the left.
- **No queue / move / inspect time.** `REM_HRS` is pure engineered setup + run. If reality needs a buffer, build it into the operation standard, not this query.
- **Setup-once, run-long WOs:** setup hours are consumed in whatever week they started; later weeks show run-only remaining. This is correct, not a bug.
- **Resource capacity is global.** Multi-site companies that staff differently per site are approximated. Adjust downstream if needed.
- **`EFFICIENCY_FACTOR = 0 or NULL`** — the `ISNULL(..., 100.0)` guard defaults to 100 %. Validate your SHOP_RESOURCE data.
- Sort by `BUCKET_NO` ascending (after the `-1` rollup appears at the top per resource).
