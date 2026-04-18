-- =============================================================
-- gold/mart/user/mart_user_profile.sql
-- Player profile snapshot — dùng cho segmentation và Tableau drill-down.
--
-- Câu hỏi business trả lời:
--   "Ai là người chơi của tôi?" — kênh nào, platform nào,
--   level nào, có nạp tiền chưa?
--
-- Grain: 1 row per user (snapshot hiện tại, overwrite mỗi ngày)
-- Source: dim_users, dim_device, fact_events, fact_purchases
-- Load: REPLACE INTO (overwrite toàn bộ row theo user_id)
-- Schedule: chạy sau load_gold.py hoàn thành
-- =============================================================
USE game_gold;

CREATE TABLE IF NOT EXISTS mart_user_profile (

    user_id                 VARCHAR(50)         NOT NULL,

    -- ── Acquisition ───────────────────────────────────────────
    acquisition_channel     VARCHAR(100)        DEFAULT NULL,
    campaign_id             VARCHAR(100)        DEFAULT NULL,
    account_created_date    DATE                NOT NULL,
    days_since_install      INT                 NOT NULL,

    -- ── Device (lần đầu ghi nhận) ─────────────────────────────
    first_device_model      VARCHAR(100)        DEFAULT NULL,
    platform                VARCHAR(20)         DEFAULT NULL    COMMENT 'iOS | Android',
    country                 VARCHAR(10)         DEFAULT NULL,

    -- ── Progression snapshot (latest) ─────────────────────────
    current_level           SMALLINT UNSIGNED   DEFAULT NULL    COMMENT 'level cao nhất ghi nhận được',
    current_power_score     INT UNSIGNED        DEFAULT NULL,
    current_gold_balance    INT UNSIGNED        DEFAULT NULL,
    current_gem_balance     INT UNSIGNED        DEFAULT NULL,

    -- ── Monetization flag ─────────────────────────────────────
    is_paying_user          TINYINT(1)          NOT NULL    DEFAULT 0   COMMENT '1 nếu đã có ít nhất 1 purchase',
    total_revenue_usd       DECIMAL(12, 4)      NOT NULL    DEFAULT 0,
    first_purchase_date     DATE                DEFAULT NULL,
    purchase_count          SMALLINT UNSIGNED   NOT NULL    DEFAULT 0,

    -- ── Activity ──────────────────────────────────────────────
    first_active_date       DATE                NOT NULL    COMMENT 'account_created_date',
    last_active_date        DATE                DEFAULT NULL COMMENT 'ngày có event mới nhất',
    total_sessions          INT UNSIGNED        NOT NULL    DEFAULT 0,
    total_events            INT UNSIGNED        NOT NULL    DEFAULT 0,

    -- ── Audit ─────────────────────────────────────────────────
    updated_date            DATE                NOT NULL    COMMENT 'ngày batch chạy gần nhất',

    PRIMARY KEY (user_id),
    INDEX idx_acquisition_channel   (acquisition_channel),
    INDEX idx_country               (country),
    INDEX idx_platform              (platform),
    INDEX idx_is_paying_user        (is_paying_user),
    INDEX idx_current_level         (current_level),
    INDEX idx_account_created_date  (account_created_date),
    INDEX idx_last_active_date      (last_active_date)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COMMENT = 'Mart: player profile snapshot — 1 row/user, overwrite daily';


-- =============================================================
-- LOAD LOGIC
-- Chạy daily sau khi load_gold.py hoàn thành.
-- REPLACE INTO = DELETE + INSERT nếu PK đã tồn tại
--             → đảm bảo snapshot luôn là giá trị mới nhất.
-- =============================================================

REPLACE INTO mart_user_profile (
    user_id,
    acquisition_channel,
    campaign_id,
    account_created_date,
    days_since_install,
    first_device_model,
    platform,
    country,
    current_level,
    current_power_score,
    current_gold_balance,
    current_gem_balance,
    is_paying_user,
    total_revenue_usd,
    first_purchase_date,
    purchase_count,
    first_active_date,
    last_active_date,
    total_sessions,
    total_events,
    updated_date
)
WITH

-- Snapshot trạng thái mới nhất của user: lấy row event có server_timestamp_utc lớn nhất
latest_state AS (
    SELECT
        fe.user_id,
        fe.snapshot_level,
        fe.snapshot_power_score,
        fe.snapshot_gold_balance,
        fe.snapshot_gem_balance,
        fe.local_event_date             AS last_active_date,
        ROW_NUMBER() OVER (
            PARTITION BY fe.user_id
            ORDER BY fe.server_timestamp_utc DESC
        ) AS rn
    FROM fact_events fe
),

-- Aggregation activity: số session, số event
activity AS (
    SELECT
        user_id,
        COUNT(DISTINCT session_id)  AS total_sessions,
        COUNT(*)                    AS total_events
    FROM fact_events
    GROUP BY user_id
),

-- Monetization summary
monetization AS (
    SELECT
        user_id,
        SUM(revenue_usd)            AS total_revenue_usd,
        MIN(purchase_date)          AS first_purchase_date,
        COUNT(*)                    AS purchase_count
    FROM fact_purchases
    GROUP BY user_id
)

SELECT
    du.user_id,

    -- Acquisition
    du.acquisition_channel,
    du.campaign_id,
    du.account_created_date,
    du.days_since_install,

    -- Device (từ dim_users first_device_model + dim_device platform/country)
    du.device_model,
    dd.platform,
    dd.country,

    -- Progression snapshot
    ls.snapshot_level           AS current_level,
    ls.snapshot_power_score     AS current_power_score,
    ls.snapshot_gold_balance    AS current_gold_balance,
    ls.snapshot_gem_balance     AS current_gem_balance,

    -- Monetization
    CASE WHEN m.user_id IS NOT NULL THEN 1 ELSE 0 END   AS is_paying_user,
    COALESCE(m.total_revenue_usd, 0)                    AS total_revenue_usd,
    m.first_purchase_date,
    COALESCE(m.purchase_count, 0)                       AS purchase_count,

    -- Activity
    du.account_created_date     AS first_active_date,
    ls.last_active_date,
    COALESCE(a.total_sessions, 0)                       AS total_sessions,
    COALESCE(a.total_events, 0)                         AS total_events,

    CURDATE()                                           AS updated_date

FROM dim_users du

-- Device info: join qua fact_events lấy device đầu tiên ghi nhận
LEFT JOIN fact_events fe_first
       ON fe_first.user_id = du.user_id
      AND fe_first.event_name = 'account_created'
LEFT JOIN dim_device dd
       ON dd.device_id = fe_first.device_id

-- Latest player state
LEFT JOIN latest_state ls
       ON ls.user_id = du.user_id
      AND ls.rn = 1

-- Activity
LEFT JOIN activity a
       ON a.user_id = du.user_id

-- Monetization
LEFT JOIN monetization m
       ON m.user_id = du.user_id
;