USE VECA;

WITH part_location_qty AS (
    SELECT
        part_id,
        SUM(COALESCE(qty, 0)) AS part_location_qty_on_hand
    FROM PART_LOCATION
    GROUP BY part_id
),

inventory_usage AS (
    SELECT
        it.part_id,

        SUM(
            CASE 
                WHEN it.type = 'I' THEN COALESCE(it.qty, 0)
                WHEN it.type = 'O' THEN -COALESCE(it.qty, 0)
                ELSE 0
            END
        ) AS inventory_trans_qty_on_hand,

        SUM(
            CASE 
                WHEN it.type = 'I' THEN 
                    COALESCE(it.act_material_cost, 0)
                  + COALESCE(it.act_labor_cost, 0)
                  + COALESCE(it.act_burden_cost, 0)
                  + COALESCE(it.act_service_cost, 0)

                WHEN it.type = 'O' THEN 
                    -1 * (
                        COALESCE(it.act_material_cost, 0)
                      + COALESCE(it.act_labor_cost, 0)
                      + COALESCE(it.act_burden_cost, 0)
                      + COALESCE(it.act_service_cost, 0)
                    )
                ELSE 0
            END
        ) AS inventory_trans_value_on_hand,

        SUM(CASE WHEN it.type = 'O' AND it.class = 'I' THEN COALESCE(it.qty, 0) ELSE 0 END) AS total_issues,

        SUM(CASE WHEN it.type = 'O' AND it.class = 'I' AND it.transaction_date >= DATEADD(DAY, -30,  GETDATE()) THEN COALESCE(it.qty, 0) ELSE 0 END) AS issues_30_day,
        SUM(CASE WHEN it.type = 'O' AND it.class = 'I' AND it.transaction_date >= DATEADD(DAY, -60,  GETDATE()) THEN COALESCE(it.qty, 0) ELSE 0 END) AS issues_60_day,
        SUM(CASE WHEN it.type = 'O' AND it.class = 'I' AND it.transaction_date >= DATEADD(DAY, -90,  GETDATE()) THEN COALESCE(it.qty, 0) ELSE 0 END) AS issues_90_day,
        SUM(CASE WHEN it.type = 'O' AND it.class = 'I' AND it.transaction_date >= DATEADD(DAY, -180, GETDATE()) THEN COALESCE(it.qty, 0) ELSE 0 END) AS issues_180_day,
        SUM(CASE WHEN it.type = 'O' AND it.class = 'I' AND it.transaction_date >= DATEADD(DAY, -360, GETDATE()) THEN COALESCE(it.qty, 0) ELSE 0 END) AS issues_360_day,

        SUM(CASE WHEN it.type = 'O' AND it.class = 'A' AND it.transfer_trans_id IS NULL THEN COALESCE(it.qty, 0) ELSE 0 END) AS total_adjust_outs,
        SUM(CASE WHEN it.type = 'I' AND it.class = 'A' AND it.transfer_trans_id IS NULL THEN COALESCE(it.qty, 0) ELSE 0 END) AS total_adjust_ins,

        SUM(CASE WHEN it.class = 'A' AND it.transfer_trans_id IS NULL THEN ABS(COALESCE(it.qty, 0)) ELSE 0 END) AS total_adjustment_qty,

        SUM(CASE WHEN it.type = 'O' AND it.class = 'A' AND it.transfer_trans_id IS NULL AND it.transaction_date >= DATEADD(DAY, -360, GETDATE()) THEN COALESCE(it.qty, 0) ELSE 0 END) AS adjust_outs_360_day,
        SUM(CASE WHEN it.type = 'I' AND it.class = 'A' AND it.transfer_trans_id IS NULL AND it.transaction_date >= DATEADD(DAY, -360, GETDATE()) THEN COALESCE(it.qty, 0) ELSE 0 END) AS adjust_ins_360_day,
        SUM(CASE WHEN it.class = 'A' AND it.transfer_trans_id IS NULL AND it.transaction_date >= DATEADD(DAY, -360, GETDATE()) THEN ABS(COALESCE(it.qty, 0)) ELSE 0 END) AS adjustment_qty_360_day,

        MAX(it.transaction_date) AS last_inventory_transaction_date,
        MAX(CASE WHEN it.type = 'O' AND it.class = 'I' THEN it.transaction_date END) AS last_issue_date,
        MAX(CASE WHEN it.class = 'A' AND it.transfer_trans_id IS NULL THEN it.transaction_date END) AS last_adjustment_date

    FROM inventory_trans it
    WHERE it.part_id IS NOT NULL
    GROUP BY it.part_id
),

inventory_base AS (
    SELECT
        COALESCE(iu.part_id, pl.part_id) AS part_id,
        ps.description AS part_description,
        ps.buyer_user_id AS buyer_id,
        ps.commodity_code,
        ps.product_code AS product_code,
        

        COALESCE(ps.unit_material_cost, 0)
      + COALESCE(ps.unit_labor_cost, 0)
      + COALESCE(ps.unit_burden_cost, 0)
      + COALESCE(ps.unit_service_cost, 0) AS standard_cost,

        COALESCE(iu.inventory_trans_qty_on_hand, 0) AS inventory_trans_qty_on_hand,
        COALESCE(iu.inventory_trans_value_on_hand, 0) AS inventory_value_on_hand_actual,
        COALESCE(pl.part_location_qty_on_hand, 0) AS part_location_qty_on_hand,

        COALESCE(pl.part_location_qty_on_hand, 0)
            - COALESCE(iu.inventory_trans_qty_on_hand, 0) AS qty_on_hand_difference,

        COALESCE(iu.issues_30_day, 0) AS issues_30_day,
        COALESCE(iu.issues_60_day, 0) AS issues_60_day,
        COALESCE(iu.issues_90_day, 0) AS issues_90_day,
        COALESCE(iu.issues_180_day, 0) AS issues_180_day,
        COALESCE(iu.issues_360_day, 0) AS issues_360_day,

        COALESCE(iu.total_adjust_ins, 0) AS total_adjust_ins,
        COALESCE(iu.total_adjust_outs, 0) AS total_adjust_outs,
        COALESCE(iu.total_adjustment_qty, 0) AS total_adjustment_qty,

        COALESCE(iu.adjust_ins_360_day, 0) AS adjust_ins_360_day,
        COALESCE(iu.adjust_outs_360_day, 0) AS adjust_outs_360_day,
        COALESCE(iu.adjustment_qty_360_day, 0) AS adjustment_qty_360_day,

        iu.last_inventory_transaction_date,
        iu.last_issue_date,
        iu.last_adjustment_date

    FROM inventory_usage iu
    FULL OUTER JOIN part_location_qty pl
        ON iu.part_id = pl.part_id
    JOIN part_site_view ps
        ON ps.part_id = COALESCE(iu.part_id, pl.part_id)
),

inventory_calc AS (
    SELECT
        *,

        inventory_value_on_hand_actual AS inventory_value_on_hand,

part_location_qty_on_hand * standard_cost AS inventory_value_on_hand_standard_estimate,


        CASE
            WHEN part_location_qty_on_hand <> inventory_trans_qty_on_hand THEN 1
            ELSE 0
        END AS qty_mismatch_flag,

        CASE
            WHEN part_location_qty_on_hand > 0
            THEN issues_360_day / NULLIF(part_location_qty_on_hand, 0)
            ELSE NULL
        END AS annual_turns,

        -- Weeks / months on hand: same denominator as annual_turns, just expressed
        -- as a duration of cover instead of a turnover ratio. Undefined (NULL)
        -- when there have been no issues in the trailing 360 days.
        CASE
            WHEN issues_360_day > 0
            THEN 52.0 * part_location_qty_on_hand / NULLIF(issues_360_day, 0)
            ELSE NULL
        END AS weeks_on_hand,

        CASE
            WHEN issues_360_day > 0
            THEN 12.0 * part_location_qty_on_hand / NULLIF(issues_360_day, 0)
            ELSE NULL
        END AS months_on_hand,

        CASE
            WHEN adjustment_qty_360_day >= 10 THEN 1
            WHEN issues_360_day > 0
                 AND adjustment_qty_360_day / NULLIF(issues_360_day, 0) >= 0.25 THEN 1
            ELSE 0
        END AS high_adjustment_part_flag

    FROM inventory_base
)

SELECT
    part_id,
    part_description,
    buyer_id,
    commodity_code,
    product_code,
    standard_cost,

    inventory_trans_qty_on_hand,
    part_location_qty_on_hand,
    qty_on_hand_difference,
    qty_mismatch_flag,

    inventory_value_on_hand,

    issues_30_day,
    issues_60_day,
    issues_90_day,
    issues_180_day,
    issues_360_day,

    coalesce(annual_turns,0) as annual_turns,
    coalesce(weeks_on_hand,0) as weeks_on_hand,
    coalesce(months_on_hand,0) as months_on_hand,

    CASE
        WHEN annual_turns > 4 THEN 'URGENT BUY / HIGH VELOCITY'
        WHEN annual_turns >= 2 THEN 'GREEN'
        WHEN annual_turns >= 1 THEN 'YELLOW'
        WHEN annual_turns < 1 THEN 'EXCESS'
        WHEN part_location_qty_on_hand > 0 AND issues_360_day = 0 THEN 'OBSOLETE / NO USAGE'
        ELSE 'NO STOCK / NO USAGE'
    END AS inventory_bucket,

    --values

    CASE
    WHEN annual_turns > 4
    THEN inventory_value_on_hand_actual
    ELSE 0
END AS urgent_buy_inventory_value,

CASE 
    WHEN annual_turns >= 2 AND annual_turns <= 4
    THEN inventory_value_on_hand_actual
    ELSE 0
END AS green_inventory_value,

CASE 
    WHEN annual_turns >= 1 AND annual_turns < 2
    THEN inventory_value_on_hand_actual
    ELSE 0
END AS yellow_inventory_value,

CASE 
    WHEN annual_turns < 1
    THEN inventory_value_on_hand_actual
    ELSE 0
END AS excess_inventory_value,

CASE
    WHEN part_location_qty_on_hand > 0
         AND issues_360_day = 0
    THEN inventory_value_on_hand_actual
    ELSE 0
END AS obsolete_inventory_value,

    CASE
        WHEN annual_turns < 1
        THEN (part_location_qty_on_hand - issues_360_day) * standard_cost
        ELSE 0
    END AS excess_over_one_year_usage_value,

    CASE
        WHEN annual_turns > 1
        THEN (issues_360_day - part_location_qty_on_hand) * standard_cost
        ELSE 0
    END AS estimated_annual_buy_need_value,

    total_adjust_ins,
    total_adjust_outs,
    total_adjustment_qty,
    adjust_ins_360_day,
    adjust_outs_360_day,
    adjustment_qty_360_day,
    high_adjustment_part_flag,

    last_inventory_transaction_date,
    last_issue_date,
    last_adjustment_date,

    CASE
    WHEN annual_turns IS NULL THEN 'No Stock / No Usage'
    WHEN annual_turns = 0 THEN 'No Usage'
    WHEN annual_turns < 1
        THEN CONCAT(
            FORMAT(FLOOR(annual_turns * 10) / 10.0, '0.0'),
            ' - ',
            FORMAT((FLOOR(annual_turns * 10) + 1) / 10.0, '0.0')
        )
    WHEN annual_turns < 2 THEN '1.0 - 2.0'
    WHEN annual_turns < 4 THEN '2.0 - 4.0'
    ELSE '4.0+'
END AS turns_bucket

FROM inventory_calc
ORDER BY
    urgent_buy_inventory_value DESC,
    obsolete_inventory_value DESC,
    excess_inventory_value DESC,
    inventory_value_on_hand DESC;
