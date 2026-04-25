# CLAUDE.md — production / performance

Rules for work-order, operation, labor, and resource-efficiency queries (VECA).

## Scope

Queries here answer: *"What's open on the floor?"* / *"Did we hit the want date?"* / *"How productive is this resource / employee?"* / *"When will this WO finish?"*

## The 5-part WO composite key

**Work orders in VISUAL are identified by five columns, not one.** Every join involving a WO must include all five:

```sql
FROM WORK_ORDER wo
INNER JOIN OPERATION o
    ON o.WORKORDER_TYPE     = wo.TYPE
   AND o.WORKORDER_BASE_ID  = wo.BASE_ID
   AND o.WORKORDER_LOT_ID   = wo.LOT_ID
   AND o.WORKORDER_SPLIT_ID = wo.SPLIT_ID
   AND o.WORKORDER_SUB_ID   = wo.SUB_ID
```

Shortcutting to `BASE_ID` alone silently collides reworked / split lots.

**Key semantics:**
- `TYPE` — `W` = standard production WO; `M` = engineering master (BOM / routing template, not a live job)
- `BASE_ID` — normally the FG part being built
- `LOT_ID` — lot number; for masters this matches `PART_SITE_VIEW.ENGINEERING_MSTR`
- `SPLIT_ID` — `'0'` primary, `'001'+` lot splits
- `SUB_ID` — `'0'` original, `'001'+` rework / restart

## Core tables & grain

| Table | Grain | Notes |
|---|---|---|
| `WORK_ORDER` | 5-part key + `SITE_ID` | Header: dates, qty, status, cost rollups |
| `OPERATION` | 5-part key + `SEQUENCE_NO` | Routing steps; `SETUP_HRS`, `RUN_HRS`, `MOVE_HRS` engineered; `ACT_*` actuals; `SCHED_START_DATE`, `SCHED_FINISH_DATE` |
| `REQUIREMENT` | 5-part key + `OPERATION_SEQ_NO` + `PIECE_NO` | Material requirements per op; `STATUS='U'` = unissued / live |
| `LABOR_TICKET` | 5-part key + `OPERATION_SEQ_NO` + `EMPLOYEE_ID` + `TRANSACTION_DATE` | Direct labor; `HOURS_WORKED`, `GOOD_QTY`, `BAD_QTY`, `INDIRECT_CODE` |
| `PART_SITE_VIEW` | (SITE_ID, PART_ID) | Standard cost components for WIP valuation |
| `SHOP_RESOURCE` | `RESOURCE_ID` | Work center; capacity, efficiency, shift definitions |
| `CUST_ORDER_LINE` / `CUSTOMER_ORDER` | SO line | Used for SO peg (direct PART_ID match, top-level FG only) |

## Open WO filter (canonical)

```sql
WHERE wo.STATUS IN ('F','R')                      -- Firmed or Released
  AND wo.TYPE    <> 'M'                           -- exclude engineering masters
  AND (@Site IS NULL OR wo.SITE_ID = @Site)
```

**Status codes:**
- `U` Unreleased · `F` Firmed · `R` Released · `C` Closed · `X` Cancelled

**Don't** filter by `CLOSE_DATE IS NULL`. A WO is "open" iff `STATUS IN ('F','R')`.

For closed-WO analysis (OTD, cycle time): `STATUS='C' AND CLOSE_DATE IS NOT NULL`.

## WIP valuation (open_wo_aging_and_wip.sql)

```sql
wip_value_approx = (ACT_MATERIAL_COST + ACT_LABOR_COST + ACT_BURDEN_COST + ACT_SERVICE_COST)
                 - (RECEIVED_QTY * std_unit_cost)

std_unit_cost   = PART_SITE_VIEW.UNIT_MATERIAL_COST + UNIT_LABOR_COST + UNIT_BURDEN_COST + UNIT_SERVICE_COST
```

- Uses **actual costs**, subtracts already-received portion at standard.
- **Can go negative** on yield-favorable WOs (more good parts than standard allowed). That's a signal, not a bug.
- **Not a ledger WIP.** Operational view only. For audit WIP, use the `WIP_BALANCE` table (not currently queried here).

Other cost views on `WORK_ORDER`:
- `REM_*_COST` — VISUAL's forward estimate of cost still to post
- `EST_*_COST` — original estimate at WO creation

## WO OTD (wo_otd_and_cycle_time.sql)

```sql
on_time_flag = CASE
    WHEN DESIRED_WANT_DATE IS NULL          THEN NULL
    WHEN CLOSE_DATE <= DESIRED_WANT_DATE    THEN 1
    ELSE                                         0
END

days_late = DATEDIFF(day, DESIRED_WANT_DATE, CLOSE_DATE)  -- negative = early
```

- **WO-level only** — does NOT walk SO pegging. Cross-check with sales OTD if you need customer-facing on-time.
- Cycle time: `DATEDIFF(day, DESIRED_RLS_DATE, CLOSE_DATE)` or `DATEDIFF(day, CREATE_DATE, CLOSE_DATE)`.

Aging buckets: `0-7`, `8-14`, `15-30`, `31-60`, `61+`, plus `NOT_DUE` and `NO_TARGET`.

## Labor productivity (labor_productivity_scorecard.sql)

Grain: `(SITE_ID, DEPARTMENT_ID, EMPLOYEE_ID)` over trailing 90 days (`@FromDate` / `@ToDate`).

Source: `LABOR_TICKET` joined to `OPERATION` on 5-part key + `OPERATION_SEQ_NO`.

```sql
clock_hours    = SUM(HOURS_WORKED)
direct_hours   = SUM(HOURS_WORKED) WHERE ISNULL(INDIRECT_CODE,'N') = 'N'
indirect_hours = SUM(HOURS_WORKED) WHERE INDIRECT_CODE = 'Y'

-- Earned hours ≈ prorated standard for qty completed (approximate)
earned_hours   = SUM(GOOD_QTY * (SETUP_HRS + RUN_HRS) / NULLIF(LOAD_SIZE_QTY, 0))

productivity_pct = 100.0 * earned_hours / NULLIF(direct_hours, 0)
rework_pct       = 100.0 * SUM(BAD_QTY) / (SUM(GOOD_QTY) + SUM(BAD_QTY))
```

**Attention flags:**
- `rework_pct > 5%`
- `direct_pct < 60%` (too much indirect)
- `productivity_pct < 60%`

**Caveat:** earned hours are **approximate** (prorated by `GOOD_QTY / LOAD_SIZE_QTY`). Good for trend, **not for payroll**.

## Resource efficiency (operation_efficiency_by_resource.sql)

Grain: `(SITE_ID, RESOURCE_ID)` over trailing 90 days on `OPERATION.CLOSE_DATE`. **Closed operations only** (`op.STATUS='C'`).

```sql
standard_hours_earned = SUM(SETUP_HRS + RUN_HRS)
actual_hours_spent    = SUM(ACT_SETUP_HRS + ACT_RUN_HRS)
efficiency_pct        = 100.0 * standard_hours_earned / NULLIF(actual_hours_spent, 0)
```

100 % = on standard. > 100 % = faster than standard.

Tiers:
- `A - at/ahead of std` ≥ 95 %
- `B - slightly behind` ≥ 80 %
- `C - behind` ≥ 60 %
- `D - chronically behind` < 60 %

Independent track: clock hours (direct labor only) and rework % from `LABOR_TICKET` on the same closed ops.

## Schedule health (schedule_health_by_operation.sql)

Grain: one row per open operation on an open WO.

```sql
rem_std_hrs = CASE WHEN SETUP_HRS + RUN_HRS > ACT_SETUP_HRS + ACT_RUN_HRS
                   THEN (SETUP_HRS + RUN_HRS) - (ACT_SETUP_HRS + ACT_RUN_HRS)
                   ELSE 0 END

op_schedule_status = CASE
    WHEN SCHED_FINISH_DATE IS NULL                                         THEN 'UNSCHEDULED'
    WHEN SCHED_FINISH_DATE < @AsOfDate AND COMPLETED_QTY < DESIRED_QTY     THEN 'PAST_DUE'
    WHEN SCHED_FINISH_DATE <= DATEADD(day, 3, @AsOfDate)
         AND SETUP_COMPLETED = 'N'                                         THEN 'STARTING_SOON'
    WHEN SCHED_FINISH_DATE <= DATEADD(day, 7, @AsOfDate)                   THEN 'DUE_THIS_WEEK'
    ELSE                                                                        'ON_SCHEDULE'
END

load_vs_calendar = CASE
    WHEN DESIRED_WANT_DATE < @AsOfDate                                     THEN 'WO_ALREADY_LATE'
    WHEN rem_std_hrs <= DATEDIFF(day, @AsOfDate, DESIRED_WANT_DATE) * 8    THEN 'FEASIBLE'
    ELSE                                                                        'AT_RISK_OVERCAPACITY'
END
```

Feasibility assumes **single shift, 8 hrs/day**. No multi-shift or multi-resource calc here — that lives in `../../scheduling/`.

## FG completion forecast (fg_completion_forecast.sql)

Produces a projected finish date per open WO. Three signals, take max:

1. **ERP scheduled finish:** `MAX(OPERATION.SCHED_FINISH_DATE)`
2. **Naive labor projection:** `today + CEILING(rem_labor_hrs / 8.0)` (single-shift assumption)
3. **Component-readiness gate:** if any `REQUIREMENT.STATUS='U'` has `(CALC_QTY - ISSUED_QTY) > PART_SITE_VIEW.QTY_ON_HAND`, **add 7 days** and flag `BLOCKED (COMPONENTS SHORT)`

SO peg is **direct `PART_ID` match** — top-level FG only, does not walk BOM upward.

Completion-status flags: `BLOCKED (COMPONENTS SHORT)`, `PAST SCHEDULED FINISH`, `OPS COMPLETE - PENDING RECEIPT`, `WILL MISS SO PROMISE`, `ON TRACK`.

## Aging & priority (open_wo_aging_and_wip.sql)

Buckets past `DESIRED_WANT_DATE` vs `@AsOfDate`: `0-7`, `8-14`, `15-30`, `31-60`, `61+`, plus `NOT_DUE`, `NO_TARGET`.

Priority:
```
P1 - late, SO demand  : DESIRED_WANT_DATE < today AND linked_so_value > 0
P2 - late             : DESIRED_WANT_DATE < today
P3 - SO demand        : linked_so_value > 0
P4 - normal           : else
```

## Site & date parameters

```sql
DECLARE @Site      nvarchar(15) = NULL;                      -- NULL = all sites
DECLARE @AsOfDate  datetime     = GETDATE();                 -- "now"
DECLARE @FromDate  datetime     = DATEADD(day, -90, GETDATE());
DECLARE @ToDate    datetime     = GETDATE();
```

No time-zone handling. Assume SQL Server local time throughout.

## Files in this folder

| File | Purpose |
|---|---|
| `open_wo_aging_and_wip.sql` | Open WO aging buckets + WIP $ + priority flag |
| `wo_otd_and_cycle_time.sql` | WO-level OTD + cycle-time (release→close, create→close) |
| `labor_productivity_scorecard.sql` | Employee productivity (earned vs direct hours, rework %) |
| `operation_efficiency_by_resource.sql` | Per-resource efficiency on closed ops |
| `schedule_health_by_operation.sql` | Open operations: on-schedule / past-due / at-risk flags |
| `fg_completion_forecast.sql` | Projected WO finish date + SO peg + component readiness |

## Gotchas

- **Rework (`SUB_ID`) and split lots (`SPLIT_ID`)** — always include both in composite joins. A reworked WO (`SUB_ID='001'`) is a **separate** WO from the original.
- **Engineering masters (`TYPE='M'`)** are templates, not production. Always exclude with `TYPE <> 'M'` or `TYPE='W'`.
- **Earned-hours numbers are approximate.** Prorated by `GOOD_QTY / LOAD_SIZE_QTY` (or `COMPLETED_QTY`). Good for scorecards and trends; **not payroll-grade**.
- **WIP $ can be negative** on yield-favorable WOs. Don't "fix" it — it's informative.
- **Operations running past standard with `rem_std_hrs = 0`** remain open until manually closed — they represent active overruns, not zero work.
- **SO peg is PART_ID match only** in these queries. For true BOM-upward pegging (sub-assembly on an SO), see `../../sales/order_information/so_fulfillment_risk.sql`.
- **`LABOR_TICKET.INDIRECT_CODE`** defaults to `'N'` (direct) when NULL — `ISNULL(INDIRECT_CODE, 'N')` is the standard guard.
- **`LABOR_TRAN`** (GL posting) is NOT used here. Scorecards live on `LABOR_TICKET`.
