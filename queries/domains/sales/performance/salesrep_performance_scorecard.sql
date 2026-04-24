/*
===============================================================================
Query Name: salesrep_performance_scorecard.sql

Purpose:
    Per-sales-rep activity, revenue, margin, and discipline scorecard.

Business Use:
    - Monthly / quarterly sales ops review
    - Commissions QA (actuals vs plan)
    - Spot the reps who discount heavily vs those holding price
    - Identify reps owning at-risk accounts (late shipments, closed short)
    - Find inactivity (reps with flat or declining bookings)

Grain:
    One row per (SITE_ID, SALESREP_ID) for the evaluation window.

Bookings vs Shipments:
    * Bookings = CUSTOMER_ORDER.ORDER_DATE inside window
                 (what the rep sold)
    * Shipments = SHIPPER.SHIPPED_DATE inside window
                  (what actually went out the door / recognized revenue)

Margin:
    Approximated at PART_SITE_VIEW standard cost:
        margin$ = ship_revenue
                 - (user_shipped_qty * std_unit_cost)
    This is a simplification; for actual posted margin use GL tables.

Window:
    @FromDate / @ToDate default to trailing 365 days. Prior-period is the
    matching window immediately before for growth comparison.

Notes / Assumptions:
    - Salesrep attribution uses CUSTOMER_ORDER.SALESREP_ID (order header).
      Line-level overrides are not considered.
    - Excludes voided shipments (SHIPPER.STATUS not in 'X','V').
    - Excludes cancelled orders (CUSTOMER_ORDER.STATUS not in 'X','V').
    - avg_discount_pct is revenue-weighted across shipped lines.

Potential Enhancements:
    - Pull human name from SYS_USER or SALESREP master (if present)
    - Split by product_code / commodity_code to show category mix
    - Add booking-to-ship conversion % (how much of what they sold
      actually shipped in the window)
===============================================================================
*/

DECLARE @Site             nvarchar(15) = NULL;
DECLARE @FromDate         datetime     = DATEADD(day, -365, GETDATE());
DECLARE @ToDate           datetime     = GETDATE();

DECLARE @PriorFromDate    datetime     = DATEADD(day, DATEDIFF(day, @ToDate, @FromDate), @FromDate);
DECLARE @PriorToDate      datetime     = @FromDate;

;WITH part_cost AS (
    SELECT
        psv.SITE_ID,
        psv.PART_ID,
        (psv.UNIT_MATERIAL_COST
         + psv.UNIT_LABOR_COST
         + psv.UNIT_BURDEN_COST
         + psv.UNIT_SERVICE_COST) AS std_unit_cost
    FROM PART_SITE_VIEW psv
),

bookings_cur AS (
    SELECT
        co.SITE_ID,
        COALESCE(NULLIF(LTRIM(RTRIM(co.SALESREP_ID)), ''), '(unassigned)') AS salesrep_id,
        co.ID                AS co_id,
        co.CUSTOMER_ID,
        col.LINE_NO,
        col.PART_ID,
        col.ORDER_QTY,
        col.UNIT_PRICE,
        COALESCE(col.TRADE_DISC_PERCENT, 0) AS trade_disc_pct,
        (col.ORDER_QTY * col.UNIT_PRICE
         * (100.0 - COALESCE(col.TRADE_DISC_PERCENT, 0)) / 100.0) AS booking_amount
    FROM CUSTOMER_ORDER co
    INNER JOIN CUST_ORDER_LINE col
        ON col.CUST_ORDER_ID = co.ID
    WHERE co.ORDER_DATE >= @FromDate
      AND co.ORDER_DATE <  @ToDate
      AND ISNULL(co.STATUS, '')       NOT IN ('X','V')
      AND ISNULL(col.LINE_STATUS, '') NOT IN ('X')
      AND (@Site IS NULL OR co.SITE_ID = @Site)
),

bookings_prior AS (
    SELECT
        co.SITE_ID,
        COALESCE(NULLIF(LTRIM(RTRIM(co.SALESREP_ID)), ''), '(unassigned)') AS salesrep_id,
        (col.ORDER_QTY * col.UNIT_PRICE
         * (100.0 - COALESCE(col.TRADE_DISC_PERCENT, 0)) / 100.0) AS booking_amount,
        co.ID AS co_id
    FROM CUSTOMER_ORDER co
    INNER JOIN CUST_ORDER_LINE col
        ON col.CUST_ORDER_ID = co.ID
    WHERE co.ORDER_DATE >= @PriorFromDate
      AND co.ORDER_DATE <  @PriorToDate
      AND ISNULL(co.STATUS, '')       NOT IN ('X','V')
      AND ISNULL(col.LINE_STATUS, '') NOT IN ('X')
      AND (@Site IS NULL OR co.SITE_ID = @Site)
),

shipped AS (
    SELECT
        s.SITE_ID,
        COALESCE(NULLIF(LTRIM(RTRIM(co.SALESREP_ID)), ''), '(unassigned)') AS salesrep_id,
        co.CUSTOMER_ID,
        s.PACKLIST_ID,
        sl.CUST_ORDER_ID,
        sl.CUST_ORDER_LINE_NO,
        col.PART_ID,
        s.SHIPPED_DATE,
        sl.USER_SHIPPED_QTY,
        sl.UNIT_PRICE,
        COALESCE(sl.TRADE_DISC_PERCENT, 0) AS trade_disc_pct,
        (sl.USER_SHIPPED_QTY * sl.UNIT_PRICE
         * (100.0 - COALESCE(sl.TRADE_DISC_PERCENT, 0)) / 100.0) AS ship_revenue,
        (sl.USER_SHIPPED_QTY * COALESCE(pc.std_unit_cost, 0))     AS std_cost_value,
        -- Line-level on-time flag
        COALESCE(
            col.PROMISE_DATE,
            col.DESIRED_SHIP_DATE,
            co.PROMISE_DATE,
            co.DESIRED_SHIP_DATE
        ) AS target_ship_date
    FROM SHIPPER s
    INNER JOIN SHIPPER_LINE sl
        ON sl.PACKLIST_ID = s.PACKLIST_ID
    INNER JOIN CUSTOMER_ORDER co
        ON co.ID = s.CUST_ORDER_ID
    INNER JOIN CUST_ORDER_LINE col
        ON col.CUST_ORDER_ID = sl.CUST_ORDER_ID
       AND col.LINE_NO       = sl.CUST_ORDER_LINE_NO
    LEFT JOIN part_cost pc
        ON pc.SITE_ID = s.SITE_ID
       AND pc.PART_ID = col.PART_ID
    WHERE s.SHIPPED_DATE >= @FromDate
      AND s.SHIPPED_DATE <  @ToDate
      AND ISNULL(s.STATUS, '') NOT IN ('X','V')
      AND sl.USER_SHIPPED_QTY > 0
      AND (@Site IS NULL OR s.SITE_ID = @Site)
),

book_cur_agg AS (
    SELECT
        SITE_ID,
        salesrep_id,
        COUNT(DISTINCT co_id)     AS orders_booked,
        COUNT(DISTINCT CUSTOMER_ID) AS unique_customers_booked,
        SUM(booking_amount)       AS bookings_amount,
        CAST(AVG(trade_disc_pct) AS decimal(5,2)) AS avg_order_disc_pct
    FROM bookings_cur
    GROUP BY SITE_ID, salesrep_id
),

book_prior_agg AS (
    SELECT
        SITE_ID,
        salesrep_id,
        SUM(booking_amount) AS bookings_amount_prior
    FROM bookings_prior
    GROUP BY SITE_ID, salesrep_id
),

ship_agg AS (
    SELECT
        SITE_ID,
        salesrep_id,
        COUNT(*)                                AS ship_lines,
        COUNT(DISTINCT PACKLIST_ID)             AS shipments,
        COUNT(DISTINCT CUST_ORDER_ID)           AS orders_shipped,
        COUNT(DISTINCT CUSTOMER_ID)             AS unique_customers_shipped,
        SUM(USER_SHIPPED_QTY)                   AS shipped_qty,
        SUM(ship_revenue)                       AS ship_revenue,
        SUM(std_cost_value)                     AS std_cost_value,
        SUM(ship_revenue - std_cost_value)      AS std_margin_amount,
        CAST(
            100.0 * SUM(ship_revenue - std_cost_value)
            / NULLIF(SUM(ship_revenue), 0)
        AS decimal(5,2))                        AS std_margin_pct,

        -- Revenue-weighted avg discount
        CAST(
            SUM(trade_disc_pct * ship_revenue)
            / NULLIF(SUM(ship_revenue), 0)
        AS decimal(5,2))                        AS rev_weighted_disc_pct,

        -- Line-based OTD at ship
        SUM(CASE WHEN SHIPPED_DATE <= target_ship_date THEN 1 ELSE 0 END) AS on_time_ship_lines,
        CAST(
            100.0 * SUM(CASE WHEN SHIPPED_DATE <= target_ship_date
                             THEN ship_revenue ELSE 0 END)
            / NULLIF(SUM(ship_revenue), 0)
        AS decimal(5,2))                        AS otd_pct_by_revenue
    FROM shipped
    GROUP BY SITE_ID, salesrep_id
),

all_reps AS (
    SELECT SITE_ID, salesrep_id FROM book_cur_agg
    UNION
    SELECT SITE_ID, salesrep_id FROM ship_agg
    UNION
    SELECT SITE_ID, salesrep_id FROM book_prior_agg
)

SELECT
    ar.SITE_ID,
    ar.salesrep_id,

    -- Bookings
    COALESCE(bc.orders_booked,            0) AS orders_booked,
    COALESCE(bc.unique_customers_booked,  0) AS unique_customers_booked,
    COALESCE(bc.bookings_amount,          0) AS bookings_amount,
    COALESCE(bp.bookings_amount_prior,    0) AS bookings_amount_prior,
    CAST(
        CASE WHEN COALESCE(bp.bookings_amount_prior, 0) > 0
             THEN (COALESCE(bc.bookings_amount, 0) - bp.bookings_amount_prior)
                  / bp.bookings_amount_prior * 100.0
             ELSE NULL
        END
    AS decimal(7,2))                         AS bookings_growth_pct,
    bc.avg_order_disc_pct,

    -- Shipments (= revenue + margin)
    COALESCE(sa.shipments,                 0) AS shipments,
    COALESCE(sa.orders_shipped,            0) AS orders_shipped,
    COALESCE(sa.unique_customers_shipped,  0) AS unique_customers_shipped,
    COALESCE(sa.ship_lines,                0) AS ship_lines,
    COALESCE(sa.shipped_qty,               0) AS shipped_qty,
    COALESCE(sa.ship_revenue,              0) AS ship_revenue,
    COALESCE(sa.std_cost_value,            0) AS std_cost_value,
    COALESCE(sa.std_margin_amount,         0) AS std_margin_amount,
    sa.std_margin_pct,
    sa.rev_weighted_disc_pct,

    -- Service
    COALESCE(sa.on_time_ship_lines,        0) AS on_time_ship_lines,
    sa.otd_pct_by_revenue,

    -- Attention flag
    CASE
        WHEN COALESCE(sa.std_margin_pct, 100) < 15        THEN 'ATTENTION - margin'
        WHEN COALESCE(sa.otd_pct_by_revenue, 100) < 80    THEN 'ATTENTION - service'
        WHEN COALESCE(bc.bookings_amount, 0) = 0
             AND COALESCE(bp.bookings_amount_prior, 0) > 0 THEN 'ATTENTION - inactive'
        ELSE 'OK'
    END                                      AS flag
FROM all_reps ar
LEFT JOIN book_cur_agg  bc ON bc.SITE_ID = ar.SITE_ID AND bc.salesrep_id = ar.salesrep_id
LEFT JOIN book_prior_agg bp ON bp.SITE_ID = ar.SITE_ID AND bp.salesrep_id = ar.salesrep_id
LEFT JOIN ship_agg      sa ON sa.SITE_ID = ar.SITE_ID AND sa.salesrep_id = ar.salesrep_id
ORDER BY COALESCE(sa.ship_revenue, 0) DESC, COALESCE(bc.bookings_amount, 0) DESC;
