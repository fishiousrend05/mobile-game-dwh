
USE game_gold;

-- =============================================================
-- DIM_DEVICE
-- Type 1 SCD — overwrite nếu thông tin thiết bị thay đổi
-- Source: Silver FACT_EVENTS (device fields)
-- Grain: 1 row per device_id
-- =============================================================

CREATE TABLE IF NOT EXISTS dim_device (
    device_id           VARCHAR(50)     NOT NULL,

    platform            VARCHAR(20)     NOT NULL COMMENT 'iOS | Android',
    os_version          VARCHAR(20)     NULL,
    network_type        VARCHAR(20)     NULL COMMENT 'WIFI | 4G | 5G | ...',
    country             VARCHAR(10)     NULL COMMENT 'ISO 3166-1 alpha-2',

    -- Metadata
    first_seen_date     DATE            NOT NULL,
    updated_at          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                                        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (device_id),
    INDEX idx_platform  (platform),
    INDEX idx_country   (country)
)
ENGINE = InnoDB
DEFAULT CHARSET = utf8mb4
COMMENT = 'Dimension: thông tin thiết bị, grain = 1 row/device';