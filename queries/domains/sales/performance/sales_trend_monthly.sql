/*
===============================================================================
Query Name: sales_trend_monthly.sql

Purpose:
    Monthly trend of bookings, shipments, and backlog by product_code.
    Shows seasonality, growth, and year-over-year (YoY) change in one
    table that can back a dashboard or spreadsheet.

    Inspired by the original Historical Backlog Query, but condensed
    into a single per-month rollup and extended with YoY comparison.

Grain:
    One row per (SITE_ID, PRODUCT_CODE, month_start) for each month with
    activity. month_start is the first day of the month.

Metrics:
    bookings_qty / bookings_amount
        CUSTOMER_ORDER rows with ORDER_DATE in the month, at list price
        net of trade discount.

    ship_qty / ship_revenue / std_cost / std_margin_amount
        Aligned to SHIPPER.SHIPPED_DATE for the month.

    bookings_amount_prior_year
        Same month a year earlier. Lets you compute YoY deltas without
        a second pivot.

    ship_revenue_prior_year
        Same.

    open_backlog_snapshot_value
        Open (not yet shipped) order value as of end-of-month (EOM)
        for each month. This is the point-in-time backlog curve.
        Approximated as: ordered_amount - shipped_before_EOM.

Windows:
    @FromMonthStart / @ToMonthStart define the reporting range. Defaults
    to trailing 36 months to @AsOfDate.

Notes / Assumptions:
    - Revenue is net of trade discount, not net of returns.
    - Excludes voided shipments and cancelled orders.
    - Margin uses PART_SITE_VIEW standard cost at query time, NOT
      as-of-transaction standard. This is a snapshot approximation.
    - Backlog snapshot treats any order line not shipped by EOM as open;
      it does not respect cancellations that happened after EOM. Good
      enough for trend analysis; for audit-grade backlog, join to a
      point-in-time status table if you have one.

Potential Enhancements:
    - Group by customer_group_id for parent-customer trend
    - Add rolling-12 sum columns
    - Add "first-order" new-customer cohort flag by month
    - Split bookings into new-logo vs repeat using CUSTOMER.OPEN_DATE
===============================================================================
*/

DECLARE @Site            nvarchar(15) = NULL;
DECLARE @AsOfDate        datetime     = GETDATE();
DECLARE @FromMonthStart  datetime     = DATEADD(month, -36, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
DECLARE @ToMonthStart    datetime     = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);

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

-- Monthly bookings
bookings AS (
    SELECT
        co.SITE_ID,
        COALESCE(col.PRODUCT_CODE, '(unknown)')                  AS product_code,
        DATEFROMPARTS(YEAR(co.ORDER_DATE), MONTH(co.ORDER_DATE), 1) AS month_start,
        col.ORDER_QTY                                            AS qty,
        (col.ORDER_QTY * col.UNIT_PRICE
         * (100.0 - COALESCE(col.TRADE_DISC_PERCENT, 0)) / 100.0) AS amount
    FROM CUSTOMER_ORDER co
    INNER JOIN CUST_ORDER_LINE col
        ON col.CUST_ORDER_ID = co.ID
    WHERE co.ORDER_DATE >= @FromMonthStart
      AND co.ORDER_DATE <  DATEADD(month, 1, @ToMonthStart)
      AND ISNULL(co.STATUS, '')       NOT IN ('X','V')
      AND ISNULL(col.LINE_STATUS, '') NOT IN ('X')
      AND (@Site IS NULL OR co.SITE_ID = @Site)
),

-- Same-month-prior-year bookings for YoY, keyed on the CURRENT month
-- so the join is 1:1
bookings_py AS (
    SELECT
        co.SITE_ID,
        COALESCE(col.PRODUCT_CODE, '(unknown)')                         AS product_code,
        DATEADD(year, 1,
            DATEFROMPARTS(YEAR(co.ORDER_DATE), MONTH(co.ORDER_DATE), 1))
                                                                        AS month_start,
        (col.ORDER_QTY * col.UNIT_PRICE
         * (100.0 - COALESCE(col.TRADE_DISC_PERCENT, 0)) / 100.0)        AS amount
    FROM CUSTOMER_ORDER co
    INNER JOIN CUST_ORDER_LINE col
        ON col.CUST_ORDER_ID = co.ID
    WHERE co.ORDER_DATE >= DATEADD(year, -1, @FromMonthStart)
      AND co.ORDER_DATE <  DATEADD(month, 1, @ToMonthStart)
      AND ISNULL(co.STATUS, '')       NOT IN ('X','V')
      AND ISNULL(col.LINE_STATUS, '') NOT IN ('X')
      AND (@Site IS NULL OR co.SITE_ID = @Site)
),

-- Monthly shipments
shipments AS (
    SELECT
        s.SITE_ID,
        COALESCE(col.PRODUCT_CODE, '(unknown)')                  AS product_code,
        DATEFROMPARTS(YEAR(s.SHIPPED_DATE), MONTH(s.SHIPPED_DATE), 1) AS month_start,
        sl.USER_SHIPPED_QTY                                      AS qty,
        (sl.USER_SHIPPED_QTY * sl.UNIT_PRICE
         * (100.0 - COALESCE(sl.TRADE_DISC_PERCENT, 0)) / 100.0)  AS amount,
        (sl.USER_SHIPPED_QTY * COALESCE(pc.std_unit_cost, 0))     AS std_cost_value
    FROM SHIPPER s
    INNER JOIN SHIPPER_LINE sl
        ON sl.PACKLIST_ID = s.PACKLIST_ID
    INNER JOIN CUST_ORDER_LINE col
        ON col.CUST_ORDER_ID = sl.CUST_ORDER_ID
       AND col.LINE_NO       = sl.CUST_ORDER_LINE_NO
    LEFT JOIN part_cost pc
        ON pc.SITE_ID = s.SITE_ID
       AND pc.PART_ID = col.PART_ID
    WHERE s.SHIPPED_DATE >= @FromMonthStart
      AND s.SHIPPED_DATE <  DATEADD(month, 1, @ToMonthStart)
      AND ISNULL(s.STATUS, '') NOT IN ('X','V')
      AND (@Site IS NULL OR s.SITE_ID = @Site)
),

shipments_py AS (
    SELECT
        s.SITE_ID,
        COALESCE(col.PRODUCT_CODE, '(unknown)')                  AS product_code,
        DATEADD(year, 1,
            DATEFROMPARTS(YEAR(s.SHIPPED_DATE), MONTH(s.SHIPPED_DATE), 1))
                                                                 AS month_start,
        (sl.USER_SHIPPED_QTY * sl.UNIT_PRICE
         * (100.0 - COALESCE(sl.TRADE_DISC_PERCENT, 0)) / 100.0)  AS amount
    FROM SHIPPER s
    INNER JOIN SHIPPER_LINE sl
        ON sl.PACKLIST_ID = s.PACKLIST_ID
    INNER JOIN CUST_ORDER_LINE col
        ON col.CUST_ORDER_ID = sl.CUST_ORDER_ID
       AND col.LINE_NO       = sl.CUST_ORDER_LINE_NO
    WHERE s.SHIPPED_DATE >= DATEADD(year, -1, @FromMonthStart)
      AND s.SHIPPED_DATE <  DATEADD(month, 1, @ToMonthStart)
      AND ISNULL(s.STATUS, '') NOT IN ('X','V')
      AND (@Site IS NULL OR s.SITE_ID = @Site)
),

-- Build month spine so we have a row even with zero activity
months AS (
    SELECT TOP (DATEDIFF(month, @FromMonthStart, @ToMonthStart) + 1)
        DATEADD(month,
                ROW_NUMBER() OVER (ORDER BY (SELECT 1)) - 1,
                @FromMonthStart) AS month_start
    FROM sys.all_objects
),

-- Distinct product_code / site spine
ps_spine AS (
    SELECT DISTINCT SITE_ID, product_code FROM bookings
    UNION
    SELECT DISTINCT SITE_ID, product_code FROM shipments
),

spine AS (
    SELECT
        ps.SITE_ID,
        ps.product_code,
        m.month_start
    FROM ps_spine ps
    CROSS JOIN months m
),

-- Aggregates
b_agg AS (
    SELECT SITE_ID, product_code, month_start,
        SUM(qty)     AS bookings_qty,
        SUM(amount)  AS bookings_amount
    FROM bookings
    GROUP BY SITE_ID, product_code, month_start
),

bpy_agg AS (
    SELECT SITE_ID, product_code, month_start,
        SUM(amount) AS bookings_amount_py
    FROM bookings_py
    GROUP BY SITE_ID, product_code, month_start
),

s_agg AS (
    SELECT SITE_ID, product_code, month_start,
        SUM(qty)             AS ship_qty,
        SUM(amount)          AS ship_revenue,
        SUM(std_cost_value)  AS std_cost_value
    FROM shipments
    GROUP BY SITE_ID, product_code, month_start
),

spy_agg AS (
    SELECT SITE_ID, product_code, month_start,
        SUM(amount) AS ship_revenue_py
    FROM shipments_py
    GROUP BY SITE_ID, product_code, month_start
),

-- Backlog snapshot value at end-of-month m: sum over all SO lines of
-- (ordered_amount - shipped_before_end_of_m). Expensive (cross-join);
-- fine for 36-month windows but keep an eye on it.
-- For the historical monthly backlog snapshot, we can't just use today's
-- status. A line that is STATUS='C' now may have been open at a prior EOM.
-- We approximate its "closed-by" date using STATUS_EFF_DATE, then gate the
-- backlog contribution on whether that close happened before the EOM in
-- question. Cancelled orders (STATUS='X') are excluded entirely - treating
-- them as never having been real backlog.
so_lines AS (
    SELECT
        co.SITE_ID,
        COALESCE(col.PRODUCT_CODE, '(unknown)')              AS product_code,
        co.ID AS co_id, col.LINE_NO,
        co.ORDER_DATE,
        col.ORDER_QTY,
        col.UNIT_PRICE,
        COALESCE(col.TRADE_DISC_PERCENT, 0) AS trade_disc_pct,
        (col.ORDER_QTY * col.UNIT_PRICE
         * (100.0 - COALESCE(col.TRADE_DISC_PERCENT, 0)) / 100.0) AS ordered_amount,
        CASE
            WHEN co.STATUS      = 'C' THEN co.STATUS_EFF_DATE
            WHEN col.LINE_STATUS = 'C' THEN col.STATUS_EFF_DATE
            ELSE NULL
        END AS effective_close_date
    FROM CUSTOMER_ORDER co
    INNER JOIN CUST_ORDER_LINE col
        ON col.CUST_ORDER_ID = co.ID
    WHERE co.STATUS <> 'X'
      AND (@Site IS NULL OR co.SITE_ID = @Site)
),

shipments_per_line AS (
    SELECT
        sl.CUST_ORDER_ID AS co_id,
        sl.CUST_ORDER_LINE_NO AS line_no,
        s.SHIPPED_DATE,
        (sl.USER_SHIPPED_QTY * sl.UNIT_PRICE
         * (100.0 - COALESCE(sl.TRADE_DISC_PERCENT, 0)) / 100.0) AS ship_amount
    FROM SHIPPER s
    INNER JOIN SHIPPER_LINE sl
        ON sl.PACKLIST_ID = s.PACKLIST_ID
    WHERE ISNULL(s.STATUS, '') NOT IN ('X','V')
),

backlog_snapshot AS (
    SELECT
        sol.SITE_ID,
        sol.product_code,
        m.month_start,
        SUM(
            CASE
                WHEN sol.ORDER_DATE < DATEADD(month, 1, m.month_start)
                 AND (sol.effective_close_date IS NULL
                      OR sol.effective_close_date >= DATEADD(month, 1, m.month_start))
                THEN sol.ordered_amount
                     - COALESCE((
                         SELECT SUM(spl.ship_amount)
                         FROM shipments_per_line spl
                         WHERE spl.co_id   = sol.co_id
                           AND spl.line_no = sol.LINE_NO
                           AND spl.SHIPPED_DATE < DATEADD(month, 1, m.month_start)
                     ), 0)
                ELSE 0
            END
        ) AS open_backlog_snapshot_value
    FROM so_lines sol
    CROSS JOIN months m
    GROUP BY sol.SITE_ID, sol.product_code, m.month_start
)

SELECT
    sp.SITE_ID,
    sp.product_code,
    sp.month_start,

    -- Bookings
    COALESCE(ba.bookings_qty,        0)                        AS bookings_qty,
    COALESCE(ba.bookings_amount,     0)                        AS bookings_amount,
    COALESCE(bpya.bookings_amount_py, 0)                       AS bookings_amount_py,
    CAST(
        CASE WHEN COALESCE(bpya.bookings_amount_py, 0) > 0
             THEN (COALESCE(ba.bookings_amount, 0) - bpya.bookings_amount_py)
                  / bpya.bookings_amount_py * 100.0
             ELSE NULL
        END
    AS decimal(7,2))                                           AS bookings_yoy_pct,

    -- Shipments
    COALESCE(sa.ship_qty,            0)                        AS ship_qty,
    COALESCE(sa.ship_revenue,        0)                        AS ship_revenue,
    COALESCE(sa.std_cost_value,      0)                        AS std_cost_value,
    (COALESCE(sa.ship_revenue, 0) - COALESCE(sa.std_cost_value, 0))
                                                               AS std_margin_amount,
    CAST(
        100.0 * (COALESCE(sa.ship_revenue, 0) - COALESCE(sa.std_cost_value, 0))
        / NULLIF(sa.ship_revenue, 0)
    AS decimal(5,2))                                           AS std_margin_pct,

    COALESCE(spa.ship_revenue_py,    0)                        AS ship_revenue_py,
    CAST(
        CASE WHEN COALESCE(spa.ship_revenue_py, 0) > 0
             THEN (COALESCE(sa.ship_revenue, 0) - spa.ship_revenue_py)
                  / spa.ship_revenue_py * 100.0
             ELSE NULL
        END
    AS decimal(7,2))                                           AS ship_revenue_yoy_pct,

    -- Backlog EOM snapshot
    COALESCE(bs.open_backlog_snapshot_value, 0)                AS open_backlog_snapshot_value,

    -- Book-to-bill
    CAST(
        COALESCE(ba.bookings_amount, 0) / NULLIF(sa.ship_revenue, 0)
    AS decimal(7,3))                                           AS book_to_bill_ratio
FROM spine sp
LEFT JOIN b_agg        ba   ON ba.SITE_ID  = sp.SITE_ID AND ba.product_code  = sp.product_code AND ba.month_start  = sp.month_start
LEFT JOIN bpy_agg      bpya ON bpya.SITE_ID= sp.SITE_ID AND bpya.product_code= sp.product_code AND bpya.month_start= sp.month_start
LEFT JOIN s_agg        sa   ON sa.SITE_ID  = sp.SITE_ID AND sa.product_code  = sp.product_code AND sa.month_start  = sp.month_start
LEFT JOIN spy_agg      spa  ON spa.SITE_ID = sp.SITE_ID AND spa.product_code = sp.product_code AND spa.month_start = sp.month_start
LEFT JOIN backlog_snapshot bs ON bs.SITE_ID= sp.SITE_ID AND bs.product_code  = sp.product_code AND bs.month_start  = sp.month_start
ORDER BY sp.SITE_ID, sp.product_code, sp.month_start;
