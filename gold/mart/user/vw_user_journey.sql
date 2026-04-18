-- =============================================================
-- gold/mart/user/vw_user_journey.sql
-- User journey timeline — các mốc quan trọng của từng user
-- được pivot thành format dễ đọc cho Tableau timeline chart.
--
-- Nguồn: mart_user_lifecycle
-- Mục đích:
--   - Vẽ timeline từ register → tutorial → purchase → churn
--   - So sánh journey speed giữa các channel / platform
--   - Tìm pattern: user nào mua nhanh, ai stuck ở tutorial
-- =============================================================
USE game_gold;

CREATE OR REPLACE VIEW vw_user_journey AS
SELECT
    l.user_id,
    p.acquisition_channel,
    p.platform,
    p.country,

    -- ── Milestone dates ───────────────────────────────────────
    l.account_created_date,
    l.first_login_date,
    l.tutorial_completed_date,
    l.first_purchase_date,
    l.last_active_date,

    -- ── Days between milestones ───────────────────────────────
    l.days_to_first_login,
    l.days_to_tutorial_complete,
    l.days_to_first_purchase,

    -- Khoảng cách tutorial → purchase (chỉ với user đã làm cả hai)
    CASE
        WHEN l.tutorial_completed_date IS NOT NULL
         AND l.first_purchase_date     IS NOT NULL
        THEN DATEDIFF(l.first_purchase_date, l.tutorial_completed_date)
        ELSE NULL
    END                                             AS days_tutorial_to_purchase,

    -- ── Current status ────────────────────────────────────────
    l.lifecycle_stage,
    l.days_since_last_active,
    l.max_level_reached,
    l.total_level_ups,
    l.total_days_active,

    -- ── Monetization summary ──────────────────────────────────
    l.lifetime_revenue_usd,
    l.purchase_count,

    -- ── Journey completeness flags ────────────────────────────
    -- Tableau dùng để filter/color các bước trong funnel chart
    CASE WHEN l.first_login_date          IS NOT NULL THEN 1 ELSE 0 END AS did_login,
    CASE WHEN l.tutorial_completed_date   IS NOT NULL THEN 1 ELSE 0 END AS did_tutorial,
    CASE WHEN l.first_purchase_date       IS NOT NULL THEN 1 ELSE 0 END AS did_purchase,

    -- Bước cuối đạt được trong funnel (dùng cho Tableau funnel viz)
    CASE
        WHEN l.first_purchase_date       IS NOT NULL THEN 'purchased'
        WHEN l.tutorial_completed_date   IS NOT NULL THEN 'tutorial_done'
        WHEN l.first_login_date          IS NOT NULL THEN 'logged_in'
        ELSE                                              'registered_only'
    END                                             AS furthest_funnel_step,

    l.updated_date

FROM mart_user_lifecycle l
LEFT JOIN mart_user_profile p ON p.user_id = l.user_id
;
