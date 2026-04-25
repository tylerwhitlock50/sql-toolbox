# CLAUDE.md — supply_chain / planning

Rules for MRP-style netting, purchasing plan, make plan, and SO build prioritization (VECA).

## Scope

Queries here produce **action lists**: what to buy, what to release to the floor, which SOs to prioritize. All net demand against supply on a weekly time-phased grid.

Dependency chain:
1. `net_requirements_weekly.sql` → base MRP grid
2. `purchasing_plan.sql` and `make_plan_weekly.sql` → action lists per part
3. `purchasing_plan_by_buyer_summary.sql` → buyer-level roll-up
4. `build_priority_by_so.sql` and `shared_buildable_allocation.sql` → SO prioritization

## Core tables

| Table | Role |
|---|---|
| `PART_SITE_VIEW` | on-hand, SS, LT, planner, buyer, vendor, ABC, make/buy flags |
| `CUSTOMER_ORDER` / `CUST_ORDER_LINE` | open SO demand (canonical filter) |
| `MASTER_SCHEDULE` / `DEMAND_FORECAST` | MS + forecast demand |
| `PURCHASE_ORDER` / `PURC_ORDER_LINE` | open PO supply |
| `WORK_ORDER` + `REQUIREMENT` | open WO supply (TYPE='W'); BOM walk via TYPE='M' |
| `PLANNED_ORDER` | optional Visual MRP output (if present) |
| `VENDOR_PART` | preferred vendor + `LEADTIME_BUFFER` |
| `INVENTORY_TRANS` | receipt history for actual lead-time P50 and weighted-avg cost |

## The weekly bucketing convention

Monday-anchored:
```sql
DECLARE @WeekStart date =
    DATEADD(day,
            -((DATEPART(weekday, CAST(GETDATE() AS date)) + @@DATEFIRST - 2) % 7),
            CAST(GETDATE() AS date));

-- Past-due demand/supply collapses to BUCKET_NO = 0
BUCKET_NO = CASE WHEN event_date < @WeekStart THEN 0
                 ELSE DATEDIFF(week, @WeekStart, event_date) END
```

**Past-due rule: always collapse to bucket 0** so overdue work stays visible.

`@Horizon` defaults to 26 weeks (or 12 in the buyer summary). `@MaxDepth` caps BOM recursion at 20.

## Canonical demand and supply filters

Demand (same shape as `../demand/`):
- **SO:** `CO.STATUS IN ('R','F') AND COL.LINE_STATUS='A' AND ORDER_QTY > TOTAL_SHIPPED_QTY`
- **MS firm:** `MASTER_SCHEDULE.FIRMED='Y' AND ORDER_QTY > 0`
- **MS forecast:** `FIRMED='N'`
- **Forecast:** `DEMAND_FORECAST.REQUIRED_QTY > 0`

Supply:
- **Open PO:** status NOT IN ('X','C'); `ORDER_QTY > TOTAL_RECEIVED_QTY`
  - Date: `COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE)`
- **Open WO:** `TYPE='W'` AND status NOT IN ('X','C'); `DESIRED_QTY > RECEIVED_QTY`
  - Date: `COALESCE(SCHED_FINISH_DATE, DESIRED_WANT_DATE)`
- **Planned orders:** `PLANNED_ORDER.ORDER_QTY > 0` (optional)

## net_requirements_weekly.sql — the base grid

One row per `(SITE_ID, PART_ID, BUCKET_NO)`.

**Projected on-hand (carry-forward self-join):**
```sql
PROJECTED_ON_HAND
    = ISNULL(psv.QTY_ON_HAND, 0)
    + SUM(NET_CHANGE over buckets 0..g1.BUCKET_NO)

NET_CHANGE = (open_po_qty + open_wo_qty + planned_order_qty) - gross_req
```

**Net requirement:**
```sql
NET_REQUIREMENT = CASE
    WHEN PROJECTED_ON_HAND < SAFETY_STOCK_QTY
    THEN SAFETY_STOCK_QTY - PROJECTED_ON_HAND
    ELSE 0
END

STATUS_FLAG = CASE
    WHEN PROJECTED_ON_HAND < 0                    THEN 'SHORTAGE'
    WHEN PROJECTED_ON_HAND < SAFETY_STOCK_QTY     THEN 'BELOW_SAFETY'
    ELSE                                               'OK'
END
```

## purchasing_plan.sql — the buy list

Filter: `PURCHASED='Y' AND FABRICATED <> 'Y' AND NET_REQUIREMENT > 0`.

**Lead time (worst case of three sources):**
```sql
EFFECTIVE_LT_DAYS = GREATEST(
    LT_ERP_PART,            -- PART_SITE_VIEW.PLANNING_LEADTIME
    LT_VENDOR_PART,         -- VENDOR_PART.LEADTIME_BUFFER (for preferred vendor)
    LT_ACTUAL_P50           -- median of actual receipts last 12 months
)
RECOMMENDED_ORDER_DATE = BUCKET_START - EFFECTIVE_LT_DAYS
```

**Order-qty rounding (precedence matters):**
```sql
CASE
    WHEN FOQ > 0                       -- fixed-order quantity wins
        THEN FOQ * CEILING(NET_REQUIREMENT / FOQ)
    WHEN MULT > 0 AND MOQ > 0          -- multiple + min
        THEN CASE WHEN NET_REQUIREMENT < MOQ THEN MOQ
                  ELSE MULT * CEILING(NET_REQUIREMENT / MULT)
             END
    WHEN MULT > 0                      -- multiple only
        THEN MULT * CEILING(NET_REQUIREMENT / MULT)
    WHEN MOQ > 0 AND NET_REQUIREMENT < MOQ
        THEN MOQ
    ELSE NET_REQUIREMENT               -- no lot-size rules
END
```

**Vendor:** default to `PART_SITE_VIEW.PREF_VENDOR_ID`. If NULL → `action_status = 'NO PREFERRED VENDOR'`.

**Expected unit cost:**
- Primary: recent weighted average from `INVENTORY_TRANS` receipts in last `@PriceLookbackMonths` (default 6)
- Fallback: `PART_SITE_VIEW.UNIT_MATERIAL_COST`

Action flags: `'ORDER NOW (PAST DUE)'`, `'NO PREFERRED VENDOR'`, `'PLAN ORDER'`, `'OK'`.

## make_plan_weekly.sql — the release list

Filter: `FABRICATED='Y' AND ENGINEERING_MSTR IS NOT NULL AND NET_REQUIREMENT > 0`.

```sql
RECOMMENDED_RELEASE_DATE = BUCKET_START - PLANNING_LEADTIME
```

Same rounding as purchasing plan.

**Level-1 component readiness** (one BOM step down — NOT recursive):
```sql
MIN_BUILDS_FROM_L1_COMPONENTS = MIN(comp_on_hand / qty_per) for each L1 component
```

Action flags:
- `'RELEASE NOW'` if due and `MIN_BUILDS >= NET_REQ`
- `'RELEASE NOW (PARTIAL)'` if due but `MIN_BUILDS < NET_REQ` (partial possible)
- `'RELEASE NOW (BLOCKED)'` if due and `MIN_BUILDS = 0`
- `'BLOCKED'` / `'FUTURE RELEASE'` / `'OK'`

**Only checks L1 components.** Sub-assemblies need their own row (they'll appear separately with their own net requirement + readiness).

## build_priority_by_so.sql — isolated buildability

One row per open SO line. Each line sees the **full component pool** (no competition):

```sql
UNITS_THIS_COMPONENT_SUPPORTS = COMPONENT_ON_HAND / QTY_PER_ASSEMBLY
ISOLATED_BUILDABLE = MIN(UNITS_THIS_COMPONENT_SUPPORTS) across all components
```

Capped at `OPEN_QTY`.

**Priority score (composite):**
```sql
PRIORITY_SCORE =
    CASE WHEN NEED_DATE < today
         THEN DATEDIFF(day, NEED_DATE, today)   -- past-due multiplier
         ELSE 1.0 / NULLIF(DATEDIFF(day, today, NEED_DATE), 0)  -- future divisor
    END
  * LINE_OPEN_VALUE
  * (1 + BUILDABLE_RATIO)
```

Top-3 short components: CSV via `STUFF(... FOR XML PATH)`.

## shared_buildable_allocation.sql — realistic buildability

Same grain as build_priority, but accounts for priority-based component consumption. Two SOs needing the same part don't both get to have it.

**Algorithm:**
1. Rank SO lines globally by simplified priority score (no buildable factor — avoid circularity)
2. Per (component, line), compute cumulative demand from higher-priority lines
3. Allocate to this line: `MIN(remaining_on_hand_for_me, this_line_demand)`
4. Per-line realistic buildable = `MIN(allocated_qty / qty_per_assembly)` across components

Output adds:
- `REALISTIC_BUILDABLE` (lower bound, credible)
- `COMPETITION_LOSS_QTY = ISOLATED - REALISTIC`
- `ALLOCATION_STATUS` flags: `'FULLY BUILDABLE (PRIORITY-ALLOC)'`, `'PARTIAL'`, `'BLOCKED BY HIGHER-PRIORITY SO'`

**When to use which:**
- `build_priority_by_so` for **prioritization decisions** — how should we sequence?
- `shared_buildable_allocation` for **customer commitments** — what can we actually promise?

## purchasing_plan_by_buyer_summary.sql — buyer standup

Per `(SITE_ID, BUYER_USER_ID, BUCKET_NO)` plus `BUCKET_NO = -1` total:

- `PARTS_TO_ORDER`, `PARTS_PAST_DUE`, `PARTS_NO_VENDOR`
- `TOTAL_QTY`, `TOTAL_VALUE_AT_STD`, `PAST_DUE_VALUE_AT_STD`
- Top-5 parts CSV ranked by `TOTAL_VALUE_AT_STD`

Bucket flags: `'PAST DUE ACTION'`, `'SOURCING NEEDED'`, `'HEAVY WEEK'` (if > 10 parts), `'OK'`.

**Simpler than `purchasing_plan.sql`:** uses `PLANNING_LEADTIME` only (not 3-source effective LT) and raw `NET_REQUIREMENT` (no MOQ/multiple rounding).

## Parameter conventions

```sql
DECLARE @Site              nvarchar(15) = NULL;   -- NULL = all sites
DECLARE @Horizon           int          = 26;     -- weeks
DECLARE @MaxDepth          int          = 20;     -- BOM recursion cap
DECLARE @AsOfDate          datetime     = GETDATE();
DECLARE @PriceLookbackMonths int        = 6;
```

Pattern: `WHERE (@Site IS NULL OR psv.SITE_ID = @Site)` — NULL means all.

## Files in this folder

| File | Purpose |
|---|---|
| `net_requirements_weekly.sql` | Base MRP grid: gross / receipts / projected / net |
| `purchasing_plan.sql` | Recommended POs: vendor, LT, expected price, qty-rounding |
| `make_plan_weekly.sql` | WO release date + qty + L1 component readiness |
| `purchasing_plan_by_buyer_summary.sql` | Buyer × week roll-up of purchasing plan |
| `build_priority_by_so.sql` | Per-SO isolated buildability + priority score |
| `shared_buildable_allocation.sql` | Per-SO realistic buildability after priority-based allocation |

## Gotchas

- **Parts with zero safety stock** never appear in the plan — net req stays 0. Feature, not bug, but be aware.
- **No preferred vendor** → purchasing plan flags but doesn't fail. Buyer must source manually.
- **Lot-size rounding precedence:** FOQ > MULT+MOQ > MULT > MOQ. Don't reorder.
- **UOM mismatches:** open PO qty is in purchase UOM; `PART_SITE_VIEW.QTY_ON_HAND` is stock UOM. These queries assume they're equal. For actual UOM-normalized PO supply, see `../purchasing/open_purchase_orders_uom_normalized.sql`.
- **Phantom parts** (`DETAIL_ONLY='Y'`) flagged `MAKE_OR_BUY='PHANTOM'` in net_requirements; excluded from make_plan (which filters on `ENGINEERING_MSTR IS NOT NULL`).
- **Subcontract ops** — a fabricated WO (TYPE='W') can be outsourced; treated as inbound supply like PO. No special handling.
- **No Visual MRP dependency.** Queries compute netting from raw demand + supply. `PLANNED_ORDER` is optional.
- **Build priority is isolated** (full on-hand assumption). For realistic commitments use `shared_buildable_allocation`. Don't promise ship dates based on `ISOLATED_BUILDABLE`.
- **Allocation ranking in shared_buildable** uses a **simplified** priority score (no buildable factor — the full score would be circular). Watch for edge cases where lines with identical priority tie-break differently between runs.
- **L1 component check in make_plan is one-step-deep.** Sub-assembly shortages one level further down won't be flagged here — they'll show up as their own row in make_plan.
- **BOM recursion:** always keep the `CHARINDEX` cycle guard. Circular BOMs crash without it.
