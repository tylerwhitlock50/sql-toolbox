/*
===============================================================================
Query Name: shared_buildable_allocation.sql

Purpose:
    Companion to build_priority_by_so.sql.

    build_priority_by_so reports each SO line's ISOLATED buildable quantity
    (the upper bound if no other SO existed). When two SOs need the same
    scarce part, both reports show their isolated max -- which double-counts.

    THIS query allocates inventory in PRIORITY order so each line's
    REALISTIC buildable accounts for the on-hand already claimed by
    higher-priority lines.

Algorithm:
    1. Compute one row per (open SO line, leaf component) with qty_per
       (cumulative through the BOM).
    2. Compute total demand per component across all SO lines.
    3. Rank SO lines globally by priority (past-due weight * line $).
    4. For each (component, line), cumulative demand above this line in
       priority order = SUM(higher-priority lines' demand for this comp).
    5. Allocated to this line = MIN(my demand, on_hand - cum_above).
    6. Buildable units this line gets via this component = allocated /
       qty_per.
    7. Per-line REALISTIC_BUILDABLE = MIN over components of step 6.

Output:
    One row per open SO line with both the realistic-allocated buildable
    AND the isolated buildable side-by-side. The DELTA shows how much
    competition with higher-priority SOs costs the line.

Use cases:
    - Hand out a credible "you can ship N today" answer per SO
    - Drive operations to focus on the lines whose REALISTIC_BUILDABLE
      is materially below their isolated max (constrained by competition)
    - Identify the components that gate the most lines

Notes:
    Compat-safe (uses ROW_NUMBER, correlated subqueries -- no PERCENTILE_CONT).
    Priority formula matches build_priority_by_so.sql so ranks line up.
===============================================================================
*/

DECLARE @Site     nvarchar(15) = NULL;
DECLARE @MaxDepth int          = 20;

;WITH
open_so AS (
    SELECT
        col.SITE_ID,
        col.CUST_ORDER_ID,
        col.LINE_NO,
        col.PART_ID,
        co.CUSTOMER_ID,
        cust.NAME                              AS CUSTOMER_NAME,
        col.ORDER_QTY,
        col.TOTAL_SHIPPED_QTY,
        col.ORDER_QTY - col.TOTAL_SHIPPED_QTY  AS OPEN_QTY,
        col.UNIT_PRICE,
        (col.ORDER_QTY - col.TOTAL_SHIPPED_QTY) * col.UNIT_PRICE AS LINE_OPEN_VALUE,
        COALESCE(col.PROMISE_DATE, col.DESIRED_SHIP_DATE, co.DESIRED_SHIP_DATE) AS NEED_DATE,
        -- Priority score (mirror of build_priority_by_so.sql, simplified
        -- to past-due weight * value -- we don't multiply by buildable here
        -- because that would create a circular definition)
        CASE
            WHEN COALESCE(col.PROMISE_DATE, col.DESIRED_SHIP_DATE, co.DESIRED_SHIP_DATE)
                 < CAST(GETDATE() AS date)
            THEN DATEDIFF(day,
                          COALESCE(col.PROMISE_DATE, col.DESIRED_SHIP_DATE, co.DESIRED_SHIP_DATE),
                          CAST(GETDATE() AS date)) * 1.0
                 * (col.ORDER_QTY - col.TOTAL_SHIPPED_QTY) * col.UNIT_PRICE
            ELSE
                1.0 / NULLIF(DATEDIFF(day, CAST(GETDATE() AS date),
                              COALESCE(col.PROMISE_DATE, col.DESIRED_SHIP_DATE, co.DESIRED_SHIP_DATE)), 0)
                 * (col.ORDER_QTY - col.TOTAL_SHIPPED_QTY) * col.UNIT_PRICE
        END AS PRIORITY_SCORE_RAW
    FROM CUST_ORDER_LINE col
    INNER JOIN CUSTOMER_ORDER co ON co.ID = col.CUST_ORDER_ID
    LEFT  JOIN CUSTOMER cust     ON cust.ID = co.CUSTOMER_ID
    WHERE co.STATUS    IN ('R','F')
      AND col.LINE_STATUS = 'A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
      AND col.PART_ID IS NOT NULL
      AND (@Site IS NULL OR col.SITE_ID = @Site)
),

bom AS (
    SELECT
        CAST(0 AS int)                          AS BOM_LEVEL,
        s.SITE_ID,
        s.CUST_ORDER_ID,
        s.LINE_NO,
        s.PART_ID                               AS COMPONENT_PART_ID,
        CAST(1 AS decimal(28,8))                AS QTY_PER_ASSEMBLY,
        CAST('/' + s.PART_ID + '/' AS nvarchar(4000)) AS PATH
    FROM open_so s

    UNION ALL

    SELECT
        parent.BOM_LEVEL + 1,
        parent.SITE_ID,
        parent.CUST_ORDER_ID,
        parent.LINE_NO,
        rq.PART_ID,
        CAST(parent.QTY_PER_ASSEMBLY * (rq.CALC_QTY / NULLIF(wo.DESIRED_QTY,0)) AS decimal(28,8)),
        CAST(parent.PATH + rq.PART_ID + '/' AS nvarchar(4000))
    FROM bom parent
    JOIN PART_SITE_VIEW psv
         ON  psv.PART_ID = parent.COMPONENT_PART_ID
         AND psv.SITE_ID = parent.SITE_ID
         AND psv.FABRICATED = 'Y'
         AND psv.ENGINEERING_MSTR IS NOT NULL
    JOIN WORK_ORDER wo
         ON  wo.TYPE='M' AND wo.BASE_ID=psv.PART_ID
         AND wo.LOT_ID=CAST(psv.ENGINEERING_MSTR AS nvarchar(3))
         AND wo.SPLIT_ID='0' AND wo.SUB_ID='0' AND wo.SITE_ID=psv.SITE_ID
    JOIN REQUIREMENT rq
         ON  rq.WORKORDER_TYPE=wo.TYPE AND rq.WORKORDER_BASE_ID=wo.BASE_ID
         AND rq.WORKORDER_LOT_ID=wo.LOT_ID AND rq.WORKORDER_SPLIT_ID=wo.SPLIT_ID
         AND rq.WORKORDER_SUB_ID=wo.SUB_ID
    WHERE rq.PART_ID IS NOT NULL AND rq.STATUS='U'
      AND parent.BOM_LEVEL < @MaxDepth
      AND CHARINDEX('/' + rq.PART_ID + '/', parent.PATH) = 0
),

-- Per (SO line, leaf component): qty_per_assembly summed across paths
component_demand AS (
    SELECT
        b.SITE_ID,
        b.CUST_ORDER_ID,
        b.LINE_NO,
        b.COMPONENT_PART_ID,
        SUM(b.QTY_PER_ASSEMBLY) AS QTY_PER_ASSEMBLY
    FROM bom b
    WHERE b.BOM_LEVEL >= 1
    GROUP BY b.SITE_ID, b.CUST_ORDER_ID, b.LINE_NO, b.COMPONENT_PART_ID
),

-- Demand qty by line × component = qty_per_assembly * line open qty
line_component_demand AS (
    SELECT
        cd.SITE_ID,
        cd.CUST_ORDER_ID,
        cd.LINE_NO,
        cd.COMPONENT_PART_ID,
        cd.QTY_PER_ASSEMBLY,
        s.OPEN_QTY,
        s.PRIORITY_SCORE_RAW,
        cd.QTY_PER_ASSEMBLY * s.OPEN_QTY AS DEMAND_FOR_THIS_LINE
    FROM component_demand cd
    INNER JOIN open_so s
        ON s.SITE_ID=cd.SITE_ID AND s.CUST_ORDER_ID=cd.CUST_ORDER_ID
       AND s.LINE_NO =cd.LINE_NO
),

-- Rank lines per component by priority (highest priority first = rank 1)
ranked AS (
    SELECT
        l.*,
        ROW_NUMBER() OVER (
            PARTITION BY l.SITE_ID, l.COMPONENT_PART_ID
            ORDER BY l.PRIORITY_SCORE_RAW DESC,
                     l.CUST_ORDER_ID, l.LINE_NO
        ) AS PRIORITY_RANK_FOR_COMPONENT
    FROM line_component_demand l
),

-- For each (line, component): cumulative demand from higher-priority lines
cum_demand AS (
    SELECT
        r1.SITE_ID,
        r1.CUST_ORDER_ID,
        r1.LINE_NO,
        r1.COMPONENT_PART_ID,
        r1.QTY_PER_ASSEMBLY,
        r1.OPEN_QTY,
        r1.DEMAND_FOR_THIS_LINE,
        r1.PRIORITY_RANK_FOR_COMPONENT,
        ISNULL(
            (SELECT SUM(r2.DEMAND_FOR_THIS_LINE)
             FROM ranked r2
             WHERE r2.SITE_ID            = r1.SITE_ID
               AND r2.COMPONENT_PART_ID  = r1.COMPONENT_PART_ID
               AND r2.PRIORITY_RANK_FOR_COMPONENT < r1.PRIORITY_RANK_FOR_COMPONENT),
            0
        ) AS CUM_DEMAND_FROM_HIGHER_PRIORITY
    FROM ranked r1
),

-- Allocate component to this line: how much of on-hand survives the higher-priority
allocation AS (
    SELECT
        cd.*,
        ISNULL(psv.QTY_ON_HAND, 0)             AS COMPONENT_ON_HAND,
        CASE
            WHEN ISNULL(psv.QTY_ON_HAND, 0) <= cd.CUM_DEMAND_FROM_HIGHER_PRIORITY
                THEN 0
            WHEN ISNULL(psv.QTY_ON_HAND, 0) - cd.CUM_DEMAND_FROM_HIGHER_PRIORITY
                  >= cd.DEMAND_FOR_THIS_LINE
                THEN cd.DEMAND_FOR_THIS_LINE
            ELSE
                ISNULL(psv.QTY_ON_HAND, 0) - cd.CUM_DEMAND_FROM_HIGHER_PRIORITY
        END AS ALLOCATED_QTY,
        psv.UNIT_MATERIAL_COST                 AS COMP_UNIT_COST
    FROM cum_demand cd
    LEFT JOIN PART_SITE_VIEW psv
        ON psv.SITE_ID = cd.SITE_ID
       AND psv.PART_ID = cd.COMPONENT_PART_ID
),

-- Per-line: realistic buildable = MIN over components of allocated/qty_per
line_realistic AS (
    SELECT
        a.SITE_ID,
        a.CUST_ORDER_ID,
        a.LINE_NO,
        MIN(
            CASE WHEN a.QTY_PER_ASSEMBLY > 0
                 THEN a.ALLOCATED_QTY / a.QTY_PER_ASSEMBLY
                 ELSE 0
            END
        ) AS REALISTIC_BUILDABLE_RAW,
        MIN(
            CASE WHEN a.QTY_PER_ASSEMBLY > 0 AND a.COMPONENT_ON_HAND > 0
                 THEN a.COMPONENT_ON_HAND / a.QTY_PER_ASSEMBLY
                 ELSE 0
            END
        ) AS ISOLATED_BUILDABLE_RAW
    FROM allocation a
    GROUP BY a.SITE_ID, a.CUST_ORDER_ID, a.LINE_NO
),

-- Top-3 components blocking this line under SHARED allocation
short_ranked AS (
    SELECT
        a.SITE_ID, a.CUST_ORDER_ID, a.LINE_NO, a.COMPONENT_PART_ID,
        a.ALLOCATED_QTY,
        a.QTY_PER_ASSEMBLY,
        CASE WHEN a.QTY_PER_ASSEMBLY > 0
             THEN a.ALLOCATED_QTY / a.QTY_PER_ASSEMBLY
             ELSE 0
        END AS UNITS_THIS_COMP_SUPPORTS,
        ROW_NUMBER() OVER (
            PARTITION BY a.SITE_ID, a.CUST_ORDER_ID, a.LINE_NO
            ORDER BY CASE WHEN a.QTY_PER_ASSEMBLY > 0
                          THEN a.ALLOCATED_QTY / a.QTY_PER_ASSEMBLY
                          ELSE 0 END ASC,
                     a.COMPONENT_PART_ID
        ) AS RNK
    FROM allocation a
),
short_csv AS (
    SELECT
        s.SITE_ID, s.CUST_ORDER_ID, s.LINE_NO,
        STUFF((
            SELECT ', ' + s2.COMPONENT_PART_ID
                   + ' (' + CAST(CAST(s2.UNITS_THIS_COMP_SUPPORTS AS decimal(20,2)) AS nvarchar(40)) + ')'
            FROM short_ranked s2
            WHERE s2.SITE_ID=s.SITE_ID AND s2.CUST_ORDER_ID=s.CUST_ORDER_ID
              AND s2.LINE_NO =s.LINE_NO AND s2.RNK <= 3
            ORDER BY s2.RNK
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)'), 1, 2, '') AS TOP3_BLOCKING_AFTER_ALLOCATION
    FROM (SELECT DISTINCT SITE_ID, CUST_ORDER_ID, LINE_NO FROM short_ranked) s
)

SELECT
    s.SITE_ID,
    s.CUST_ORDER_ID,
    s.LINE_NO,
    s.PART_ID,
    psv.DESCRIPTION,
    s.CUSTOMER_ID,
    s.CUSTOMER_NAME,
    s.NEED_DATE,
    CASE WHEN s.NEED_DATE < CAST(GETDATE() AS date)
         THEN DATEDIFF(day, s.NEED_DATE, CAST(GETDATE() AS date))
         ELSE 0
    END                                         AS DAYS_PAST_DUE,
    s.OPEN_QTY,
    s.UNIT_PRICE,
    s.LINE_OPEN_VALUE,

    -- Isolated (build_priority_by_so view): no competition
    CAST(
        CASE
            WHEN lr.ISOLATED_BUILDABLE_RAW IS NULL THEN s.OPEN_QTY
            WHEN lr.ISOLATED_BUILDABLE_RAW > s.OPEN_QTY THEN s.OPEN_QTY
            ELSE lr.ISOLATED_BUILDABLE_RAW
        END
    AS decimal(20,4)) AS ISOLATED_BUILDABLE,

    -- Realistic (this query's contribution): after priority allocation
    CAST(
        CASE
            WHEN lr.REALISTIC_BUILDABLE_RAW IS NULL THEN 0
            WHEN lr.REALISTIC_BUILDABLE_RAW > s.OPEN_QTY THEN s.OPEN_QTY
            ELSE lr.REALISTIC_BUILDABLE_RAW
        END
    AS decimal(20,4)) AS REALISTIC_BUILDABLE,

    -- Delta: how much being lower-priority costs this line
    CAST(
        CASE
            WHEN lr.ISOLATED_BUILDABLE_RAW IS NULL THEN 0
            WHEN lr.ISOLATED_BUILDABLE_RAW > s.OPEN_QTY THEN s.OPEN_QTY
            ELSE lr.ISOLATED_BUILDABLE_RAW
        END
        -
        CASE
            WHEN lr.REALISTIC_BUILDABLE_RAW IS NULL THEN 0
            WHEN lr.REALISTIC_BUILDABLE_RAW > s.OPEN_QTY THEN s.OPEN_QTY
            ELSE lr.REALISTIC_BUILDABLE_RAW
        END
    AS decimal(20,4)) AS COMPETITION_LOSS_QTY,

    CAST(
        CASE
            WHEN s.OPEN_QTY = 0 THEN 0
            WHEN lr.REALISTIC_BUILDABLE_RAW IS NULL THEN 0
            WHEN lr.REALISTIC_BUILDABLE_RAW >= s.OPEN_QTY THEN 100
            ELSE 100.0 * lr.REALISTIC_BUILDABLE_RAW / s.OPEN_QTY
        END
    AS decimal(7,2)) AS REALISTIC_BUILDABLE_PCT,

    sc.TOP3_BLOCKING_AFTER_ALLOCATION,

    CAST(
        CASE
            WHEN s.OPEN_QTY = 0 THEN 0
            WHEN lr.REALISTIC_BUILDABLE_RAW IS NULL THEN 0
            WHEN lr.REALISTIC_BUILDABLE_RAW >= s.OPEN_QTY THEN s.LINE_OPEN_VALUE
            ELSE s.LINE_OPEN_VALUE * lr.REALISTIC_BUILDABLE_RAW / s.OPEN_QTY
        END
    AS decimal(23,2)) AS SHIP_TODAY_VALUE_REALISTIC,

    CASE
        WHEN lr.REALISTIC_BUILDABLE_RAW IS NULL                      THEN 'NO BOM'
        WHEN lr.REALISTIC_BUILDABLE_RAW >= s.OPEN_QTY                THEN 'FULLY BUILDABLE (PRIORITY-ALLOC)'
        WHEN lr.REALISTIC_BUILDABLE_RAW > 0                          THEN 'PARTIAL (PRIORITY-ALLOC)'
        WHEN lr.ISOLATED_BUILDABLE_RAW > 0
             AND lr.REALISTIC_BUILDABLE_RAW = 0                      THEN 'BLOCKED BY HIGHER-PRIORITY SO'
        ELSE                                                              'BLOCKED'
    END AS ALLOCATION_STATUS,

    s.PRIORITY_SCORE_RAW                       AS PRIORITY_SCORE
FROM open_so s
LEFT JOIN line_realistic lr
    ON  lr.SITE_ID       = s.SITE_ID
    AND lr.CUST_ORDER_ID = s.CUST_ORDER_ID
    AND lr.LINE_NO       = s.LINE_NO
LEFT JOIN short_csv sc
    ON  sc.SITE_ID       = s.SITE_ID
    AND sc.CUST_ORDER_ID = s.CUST_ORDER_ID
    AND sc.LINE_NO       = s.LINE_NO
LEFT JOIN PART_SITE_VIEW psv
    ON psv.PART_ID = s.PART_ID AND psv.SITE_ID = s.SITE_ID
ORDER BY
    s.PRIORITY_SCORE_RAW DESC,
    DAYS_PAST_DUE        DESC,
    s.LINE_OPEN_VALUE    DESC
OPTION (MAXRECURSION 0);
