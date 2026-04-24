/*
===============================================================================
Query Name: so_fulfillment_risk.sql

Purpose:
    Per open sales-order line, surface SPECIFIC blocking components and the
    next inbound supply that would unblock them.

    Where build_priority_by_so.sql says "this line can build N now", and
    shared_buildable_allocation.sql says "after priority allocation, you
    actually get M", THIS query says:

        "Line X is blocked by 3 components: A is short 50 (next PO 12345
         due 2026-05-12), B is short 12 (no PO -- buyer must place one),
         C is short 8 (open WO 9876 due 2026-04-30)."

    Designed for the customer-service rep / planner who has to call a
    customer with a status, or for the buyer who has to escalate POs.

Grain:
    One row per (SITE_ID, CUST_ORDER_ID, LINE_NO, BLOCKING_COMPONENT_PART).
    A line that needs nothing emitted no rows. A line that's blocked by 4
    components emits 4 rows.

Columns of interest:
    BLOCKING_COMPONENT_PART      -- what's short
    QTY_SHORT_FOR_THIS_LINE      -- total open requirement minus on-hand
    NEXT_SUPPLY_TYPE             -- 'PO' | 'WO' | 'PLANNED' | 'NONE'
    NEXT_SUPPLY_REF              -- PO id, WO key, planned-order ROWID
    NEXT_SUPPLY_DATE             -- expected receipt
    NEXT_SUPPLY_QTY              -- expected qty (clears the shortage if >= short)
    EXPECTED_UNBLOCK_DATE        -- earliest date all blockers clear
    UNBLOCK_STATUS               -- 'WILL UNBLOCK' | 'PARTIAL' | 'NO SUPPLY PLANNED'

Notes:
    Compat-safe. Single recursive CTE for BOM walk. Shortage uses isolated
    on-hand (no allocation against other SO lines) so this is the upper-
    bound expectation.
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

bom AS (
    SELECT
        CAST(0 AS int)                          AS BOM_LEVEL,
        s.SITE_ID, s.CUST_ORDER_ID, s.LINE_NO,
        s.PART_ID                               AS COMPONENT_PART_ID,
        CAST(1 AS decimal(28,8))                AS QTY_PER_ASSEMBLY,
        CAST('/' + s.PART_ID + '/' AS nvarchar(4000)) AS PATH
    FROM open_so s
    UNION ALL
    SELECT
        parent.BOM_LEVEL + 1, parent.SITE_ID, parent.CUST_ORDER_ID, parent.LINE_NO,
        rq.PART_ID,
        CAST(parent.QTY_PER_ASSEMBLY * (rq.CALC_QTY / NULLIF(wo.DESIRED_QTY,0)) AS decimal(28,8)),
        CAST(parent.PATH + rq.PART_ID + '/' AS nvarchar(4000))
    FROM bom parent
    JOIN PART_SITE_VIEW psv
         ON psv.PART_ID=parent.COMPONENT_PART_ID AND psv.SITE_ID=parent.SITE_ID
         AND psv.FABRICATED='Y' AND psv.ENGINEERING_MSTR IS NOT NULL
    JOIN WORK_ORDER wo
         ON wo.TYPE='M' AND wo.BASE_ID=psv.PART_ID
         AND wo.LOT_ID=CAST(psv.ENGINEERING_MSTR AS nvarchar(3))
         AND wo.SPLIT_ID='0' AND wo.SUB_ID='0' AND wo.SITE_ID=psv.SITE_ID
    JOIN REQUIREMENT rq
         ON rq.WORKORDER_TYPE=wo.TYPE AND rq.WORKORDER_BASE_ID=wo.BASE_ID
         AND rq.WORKORDER_LOT_ID=wo.LOT_ID AND rq.WORKORDER_SPLIT_ID=wo.SPLIT_ID
         AND rq.WORKORDER_SUB_ID=wo.SUB_ID
    WHERE rq.PART_ID IS NOT NULL AND rq.STATUS='U'
      AND parent.BOM_LEVEL < @MaxDepth
      AND CHARINDEX('/' + rq.PART_ID + '/', parent.PATH) = 0
),

-- Component demand per line (qty_per * line open qty)
component_demand AS (
    SELECT
        b.SITE_ID, b.CUST_ORDER_ID, b.LINE_NO, b.COMPONENT_PART_ID,
        SUM(b.QTY_PER_ASSEMBLY) AS QTY_PER_ASSEMBLY,
        SUM(b.QTY_PER_ASSEMBLY) * MAX(s.OPEN_QTY) AS DEMAND_QTY
    FROM bom b
    JOIN open_so s
        ON s.SITE_ID=b.SITE_ID AND s.CUST_ORDER_ID=b.CUST_ORDER_ID AND s.LINE_NO=b.LINE_NO
    WHERE b.BOM_LEVEL >= 1
    GROUP BY b.SITE_ID, b.CUST_ORDER_ID, b.LINE_NO, b.COMPONENT_PART_ID
),

-- Earliest open PO supply per (site, part)
po_next AS (
    SELECT
        p.SITE_ID, pl.PART_ID,
        MIN(COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE)) AS NEXT_DATE,
        SUM(pl.ORDER_QTY - pl.TOTAL_RECEIVED_QTY)                AS TOTAL_OPEN_QTY
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl ON pl.PURC_ORDER_ID = p.ID
    WHERE ISNULL(p.STATUS,'') NOT IN ('X','C')
      AND ISNULL(pl.LINE_STATUS,'') NOT IN ('X','C')
      AND pl.PART_ID IS NOT NULL
      AND pl.ORDER_QTY > pl.TOTAL_RECEIVED_QTY
      AND (@Site IS NULL OR p.SITE_ID = @Site)
    GROUP BY p.SITE_ID, pl.PART_ID
),

-- The PO/line whose date matches NEXT_DATE (for the ref id)
po_next_ref AS (
    SELECT
        p.SITE_ID, pl.PART_ID,
        MIN(p.ID + '/' + CAST(pl.LINE_NO AS nvarchar(10))) AS NEXT_REF
    FROM PURCHASE_ORDER p
    INNER JOIN PURC_ORDER_LINE pl ON pl.PURC_ORDER_ID = p.ID
    INNER JOIN po_next pn
        ON pn.SITE_ID = p.SITE_ID AND pn.PART_ID = pl.PART_ID
       AND COALESCE(pl.DESIRED_RECV_DATE, p.DESIRED_RECV_DATE) = pn.NEXT_DATE
    WHERE ISNULL(p.STATUS,'') NOT IN ('X','C')
      AND ISNULL(pl.LINE_STATUS,'') NOT IN ('X','C')
      AND pl.PART_ID IS NOT NULL
      AND pl.ORDER_QTY > pl.TOTAL_RECEIVED_QTY
    GROUP BY p.SITE_ID, pl.PART_ID
),

-- Earliest open WO supply (fab parts being produced)
wo_next AS (
    SELECT
        wo.SITE_ID, wo.PART_ID,
        MIN(COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE)) AS NEXT_DATE,
        SUM(wo.DESIRED_QTY - wo.RECEIVED_QTY)                     AS TOTAL_OPEN_QTY
    FROM WORK_ORDER wo
    WHERE wo.TYPE='W' AND ISNULL(wo.STATUS,'') NOT IN ('X','C')
      AND wo.DESIRED_QTY > wo.RECEIVED_QTY AND wo.PART_ID IS NOT NULL
      AND (@Site IS NULL OR wo.SITE_ID = @Site)
    GROUP BY wo.SITE_ID, wo.PART_ID
),

wo_next_ref AS (
    SELECT
        wo.SITE_ID, wo.PART_ID,
        MIN(wo.TYPE + '/' + wo.BASE_ID + '/' + wo.LOT_ID
            + '/' + wo.SPLIT_ID + '/' + wo.SUB_ID) AS NEXT_REF
    FROM WORK_ORDER wo
    INNER JOIN wo_next wn
        ON wn.SITE_ID = wo.SITE_ID AND wn.PART_ID = wo.PART_ID
       AND COALESCE(wo.SCHED_FINISH_DATE, wo.DESIRED_WANT_DATE) = wn.NEXT_DATE
    WHERE wo.TYPE='W' AND ISNULL(wo.STATUS,'') NOT IN ('X','C')
      AND wo.DESIRED_QTY > wo.RECEIVED_QTY
    GROUP BY wo.SITE_ID, wo.PART_ID
),

planned_next AS (
    SELECT po.SITE_ID, po.PART_ID,
           MIN(po.WANT_DATE) AS NEXT_DATE,
           SUM(po.ORDER_QTY) AS TOTAL_OPEN_QTY
    FROM PLANNED_ORDER po
    WHERE po.WANT_DATE IS NOT NULL
      AND (@Site IS NULL OR po.SITE_ID = @Site)
    GROUP BY po.SITE_ID, po.PART_ID
),

-- Pick the earliest next-supply across PO / WO / PLANNED
next_supply AS (
    SELECT SITE_ID, PART_ID,
           MIN(NEXT_DATE) AS NEXT_SUPPLY_DATE
    FROM (
        SELECT SITE_ID, PART_ID, NEXT_DATE FROM po_next
        UNION ALL
        SELECT SITE_ID, PART_ID, NEXT_DATE FROM wo_next
        UNION ALL
        SELECT SITE_ID, PART_ID, NEXT_DATE FROM planned_next
    ) u
    WHERE NEXT_DATE IS NOT NULL
    GROUP BY SITE_ID, PART_ID
),

-- Resolve which source produced the chosen NEXT_SUPPLY_DATE
next_supply_resolved AS (
    SELECT
        ns.SITE_ID, ns.PART_ID, ns.NEXT_SUPPLY_DATE,
        CASE
            WHEN po.NEXT_DATE = ns.NEXT_SUPPLY_DATE THEN 'PO'
            WHEN wo.NEXT_DATE = ns.NEXT_SUPPLY_DATE THEN 'WO'
            WHEN pl.NEXT_DATE = ns.NEXT_SUPPLY_DATE THEN 'PLANNED'
            ELSE 'NONE'
        END AS NEXT_SUPPLY_TYPE,
        CASE
            WHEN po.NEXT_DATE = ns.NEXT_SUPPLY_DATE THEN po.TOTAL_OPEN_QTY
            WHEN wo.NEXT_DATE = ns.NEXT_SUPPLY_DATE THEN wo.TOTAL_OPEN_QTY
            WHEN pl.NEXT_DATE = ns.NEXT_SUPPLY_DATE THEN pl.TOTAL_OPEN_QTY
            ELSE 0
        END AS NEXT_SUPPLY_QTY,
        CASE
            WHEN po.NEXT_DATE = ns.NEXT_SUPPLY_DATE THEN por.NEXT_REF
            WHEN wo.NEXT_DATE = ns.NEXT_SUPPLY_DATE THEN wor.NEXT_REF
            WHEN pl.NEXT_DATE = ns.NEXT_SUPPLY_DATE THEN '(planned-order)'
            ELSE NULL
        END AS NEXT_SUPPLY_REF
    FROM next_supply ns
    LEFT JOIN po_next       po  ON po.SITE_ID = ns.SITE_ID  AND po.PART_ID  = ns.PART_ID
    LEFT JOIN po_next_ref   por ON por.SITE_ID = ns.SITE_ID AND por.PART_ID = ns.PART_ID
    LEFT JOIN wo_next       wo  ON wo.SITE_ID = ns.SITE_ID  AND wo.PART_ID  = ns.PART_ID
    LEFT JOIN wo_next_ref   wor ON wor.SITE_ID = ns.SITE_ID AND wor.PART_ID = ns.PART_ID
    LEFT JOIN planned_next  pl  ON pl.SITE_ID = ns.SITE_ID  AND pl.PART_ID  = ns.PART_ID
)

SELECT
    s.SITE_ID,
    s.CUST_ORDER_ID,
    s.LINE_NO,
    s.PART_ID                                    AS SO_PART_ID,
    psv_top.DESCRIPTION                          AS SO_PART_DESC,
    s.CUSTOMER_ID,
    s.CUSTOMER_NAME,
    s.OPEN_QTY,
    s.UNIT_PRICE,
    s.LINE_OPEN_VALUE,
    s.NEED_DATE,
    CASE WHEN s.NEED_DATE < CAST(GETDATE() AS date)
         THEN DATEDIFF(day, s.NEED_DATE, CAST(GETDATE() AS date))
         ELSE 0 END                              AS DAYS_PAST_DUE,

    cd.COMPONENT_PART_ID                         AS BLOCKING_COMPONENT_PART,
    psv_c.DESCRIPTION                            AS COMPONENT_DESCRIPTION,
    psv_c.PURCHASED, psv_c.FABRICATED,
    psv_c.PREF_VENDOR_ID                         AS COMP_PREF_VENDOR_ID,
    psv_c.BUYER_USER_ID                          AS COMP_BUYER,
    cd.QTY_PER_ASSEMBLY,
    cd.DEMAND_QTY                                AS DEMAND_FOR_LINE,
    ISNULL(psv_c.QTY_ON_HAND, 0)                 AS COMPONENT_ON_HAND,
    CAST(
        CASE WHEN cd.DEMAND_QTY > ISNULL(psv_c.QTY_ON_HAND, 0)
             THEN cd.DEMAND_QTY - ISNULL(psv_c.QTY_ON_HAND, 0)
             ELSE 0
        END AS decimal(20,4)) AS QTY_SHORT_FOR_THIS_LINE,

    nsr.NEXT_SUPPLY_TYPE,
    nsr.NEXT_SUPPLY_REF,
    nsr.NEXT_SUPPLY_DATE,
    nsr.NEXT_SUPPLY_QTY,

    CASE
        WHEN cd.DEMAND_QTY <= ISNULL(psv_c.QTY_ON_HAND,0)              THEN 'OK (NO SHORTAGE)'
        WHEN nsr.NEXT_SUPPLY_TYPE = 'NONE' OR nsr.NEXT_SUPPLY_TYPE IS NULL
                                                                       THEN 'NO SUPPLY PLANNED'
        WHEN nsr.NEXT_SUPPLY_QTY + ISNULL(psv_c.QTY_ON_HAND,0) >= cd.DEMAND_QTY
                                                                       THEN 'WILL UNBLOCK'
        ELSE                                                                'PARTIAL'
    END AS UNBLOCK_STATUS,

    -- Earliest the line can ship: latest of (component next-supply dates)
    -- Computed by re-aggregating below if you want the per-line view; here
    -- we surface this row's component date and let the user see them all
    -- by sorting on (CUST_ORDER_ID, LINE_NO, NEXT_SUPPLY_DATE DESC).
    nsr.NEXT_SUPPLY_DATE                         AS THIS_COMPONENT_UNBLOCK_DATE

FROM open_so s
INNER JOIN component_demand cd
    ON  cd.SITE_ID=s.SITE_ID AND cd.CUST_ORDER_ID=s.CUST_ORDER_ID AND cd.LINE_NO=s.LINE_NO
LEFT  JOIN PART_SITE_VIEW psv_top
    ON  psv_top.SITE_ID=s.SITE_ID AND psv_top.PART_ID=s.PART_ID
LEFT  JOIN PART_SITE_VIEW psv_c
    ON  psv_c.SITE_ID=cd.SITE_ID AND psv_c.PART_ID=cd.COMPONENT_PART_ID
LEFT  JOIN next_supply_resolved nsr
    ON  nsr.SITE_ID=cd.SITE_ID AND nsr.PART_ID=cd.COMPONENT_PART_ID
WHERE cd.DEMAND_QTY > ISNULL(psv_c.QTY_ON_HAND, 0)         -- only rows that ARE blocking
ORDER BY
    -- Past-due first, then by line value, then by worst component date
    CASE WHEN s.NEED_DATE < CAST(GETDATE() AS date) THEN 0 ELSE 1 END,
    s.LINE_OPEN_VALUE DESC,
    s.CUST_ORDER_ID, s.LINE_NO,
    nsr.NEXT_SUPPLY_DATE DESC
OPTION (MAXRECURSION 0);
