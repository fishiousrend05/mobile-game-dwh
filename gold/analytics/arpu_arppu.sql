-- =============================================================
-- gold/analytics/arpu_arppu.sql
-- ARPU / ARPPU ranking theo channel và trend theo tháng.
--
-- Khác với mart_arpu:
--   mart_arpu aggregate theo ngày/tuần/tháng — không có chiều channel.
--   Query này tính ARPU/ARPPU breakdown theo acquisition_channel
--   để trả lời "channel nào đang generate revenue hiệu quả nhất?"
--
-- Hai phần:
--   Part 1: Monthly ARPU/ARPPU × channel (ranking)
--   Part 2: Trend ARPU theo tháng toàn game (line chart)
-- =============================================================
Use game_gold;

-- ── Part 1: ARPU / ARPPU theo channel (tháng gần nhất đủ data) ───
WITH

-- Tổng hợp revenue và user count theo tháng × channel
monthly_channel AS (
    SELECT
        DATE_FORMAT(fp.purchase_date, '%Y-%m')          AS month,
        COALESCE(du.acquisition_channel, 'unknown')     AS acquisition_channel,
        SUM(fp.revenue_usd)                             AS total_revenue,
        COUNT(DISTINCT fp.user_id)                      AS paying_users,
        COUNT(*)                                        AS transactions
    FROM fact_purchases fp
    LEFT JOIN dim_users du ON du.user_id = fp.user_id
    GROUP BY
        DATE_FORMAT(fp.purchase_date, '%Y-%m'),
        COALESCE(du.acquisition_channel, 'unknown')
),

-- Active users theo tháng × channel (mẫu số của ARPU)
monthly_active_by_channel AS (
    SELECT
        DATE_FORMAT(fe.local_event_date, '%Y-%m')       AS month,
        COALESCE(du.acquisition_channel, 'unknown')     AS acquisition_channel,
        COUNT(DISTINCT fe.user_id)                      AS active_users
    FROM fact_events fe
    LEFT JOIN dim_users du ON du.user_id = fe.user_id
    GROUP BY
        DATE_FORMAT(fe.local_event_date, '%Y-%m'),
        COALESCE(du.acquisition_channel, 'unknown')
)

SELECT
    mc.month,
    mc.acquisition_channel,
    mac.active_users,
    mc.paying_users,
    ROUND(mc.total_revenue, 2)                          AS total_revenue_usd,
    mc.transactions,

    -- ARPU = revenue / active users trong tháng đó
    CASE WHEN mac.active_users > 0
         THEN ROUND(mc.total_revenue / mac.active_users, 4)
         ELSE 0 END                                     AS arpu,

    -- ARPPU = revenue / paying users trong tháng đó
    CASE WHEN mc.paying_users > 0
         THEN ROUND(mc.total_revenue / mc.paying_users, 4)
         ELSE 0 END                                     AS arppu,

    -- Conversion rate trong tháng đó
    CASE WHEN mac.active_users > 0
         THEN ROUND(mc.paying_users / mac.active_users * 100, 2)
         ELSE 0 END                                     AS paying_rate_pct,

    -- Rank channel theo ARPU trong cùng tháng
    RANK() OVER (
        PARTITION BY mc.month
        ORDER BY
            CASE WHEN mac.active_users > 0
                 THEN mc.total_revenue / mac.active_users
                 ELSE 0 END DESC
    )                                                   AS arpu_rank

FROM monthly_channel mc
LEFT JOIN monthly_active_by_channel mac
       ON mac.month              = mc.month
      AND mac.acquisition_channel = mc.acquisition_channel
ORDER BY mc.month DESC, arpu_rank
;


-- ── Part 2: Monthly ARPU trend toàn game ──────────────────────────
-- Chạy query này riêng để lấy line chart data

/*
SELECT
    period_start                                        AS month,
    total_active_users,
    total_paying_users,
    total_revenue_usd,
    arpu,
    arppu,
    paying_user_rate,

    -- MoM change
    LAG(arpu)  OVER (ORDER BY period_start)             AS prev_month_arpu,
    CASE WHEN LAG(arpu) OVER (ORDER BY period_start) > 0
         THEN ROUND(
             (arpu - LAG(arpu) OVER (ORDER BY period_start))
             / LAG(arpu) OVER (ORDER BY period_start) * 100, 2)
         ELSE NULL
    END                                                 AS arpu_mom_pct

FROM mart_arpu
WHERE period_type = 'monthly'
ORDER BY period_start
;
*/