-- =============================================================
-- gold/analytics/cohort_retention.sql
-- Retention matrix đầy đủ — format chuẩn cho heatmap.
--
-- Khác với mart_retention / vw_retention_detail:
--   Pivot thành dạng matrix: mỗi row = 1 cohort_week,
--   mỗi cột = D1 / D7 / D30 của từng channel.
--   Thêm rank và rolling average 4 tuần để smooth noise.
--
-- Dùng cho: phân tích trend retention sau khi thay đổi
--           game design (tutorial, onboarding, event).
-- =============================================================
 Use game_gold;

WITH

-- Aggregate retention theo cohort_week (smooth hơn cohort_date)
weekly_retention AS (
    SELECT
        DATE_SUB(cohort_date, INTERVAL WEEKDAY(cohort_date) DAY)
                                                AS cohort_week,
        acquisition_channel,
        SUM(cohort_size)                        AS cohort_size,
        SUM(retained_d1)                        AS retained_d1,
        SUM(retained_d7)                        AS retained_d7,
        SUM(retained_d30)                       AS retained_d30,
        -- d7/d30 available nếu tất cả cohort trong tuần đều available
        MIN(d7_available)                       AS d7_available,
        MIN(d30_available)                      AS d30_available
    FROM mart_retention
    GROUP BY cohort_week, acquisition_channel
),

-- Retention rates theo tuần
weekly_rates AS (
    SELECT
        cohort_week,
        acquisition_channel,
        cohort_size,
        retained_d1,
        retained_d7,
        retained_d30,
        d7_available,
        d30_available,
        CASE WHEN cohort_size > 0
             THEN ROUND(retained_d1  / cohort_size, 4) ELSE 0 END AS retention_d1,
        CASE WHEN cohort_size > 0 AND d7_available  = 1
             THEN ROUND(retained_d7  / cohort_size, 4) ELSE NULL  END AS retention_d7,
        CASE WHEN cohort_size > 0 AND d30_available = 1
             THEN ROUND(retained_d30 / cohort_size, 4) ELSE NULL  END AS retention_d30
    FROM weekly_retention
),

-- Rolling 4-week average D1 retention (smooth noise từ cohort nhỏ)
rolling_avg AS (
    SELECT
        w1.cohort_week,
        w1.acquisition_channel,
        ROUND(AVG(w2.retention_d1), 4)          AS rolling_4w_d1_avg
    FROM weekly_rates w1
    JOIN weekly_rates w2
      ON w2.acquisition_channel = w1.acquisition_channel
     AND w2.cohort_week BETWEEN
         DATE_SUB(w1.cohort_week, INTERVAL 21 DAY) AND w1.cohort_week
    GROUP BY w1.cohort_week, w1.acquisition_channel
)

SELECT
    wr.cohort_week,
    wr.acquisition_channel,
    wr.cohort_size,

    -- ── D1 ────────────────────────────────────────────────────
    wr.retained_d1,
    ROUND(wr.retention_d1  * 100, 2)            AS d1_pct,
    ROUND(ra.rolling_4w_d1_avg * 100, 2)        AS d1_rolling_4w_pct,

    -- ── D7 ────────────────────────────────────────────────────
    CASE WHEN wr.d7_available = 1
         THEN wr.retained_d7  ELSE NULL END      AS retained_d7,
    CASE WHEN wr.d7_available = 1
         THEN ROUND(wr.retention_d7  * 100, 2)
         ELSE NULL END                           AS d7_pct,

    -- ── D30 ───────────────────────────────────────────────────
    CASE WHEN wr.d30_available = 1
         THEN wr.retained_d30 ELSE NULL END      AS retained_d30,
    CASE WHEN wr.d30_available = 1
         THEN ROUND(wr.retention_d30 * 100, 2)
         ELSE NULL END                           AS d30_pct,

    -- ── D1→D7 decay (drop-off giữa hai mốc) ──────────────────
    CASE WHEN wr.d7_available = 1
          AND wr.retention_d1 > 0
         THEN ROUND((wr.retention_d1 - wr.retention_d7) / wr.retention_d1 * 100, 2)
         ELSE NULL END                           AS d1_to_d7_decay_pct,

    -- ── Benchmark ─────────────────────────────────────────────
    CASE
        WHEN wr.retention_d1 >= 0.40    THEN 'good'
        WHEN wr.retention_d1 >= 0.25    THEN 'average'
        ELSE                                 'poor'
    END                                         AS d1_grade

FROM weekly_rates wr
LEFT JOIN rolling_avg ra
       ON ra.cohort_week         = wr.cohort_week
      AND ra.acquisition_channel = wr.acquisition_channel
ORDER BY wr.cohort_week DESC, wr.acquisition_channel
;