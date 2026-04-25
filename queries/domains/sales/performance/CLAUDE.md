# CLAUDE.md — sales / performance

Rules for customer-facing performance scorecards, OTD, revenue, and demand trend (VECA).

## Scope

Scorecards and trend reports: customer OTD, sales rep performance, SO aging, monthly sales trend, per-part demand trend + ABC.

All of these **consume** the canonical open-SO definition from `../order_information/`. If you're writing a new query here, start by grabbing open SO lines with the filter below and layering on the performance lens.

## The open-order filter (repeat from order_information)

```sql
WHERE co.STATUS IN ('R','F')
  AND col.LINE_STATUS = 'A'
  AND col.ORDER_QTY - ISNULL(col.TOTAL_SHIPPED_QTY, 0) > 0
  AND col.PART_ID IS NOT NULL
```

## Canonical shipment join (SO → shipment)

OTD, revenue, and demand trend all live on the **shipment side**, not the order side. The join is deceptively tricky:

```sql
FROM CUSTOMER_ORDER co
INNER JOIN SHIPPER s
    ON co.ID = s.CUST_ORDER_ID
INNER JOIN SHIPPER_LINE sl
    ON sl.PACKLIST_ID = s.PACKLIST_ID
INNER JOIN CUST_ORDER_LINE col
    ON col.CUST_ORDER_ID = sl.CUST_ORDER_ID
   AND col.LINE_NO       = sl.CUST_ORDER_LINE_NO      -- BOTH keys, not just one
WHERE ISNULL(s.STATUS, '') NOT IN ('X', 'V')          -- exclude voided shipments
```

**Critical:** Join `SHIPPER_LINE` to `CUST_ORDER_LINE` on **both** `CUST_ORDER_ID` AND `LINE_NO`. Forgetting `LINE_NO` causes 1:N explosions when a line ships in multiple deliveries.

**Always** exclude voided shipments: `ISNULL(s.STATUS, '') NOT IN ('X', 'V')`.

## Shipped-quantity conventions

| Field | Use for |
|---|---|
| `SHIPPER_LINE.SHIPPED_QTY` | On-hand impact, inventory reconciliation |
| `SHIPPER_LINE.USER_SHIPPED_QTY` | Revenue & margin (post-adjustment) |
| `CUST_ORDER_LINE.TOTAL_SHIPPED_QTY` | Cumulative across all shipments on the line |

## Target ship date (OTD, aging)

Use the canonical coalesce — **all performance queries must agree on this**:

```sql
COALESCE(
    cld.DESIRED_SHIP_DATE,
    col.PROMISE_DATE,
    col.DESIRED_SHIP_DATE,
    co.PROMISE_DATE,
    co.DESIRED_SHIP_DATE
) AS target_ship_date
```

## OTD definitions

**Shipment-level on-time flag:**
```sql
days_late = DATEDIFF(day, target_ship_date, s.SHIPPED_DATE)
on_time   = CASE WHEN days_late <= @OnTimeToleranceDays THEN 1 ELSE 0 END
```
`@OnTimeToleranceDays` defaults to **0** (must ship on or before target). Parameterize if a customer has a negotiated grace window.

**Two OTD percentages (report both, they diverge):**
```sql
otd_pct_by_line    = 100.0 * SUM(on_time) / COUNT(*)
otd_pct_by_revenue = 100.0 * SUM(on_time * revenue) / SUM(revenue)
```
**Revenue-weighted is the primary commercial number** — a single big-ticket miss can tank service-tier even if line-OTD looks fine.

**Customer service tiers** (from `customer_otd_scorecard.sql`):
- A (Gold): OTD-by-rev ≥ 95 AND line-fill ≥ 98
- B (OK): OTD-by-rev ≥ 85
- C (Needs Improvement): OTD-by-rev ≥ 70
- D (At Risk): otherwise

These thresholds are **business policy** — confirm with sales leadership before changing.

## Revenue & margin

**Revenue (always subtract trade discount):**
```sql
revenue = qty * UNIT_PRICE * (100.0 - COALESCE(TRADE_DISC_PERCENT, 0)) / 100.0
```
Use `USER_SHIPPED_QTY` for qty when measuring shipped revenue (post-adjustment).

**Standard cost (from `PART_SITE_VIEW`):**
```sql
std_unit_cost = UNIT_MATERIAL_COST + UNIT_LABOR_COST + UNIT_BURDEN_COST + UNIT_SERVICE_COST
```
This is a **snapshot at query time**, not historical cost at ship date. For audit-grade cost, go to the GL.

**Standard margin:**
```sql
std_margin_pct = 100.0 * (revenue - qty * std_unit_cost) / NULLIF(revenue, 0)
```
`< 15%` triggers the "margin" attention flag in the rep scorecard.

**Revenue-weighted discount:**
```sql
SUM(TRADE_DISC_PERCENT * revenue) / NULLIF(SUM(revenue), 0)
```

## Bookings vs shipments — don't conflate

- **Bookings** = `CUSTOMER_ORDER.ORDER_DATE` in window (what the rep sold)
- **Shipments** = `SHIPPER.SHIPPED_DATE` in window (what actually left)

These are **different order flows**. A January booking may ship in March. Never sum both under one time axis.

**Book-to-bill ratio** (tracked monthly in `sales_trend_monthly.sql`):
```sql
book_to_bill = bookings_amount / NULLIF(shipped_revenue, 0)
-- > 1 : backlog building
-- < 1 : demand falling short of shipment capacity
```

## Demand trend (monthly per-part velocity)

Source in `demand_trend_monthly.sql` is `CUST_LINE_DEL.ACTUAL_SHIP_DATE` (shipment-based, not order-based) with `CUST_ORDER_LINE.UNIT_PRICE`.

**Trailing averages** (self-join on (part, site) over rolling 3/6/12-month windows — no `OVER()` frames for compat):
```sql
T3_AVG_QTY  = SUM(qty over last 3 months) / 3.0
T6_AVG_QTY  = SUM(qty over last 6 months) / 6.0
T12_AVG_QTY = SUM(qty over last 12 months) / 12.0
T12_STDDEV  = STDEV(monthly qty, last 12 months)
```

**Pareto ABC** (computed once per part at latest month, broadcast to all rows):
- A: cumulative T12_REVENUE ≤ 80 %
- B: next 15 % (80 – 95)
- C: bottom 5 %

**Trend flag** (T3 vs T6 velocity):
```
trend_pct = 100 * (T3_AVG_QTY - T6_AVG_QTY) / T6_AVG_QTY

< 3 months data       → 'TOO NEW'
T6 = 0                → 'EMERGING'
T3 = 0                → 'DYING'
trend > +25%          → 'GROWING FAST'
trend > +5%           → 'GROWING'
trend < -25%          → 'DECLINING FAST'
trend < -5%           → 'DECLINING'
else                  → 'STABLE'
```

**Lumpiness (demand CV):**
```sql
demand_cv_pct = 100.0 * T12_STDDEV / T12_AVG_QTY
-- > 75   → HIGH (LUMPY / seasonal / project-based)
-- 35–75  → MODERATE
-- < 35   → LOW (SMOOTH)
```

## Site filtering

```sql
WHERE (@Site IS NULL OR co.SITE_ID = @Site)
```
Same pattern as elsewhere. NULL = all sites.

## Files in this folder

| File | Purpose |
|---|---|
| `customer_otd_scorecard.sql` | Per-customer OTD %, fill rate, service tier. Revenue-weighted. |
| `customer_scorecard.sql` | Per-customer revenue, margin, orders, backlog, NEW/GROWING/DECLINING/CHURNED segment. |
| `salesrep_performance_scorecard.sql` | Per-rep bookings + shipments + margin + OTD, with attention flags. |
| `past_due_so_aging.sql` | Line-level SO aging with supply status and priority (P1–P4). |
| `sales_trend_monthly.sql` | Monthly bookings, shipments, margin, backlog snapshot, YoY, book-to-bill. |
| `demand_trend_monthly.sql` | Per-part monthly velocity + T3/T6/T12 + Pareto ABC + CV (lumpiness). |

## Gotchas

- **Historical backlog is approximated** in `sales_trend_monthly.sql` as `ordered_amount − shipped_before_EOM`. It does **not** adjust for cancellations that happened after the EOM. For audit-grade historical backlog, maintain a point-in-time snapshot table.
- **Standard cost is snapshot, not historical.** Margin trends reflect today's costs applied to historical shipments.
- **YoY comparisons** must align periods offset by 365 days — see `demand_trend_monthly.sql` and `sales_trend_monthly.sql` for the pattern.
- **Service-tier thresholds and margin flags (< 15%, < 80% OTD)** are business policy — don't change them without sign-off.
- **Revenue-weighted metrics everywhere.** Don't use unweighted line counts for commercial scorecards.
