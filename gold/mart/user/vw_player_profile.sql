-- =============================================================
-- gold/mart/user/vw_player_profile.sql
-- Player profile đã được enrich và classify — dùng trực tiếp
-- trong Tableau mà không cần transform thêm.
--
-- Nguồn: mart_user_profile + mart_user_lifecycle (JOIN theo user_id)
-- Mục đích:
--   - Segmentation: high-value / mid / casual / new
--   - Filter nhanh theo platform, country, channel
--   - Drill-down từ aggregate chart xuống user cụ thể
-- =============================================================
USE game_gold;

CREATE OR REPLACE VIEW vw_player_profile AS
SELECT
    -- ── Identity ──────────────────────────────────────────────
    p.user_id,
    p.acquisition_channel,
    p.campaign_id,
    p.platform,
    p.country,
    p.first_device_model,

    -- ── Dates ─────────────────────────────────────────────────
    p.account_created_date,
    p.last_active_date,
    p.first_purchase_date,

    -- ── Progression ───────────────────────────────────────────
    p.current_level,
    p.current_power_score,
    p.current_gold_balance,
    p.current_gem_balance,

    -- ── Engagement ────────────────────────────────────────────
    p.total_sessions,
    p.total_events,
    l.total_days_active,
    l.days_since_last_active,
    l.lifecycle_stage,

    -- ── Monetization ──────────────────────────────────────────
    p.is_paying_user,
    p.purchase_count,
    p.total_revenue_usd,
    l.lifetime_revenue_usd,         -- từ lifecycle — consistent hơn

    -- ── Lifecycle milestones ──────────────────────────────────
    l.days_to_first_login,
    l.days_to_tutorial_complete,
    l.days_to_first_purchase,
    l.tutorial_completed_date,

    -- ── Computed segments (Tableau dùng trực tiếp) ────────────
    -- Value segment dựa trên revenue
    fn_value_segment(p.total_revenue_usd)           AS value_segment,

    fn_engagement_segment(l.days_since_last_active) AS engagement_segment,

    -- Tutorial funnel position
    CASE
        WHEN l.tutorial_completed_date IS NULL  THEN 'pre_tutorial'
        WHEN p.first_purchase_date     IS NULL  THEN 'post_tutorial'
        ELSE                                         'converted'
    END                                             AS funnel_stage,

    p.updated_date

FROM mart_user_profile p
LEFT JOIN mart_user_lifecycle l ON l.user_id = p.user_id
;
