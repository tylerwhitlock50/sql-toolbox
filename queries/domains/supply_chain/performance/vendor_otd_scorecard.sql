/*
===============================================================================
Query Name: vendor_otd_scorecard.sql

Purpose:
    Vendor on-time delivery (OTD), quality, and spend scorecard.

    Measures how each vendor is performing against their commitments using
    actual receipts (RECEIVER / RECEIVER_LINE) compared to the dates the
    buyer asked for on the PO line.

Business Use:
    - Rank vendors by OTD% and $ spend
    - Identify chronically late or low-quality vendors
    - Feed vendor reviews / QBRs with objective numbers
    - Support consolidation decisions (spend concentration by vendor)

Grain:
    One row per (SITE_ID, VENDOR_ID) for the evaluation window.

Window:
    Parameterized via @FromDate / @ToDate. Defaults to trailing 365 days
    from GETDATE(). Evaluation is based on the RECEIVER.RECEIVED_DATE
    (i.e. when material actually landed), not when the PO was placed.

OTD Definition:
    For each receipt row we compute:
        days_late = DATEDIFF(day, target_date, RECEIVED_DATE)
    where target_date is COALESCE(PURC_LINE_DEL.DESIRED_RECV_DATE,
                                  PURC_ORDER_LINE.DESIRED_RECV_DATE,
                                  PURCHASE_ORDER.PROMISE_DATE,
                                  PURCHASE_ORDER.DESIRED_RECV_DATE).

    A receipt is counted on-time if days_late <= @OnTimeToleranceDays
    (default 0 = must be on or before target).

Quality:
    Uses RECEIVER_LINE.REJECTED_QTY relative to RECEIVED_QTY.

Notes / Assumptions:
    - INVENTORY_TRANS already carries actual cost per receipt. We use
      ACT_MATERIAL_COST from the matching receipt transaction to tally
      spend rather than unit_price * qty (picks up freight/landed if costed).
    - Receipts with RECEIVED_QTY <= 0 are excluded from OTD counts
      (returns, reversals).
    - Vendors with fewer than @MinReceipts in the window are still
      returned but you'll typically want to filter those out when ranking.

Potential Enhancements:
    - Split OTD by commodity_code or product_code (vendor may be great at
      one thing and terrible at another)
    - Add receipt-weighted vs line-weighted OTD
    - Flag vendors whose OTD has degraded vs prior period (lag over window)
===============================================================================
*/

DECLARE @Site                   nvarchar(15) = NULL;               -- NULL = all sites
DECLARE @FromDate               datetime     = DATEADD(day, -365, GETDATE());
DECLARE @ToDate                 datetime     = GETDATE();
DECLARE @OnTimeToleranceDays    int          = 0;                  -- 0 = must hit target exactly or be early
DECLARE @MinReceipts            int          = 0;                  -- applied in final WHERE

;WITH receipts AS (
    SELECT
        p.SITE_ID,
        p.VENDOR_ID,
        p.ID                                  AS po_id,
        pl.LINE_NO                            AS po_line_no,
        pl.PART_ID,
        r.ID                                  AS receiver_id,
        rl.LINE_NO                            AS receiver_line_no,
        r.RECEIVED_DATE,

        rl.RECEIVED_QTY,
        COALESCE(rl.REJECTED_QTY, 0)          AS rejected_qty,

        -- Target date the buyer asked for, best-available
        COALESCE(
            pd.DESIRED_RECV_DATE,
            pl.DESIRED_RECV_DATE,
            p.PROMISE_DATE,
            p.DESIRED_RECV_DATE
        )                                     AS target_recv_date,

        DATEDIFF(day,
            COALESCE(
                pd.DESIRED_RECV_DATE,
                pl.DESIRED_RECV_DATE,
                p.PROMISE_DATE,
                p.DESIRED_RECV_DATE
            ),
            r.RECEIVED_DATE
        )                                     AS days_late,

        -- Actual material cost on the matching inventory transaction
        it.ACT_MATERIAL_COST                  AS receipt_value,
        pl.UNIT_PRICE                         AS po_unit_price
    FROM RECEIVER r
    INNER JOIN RECEIVER_LINE rl
        ON rl.RECEIVER_ID = r.ID
    INNER JOIN PURCHASE_ORDER p
        ON p.ID = r.PURC_ORDER_ID
    INNER JOIN PURC_ORDER_LINE pl
        ON pl.PURC_ORDER_ID = rl.PURC_ORDER_ID
       AND pl.LINE_NO       = rl.PURC_ORDER_LINE_NO
    LEFT JOIN PURC_LINE_DEL pd
        ON pd.PURC_ORDER_ID      = pl.PURC_ORDER_ID
       AND pd.PURC_ORDER_LINE_NO = pl.LINE_NO
       AND pd.DEL_SCHED_LINE_NO  = 1
    LEFT JOIN INVENTORY_TRANS it
        ON it.TRANSACTION_ID = rl.TRANSACTION_ID
    WHERE r.RECEIVED_DATE >= @FromDate
      AND r.RECEIVED_DATE <  @ToDate
      AND rl.RECEIVED_QTY  > 0
      AND (@Site IS NULL OR p.SITE_ID = @Site)
),

flagged AS (
    SELECT
        r.*,
        CASE WHEN r.days_late <= @OnTimeToleranceDays THEN 1 ELSE 0 END AS is_on_time,
        CASE WHEN r.days_late >  @OnTimeToleranceDays THEN 1 ELSE 0 END AS is_late,
        CASE WHEN r.rejected_qty > 0                   THEN 1 ELSE 0 END AS had_rejection
    FROM receipts r
),

vendor_agg AS (
    SELECT
        f.SITE_ID,
        f.VENDOR_ID,

        COUNT(*)                                               AS total_receipts,
        COUNT(DISTINCT f.po_id)                                AS unique_pos,
        COUNT(DISTINCT f.PART_ID)                              AS unique_parts,

        SUM(f.is_on_time)                                      AS on_time_receipts,
        SUM(f.is_late)                                         AS late_receipts,

        CAST(100.0 * SUM(f.is_on_time) / NULLIF(COUNT(*), 0)
             AS decimal(5,2))                                  AS otd_pct,

        CAST(AVG(CAST(f.days_late AS float)) AS decimal(7,2))  AS avg_days_late,
        MAX(f.days_late)                                       AS max_days_late,

        SUM(f.RECEIVED_QTY)                                    AS total_received_qty,
        SUM(f.rejected_qty)                                    AS total_rejected_qty,
        SUM(f.had_rejection)                                   AS receipts_with_rejection,
        CAST(100.0 * SUM(f.rejected_qty) / NULLIF(SUM(f.RECEIVED_QTY + f.rejected_qty), 0)
             AS decimal(5,2))                                  AS reject_pct,

        SUM(COALESCE(f.receipt_value, 0))                      AS total_spend,
        MIN(f.RECEIVED_DATE)                                   AS first_receipt_in_window,
        MAX(f.RECEIVED_DATE)                                   AS last_receipt_in_window
    FROM flagged f
    GROUP BY f.SITE_ID, f.VENDOR_ID
)

SELECT
    va.SITE_ID,
    va.VENDOR_ID,
    v.NAME                                          AS vendor_name,

    va.unique_pos,
    va.unique_parts,
    va.total_receipts,

    va.on_time_receipts,
    va.late_receipts,
    va.otd_pct,
    va.avg_days_late,
    va.max_days_late,

    va.total_received_qty,
    va.total_rejected_qty,
    va.receipts_with_rejection,
    va.reject_pct,

    va.total_spend,
    CAST(va.total_spend / NULLIF(va.total_receipts, 0) AS decimal(22,2)) AS avg_spend_per_receipt,

    va.first_receipt_in_window,
    va.last_receipt_in_window,

    CASE
        WHEN va.otd_pct >= 95 AND va.reject_pct <  1 THEN 'A - PREFERRED'
        WHEN va.otd_pct >= 85 AND va.reject_pct <  2 THEN 'B - ACCEPTABLE'
        WHEN va.otd_pct >= 70                        THEN 'C - NEEDS IMPROVEMENT'
        ELSE                                               'D - AT RISK'
    END                                              AS vendor_tier
FROM vendor_agg va
LEFT JOIN VENDOR v
    ON v.ID = va.VENDOR_ID
WHERE va.total_receipts >= @MinReceipts
ORDER BY va.total_spend DESC, va.otd_pct ASC;
