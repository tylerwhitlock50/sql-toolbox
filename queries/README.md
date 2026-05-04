# SQL Toolbox - Canonical Queries

This folder is the source of truth for production-ready queries.

## Folder Layout

- `domains/gl/` - General ledger and accounting queries
- `domains/sales/` - Sales reporting and customer-order analytics
- `domains/inventory/` - Inventory snapshots, planning info, fix scripts
- `domains/production/` - Work-order, labor, and shop-floor performance
- `domains/supply_chain/` - Material flow, planning, and supply-chain analysis
  - `bom/` - BOM and routing explosion queries
  - `demand/` - Unified demand views and BOM-exploded gross requirements
  - `planning/` - Time-phased net requirements, purchasing plan, build priority
  - `purchasing/` - Open/planned PO supply, price history, cost summaries
  - `performance/` - Vendor/buyer scorecards, lead-time, price volatility, shortages
  - `executive/` - CEO-level KPI snapshots and waste/stagnation reports
  - `E&O/` - Excess and obsolete inventory analysis
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
| Diagnostics | `domains/diagnostics/diagnose_single_invoice_exchange_failure.sql` | Single invoice Exchange failure deep dive (VECA -> VFIN) |
| Sales | `domains/sales/order_information/so_header_and_lines.sql` | Customer-order header + line detail |
| Sales | `domains/sales/order_information/so_header_and_lines_open_orders.sql` | Open customer orders only (canonical filter) |
| Sales | `domains/sales/order_information/so_fulfillment_risk.sql` | **Per SO line: blocking components + next supply that would unblock** |
| Sales | `domains/sales/performance/customer_otd_scorecard.sql` | Customer on-time delivery scorecard |
| Sales | `domains/sales/performance/customer_scorecard.sql` | Customer activity & performance |
| Sales | `domains/sales/performance/past_due_so_aging.sql` | Past-due SO aging buckets |
| Sales | `domains/sales/performance/salesrep_performance_scorecard.sql` | Sales rep scorecard |
| Sales | `domains/sales/performance/sales_trend_monthly.sql` | Monthly sales trend |
| Sales | `domains/sales/performance/demand_trend_monthly.sql` | **Per-part monthly velocity + T3/T6/T12 trend + Pareto ABC + seasonality** |
| Inventory | `domains/inventory/part_information/planning_information.sql` | Part-level planning snapshot (on-hand, demand, MRP exceptions) |
| Inventory | `domains/inventory/part_information/exceptions_report.sql` | Inventory exception analysis |
| Inventory | `domains/inventory/part_information/inventory_vs_part_location_qty_mismatch.sql` | Reconcile inventory vs part-location qty |
| Inventory | `domains/inventory/part_information/stocking_policy_recommendations.sql` | **Recommended SS + ROP from demand × LT variability vs current setting** |
| Production | `domains/production/performance/open_wo_list.sql` | **Full open-WO list (on-time + late) + WIP $ + priority** — feeds `reports/open_wo_list.rdl` |
| Production | `domains/production/performance/open_wo_aging_and_wip.sql` | Open WO aging + WIP $ (preserved for reference; same row-set as `open_wo_list.sql`) |
| Production | `domains/production/performance/wo_otd_and_cycle_time.sql` | WO on-time + cycle time |
| Production | `domains/production/performance/labor_productivity_scorecard.sql` | Labor productivity |
| Production | `domains/production/performance/operation_efficiency_by_resource.sql` | Resource utilization |
| Production | `domains/production/performance/schedule_health_by_operation.sql` | Operation schedule health |
| Production | `domains/production/performance/fg_completion_forecast.sql` | **Open WO finish-date forecast + SO peg + component readiness** |
| Scheduling | `domains/scheduling/resource_capacity_load.sql` | **Per-resource weekly load vs capacity + bottleneck flag** |
| Supply Chain | `domains/supply_chain/bom/recursive_bom_from_masters.sql` | Recursive BOM explosion (single top part) |
| Supply Chain | `domains/supply_chain/bom/recursive_bom_all_active_parts.sql` | Recursive BOM explosion (all active sales parts) |
| Supply Chain | `domains/supply_chain/bom/recursive_routing_from_masters.sql` | Recursive routing explosion (single top part) |
| Supply Chain | `domains/supply_chain/bom/recursive_routing_all_active_parts.sql` | Recursive routing explosion (all active parts) |
| Supply Chain | `domains/supply_chain/demand/total_demand_by_part.sql` | **Unified demand: SO backorder + master schedule + forecast** |
| Supply Chain | `domains/supply_chain/demand/exploded_gross_demand.sql` | **BOM-exploded component-level gross demand by source** |
| Supply Chain | `domains/supply_chain/planning/net_requirements_weekly.sql` | **Time-phased MRP grid (gross / receipts / projected / net)** |
| Supply Chain | `domains/supply_chain/planning/purchasing_plan.sql` | **Recommended POs: vendor, lead time, expected price** |
| Supply Chain | `domains/supply_chain/planning/build_priority_by_so.sql` | **Per-SO buildability + priority score (isolated)** |
| Supply Chain | `domains/supply_chain/planning/shared_buildable_allocation.sql` | **Per-SO buildable AFTER priority allocation across competing SOs** |
| Supply Chain | `domains/supply_chain/planning/purchasing_plan_by_buyer_summary.sql` | **Buyer × week roll-up: parts to order, $ to spend, past-due** |
| Supply Chain | `domains/supply_chain/planning/make_plan_weekly.sql` | **Fabrication plan: WO release date + qty + component readiness** |
| Supply Chain | `domains/supply_chain/planning/supplemental_supply.sql` | **Unified open-WO + open-PO supply + open WO requirements (signed) for snapshot netting** |
| Supply Chain | `domains/supply_chain/purchasing/open_po_list.sql` | **Full open PO list (past-due + not-due) incl. service POs + priority** — feeds `reports/open_po_list.rdl` |
| Supply Chain | `domains/supply_chain/purchasing/open_and_planned_supply_detail.sql` | Unified open PO + planned supply (UOM normalized) |
| Supply Chain | `domains/supply_chain/purchasing/open_purchase_orders_uom_normalized.sql` | Open POs with UOM conversion |
| Supply Chain | `domains/supply_chain/purchasing/part_cost_summary.sql` | Std vs weighted-avg vs last-PO cost |
| Supply Chain | `domains/supply_chain/purchasing/purchase_price_history_yearly.sql` | Yearly PO receipt price history |
| Supply Chain | `domains/supply_chain/performance/vendor_otd_scorecard.sql` | Vendor on-time delivery scorecard |
| Supply Chain | `domains/supply_chain/performance/vendor_lead_time_history.sql` | **Actual lead time stats per (vendor, part); ERP-vs-reality gap** |
| Supply Chain | `domains/supply_chain/performance/part_price_volatility.sql` | **Monthly price trend + MoM/YoY + trailing-12 volatility** |
| Supply Chain | `domains/supply_chain/performance/vendor_scorecard_360.sql` | **Consolidated vendor 360 (spend + OTD + LT + price + risk)** |
| Supply Chain | `domains/supply_chain/performance/commodity_spend_rollup.sql` | **Spend by commodity: top vendors, HHI concentration, inflation flags** |
| Supply Chain | `domains/supply_chain/performance/buyer_performance_scorecard.sql` | Buyer-level OTD, spend, quality |
| Supply Chain | `domains/supply_chain/performance/past_due_po_aging.sql` | Past-due PO aging only (preserved for reference; broader version is `../purchasing/open_po_list.sql`) |
| Supply Chain | `domains/supply_chain/performance/material_shortage_vs_open_demand.sql` | Component shortages tied to SO at risk |
| Supply Chain | `domains/supply_chain/performance/eo_forecast_coverage_months.sql` | E&O forecast coverage months |
| Supply Chain | `domains/supply_chain/E&O/historical_E&O_basis.sql` | Historical E&O cost basis |
| Supply Chain | `domains/supply_chain/executive/waste_and_stagnation.sql` | **Waste report: stagnant, excess, dead, orphan WO, early PO** |
| Supply Chain | `domains/supply_chain/executive/executive_supply_chain_kpis.sql` | **Per-site CEO KPI snapshot (backlog/WIP/inventory/OTD/turns)** |
| Supply Chain | `domains/supply_chain/executive/component_uniqueness.sql` | **Per component: how many active FGs use it (variant / family / platform)** |
| Supply Chain | `domains/supply_chain/executive/sku_complexity_scorecard.sql` | **Per SKU: T12 sales + batch/setup tax + variant-only inventory $** |
| Supply Chain | `domains/supply_chain/executive/product_line_cost_to_serve.sql` | **Per product line: SKU mix, setup overhead, variation inventory $** |

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
