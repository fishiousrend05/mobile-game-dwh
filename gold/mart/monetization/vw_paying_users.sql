-- =============================================================
-- gold/mart/monetization/vw_paying_users.sql
-- Paying user segments và LTV context — dùng để phân tích
-- chân dung người nạp tiền và identify high-value cohorts.
--
-- Nguồn: mart_user_profile + mart_ltv
-- Mục đích:
--   - Whale / dolphin / minnow breakdown theo channel
--   - LTV tại D7/D30 cho từng cohort × channel
--   - Identify channel nào mang lại paying user chất lượng cao
-- =============================================================
USE game_gold;

CREATE OR REPLACE VIEW vw_paying_users AS
SELECT
    -- ── User info ─────────────────────────────────────────────
    p.user_id,
    p.acquisition_channel,
    p.platform,
    p.country,
    p.account_created_date,
    DATE_FORMAT(p.account_created_date, '%Y-%m') AS cohort_month,

    -- ── Purchase history ──────────────────────────────────────
    p.first_purchase_date,
    p.purchase_count,
    p.total_revenue_usd,
    p.days_since_install,

    -- Ngày từ register đến first purchase
    DATEDIFF(p.first_purchase_date, p.account_created_date)
                                            AS days_to_convert,

    -- ── Value segment ─────────────────────────────────────────
    fn_value_segment(p.total_revenue_usd)   AS value_segment,

    -- ── Progression context (tại thời điểm hiện tại) ─────────
    p.current_level,
    p.current_gem_balance,

    -- ── Cohort LTV benchmarks ─────────────────────────────────
    -- So sánh user này với LTV trung bình của cohort tháng + channel
    lt.ltv_d7,
    lt.ltv_d30,
    lt.ltv_total                            AS avg_ltv_cohort,

    -- User này above/below cohort LTV average
    CASE
        WHEN lt.ltv_total IS NULL           THEN NULL
        WHEN p.total_revenue_usd > lt.ltv_total * 3 THEN 'top_spender'
        WHEN p.total_revenue_usd > lt.ltv_total     THEN 'above_avg'
        ELSE                                              'below_avg'
    END                                     AS ltv_vs_cohort,

    -- ── Cohort conversion rate context ────────────────────────
    lt.conversion_rate                      AS cohort_conversion_rate,

    p.updated_date

FROM mart_user_profile p
LEFT JOIN mart_ltv lt
       ON lt.cohort_month        = DATE_FORMAT(p.account_created_date, '%Y-%m')
      AND lt.acquisition_channel = COALESCE(p.acquisition_channel, 'unknown')
WHERE p.is_paying_user = 1
;