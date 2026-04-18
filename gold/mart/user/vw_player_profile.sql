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
    CASE
        WHEN p.total_revenue_usd >= 50   THEN 'whale'
        WHEN p.total_revenue_usd >= 10   THEN 'dolphin'
        WHEN p.total_revenue_usd >  0    THEN 'minnow'
        ELSE                                  'non_payer'
    END                                             AS value_segment,

    -- Engagement segment dựa trên days_active trong 30 ngày gần nhất
    CASE
        WHEN l.days_since_last_active IS NULL   THEN 'new'
        WHEN l.days_since_last_active <= 1      THEN 'daily'
        WHEN l.days_since_last_active <= 7      THEN 'weekly'
        WHEN l.days_since_last_active <= 30     THEN 'casual'
        ELSE                                         'churned'
    END                                             AS engagement_segment,

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
