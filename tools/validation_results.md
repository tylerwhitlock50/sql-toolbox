# Query Validation Results

Generated: 2026-05-04. Each canonical `.sql` under `queries/domains/` was
preprocessed by `tools/inline_params.py` (strip DECLARE block, inline default
param values) and run inside the `mcp-server` container via
`tools/validate_all.py`. Each PASS pulled at least 1 row.

Run budget: 60s/query. Queries that hit the timeout are listed under "Slow"
(unknown if correct; needs longer budget or optimization).

## Summary

| Status | Count |
|---|---|
| PASS | 37 |
| FAIL (real SQL error) | 5 |
| FAIL (timed out at 60s) | 10 |
| SKIP_MULTI (multi-statement, per user rule) | 5 |
| SKIP_FIX_SCRIPT (write script) | 6 |
| SKIP_EMPTY (file is 0 bytes) | 1 |
| **Total** | **64** (+ 6 fix_scripts) |

## PASS (37)

| Query | Time |
|---|---|
| `gl/chart_of_accounts.sql` | 0.0s |
| `gl/gl_balance_export.sql` | 0.0s |
| `gl/gl_posting_map.sql` | 0.3s |
| `gl/gl_posting_map_enriched.sql` | 0.0s |
| `gl/trial_balance.sql` | 0.1s |
| `inventory/part_information/exceptions_report.sql` | 0.0s |
| `inventory/part_information/planning_information.sql` | 18.3s |
| `inventory/part_information/stocking_policy_recommendations.sql` | 1.2s |
| `production/performance/fg_completion_forecast.sql` | 0.6s |
| `production/performance/labor_productivity_scorecard.sql` | 0.9s |
| `production/performance/open_wo_aging_and_wip.sql` | 0.2s |
| `production/performance/open_wo_list.sql` | 0.7s |
| `production/performance/operation_efficiency_by_resource.sql` | 1.1s |
| `production/performance/schedule_health_by_operation.sql` | 0.2s |
| `production/performance/wo_otd_and_cycle_time.sql` | 0.2s |
| `sales/active_parts_pricelist.sql` | 0.0s |
| `sales/order_information/so_fulfillment_risk.sql` | 13.5s |
| `sales/order_information/so_header_and_lines.sql` | 0.0s |
| `sales/order_information/so_header_and_lines_open_orders.sql` | 0.0s |
| `sales/performance/customer_otd_scorecard.sql` | 3.8s |
| `sales/performance/demand_trend_monthly.sql` | 0.1s |
| `sales/performance/past_due_so_aging.sql` | 0.3s |
| `sales/performance/salesrep_performance_scorecard.sql` | 2.3s |
| `scheduling/resource_capacity_load.sql` | 1.1s |
| `supply_chain/bom/recursive_bom_all_active_parts.sql` | 45.2s |
| `supply_chain/bom/recursive_bom_from_masters.sql` | 0.1s |
| `supply_chain/bom/recursive_routing_all_active_parts.sql` | 3.6s |
| `supply_chain/bom/recursive_routing_from_masters.sql` | 0.1s |
| `supply_chain/demand/total_demand_by_part.sql` | 0.2s |
| `supply_chain/performance/buyer_performance_scorecard.sql` | 0.8s |
| `supply_chain/performance/commodity_spend_rollup.sql` | 6.5s |
| `supply_chain/performance/eo_forecast_coverage_months.sql` | 4.8s |
| `supply_chain/performance/material_shortage_vs_open_demand.sql` | 1.9s |
| `supply_chain/performance/part_price_volatility.sql` | 35.4s |
| `supply_chain/performance/past_due_po_aging.sql` | 0.2s |
| `supply_chain/performance/vendor_lead_time_history.sql` | 0.3s |
| `supply_chain/performance/vendor_otd_scorecard.sql` | 0.3s |
| `supply_chain/planning/obsolete_check.sql` | 16.5s |
| `supply_chain/planning/obsolete_explainer.sql` | 14.4s |
| `supply_chain/planning/supplemental_supply.sql` | 0.0s |
| `supply_chain/purchasing/open_and_planned_supply_detail.sql` | 0.4s |
| `supply_chain/purchasing/open_po_list.sql` | 0.3s |
| `supply_chain/purchasing/open_purchase_orders_uom_normalized.sql` | 0.2s |
| `supply_chain/purchasing/part_cost_summary.sql` | 6.2s |
| `supply_chain/purchasing/purchase_price_history_yearly.sql` | 1.9s |

## FAIL — real SQL errors (5)

These are bona-fide query bugs that need fixing:

| Query | Error |
|---|---|
| `sales/performance/customer_scorecard.sql` | Arithmetic overflow converting numeric to numeric |
| `sales/performance/sales_trend_monthly.sql` | Cannot perform an aggregate function on an expression containing an aggregate or a subquery |
| `supply_chain/executive/executive_supply_chain_kpis.sql` | ORDER BY items must appear in the select list if the statement contains a UNION, INTERSECT or EXCEPT operator |
| `supply_chain/executive/waste_and_stagnation.sql` | No column name was specified for column 1 of 'excess' |
| `supply_chain/performance/vendor_scorecard_360.sql` | `INVENTORY_TRANS.TRANSACTION_DATE` not contained in aggregate function or GROUP BY |

## FAIL — timed out at 60s (10)

These are correctness-unknown — likely heavy planning queries that need a
longer budget (CLAUDE.md notes BOM-driven queries should be cached or
materialized for production):

| Query |
|---|
| `supply_chain/demand/exploded_gross_demand.sql` |
| `supply_chain/executive/component_uniqueness.sql` |
| `supply_chain/executive/product_line_cost_to_serve.sql` |
| `supply_chain/executive/sku_complexity_scorecard.sql` |
| `supply_chain/planning/build_priority_by_so.sql` |
| `supply_chain/planning/make_plan_weekly.sql` |
| `supply_chain/planning/net_requirements_weekly.sql` |
| `supply_chain/planning/purchasing_plan.sql` |
| `supply_chain/planning/purchasing_plan_by_buyer_summary.sql` |
| `supply_chain/planning/shared_buildable_allocation.sql` |

Most of these depend on `net_requirements_weekly.sql` (base MRP grid). Any
fix or optimization there cascades to the dependents.

## SKIP — multi-statement (5)

These contain 2+ top-level statements; they're diagnostic notebooks rather
than single queries. Per user rule, not run.

| Query | Statements |
|---|---|
| `diagnostics/diagnose_exchange_subscriptions.sql` | 28 |
| `diagnostics/diagnose_single_invoice_exchange_failure.sql` | 13 |
| `diagnostics/diagnose_veca_vfin_overlap.sql` | 7 |
| `gl/gl_posting_today.sql` | 3 |
| `supply_chain/E&O/historical_E&O_basis.sql` | 2 |

## SKIP — empty file (1)

| Query | Note |
|---|---|
| `inventory/part_information/inventory_vs_part_location_qty_mismatch.sql` | 0 bytes; canonical content missing |

## SKIP — fix_scripts (6)

Write scripts, intentionally not run:

- `inventory/fix_scripts/1-update_qty_on_hand.sql`
- `inventory/fix_scripts/1.5-Missing_location_parts.sql`
- `inventory/fix_scripts/2-match_requirement_status.sql`
- `inventory/fix_scripts/3-update_qty_in_demand.sql`
- `inventory/fix_scripts/find_missing_location_data.sql`
- `inventory/fix_scripts/find_missing_location_data_build_fixes.sql`
