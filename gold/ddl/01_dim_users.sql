-- Tạo database cho Data Warehouse nếu chưa có
CREATE DATABASE IF NOT EXISTS game_gold;
USE game_gold;

-- =============================================================
-- DIM_USERS
-- Slowly Changing Dimension (Type 1 — overwrite on conflict)
-- Source: Silver FACT_EVENTS + FACT_EVENT_PARAMS (account_created)
-- Grain: 1 row per user_id
-- =============================================================

CREATE TABLE IF NOT EXISTS dim_users (
    user_id             VARCHAR(50)     NOT NULL,

    -- Acquisition info — chỉ có từ event account_created
    acquisition_channel VARCHAR(100)    NULL,
    campaign_id         VARCHAR(100)    NULL,
    device_model        VARCHAR(100)    NULL,

    -- Timestamps
    account_created_at  BIGINT          NOT NULL COMMENT 'epoch ms từ Bronze',
    account_created_date DATE           NOT NULL COMMENT 'derived, dùng cho partition join',
    days_since_install  INT             NULL,

    -- Metadata
    first_seen_date     DATE            NOT NULL COMMENT 'event_date đầu tiên ghi nhận user',
    updated_at          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                                        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (user_id),
    INDEX idx_account_created_date (account_created_date),
    INDEX idx_acquisition_channel  (acquisition_channel),
    INDEX idx_campaign_id          (campaign_id)
)
ENGINE = InnoDB
DEFAULT CHARSET = utf8mb4
COMMENT = 'Dimension: thông tin tĩnh của user, grain = 1 row/user';