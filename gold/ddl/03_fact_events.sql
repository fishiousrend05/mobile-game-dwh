USE game_gold;

-- =============================================================
-- FACT_EVENTS
-- Bảng fact trung tâm — mọi event đều có 1 row ở đây
-- Source: Silver FACT_EVENTS (load bởi load_gold.py / Spark JDBC)
-- Grain: 1 row per event_uuid
-- Partition: RANGE trên event_date_int (YYYYMMDD) — pruning theo ngày
-- =============================================================

CREATE TABLE IF NOT EXISTS fact_events (
    -- Keys
    event_uuid              VARCHAR(36)     NOT NULL,
    user_id                 VARCHAR(50)     NOT NULL,
    session_id              VARCHAR(50)     NOT NULL,
    device_id               VARCHAR(50)     NOT NULL,

    -- Event identity
    event_name              VARCHAR(50)     NOT NULL
                            COMMENT 'account_created | login | tutorial_completed | level_up | in_app_purchase',
    app_version             VARCHAR(20)     NULL,

    -- Timestamps (UTC)
    server_timestamp_utc    DATETIME(3)     NOT NULL,
    client_timestamp_utc    DATETIME(3)     NULL,
    server_timestamp_local  DATETIME(3)     NULL,
    local_event_date        DATE            NULL,

    -- Partition key — phải nằm trong PRIMARY KEY khi dùng partition
    event_date              DATE            NOT NULL,
    event_date_int          INT             NOT NULL
                            COMMENT 'YYYYMMDD — dùng cho PARTITION BY RANGE',

    -- Snapshot trạng thái người chơi tại thời điểm event
    snapshot_level          INT             NULL,
    snapshot_power_score    INT             NULL,
    snapshot_gold_balance   INT             NULL,
    snapshot_gem_balance    INT             NULL,

    PRIMARY KEY (event_uuid, event_date_int),          -- event_date_int bắt buộc trong PK khi partition
    INDEX idx_user_date     (user_id, event_date),
    INDEX idx_event_name    (event_name, event_date),
    INDEX idx_session       (session_id),
    INDEX idx_device        (device_id)
)
ENGINE = InnoDB
DEFAULT CHARSET = utf8mb4
COMMENT = 'Fact: mọi telemetry event, grain = 1 row/event'

PARTITION BY RANGE (event_date_int) (
    PARTITION p2026_01 VALUES LESS THAN (20260201),
    PARTITION p2026_02 VALUES LESS THAN (20260301),
    PARTITION p2026_03 VALUES LESS THAN (20260401),
    PARTITION p2026_04 VALUES LESS THAN (20260501),
    PARTITION p2026_05 VALUES LESS THAN (20260601),
    PARTITION p2026_06 VALUES LESS THAN (20260701),
    PARTITION p2026_07 VALUES LESS THAN (20260801),
    PARTITION p2026_08 VALUES LESS THAN (20260901),
    PARTITION p2026_09 VALUES LESS THAN (20261001),
    PARTITION p2026_10 VALUES LESS THAN (20261101),
    PARTITION p2026_11 VALUES LESS THAN (20261201),
    PARTITION p2026_12 VALUES LESS THAN (20270101),
    PARTITION p_future  VALUES LESS THAN MAXVALUE   -- catch-all, thêm partition mới hàng tháng
);

-- =============================================================
-- NOTE: Thêm partition hàng tháng bằng cách:
--   ALTER TABLE fact_events REORGANIZE PARTITION p_future INTO (
--       PARTITION p2027_01 VALUES LESS THAN (20270201),
--       PARTITION p_future  VALUES LESS THAN MAXVALUE
--   );
-- =============================================================