WITH inv_totals AS (
    SELECT
        it.part_id,
        SUM(
            CASE 
                WHEN LOWER(it.type) = 'i' THEN ISNULL(it.qty, 0)
                ELSE -ISNULL(it.qty, 0)
            END
        ) AS net_qty_all_time,
        SUM(
            CASE 
                WHEN LOWER(it.type) = 'i' THEN
                      ISNULL(it.act_material_cost, 0)
                    + ISNULL(it.act_labor_cost, 0)
                    + ISNULL(it.act_service_cost, 0)
                    + ISNULL(it.act_burden_cost, 0)
                ELSE -(
                      ISNULL(it.act_material_cost, 0)
                    + ISNULL(it.act_labor_cost, 0)
                    + ISNULL(it.act_service_cost, 0)
                    + ISNULL(it.act_burden_cost, 0)
                )
            END
        ) AS net_cost_all_time
    FROM dbo.inventory_trans it
    GROUP BY
        it.part_id
),
usage_hist AS (
    SELECT
        it.part_id,
        SUM(CASE 
                WHEN it.type = 'O'
                 AND it.class = 'I'
                 AND it.transaction_date >= DATEADD(DAY, -7, CAST(GETDATE() AS date))
                THEN ABS(ISNULL(it.qty, 0)) 
                ELSE 0 
            END) AS used_qty_last_7d,
        SUM(CASE 
                WHEN it.type = 'O'
                 AND it.class = 'I'
                 AND it.transaction_date >= DATEADD(DAY, -30, CAST(GETDATE() AS date))
                THEN ABS(ISNULL(it.qty, 0)) 
                ELSE 0 
            END) AS used_qty_last_30d,
        SUM(CASE 
                WHEN it.type = 'O'
                 AND it.class = 'I'
                 AND it.transaction_date >= DATEADD(DAY, -90, CAST(GETDATE() AS date))
                THEN ABS(ISNULL(it.qty, 0)) 
                ELSE 0 
            END) AS used_qty_last_90d,
        SUM(CASE 
                WHEN it.type = 'O'
                 AND it.class = 'I'
                 AND it.transaction_date >= DATEADD(DAY, -180, CAST(GETDATE() AS date))
                THEN ABS(ISNULL(it.qty, 0)) 
                ELSE 0 
            END) AS used_qty_last_180d,
        SUM(CASE 
                WHEN it.type = 'O'
                 AND it.class = 'I'
                 AND it.transaction_date >= DATEADD(DAY, -365, CAST(GETDATE() AS date))
                THEN ABS(ISNULL(it.qty, 0)) 
                ELSE 0 
            END) AS used_qty_last_365d,
        COUNT(CASE 
                WHEN it.type = 'O'
                 AND it.class = 'I'
                 AND it.transaction_date >= DATEADD(DAY, -30, CAST(GETDATE() AS date))
                THEN 1 
            END) AS issue_txn_last_30d,
        COUNT(CASE 
                WHEN it.type = 'O'
                 AND it.class = 'I'
                 AND it.transaction_date >= DATEADD(DAY, -90, CAST(GETDATE() AS date))
                THEN 1 
            END) AS issue_txn_last_90d,
        COUNT(CASE 
                WHEN it.type = 'O'
                 AND it.class = 'I'
                 AND it.transaction_date >= DATEADD(DAY, -365, CAST(GETDATE() AS date))
                THEN 1 
            END) AS issue_txn_last_365d,
        MAX(CASE 
                WHEN it.type = 'O'
                 AND it.class = 'I'
                THEN it.transaction_date
            END) AS last_issue_date
    FROM dbo.inventory_trans it
    GROUP BY
        it.part_id
),
mrp AS (
    SELECT
        me.part_id,
        me.site_id,
        me.mrp_exception_info AS mrp_exception_info_raw,
        me.issue_late_days,
        me.order_late_days,
        me.release_late_days,
        me.sugg_release_late_days,
        me.order_proj_early_days,
        me.order_proj_late_days,
        me.stockout_qty,
        me.overstock_qty,
        me.release_near_flag,
        me.sugg_release_near_flag
    FROM dbo.TW_MRP_EXCEPTIONS me
),
base AS (
    SELECT
        p.part_id,
        p.site_id,
        p.engineering_mstr,
        p.description,
        p.status,

        p.stock_um,
        p.commodity_code,
        p.mfg_name,
        p.abc_code,
        p.pref_vendor_id AS preferred_vendor_id,
        p.planner_user_id,
        p.buyer_user_id,

        p.fabricated,
        p.purchased,
        p.stocked,
        p.mrp_required,
        p.mrp_exceptions,
        p.order_policy,
        p.planning_leadtime AS planning_lead_time_days,
        p.safety_stock_qty,
        p.days_of_supply,
        p.minimum_order_qty AS min_order_qty,
        p.maximum_order_qty AS max_order_qty,
        p.multiple_order_qty AS order_multiple_qty,

        ISNULL(p.qty_on_hand, 0) AS on_hand_qty,
        ISNULL(p.qty_available_mrp, 0) AS available_mrp_qty,
        ISNULL(p.qty_on_order, 0) AS on_order_qty,
        ISNULL(p.qty_in_demand, 0) AS demand_qty,
        ISNULL(p.qty_committed, 0) AS committed_qty,

        mrp.mrp_exception_info_raw,
        mrp.issue_late_days,
        mrp.order_late_days,
        mrp.release_late_days,
        mrp.sugg_release_late_days,
        mrp.order_proj_early_days,
        mrp.order_proj_late_days,
        mrp.stockout_qty,
        mrp.overstock_qty,
        mrp.release_near_flag,
        mrp.sugg_release_near_flag,

        ISNULL(u.used_qty_last_7d, 0) AS used_qty_last_7d,
        ISNULL(u.used_qty_last_30d, 0) AS used_qty_last_30d,
        ISNULL(u.used_qty_last_90d, 0) AS used_qty_last_90d,
        ISNULL(u.used_qty_last_180d, 0) AS used_qty_last_180d,
        ISNULL(u.used_qty_last_365d, 0) AS used_qty_last_365d,
        ISNULL(u.issue_txn_last_30d, 0) AS issue_txn_last_30d,
        ISNULL(u.issue_txn_last_90d, 0) AS issue_txn_last_90d,
        ISNULL(u.issue_txn_last_365d, 0) AS issue_txn_last_365d,
        u.last_issue_date,

        ISNULL(t.net_qty_all_time, 0) AS net_qty_all_time,
        ISNULL(t.net_cost_all_time, 0) AS net_cost_all_time,

        -- REPLACE THIS with the real current cost field
        CAST(NULL AS decimal(18,4)) AS current_unit_cost,

        CASE WHEN p.status = 'A' THEN 1 ELSE 0 END AS is_active,
        CASE WHEN p.stocked = 'Y' THEN 1 ELSE 0 END AS is_stocked,
        CASE WHEN p.purchased = 'Y' THEN 1 ELSE 0 END AS is_purchased,
        CASE WHEN p.fabricated = 'Y' THEN 1 ELSE 0 END AS is_fabricated,
        CASE WHEN ISNULL(mrp.stockout_qty, 0) > 0 THEN 1 ELSE 0 END AS has_stockout,
        CASE WHEN ISNULL(mrp.overstock_qty, 0) > 0 THEN 1 ELSE 0 END AS has_overstock,
        CASE 
            WHEN p.buyer_user_id IS NOT NULL 
             AND UPPER(p.buyer_user_id) LIKE '%DO NOT ORDER%' 
            THEN 1 
            ELSE 0 
        END AS do_not_order_flag,

        p.last_abc_date,
        p.create_date,
        p.modify_date,
        p.user_1,
        p.user_2 as planning_id,
        p.user_6 as UPC_CODE
    FROM dbo.part_site_view p
    LEFT JOIN mrp
        ON p.part_id = mrp.part_id
       AND p.site_id = mrp.site_id
    LEFT JOIN usage_hist u
        ON p.part_id = u.part_id
    LEFT JOIN inv_totals t
        ON p.part_id = t.part_id
)
SELECT
    b.*,

    CAST(b.used_qty_last_365d / 365.0 AS decimal(18,6)) AS avg_daily_usage_365d,

CASE
    WHEN b.used_qty_last_365d <= 0 THEN NULL
    WHEN b.on_hand_qty <= 0 THEN NULL
    ELSE CAST(b.on_hand_qty / NULLIF(b.used_qty_last_365d / 365.0, 0) AS decimal(18,2))
END AS projected_days_of_supply_365d,

CASE
    WHEN b.used_qty_last_365d <= 0 THEN NULL
    WHEN b.on_hand_qty <= 0 THEN NULL
    WHEN (b.on_hand_qty / NULLIF(b.used_qty_last_365d / 365.0, 0)) > 3650 THEN NULL
    ELSE DATEADD(
        DAY,
        CAST(b.on_hand_qty / NULLIF(b.used_qty_last_365d / 365.0, 0) AS int),
        CAST(GETDATE() AS date)
    )
END AS expected_depletion_date,

    CASE
        WHEN b.used_qty_last_365d <= 0 THEN 0
        WHEN b.on_hand_qty <= b.used_qty_last_365d THEN b.on_hand_qty
        ELSE b.used_qty_last_365d
    END AS active_qty,

    CASE
        WHEN b.used_qty_last_365d <= 0 THEN 0
        WHEN b.on_hand_qty > b.used_qty_last_365d THEN b.on_hand_qty - b.used_qty_last_365d
        ELSE 0
    END AS excess_qty,

    CASE
        WHEN b.used_qty_last_365d <= 0 AND b.on_hand_qty > 0 THEN b.on_hand_qty
        ELSE 0
    END AS obsolete_qty,

    CASE
        WHEN b.current_unit_cost IS NULL THEN NULL
        WHEN b.used_qty_last_365d <= 0 THEN 0
        WHEN b.on_hand_qty <= b.used_qty_last_365d THEN b.on_hand_qty * b.current_unit_cost
        ELSE b.used_qty_last_365d * b.current_unit_cost
    END AS active_value,

    CASE
        WHEN b.current_unit_cost IS NULL THEN NULL
        WHEN b.used_qty_last_365d <= 0 THEN 0
        WHEN b.on_hand_qty > b.used_qty_last_365d THEN (b.on_hand_qty - b.used_qty_last_365d) * b.current_unit_cost
        ELSE 0
    END AS excess_value,

    CASE
        WHEN b.current_unit_cost IS NULL THEN NULL
        WHEN b.used_qty_last_365d <= 0 AND b.on_hand_qty > 0 THEN b.on_hand_qty * b.current_unit_cost
        ELSE 0
    END AS obsolete_value
FROM base b;