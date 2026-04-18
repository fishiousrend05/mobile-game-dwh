-- =============================================================
-- gold/analytics/conversion_funnel.sql
-- Funnel so sánh theo tuần — phát hiện thay đổi CR sau update.
--
-- Khác với mart_funnel / vw_funnel_detail:
--   mart_funnel: grain theo cohort_date × channel.
--   Query này: aggregate theo cohort_week để so sánh tuần-over-tuần
--   và highlight step nào bị drop-off nhiều nhất.
--
-- Hai phần:
--   Part 1: Weekly funnel summary — WoW CR comparison
--   Part 2: Step-by-step drop-off waterfall per channel
-- =============================================================
Use game_gold;

-- ── Part 1: Weekly funnel — WoW conversion rate ───────────────────
WITH

weekly_funnel AS (
    SELECT
        DATE_SUB(cohort_date, INTERVAL WEEKDAY(cohort_date) DAY)
                                                AS cohort_week,
        SUM(step1_registered)                   AS registered,
        SUM(step2_tutorial_done)                AS tutorial_done,
        SUM(step3_first_purchase)               AS purchased,
        SUM(dropoff_at_tutorial)                AS dropped_at_tutorial,
        SUM(dropoff_after_tutorial)             AS dropped_after_tutorial,
        -- Weighted avg median days
        ROUND(
            SUM(median_days_to_tutorial * step1_registered)
            / NULLIF(SUM(step1_registered), 0), 1
        )                                       AS avg_days_to_tutorial,
        ROUND(
            SUM(median_days_to_purchase * step1_registered)
            / NULLIF(SUM(step1_registered), 0), 1
        )                                       AS avg_days_to_purchase
    FROM mart_funnel
    WHERE acquisition_channel = 'all'
    GROUP BY cohort_week
),

-- Gắn tuần trước để tính WoW
with_wow AS (
    SELECT
        t.*,
        prev.registered                         AS prev_week_registered,
        prev.tutorial_done                      AS prev_week_tutorial_done,
        prev.purchased                          AS prev_week_purchased,
        -- CR tuần này
        CASE WHEN t.registered > 0
             THEN ROUND(t.tutorial_done / t.registered, 4) ELSE 0 END
                                                AS cr_reg_to_tutorial,
        CASE WHEN t.tutorial_done > 0
             THEN ROUND(t.purchased / t.tutorial_done, 4) ELSE 0 END
                                                AS cr_tutorial_to_purchase,
        CASE WHEN t.registered > 0
             THEN ROUND(t.purchased / t.registered, 4) ELSE 0 END
                                                AS cr_overall,
        -- CR tuần trước (để tính delta)
        CASE WHEN prev.registered > 0
             THEN ROUND(prev.purchased / prev.registered, 4) ELSE 0 END
                                                AS prev_cr_overall
    FROM weekly_funnel t
    LEFT JOIN weekly_funnel prev
           ON prev.cohort_week = DATE_SUB(t.cohort_week, INTERVAL 7 DAY)
)

SELECT
    cohort_week,
    registered,
    tutorial_done,
    purchased,
    dropped_at_tutorial,
    dropped_after_tutorial,

    ROUND(cr_reg_to_tutorial      * 100, 2)     AS cr_reg_to_tutorial_pct,
    ROUND(cr_tutorial_to_purchase * 100, 2)     AS cr_tutorial_to_purchase_pct,
    ROUND(cr_overall              * 100, 2)     AS cr_overall_pct,

    -- WoW delta CR
    prev_cr_overall,
    ROUND((cr_overall - prev_cr_overall) * 100, 2)
                                                AS cr_overall_wow_delta_pp,  -- percentage points

    avg_days_to_tutorial,
    avg_days_to_purchase,

    -- Điểm drop-off chính (step nào mất nhiều user nhất tương đối)
    CASE
        WHEN registered > 0
         AND dropped_at_tutorial > dropped_after_tutorial
        THEN 'tutorial_step'
        ELSE 'purchase_step'
    END                                         AS main_dropoff_step

FROM with_wow
ORDER BY cohort_week DESC
;


-- ── Part 2: Drop-off waterfall per channel (tháng gần nhất) ───────
/*
SELECT
    acquisition_channel,
    SUM(step1_registered)                       AS step1_registered,
    SUM(step2_tutorial_done)                    AS step2_tutorial,
    SUM(step3_first_purchase)                   AS step3_purchase,

    ROUND(SUM(step2_tutorial_done)  / NULLIF(SUM(step1_registered),  0) * 100, 2) AS cr_to_tutorial_pct,
    ROUND(SUM(step3_first_purchase) / NULLIF(SUM(step2_tutorial_done),0) * 100, 2) AS cr_to_purchase_pct,
    ROUND(SUM(step3_first_purchase) / NULLIF(SUM(step1_registered),  0) * 100, 2) AS cr_overall_pct,

    -- Drop-off absolute
    SUM(step1_registered)  - SUM(step2_tutorial_done)   AS lost_at_tutorial,
    SUM(step2_tutorial_done) - SUM(step3_first_purchase) AS lost_after_tutorial,

    RANK() OVER (ORDER BY
        SUM(step3_first_purchase) / NULLIF(SUM(step1_registered), 0) DESC
    )                                           AS channel_rank

FROM mart_funnel
WHERE cohort_date >= DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL 1 MONTH), '%Y-%m-01')
  AND acquisition_channel != 'all'
GROUP BY acquisition_channel
ORDER BY channel_rank
;
*/