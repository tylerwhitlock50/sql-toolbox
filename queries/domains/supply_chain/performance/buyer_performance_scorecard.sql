/*
===============================================================================
Query Name: buyer_performance_scorecard.sql

Purpose:
    Per-buyer scorecard. Answers "how is each buyer on my team doing?"
    using open + received purchase-order activity over a rolling window.

Business Use:
    - Workload visibility (open PO value & line count per buyer)
    - Execution metrics (how much of their book is past due?)
    - Quality of sourcing (price variance vs standard)
    - Throughput (receipts closed in the window)
    - One-on-one / staffing discussions with objective numbers

Grain:
    One row per (SITE_ID, BUYER) for the evaluation window.

Buyer identification:
    PO header BUYER column is the primary attribution. Falls back to
    PART_SITE_VIEW.BUYER_USER_ID if the PO header is blank so that
    parts still roll up to their assigned buyer.

Window:
    @FromDate / @ToDate default to trailing 365 days. Metrics that are
    "point in time" (past due, open $) are computed as-of @AsOfDate
    (default GETDATE()).

Metrics:
    * open_po_lines / open_po_value
        PO lines with remaining open qty and line/header status not in
        ('X','C'). Value uses PO unit price in purchase UOM.

    * past_due_lines / past_due_value
        Subset of open lines where target_recv_date < @AsOfDate.
        target_recv_date = COALESCE(schedule, line, header promise, header desired).

    * weighted_avg_days_past_due
        Value-weighted (open_value) days past target. More meaningful than
        simple average because a $50k line 30 days late matters more than
        a $50 line 30 days late.

    * received_lines_in_window / received_value_in_window
        Volume of work the buyer actually closed out in the window.

    * otd_pct
        % of receipts in window where receive date <= target date.

    * lines_with_price_variance_gt_5pct
        Count of received lines where PO unit price differed from
        PART_SITE_VIEW standard material cost by more than 5%. This
        surfaces sourcing drift (inflation, new vendors, bad quotes).

    * stalled_lines
        Open lines with desired_recv_date > @StalledDays old and no
        receipt activity ever. These are the "forgotten POs" a buyer
        should clean up.

Potential Enhancements:
    - Pull human name from SYS_USER table (if buyer id is a user id)
    - Split by commodity to show category specialization
    - Compare current window vs prior window (trend)
===============================================================================
*/

DECLARE @Site            nvarchar(15) = NULL;
DECLARE @FromDate        datetime     = DATEADD(day, -365, GETDATE());
DECLARE @ToDate          datetime     = GETDATE();
DECLARE @AsOfDate        datetime     = GETDATE();
DECLARE @StalledDays     int          = 60;
DECLARE @PriceVarPct     decimal(5,2) = 5.00;

;WITH po_lines AS (
    SELECT
        p.SITE_ID,
        COALESCE(NULLIF(LTRIM(RTRIM(p.BUYER)), ''),
                 psv.BUYER_USER_ID,
                 '(unassigned)')                                   AS buyer,
        p.ID                                                       AS po_id,
        p.VENDOR_ID,
        pl.LINE_NO,
        pl.PART_ID,
        pl.UNIT_PRICE                                              AS po_unit_price,
        (psv.UNIT_MATERIAL_COST
         + psv.UNIT_LABOR_COST
         + psv.UNIT_BURDEN_COST
         + psv.UNIT_SERVICE_COST)                                  AS std_unit_cost,
        pl.ORDER_QTY,
        pl.TOTAL_RECEIVED_QTY,
        (pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY)                     AS open_qty,
        COALESCE(
            pl.DESIRED_RECV_DATE,
            p.PROMISE_DATE,
            p.DESIRED_RECV_DATE
        )                                                          AS target_recv_date,
        p.ORDER_DATE,
        p.STATUS                                                   AS po_status,
        pl.LINE_STATUS
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl
        ON pl.PURC_ORDER_ID = p.ID
    LEFT JOIN PART_SITE_VIEW psv
        ON psv.SITE_ID = p.SITE_ID
       AND psv.PART_ID = pl.PART_ID
    WHERE (@Site IS NULL OR p.SITE_ID = @Site)
      AND pl.PART_ID IS NOT NULL
),

open_lines AS (
    SELECT
        pl.*
    FROM po_lines pl
    WHERE ISNULL(pl.po_status, '')   NOT IN ('X','C')
      AND ISNULL(pl.LINE_STATUS, '') NOT IN ('X','C')
      AND pl.open_qty > 0
),

received_in_window AS (
    -- One row per (po_line, receipt) inside the window
    SELECT
        pl.SITE_ID,
        pl.buyer,
        pl.po_id,
        pl.LINE_NO,
        pl.PART_ID,
        pl.po_unit_price,
        pl.std_unit_cost,
        pl.target_recv_date,
        r.RECEIVED_DATE,
        rl.RECEIVED_QTY,
        COALESCE(it.ACT_MATERIAL_COST, rl.RECEIVED_QTY * pl.po_unit_price) AS receipt_value,
        DATEDIFF(day, pl.target_recv_date, r.RECEIVED_DATE)                AS days_late
    FROM po_lines pl
    INNER JOIN RECEIVER_LINE rl
        ON rl.PURC_ORDER_ID      = pl.po_id
       AND rl.PURC_ORDER_LINE_NO = pl.LINE_NO
    INNER JOIN RECEIVER r
        ON r.ID = rl.RECEIVER_ID
    LEFT JOIN INVENTORY_TRANS it
        ON it.TRANSACTION_ID = rl.TRANSACTION_ID
    WHERE r.RECEIVED_DATE >= @FromDate
      AND r.RECEIVED_DATE <  @ToDate
      AND rl.RECEIVED_QTY  > 0
),

open_agg AS (
    SELECT
        o.SITE_ID,
        o.buyer,
        COUNT(*)                                             AS open_po_lines,
        COUNT(DISTINCT o.po_id)                              AS open_pos,
        COUNT(DISTINCT o.VENDOR_ID)                          AS open_vendors,
        SUM(o.open_qty * o.po_unit_price)                    AS open_po_value,

        SUM(CASE WHEN o.target_recv_date < @AsOfDate
                 THEN 1 ELSE 0 END)                          AS past_due_lines,
        SUM(CASE WHEN o.target_recv_date < @AsOfDate
                 THEN o.open_qty * o.po_unit_price
                 ELSE 0 END)                                 AS past_due_value,

        -- Value-weighted average days past due (past-due lines only)
        CAST(
            SUM(CASE WHEN o.target_recv_date < @AsOfDate
                     THEN DATEDIFF(day, o.target_recv_date, @AsOfDate)
                          * (o.open_qty * o.po_unit_price)
                     ELSE 0 END)
            / NULLIF(
                SUM(CASE WHEN o.target_recv_date < @AsOfDate
                         THEN o.open_qty * o.po_unit_price
                         ELSE 0 END), 0)
        AS decimal(7,2))                                     AS weighted_avg_days_past_due,

        -- Stalled: line desired more than @StalledDays ago and nothing ever received
        SUM(CASE WHEN DATEDIFF(day, o.target_recv_date, @AsOfDate) > @StalledDays
                  AND o.TOTAL_RECEIVED_QTY = 0
                 THEN 1 ELSE 0 END)                          AS stalled_lines,
        SUM(CASE WHEN DATEDIFF(day, o.target_recv_date, @AsOfDate) > @StalledDays
                  AND o.TOTAL_RECEIVED_QTY = 0
                 THEN o.open_qty * o.po_unit_price
                 ELSE 0 END)                                 AS stalled_value
    FROM open_lines o
    GROUP BY o.SITE_ID, o.buyer
),

recv_agg AS (
    SELECT
        r.SITE_ID,
        r.buyer,
        COUNT(*)                                             AS received_lines_in_window,
        SUM(r.RECEIVED_QTY)                                  AS received_qty_in_window,
        SUM(r.receipt_value)                                 AS received_value_in_window,

        SUM(CASE WHEN r.days_late <= 0 THEN 1 ELSE 0 END)    AS on_time_receipts,
        CAST(100.0 * SUM(CASE WHEN r.days_late <= 0 THEN 1 ELSE 0 END)
             / NULLIF(COUNT(*), 0) AS decimal(5,2))          AS otd_pct,

        SUM(CASE
                WHEN r.std_unit_cost > 0
                 AND ABS(r.po_unit_price - r.std_unit_cost)
                       / NULLIF(r.std_unit_cost, 0) * 100.0
                       > @PriceVarPct
                THEN 1 ELSE 0
            END)                                             AS lines_with_price_variance_gt_threshold
    FROM received_in_window r
    GROUP BY r.SITE_ID, r.buyer
),

all_buyers AS (
    SELECT SITE_ID, buyer FROM open_agg
    UNION
    SELECT SITE_ID, buyer FROM recv_agg
)

SELECT
    ab.SITE_ID,
    ab.buyer,

    -- Workload / point-in-time
    COALESCE(oa.open_pos,         0)                     AS open_pos,
    COALESCE(oa.open_po_lines,    0)                     AS open_po_lines,
    COALESCE(oa.open_vendors,     0)                     AS open_vendors,
    COALESCE(oa.open_po_value,    0)                     AS open_po_value,

    COALESCE(oa.past_due_lines,   0)                     AS past_due_lines,
    COALESCE(oa.past_due_value,   0)                     AS past_due_value,
    oa.weighted_avg_days_past_due,

    COALESCE(oa.stalled_lines,    0)                     AS stalled_lines,
    COALESCE(oa.stalled_value,    0)                     AS stalled_value,

    -- Execution in window
    COALESCE(ra.received_lines_in_window,  0)            AS received_lines_in_window,
    COALESCE(ra.received_qty_in_window,    0)            AS received_qty_in_window,
    COALESCE(ra.received_value_in_window,  0)            AS received_value_in_window,
    COALESCE(ra.on_time_receipts,          0)            AS on_time_receipts,
    ra.otd_pct,
    COALESCE(ra.lines_with_price_variance_gt_threshold, 0)
                                                         AS lines_with_price_variance_gt_threshold,

    -- Simple attention flag
    CASE
        WHEN COALESCE(oa.past_due_value, 0) > COALESCE(oa.open_po_value, 0) * 0.25
         OR COALESCE(oa.stalled_lines, 0) >= 5
         OR COALESCE(ra.otd_pct, 100) < 80
            THEN 'ATTENTION'
        ELSE 'OK'
    END                                                  AS flag
FROM all_buyers ab
LEFT JOIN open_agg oa
    ON oa.SITE_ID = ab.SITE_ID AND oa.buyer = ab.buyer
LEFT JOIN recv_agg ra
    ON ra.SITE_ID = ab.SITE_ID AND ra.buyer = ab.buyer
ORDER BY
    COALESCE(oa.past_due_value, 0) DESC,
    COALESCE(oa.open_po_value,  0) DESC;
