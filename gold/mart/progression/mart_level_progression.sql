-- =============================================================
-- gold/mart/progression/mart_level_progression.sql
-- Tốc độ lên level và kinh tế tài nguyên theo từng level.
--
-- Câu hỏi business trả lời:
--   "Level nào khiến player stuck lâu nhất?"
--   "Trung bình cần bao nhiêu gold để lên từ level 14 → 15?"
--   "Level nào có drop-off cao nhất (nhiều user đạt nhưng ít user vượt qua)?"
--   "Tốc độ progression của iOS vs Android khác nhau không?"
--
-- Grain: 1 row per (new_level, platform)
--   Aggregate trên toàn bộ lịch sử — overwrite mỗi ngày khi có data mới.
--
-- Source: fact_progression, fact_events, dim_device
-- Load: REPLACE INTO
-- Schedule: sau load_gold.py
-- =============================================================
 use game_gold;

CREATE TABLE IF NOT EXISTS mart_level_progression (

    new_level               SMALLINT UNSIGNED   NOT NULL    COMMENT 'level đạt được',
    platform                VARCHAR(10)         NOT NULL    COMMENT 'iOS | Android | all',

    -- ── Volume ────────────────────────────────────────────────
    total_level_up_events   INT UNSIGNED        NOT NULL    DEFAULT 0   COMMENT 'số lần level_up đạt new_level này',
    unique_users_reached    INT UNSIGNED        NOT NULL    DEFAULT 0   COMMENT 'số user distinct đã đạt level này',

    -- ── Time to level up (giây) ───────────────────────────────
    avg_time_to_level_sec   INT UNSIGNED        NOT NULL    DEFAULT 0   COMMENT 'trung bình thời gian từ level trước',
    median_time_to_level_sec INT UNSIGNED       NOT NULL    DEFAULT 0,
    min_time_to_level_sec   INT UNSIGNED        NOT NULL    DEFAULT 0,
    max_time_to_level_sec   INT UNSIGNED        NOT NULL    DEFAULT 0,

    -- ── Resource cost ─────────────────────────────────────────
    avg_gold_spent          INT UNSIGNED        NOT NULL    DEFAULT 0,
    avg_exp_potions_spent   DECIMAL(6, 2)       NOT NULL    DEFAULT 0,
    total_gold_consumed     BIGINT UNSIGNED     NOT NULL    DEFAULT 0   COMMENT 'tổng gold tiêu tốn ở level này',

    -- ── Location ──────────────────────────────────────────────
    top_location_id         VARCHAR(100)        DEFAULT NULL COMMENT 'location phổ biến nhất khi level_up',

    -- ── Drop-off signal ───────────────────────────────────────
    -- So sánh với level trước — tính ở analytics layer,
    -- lưu ở đây để Tableau dùng trực tiếp không cần tự JOIN
    pct_of_prev_level_users DECIMAL(6, 4)       DEFAULT NULL
                                                COMMENT 'unique_users_reached / unique_users_reached(level-1). NULL cho level 1',

    -- ── Audit ─────────────────────────────────────────────────
    updated_at              DATETIME            NOT NULL    DEFAULT CURRENT_TIMESTAMP
                                                            ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (new_level, platform),
    INDEX idx_new_level     (new_level),
    INDEX idx_platform      (platform)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COMMENT = 'Mart: level-up velocity và resource economy theo level × platform';

-- =============================================================
-- LOAD LOGIC (Fixed for MySQL using PERCENT_RANK)
-- =============================================================

-- ── Per platform ──────────────────────────────────────────────
REPLACE INTO mart_level_progression (
    new_level, platform,
    total_level_up_events, unique_users_reached,
    avg_time_to_level_sec, median_time_to_level_sec,
    min_time_to_level_sec, max_time_to_level_sec,
    avg_gold_spent, avg_exp_potions_spent, total_gold_consumed,
    top_location_id,
    pct_of_prev_level_users
)
WITH
progression_with_platform AS (
    SELECT
        fp.event_uuid,
        fp.user_id,
        fp.new_level,
        fp.time_to_level_up_sec,
        fp.gold_spent,
        fp.exp_potions_spent,
        fp.location_id,
        COALESCE(dd.platform, 'unknown')    AS platform
    FROM fact_progression fp
    LEFT JOIN fact_events fe ON fe.event_uuid = fp.event_uuid
    LEFT JOIN dim_device dd ON dd.device_id  = fe.device_id
),
-- Calculate Percent Rank for Median
time_percentiles AS (
    SELECT
        new_level,
        platform,
        time_to_level_up_sec,
        PERCENT_RANK() OVER (PARTITION BY new_level, platform ORDER BY time_to_level_up_sec) AS pct
    FROM progression_with_platform
),
top_location AS (
    SELECT
        new_level,
        platform,
        location_id,
        ROW_NUMBER() OVER (PARTITION BY new_level, platform ORDER BY COUNT(*) DESC) AS rn
    FROM progression_with_platform
    WHERE location_id IS NOT NULL
    GROUP BY new_level, platform, location_id
),
level_agg AS (
    SELECT
        pwp.new_level,
        pwp.platform,
        COUNT(*)                            AS total_level_up_events,
        COUNT(DISTINCT pwp.user_id)         AS unique_users_reached,
        ROUND(AVG(pwp.time_to_level_up_sec)) AS avg_time_to_level_sec,
        -- Use the workaround for Median
        (SELECT MIN(time_to_level_up_sec) FROM time_percentiles tp
         WHERE tp.new_level = pwp.new_level AND tp.platform = pwp.platform AND tp.pct >= 0.5) AS median_time_to_level_sec,
        MIN(pwp.time_to_level_up_sec)       AS min_time_to_level_sec,
        MAX(pwp.time_to_level_up_sec)       AS max_time_to_level_sec,
        ROUND(AVG(pwp.gold_spent))          AS avg_gold_spent,
        ROUND(AVG(pwp.exp_potions_spent), 2) AS avg_exp_potions_spent,
        SUM(pwp.gold_spent)                 AS total_gold_consumed
    FROM progression_with_platform pwp
    GROUP BY pwp.new_level, pwp.platform
)

SELECT
    la.new_level,
    la.platform,
    la.total_level_up_events,
    la.unique_users_reached,
    la.avg_time_to_level_sec,
    COALESCE(la.median_time_to_level_sec, 0),
    la.min_time_to_level_sec,
    la.max_time_to_level_sec,
    la.avg_gold_spent,
    la.avg_exp_potions_spent,
    la.total_gold_consumed,
    tl.location_id                          AS top_location_id,
    CASE WHEN prev_la.unique_users_reached > 0
         THEN ROUND(la.unique_users_reached / prev_la.unique_users_reached, 4)
         ELSE NULL END                      AS pct_of_prev_level_users
FROM level_agg la
LEFT JOIN top_location tl ON tl.new_level = la.new_level AND tl.platform = la.platform AND tl.rn = 1
LEFT JOIN level_agg prev_la ON prev_la.new_level = la.new_level - 1 AND prev_la.platform  = la.platform;


-- ── platform = 'all' ──────────────────────────────────────────
REPLACE INTO mart_level_progression (
    new_level, platform,
    total_level_up_events, unique_users_reached,
    avg_time_to_level_sec, median_time_to_level_sec,
    min_time_to_level_sec, max_time_to_level_sec,
    avg_gold_spent, avg_exp_potions_spent, total_gold_consumed,
    top_location_id,
    pct_of_prev_level_users
)
WITH
time_percentiles_all AS (
    SELECT
        new_level,
        time_to_level_up_sec,
        PERCENT_RANK() OVER (PARTITION BY new_level ORDER BY time_to_level_up_sec) AS pct
    FROM fact_progression
),
top_location_all AS (
    SELECT
        new_level,
        location_id,
        ROW_NUMBER() OVER (PARTITION BY new_level ORDER BY COUNT(*) DESC) AS rn
    FROM fact_progression
    WHERE location_id IS NOT NULL
    GROUP BY new_level, location_id
),
level_agg_all AS (
    SELECT
        fp.new_level,
        COUNT(*)                            AS total_level_up_events,
        COUNT(DISTINCT fp.user_id)          AS unique_users_reached,
        ROUND(AVG(fp.time_to_level_up_sec)) AS avg_time_to_level_sec,
         -- Use the workaround for Median
        (SELECT MIN(time_to_level_up_sec) FROM time_percentiles_all tp
         WHERE tp.new_level = fp.new_level AND tp.pct >= 0.5) AS median_time_to_level_sec,
        MIN(fp.time_to_level_up_sec)        AS min_time_to_level_sec,
        MAX(fp.time_to_level_up_sec)        AS max_time_to_level_sec,
        ROUND(AVG(fp.gold_spent))           AS avg_gold_spent,
        ROUND(AVG(fp.exp_potions_spent), 2) AS avg_exp_potions_spent,
        SUM(fp.gold_spent)                  AS total_gold_consumed
    FROM fact_progression fp
    GROUP BY fp.new_level
)

SELECT
    la.new_level,
    'all'                                   AS platform,
    la.total_level_up_events,
    la.unique_users_reached,
    la.avg_time_to_level_sec,
    COALESCE(la.median_time_to_level_sec, 0),
    la.min_time_to_level_sec,
    la.max_time_to_level_sec,
    la.avg_gold_spent,
    la.avg_exp_potions_spent,
    la.total_gold_consumed,
    tl.location_id                          AS top_location_id,
    CASE WHEN prev_la.unique_users_reached > 0
         THEN ROUND(la.unique_users_reached / prev_la.unique_users_reached, 4)
         ELSE NULL END                      AS pct_of_prev_level_users
FROM level_agg_all la
LEFT JOIN top_location_all tl ON tl.new_level = la.new_level AND tl.rn = 1
LEFT JOIN level_agg_all prev_la ON prev_la.new_level = la.new_level - 1;