/*
===============================================================================
Query Name: total_demand_by_part.sql

Purpose:
    Unify every flavor of demand the company has on the books into ONE row-set
    so downstream queries (BOM explosion, MRP, purchasing plan) can read a
    single source. Today demand is fragmented across:

        * Open sales orders (backorder)
        * MASTER_SCHEDULE (firmed='Y' = committed master schedule;
                           firmed='N' = master-schedule-loaded forecast)
        * DEMAND_FORECAST (raw forecast import target)

    The pipeline is built so it works TODAY (when forecast tables may be
    empty) and continues to work once forecast load lands.

Grain:
    One row per (SITE_ID, PART_ID, NEED_DATE, DEMAND_SOURCE, SOURCE_REF).
    SOURCE_REF carries the originating record id so we can trace each demand
    row back to a sales order line, master-schedule row, or forecast row.

Demand priority (so SO demand wins over forecast in netting):
    1 = Sales backorder
    2 = Master schedule (firmed)
    3 = Master schedule (un-firmed -- treated as forecast)
    4 = Demand forecast

Open-order filter (canonical, see so_header_and_lines_open_orders.sql):
    CUSTOMER_ORDER.STATUS IN ('R','F') AND CUST_ORDER_LINE.LINE_STATUS = 'A'.

Caveats:
    - Forecast tables (MASTER_SCHEDULE, DEMAND_FORECAST) may be empty today;
      that's expected. Sales-order rows alone make the rest of the pipeline
      run.
    - This is gross demand (no netting against on-hand or open supply).
      Netting is done in net_requirements_weekly.sql.
    - Demand date precedence for SO: line PROMISE_DATE if present, else line
      DESIRED_SHIP_DATE, else header DESIRED_SHIP_DATE.
===============================================================================
*/

DECLARE @Site nvarchar(15) = NULL;   -- NULL = all sites

;WITH so_demand AS (
    SELECT
        col.SITE_ID,
        col.PART_ID,
        COALESCE(col.PROMISE_DATE,
                 col.DESIRED_SHIP_DATE,
                 co.DESIRED_SHIP_DATE)               AS NEED_DATE,
        CAST('SO_BACKORDER' AS nvarchar(20))         AS DEMAND_SOURCE,
        CAST(1 AS tinyint)                           AS DEMAND_PRIORITY,
        col.ORDER_QTY - col.TOTAL_SHIPPED_QTY        AS DEMAND_QTY,
        col.UNIT_PRICE                               AS UNIT_PRICE,
        (col.ORDER_QTY - col.TOTAL_SHIPPED_QTY) * col.UNIT_PRICE
                                                     AS DEMAND_VALUE,
        co.CUSTOMER_ID                               AS PARTY_ID,
        col.CUST_ORDER_ID + '/'
            + CAST(col.LINE_NO AS nvarchar(10))      AS SOURCE_REF
    FROM CUST_ORDER_LINE col
    INNER JOIN CUSTOMER_ORDER co
        ON co.ID = col.CUST_ORDER_ID
    WHERE co.STATUS    IN ('R','F')
      AND col.LINE_STATUS = 'A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
      AND col.PART_ID IS NOT NULL
      AND (@Site IS NULL OR col.SITE_ID = @Site)
),

ms_demand AS (
    SELECT
        ms.SITE_ID,
        ms.PART_ID,
        ms.WANT_DATE                                 AS NEED_DATE,
        CASE WHEN ms.FIRMED = 'Y' THEN 'MS_FIRM'
             ELSE 'MS_FORECAST' END                  AS DEMAND_SOURCE,
        CASE WHEN ms.FIRMED = 'Y' THEN CAST(2 AS tinyint)
             ELSE                       CAST(3 AS tinyint) END AS DEMAND_PRIORITY,
        ms.ORDER_QTY                                 AS DEMAND_QTY,
        CAST(NULL AS decimal(22,8))                  AS UNIT_PRICE,
        CAST(NULL AS decimal(23,8))                  AS DEMAND_VALUE,
        CAST(NULL AS nvarchar(15))                   AS PARTY_ID,
        ms.MASTER_SCHEDULE_ID                        AS SOURCE_REF
    FROM MASTER_SCHEDULE ms
    WHERE ms.ORDER_QTY > 0
      AND (@Site IS NULL OR ms.SITE_ID = @Site)
),

forecast_demand AS (
    SELECT
        df.SITE_ID,
        df.PART_ID,
        df.REQUIRED_DATE                             AS NEED_DATE,
        CAST('FORECAST' AS nvarchar(20))             AS DEMAND_SOURCE,
        CAST(4 AS tinyint)                           AS DEMAND_PRIORITY,
        df.REQUIRED_QTY                              AS DEMAND_QTY,
        CAST(NULL AS decimal(22,8))                  AS UNIT_PRICE,
        CAST(NULL AS decimal(23,8))                  AS DEMAND_VALUE,
        CAST(NULL AS nvarchar(15))                   AS PARTY_ID,
        CAST(df.ROWID AS nvarchar(20))               AS SOURCE_REF
    FROM DEMAND_FORECAST df
    WHERE df.REQUIRED_QTY > 0
      AND (@Site IS NULL OR df.SITE_ID = @Site)
),

unioned AS (
    SELECT * FROM so_demand
    UNION ALL
    SELECT * FROM ms_demand
    UNION ALL
    SELECT * FROM forecast_demand
)

SELECT
    u.SITE_ID,
    u.PART_ID,
    psv.DESCRIPTION,
    psv.PRODUCT_CODE,
    psv.COMMODITY_CODE,
    psv.STOCK_UM,
    psv.FABRICATED,
    psv.PURCHASED,
    psv.STOCKED,
    psv.PLANNER_USER_ID,
    psv.BUYER_USER_ID,
    psv.PLANNING_LEADTIME,
    psv.ABC_CODE,

    u.NEED_DATE,
    -- Bucket the date into the start-of-Monday of the ISO week so downstream
    -- queries can group on a single canonical bucket.
    DATEADD(day,
            -((DATEPART(weekday, u.NEED_DATE) + @@DATEFIRST - 2) % 7),
            CAST(u.NEED_DATE AS date))               AS WEEK_BUCKET,

    u.DEMAND_SOURCE,
    u.DEMAND_PRIORITY,
    u.DEMAND_QTY,
    u.UNIT_PRICE,
    u.DEMAND_VALUE,
    u.PARTY_ID,
    u.SOURCE_REF,

    -- Days from today until the demand is needed (negative = past due)
    DATEDIFF(day, CAST(GETDATE() AS date), u.NEED_DATE) AS DAYS_UNTIL_NEED,

    CASE
        WHEN u.NEED_DATE < CAST(GETDATE() AS date) THEN 'PAST_DUE'
        WHEN u.NEED_DATE < DATEADD(day,  30, CAST(GETDATE() AS date)) THEN '0-30 DAYS'
        WHEN u.NEED_DATE < DATEADD(day,  60, CAST(GETDATE() AS date)) THEN '30-60 DAYS'
        WHEN u.NEED_DATE < DATEADD(day,  90, CAST(GETDATE() AS date)) THEN '60-90 DAYS'
        WHEN u.NEED_DATE < DATEADD(day, 180, CAST(GETDATE() AS date)) THEN '90-180 DAYS'
        ELSE                                                                '180+ DAYS'
    END AS NEED_BUCKET
FROM unioned u
LEFT JOIN PART_SITE_VIEW psv
    ON  psv.PART_ID = u.PART_ID
    AND psv.SITE_ID = u.SITE_ID
ORDER BY
    u.DEMAND_PRIORITY,
    u.NEED_DATE,
    u.SITE_ID,
    u.PART_ID;
