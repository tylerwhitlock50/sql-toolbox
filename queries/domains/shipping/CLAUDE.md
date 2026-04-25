# CLAUDE.md — shipping

**This folder is currently empty.** Placeholder conventions for when queries land here.

## Scope

Fulfillment and logistics queries live here: carrier-level OTD, freight variance, backorder-to-ship pipeline, shipment-line revenue reconciliation. The sales performance folder already covers customer-facing OTD from the shipment-date perspective — use this folder for **logistics/operations** views, not commercial scorecards.

## Expected tables

| Table | Grain | Purpose |
|---|---|---|
| `SHIPPER` | 1 row per packlist / shipment event | `ID`, `PACKLIST_ID`, `CUST_ORDER_ID`, `SHIPPED_DATE`, `SHIP_VIA_ID`, `FREIGHT_TERMS_ID`, `STATUS`, carrier fields |
| `SHIPPER_LINE` | 1 row per item per shipment | `PACKLIST_ID`, `CUST_ORDER_ID`, `CUST_ORDER_LINE_NO`, `PART_ID`, `SHIPPED_QTY`, `USER_SHIPPED_QTY` |
| `SHIP_VIA` | Carrier master | `SHIP_VIA_ID`, name, mode |
| `FREIGHT_TERMS` | FOB master | Freight cost responsibility flag |
| `CUST_LINE_DEL` | Delivery schedule per SO line | `ACTUAL_SHIP_DATE`, `DESIRED_SHIP_DATE` — ties schedule to shipment |

## Canonical joins

**SO → shipment** (must include BOTH CUST_ORDER_ID AND LINE_NO):
```sql
FROM CUSTOMER_ORDER co
INNER JOIN SHIPPER s
    ON co.ID = s.CUST_ORDER_ID
INNER JOIN SHIPPER_LINE sl
    ON sl.PACKLIST_ID = s.PACKLIST_ID
INNER JOIN CUST_ORDER_LINE col
    ON col.CUST_ORDER_ID = sl.CUST_ORDER_ID
   AND col.LINE_NO       = sl.CUST_ORDER_LINE_NO
WHERE ISNULL(s.STATUS, '') NOT IN ('X','V')   -- exclude voided shipments
```

**Always** exclude voided shipments (`STATUS IN ('X','V')`). Joining on `PACKLIST_ID` alone or `CUST_ORDER_ID` alone causes 1:N explosions.

## Open-line-remaining-to-ship filter

Same canonical open-SO filter as `../sales/order_information/`:
```sql
WHERE co.STATUS IN ('R','F')
  AND col.LINE_STATUS = 'A'
  AND col.ORDER_QTY - ISNULL(col.TOTAL_SHIPPED_QTY, 0) > 0
  AND col.PART_ID IS NOT NULL
```

## Quantity semantics

- `SHIPPER_LINE.SHIPPED_QTY` — on-hand impact
- `SHIPPER_LINE.USER_SHIPPED_QTY` — revenue (post-adjustment)
- `CUST_ORDER_LINE.TOTAL_SHIPPED_QTY` — cumulative across all shipments on that line

## Likely queries (not yet written)

- `fulfillment_performance.sql` — shipment-level OTD, carrier / mode breakdown, aging from target ship date
- `carrier_performance.sql` — `SHIP_VIA`-level OTD, claims, damage, transit time
- `freight_cost_allocation.sql` — freight charge per shipment / customer; variance vs quoted / standard
- `open_shipments_and_backlog.sql` — unshipped lines with root-cause tags (WIP, components, scheduling)
- `so_fulfillment_risk.sql` (BOM-aware version) — currently in `sales/order_information/`; might move here if it becomes shipping-owned

## Gotchas when this folder gets populated

- **BOM-upward pegging for sub-assemblies** is nontrivial. Direct `PART_ID` match only covers top-level FG. For true "which SOs are blocked by this sub-assembly" you need a recursive walk.
- **Freight charges and service charges** may live on SO lines with `PART_ID IS NULL`. Standard open-SO filter excludes them — good for inventory pegging, but you may need to include them for freight cost queries.
- **Currency:** `SHIPPER` / `CUSTOMER_ORDER` have currency fields. Normalize upstream if reporting across currencies.
- **Connection to GL postings** — shipments drive revenue recognition in VFIN via the Exchange layer (`LSA`). For revenue-GL reconciliation, queries cross DBs; see `../diagnostics/`.
