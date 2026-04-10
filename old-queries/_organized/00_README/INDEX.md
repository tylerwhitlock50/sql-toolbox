# Old queries catalog (auto-generated)

This index is generated from `old-queries/_analysis/inventory.csv` and provides a starting point for cleanup.

Legend: **KEEP** (good candidate to keep), **REVIEW** (needs human decision), **REVIEW (writes)** (do not run without careful review).

## KEEP (likely useful) / accounting_vfin

- `old-queries/Queries/Trial Balance for 2021.sql` -> `old-queries/_organized/60_accounting_vfin/Queries__Trial Balance for 2021.sql` — dbs=VFIN; tables=VFIN.dbo.LEDGER_ACCOUNT,VFIN.dbo.LEDGER_ACCOUNT_BALANCE

## KEEP (likely useful) / admin_dba

- `old-queries/it queries/Admin-Lookup Space usage by DB.sql` -> `old-queries/_organized/70_admin_dba/it queries__Admin-Lookup Space usage by DB.sql` — tables=SYS.DATABASE_FILES,SYS.MASTER_FILES

## KEEP (likely useful) / labor_timecards

- `old-queries/Queries/Labor By Day Estimated.sql` -> `old-queries/_organized/50_labor_time/Queries__Labor By Day Estimated.sql` — tables=vta.dbo.labor_time_entry,vta.dbo.labor_time_card,VTA].[dbo].[LABOR_EMPLOYEE_DEPARTMENT,dbo].[LABOR_EMPLOYEE_PAY_RATE
- `old-queries/it queries/Costing Utilities - Labor Ticket Check.sql` -> `old-queries/_organized/50_labor_time/it queries__Costing Utilities - Labor Ticket Check.sql` — dbs=VECA; tables=LABOR_TICKET,OPERATION
- `old-queries/it queries/Get Labor Time Clocks.sql` -> `old-queries/_organized/50_labor_time/it queries__Get Labor Time Clocks.sql` — tables=VTA.dbo.LABOR_TIME_ENTRY,VTA.dbo.LABOR_TIME_ENTRY_BREAK,labor_time_card,labor_employee…
- `old-queries/it queries/Get Labor Timecard Information.sql` -> `old-queries/_organized/50_labor_time/it queries__Get Labor Timecard Information.sql` — tables=VTA.dbo.LABOR_EMPLOYEE,VTA.dbo.LABOR_TIME_CARD,VTA.dbo.LABOR_TIME_ENTRY,vta.dbo.labor_employee_pay_rate…
- `old-queries/it queries/Lookup VTA Timecards.sql` -> `old-queries/_organized/50_labor_time/it queries__Lookup VTA Timecards.sql` — tables=VTA].[dbo].[LABOR_TIME_ENTRY,LABOR_TIME_CARD,labor_employee,labor_time_entry

## KEEP (likely useful) / other

- `old-queries/Queries/ATS Report.sql` -> `old-queries/_organized/90_misc/Queries__ATS Report.sql` — dbs=VECA; tables=VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUSTOMER_ORDER,VECA.dbo.CUSTOMER_ENTITY,VECA.dbo.PART_LOCATION
- `old-queries/Queries/Open Order Mailings/SQL/Mailing Customer IDs.sql` -> `old-queries/_organized/90_misc/Queries__Open Order Mailings__SQL__Mailing Customer IDs.sql` — dbs=VECA; tables=VECA.dbo.CUST_CONT_EML_DOC
- `old-queries/Queries/Open Order Mailings/SQL/Open Order Report for Mailings.sql` -> `old-queries/_organized/90_misc/Queries__Open Order Mailings__SQL__Open Order Report for Mailings.sql` — dbs=VECA; tables=VECA.dbo.CUSTOMER_ORDER,VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUST_LINE_DEL
- `old-queries/Queries/Open Order Report for Mailings.sql` -> `old-queries/_organized/90_misc/Queries__Open Order Report for Mailings.sql` — dbs=VECA; tables=VECA.dbo.CUSTOMER_ORDER,VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUST_LINE_DEL
- `old-queries/Queries/Open Orders 2022.03.31.sql` -> `old-queries/_organized/90_misc/Queries__Open Orders 2022.03.31.sql` — dbs=VECA; tables=VECA.dbo.CUSTOMER_ORDER,VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUST_LINE_DEL
- `old-queries/Queries/Open Orders.sql` -> `old-queries/_organized/90_misc/Queries__Open Orders.sql` — dbs=VECA; tables=VECA.dbo.CUSTOMER_ORDER,VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUST_LINE_DEL
- `old-queries/it queries/Customer notes lookup query.sql` -> `old-queries/_organized/90_misc/it queries__Customer notes lookup query.sql` — dbs=VECA; tables=VECA].[dbo].[NOTATION,notation
- `old-queries/it queries/EBB_ATF_Serial_Lookup.sql` -> `old-queries/_organized/90_misc/it queries__EBB_ATF_Serial_Lookup.sql` — tables=BC15
- `old-queries/it queries/Infor Profile Lookup.sql` -> `old-queries/_organized/90_misc/it queries__Infor Profile Lookup.sql` — dbs=VECA; tables=user_profile,application_user,vta.dbo.labor_employee,USER_FLD_AUTHORITY…
- `old-queries/it queries/Lookup PL info and tracking.sql` -> `old-queries/_organized/90_misc/it queries__Lookup PL info and tracking.sql` — tables=USER_DEF_FIELDS,Z_UPS_SHIPMENTS
- `old-queries/it queries/Lookup Packlist with tracking (PLFixer).sql` -> `old-queries/_organized/90_misc/it queries__Lookup Packlist with tracking (PLFixer).sql` — dbs=VECA; tables=VECA.dbo.USER_DEF_FIELDS
- `old-queries/it queries/Lookup Trace by Customer ID.sql` -> `old-queries/_organized/90_misc/it queries__Lookup Trace by Customer ID.sql` — dbs=VECA; tables=customer_order,Inventory_trans,trace_inv_trans
- `old-queries/it queries/SN Upload Cleanup by Trace_rank.sql` -> `old-queries/_organized/90_misc/it queries__SN Upload Cleanup by Trace_rank.sql` — dbs=VECA; tables=VECA].[dbo].[_SN_UPLOAD
- `old-queries/it queries/Serial Numbers/FindGunInfoBySerialNumber.sql` -> `old-queries/_organized/90_misc/it queries__Serial Numbers__FindGunInfoBySerialNumber.sql` — tables=inventory_trans,trace_inv_trans,USER_DEF_FIELDS

## KEEP (likely useful) / parts_inventory

- `old-queries/Queries/Labor By Department Estimate.sql` -> `old-queries/_organized/40_parts_inventory/Queries__Labor By Department Estimate.sql` — dbs=VECA; tables=vta.dbo.labor_time_entry,vta.dbo.labor_time_card,VTA].[dbo].[LABOR_EMPLOYEE_DEPARTMENT,vta.[dbo].[LABOR_EMPLOYEE_PAY_RATE…
- `old-queries/Queries/SerialNumberDetail.sql` -> `old-queries/_organized/40_parts_inventory/Queries__SerialNumberDetail.sql` — dbs=VECA; tables=VECA].[dbo].[TRACE_INV_TRANS,veca.dbo.inventory_trans,VECA.dbo.PART,VECA.dbo.USER_DEF_FIELDS
- `old-queries/it queries/ComponentsProject/PARTLOCLOOKUP.sql` -> `old-queries/_organized/40_parts_inventory/it queries__ComponentsProject__PARTLOCLOOKUP.sql` — tables=PART_LOCATION,PART
- `old-queries/it queries/Get Open Order Line Detail.sql` -> `old-queries/_organized/40_parts_inventory/it queries__Get Open Order Line Detail.sql` — dbs=VECA; tables=VECA.dbo.CUSTOMER_ORDER,VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUSTOMER,VECA.dbo.CUSTOMER_ENTITY…
- `old-queries/it queries/Get requirements and quantities by part.sql` -> `old-queries/_organized/40_parts_inventory/it queries__Get requirements and quantities by part.sql` — dbs=VECA; tables=REQUIREMENT,PART_SITE,PART,PART_LOCATION
- `old-queries/it queries/Lookup Part Requirements by engineering master.sql` -> `old-queries/_organized/40_parts_inventory/it queries__Lookup Part Requirements by engineering master.sql` — tables=REQUIREMENT,PART_SITE
- `old-queries/it queries/More Trace Lookups.sql` -> `old-queries/_organized/40_parts_inventory/it queries__More Trace Lookups.sql` — dbs=VECA; tables=VECA].[dbo].[TRACE_INV_TRANS,part,trace
- `old-queries/it queries/Open order parts vs available-buildable-open quantities.sql` -> `old-queries/_organized/40_parts_inventory/it queries__Open order parts vs available-buildable-open quantities.sql` — dbs=VECA; tables=cust_order_line,customer_order,customer_entity,REQUIREMENT…
- `old-queries/it queries/Part Trace Lookup with QTY and Part Info.sql` -> `old-queries/_organized/40_parts_inventory/it queries__Part Trace Lookup with QTY and Part Info.sql` — dbs=VECA; tables=VECA].[dbo].PART,TRACE_INV_TRANS,PART_LOCATION,dbo.TRACE_INV_TRANS…
- `old-queries/it queries/Verify Match between trace-inventory-part_location quantities.sql` -> `old-queries/_organized/40_parts_inventory/it queries__Verify Match between trace-inventory-part_location quantities.sql` — tables=INVENTORY_TRANS,TRACE_INV_TRANS,part_location,pq…

## KEEP (likely useful) / shipping

- `old-queries/Queries/2022.01.25 - Customer Scorecard Completed.sql` -> `old-queries/_organized/20_shipping/Queries__2022.01.25 - Customer Scorecard Completed.sql` — dbs=VECA;VFIN; tables=VECA.dbo.Customer,VECA.dbo.CUSTOMER_ORDER,Vfin.dbo.RECEIVABLES_RECEIVABLE,veca.dbo.shipper…
- `old-queries/Queries/2022.01.25 - Open Orders.sql` -> `old-queries/_organized/20_shipping/Queries__2022.01.25 - Open Orders.sql` — dbs=VECA;VFIN; tables=VECA.dbo.CUSTOMER_ORDER,VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUST_LINE_DEL,VECA.dbo.Customer…
- `old-queries/Queries/Customer Scorecard Completed.sql` -> `old-queries/_organized/20_shipping/Queries__Customer Scorecard Completed.sql` — dbs=VECA;VFIN; tables=VECA.dbo.Customer,VECA.dbo.CUSTOMER_ORDER,Vfin.dbo.RECEIVABLES_RECEIVABLE,veca.dbo.shipper…
- `old-queries/Queries/Customer Scorecard.sql` -> `old-queries/_organized/20_shipping/Queries__Customer Scorecard.sql` — dbs=VECA;VFIN; tables=VECA.dbo.Customer,VECA.dbo.CUSTOMER_ORDER,Vfin.dbo.RECEIVABLES_RECEIVABLE,veca.dbo.shipper…
- `old-queries/Queries/Tracking Number Lookup.sql` -> `old-queries/_organized/20_shipping/Queries__Tracking Number Lookup.sql` — dbs=VECA;VFIN; tables=veca.dbo.user_def_fields,VECA.dbo.customer_order,VECA.dbo.shipper,VFIN.dbo.RECEIVABLES_RECEIVABLE…
- `old-queries/it queries/0ePacklist.sql` -> `old-queries/_organized/20_shipping/it queries__0ePacklist.sql` — dbs=VECA; tables=shipper,customer_order,LOCATION,part_location…
- `old-queries/it queries/Get Sales Tax Group and Shipper Line by Packlist.sql` -> `old-queries/_organized/20_shipping/it queries__Get Sales Tax Group and Shipper Line by Packlist.sql` — dbs=VECA; tables=SHIPPER_LINE
- `old-queries/it queries/Shipping/AllocableQtyQuery.sql` -> `old-queries/_organized/20_shipping/it queries__Shipping__AllocableQtyQuery.sql` — tables=CUSTOMER_ORDER,CUST_ORDER_LINE,IRP_DELIVERY_SCHEDULE_LINE_SHIP_DATE,VS_TRACE_LOCATION_QTY…
- `old-queries/it queries/Show all shipped serial numbers and product codes.sql` -> `old-queries/_organized/20_shipping/it queries__Show all shipped serial numbers and product codes.sql` — dbs=VECA; tables=SHIPPER,SHIPPER_LINE,TRACE_INV_TRANS,PART

## KEEP (likely useful) / work_orders

- `old-queries/it queries/Basic Workorder Lookup.sql` -> `old-queries/_organized/30_work_orders/it queries__Basic Workorder Lookup.sql` — dbs=VECA; tables=work_order,operation,requirement,inventory_Trans
- `old-queries/it queries/Cancel specific work orders-requirements-operations.sql` -> `old-queries/_organized/30_work_orders/it queries__Cancel specific work orders-requirements-operations.sql` — dbs=VECA; tables=work_order,requirement
- `old-queries/it queries/Get WIP-Open Orders-Available quantity queries by part.sql` -> `old-queries/_organized/30_work_orders/it queries__Get WIP-Open Orders-Available quantity queries by part.sql` — dbs=VECA; tables=cust_order_line,customer_order,customer_entity,part…
- `old-queries/it queries/Get Workorder Issued and calc qty.sql` -> `old-queries/_organized/30_work_orders/it queries__Get Workorder Issued and calc qty.sql` — dbs=VECA; tables=work_order,requirement
- `old-queries/it queries/Get qty of parts on open orders.sql` -> `old-queries/_organized/30_work_orders/it queries__Get qty of parts on open orders.sql` — dbs=VECA; tables=work_order,cust_order_line,customer_order,customer_entity
- `old-queries/it queries/Lookup Duplicate Transactions by SN.sql` -> `old-queries/_organized/30_work_orders/it queries__Lookup Duplicate Transactions by SN.sql` — dbs=VECA; tables=trace_inv_trans,INVENTORY_TRANS,part,work_order
- `old-queries/it queries/Lookup Workorder Information Operation-Requirement-Labor Transaction.sql` -> `old-queries/_organized/30_work_orders/it queries__Lookup Workorder Information Operation-Requirement-Labor Transaction.sql` — dbs=VECA; tables=OPERATION,OPERATION_BINARY,REQUIREMENT,PART…
- `old-queries/it queries/More Transaction Lookups.sql` -> `old-queries/_organized/30_work_orders/it queries__More Transaction Lookups.sql` — dbs=VECA; tables=inventory_trans,TRACE_INV_TRANS,PART,VECA.dbo.PART…
- `old-queries/it queries/Sales/Avg Cost by Part ID.sql` -> `old-queries/_organized/30_work_orders/it queries__Sales__Avg Cost by Part ID.sql` — tables=work_order,part
- `old-queries/it queries/Show matching quantities workorder vs transactions.sql` -> `old-queries/_organized/30_work_orders/it queries__Show matching quantities workorder vs transactions.sql` — dbs=VECA; tables=work_order,inventory_trans,trace_inv_trans
- `old-queries/it queries/Workorder Lookup.sql` -> `old-queries/_organized/30_work_orders/it queries__Workorder Lookup.sql` — dbs=VECA; tables=work_order,requirement,DEMAND_SUPPLY_LINK,part_location…
- `old-queries/it queries/Workorder Trace lookup with extra part info.sql` -> `old-queries/_organized/30_work_orders/it queries__Workorder Trace lookup with extra part info.sql` — dbs=VECA; tables=INVENTORY_TRANS,TRACE_INV_TRANS,part,PART_CO_BINARY…

## REVIEW / admin_dba

- `old-queries/it queries/Admin-Find Foreign Key References.sql` -> `old-queries/_organized/70_admin_dba/it queries__Admin-Find Foreign Key References.sql` — dbs=VECA; tables=sys.foreign_keys,sys.foreign_key_columns,sys.tables
- `old-queries/it queries/Check Index Fragmentation.sql` -> `old-queries/_organized/70_admin_dba/it queries__Check Index Fragmentation.sql` — tables=sys.fulltext_index_fragments
- `old-queries/it queries/Grant Select to DB.sql` -> `old-queries/_organized/70_admin_dba/it queries__Grant Select to DB.sql` — dbs=VFIN

## REVIEW / other

- `old-queries/Queries/2022.02.11 - 7CARMS - Forecast and Usage.sql` -> `old-queries/_organized/90_misc/Queries__2022.02.11 - 7CARMS - Forecast and Usage.sql` — dbs=VECA; tables=VECA.dbo.PLANNED_MATL_REQ,veca.dbo.inventory_trans
- `old-queries/Queries/GL Posting Level Detail.sql` -> `old-queries/_organized/90_misc/Queries__GL Posting Level Detail.sql` — dbs=VECA;VFIN; tables=VFIN.dbo.PAYABLES_PAYABLE_DIST,VFIN.dbo.RECEIVABLES_RECEIVABLE_DIST,VFIN.dbo.CASHMGMT_BANK_ADJ_DIST,VFIN.dbo.CASHMGMT_PAYMENT_DIST…
- `old-queries/Queries/GL Summary Detail.sql` -> `old-queries/_organized/90_misc/Queries__GL Summary Detail.sql` — dbs=VECA;VFIN; tables=VFIN.dbo.LEDGER_ACCOUNT_BALANCE,VECA.dbo.Z_GL_MAPPING,VFIN.dbo.LEDGER_ACCOUNT
- `old-queries/Queries/Historical Backlog Query.sql` -> `old-queries/_organized/90_misc/Queries__Historical Backlog Query.sql` — dbs=VECA; tables=VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUSTOMER_ORDER
- `old-queries/Queries/Note and Spec Fields.sql` -> `old-queries/_organized/90_misc/Queries__Note and Spec Fields.sql` — dbs=VECA; tables=VECA.dbo.PURC_LINE_BINARY,VECA.dbo.PURC_ORDER_BINARY,VECA.dbo.NOTATION,VECA.DBO.Customer_Binary…
- `old-queries/Queries/POV Baseline Queries.sql` -> `old-queries/_organized/90_misc/Queries__POV Baseline Queries.sql` — dbs=VECA; tables=VECA.dbo.INVENTORY_TRANS
- `old-queries/Queries/Top 10 Products by Family.sql` -> `old-queries/_organized/90_misc/Queries__Top 10 Products by Family.sql` — dbs=VECA; tables=VECA.dbo.CUST_ORDER_LINE,VECA.dbo.USER_DEF_FIELDS
- `old-queries/Queries/Top 25 FFT Products for Canada.sql` -> `old-queries/_organized/90_misc/Queries__Top 25 FFT Products for Canada.sql` — dbs=VECA; tables=VECA.dbo.CUST_ORDER_LINE,VECA.dbo.USER_DEF_FIELDS
- `old-queries/Queries/lastMileOrderUpdate.sql` -> `old-queries/_organized/90_misc/Queries__lastMileOrderUpdate.sql` — dbs=VECA; tables=VECA.dbo.CUSTOMER_ORDER,VECA.dbo.USER_DEF_FIELDS
- `old-queries/Queries/unbalancesInvoices.sql` -> `old-queries/_organized/90_misc/Queries__unbalancesInvoices.sql` — dbs=VFIN; tables=vfin.dbo.payables_payable_dist
- `old-queries/Queries/updated hourly rates.sql` -> `old-queries/_organized/90_misc/Queries__updated hourly rates.sql` — tables=VTA.dbo.LABOR_EMPLOYEE_DEPARTMENT
- `old-queries/it queries/ATF App Join Expected vs Counted Tables.sql` -> `old-queries/_organized/90_misc/it queries__ATF App Join Expected vs Counted Tables.sql` — dbs=VECA; tables=VECA].[dbo].[ATF_SN,VECA].[dbo].ATF_CNT_TBL
- `old-queries/it queries/EBBOpenAcquisitions.sql` -> `old-queries/_organized/90_misc/it queries__EBBOpenAcquisitions.sql` — tables=TDJ,"TEST_DB_CHRISTENSEN$Easy,"Christensen_Arms$Easy
- `old-queries/it queries/Get Active Employee Emails.sql` -> `old-queries/_organized/90_misc/it queries__Get Active Employee Emails.sql` — tables=VTA.dbo.LABOR_EMPLOYEE
- `old-queries/it queries/Get User Infor Access Levels.sql` -> `old-queries/_organized/90_misc/it queries__Get User Infor Access Levels.sql` — dbs=VECA; tables=user_profile,application_user,vta.dbo.labor_employee,USER_FLD_AUTHORITY…
- `old-queries/it queries/Get notes from customer order (convert bits to varchar).sql` -> `old-queries/_organized/90_misc/it queries__Get notes from customer order (convert bits to varchar).sql` — dbs=VECA; tables=VECA].[dbo].[CUST_order_BINARY
- `old-queries/it queries/KioskUsersActive.sql` -> `old-queries/_organized/90_misc/it queries__KioskUsersActive.sql` — tables=LSA.dbo.LSA_LOGINS,VTA.dbo.SHARED_CONFIG_KIOSK
- `old-queries/it queries/Safety Stock Bulk Update Example.sql` -> `old-queries/_organized/90_misc/it queries__Safety Stock Bulk Update Example.sql`

## REVIEW / parts_inventory

- `old-queries/Queries/Employee Department Up to date.sql` -> `old-queries/_organized/40_parts_inventory/Queries__Employee Department Up to date.sql` — tables=VTA.dbo.LABOR_EMPLOYEE_DEPARTMENT,VTA.dbo.LABOR_EMPLOYEE_PAY_RATE
- `old-queries/Queries/Inventory Location and Value.sql` -> `old-queries/_organized/40_parts_inventory/Queries__Inventory Location and Value.sql` — dbs=VECA; tables=VECA.dbo.INVENTORY_TRANS,VECA.dbo.PART_LOCATION,VECA.dbo.part
- `old-queries/Queries/Inventory Turns.sql` -> `old-queries/_organized/40_parts_inventory/Queries__Inventory Turns.sql` — dbs=VECA; tables=veca.dbo.part,VECA.dbo.INVENTORY_TRANS
- `old-queries/Queries/LastMileOrderCollection.sql` -> `old-queries/_organized/40_parts_inventory/Queries__LastMileOrderCollection.sql` — dbs=VECA; tables=VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUSTOMER_ORDER,veca.dbo.customer,veca.dbo.cust_address…
- `old-queries/Queries/Order Forecast Query.sql` -> `old-queries/_organized/40_parts_inventory/Queries__Order Forecast Query.sql` — dbs=VECA; tables=VECA.dbo.CUSTOMER_ORDER,VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUSTOMER_CARMS,VECA.dbo.PART
- `old-queries/Queries/Part User Defined Fields.sql` -> `old-queries/_organized/40_parts_inventory/Queries__Part User Defined Fields.sql` — dbs=VECA; tables=VECA.dbo.PART,VECA.dbo.USER_DEF_FIELDS
- `old-queries/Queries/Redeptions by Part.sql` -> `old-queries/_organized/40_parts_inventory/Queries__Redeptions by Part.sql` — dbs=VECA; tables=VECA.dbo.CUST_ORDER_LINE
- `old-queries/it queries/ComponentsProject/CompInventory.sql` -> `old-queries/_organized/40_parts_inventory/it queries__ComponentsProject__CompInventory.sql` — tables=dbo.PART_LOCATION,loc_totals,wh_totals,dbo.PART
- `old-queries/it queries/Find picklist orders available.sql` -> `old-queries/_organized/40_parts_inventory/it queries__Find picklist orders available.sql` — dbs=VECA; tables=veca.dbo.customer_order,veca.dbo.cust_order_line,veca.dbo.part,veca.dbo.customer_entity…
- `old-queries/it queries/Part User Defined Fields.sql` -> `old-queries/_organized/40_parts_inventory/it queries__Part User Defined Fields.sql` — dbs=VECA; tables=VECA.dbo.PART,VECA.dbo.USER_DEF_FIELDS
- `old-queries/it queries/Update order policies for bulk changes to MRP.sql` -> `old-queries/_organized/40_parts_inventory/it queries__Update order policies for bulk changes to MRP.sql` — dbs=VECA; tables=part,part_location,warehouse_locati

## REVIEW / shipping

- `old-queries/Queries/2022 Orders and Shipments (Kort Request).sql` -> `old-queries/_organized/20_shipping/Queries__2022 Orders and Shipments (Kort Request).sql` — dbs=VECA; tables=VECA.dbo.CUST_ORDER_LINE,veca.dbo.part
- `old-queries/Queries/2022.01.25 - Order Scores Selection.sql` -> `old-queries/_organized/20_shipping/Queries__2022.01.25 - Order Scores Selection.sql` — dbs=VECA;VFIN; tables=VECA.dbo.CUSTOMER_ORDER,VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUST_LINE_DEL,VECA.dbo.Customer…
- `old-queries/Queries/2022.02.22 - Picklist SQL.sql` -> `old-queries/_organized/20_shipping/Queries__2022.02.22 - Picklist SQL.sql` — dbs=VECA;VFIN; tables=VECA.dbo.CUSTOMER_ORDER,VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUST_LINE_DEL,VECA.dbo.Customer…
- `old-queries/Queries/2022.02.23 - Picklist Updated SQL.sql` -> `old-queries/_organized/20_shipping/Queries__2022.02.23 - Picklist Updated SQL.sql` — dbs=VECA;VFIN; tables=VECA.dbo.CUSTOMER_ORDER,VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUST_LINE_DEL,VECA.dbo.Customer…
- `old-queries/Queries/2022.03.14 - Tableau Shipping Dashboard V2.sql` -> `old-queries/_organized/20_shipping/Queries__2022.03.14 - Tableau Shipping Dashboard V2.sql` — dbs=VECA;VFIN; tables=VECA.dbo.CUSTOMER_ORDER,VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUST_LINE_DEL,VECA.dbo.Customer…
- `old-queries/Queries/Gross Margin Comparison Structure.sql` -> `old-queries/_organized/20_shipping/Queries__Gross Margin Comparison Structure.sql` — dbs=VECA; tables=veca.dbo.shipper_Line,veca.dbo.cust_order_line,veca.dbo.shipper,VECA.dbo.INVENTORY_TRANS…
- `old-queries/it queries/0eXchg.sql` -> `old-queries/_organized/20_shipping/it queries__0eXchg.sql` — dbs=VECA;VFIN; tables=VECA.dbo.CUSTOMER,VFIN.dbo.RECEIVABLES_CUSTOMER,VECA.dbo.CUSTOMER_ORDER,VFIN.dbo.RECEIVABLES_CUSTOMER_ORDER…
- `old-queries/it queries/SN Upload Update List.sql` -> `old-queries/_organized/20_shipping/it queries__SN Upload Update List.sql` — dbs=VECA; tables=_SN_UPLOAD,SHIPPER,SHIPPER_LINE,TRACE_INV_TRANS…

## REVIEW / work_orders

- `old-queries/Queries/2022.03.14 - Tableau Shipping Dashboard.sql` -> `old-queries/_organized/30_work_orders/Queries__2022.03.14 - Tableau Shipping Dashboard.sql` — dbs=VECA; tables=VECA.dbo.PART,veca.dbo.work_order
- `old-queries/Queries/Material Planning Window Recalculation.sql` -> `old-queries/_organized/30_work_orders/Queries__Material Planning Window Recalculation.sql` — dbs=VECA; tables=VECA.dbo.PURCHASE_ORDER,VECA.dbo.PURC_ORDER_LINE,VECA.dbo.PURC_LINE_DEL,VECA.dbo.PLANNED_MATL_REQ…
- `old-queries/it queries/Find list of closed work orders where close date null.sql` -> `old-queries/_organized/30_work_orders/it queries__Find list of closed work orders where close date null.sql` — dbs=VECA; tables=work_order,inventory_trans
- `old-queries/it queries/Get Average and Total costs of parts by part.sql` -> `old-queries/_organized/30_work_orders/it queries__Get Average and Total costs of parts by part.sql` — dbs=VECA; tables=work_order,part
- `old-queries/it queries/MRP Recreation Runner.sql` -> `old-queries/_organized/30_work_orders/it queries__MRP Recreation Runner.sql` — dbs=VECA; tables=VECA.dbo.PURCHASE_ORDER,VECA.dbo.PURC_ORDER_LINE,VECA.dbo.PURC_LINE_DEL,VECA.dbo.PLANNED_MATL_REQ…
- `old-queries/it queries/MRP monthly database script.sql` -> `old-queries/_organized/30_work_orders/it queries__MRP monthly database script.sql` — dbs=VECA; tables=VECA.dbo.PURCHASE_ORDER,VECA.dbo.PURC_ORDER_LINE,VECA.dbo.PURC_LINE_DEL,VECA.dbo.PLANNED_MATL_REQ…
- `old-queries/it queries/Packaging/TroubleshootingTool.sql` -> `old-queries/_organized/30_work_orders/it queries__Packaging__TroubleshootingTool.sql` — tables=TRACE_INV_TRANS,INVENTORY_TRANS,WORK_ORDER,PART…
- `old-queries/it queries/Parts on WO not allocated.sql` -> `old-queries/_organized/30_work_orders/it queries__Parts on WO not allocated.sql` — tables=dbo.WORK_ORDER,dbo.REQUIREMENT
- `old-queries/it queries/SELECT [t0].[SKU] AS [SKU],.sql` -> `old-queries/_organized/30_work_orders/it queries__SELECT [t0].[SKU] AS [SKU],.sql` — tables=WORK_ORDER,dbo.REQUIREMENT,PART_LOCATION,REQUIREMENT…
- `old-queries/it queries/Scheduling queries for available, required etc.sql` -> `old-queries/_organized/30_work_orders/it queries__Scheduling queries for available, required etc.sql` — dbs=VECA; tables=REQUIREMENT,PART_SITE,PART,PART_LOCATION…
- `old-queries/it queries/work_order_old_open.sql` -> `old-queries/_organized/30_work_orders/it queries__work_order_old_open.sql` — tables=work_order,requirement,DEMAND_SUPPLY_LINK,part_location…

## REVIEW (maybe obsolete/test) / parts_inventory

- `old-queries/it queries/Test Query for non picklst orders.sql` -> `old-queries/_organized/40_parts_inventory/it queries__Test Query for non picklst orders.sql` — dbs=VECA; tables=veca.dbo.customer_order,veca.dbo.cust_order_line,veca.dbo.part,veca.dbo.customer_entity…

## REVIEW (maybe obsolete/test) / shipping

- `old-queries/Queries/SHIPPING ALGORITHIM TESTING.sql` -> `old-queries/_organized/20_shipping/Queries__SHIPPING ALGORITHIM TESTING.sql` — dbs=VECA;VFIN; tables=VECA.dbo.CUSTOMER_ORDER,VECA.dbo.CUST_ORDER_LINE,VECA.dbo.CUST_LINE_DEL,VECA.dbo.Customer…

## REVIEW (writes) / accounting_vfin

- `old-queries/Queries/VFIN Payable Posting Corrections.sql` -> `old-queries/_organized/99_write_scripts_review/Queries__VFIN Payable Posting Corrections.sql` — dbs=VFIN; writes=UPDATE; tables=vfin.dbo.payables_payable_dist,vfin.dbo.ledger_account_balance,vfin.dbo.ledger_account,vfin.dbo.receivables_receivable_dist

## REVIEW (writes) / admin_dba

- `old-queries/it queries/Grant Select Update Insert Delete to Table for User.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__Grant Select Update Insert Delete to Table for User.sql` — dbs=VFIN; writes=DELETE;INSERT;UPDATE
- `old-queries/it queries/Restore Backup Query.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__Restore Backup Query.sql` — dbs=VECA;VFIN; writes=ALTER; tables=DISK
- `old-queries/it queries/sqlserver index rebuild.new (1).sql` -> `old-queries/_organized/99_write_scripts_review/it queries__sqlserver index rebuild.new (1).sql` — writes=ALTER;DROP; tables=sys.dm_db_index_physical_stats,partitions,sys.objects,sys.schemas…

## REVIEW (writes) / other

- `old-queries/Queries/By Pass Email Script.sql` -> `old-queries/_organized/99_write_scripts_review/Queries__By Pass Email Script.sql` — dbs=VECA; writes=UPDATE
- `old-queries/it queries/0aVmfg.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__0aVmfg.sql` — dbs=VECA; writes=DELETE; tables=DBO.LOGINS
- `old-queries/it queries/ATF App Queries.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__ATF App Queries.sql` — dbs=VECA; writes=DELETE;DROP; tables=ATF_SN,ATF_CNT_TBL,VECA].[dbo].[ATF_CNT_TBL,ATF_AUDIT_PERIOD…
- `old-queries/it queries/ComponentsProject/RACKSHELFBIN.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__ComponentsProject__RACKSHELFBIN.sql` — writes=INSERT; tables=sys.all_objects,N,Shelves,Bins…
- `old-queries/it queries/Entrust Query.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__Entrust Query.sql` — writes=CREATE;INSERT; tables=sys.dm_exec_query_stats,ESI_CORE].[ESI_GLOBAL,ESI_CORE].[v_ERP_INVOICE_HEADER_TEST,ESI_EDI].[ESI_DASH_HEADER_INVOICE…
- `old-queries/it queries/Update Receiver-GL Mapping information.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__Update Receiver-GL Mapping information.sql` — writes=UPDATE; tables=receivable,receivable_line,cust_order_line,customer

## REVIEW (writes) / parts_inventory

- `old-queries/it queries/0gBadAdjs.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__0gBadAdjs.sql` — dbs=VECA; writes=UPDATE; tables=INVENTORY_TRANS,PART
- `old-queries/it queries/ComponentsProject/PARTLOCDELETE.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__ComponentsProject__PARTLOCDELETE.sql` — writes=DELETE; tables=PART_LOCATION
- `old-queries/it queries/Update Order Policy Bulk Change (2021).sql` -> `old-queries/_organized/99_write_scripts_review/it queries__Update Order Policy Bulk Change (2021).sql` — writes=UPDATE; tables=PART

## REVIEW (writes) / sales_edi

- `old-queries/it queries/Sales/EDI/UpdateCustAddressfromFile.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__Sales__EDI__UpdateCustAddressfromFile.sql` — writes=CREATE;DROP;INSERT;UPDATE; tables='\\2CARMS\CARMS$\CA,CUST_ADDRESS,test2.dbo.cust_address

## REVIEW (writes) / shipping

- `old-queries/it queries/SN UPload Update Produc Codes.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__SN UPload Update Produc Codes.sql` — dbs=VECA; writes=UPDATE; tables=SHIPPER,SHIPPER_LINE,TRACE_INV_TRANS,PART…
- `old-queries/it queries/ViewsJoel/v_DASH_HEADER_INVOICE.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__ViewsJoel__v_DASH_HEADER_INVOICE.sql` — dbs=VECA; writes=CREATE; tables=3CARMS\CAPROD].[VECA].[dbo].[RECEIVABLE,ESI_CORE].[ESI_CUSTOMER,ESI_CORE].[ESI_TRADING_PARTNER,ESI_CORE].[ESI_CUSTOMER_GROUP…
- `old-queries/it queries/ViewsJoel/v_DASH_HEADER_INVOICE_PLAY.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__ViewsJoel__v_DASH_HEADER_INVOICE_PLAY.sql` — dbs=VECA; writes=CREATE; tables=6CARMS\CAPROD].[VECA].[dbo].[RECEIVABLE,ESI_CORE].[ESI_CUSTOMER,ESI_CORE].[ESI_TRADING_PARTNER,ESI_CORE].[ESI_CUSTOMER_GROUP…
- `old-queries/it queries/ViewsJoel/v_DASH_HEADER_INVOICE_TEST.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__ViewsJoel__v_DASH_HEADER_INVOICE_TEST.sql` — dbs=VECA; writes=CREATE; tables=6CARMS\CAPROD].[VECA].[dbo].[RECEIVABLE,ESI_CORE].[ESI_CUSTOMER,ESI_CORE].[ESI_TRADING_PARTNER,ESI_CORE].[ESI_CUSTOMER_GROUP…
- `old-queries/it queries/ViewsJoel/v_DASH_LINE_INVOICE.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__ViewsJoel__v_DASH_LINE_INVOICE.sql` — dbs=VECA; writes=CREATE; tables=3CARMS\CAPROD].[VECA].[dbo].[RECEIVABLE_LINE,3CARMS\CAPROD].[VECA].[dbo].[RECEIVABLE,3CARMS\CAPROD].[VECA].[dbo].[SHIPPER_LINE,3CARMS\CAPROD].[VECA].[dbo].[SHIPPER…
- `old-queries/it queries/ViewsJoel/v_DASH_LINE_INVOICE_PLAY.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__ViewsJoel__v_DASH_LINE_INVOICE_PLAY.sql` — dbs=VECA; writes=CREATE; tables=6CARMS\CAPROD].[VECA].[dbo].[RECEIVABLE_LINE,6CARMS\CAPROD].[VECA].[dbo].[RECEIVABLE,6CARMS\CAPROD].[VECA].[dbo].[SHIPPER_LINE,6CARMS\CAPROD].[VECA].[dbo].[SHIPPER…
- `old-queries/it queries/ViewsJoel/v_DASH_LINE_INVOICE_TEST.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__ViewsJoel__v_DASH_LINE_INVOICE_TEST.sql` — dbs=VECA; writes=CREATE; tables=6CARMS\CAPROD].[VECA].[dbo].[RECEIVABLE_LINE,6CARMS\CAPROD].[VECA].[dbo].[RECEIVABLE,6CARMS\CAPROD].[VECA].[dbo].[SHIPPER_LINE,6CARMS\CAPROD].[VECA].[dbo].[SHIPPER…

## REVIEW (writes) / work_orders

- `old-queries/it queries/Admin-Map Network Drive for MSSQL Backups.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__Admin-Map Network Drive for MSSQL Backups.sql` — writes=CREATE
- `old-queries/it queries/Test for bad trace inv transactions.sql` -> `old-queries/_organized/99_write_scripts_review/it queries__Test for bad trace inv transactions.sql` — dbs=VECA; writes=UPDATE; tables=trace_inv_trans,INVENTORY_TRANS,part,part_location…
