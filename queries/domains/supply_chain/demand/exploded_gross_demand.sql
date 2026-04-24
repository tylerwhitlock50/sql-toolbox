/*
===============================================================================
Query Name: exploded_gross_demand.sql

Purpose:
    Take every demand row from total_demand_by_part.sql and walk it through
    the engineering-master BOM to produce COMPONENT-LEVEL gross requirements.
    This is the link that closes the gap between "we have a forecast" and
    "we know what we need to build / buy in what quantity."

    Without this query, planning has to look at each top assembly's demand
    one at a time. With it, you get a single row-per-component answer to:

        "Across all open sales orders + master schedule + forecast, how much
         of THIS part do we need, by when, and is it make or buy?"

Grain (final output):
    One row per (SITE_ID, COMPONENT_PART_ID, NEED_DATE, DEMAND_SOURCE,
                 SOURCE_REF, BOM_LEVEL).
    A part that appears in multiple sub-assemblies of the same demand line
    will have its qty summed across paths.

Key linkage (per repo memory):
    PART_SITE.ENGINEERING_MSTR -> WORK_ORDER.LOT_ID,
    master WO is TYPE='M', SPLIT_ID='0', SUB_ID='0', BASE_ID = PART_ID.
    REQUIREMENT.STATUS = 'U' (NOT 'A') for the live master BOM.
    Per-assembly yield = REQUIREMENT.CALC_QTY / WORK_ORDER.DESIRED_QTY
    (CALC_QTY already includes scrap, so we do NOT add a scrap multiplier).

Component class:
    TOP                  - the demanded top part itself (level 0)
    FABRICATED_EXPLODED  - fabricated part with a master, walked into
    FABRICATED_NO_MASTER - fabricated part missing a master (DATA GAP)
    PURCHASED_LEAF       - purchased component (this is what to BUY)
    OTHER_LEAF           - phantom / detail-only / stocked leaf

ORDER_BY_DATE:
    Demand NEED_DATE minus the COMPONENT's PLANNING_LEADTIME (days). This
    is the date by which the buy/build must start to make the demand date.

Notes:
    * Cycle guard via PATH string (CHARINDEX), max depth defaults to 20.
    * Top part is emitted as level 0 so build_priority / net_requirements
      can plan to BUILD it as well as buy its components.
    * If a demand part has no engineering master, level 0 is still emitted
      and the row is flagged COMPONENT_CLASS = 'FABRICATED_NO_MASTER' or
      'PURCHASED_LEAF' as appropriate.

Reuse / companion queries:
    Wraps the demand union from total_demand_by_part.sql inline (so this
    query is self-contained and can be run on its own).
    Mirrors the recursive walk pattern of recursive_bom_from_masters.sql.
===============================================================================
*/

DECLARE @Site     nvarchar(15) = NULL;   -- NULL = all sites
DECLARE @MaxDepth int          = 20;

;WITH demand AS (
    -- ---- Sales backorder ----
    SELECT
        col.SITE_ID,
        col.PART_ID,
        COALESCE(col.PROMISE_DATE, col.DESIRED_SHIP_DATE, co.DESIRED_SHIP_DATE) AS NEED_DATE,
        CAST('SO_BACKORDER' AS nvarchar(20))     AS DEMAND_SOURCE,
        CAST(1 AS tinyint)                       AS DEMAND_PRIORITY,
        col.ORDER_QTY - col.TOTAL_SHIPPED_QTY    AS DEMAND_QTY,
        col.CUST_ORDER_ID + '/' + CAST(col.LINE_NO AS nvarchar(10)) AS SOURCE_REF
    FROM CUST_ORDER_LINE col
    INNER JOIN CUSTOMER_ORDER co ON co.ID = col.CUST_ORDER_ID
    WHERE co.STATUS    IN ('R','F')
      AND col.LINE_STATUS = 'A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
      AND col.PART_ID  IS NOT NULL
      AND (@Site IS NULL OR col.SITE_ID = @Site)

    UNION ALL

    -- ---- Master schedule (firm + un-firm) ----
    SELECT
        ms.SITE_ID,
        ms.PART_ID,
        ms.WANT_DATE,
        CASE WHEN ms.FIRMED = 'Y' THEN 'MS_FIRM' ELSE 'MS_FORECAST' END,
        CASE WHEN ms.FIRMED = 'Y' THEN 2 ELSE 3 END,
        ms.ORDER_QTY,
        ms.MASTER_SCHEDULE_ID
    FROM MASTER_SCHEDULE ms
    WHERE ms.ORDER_QTY > 0
      AND (@Site IS NULL OR ms.SITE_ID = @Site)

    UNION ALL

    -- ---- Forecast ----
    SELECT
        df.SITE_ID,
        df.PART_ID,
        df.REQUIRED_DATE,
        'FORECAST',
        4,
        df.REQUIRED_QTY,
        CAST(df.ROWID AS nvarchar(20))
    FROM DEMAND_FORECAST df
    WHERE df.REQUIRED_QTY > 0
      AND (@Site IS NULL OR df.SITE_ID = @Site)
),

-- Aggregate demand to one row per (site, part, date, source, ref) so we
-- don't double-walk the BOM for duplicate keys.
demand_agg AS (
    SELECT
        SITE_ID, PART_ID, NEED_DATE, DEMAND_SOURCE, DEMAND_PRIORITY, SOURCE_REF,
        SUM(DEMAND_QTY) AS DEMAND_QTY
    FROM demand
    GROUP BY SITE_ID, PART_ID, NEED_DATE, DEMAND_SOURCE, DEMAND_PRIORITY, SOURCE_REF
),

bom AS
(
    -- ---- Anchor: level 0 = the demanded top part itself ----
    --   GROSS_REQ at level 0 = the demand qty
    --   This row lets net_requirements / build_priority plan the parent
    --   build as well as the components.
    SELECT
        CAST(0 AS int)                          AS BOM_LEVEL,
        d.SITE_ID,
        d.NEED_DATE,
        d.DEMAND_SOURCE,
        d.DEMAND_PRIORITY,
        d.SOURCE_REF,
        d.PART_ID                               AS BUILD_PART_ID,
        d.PART_ID                               AS COMPONENT_PART_ID,
        CAST(d.DEMAND_QTY AS decimal(28,8))     AS GROSS_QTY,
        CAST(NULL AS smallint)                  AS OPERATION_SEQ_NO,
        CAST(NULL AS smallint)                  AS PIECE_NO,
        CAST(NULL AS decimal(20,8))             AS QTY_PER,
        CAST('/' + d.PART_ID + '/' AS nvarchar(4000)) AS PATH
    FROM demand_agg d

    UNION ALL

    -- ---- Recursive: explode each fabricated component that has a master ----
    SELECT
        parent.BOM_LEVEL + 1,
        parent.SITE_ID,
        parent.NEED_DATE,
        parent.DEMAND_SOURCE,
        parent.DEMAND_PRIORITY,
        parent.SOURCE_REF,
        wo.PART_ID                              AS BUILD_PART_ID,
        rq.PART_ID                              AS COMPONENT_PART_ID,
        CAST(parent.GROSS_QTY
             * (rq.CALC_QTY / NULLIF(wo.DESIRED_QTY, 0)) AS decimal(28,8)) AS GROSS_QTY,
        rq.OPERATION_SEQ_NO,
        rq.PIECE_NO,
        rq.QTY_PER,
        CAST(parent.PATH + rq.PART_ID + '/' AS nvarchar(4000))
    FROM   bom                parent
    JOIN   PART_SITE_VIEW     psv
           ON  psv.PART_ID = parent.COMPONENT_PART_ID
           AND psv.SITE_ID = parent.SITE_ID
           AND psv.FABRICATED = 'Y'
           AND psv.ENGINEERING_MSTR IS NOT NULL
    JOIN   WORK_ORDER         wo
           ON  wo.TYPE     = 'M'
           AND wo.BASE_ID  = psv.PART_ID
           AND wo.LOT_ID   = CAST(psv.ENGINEERING_MSTR AS nvarchar(3))
           AND wo.SPLIT_ID = '0'
           AND wo.SUB_ID   = '0'
           AND wo.SITE_ID  = psv.SITE_ID
    JOIN   REQUIREMENT        rq
           ON  rq.WORKORDER_TYPE     = wo.TYPE
           AND rq.WORKORDER_BASE_ID  = wo.BASE_ID
           AND rq.WORKORDER_LOT_ID   = wo.LOT_ID
           AND rq.WORKORDER_SPLIT_ID = wo.SPLIT_ID
           AND rq.WORKORDER_SUB_ID   = wo.SUB_ID
    WHERE  rq.PART_ID IS NOT NULL
      AND  rq.STATUS   = 'U'
      AND  parent.BOM_LEVEL < @MaxDepth
      AND  CHARINDEX('/' + rq.PART_ID + '/', parent.PATH) = 0   -- cycle guard
),

-- Aggregate to one row per (site, component, need_date, source, ref, level)
exploded AS (
    SELECT
        b.SITE_ID,
        b.COMPONENT_PART_ID,
        b.NEED_DATE,
        b.DEMAND_SOURCE,
        b.DEMAND_PRIORITY,
        b.SOURCE_REF,
        MIN(b.BOM_LEVEL)             AS BOM_LEVEL,    -- shallowest path wins for reporting
        MIN(b.BUILD_PART_ID)          AS BUILD_PART_ID,
        SUM(b.GROSS_QTY)              AS GROSS_REQUIRED_QTY
    FROM bom b
    GROUP BY
        b.SITE_ID, b.COMPONENT_PART_ID, b.NEED_DATE, b.DEMAND_SOURCE,
        b.DEMAND_PRIORITY, b.SOURCE_REF
)

SELECT
    e.SITE_ID,
    e.COMPONENT_PART_ID                         AS PART_ID,
    psv.DESCRIPTION,
    psv.PRODUCT_CODE,
    psv.COMMODITY_CODE,
    psv.STOCK_UM,
    psv.FABRICATED,
    psv.PURCHASED,
    psv.STOCKED,
    psv.DETAIL_ONLY,
    psv.PLANNING_LEADTIME,
    psv.PLANNER_USER_ID,
    psv.BUYER_USER_ID,
    psv.PREF_VENDOR_ID,
    psv.ABC_CODE,
    psv.UNIT_MATERIAL_COST,

    -- Make-vs-buy classification (drives downstream routing)
    CASE
        WHEN psv.PURCHASED = 'Y' AND ISNULL(psv.FABRICATED,'N') <> 'Y' THEN 'BUY'
        WHEN psv.FABRICATED = 'Y'                                      THEN 'MAKE'
        WHEN psv.DETAIL_ONLY = 'Y'                                     THEN 'PHANTOM'
        ELSE 'OTHER'
    END AS MAKE_OR_BUY,

    -- Tie-back to BOM walk classification
    CASE
        WHEN e.BOM_LEVEL = 0                                              THEN 'TOP'
        WHEN psv.FABRICATED = 'Y' AND psv.ENGINEERING_MSTR IS NULL        THEN 'FABRICATED_NO_MASTER'
        WHEN psv.FABRICATED = 'Y' AND m_wo.BASE_ID IS NULL                THEN 'FABRICATED_NO_MASTER'
        WHEN psv.FABRICATED = 'Y'                                         THEN 'FABRICATED_EXPLODED'
        WHEN psv.PURCHASED  = 'Y'                                         THEN 'PURCHASED_LEAF'
        WHEN psv.DETAIL_ONLY = 'Y'                                        THEN 'PHANTOM'
        ELSE                                                                  'OTHER_LEAF'
    END AS COMPONENT_CLASS,

    e.BOM_LEVEL,
    e.BUILD_PART_ID,
    e.DEMAND_SOURCE,
    e.DEMAND_PRIORITY,
    e.SOURCE_REF,
    e.NEED_DATE,
    e.GROSS_REQUIRED_QTY,

    -- Order-by-date = need_date - component planning lead time
    DATEADD(day, -ISNULL(psv.PLANNING_LEADTIME, 0), e.NEED_DATE) AS ORDER_BY_DATE,

    -- Extended std cost of this gross requirement
    CAST(e.GROSS_REQUIRED_QTY * psv.UNIT_MATERIAL_COST AS decimal(23,4)) AS EXTENDED_MATERIAL_COST_AT_STD,

    DATEDIFF(day, CAST(GETDATE() AS date), e.NEED_DATE) AS DAYS_UNTIL_NEED
FROM exploded e
LEFT JOIN PART_SITE_VIEW psv
       ON  psv.PART_ID = e.COMPONENT_PART_ID
       AND psv.SITE_ID = e.SITE_ID
LEFT JOIN WORK_ORDER     m_wo
       ON  m_wo.TYPE     = 'M'
       AND m_wo.BASE_ID  = psv.PART_ID
       AND m_wo.LOT_ID   = CAST(psv.ENGINEERING_MSTR AS nvarchar(3))
       AND m_wo.SPLIT_ID = '0'
       AND m_wo.SUB_ID   = '0'
       AND m_wo.SITE_ID  = psv.SITE_ID
ORDER BY
    e.SITE_ID,
    e.COMPONENT_PART_ID,
    e.NEED_DATE,
    e.DEMAND_PRIORITY
OPTION (MAXRECURSION 0);
