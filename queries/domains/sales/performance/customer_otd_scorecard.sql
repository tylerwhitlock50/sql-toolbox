/*
===============================================================================
Query Name: customer_otd_scorecard.sql

Purpose:
    Per-customer on-time ship scorecard. Measures how well we are
    delivering to each customer against the date they were promised
    (or asked for), using SHIPPER / SHIPPER_LINE as the actual-shipment
    source of truth.

Business Use:
    - Customer reviews / QBRs with objective OTD numbers
    - Identify customers who are bearing the brunt of shipment slips
    - Rank customers by revenue + service level (who hurts most when late)
    - Feed commercial team with fact base for at-risk accounts

Grain:
    One row per (SITE_ID, CUSTOMER_ID) for the evaluation window.

OTD Definition:
    For each shipment line we compute:
        days_late = DATEDIFF(day, target_ship_date, SHIPPER.SHIPPED_DATE)
    where target_ship_date =
        COALESCE(CUST_ORDER_LINE.PROMISE_DATE,
                 CUST_ORDER_LINE.DESIRED_SHIP_DATE,
                 CUSTOMER_ORDER.PROMISE_DATE,
                 CUSTOMER_ORDER.DESIRED_SHIP_DATE)

    A shipment is counted on-time if days_late <= @OnTimeToleranceDays.

Fill-rate Definition:
    At the order-line level we compare TOTAL_SHIPPED_QTY vs ORDER_QTY for
    all lines that have shipped or closed in the window. Lines where
    TOTAL_SHIPPED_QTY < ORDER_QTY and LINE_STATUS = 'C' (closed) are
    treated as closed-short.

Window:
    Parameterized via @FromDate / @ToDate. Evaluation is based on
    SHIPPER.SHIPPED_DATE for shipment-level metrics.

Notes / Assumptions:
    - Uses SHIPPER.STATUS not in ('X','V') to exclude voided shipments.
      ('V' is defensive — adjust if your environment differs.)
    - Revenue uses SHIPPER_LINE.UNIT_PRICE and TRADE_DISC_PERCENT.
    - Does NOT pull cost / margin here; use salesrep_performance_scorecard.sql
      for cost side. Keeping this one focused on service level.
    - Customers with fewer than @MinShipments in the window still show
      up; filter when ranking.

Potential Enhancements:
    - Split by order_type or product_code (a customer may be great on
      stock items but poor on configured)
    - Compare current period to prior period (lag)
    - Add return / RMA count from SHIPPER where SHIP_REASON_CD indicates
      return
===============================================================================
*/

DECLARE @Site                 nvarchar(15) = NULL;
DECLARE @FromDate             datetime     = DATEADD(day, -365, GETDATE());
DECLARE @ToDate               datetime     = GETDATE();
DECLARE @OnTimeToleranceDays  int          = 0;
DECLARE @MinShipments         int          = 0;

;WITH shipped AS (
    SELECT
        s.SITE_ID,
        co.CUSTOMER_ID,
        co.SALESREP_ID,
        co.TERRITORY,
        s.PACKLIST_ID,
        sl.LINE_NO                            AS ship_line_no,
        sl.CUST_ORDER_ID,
        sl.CUST_ORDER_LINE_NO,
        col.PART_ID,

        s.SHIPPED_DATE,
        sl.SHIPPED_QTY,
        sl.USER_SHIPPED_QTY,
        sl.UNIT_PRICE                         AS ship_unit_price,
        COALESCE(sl.TRADE_DISC_PERCENT, 0)    AS trade_disc_pct,

        (sl.USER_SHIPPED_QTY * sl.UNIT_PRICE
         * (100.0 - COALESCE(sl.TRADE_DISC_PERCENT, 0)) / 100.0)
                                              AS ship_revenue,

        -- Best-available promised ship date (line first, header fallback)
        COALESCE(
            col.PROMISE_DATE,
            col.DESIRED_SHIP_DATE,
            co.PROMISE_DATE,
            co.DESIRED_SHIP_DATE
        )                                     AS target_ship_date,

        DATEDIFF(day,
            COALESCE(
                col.PROMISE_DATE,
                col.DESIRED_SHIP_DATE,
                co.PROMISE_DATE,
                co.DESIRED_SHIP_DATE
            ),
            s.SHIPPED_DATE
        )                                     AS days_late
    FROM SHIPPER s
    INNER JOIN SHIPPER_LINE sl
        ON sl.PACKLIST_ID = s.PACKLIST_ID
    INNER JOIN CUSTOMER_ORDER co
        ON co.ID = s.CUST_ORDER_ID
    INNER JOIN CUST_ORDER_LINE col
        ON col.CUST_ORDER_ID = sl.CUST_ORDER_ID
       AND col.LINE_NO       = sl.CUST_ORDER_LINE_NO
    WHERE s.SHIPPED_DATE >= @FromDate
      AND s.SHIPPED_DATE <  @ToDate
      AND ISNULL(s.STATUS, '') NOT IN ('X','V')
      AND sl.USER_SHIPPED_QTY > 0
      AND (@Site IS NULL OR s.SITE_ID = @Site)
),

fill_base AS (
    -- Order-line level: all SO lines that had activity in window (shipped
    -- or closed), so we can compute line fill rate.
    SELECT
        co.SITE_ID,
        co.CUSTOMER_ID,
        col.CUST_ORDER_ID,
        col.LINE_NO,
        col.ORDER_QTY,
        col.TOTAL_SHIPPED_QTY,
        col.LINE_STATUS,
        col.UNIT_PRICE,
        COALESCE(col.TRADE_DISC_PERCENT, 0) AS trade_disc_pct,
        col.PROMISE_DATE,
        col.DESIRED_SHIP_DATE
    FROM CUST_ORDER_LINE col
    INNER JOIN CUSTOMER_ORDER co
        ON co.ID = col.CUST_ORDER_ID
    WHERE (@Site IS NULL OR co.SITE_ID = @Site)
      AND (
            -- Any line with at least one shipment in the window
            EXISTS (
                SELECT 1
                FROM SHIPPER s2
                INNER JOIN SHIPPER_LINE sl2
                    ON sl2.PACKLIST_ID = s2.PACKLIST_ID
                WHERE sl2.CUST_ORDER_ID      = col.CUST_ORDER_ID
                  AND sl2.CUST_ORDER_LINE_NO = col.LINE_NO
                  AND s2.SHIPPED_DATE >= @FromDate
                  AND s2.SHIPPED_DATE <  @ToDate
                  AND ISNULL(s2.STATUS, '') NOT IN ('X','V')
            )
            -- Or lines closed inside the window with short-ship
            OR (col.LINE_STATUS = 'C'
                AND col.STATUS_EFF_DATE >= @FromDate
                AND col.STATUS_EFF_DATE <  @ToDate)
          )
),

ship_agg AS (
    SELECT
        sh.SITE_ID,
        sh.CUSTOMER_ID,
        COUNT(*)                                              AS ship_lines,
        COUNT(DISTINCT sh.PACKLIST_ID)                        AS shipments,
        COUNT(DISTINCT sh.CUST_ORDER_ID)                      AS orders_shipped,
        COUNT(DISTINCT sh.PART_ID)                            AS parts_shipped,

        SUM(sh.USER_SHIPPED_QTY)                              AS total_shipped_qty,
        SUM(sh.ship_revenue)                                  AS total_ship_revenue,

        SUM(CASE WHEN sh.days_late <= @OnTimeToleranceDays THEN 1 ELSE 0 END)
                                                              AS on_time_ship_lines,
        SUM(CASE WHEN sh.days_late >  @OnTimeToleranceDays THEN 1 ELSE 0 END)
                                                              AS late_ship_lines,

        CAST(100.0 * SUM(CASE WHEN sh.days_late <= @OnTimeToleranceDays THEN 1 ELSE 0 END)
             / NULLIF(COUNT(*), 0) AS decimal(5,2))            AS otd_pct_by_line,

        CAST(100.0 * SUM(CASE WHEN sh.days_late <= @OnTimeToleranceDays
                              THEN sh.ship_revenue ELSE 0 END)
             / NULLIF(SUM(sh.ship_revenue), 0)
             AS decimal(5,2))                                 AS otd_pct_by_revenue,

        CAST(AVG(CAST(sh.days_late AS float)) AS decimal(7,2)) AS avg_days_late,
        MAX(sh.days_late)                                      AS max_days_late,

        MIN(sh.SHIPPED_DATE)                                   AS first_ship_in_window,
        MAX(sh.SHIPPED_DATE)                                   AS last_ship_in_window
    FROM shipped sh
    GROUP BY sh.SITE_ID, sh.CUSTOMER_ID
),

fill_agg AS (
    SELECT
        fb.SITE_ID,
        fb.CUSTOMER_ID,
        COUNT(*)                                               AS order_lines_in_window,
        SUM(CASE WHEN fb.TOTAL_SHIPPED_QTY >= fb.ORDER_QTY
                 THEN 1 ELSE 0 END)                            AS lines_fully_shipped,
        SUM(CASE WHEN fb.LINE_STATUS = 'C'
                  AND fb.TOTAL_SHIPPED_QTY < fb.ORDER_QTY
                 THEN 1 ELSE 0 END)                            AS lines_closed_short,
        CAST(100.0 * SUM(fb.TOTAL_SHIPPED_QTY)
             / NULLIF(SUM(fb.ORDER_QTY), 0)
             AS decimal(5,2))                                   AS qty_fill_rate_pct,
        CAST(100.0 * SUM(CASE WHEN fb.TOTAL_SHIPPED_QTY >= fb.ORDER_QTY
                              THEN 1 ELSE 0 END)
             / NULLIF(COUNT(*), 0)
             AS decimal(5,2))                                   AS line_fill_rate_pct
    FROM fill_base fb
    GROUP BY fb.SITE_ID, fb.CUSTOMER_ID
)

SELECT
    sa.SITE_ID,
    sa.CUSTOMER_ID,
    c.NAME                                                     AS customer_name,
    c.TERRITORY,
    c.SALESREP_ID,

    sa.shipments,
    sa.orders_shipped,
    sa.ship_lines,
    sa.parts_shipped,
    sa.total_shipped_qty,
    sa.total_ship_revenue,

    sa.on_time_ship_lines,
    sa.late_ship_lines,
    sa.otd_pct_by_line,
    sa.otd_pct_by_revenue,
    sa.avg_days_late,
    sa.max_days_late,

    COALESCE(fa.order_lines_in_window, 0)  AS order_lines_in_window,
    COALESCE(fa.lines_fully_shipped,   0)  AS lines_fully_shipped,
    COALESCE(fa.lines_closed_short,    0)  AS lines_closed_short,
    fa.qty_fill_rate_pct,
    fa.line_fill_rate_pct,

    sa.first_ship_in_window,
    sa.last_ship_in_window,

    CASE
        WHEN sa.otd_pct_by_revenue >= 95 AND COALESCE(fa.line_fill_rate_pct, 100) >= 98 THEN 'A - GOLD'
        WHEN sa.otd_pct_by_revenue >= 85                                                THEN 'B - OK'
        WHEN sa.otd_pct_by_revenue >= 70                                                THEN 'C - NEEDS IMPROVEMENT'
        ELSE                                                                                 'D - AT RISK'
    END                                                        AS service_tier
FROM ship_agg sa
LEFT JOIN CUSTOMER c
    ON c.ID = sa.CUSTOMER_ID
LEFT JOIN fill_agg fa
    ON fa.SITE_ID = sa.SITE_ID AND fa.CUSTOMER_ID = sa.CUSTOMER_ID
WHERE sa.shipments >= @MinShipments
ORDER BY sa.total_ship_revenue DESC, sa.otd_pct_by_revenue ASC;
