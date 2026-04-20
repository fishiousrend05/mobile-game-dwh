-- =============================================================
-- gold/mart/progression/vw_funnel_detail.sql
-- Funnel performance view — so sánh conversion rates theo
-- cohort_week và channel cho Tableau funnel visualization.
--
-- Nguồn: mart_funnel
-- Mục đích:
--   - Weekly funnel trend: CR tuần này vs tuần trước
--   - Channel comparison: facebook_ads vs organic vs referral
--   - Identify cohort nào có bước drop-off bất thường
-- =============================================================
USE game_gold;

CREATE OR REPLACE VIEW vw_funnel_detail AS
SELECT
    f.cohort_date,
    f.acquisition_channel,

    -- ── Cohort week / month (để group trong Tableau) ──────────
    DATE_SUB(f.cohort_date,
        INTERVAL WEEKDAY(f.cohort_date) DAY)    AS cohort_week,
    DATE_FORMAT(f.cohort_date, '%Y-%m-01')      AS cohort_month,

    -- ── Funnel volume ─────────────────────────────────────────
    f.step1_registered,
    f.step2_tutorial_done,
    f.step3_first_purchase,
    f.dropoff_at_tutorial,
    f.dropoff_after_tutorial,

    -- ── Conversion rates (%) — format sẵn cho Tableau label ──
    ROUND(f.cr_reg_to_tutorial      * 100, 2)   AS cr_reg_to_tutorial_pct,
    ROUND(f.cr_tutorial_to_purchase * 100, 2)   AS cr_tutorial_to_purchase_pct,
    ROUND(f.cr_overall              * 100, 2)   AS cr_overall_pct,

    -- ── Drop-off rates ────────────────────────────────────────
    CASE WHEN f.step1_registered > 0
         THEN ROUND(f.dropoff_at_tutorial   / f.step1_registered * 100, 2)
         ELSE 0
    END                                         AS dropoff_rate_at_tutorial_pct,

    CASE WHEN f.step2_tutorial_done > 0
         THEN ROUND(f.dropoff_after_tutorial / f.step2_tutorial_done * 100, 2)
         ELSE 0
    END                                         AS dropoff_rate_after_tutorial_pct,

    -- ── Time-to-convert ───────────────────────────────────────
    f.median_days_to_tutorial,
    f.median_days_to_purchase,

    -- ── Funnel health flag (Tableau color coding) ─────────────
    fn_funnel_health(f.cr_overall)              AS funnel_health,

    f.updated_at

FROM mart_funnel f
;