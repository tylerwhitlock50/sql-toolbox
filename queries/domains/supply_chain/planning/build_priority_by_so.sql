/*
===============================================================================
Query Name: build_priority_by_so.sql

Purpose:
    Answer the CEO question: "Of our backorder, what can I actually ship
    today, and which orders should I push through first?"

    For every open sales-order line, walk the engineering-master BOM to
    compute MAX_BUILDABLE_NOW = MIN over components of (on_hand / qty_per).
    Then rank lines by: past-due weight * line value * (1 - buildable share).

    This pairs with material_shortage_vs_open_demand.sql (which is
    component-centric) by inverting the lens to be SO-centric.

Grain:
    One row per open sales-order line that is FABRICATED (or that has
    components -- a purchased item resold also gets a row, with the part
    itself as its only "component").

Key columns:
    OPEN_QTY             - ORDER_QTY - TOTAL_SHIPPED_QTY (stocking UM)
    ISOLATED_BUILDABLE   - max units of this SO line we could complete if
                           we had 100% access to current on-hand. NOT
                           shared/allocated across other SOs -- this is the
                           upper bound, not the realistic share.
    BUILDABLE_PCT        - ISOLATED_BUILDABLE / OPEN_QTY
    TOP3_SHORT_COMPONENTS- CSV of the 3 components most limiting the build
    DAYS_PAST_DUE        - days since DESIRED_SHIP_DATE (negative = future)
    PRIORITY_SCORE       - sortable composite (see notes)
    SHIP_TODAY_VALUE     - $ that could ship today if we built ISOLATED_BUILDABLE

Important caveat:
    Buildability is computed PER-LINE in isolation. Two SO lines competing
    for the same scarce component will both show their isolated max. Use
    this for prioritization, not for issuing build commitments.

Priority score:
    Composite = (urgency factor) * line_$ * (1 + buildable_pct)
       urgency = max(1, days_past_due) for past due,
                 1 / max(1, days_until_due) for future
    Higher = build first. This biases toward past-due, high-$ lines that
    can actually be built.
===============================================================================
*/

DECLARE @Site     nvarchar(15) = NULL;
DECLARE @MaxDepth int          = 20;

;WITH
-- ============================================================
-- Open SO lines (top assemblies to build)
-- ============================================================
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
        COALESCE(col.PROMISE_DATE, col.DESIRED_SHIP_DATE, co.DESIRED_SHIP_DATE) AS NEED_DATE
    FROM CUST_ORDER_LINE col
    INNER JOIN CUSTOMER_ORDER co ON co.ID = col.CUST_ORDER_ID
    LEFT  JOIN CUSTOMER cust     ON cust.ID = co.CUSTOMER_ID
    WHERE co.STATUS    IN ('R','F')
      AND col.LINE_STATUS = 'A'
      AND col.ORDER_QTY > col.TOTAL_SHIPPED_QTY
      AND col.PART_ID IS NOT NULL
      AND (@Site IS NULL OR col.SITE_ID = @Site)
),

-- ============================================================
-- BOM walk anchored on each open SO line
--   - level 0 = the top part itself (qty_per_assembly = 1)
--   - level N = each REQUIREMENT line, accumulating qty_per
-- ============================================================
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

-- ============================================================
-- Aggregate qty_per_assembly to one row per
--    (SO_LINE, COMPONENT_PART) summed across paths.
-- For the buildable calc we only care about LEAF components
-- (purchased / no-master fabricated / phantom) since fab parts
-- with masters get rolled up into their components.
-- We keep level >= 1 because level 0 is the top part itself,
-- which is what we're trying to BUILD (not consume on-hand of).
-- ============================================================
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

-- ============================================================
-- Per-component buildability for each SO line
-- ============================================================
component_buildability AS (
    SELECT
        cd.SITE_ID,
        cd.CUST_ORDER_ID,
        cd.LINE_NO,
        cd.COMPONENT_PART_ID,
        cd.QTY_PER_ASSEMBLY,
        ISNULL(psv.QTY_ON_HAND, 0) AS COMPONENT_ON_HAND,
        psv.FABRICATED             AS COMP_FABRICATED,
        psv.PURCHASED              AS COMP_PURCHASED,
        psv.UNIT_MATERIAL_COST     AS COMP_UNIT_COST,
        -- How many units of the top assembly this component, in isolation, supports
        CASE
            WHEN cd.QTY_PER_ASSEMBLY > 0
                THEN ISNULL(psv.QTY_ON_HAND, 0) / cd.QTY_PER_ASSEMBLY
            ELSE 0
        END AS UNITS_THIS_COMPONENT_SUPPORTS
    FROM component_demand cd
    LEFT JOIN PART_SITE_VIEW psv
        ON psv.PART_ID = cd.COMPONENT_PART_ID
       AND psv.SITE_ID = cd.SITE_ID
),

-- ============================================================
-- Per-SO-line: minimum across components (the binding constraint)
-- and CSV of top-3 short components
-- ============================================================
line_constraint AS (
    SELECT
        cb.SITE_ID,
        cb.CUST_ORDER_ID,
        cb.LINE_NO,
        MIN(cb.UNITS_THIS_COMPONENT_SUPPORTS) AS ISOLATED_BUILDABLE_RAW,
        COUNT(*)                              AS COMPONENT_COUNT,
        SUM(CASE WHEN cb.COMPONENT_ON_HAND <= 0 THEN 1 ELSE 0 END) AS COMPONENTS_AT_ZERO
    FROM component_buildability cb
    GROUP BY cb.SITE_ID, cb.CUST_ORDER_ID, cb.LINE_NO
),

short_ranked AS (
    SELECT
        cb.SITE_ID,
        cb.CUST_ORDER_ID,
        cb.LINE_NO,
        cb.COMPONENT_PART_ID,
        cb.UNITS_THIS_COMPONENT_SUPPORTS,
        ROW_NUMBER() OVER (
            PARTITION BY cb.SITE_ID, cb.CUST_ORDER_ID, cb.LINE_NO
            ORDER BY cb.UNITS_THIS_COMPONENT_SUPPORTS ASC, cb.COMPONENT_PART_ID
        ) AS RNK
    FROM component_buildability cb
),

short_csv AS (
    SELECT
        s.SITE_ID, s.CUST_ORDER_ID, s.LINE_NO,
        STUFF((
            SELECT ', ' + s2.COMPONENT_PART_ID
                   + ' (' + CAST(CAST(s2.UNITS_THIS_COMPONENT_SUPPORTS AS decimal(20,2)) AS nvarchar(40)) + ')'
            FROM short_ranked s2
            WHERE s2.SITE_ID       = s.SITE_ID
              AND s2.CUST_ORDER_ID = s.CUST_ORDER_ID
              AND s2.LINE_NO       = s.LINE_NO
              AND s2.RNK <= 3
            ORDER BY s2.RNK
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)'), 1, 2, '') AS TOP3_SHORT_COMPONENTS
    FROM (SELECT DISTINCT SITE_ID, CUST_ORDER_ID, LINE_NO FROM short_ranked) s
)

-- ============================================================
-- Final: tie everything together, score, sort
-- ============================================================
SELECT
    s.SITE_ID,
    s.CUST_ORDER_ID,
    s.LINE_NO,
    s.PART_ID,
    psv.DESCRIPTION,
    psv.PRODUCT_CODE,
    s.CUSTOMER_ID,
    s.CUSTOMER_NAME,
    s.NEED_DATE,
    DATEDIFF(day, CAST(GETDATE() AS date), s.NEED_DATE) AS DAYS_UNTIL_NEED,
    CASE WHEN s.NEED_DATE < CAST(GETDATE() AS date)
         THEN DATEDIFF(day, s.NEED_DATE, CAST(GETDATE() AS date))
         ELSE 0
    END AS DAYS_PAST_DUE,
    s.ORDER_QTY,
    s.TOTAL_SHIPPED_QTY,
    s.OPEN_QTY,
    s.UNIT_PRICE,
    s.LINE_OPEN_VALUE,

    lc.COMPONENT_COUNT,
    lc.COMPONENTS_AT_ZERO,

    -- Cap buildable at the open qty (we never need more than open_qty)
    CAST(
        CASE
            WHEN lc.ISOLATED_BUILDABLE_RAW IS NULL THEN s.OPEN_QTY
            WHEN lc.ISOLATED_BUILDABLE_RAW > s.OPEN_QTY THEN s.OPEN_QTY
            ELSE lc.ISOLATED_BUILDABLE_RAW
        END
    AS decimal(20,4)) AS ISOLATED_BUILDABLE,

    CAST(
        CASE
            WHEN s.OPEN_QTY = 0 THEN 0
            WHEN lc.ISOLATED_BUILDABLE_RAW IS NULL THEN 100
            WHEN lc.ISOLATED_BUILDABLE_RAW >= s.OPEN_QTY THEN 100
            ELSE 100.0 * lc.ISOLATED_BUILDABLE_RAW / s.OPEN_QTY
        END
    AS decimal(7,2)) AS BUILDABLE_PCT,

    CAST(
        CASE
            WHEN s.OPEN_QTY = 0 THEN 0
            WHEN lc.ISOLATED_BUILDABLE_RAW IS NULL THEN s.LINE_OPEN_VALUE
            WHEN lc.ISOLATED_BUILDABLE_RAW >= s.OPEN_QTY THEN s.LINE_OPEN_VALUE
            ELSE s.LINE_OPEN_VALUE * lc.ISOLATED_BUILDABLE_RAW / s.OPEN_QTY
        END
    AS decimal(23,2)) AS SHIP_TODAY_VALUE,

    sc.TOP3_SHORT_COMPONENTS,

    CASE
        WHEN lc.ISOLATED_BUILDABLE_RAW IS NULL                 THEN 'NO BOM (CHECK MASTER)'
        WHEN lc.ISOLATED_BUILDABLE_RAW >= s.OPEN_QTY
             AND s.NEED_DATE < CAST(GETDATE() AS date)         THEN 'SHIP NOW (PAST DUE, FULLY BUILDABLE)'
        WHEN lc.ISOLATED_BUILDABLE_RAW >= s.OPEN_QTY           THEN 'FULLY BUILDABLE'
        WHEN lc.ISOLATED_BUILDABLE_RAW > 0
             AND s.NEED_DATE < CAST(GETDATE() AS date)         THEN 'PARTIAL SHIP (PAST DUE)'
        WHEN lc.ISOLATED_BUILDABLE_RAW > 0                     THEN 'PARTIAL BUILDABLE'
        WHEN s.NEED_DATE < CAST(GETDATE() AS date)             THEN 'BLOCKED (PAST DUE)'
        ELSE                                                        'BLOCKED'
    END AS BUILD_STATUS,

    -- Priority score: high = build first
    CAST(
        CASE
            WHEN s.NEED_DATE < CAST(GETDATE() AS date)
                THEN DATEDIFF(day, s.NEED_DATE, CAST(GETDATE() AS date)) * 1.0
            ELSE 1.0 / NULLIF(DATEDIFF(day, CAST(GETDATE() AS date), s.NEED_DATE), 0)
        END
        * s.LINE_OPEN_VALUE
        * (1 +
           CASE
               WHEN s.OPEN_QTY = 0 THEN 0
               WHEN lc.ISOLATED_BUILDABLE_RAW IS NULL THEN 1
               WHEN lc.ISOLATED_BUILDABLE_RAW >= s.OPEN_QTY THEN 1
               ELSE lc.ISOLATED_BUILDABLE_RAW / s.OPEN_QTY
           END)
    AS decimal(28,2)) AS PRIORITY_SCORE

FROM open_so s
LEFT JOIN line_constraint lc
    ON  lc.SITE_ID       = s.SITE_ID
    AND lc.CUST_ORDER_ID = s.CUST_ORDER_ID
    AND lc.LINE_NO       = s.LINE_NO
LEFT JOIN short_csv sc
    ON  sc.SITE_ID       = s.SITE_ID
    AND sc.CUST_ORDER_ID = s.CUST_ORDER_ID
    AND sc.LINE_NO       = s.LINE_NO
LEFT JOIN PART_SITE_VIEW psv
    ON psv.PART_ID = s.PART_ID AND psv.SITE_ID = s.SITE_ID
ORDER BY
    PRIORITY_SCORE DESC,
    DAYS_PAST_DUE  DESC,
    s.LINE_OPEN_VALUE DESC
OPTION (MAXRECURSION 0);
