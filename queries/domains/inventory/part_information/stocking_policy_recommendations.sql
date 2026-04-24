/*
===============================================================================
Query Name: stocking_policy_recommendations.sql

Purpose:
    Recommend SAFETY STOCK and REORDER POINT for each part based on
    observed demand variability and lead-time variability, and compare
    to the values currently set in PART_SITE_VIEW.

    Output drives a planner review: for each part, do we have too much
    safety stock (cash tied up) or too little (stockout risk)? Are we
    using a stale ROP that no longer reflects reality?

Method (standard normal approximation):
    SS  = z * sqrt(LT_mo * sigma_d^2 + d_avg^2 * sigma_LT_mo^2)
    ROP = d_avg * LT_mo + SS

    where (working in monthly units):
        d_avg        = mean monthly issue qty (T12)
        sigma_d      = stddev of monthly issue qty (T12)
        LT_mo        = lead time mean (days / 30)
        sigma_LT_mo  = lead time stddev (days / 30)
        z            = service-level multiplier
                       (1.28 = 90%, 1.65 = 95%, 2.05 = 98%, 2.33 = 99%)

Demand source:
    INVENTORY_TRANS where TYPE='O' (issues out) over @DemandLookbackMonths.
    Includes WO issues + customer-order issues = real consumption signal.

Lead-time source:
    Same logic as vendor_lead_time_history.sql -- INVENTORY_TRANS receipts
    joined to PURCHASE_ORDER, RECEIPT_DATE - ORDER_DATE in days.

Action flag:
    INCREASE SS  recommended SS > current SS by > 50% AND > 5 units
    DECREASE SS  recommended SS < current SS by > 50% AND current > 5 units
    NEW POLICY   no current SS set but recommended > 0
    NO HISTORY   too few demand or LT observations -- don't change anything
    OK           difference within tolerance

Notes:
    Compat-safe (manual median in vendor_lead_time_history; here we use
    AVG and STDEV which are SQL 2005+).
    Recommendation is a starting point -- planners should overlay product
    knowledge (single-source vs multi-source, criticality, shelf life).
===============================================================================
*/

DECLARE @Site                  nvarchar(15) = NULL;
DECLARE @DemandLookbackMonths  int          = 12;
DECLARE @LTLookbackMonths      int          = 18;
DECLARE @ServiceLevelZ         decimal(5,2) = 1.65;   -- 95% service level
DECLARE @MinDemandObs          int          = 4;      -- months with usage
DECLARE @MinLTObs              int          = 2;      -- LT observations
DECLARE @SignificantDeltaPct   decimal(6,2) = 50.0;
DECLARE @SignificantDeltaQty   decimal(20,4) = 5.0;

;WITH
-- ============================================================
-- Demand: monthly issue qty per (site, part)
-- ============================================================
issues AS (
    SELECT
        it.SITE_ID, it.PART_ID,
        DATEADD(month, DATEDIFF(month, 0, it.TRANSACTION_DATE), 0) AS YEAR_MONTH,
        SUM(it.QTY) AS QTY
    FROM INVENTORY_TRANS it
    WHERE it.TYPE = 'O'
      AND it.PART_ID IS NOT NULL
      AND it.QTY > 0
      AND it.TRANSACTION_DATE >= DATEADD(month, -@DemandLookbackMonths, GETDATE())
      AND (@Site IS NULL OR it.SITE_ID = @Site)
    GROUP BY it.SITE_ID, it.PART_ID,
             DATEADD(month, DATEDIFF(month, 0, it.TRANSACTION_DATE), 0)
),

demand_stats AS (
    SELECT
        SITE_ID, PART_ID,
        COUNT(*)                                             AS DEMAND_MONTHS,
        SUM(QTY)                                             AS T_DEMAND_QTY,
        CAST(AVG(CAST(QTY AS decimal(20,4))) AS decimal(20,4)) AS DEMAND_AVG_PER_MONTH,
        CAST(STDEV(QTY)                      AS decimal(20,4)) AS DEMAND_STDDEV_PER_MONTH
    FROM issues
    GROUP BY SITE_ID, PART_ID
),

-- ============================================================
-- Lead time observations: receipt date - PO order date
-- ============================================================
lt_obs AS (
    SELECT
        it.SITE_ID, it.PART_ID,
        DATEDIFF(day, p.ORDER_DATE, it.TRANSACTION_DATE) AS LT_DAYS
    FROM INVENTORY_TRANS it
    INNER JOIN PURCHASE_ORDER p ON p.ID = it.PURC_ORDER_ID
    WHERE it.TYPE='I' AND it.CLASS='R'
      AND it.PURC_ORDER_ID IS NOT NULL
      AND it.PART_ID IS NOT NULL
      AND p.ORDER_DATE IS NOT NULL
      AND it.QTY > 0
      AND it.TRANSACTION_DATE >= DATEADD(month, -@LTLookbackMonths, GETDATE())
      AND DATEDIFF(day, p.ORDER_DATE, it.TRANSACTION_DATE) BETWEEN 0 AND 365
      AND (@Site IS NULL OR it.SITE_ID = @Site)
),

lt_stats AS (
    SELECT
        SITE_ID, PART_ID,
        COUNT(*)                                              AS LT_OBS,
        CAST(AVG(CAST(LT_DAYS AS decimal(10,2))) AS decimal(10,2)) AS LT_AVG_DAYS,
        CAST(STDEV(LT_DAYS) AS decimal(10,2))                 AS LT_STDDEV_DAYS
    FROM lt_obs
    GROUP BY SITE_ID, PART_ID
)

-- ============================================================
-- Per-part recommendation
-- ============================================================
SELECT
    psv.SITE_ID,
    psv.PART_ID,
    psv.DESCRIPTION,
    psv.PRODUCT_CODE,
    psv.COMMODITY_CODE,
    psv.STOCK_UM,
    psv.FABRICATED, psv.PURCHASED,
    psv.PLANNER_USER_ID, psv.BUYER_USER_ID,
    psv.ABC_CODE,
    psv.PREF_VENDOR_ID,
    psv.UNIT_MATERIAL_COST,

    -- Current ERP policy
    psv.PLANNING_LEADTIME                       AS CURRENT_LT_DAYS,
    psv.SAFETY_STOCK_QTY                        AS CURRENT_SS,
    psv.ORDER_POINT                             AS CURRENT_ROP,
    psv.MINIMUM_ORDER_QTY                       AS CURRENT_MOQ,
    psv.MULTIPLE_ORDER_QTY                      AS CURRENT_MULT,
    psv.QTY_ON_HAND                             AS CURRENT_ON_HAND,

    -- Demand stats
    ISNULL(ds.DEMAND_MONTHS, 0)                 AS DEMAND_MONTHS_OBSERVED,
    CAST(ISNULL(ds.T_DEMAND_QTY, 0) AS decimal(20,4)) AS T_DEMAND_QTY,
    ds.DEMAND_AVG_PER_MONTH,
    ds.DEMAND_STDDEV_PER_MONTH,

    -- Lead-time stats
    ISNULL(ls.LT_OBS, 0)                        AS LT_OBSERVED,
    ls.LT_AVG_DAYS,
    ls.LT_STDDEV_DAYS,

    -- Recommendation (working in monthly units; LT/30, sigma_LT/30)
    CAST(@ServiceLevelZ AS decimal(5,2))        AS SERVICE_Z,
    CAST(
        CASE
            WHEN ds.DEMAND_AVG_PER_MONTH IS NULL
              OR ls.LT_AVG_DAYS         IS NULL
                THEN NULL
            ELSE
                @ServiceLevelZ
                * SQRT(
                    (ls.LT_AVG_DAYS / 30.0)
                      * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                      * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                    + ds.DEMAND_AVG_PER_MONTH * ds.DEMAND_AVG_PER_MONTH
                      * ((ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0)
                         * (ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0))
                )
        END
    AS decimal(20,2)) AS RECOMMENDED_SS,

    CAST(
        CASE
            WHEN ds.DEMAND_AVG_PER_MONTH IS NULL
              OR ls.LT_AVG_DAYS         IS NULL
                THEN NULL
            ELSE
                ds.DEMAND_AVG_PER_MONTH * (ls.LT_AVG_DAYS / 30.0)
                + @ServiceLevelZ
                  * SQRT(
                      (ls.LT_AVG_DAYS / 30.0)
                        * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                        * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                      + ds.DEMAND_AVG_PER_MONTH * ds.DEMAND_AVG_PER_MONTH
                        * ((ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0)
                           * (ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0))
                  )
        END
    AS decimal(20,2)) AS RECOMMENDED_ROP,

    -- Delta vs current
    CAST(
        CASE
            WHEN ds.DEMAND_AVG_PER_MONTH IS NULL OR ls.LT_AVG_DAYS IS NULL THEN NULL
            ELSE
                @ServiceLevelZ
                * SQRT(
                    (ls.LT_AVG_DAYS / 30.0)
                      * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                      * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                    + ds.DEMAND_AVG_PER_MONTH * ds.DEMAND_AVG_PER_MONTH
                      * ((ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0)
                         * (ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0))
                )
                - ISNULL(psv.SAFETY_STOCK_QTY, 0)
        END
    AS decimal(20,2)) AS SS_DELTA,

    CAST(
        ISNULL(psv.UNIT_MATERIAL_COST, 0)
        * CASE
              WHEN ds.DEMAND_AVG_PER_MONTH IS NULL OR ls.LT_AVG_DAYS IS NULL THEN 0
              ELSE
                  @ServiceLevelZ
                  * SQRT(
                      (ls.LT_AVG_DAYS / 30.0)
                        * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                        * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                      + ds.DEMAND_AVG_PER_MONTH * ds.DEMAND_AVG_PER_MONTH
                        * ((ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0)
                           * (ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0))
                  )
                  - ISNULL(psv.SAFETY_STOCK_QTY, 0)
          END
    AS decimal(23,2)) AS SS_DELTA_VALUE_AT_STD,

    -- Demand variability summary (for the planner's eye)
    CAST(
        CASE WHEN ds.DEMAND_AVG_PER_MONTH IS NULL OR ds.DEMAND_AVG_PER_MONTH = 0 THEN NULL
             ELSE 100.0 * ds.DEMAND_STDDEV_PER_MONTH / ds.DEMAND_AVG_PER_MONTH
        END AS decimal(10,2)) AS DEMAND_CV_PCT,

    CASE
        WHEN ISNULL(ds.DEMAND_MONTHS, 0) < @MinDemandObs
          OR ISNULL(ls.LT_OBS, 0)        < @MinLTObs
            THEN 'NO HISTORY'
        WHEN ISNULL(psv.SAFETY_STOCK_QTY, 0) = 0
            THEN 'NEW POLICY'
        WHEN ABS(
                @ServiceLevelZ
                * SQRT(
                    (ls.LT_AVG_DAYS / 30.0)
                      * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                      * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                    + ds.DEMAND_AVG_PER_MONTH * ds.DEMAND_AVG_PER_MONTH
                      * ((ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0)
                         * (ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0))
                )
                - psv.SAFETY_STOCK_QTY
             ) < @SignificantDeltaQty
            THEN 'OK'
        WHEN @ServiceLevelZ
             * SQRT(
                 (ls.LT_AVG_DAYS / 30.0)
                   * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                   * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                 + ds.DEMAND_AVG_PER_MONTH * ds.DEMAND_AVG_PER_MONTH
                   * ((ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0)
                      * (ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0))
             )
             > psv.SAFETY_STOCK_QTY * (1 + @SignificantDeltaPct/100.0)
            THEN 'INCREASE SS'
        WHEN @ServiceLevelZ
             * SQRT(
                 (ls.LT_AVG_DAYS / 30.0)
                   * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                   * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                 + ds.DEMAND_AVG_PER_MONTH * ds.DEMAND_AVG_PER_MONTH
                   * ((ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0)
                      * (ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0))
             )
             < psv.SAFETY_STOCK_QTY * (1 - @SignificantDeltaPct/100.0)
            THEN 'DECREASE SS'
        ELSE 'OK'
    END AS POLICY_ACTION

FROM PART_SITE_VIEW psv
LEFT JOIN demand_stats ds ON ds.SITE_ID=psv.SITE_ID AND ds.PART_ID=psv.PART_ID
LEFT JOIN lt_stats     ls ON ls.SITE_ID=psv.SITE_ID AND ls.PART_ID=psv.PART_ID
WHERE (@Site IS NULL OR psv.SITE_ID = @Site)
  AND psv.PURCHASED = 'Y'
  AND ISNULL(psv.STATUS, '') NOT IN ('I')      -- skip inactive
  AND (ISNULL(ds.DEMAND_MONTHS, 0) >= @MinDemandObs
       OR ISNULL(psv.SAFETY_STOCK_QTY, 0) > 0)  -- only parts with history or current policy
ORDER BY
    CASE
        WHEN ISNULL(ds.DEMAND_MONTHS, 0) < @MinDemandObs
          OR ISNULL(ls.LT_OBS, 0)        < @MinLTObs THEN 4
        WHEN ISNULL(psv.SAFETY_STOCK_QTY, 0) = 0     THEN 1
        WHEN @ServiceLevelZ
             * SQRT(
                 (ls.LT_AVG_DAYS / 30.0)
                   * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                   * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                 + ds.DEMAND_AVG_PER_MONTH * ds.DEMAND_AVG_PER_MONTH
                   * ((ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0)
                      * (ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0))
             ) > psv.SAFETY_STOCK_QTY * (1 + @SignificantDeltaPct/100.0) THEN 2
        WHEN psv.SAFETY_STOCK_QTY > 0
         AND @ServiceLevelZ
             * SQRT(
                 (ls.LT_AVG_DAYS / 30.0)
                   * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                   * ISNULL(ds.DEMAND_STDDEV_PER_MONTH, 0)
                 + ds.DEMAND_AVG_PER_MONTH * ds.DEMAND_AVG_PER_MONTH
                   * ((ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0)
                      * (ISNULL(ls.LT_STDDEV_DAYS, 0) / 30.0))
             ) < psv.SAFETY_STOCK_QTY * (1 - @SignificantDeltaPct/100.0) THEN 3
        ELSE 5
    END,
    psv.SITE_ID,
    psv.PART_ID;
