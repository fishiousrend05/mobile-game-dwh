USE game_gold;
-- =============================================================
-- 05_fact_progression.sql
-- FACT_PROGRESSION: Mỗi row = 1 level_up event.
-- Source: Silver FACT_EVENT_PARAMS (event_name = 'level_up')
--         + FACT_EVENT_ITEMS  (resources_spent của event đó)
-- Load:   INSERT IGNORE — idempotent theo event_uuid
--
-- Tại sao tách khỏi fact_events?
--   level_up có payload đặc thù: old/new_level, time_to_level_up,
--   location_id, resources_spent — không fit vào fact_events chung.
--   Đây là input chính cho mart_level_progression và mart_funnel.
--
-- FK notes:
--   → dim_users(user_id)      : FK chuẩn
--   → fact_events(event_uuid) : no FK — fact_events is partitioned
--                               → enforce ở load_gold.py
-- =============================================================

CREATE TABLE IF NOT EXISTS fact_progression (

    -- ── Primary key ───────────────────────────────────────────
    event_uuid              VARCHAR(36)         NOT NULL
                                                COMMENT 'Natural PK — cùng event_uuid với fact_events',

    -- ── References ────────────────────────────────────────────
    user_id                 VARCHAR(50)         NOT NULL
                                                COMMENT 'Denormalized — tránh join fact_events khi query progression',

    -- ── Level transition ──────────────────────────────────────
    old_level               SMALLINT UNSIGNED   NOT NULL,
    new_level               SMALLINT UNSIGNED   NOT NULL,
    time_to_level_up_sec    INT UNSIGNED        NOT NULL
                                                COMMENT 'Giây từ lần level_up trước đến lần này',
    location_id             VARCHAR(100)        DEFAULT NULL
                                                COMMENT 'dungeon_of_fire | world_map | ... — nơi xảy ra level_up',

    -- ── Resources spent (pre-aggregated từ FACT_EVENT_ITEMS) ──
    -- Tổng hợp sẵn để mart_level_progression không cần join FACT_EVENT_ITEMS
    gold_spent              INT UNSIGNED        NOT NULL    DEFAULT 0,
    exp_potions_spent       SMALLINT UNSIGNED   NOT NULL    DEFAULT 0,

    -- ── Timestamps ────────────────────────────────────────────
    leveled_up_at           DATETIME(3)         NOT NULL
                                                COMMENT 'server_timestamp_utc của event tương ứng',
    level_up_date           DATE                NOT NULL
                                                COMMENT 'DATE(leveled_up_at) — GROUP BY daily',

    -- ── Audit ─────────────────────────────────────────────────
    event_date              DATE                NOT NULL
                                                COMMENT 'Silver partition date của batch load',

    -- ── Constraints & Indexes ─────────────────────────────────
    PRIMARY KEY (event_uuid),
    INDEX idx_user_date         (user_id, level_up_date),
    INDEX idx_new_level_date    (new_level, level_up_date),
    INDEX idx_location_date     (location_id, level_up_date),
    INDEX idx_level_up_date     (level_up_date),

    CONSTRAINT fk_fpr_user FOREIGN KEY (user_id) REFERENCES dim_users (user_id)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COMMENT = 'Fact: mỗi row = 1 level_up event. Resources spent pre-agg từ FACT_EVENT_ITEMS.';