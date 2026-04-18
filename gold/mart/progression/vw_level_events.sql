-- =============================================================
-- gold/mart/progression/vw_level_events.sql
-- Level progression drill-down — phân tích bottleneck và
-- economy balance theo từng level.
--
-- Nguồn: mart_level_progression
-- Mục đích:
--   - Bar chart: avg time-to-level theo từng level (tìm spike)
--   - Scatter: gold cost vs time cost (economy balance check)
--   - Drop-off waterfall: user count giảm dần theo level
--   - Platform comparison: iOS vs Android progression speed
-- =============================================================
USE game_gold;

CREATE OR REPLACE VIEW vw_level_events AS
SELECT
    lp.new_level,
    lp.platform,

    -- ── Volume ────────────────────────────────────────────────
    lp.total_level_up_events,
    lp.unique_users_reached,

    -- ── Time metrics ──────────────────────────────────────────
    lp.avg_time_to_level_sec,
    lp.median_time_to_level_sec,
    lp.min_time_to_level_sec,
    lp.max_time_to_level_sec,

    -- Convert sang phút/giờ cho Tableau label dễ đọc
    ROUND(lp.avg_time_to_level_sec    / 60, 1) AS avg_time_minutes,
    ROUND(lp.median_time_to_level_sec / 60, 1) AS median_time_minutes,
    ROUND(lp.avg_time_to_level_sec  / 3600, 2) AS avg_time_hours,

    -- ── Resource cost ─────────────────────────────────────────
    lp.avg_gold_spent,
    lp.avg_exp_potions_spent,
    lp.total_gold_consumed,
    lp.top_location_id,

    -- ── Drop-off ──────────────────────────────────────────────
    lp.pct_of_prev_level_users,
    ROUND((1 - COALESCE(lp.pct_of_prev_level_users, 1)) * 100, 2)
                                                AS dropoff_pct,

    -- Bottleneck flag — level nào mất nhiều thời gian hơn
    -- trung bình toàn bộ levels đáng kể (> 1.5x median toàn game)
    CASE
        WHEN lp.platform = 'all'
         AND lp.avg_time_to_level_sec > (
                SELECT AVG(avg_time_to_level_sec) * 1.5
                FROM mart_level_progression
                WHERE platform = 'all'
             )
        THEN 1 ELSE 0
    END                                         AS is_bottleneck,

    -- Economy stress flag — gold cost bất thường cao
    CASE
        WHEN lp.platform = 'all'
         AND lp.avg_gold_spent > (
                SELECT AVG(avg_gold_spent) * 2
                FROM mart_level_progression
                WHERE platform = 'all'
                  AND avg_gold_spent > 0
             )
        THEN 1 ELSE 0
    END                                         AS is_high_cost,

    -- Level band (dùng để group trong Tableau)
    CASE
        WHEN lp.new_level <= 10  THEN 'early_game'
        WHEN lp.new_level <= 30  THEN 'mid_game'
        ELSE                          'late_game'
    END                                         AS level_band,

    lp.updated_at

FROM mart_level_progression lp
;