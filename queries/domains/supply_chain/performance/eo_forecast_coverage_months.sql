/*
===============================================================================
Query Name: eo_forecast_coverage_months.sql

Purpose:
    Forward-looking excess & obsolescence forecast driven by months-of-cover.

    Where historical_E&O_basis.sql buckets parts by trailing annual turns,
    this query projects E&O risk by combining:
        * current on-hand
        * inbound open supply (open PO + planned)
        * trailing-window average monthly usage (6 mo and 12 mo)
        * open customer-order demand (forward demand signal)

    The result is a "months of coverage" number per part that can be
    bucketed into HEALTHY / EXCESS / OBSOLETE_TREND, and a projected
    E&O dollar value at the part's standard cost.

Grain:
    One row per (SITE_ID, PART_ID) that has inventory or usage history.

Key calculations:
    avg_monthly_usage_12m   = issues_last_360d / 12
    avg_monthly_usage_6m    = issues_last_180d / 6
    blended_monthly_demand  = greatest of
                                (avg_monthly_usage_6m,
                                 avg_monthly_usage_12m,
                                 open_so_monthly_run_rate)
                              -- use the most recent / demanding signal

    months_of_cover         = (qty_on_hand + open_supply_qty)
                              / NULLIF(blended_monthly_demand, 0)

    projected_eo_value      = standard_cost *
                                MAX(0,
                                    qty_on_hand + open_supply_qty
                                    - blended_monthly_demand * @CoverTargetMonths)

Bucketing (tunable via @Target / @Excess / @Obsolete thresholds):
    OBSOLETE_TREND   : no usage in trailing 360 days AND qty_on_hand > 0
    EXCESS_DEEP      : months_of_cover > @ObsoleteCoverMonths (default 24)
    EXCESS           : months_of_cover > @ExcessCoverMonths (default 12)
    HEALTHY          : between @TargetCoverMonths (3) and @ExcessCoverMonths
    AT_RISK          : months_of_cover < @TargetCoverMonths
    STOCK_OUT        : months_of_cover = 0 with demand > 0

Business Use:
    - Proactive E&O review (find what will be excess before it gets old)
    - Sizing write-down reserves
    - Pairs with buyer / planner scorecards to hold owners accountable
    - Buy-plan input: AT_RISK parts flag future PO needs

Notes / Assumptions:
    - "Issues" = INVENTORY_TRANS TYPE='O' AND CLASS='I' (stockroom issues).
      Matches the convention in historical_E&O_basis.sql.
    - Open supply qty is normalized to stock UOM using the conversion
      hierarchy (part-specific -> default -> 1.0).
    - Standard cost = sum of unit material/labor/burden/service costs
      from PART_SITE_VIEW.
    - Not BOM-aware: component-level future demand from exploded WOs
      is represented only through existing open requirements (via the
      issues history, which already reflects past usage patterns).
    - Does not subtract allocated/committed; uses simple qty_on_hand
      from PART_SITE_VIEW.

Potential Enhancements:
    - Add 3-month and 24-month usage averages for stability signals
    - Split by buyer / planner so the table can be assigned to an owner
    - Add a "last_issue_date" staleness column for obsolete detection
    - Project forward to a specific target date using PLANNING_LEADTIME
===============================================================================
*/

DECLARE @Site               nvarchar(15)  = NULL;
DECLARE @AsOfDate           datetime      = GETDATE();
DECLARE @TargetCoverMonths  decimal(10,2) = 3.0;
DECLARE @ExcessCoverMonths  decimal(10,2) = 12.0;
DECLARE @ObsoleteCoverMonths decimal(10,2) = 24.0;

;WITH part_site AS (
    SELECT
        psv.SITE_ID,
        psv.PART_ID,
        psv.DESCRIPTION,
        psv.STOCK_UM,
        psv.PRODUCT_CODE,
        psv.COMMODITY_CODE,
        psv.PURCHASED,
        psv.FABRICATED,
        psv.STOCKED,
        psv.ABC_CODE,
        psv.BUYER_USER_ID,
        psv.PLANNER_USER_ID,
        psv.PLANNING_LEADTIME,
        COALESCE(psv.QTY_ON_HAND, 0) AS qty_on_hand,
        COALESCE(psv.SAFETY_STOCK_QTY, 0) AS safety_stock,
        (psv.UNIT_MATERIAL_COST
         + psv.UNIT_LABOR_COST
         + psv.UNIT_BURDEN_COST
         + psv.UNIT_SERVICE_COST) AS std_unit_cost
    FROM PART_SITE_VIEW psv
    WHERE (@Site IS NULL OR psv.SITE_ID = @Site)
),

usage AS (
    SELECT
        it.SITE_ID,
        it.PART_ID,
        SUM(CASE WHEN it.TRANSACTION_DATE >= DATEADD(day,  -90, @AsOfDate)
                 THEN it.QTY ELSE 0 END) AS issues_90d,
        SUM(CASE WHEN it.TRANSACTION_DATE >= DATEADD(day, -180, @AsOfDate)
                 THEN it.QTY ELSE 0 END) AS issues_180d,
        SUM(CASE WHEN it.TRANSACTION_DATE >= DATEADD(day, -360, @AsOfDate)
                 THEN it.QTY ELSE 0 END) AS issues_360d,
        MAX(it.TRANSACTION_DATE)        AS last_issue_date
    FROM INVENTORY_TRANS it
    WHERE it.TYPE  = 'O'
      AND it.CLASS = 'I'
      AND it.PART_ID IS NOT NULL
      AND (@Site IS NULL OR it.SITE_ID = @Site)
    GROUP BY it.SITE_ID, it.PART_ID
),

open_supply AS (
    SELECT
        p.SITE_ID,
        pl.PART_ID,
        SUM(
            (pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY) *
            CASE
                WHEN pl.PURCHASE_UM = ps.STOCK_UM      THEN 1.0
                WHEN puc.CONVERSION_FACTOR IS NOT NULL THEN puc.CONVERSION_FACTOR
                WHEN duc.CONVERSION_FACTOR IS NOT NULL THEN duc.CONVERSION_FACTOR
                ELSE 1.0
            END
        ) AS open_po_qty
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl
        ON pl.PURC_ORDER_ID = p.ID
    LEFT JOIN part_site ps
        ON ps.SITE_ID = p.SITE_ID
       AND ps.PART_ID = pl.PART_ID
    LEFT JOIN PART_UNITS_CONV puc
        ON puc.PART_ID = pl.PART_ID
       AND puc.FROM_UM = pl.PURCHASE_UM
       AND puc.TO_UM   = ps.STOCK_UM
    LEFT JOIN UNITS_CONVERSION duc
        ON duc.FROM_UM = pl.PURCHASE_UM
       AND duc.TO_UM   = ps.STOCK_UM
    WHERE ISNULL(p.STATUS, '')       NOT IN ('X','C')
      AND ISNULL(pl.LINE_STATUS, '') NOT IN ('X','C')
      AND pl.ORDER_QTY > pl.TOTAL_RECEIVED_QTY
      AND pl.PART_ID IS NOT NULL
      AND (@Site IS NULL OR p.SITE_ID = @Site)
    GROUP BY p.SITE_ID, pl.PART_ID
),

planned AS (
    SELECT
        po.SITE_ID,
        po.PART_ID,
        SUM(po.ORDER_QTY) AS planned_qty
    FROM PLANNED_ORDER po
    WHERE (@Site IS NULL OR po.SITE_ID = @Site)
    GROUP BY po.SITE_ID, po.PART_ID
),

-- Forward SO demand, expressed as monthly run-rate against @AsOfDate
so_demand AS (
    SELECT
        col.SITE_ID,
        col.PART_ID,
        SUM(col.ORDER_QTY - col.TOTAL_SHIPPED_QTY) AS open_so_qty,
        -- Spread over the window from today to the latest desired ship date
        -- (in months), bounded to >= 1 month.
        CASE
            WHEN MAX(col.DESIRED_SHIP_DATE) > @AsOfDate
            THEN SUM(col.ORDER_QTY - col.TOTAL_SHIPPED_QTY)
                 / NULLIF(
                     CAST(DATEDIFF(day, @AsOfDate, MAX(col.DESIRED_SHIP_DATE))
                          AS decimal(10,2)) / 30.0, 0)
            ELSE SUM(col.ORDER_QTY - col.TOTAL_SHIPPED_QTY)
        END AS so_monthly_run_rate
    FROM CUST_ORDER_LINE col
    INNER JOIN CUSTOMER_ORDER co
        ON co.ID = col.CUST_ORDER_ID
    -- Canonical open-order filter (see so_header_and_lines_open_orders.sql):
    -- header STATUS IN ('R','F') and line LINE_STATUS = 'A'.
    WHERE co.STATUS IN ('R', 'F')
      AND col.LINE_STATUS = 'A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
      AND (@Site IS NULL OR col.SITE_ID = @Site)
    GROUP BY col.SITE_ID, col.PART_ID
),

base AS (
    SELECT
        ps.SITE_ID,
        ps.PART_ID,
        ps.DESCRIPTION,
        ps.STOCK_UM,
        ps.PRODUCT_CODE,
        ps.COMMODITY_CODE,
        ps.PURCHASED,
        ps.FABRICATED,
        ps.STOCKED,
        ps.ABC_CODE,
        ps.BUYER_USER_ID,
        ps.PLANNER_USER_ID,
        ps.PLANNING_LEADTIME,
        ps.std_unit_cost,

        ps.qty_on_hand,
        ps.safety_stock,

        COALESCE(u.issues_90d,  0) AS issues_90d,
        COALESCE(u.issues_180d, 0) AS issues_180d,
        COALESCE(u.issues_360d, 0) AS issues_360d,
        u.last_issue_date,

        COALESCE(u.issues_180d, 0) / 6.0  AS avg_monthly_usage_6m,
        COALESCE(u.issues_360d, 0) / 12.0 AS avg_monthly_usage_12m,

        COALESCE(os.open_po_qty, 0)       AS open_po_qty,
        COALESCE(pl.planned_qty, 0)       AS planned_qty,
        (ps.qty_on_hand
         + COALESCE(os.open_po_qty, 0)
         + COALESCE(pl.planned_qty, 0))   AS projected_supply,

        COALESCE(sd.open_so_qty, 0)              AS open_so_qty,
        COALESCE(sd.so_monthly_run_rate, 0)      AS so_monthly_run_rate
    FROM part_site ps
    LEFT JOIN usage       u  ON u.SITE_ID  = ps.SITE_ID AND u.PART_ID  = ps.PART_ID
    LEFT JOIN open_supply os ON os.SITE_ID = ps.SITE_ID AND os.PART_ID = ps.PART_ID
    LEFT JOIN planned     pl ON pl.SITE_ID = ps.SITE_ID AND pl.PART_ID = ps.PART_ID
    LEFT JOIN so_demand   sd ON sd.SITE_ID = ps.SITE_ID AND sd.PART_ID = ps.PART_ID
    WHERE ps.qty_on_hand > 0
       OR COALESCE(u.issues_360d, 0) > 0
       OR COALESCE(os.open_po_qty, 0) > 0
       OR COALESCE(sd.open_so_qty, 0) > 0
),

calc AS (
    SELECT
        b.*,
        -- Blended demand: take the most demanding of recent usage / SO signal
        CASE
            WHEN b.avg_monthly_usage_6m  >= b.avg_monthly_usage_12m
             AND b.avg_monthly_usage_6m  >= b.so_monthly_run_rate
                THEN b.avg_monthly_usage_6m
            WHEN b.avg_monthly_usage_12m >= b.so_monthly_run_rate
                THEN b.avg_monthly_usage_12m
            ELSE b.so_monthly_run_rate
        END AS blended_monthly_demand
    FROM base b
)

SELECT
    c.SITE_ID,
    c.PART_ID,
    c.DESCRIPTION,
    c.PRODUCT_CODE,
    c.COMMODITY_CODE,
    c.PURCHASED,
    c.FABRICATED,
    c.STOCKED,
    c.ABC_CODE,
    c.BUYER_USER_ID,
    c.PLANNER_USER_ID,
    c.PLANNING_LEADTIME,

    c.STOCK_UM,
    c.std_unit_cost,
    c.qty_on_hand,
    c.safety_stock,

    c.issues_90d,
    c.issues_180d,
    c.issues_360d,
    c.last_issue_date,
    DATEDIFF(day, c.last_issue_date, @AsOfDate) AS days_since_last_issue,

    CAST(c.avg_monthly_usage_6m  AS decimal(20,4)) AS avg_monthly_usage_6m,
    CAST(c.avg_monthly_usage_12m AS decimal(20,4)) AS avg_monthly_usage_12m,
    CAST(c.so_monthly_run_rate   AS decimal(20,4)) AS so_monthly_run_rate,
    CAST(c.blended_monthly_demand AS decimal(20,4)) AS blended_monthly_demand,

    c.open_po_qty,
    c.planned_qty,
    c.projected_supply,
    c.open_so_qty,

    CAST(c.qty_on_hand / NULLIF(c.blended_monthly_demand, 0)
         AS decimal(10,2))                                         AS months_of_cover_on_hand,
    CAST(c.projected_supply / NULLIF(c.blended_monthly_demand, 0)
         AS decimal(10,2))                                         AS months_of_cover_total,

    -- Same coverage expressed in weeks so the team can present in either
    -- unit without re-deriving (52/12 ≈ 4.333 weeks per month).
    CAST(52.0 / 12.0 * c.qty_on_hand / NULLIF(c.blended_monthly_demand, 0)
         AS decimal(10,2))                                         AS weeks_of_cover_on_hand,
    CAST(52.0 / 12.0 * c.projected_supply / NULLIF(c.blended_monthly_demand, 0)
         AS decimal(10,2))                                         AS weeks_of_cover_total,

    -- Inventory value at standard cost
    CAST(c.qty_on_hand * c.std_unit_cost
         AS decimal(23,2))                                         AS on_hand_value_at_std,

    -- Projected excess at the @TargetCoverMonths horizon
    CAST(
        CASE
            WHEN c.projected_supply
                 - (c.blended_monthly_demand * @TargetCoverMonths) > 0
            THEN (c.projected_supply
                  - (c.blended_monthly_demand * @TargetCoverMonths))
                 * c.std_unit_cost
            ELSE 0
        END
    AS decimal(23,2))                                              AS projected_excess_value_at_target,

    -- Classification
    CASE
        WHEN c.issues_360d = 0 AND c.qty_on_hand > 0
                                                                    THEN 'OBSOLETE_TREND'
        WHEN c.blended_monthly_demand = 0 AND c.qty_on_hand > 0
                                                                    THEN 'NO_DEMAND_SIGNAL'
        WHEN c.qty_on_hand / NULLIF(c.blended_monthly_demand, 0)
               > @ObsoleteCoverMonths                                THEN 'EXCESS_DEEP'
        WHEN c.qty_on_hand / NULLIF(c.blended_monthly_demand, 0)
               > @ExcessCoverMonths                                  THEN 'EXCESS'
        WHEN c.qty_on_hand / NULLIF(c.blended_monthly_demand, 0)
               >= @TargetCoverMonths                                 THEN 'HEALTHY'
        WHEN c.blended_monthly_demand > 0 AND c.qty_on_hand = 0
             AND c.projected_supply = 0                              THEN 'STOCK_OUT'
        WHEN c.qty_on_hand / NULLIF(c.blended_monthly_demand, 0)
               < @TargetCoverMonths                                  THEN 'AT_RISK'
        ELSE                                                              'REVIEW'
    END                                                            AS coverage_bucket
FROM calc c
ORDER BY
    CASE
        WHEN c.issues_360d = 0 AND c.qty_on_hand > 0 THEN 1
        WHEN c.qty_on_hand / NULLIF(c.blended_monthly_demand, 0)
             > @ObsoleteCoverMonths                   THEN 2
        WHEN c.qty_on_hand / NULLIF(c.blended_monthly_demand, 0)
             > @ExcessCoverMonths                     THEN 3
        ELSE 4
    END,
    c.qty_on_hand * c.std_unit_cost DESC;
