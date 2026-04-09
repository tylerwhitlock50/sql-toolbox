# VECA Database Reference (Infor VISUAL Manufacturing)

This document covers the key tables used for day-to-day queries against the VECA ERP database. It is organized by functional area. Use this as a quick reference to avoid scanning DDL scripts for context.

---

## 1. Customer Orders (Sales)

### CUSTOMER_ORDER
The header table for all sales orders.

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(15) | **PK**. Sales order number |
| CUSTOMER_ID | nvarchar(15) | FK to CUSTOMER |
| CUSTOMER_PO_REF | nvarchar(40) | Customer's PO reference |
| SITE_ID | nvarchar(15) | FK to SITE |
| ORDER_DATE | datetime | Default: getdate() |
| DESIRED_SHIP_DATE | datetime | Requested ship date |
| PROMISE_DATE | datetime | Promised date |
| STATUS | nchar(1) | Order status flag |
| CURRENCY_ID | nvarchar(15) | FK to CURRENCY |
| SALESREP_ID | nvarchar(15) | Sales representative |
| TERRITORY | nvarchar(15) | Sales territory |
| SHIP_VIA | nvarchar(40) | Shipping method |
| FREE_ON_BOARD | nvarchar(25) | FOB terms |
| FREIGHT_TERMS | nchar(1) | Freight terms code |
| SELL_RATE / BUY_RATE | decimal(15,8) | Exchange rates |
| TOTAL_AMT_ORDERED | decimal(23,8) | Sum of line amounts |
| TOTAL_AMT_SHIPPED | decimal(23,8) | Sum shipped |
| WAREHOUSE_ID | nvarchar(15) | Default warehouse |
| ORDER_TYPE | nvarchar(20) | FK to CUST_ORDER_TYPE |
| CARRIER_ID | nvarchar(15) | Carrier |
| SHIP_TO_ADDR_NO | int | Ship-to address number |
| SHIPTO_ID | nvarchar(20) | Ship-to ID |
| DISCOUNT_CODE | nvarchar(15) | Discount terms |
| SALES_TAX_GROUP_ID | nvarchar(15) | Tax group |
| TERMS_NET_TYPE/DAYS/DATE | mixed | Payment terms - net |
| TERMS_DISC_TYPE/DAYS/DATE/PERCENT | mixed | Payment terms - discount |
| BACK_ORDER | nchar(1) | Backorder allowed flag |
| CONSIGNMENT | nchar(1) | Default: 'N' |
| PROJECT_ID | nvarchar(15) | Project reference |
| ENTERED_BY | nvarchar(20) | User who created order |
| USER_1 .. USER_10 | nvarchar(80) | User-defined fields |

**Key FKs:** CUSTOMER_ID -> CUSTOMER, SITE_ID -> SITE, CURRENCY_ID -> CURRENCY, SALES_TAX_GROUP_ID -> SALES_TAX_GROUP, TERMS_ID -> TERMS

### CUST_ORDER_LINE
Line items on a sales order.

| Column | Type | Notes |
|---|---|---|
| **CUST_ORDER_ID** | nvarchar(15) | **PK (composite)**. FK to CUSTOMER_ORDER |
| **LINE_NO** | smallint | **PK (composite)** |
| PART_ID | nvarchar(30) | FK to PART |
| CUSTOMER_PART_ID | nvarchar(30) | Customer's part number |
| LINE_STATUS | nchar(1) | Line status flag |
| ORDER_QTY | decimal(20,8) | Ordered quantity (stocking UM) |
| USER_ORDER_QTY | decimal(20,8) | Ordered quantity (selling UM) |
| SELLING_UM | nvarchar(15) | Selling unit of measure |
| UNIT_PRICE | decimal(22,8) | Unit selling price |
| TRADE_DISC_PERCENT | decimal(6,3) | Trade discount % |
| DESIRED_SHIP_DATE | datetime | Line-level ship date |
| PROMISE_DATE | datetime | Line-level promise date |
| PRODUCT_CODE | nvarchar(15) | Accounting product code |
| COMMODITY_CODE | nvarchar(15) | Commodity classification |
| TOTAL_SHIPPED_QTY | decimal(20,8) | Total shipped |
| TOTAL_AMT_SHIPPED | decimal(23,8) | Total amount shipped |
| TOTAL_AMT_ORDERED | decimal(23,8) | Total amount ordered |
| ALLOCATED_QTY | decimal(20,8) | Allocated inventory qty |
| FULFILLED_QTY | decimal(20,8) | Fulfilled qty |
| WAREHOUSE_ID | nvarchar(15) | Warehouse for this line |
| SITE_ID | nvarchar(15) | Site for this line |
| GL_REVENUE_ACCT_ID | nvarchar(30) | Revenue GL account |
| MAT/LAB/BUR/SER_GL_ACCT_ID | nvarchar(30) | Cost GL accounts |
| DRAWING_ID / DRAWING_REV_NO | nvarchar | Engineering drawing ref |
| USER_1 .. USER_10 | nvarchar(80) | User-defined fields |

**Key FKs:** CUST_ORDER_ID -> CUSTOMER_ORDER (cascade delete), PART_ID -> PART, SELLING_UM -> UNITS

### CUST_LINE_DEL
Delivery schedule lines under each order line. Tracks planned and actual shipments.

| Column | Type | Notes |
|---|---|---|
| **CUST_ORDER_ID** | nvarchar(15) | **PK (composite)** |
| **CUST_ORDER_LINE_NO** | smallint | **PK (composite)** |
| **DEL_SCHED_LINE_NO** | smallint | **PK (composite)** |
| DESIRED_SHIP_DATE | datetime | Scheduled ship date |
| ACTUAL_SHIP_DATE | datetime | Actual ship date |
| ORDER_QTY | decimal(20,8) | Delivery qty (stocking UM) |
| USER_ORDER_QTY | decimal(20,8) | Delivery qty (selling UM) |
| SHIPPED_QTY | decimal(20,8) | Shipped qty |
| ALLOCATED_QTY | decimal(20,8) | Allocated qty |
| FULFILLED_QTY | decimal(20,8) | Fulfilled qty |
| LINE_STATUS | nchar(1) | Delivery line status |
| RELEASE_NUMBER | nvarchar(30) | Release/blanket number |
| SHIPTO_ID | nvarchar(20) | Ship-to override |
| WAREHOUSE_ID | nvarchar(15) | Warehouse override |
| CARRIER_ID | nvarchar(15) | Carrier override |

### CUST_ORDER_TYPE
Lookup table for order type codes.

| Column | Type | Notes |
|---|---|---|
| **TYPE** | nvarchar(20) | **PK**. Order type code |
| DESCRIPTION | nvarchar(40) | Description |

### CUST_LINE_BILLING
Milestone/progress billing events per order line.

| Column | Type | Notes |
|---|---|---|
| **CUST_ORDER_ID** | nvarchar(15) | **PK (composite)** |
| **CUST_ORDER_LINE_NO** | smallint | **PK (composite)** |
| **EVENT_SEQ_NO** | smallint | **PK (composite)** |
| DESCRIPTION | nvarchar(80) | Event description |
| BILL_AMOUNT / BILL_PERCENT | decimal | Billing amount or % |
| REV_AMOUNT / REV_PERCENT | decimal | Revenue amount or % |
| MILESTONE_ID | nvarchar(15) | Milestone reference |
| EVENT_DATE | datetime | Target event date |
| TRIGGERED_FLAG / TRIGGERED_DATE | mixed | Whether event has fired |
| INVOICE_ID | nvarchar(15) | Generated invoice ref |

---

## 2. Parts / Items

The part master is split across three objects. **Prefer querying from PART_SITE_VIEW** which merges PART and PART_SITE with ISNULL() fallback logic (site-level values override part-level defaults).

### PART
Global part master. Defines the item and its default attributes.

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(30) | **PK**. Part number |
| DESCRIPTION | nvarchar(120) | Part description |
| STOCK_UM | nvarchar(15) | Stocking unit of measure |
| PRODUCT_CODE | nvarchar(15) | Accounting product code group |
| COMMODITY_CODE | nvarchar(15) | Commodity classification |
| FABRICATED | nchar(1) | Is manufactured |
| PURCHASED | nchar(1) | Is purchased |
| STOCKED | nchar(1) | Is stocked/inventoried |
| DETAIL_ONLY | nchar(1) | Non-inventory (phantom) flag |
| PLANNING_LEADTIME | smallint | Default lead time (days) |
| ORDER_POLICY | nchar(1) | MRP order policy |
| SAFETY_STOCK_QTY | decimal(20,8) | Safety stock |
| FIXED_ORDER_QTY | decimal(20,8) | Fixed order quantity |
| MINIMUM_ORDER_QTY | decimal(20,8) | Minimum order |
| MAXIMUM_ORDER_QTY | decimal(20,8) | Maximum order |
| PREF_VENDOR_ID | nvarchar(15) | Preferred vendor |
| BUYER_USER_ID | nvarchar(20) | Buyer |
| PLANNER_USER_ID | nvarchar(20) | Planner |
| QTY_ON_HAND | decimal(20,8) | Global on-hand qty |
| QTY_AVAILABLE_ISS | decimal(20,8) | Available to issue |
| QTY_AVAILABLE_MRP | decimal(20,8) | Available for MRP |
| QTY_ON_ORDER | decimal(20,8) | On order (PO/WO) |
| QTY_IN_DEMAND | decimal(20,8) | In demand (CO/WO req) |
| QTY_COMMITTED | decimal(20,8) | Committed qty |
| WEIGHT / WEIGHT_UM | mixed | Item weight |
| DRAWING_ID / DRAWING_REV_NO | nvarchar | Engineering drawing |
| MFG_NAME / MFG_PART_ID | nvarchar | Manufacturer reference |
| INSPECTION_REQD | nchar(1) | Receiving inspection flag |
| ABC_CODE | nchar(1) | ABC classification |
| STATUS | nchar(1) | Active/inactive |
| IS_KIT | nchar(1) | Kit flag |
| REVISION_ID | nvarchar(8) | Current engineering revision |
| MAT/LAB/BUR/SER_GL_ACCT_ID | nvarchar(30) | Default GL accounts |
| USER_1 .. USER_10 | nvarchar(80) | User-defined fields |

### PART_SITE
Site-level overrides for a part. Same structure as PART for most columns but values here take precedence.

| Column | Type | Notes |
|---|---|---|
| **SITE_ID** | nvarchar(15) | **PK (composite)**. FK to SITE |
| **PART_ID** | nvarchar(30) | **PK (composite)**. FK to PART |
| UNIT_PRICE | decimal(22,8) | Selling price |
| UNIT_MATERIAL_COST | decimal(22,8) | Standard material cost |
| UNIT_LABOR_COST | decimal(22,8) | Standard labor cost |
| UNIT_BURDEN_COST | decimal(22,8) | Standard burden cost |
| UNIT_SERVICE_COST | decimal(22,8) | Standard service cost |
| BURDEN_PERCENT | decimal(5,2) | Burden % |
| FIXED_COST | decimal(23,8) | Fixed cost per run |
| PRIMARY_WHS_ID / PRIMARY_LOC_ID | nvarchar(15) | Default warehouse/location |
| BACKFLUSH_WHS_ID / BACKFLUSH_LOC_ID | nvarchar(15) | Backflush warehouse/location |
| INSPECT_WHS_ID / INSPECT_LOC_ID | nvarchar(15) | Inspection warehouse/location |
| QTY_ON_HAND | decimal(20,8) | Site-level on-hand |
| QTY_AVAILABLE_ISS / QTY_AVAILABLE_MRP | decimal(20,8) | Site-level availability |
| QTY_ON_ORDER / QTY_IN_DEMAND / QTY_COMMITTED | decimal(20,8) | Site-level demand/supply |
| NEW_MATERIAL/LABOR/BURDEN/SERVICE_COST | decimal | Pending cost roll values |
| PRODUCT_CODE | nvarchar(15) | Site-level product code override |
| STATUS | nchar(1) | Site-level status |
| *(plus all planning, flags, and UDF columns from PART)* | | Site-level overrides |

### PART_SITE_VIEW (Preferred)
**USE THIS VIEW for most queries.** Joins PART + PART_SITE using `ISNULL(PART_SITE.col, PART.col)` so site-level values take precedence with part-level defaults as fallback. Contains all columns from both tables (~170 columns).

---

## 3. Product Codes (Accounting Grouping)

### PRODUCT
Defines accounting product code groups that drive GL account mapping.

| Column | Type | Notes |
|---|---|---|
| **CODE** | nvarchar(15) | **PK**. Product code |
| DESCRIPTION | nvarchar(80) | Description |
| REV_GL_ACCT_ID | nvarchar(30) | Revenue GL account |
| ADJ_GL_ACCT_ID | nvarchar(30) | Adjustment GL account |
| INV_MAT/LAB/BUR/SER_GL_ACCT_ID | nvarchar(30) | Inventory GL accounts (material, labor, burden, service) |
| VAR_MAT/LAB/BUR/SER_GL_ACCT_ID | nvarchar(30) | Variance GL accounts |
| CGS_MAT/LAB/BUR/SER_GL_ACCT_ID | nvarchar(30) | Cost of Goods Sold GL accounts |
| WIP_MAT/LAB/BUR/SER_GL_ACCT_ID | nvarchar(30) | WIP GL accounts |
| WITHHOLDING_CODE | nvarchar(15) | FK to WITHHOLDING |
| DEMAND_FENCE_1 / DEMAND_FENCE_2 | int | Demand time fences |
| COST_CATEGORY_ID | nvarchar(15) | Cost category |
| ACTIVE_FLAG | nchar(1) | Default: 'Y' |

**Note:** The PRODUCT_CODE column on PART and PART_SITE references this table's CODE column. This is the primary mechanism for grouping parts into accounting categories.

---

## 4. Purchase Orders

### PURCHASE_ORDER
Header table for all purchase orders.

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(15) | **PK**. PO number |
| VENDOR_ID | nvarchar(15) | FK to VENDOR |
| SITE_ID | nvarchar(15) | FK to SITE |
| ORDER_DATE | datetime | Default: getdate() |
| DESIRED_RECV_DATE | datetime | Requested receive date |
| PROMISE_DATE | datetime | Vendor promise date |
| STATUS | nchar(1) | PO status flag |
| BUYER | nvarchar(20) | Buyer user ID |
| CURRENCY_ID | nvarchar(15) | FK to CURRENCY |
| SELL_RATE / BUY_RATE | decimal(15,8) | Exchange rates |
| TOTAL_AMT_ORDERED | decimal(23,8) | Total PO amount |
| TOTAL_AMT_RECVD | decimal(23,8) | Total received amount |
| WAREHOUSE_ID | nvarchar(15) | Default receiving warehouse |
| SHIP_VIA | nvarchar(40) | Shipping method |
| FREE_ON_BOARD | nvarchar(25) | FOB terms |
| CONSIGNMENT | nchar(1) | Default: 'N' |
| TERMS_NET_TYPE/DAYS/DATE | mixed | Payment terms - net |
| TERMS_DISC_TYPE/DAYS/DATE/PERCENT | mixed | Payment terms - discount |
| TERMS_ID | nvarchar(15) | FK to TERMS |
| ENTERED_BY | nvarchar(20) | User who created PO |
| USER_1 .. USER_10 | nvarchar(80) | User-defined fields |

**Key FKs:** VENDOR_ID -> VENDOR, SITE_ID -> SITE, CURRENCY_ID -> CURRENCY, TERMS_ID -> TERMS

### PURC_ORDER_LINE
Line items on a purchase order.

| Column | Type | Notes |
|---|---|---|
| **PURC_ORDER_ID** | nvarchar(15) | **PK (composite)**. FK to PURCHASE_ORDER |
| **LINE_NO** | smallint | **PK (composite)** |
| PART_ID | nvarchar(30) | FK to PART |
| VENDOR_PART_ID | nvarchar(30) | Vendor's part number |
| SERVICE_ID | nvarchar(15) | FK to SERVICE (for service POs) |
| ORDER_QTY | decimal(20,8) | Ordered qty (stocking UM) |
| USER_ORDER_QTY | decimal(20,8) | Ordered qty (purchasing UM) |
| PURCHASE_UM | nvarchar(15) | Purchasing unit of measure |
| UNIT_PRICE | decimal(22,8) | Unit purchase price |
| TRADE_DISC_PERCENT | decimal(6,3) | Trade discount % |
| DESIRED_RECV_DATE | datetime | Line-level receive date |
| PROMISE_DATE | datetime | Line-level promise date |
| LINE_STATUS | nchar(1) | Line status flag |
| PRODUCT_CODE | nvarchar(15) | Product code |
| COMMODITY_CODE | nvarchar(15) | Commodity code |
| TOTAL_RECEIVED_QTY | decimal(20,8) | Total received |
| TOTAL_AMT_RECVD | decimal(23,8) | Total received amount |
| TOTAL_AMT_ORDERED | decimal(23,8) | Total ordered amount |
| ALLOCATED_QTY | decimal(20,8) | Allocated qty |
| FULFILLED_QTY | decimal(20,8) | Fulfilled qty |
| GL_EXPENSE_ACCT_ID | nvarchar(30) | Expense GL account |
| WAREHOUSE_ID | nvarchar(15) | Receiving warehouse |
| SITE_ID | nvarchar(15) | Site for this line |
| USER_1 .. USER_10 | nvarchar(80) | User-defined fields |

**Key FKs:** PURC_ORDER_ID -> PURCHASE_ORDER (cascade delete), PART_ID -> PART, SERVICE_ID -> SERVICE, PURCHASE_UM -> UNITS

### PURC_LINE_DEL
Delivery schedule for each PO line. Tracks expected and actual receipts.

| Column | Type | Notes |
|---|---|---|
| **PURC_ORDER_ID** | nvarchar(15) | **PK (composite)** |
| **PURC_ORDER_LINE_NO** | smallint | **PK (composite)** |
| **DEL_SCHED_LINE_NO** | smallint | **PK (composite)** |
| DESIRED_RECV_DATE | datetime | Expected receive date |
| ACTUAL_RECV_DATE | datetime | Actual receive date |
| ORDER_QTY | decimal(20,8) | Delivery qty (stocking UM) |
| USER_ORDER_QTY | decimal(20,8) | Delivery qty (purchasing UM) |
| RECEIVED_QTY | decimal(20,8) | Received qty |
| RELEASE_NUMBER | nvarchar(30) | Blanket release number |
| WAREHOUSE_ID | nvarchar(15) | Receiving warehouse |
| ALLOCATED_QTY / FULFILLED_QTY | decimal(20,8) | Allocation tracking |

**Key FKs:** (PURC_ORDER_ID, PURC_ORDER_LINE_NO) -> PURC_ORDER_LINE (cascade delete)

---

## 5. Work Orders (Manufacturing)

### WORK_ORDER
Header for production/manufacturing work orders. Uses a 5-part composite key.

| Column | Type | Notes |
|---|---|---|
| **TYPE** | nchar(1) | **PK (composite)**. W=Work Order, M=Master, etc. |
| **BASE_ID** | nvarchar(30) | **PK (composite)**. Work order number |
| **LOT_ID** | nvarchar(3) | **PK (composite)**. Lot segment |
| **SPLIT_ID** | nvarchar(3) | **PK (composite)**. Split segment |
| **SUB_ID** | nvarchar(3) | **PK (composite)**. Sub segment |
| PART_ID | nvarchar(30) | FK to PART. Part being produced |
| DESIRED_QTY | decimal(20,8) | Quantity to produce |
| RECEIVED_QTY | decimal(20,8) | Quantity completed/received |
| STATUS | nchar(1) | Order status |
| CREATE_DATE | datetime | Creation date |
| DESIRED_RLS_DATE | datetime | Desired release date |
| DESIRED_WANT_DATE | datetime | Desired completion date |
| CLOSE_DATE | datetime | Date closed |
| SCHED_START_DATE | datetime | Scheduled start |
| SCHED_FINISH_DATE | datetime | Scheduled finish |
| PRODUCT_CODE | nvarchar(15) | Product code |
| SITE_ID | nvarchar(15) | FK to SITE |
| WAREHOUSE_ID | nvarchar(15) | Output warehouse |
| EST_MATERIAL/LABOR/BURDEN/SERVICE_COST | decimal(23,8) | Estimated costs |
| ACT_MATERIAL/LABOR/BURDEN/SERVICE_COST | decimal(23,8) | Actual costs |
| REM_MATERIAL/LABOR/BURDEN/SERVICE_COST | decimal(23,8) | Remaining costs |
| MAT/LAB/BUR/SER_GL_ACCT_ID | nvarchar(30) | GL accounts |
| DRAWING_ID / DRAWING_REV_NO | nvarchar | Drawing reference |
| ALLOCATED_QTY / FULFILLED_QTY | decimal(20,8) | Allocation tracking |
| USER_1 .. USER_10 | nvarchar(80) | User-defined fields |

**Key FKs:** PART_ID -> PART, SITE_ID -> SITE

### OPERATION
Routing operations (steps) on a work order. Defines the sequence of manufacturing activities.

| Column | Type | Notes |
|---|---|---|
| **WORKORDER_TYPE** | nchar(1) | **PK (composite)** |
| **WORKORDER_BASE_ID** | nvarchar(30) | **PK (composite)** |
| **WORKORDER_LOT_ID** | nvarchar(3) | **PK (composite)** |
| **WORKORDER_SPLIT_ID** | nvarchar(3) | **PK (composite)** |
| **WORKORDER_SUB_ID** | nvarchar(3) | **PK (composite)** |
| **SEQUENCE_NO** | smallint | **PK (composite)**. Operation step number |
| RESOURCE_ID | nvarchar(15) | FK to SHOP_RESOURCE. Work center |
| SETUP_HRS | decimal(8,3) | Estimated setup hours |
| RUN | decimal(20,8) | Run rate value |
| RUN_TYPE | nvarchar(15) | Run type (hrs/pc, pcs/hr, etc.) |
| RUN_HRS | decimal(7,2) | Calculated run hours |
| MOVE_HRS | decimal(6,3) | Move hours to next op |
| STATUS | nchar(1) | Operation status |
| COMPLETED_QTY | decimal(20,8) | Completed qty |
| ACT_SETUP_HRS | decimal(7,2) | Actual setup hours |
| ACT_RUN_HRS | decimal(7,2) | Actual run hours |
| SCHED_START_DATE | datetime | Scheduled start |
| SCHED_FINISH_DATE | datetime | Scheduled finish |
| VENDOR_ID | nvarchar(15) | Outside service vendor |
| SERVICE_ID | nvarchar(15) | Outside service ID |
| SETUP/RUN_COST_PER_HR | decimal(22,8) | Labor rates |
| BUR_PER_HR_SETUP/RUN | decimal(22,8) | Burden rates |
| EST/REM/ACT_ATL_LAB/BUR/SER_COST | decimal(23,8) | Cost tracking (at-this-level) |
| EST/REM/ACT_TTL_MAT/LAB/BUR/SER_COST | decimal(23,8) | Cost tracking (total) |
| USER_1 .. USER_10 | nvarchar(80) | User-defined fields |

**Key FKs:** (WO 5-part key) -> WORK_ORDER (cascade delete), RESOURCE_ID -> SHOP_RESOURCE, SERVICE_ID -> SERVICE

### REQUIREMENT
Material requirements (BOM) for each work order operation.

| Column | Type | Notes |
|---|---|---|
| **WORKORDER_TYPE** | nchar(1) | **PK (composite)** |
| **WORKORDER_BASE_ID** | nvarchar(30) | **PK (composite)** |
| **WORKORDER_LOT_ID** | nvarchar(3) | **PK (composite)** |
| **WORKORDER_SPLIT_ID** | nvarchar(3) | **PK (composite)** |
| **WORKORDER_SUB_ID** | nvarchar(3) | **PK (composite)** |
| **OPERATION_SEQ_NO** | smallint | **PK (composite)**. Links to OPERATION |
| **PIECE_NO** | smallint | **PK (composite)**. Line within operation |
| PART_ID | nvarchar(30) | FK to PART. Required material |
| STATUS | nchar(1) | Requirement status |
| QTY_PER | decimal(20,8) | Quantity per parent |
| QTY_PER_TYPE | nchar(1) | Per-unit or fixed |
| FIXED_QTY | decimal(20,8) | Fixed quantity |
| SCRAP_PERCENT | decimal(5,2) | Scrap allowance % |
| USAGE_UM | nvarchar(15) | Unit of measure |
| CALC_QTY | decimal(20,8) | Calculated total requirement |
| ISSUED_QTY | decimal(20,8) | Actually issued qty |
| REQUIRED_DATE | datetime | Date material needed |
| UNIT_MATERIAL/LABOR/BURDEN/SERVICE_COST | decimal(22,8) | Unit costs |
| EST/REM/ACT_MATERIAL/LABOR/BURDEN/SERVICE_COST | decimal(23,8) | Cost tracking |
| VENDOR_ID | nvarchar(15) | Vendor for purchased material |
| WAREHOUSE_ID | nvarchar(15) | Issuing warehouse |
| ALLOCATED_QTY / FULFILLED_QTY | decimal(20,8) | Allocation tracking |
| USER_1 .. USER_10 | nvarchar(80) | User-defined fields |

**Key FKs:** (WO 5-part key + SUB_ID) -> WORK_ORDER (cascade delete), PART_ID -> PART, VENDOR_ID -> VENDOR, USAGE_UM -> UNITS

---

## 6. Customer Information

### CUSTOMER
Customer master table.

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(15) | **PK**. Customer number |
| NAME | nvarchar(50) | Customer name |
| ADDR_1 / ADDR_2 / ADDR_3 | nvarchar(50) | Address lines |
| CITY / STATE / ZIPCODE / COUNTRY | nvarchar | Address fields |
| BILL_TO_NAME | nvarchar(50) | Bill-to name |
| BILL_TO_ADDR_1/2/3 / CITY / STATE / ZIPCODE / COUNTRY | nvarchar | Bill-to address |
| CURRENCY_ID | nvarchar(15) | Default currency |
| SALESREP_ID | nvarchar(15) | Default sales rep |
| TERRITORY | nvarchar(15) | Default territory |
| DISCOUNT_CODE | nvarchar(15) | Default discount code |
| DEF_SLS_TAX_GRP_ID | nvarchar(15) | Default tax group |
| FREIGHT_TERMS | nchar(1) | Default freight terms |
| TERMS_NET_TYPE/DAYS/DATE | mixed | Default payment terms |
| TERMS_DISC_TYPE/DAYS/DATE/PERCENT | mixed | Default discount terms |
| TAX_EXEMPT | nchar(1) | Tax exempt flag |
| TAX_ID_NUMBER | nvarchar(25) | Tax ID |
| BACKORDER_FLAG | nchar(1) | Allow backorders |
| CARRIER_ID | nvarchar(15) | Default carrier |
| SHIPTO_ID | nvarchar(20) | Default ship-to |
| ACTIVE_FLAG | nchar(1) | Active/inactive |
| PRIORITY | smallint | Customer priority |
| CUSTOMER_GROUP_ID | nvarchar(15) | Customer group |
| PRICE_GROUP | nvarchar(15) | Price group |
| USER_1 .. USER_10 | nvarchar(80) | User-defined fields |

### CUSTOMER_SITE
Site-level customer configuration. Extends CUSTOMER with site-specific settings.

| Column | Type | Notes |
|---|---|---|
| **SITE_ID** | nvarchar(15) | **PK (composite)**. FK to SITE |
| **CUSTOMER_ID** | nvarchar(15) | **PK (composite)**. FK to CUSTOMER |
| CUSTOMER_TYPE | nvarchar(20) | Customer type at this site |
| WAREHOUSE_ID | nvarchar(15) | Default warehouse |
| ORDER_FILL_RATE | decimal(5,2) | Fill rate target |
| PRIORITY_CODE | nvarchar(15) | Priority at this site |
| AUTO_ALLOCATE | nchar(1) | Auto-allocation flag |

### CUST_ADDRESS
Multiple ship-to addresses per customer.

| Column | Type | Notes |
|---|---|---|
| **CUSTOMER_ID** | nvarchar(15) | **PK (composite)**. FK to CUSTOMER |
| **ADDR_NO** | int | **PK (composite)**. Address sequence |
| SHIPTO_ID | nvarchar(20) | Ship-to identifier |
| NAME / ADDR_1/2/3 / CITY / STATE / ZIPCODE / COUNTRY | nvarchar | Address fields |
| DEF_SLS_TAX_GRP_ID | nvarchar(15) | Tax group for this address |
| SALESREP_ID | nvarchar(15) | Sales rep override |
| TERRITORY | nvarchar(15) | Territory override |
| CARRIER_ID | nvarchar(15) | Carrier override |
| ACTIVE_FLAG | nchar(1) | Default: 'Y' |

### CUSTOMER_CONTACT
Contact records per customer.

| Column | Type | Notes |
|---|---|---|
| **CUSTOMER_ID** | nvarchar(15) | **PK (composite)**. FK to CUSTOMER |
| **CONTACT_NO** | smallint | **PK (composite)** |
| CONTACT_FIRST_NAME / LAST_NAME | nvarchar(30) | Name |
| CONTACT_POSITION | nvarchar(50) | Job title |
| CONTACT_PHONE / FAX / MOBILE / EMAIL | nvarchar | Contact info |

### CUSTOMER_SITE_VIEW
Joins CUSTOMER + CUSTOMER_SITE similar to PART_SITE_VIEW. Use for queries that need customer data with site-specific overrides.

---

## 7. Inventory Traceability

### TRACE
Current inventory trace records (lots, serials). Tracks quantities by trace ID within a part.

| Column | Type | Notes |
|---|---|---|
| **PART_ID** | nvarchar(30) | **PK (composite)**. FK to PART |
| **ID** | nvarchar(30) | **PK (composite)**. Trace ID (lot/serial number) |
| IN_QTY | decimal(20,8) | Total received into this trace |
| OUT_QTY | decimal(20,8) | Total issued out |
| REPORTED_QTY | decimal(20,8) | Qty reported (WIP) |
| ASSIGNED_QTY | decimal(20,8) | Qty assigned to orders |
| COMMITTED_QTY | decimal(20,8) | Committed qty |
| UNAVAILABLE_QTY | decimal(20,8) | Unavailable qty |
| LOT_ID | nvarchar(30) | Lot identifier |
| SERIAL_ID | nvarchar(30) | Serial identifier |
| OWNER_ID | nvarchar(15) | Ownership (consignment) |
| EXPIRATION_DATE | datetime | Expiry date |
| PRODUCTION_DATE | datetime | Production date |
| SHIP_BY_DATE | datetime | Ship-by date |
| APROPERTY_1 .. APROPERTY_5 | nvarchar(80) | Alpha trace properties |
| NPROPERTY_1 .. NPROPERTY_5 | decimal(15,6) | Numeric trace properties |
| COMMENTS | nvarchar(250) | Comments |
| SITE_ID | nvarchar(15) | Site |

### TRACE_HISTORY
Audit trail of changes to trace records.

| Column | Type | Notes |
|---|---|---|
| **PART_ID** | nvarchar(30) | **PK (composite)** |
| **TRACE_ID** | nvarchar(30) | **PK (composite)** |
| **CREATE_DATE** | datetime | **PK (composite)**. When change occurred |
| ORIG_TRACE_ID | nvarchar(30) | Original trace ID (before change) |
| APROPERTY_1..5 / NPROPERTY_1..5 | mixed | Property values at time of change |
| HIST_COMMENTS | nvarchar(250) | Reason for change |
| USER_ID | nvarchar(20) | User who made the change |

### TRACE_INV_TRANS
Links trace records to inventory transactions for full traceability.

| Column | Type | Notes |
|---|---|---|
| **PART_ID** | nvarchar(30) | **PK (composite)** |
| **TRACE_ID** | nvarchar(30) | **PK (composite)** |
| **TRANSACTION_ID** | int | **PK (composite)**. FK to INVENTORY_TRANS |
| QTY | decimal(20,8) | Transaction quantity |
| COSTED_QTY | decimal(20,8) | Costed quantity |

### TRACE_PROFILE
Configuration for how traceability works per part per site. Defines which properties are tracked, required, and visible.

| Column | Type | Notes |
|---|---|---|
| **SITE_ID** | nvarchar(15) | **PK (composite)** |
| **PART_ID** | nvarchar(30) | **PK (composite)** |
| NUMBERING_ID | nvarchar(30) | Auto-numbering scheme |
| APPLY_TO_REC / ISSUE / ADJ / LABOR | nchar(1) | When to apply tracing |
| PRE_ASSIGN / ASSIGN_METHOD | nchar(1) | Assignment behavior |
| OWNERSHIP / LOT / SERIAL / EXPIRATION | nchar(1) | Which dimensions to track |
| MAX_LOT_QTY | decimal(20,8) | Maximum lot size |
| SHELF_LIFE | smallint | Shelf life (days) |
| APROPERTY_LABEL_1..5 | nvarchar(30) | Custom property labels |
| NPROPERTY_LABEL_1..5 | nvarchar(30) | Custom numeric property labels |
| *(plus ~50 columns for _REQD, _EDIT, _VIS, _KNOWN flags per property)* | | |

### TRACE_NUMBERING
Auto-numbering schemes for trace IDs.

| Column | Type | Notes |
|---|---|---|
| **ID** | nvarchar(30) | **PK**. Numbering scheme ID |
| NEXT_NUMBER | decimal(15,0) | Next sequence number |
| ALPHA_PREFIX / ALPHA_SUFFIX | nvarchar(4) | Prefix/suffix |
| DECIMAL_PLACES | smallint | Number of digits (3-15) |
| LEADING_ZEROS | nchar(1) | Pad with leading zeros |

### CY_TRACE_AUDIT
Custom audit table for trace-related issues/events.

| Column | Type | Notes |
|---|---|---|
| **audit_id** | int | **PK**. Identity |
| trace_id | varchar(50) | Unique. Trace ID being audited |
| part_id | varchar(50) | Part ID |
| order_id | varchar(50) | Related order |
| line_no | int | Related line number |
| reason | varchar(100) | Audit reason |
| reported_by | varchar(50) | Who reported it |
| reported_date | datetime | When reported |

---

## Common Patterns

- **Status codes** are typically single-char nchar(1) fields. Common values vary by table but generally follow VISUAL conventions (e.g., 'F' = Firm, 'R' = Released, 'C' = Closed).
- **USER_1 through USER_10** fields exist on most major tables for custom/user-defined data.
- **SITE_ID** appears on most transactional tables; VECA is a multi-site system.
- **_VIEW tables** (PART_SITE_VIEW, CUSTOMER_SITE_VIEW, etc.) merge the base table with its site-specific override table using ISNULL() logic. Always prefer the view over joining manually.
- **Work Order keys** are 5-part composite: TYPE + BASE_ID + LOT_ID + SPLIT_ID + SUB_ID. All child tables (OPERATION, REQUIREMENT) carry this full key.
- **Delivery schedules** (CUST_LINE_DEL, PURC_LINE_DEL) are children of order lines, tracking multiple planned/actual ship or receive dates per line.
- **PRODUCT_CODE** on PART/PART_SITE references the PRODUCT table's CODE column, which maps to GL account sets for revenue, inventory, variance, COGS, and WIP.
