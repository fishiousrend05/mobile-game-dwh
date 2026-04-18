-- =============================================================
-- gold/mart/engagement/vw_retention_detail.sql
-- Retention cohort grid — format chuẩn cho heatmap Tableau.
-- Mỗi row là một (cohort_date, metric) → dễ pivot trong Tableau.
--
-- Nguồn: mart_retention (channel = 'all')
-- Mục đích:
--   - Cohort retention heatmap: trục X = D1/D7/D30, trục Y = cohort_date
--   - Highlight cohort nào có D7 retention cao bất thường
--   - So sánh retention trend theo tuần/tháng
-- =============================================================
USE game_gold;

CREATE OR REPLACE VIEW vw_retention_detail AS
SELECT
    r.cohort_date,
    r.cohort_size,

    -- ── D1 ────────────────────────────────────────────────────
    r.retained_d1,
    ROUND(r.retention_d1 * 100, 2)         AS retention_d1_pct,

    -- ── D7 ────────────────────────────────────────────────────
    r.retained_d7,
    ROUND(r.retention_d7 * 100, 2)         AS retention_d7_pct,
    r.d7_available,

    -- ── D30 ───────────────────────────────────────────────────
    r.retained_d30,
    ROUND(r.retention_d30 * 100, 2)        AS retention_d30_pct,
    r.d30_available,

    -- ── Benchmark flags (Tableau dùng để color code) ──────────
    -- Industry benchmark mobile game: D1 ~40%, D7 ~15%, D30 ~5%
    CASE
        WHEN r.retention_d1 >= 0.40 THEN 'above_benchmark'
        WHEN r.retention_d1 >= 0.25 THEN 'at_benchmark'
        ELSE                              'below_benchmark'
    END                                     AS d1_benchmark,

    CASE
        WHEN r.d7_available = 0             THEN 'pending'
        WHEN r.retention_d7 >= 0.15         THEN 'above_benchmark'
        WHEN r.retention_d7 >= 0.08         THEN 'at_benchmark'
        ELSE                                     'below_benchmark'
    END                                     AS d7_benchmark,

    CASE
        WHEN r.d30_available = 0            THEN 'pending'
        WHEN r.retention_d30 >= 0.05        THEN 'above_benchmark'
        WHEN r.retention_d30 >= 0.02        THEN 'at_benchmark'
        ELSE                                     'below_benchmark'
    END                                     AS d30_benchmark,

    -- ── Rolling cohort week (dùng để group cohort theo tuần) ──
    DATE_SUB(r.cohort_date,
        INTERVAL WEEKDAY(r.cohort_date) DAY) AS cohort_week,

    -- ── Rolling cohort month ───────────────────────────────────
    DATE_FORMAT(r.cohort_date, '%Y-%m-01') AS cohort_month,

    r.updated_at

FROM mart_retention r
WHERE r.acquisition_channel = 'all'
;