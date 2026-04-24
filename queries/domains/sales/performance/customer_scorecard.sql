/*
===============================================================================
Query Name: customer_scorecard.sql

Purpose:
    Per-customer commercial scorecard combining revenue trend, margin,
    order cadence, open backlog, and service level.

    The one-page "know thy customer" view for account reviews.

Grain:
    One row per (SITE_ID, CUSTOMER_ID) with activity in the trailing
    window or a prior window.

Windows:
    Current  = @FromDate       -> @ToDate         (default: trailing 365 days)
    Prior    = @PriorFromDate  -> @PriorToDate    (same length, immediately before)

Metrics:
    Revenue:
        ship_revenue_cur       - SHIPPER_LINE * (1 - disc%) in current window
        ship_revenue_prior     - same, prior window
        revenue_growth_pct     - ((cur - prior) / prior) * 100

    Orders:
        orders_booked_cur      - count of CUSTOMER_ORDERs with ORDER_DATE in window
        avg_order_value_cur    - bookings / orders
        first_order_date       - when did the customer first appear
        last_order_date        - most recent order

    Backlog:
        open_backlog_value     - open SO lines valued at unit_price net of discount
        past_due_backlog_value - subset of open backlog where target_ship_date < @AsOfDate

    Margin:
        std_margin_amount      - ship_revenue - shipped_qty * std_unit_cost
        std_margin_pct         - margin / revenue

    Service:
        ship_lines             - count of shipped lines in current window
        otd_pct_by_revenue     - % of revenue that shipped on or before target

Notes / Assumptions:
    - Revenue is net of trade discount, NOT net of returns. If SHIPPER
      rows carry negative USER_SHIPPED_QTY for returns, they are
      incorporated naturally. Filter if you want gross-only.
    - Margin uses PART_SITE_VIEW standard cost (material+labor+burden+service).
    - Excludes voided shipments (STATUS not in 'X','V') and cancelled
      orders (STATUS not in 'X','V').

Potential Enhancements:
    - Add customer_group rollup for parent-customer view
    - Add product_code mix to show diversification
    - Add trailing 3-month vs trailing 12-month comparison for recency signal
    - Join to CUSTOMER_SITE for credit_limit / credit_hold flags
===============================================================================
*/

DECLARE @Site             nvarchar(15) = NULL;
DECLARE @AsOfDate         datetime     = GETDATE();
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

-- Shipments (current)
ship_cur AS (
    SELECT
        s.SITE_ID,
        co.CUSTOMER_ID,
        s.PACKLIST_ID,
        col.LINE_NO,
        col.PART_ID,
        s.SHIPPED_DATE,
        sl.USER_SHIPPED_QTY,
        (sl.USER_SHIPPED_QTY * sl.UNIT_PRICE
         * (100.0 - COALESCE(sl.TRADE_DISC_PERCENT, 0)) / 100.0) AS ship_revenue,
        (sl.USER_SHIPPED_QTY * COALESCE(pc.std_unit_cost, 0))     AS std_cost_value,
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
      AND (@Site IS NULL OR s.SITE_ID = @Site)
),

ship_prior AS (
    SELECT
        s.SITE_ID,
        co.CUSTOMER_ID,
        (sl.USER_SHIPPED_QTY * sl.UNIT_PRICE
         * (100.0 - COALESCE(sl.TRADE_DISC_PERCENT, 0)) / 100.0) AS ship_revenue
    FROM SHIPPER s
    INNER JOIN SHIPPER_LINE sl
        ON sl.PACKLIST_ID = s.PACKLIST_ID
    INNER JOIN CUSTOMER_ORDER co
        ON co.ID = s.CUST_ORDER_ID
    WHERE s.SHIPPED_DATE >= @PriorFromDate
      AND s.SHIPPED_DATE <  @PriorToDate
      AND ISNULL(s.STATUS, '') NOT IN ('X','V')
      AND (@Site IS NULL OR s.SITE_ID = @Site)
),

-- Bookings (current)
book_cur AS (
    SELECT
        co.SITE_ID,
        co.CUSTOMER_ID,
        co.ID AS co_id,
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

-- Open backlog (point in time)
backlog AS (
    SELECT
        co.SITE_ID,
        co.CUSTOMER_ID,
        col.CUST_ORDER_ID,
        col.LINE_NO,
        (col.ORDER_QTY - col.TOTAL_SHIPPED_QTY)                         AS open_qty,
        (col.ORDER_QTY - col.TOTAL_SHIPPED_QTY) * col.UNIT_PRICE
          * (100.0 - COALESCE(col.TRADE_DISC_PERCENT, 0)) / 100.0       AS open_value,
        COALESCE(
            col.PROMISE_DATE,
            col.DESIRED_SHIP_DATE,
            co.PROMISE_DATE,
            co.DESIRED_SHIP_DATE
        ) AS target_ship_date
    FROM CUSTOMER_ORDER co
    INNER JOIN CUST_ORDER_LINE col
        ON col.CUST_ORDER_ID = co.ID
    -- Open-backlog filter must match the canonical open-order definition
    -- (so_header_and_lines_open_orders.sql): header STATUS IN ('R','F')
    -- and line LINE_STATUS = 'A'. Using NOT IN ('X') was wrong because
    -- closed orders (STATUS='C') still carry ORDER_QTY > TOTAL_SHIPPED_QTY
    -- when closed short.
    WHERE co.STATUS IN ('R', 'F')
      AND col.LINE_STATUS = 'A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
      AND (@Site IS NULL OR co.SITE_ID = @Site)
),

-- Lifetime first/last order for recency
order_history AS (
    SELECT
        co.SITE_ID,
        co.CUSTOMER_ID,
        MIN(co.ORDER_DATE) AS first_order_date,
        MAX(co.ORDER_DATE) AS last_order_date
    FROM CUSTOMER_ORDER co
    WHERE ISNULL(co.STATUS, '') NOT IN ('X','V')
      AND (@Site IS NULL OR co.SITE_ID = @Site)
    GROUP BY co.SITE_ID, co.CUSTOMER_ID
),

-- Aggregations
ship_cur_agg AS (
    SELECT
        SITE_ID,
        CUSTOMER_ID,
        COUNT(*)                                   AS ship_lines,
        COUNT(DISTINCT PACKLIST_ID)                AS shipments,
        SUM(USER_SHIPPED_QTY)                      AS shipped_qty,
        SUM(ship_revenue)                          AS ship_revenue,
        SUM(std_cost_value)                        AS std_cost_value,
        SUM(ship_revenue - std_cost_value)         AS std_margin_amount,
        CAST(100.0 * SUM(ship_revenue - std_cost_value)
             / NULLIF(SUM(ship_revenue), 0)
             AS decimal(5,2))                      AS std_margin_pct,
        SUM(CASE WHEN SHIPPED_DATE <= target_ship_date THEN ship_revenue ELSE 0 END)
                                                   AS on_time_revenue,
        CAST(100.0 * SUM(CASE WHEN SHIPPED_DATE <= target_ship_date
                              THEN ship_revenue ELSE 0 END)
             / NULLIF(SUM(ship_revenue), 0)
             AS decimal(5,2))                      AS otd_pct_by_revenue
    FROM ship_cur
    GROUP BY SITE_ID, CUSTOMER_ID
),

ship_prior_agg AS (
    SELECT
        SITE_ID,
        CUSTOMER_ID,
        SUM(ship_revenue) AS ship_revenue_prior
    FROM ship_prior
    GROUP BY SITE_ID, CUSTOMER_ID
),

book_cur_agg AS (
    SELECT
        SITE_ID,
        CUSTOMER_ID,
        COUNT(DISTINCT co_id) AS orders_booked,
        SUM(booking_amount)   AS bookings_amount
    FROM book_cur
    GROUP BY SITE_ID, CUSTOMER_ID
),

backlog_agg AS (
    SELECT
        SITE_ID,
        CUSTOMER_ID,
        COUNT(*)                                        AS open_backlog_lines,
        SUM(open_value)                                 AS open_backlog_value,
        SUM(CASE WHEN target_ship_date < @AsOfDate
                 THEN open_value ELSE 0 END)            AS past_due_backlog_value,
        SUM(CASE WHEN target_ship_date < @AsOfDate
                 THEN 1 ELSE 0 END)                     AS past_due_backlog_lines
    FROM backlog
    GROUP BY SITE_ID, CUSTOMER_ID
),

all_customers AS (
    SELECT SITE_ID, CUSTOMER_ID FROM ship_cur_agg
    UNION
    SELECT SITE_ID, CUSTOMER_ID FROM book_cur_agg
    UNION
    SELECT SITE_ID, CUSTOMER_ID FROM backlog_agg
    UNION
    SELECT SITE_ID, CUSTOMER_ID FROM ship_prior_agg
)

SELECT
    ac.SITE_ID,
    ac.CUSTOMER_ID,
    c.NAME                                        AS customer_name,
    c.TERRITORY,
    c.SALESREP_ID,
    c.CUSTOMER_GROUP_ID,

    -- Revenue
    COALESCE(sca.ship_revenue, 0)                 AS ship_revenue_cur,
    COALESCE(spa.ship_revenue_prior, 0)           AS ship_revenue_prior,
    CAST(
        CASE WHEN COALESCE(spa.ship_revenue_prior, 0) > 0
             THEN (COALESCE(sca.ship_revenue, 0) - spa.ship_revenue_prior)
                  / spa.ship_revenue_prior * 100.0
             ELSE NULL
        END
    AS decimal(7,2))                              AS revenue_growth_pct,

    -- Margin
    COALESCE(sca.std_cost_value,    0)            AS std_cost_value,
    COALESCE(sca.std_margin_amount, 0)            AS std_margin_amount,
    sca.std_margin_pct,

    -- Orders
    COALESCE(bca.orders_booked,     0)            AS orders_booked_cur,
    COALESCE(bca.bookings_amount,   0)            AS bookings_amount_cur,
    CAST(COALESCE(bca.bookings_amount, 0)
         / NULLIF(bca.orders_booked, 0)
        AS decimal(23,2))                         AS avg_order_value_cur,

    COALESCE(sca.ship_lines, 0)                   AS ship_lines,
    COALESCE(sca.shipments,  0)                   AS shipments,
    COALESCE(sca.shipped_qty, 0)                  AS shipped_qty,

    -- Service
    sca.otd_pct_by_revenue,

    -- Backlog
    COALESCE(ba.open_backlog_lines,   0)          AS open_backlog_lines,
    COALESCE(ba.open_backlog_value,   0)          AS open_backlog_value,
    COALESCE(ba.past_due_backlog_lines, 0)        AS past_due_backlog_lines,
    COALESCE(ba.past_due_backlog_value, 0)        AS past_due_backlog_value,

    -- Recency
    oh.first_order_date,
    oh.last_order_date,
    DATEDIFF(day, oh.last_order_date, @AsOfDate)  AS days_since_last_order,

    -- Segment
    CASE
        WHEN COALESCE(sca.ship_revenue, 0) = 0
         AND COALESCE(spa.ship_revenue_prior, 0) > 0                          THEN 'CHURNED'
        WHEN oh.first_order_date >= @FromDate                                  THEN 'NEW'
        WHEN COALESCE(sca.ship_revenue, 0) > COALESCE(spa.ship_revenue_prior, 0) * 1.10
                                                                              THEN 'GROWING'
        WHEN COALESCE(sca.ship_revenue, 0) < COALESCE(spa.ship_revenue_prior, 0) * 0.90
                                                                              THEN 'DECLINING'
        ELSE                                                                        'STABLE'
    END                                           AS segment
FROM all_customers ac
LEFT JOIN CUSTOMER c
    ON c.ID = ac.CUSTOMER_ID
LEFT JOIN ship_cur_agg   sca ON sca.SITE_ID = ac.SITE_ID AND sca.CUSTOMER_ID = ac.CUSTOMER_ID
LEFT JOIN ship_prior_agg spa ON spa.SITE_ID = ac.SITE_ID AND spa.CUSTOMER_ID = ac.CUSTOMER_ID
LEFT JOIN book_cur_agg   bca ON bca.SITE_ID = ac.SITE_ID AND bca.CUSTOMER_ID = ac.CUSTOMER_ID
LEFT JOIN backlog_agg    ba  ON ba.SITE_ID  = ac.SITE_ID AND ba.CUSTOMER_ID  = ac.CUSTOMER_ID
LEFT JOIN order_history  oh  ON oh.SITE_ID  = ac.SITE_ID AND oh.CUSTOMER_ID  = ac.CUSTOMER_ID
ORDER BY
    COALESCE(sca.ship_revenue, 0) DESC,
    COALESCE(ba.open_backlog_value, 0) DESC;
