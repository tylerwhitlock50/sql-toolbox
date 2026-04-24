# Supply Chain & Operations Reporting — Proposal

A proposed split of our new SQL toolbox into **Tableau dashboards** (for visibility, trends, decision support) and **SSRS reports** (for live operational lists people work *from*).

---

## 1. Why this matters

We've built ~30 production-grade queries that finally answer the business questions we couldn't before:

- *"Given our backorder + master schedule + forecast, what do we need to build and buy in what quantity?"*
- *"Of our open orders, which can ship today, and which are blocked by what?"*
- *"Where is cash stuck in the building — and what's drifting on price or lead time?"*
- *"How is the business actually performing this week?"*

But raw queries don't change behavior. The next step is **putting the right view in front of the right person at the right cadence**. That's a mix of:

- **Tableau** — interactive dashboards for analysis, comparison, and trend. Updated daily; consumed by leadership and planners *thinking* about the business.
- **SSRS** — printable, parameterized, subscribed reports. Updated live (or near-live); consumed by buyers, planners, schedulers, and CSRs *doing* the work.

Splitting these correctly means leadership gets a coherent story, and the operations team gets actionable lists they can work from instead of rebuilding views every morning.

---

## 2. The story we want to tell

The dashboards should walk the reader through the business as a funnel:

```
   Demand        →  BOM / Plan       →  Execution        →  Outcomes
   --------        ---------------     -----------         ----------
   Sales backlog   What to build      Build / buy         OTD %
   Master sched    What to buy        Vendor in/out       Inventory turns
   Forecast       Capacity load      Shop OEE            $ stuck (waste)
                                                          Backlog $
```

Five Tableau pages map to that funnel, plus a top-level CEO page that aggregates the headline numbers.

---

## 3. Tableau dashboard architecture

Six pages. Each is described as a one-page brief: audience, key questions, visuals, source queries, refresh cadence.

### Page 1 — Executive Scoreboard *(landing page)*

- **Audience**: CEO, COO, CFO. Weekly review.
- **Questions**: How are we doing? Where's the biggest dollar problem?
- **Visuals**:
  1. **KPI tiles** (top): Backlog $, Past-due Backlog $, WIP $, Inventory $, Inventory Turns (T12), Vendor OTD %, Customer OTD %, Stagnant Inventory $.
  2. **Trend sparkline strip**: 13-week history under each tile so the eye sees direction, not just level.
  3. **Site comparison bar chart** (when multi-site): each metric across sites + ALL_SITES rollup.
  4. **Top-10 issues table**: top items from `waste_and_stagnation` sorted by `DOLLAR_IMPACT` — clickable to drill into Page 5.
- **Source queries**:
  - `executive_supply_chain_kpis.sql` (one row per site + ALL_SITES rollup)
  - `waste_and_stagnation.sql`
- **Refresh**: nightly extract.

### Page 2 — Sales & Demand

- **Audience**: Sales leadership, demand planners, S&OP.
- **Questions**: What's selling? What's growing or dying? Which customers are we letting down?
- **Visuals**:
  1. **Revenue trend** by month (last 24m), filtered by site / product code / commodity.
  2. **Pareto chart** of T12 revenue per part (A/B/C zones shaded) — answers "where do we make our money?"
  3. **Trend table** sortable by `TREND_FLAG`: parts in `GROWING FAST` / `DECLINING FAST` / `EMERGING` / `DYING`.
  4. **Demand variability heatmap**: parts × month, color = `DEMAND_CV_PCT_T12` — surfaces which parts are stable vs lumpy (hard to forecast).
  5. **Customer OTD scorecard** (bar) — top 10 customers by revenue with on-time %.
  6. **Past-due backlog by customer** treemap.
- **Source queries**:
  - `demand_trend_monthly.sql`
  - `customer_otd_scorecard.sql`
  - `past_due_so_aging.sql`
  - `customer_scorecard.sql`
- **Refresh**: nightly. Master-schedule overlays once that data lands.

### Page 3 — Supply Chain & Vendors

- **Audience**: Purchasing manager, CFO (cost), sourcing strategy.
- **Questions**: Which vendors are reliable? Where is price drifting? Where do we have concentration risk?
- **Visuals**:
  1. **Vendor performance quadrant chart**: x = OTD %, y = lead-time CV %, bubble = $ spend, color = HEALTH (Red/Yellow/Green). Top-right and bottom-left are the obvious targets.
  2. **Commodity bubble chart**: x = HHI concentration, y = T3 spend, bubble = total spend, color = `SOURCING_FLAG`. Identifies "diversify" candidates and "negotiate" priorities.
  3. **Price volatility heatmap**: parts × month, color = MoM %Δ. Red bands surface inflating commodities.
  4. **Lead-time-vs-ERP scatter**: x = LT_VENDOR_PART (what ERP says), y = P50 actual. Diagonal = honest. Above diagonal = ERP optimistic. Click for part list.
  5. **Past-due PO aging** stacked bar by buyer.
- **Source queries**:
  - `vendor_scorecard_360.sql`
  - `vendor_lead_time_history.sql`
  - `commodity_spend_rollup.sql`
  - `part_price_volatility.sql`
  - `past_due_po_aging.sql`
- **Refresh**: nightly.

### Page 4 — Production & Capacity

- **Audience**: VP Ops, plant manager, scheduler.
- **Questions**: Where's the bottleneck? Will we ship the WOs we've got? What's WIP $ doing?
- **Visuals**:
  1. **Resource heatmap**: x = week, y = resource, color = LOAD_PCT (`OK` green, `WATCH` yellow, `OVERLOAD` orange, `CRITICAL` red, `PAST DUE` purple). Single biggest scheduling visual.
  2. **WIP trend** line: WIP $ over time, by site.
  3. **Open WO completion forecast** Gantt: WOs sorted by FORECAST_FINISH_DATE, color = COMPLETION_STATUS. "BLOCKED (COMPONENTS SHORT)" and "WILL MISS SO PROMISE" pop visually.
  4. **WO OTD trend** line: rolling 4-week OTD %.
  5. **Schedule-health by operation** stacked bar.
- **Source queries**:
  - `resource_capacity_load.sql`
  - `fg_completion_forecast.sql`
  - `open_wo_aging_and_wip.sql`
  - `wo_otd_and_cycle_time.sql`
  - `schedule_health_by_operation.sql`
- **Refresh**: nightly. Capacity heatmap could go to hourly if scheduling churns intra-day.

### Page 5 — Inventory & Working Capital

- **Audience**: CFO, materials manager, ops leadership.
- **Questions**: Where is cash stuck? What can we get rid of? Are our stocking policies right?
- **Visuals**:
  1. **Inventory $ waterfall**: Total → segmented by Active / Stagnant / Excess / Dead. Drives the conversation about freeing cash.
  2. **Waste treemap** by `CATEGORY` (sized by $) from `waste_and_stagnation`.
  3. **Months-of-supply distribution** histogram: how many parts have <1mo, 1–3, 3–6, 6–12, 12+? Draws attention to the long tail.
  4. **Stocking-policy delta** scatter: x = current SS, y = recommended SS, color = `POLICY_ACTION`. Off-diagonal points are the review list.
  5. **Inventory turns by ABC class** bar.
- **Source queries**:
  - `waste_and_stagnation.sql`
  - `stocking_policy_recommendations.sql`
  - `planning_information.sql`
  - `eo_forecast_coverage_months.sql`
  - `historical_E&O_basis.sql`
- **Refresh**: nightly.

### Page 6 — Backorder Triage *(operational support, exec-friendly)*

- **Audience**: COO, customer service leadership, S&OP weekly meeting.
- **Questions**: Of our backorder, what can we ship today? What's blocked? What's the $ at stake?
- **Visuals**:
  1. **Buildable bar**: open backorder $ split into "ship today" (FULLY BUILDABLE) / "partial" / "blocked". One number per category.
  2. **Top 25 SO lines** table: sorted by PRIORITY_SCORE, columns include CUSTOMER, $, BUILDABLE_PCT, TOP3_SHORT_COMPONENTS. The weekly fight list.
  3. **Component blocking heatmap**: top 25 components × # SO lines blocked by it × $ at risk. Drives expedite priorities.
  4. **Allocation delta**: side-by-side ISOLATED_BUILDABLE vs REALISTIC_BUILDABLE so we see how priority allocation changes the picture.
- **Source queries**:
  - `build_priority_by_so.sql`
  - `shared_buildable_allocation.sql`
  - `material_shortage_vs_open_demand.sql`
  - `so_fulfillment_risk.sql`
- **Refresh**: 2× daily (morning standup, end of day).

---

## 4. SSRS reports (operational, live)

These are the **lists people work from**. Tableau is for *thinking*; SSRS is for *doing*. Each is parameterized, subscribable, and printable.

| # | Report | Audience | Trigger / cadence | Source query |
|---|---|---|---|---|
| 1 | **Buyer's Weekly PO Action List** | Each buyer | Subscription, Monday 6 AM | `purchasing_plan.sql` (filtered by `BUYER_USER_ID`) |
| 2 | **Buyer Summary (one-pager)** | Buyer + manager | Subscription, Monday 6 AM | `purchasing_plan_by_buyer_summary.sql` |
| 3 | **Daily Production Release List** | Production planner | Subscription, daily 6 AM | `make_plan_weekly.sql` (filter `ACTION_STATUS IN ('RELEASE NOW', 'RELEASE NOW (PARTIAL)')`) |
| 4 | **Daily Build Priority Sheet** | Shop foreman, scheduling | Daily 6 AM, posted to floor | `shared_buildable_allocation.sql` |
| 5 | **SO Fulfillment Risk** | CSR / sales | On-demand by SO# or customer | `so_fulfillment_risk.sql` (parameter: customer / order ID) |
| 6 | **Past-Due PO Follow-up** | Buyer | Subscription, Monday 6 AM + Wed | `past_due_po_aging.sql` |
| 7 | **Past-Due SO List** | Customer service | Subscription, daily 6 AM | `past_due_so_aging.sql` |
| 8 | **Material Shortage Expedite List** | Buyer + planner | Subscription, daily 6 AM | `material_shortage_vs_open_demand.sql` |
| 9 | **Open WO Aging Sheet** | Plant manager | Subscription, daily 6 AM | `open_wo_aging_and_wip.sql` |
| 10 | **WO Completion Forecast** | CSR commitments | On-demand | `fg_completion_forecast.sql` |
| 11 | **Vendor OTD Scorecard** | Buyer reviews | Monthly subscription | `vendor_otd_scorecard.sql` |
| 12 | **Stocking-Policy Review Worksheet** | Materials manager | Quarterly review | `stocking_policy_recommendations.sql` (filter `POLICY_ACTION <> 'OK'`) |

### Design rules for the SSRS layer

- **Parameter-first.** Each report has explicit input parameters (`@Site`, `@Buyer`, `@AsOfDate`, etc.). No hardcoded values.
- **Hyperlink between reports.** A row in *SO Fulfillment Risk* should hyperlink to *Material Shortage Expedite* filtered to that part.
- **Print-friendly.** A buyer should be able to print their Monday list and check off items.
- **Subscription delivery.** Email PDF + Excel attachments to named distribution lists. No "go log into the BI tool" friction.
- **Latency target.** ≤ 60 s render at typical data volumes. If a query is too heavy live, materialize a nightly extract table.

---

## 5. Phased rollout

To not boil the ocean, a 3-phase delivery:

### Phase 1 — *Stop the bleeding* (weeks 1–4)
Operational SSRS reports for the buying / planning / CSR teams. Highest immediate value because it changes daily behavior.
- SSRS #1 Buyer Weekly PO Action List
- SSRS #2 Buyer Summary one-pager
- SSRS #4 Daily Build Priority
- SSRS #8 Material Shortage Expedite List
- Tableau Page 6 Backorder Triage (for the weekly S&OP meeting)

### Phase 2 — *Make it visible* (weeks 5–8)
Executive layer + supplier intelligence. Shifts leadership conversations from anecdotes to data.
- Tableau Page 1 Executive Scoreboard
- Tableau Page 3 Supply Chain & Vendors
- Tableau Page 5 Inventory & Working Capital
- SSRS #6 Past-Due PO Follow-up
- SSRS #11 Vendor OTD Scorecard

### Phase 3 — *Plan ahead* (weeks 9–14)
Demand planning, capacity, fab plan. Requires the master schedule / forecast load to be live to be fully useful.
- Tableau Page 2 Sales & Demand
- Tableau Page 4 Production & Capacity
- SSRS #3 Daily Production Release List
- SSRS #5 SO Fulfillment Risk (parameterized)
- SSRS #12 Stocking-Policy Review

---

## 6. Technical notes for the analyst

- **Data layer.** All Tableau views should connect to a **published Tableau data source** that wraps the SQL Server connection — not direct workbook connections. Lets us version the model and avoid every workbook hardcoding the same joins.
- **Materialize the heavy queries.** The BOM-explosion-driven queries (`exploded_gross_demand`, `net_requirements_weekly`, `purchasing_plan`, `build_priority_by_so`) are expensive to recompute on the fly. Recommend a nightly SQL Agent job that writes their output to staging tables (`rep_purchasing_plan`, `rep_build_priority`, etc.) which Tableau and SSRS both read. This keeps the canonical SQL in this repo as the source of truth and the staging tables as the warm cache.
- **Parameter conventions.** Every query already declares `@Site`, `@Horizon`, etc. at the top — keep those names consistent in SSRS so analysts moving between tools don't get tripped up.
- **Color conventions across pages.**
  - Status colors: GREEN ok / YELLOW watch / ORANGE / RED critical / PURPLE past-due. Use the same palette everywhere — never invent new ones per page.
  - Actions vs metrics: action flags are colored, metrics are gray scale. Eyes go to color first.
- **Multi-site handling.** Default Site filter to ALL but make it the most prominent control on every page. KPI page already emits an `_ALL_SITES_` rollup row; respect it.
- **Date conventions.** All trend visuals use the Monday-of-week bucket emitted by the queries. Don't have Tableau re-bucket — it'll desynchronize from the SSRS reports.

---

## 7. Ownership

| Role | Responsibility |
|---|---|
| Data analyst | Builds Tableau dashboards, owns staging-table refresh job. Quarterly review of dashboard usage telemetry. |
| Reporting / IT | Builds and subscribes the SSRS reports. Manages distribution lists. |
| Materials manager | Owns the buyer & planner SSRS subscriptions. Calls out missed actions. |
| Supply-chain manager | Owns Tableau Pages 3 + 5. Quarterly vendor / commodity review. |
| COO / S&OP lead | Owns Pages 1, 2, 4, 6. Drives weekly review meeting using Page 6 as the agenda. |

---

## 8. What this gets us

- **For the CEO**: one page that says how the business is doing in 30 seconds, with click-through into every category.
- **For each buyer**: one printable list every Monday with the orders they need to place this week, with vendor / price / past-due flags built in.
- **For the production planner**: a daily release list and a build priority sheet that answers *"what should we do next?"*
- **For sales / CSR**: a per-customer fulfillment risk view that explains exactly *why* an order is late and *when* it'll clear.
- **For sourcing**: a quarterly view of which commodities and vendors deserve negotiation or diversification.

Most importantly: **decisions stop happening from gut feel and email threads, and start happening from a shared, repeatable picture of the business.**
