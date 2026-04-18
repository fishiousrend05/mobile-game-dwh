-- =============================================================
-- gold/mart/user/mart_user_lifecycle.sql
-- User lifecycle timeline — dùng cho retention analysis và LTV.
--
-- Câu hỏi business trả lời:
--   "User đang ở giai đoạn nào?" — new / active / at_risk / churned
--   "Mất bao nhiêu ngày từ đăng ký đến nạp tiền đầu tiên?"
--   "User nào có nguy cơ churn?"
--
-- Grain: 1 row per user (snapshot hiện tại, overwrite mỗi ngày)
-- Source: dim_users, fact_events, fact_purchases, fact_progression
-- Load: REPLACE INTO
-- Schedule: chạy sau mart_user_profile (dùng kết quả của nó không,
--           nhưng chạy sau để đảm bảo fact tables đã được load đầy đủ)
--
-- Định nghĩa lifecycle_stage:
--   new          : last_active_date = account_created_date (chưa quay lại)
--   active       : last_active_date trong 7 ngày gần nhất
--   at_risk      : last_active_date trong 8–30 ngày gần nhất
--   churned      : last_active_date > 30 ngày trước
-- =============================================================
USE game_gold;

CREATE TABLE IF NOT EXISTS mart_user_lifecycle (

    user_id                     VARCHAR(50)         NOT NULL,

    -- ── Milestones ────────────────────────────────────────────
    account_created_date        DATE                NOT NULL,
    first_active_date           DATE                NOT NULL    COMMENT 'ngày đầu tiên có event',
    last_active_date            DATE                DEFAULT NULL,
    first_login_date            DATE                DEFAULT NULL,
    tutorial_completed_date     DATE                DEFAULT NULL,
    first_purchase_date         DATE                DEFAULT NULL,

    -- ── Days-to milestones (từ account_created_date) ──────────
    -- NULL = milestone chưa đạt được
    days_to_first_login         SMALLINT            DEFAULT NULL,
    days_to_tutorial_complete   SMALLINT            DEFAULT NULL,
    days_to_first_purchase      SMALLINT            DEFAULT NULL,

    -- ── Progression peak ──────────────────────────────────────
    max_level_reached           SMALLINT UNSIGNED   DEFAULT NULL,
    total_level_ups             SMALLINT UNSIGNED   NOT NULL    DEFAULT 0,

    -- ── Monetization ──────────────────────────────────────────
    lifetime_revenue_usd        DECIMAL(12, 4)      NOT NULL    DEFAULT 0,
    purchase_count              SMALLINT UNSIGNED   NOT NULL    DEFAULT 0,
    days_since_last_purchase    SMALLINT            DEFAULT NULL COMMENT 'NULL nếu chưa mua',

    -- ── Engagement ────────────────────────────────────────────
    total_days_active           SMALLINT UNSIGNED   NOT NULL    DEFAULT 0   COMMENT 'số ngày có ít nhất 1 event',
    total_sessions              INT UNSIGNED        NOT NULL    DEFAULT 0,
    days_since_last_active      SMALLINT            DEFAULT NULL,

    -- ── Lifecycle classification ──────────────────────────────
    lifecycle_stage             VARCHAR(20)         NOT NULL
                                                    COMMENT 'new | active | at_risk | churned',

    -- ── Audit ─────────────────────────────────────────────────
    updated_date                DATE                NOT NULL,

    PRIMARY KEY (user_id),
    INDEX idx_lifecycle_stage           (lifecycle_stage),
    INDEX idx_account_created_date      (account_created_date),
    INDEX idx_last_active_date          (last_active_date),
    INDEX idx_first_purchase_date       (first_purchase_date),
    INDEX idx_days_to_first_purchase    (days_to_first_purchase),
    INDEX idx_max_level_reached         (max_level_reached)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COMMENT = 'Mart: user lifecycle timeline — 1 row/user, overwrite daily';


-- =============================================================
-- LOAD LOGIC
-- =============================================================

REPLACE INTO mart_user_lifecycle (
    user_id,
    account_created_date,
    first_active_date,
    last_active_date,
    first_login_date,
    tutorial_completed_date,
    first_purchase_date,
    days_to_first_login,
    days_to_tutorial_complete,
    days_to_first_purchase,
    max_level_reached,
    total_level_ups,
    lifetime_revenue_usd,
    purchase_count,
    days_since_last_purchase,
    total_days_active,
    total_sessions,
    days_since_last_active,
    lifecycle_stage,
    updated_date
)
WITH

-- Milestone dates từ fact_events — MIN để lấy lần đầu tiên
milestones AS (
    SELECT
        user_id,
        MIN(local_event_date)                                               AS first_active_date,
        MAX(local_event_date)                                               AS last_active_date,
        MIN(CASE WHEN event_name = 'login'              THEN local_event_date END) AS first_login_date,
        MIN(CASE WHEN event_name = 'tutorial_completed' THEN local_event_date END) AS tutorial_completed_date,
        COUNT(DISTINCT local_event_date)                                    AS total_days_active,
        COUNT(DISTINCT session_id)                                          AS total_sessions
    FROM fact_events
    GROUP BY user_id
),

-- Progression summary từ fact_progression
progression AS (
    SELECT
        user_id,
        MAX(new_level)  AS max_level_reached,
        COUNT(*)        AS total_level_ups
    FROM fact_progression
    GROUP BY user_id
),

-- Monetization từ fact_purchases
monetization AS (
    SELECT
        user_id,
        SUM(revenue_usd)    AS lifetime_revenue_usd,
        COUNT(*)            AS purchase_count,
        MIN(purchase_date)  AS first_purchase_date,
        MAX(purchase_date)  AS last_purchase_date     -- THÊM DÒNG NÀY
    FROM fact_purchases
    GROUP BY user_id
)

SELECT
    du.user_id,

    -- Milestones
    du.account_created_date,
    COALESCE(m.first_active_date, du.account_created_date) AS first_active_date,
    m.last_active_date,
    m.first_login_date,
    m.tutorial_completed_date,
    mon.first_purchase_date,

    -- Days-to milestones
    DATEDIFF(m.first_login_date,        du.account_created_date) AS days_to_first_login,
    DATEDIFF(m.tutorial_completed_date, du.account_created_date) AS days_to_tutorial_complete,
    DATEDIFF(mon.first_purchase_date,   du.account_created_date) AS days_to_first_purchase,

    -- Progression
    p.max_level_reached,
    COALESCE(p.total_level_ups, 0)              AS total_level_ups,

    -- Monetization
    COALESCE(mon.lifetime_revenue_usd, 0)       AS lifetime_revenue_usd,
    COALESCE(mon.purchase_count, 0)             AS purchase_count,
    DATEDIFF(CURDATE(), mon.last_purchase_date) AS days_since_last_purchase, -- ĐỔI THÀNH LAST_PURCHASE

    -- Engagement
    COALESCE(m.total_days_active, 0)            AS total_days_active,
    COALESCE(m.total_sessions, 0)               AS total_sessions,
    DATEDIFF(CURDATE(), m.last_active_date)     AS days_since_last_active,

    -- Lifecycle stage
    CASE
        WHEN m.last_active_date IS NULL
             THEN 'new'
        WHEN DATEDIFF(CURDATE(), m.last_active_date) <= 7
             THEN 'active'
        WHEN DATEDIFF(CURDATE(), m.last_active_date) <= 30
             THEN 'at_risk'
        ELSE 'churned'
    END                                         AS lifecycle_stage,

    CURDATE()                                   AS updated_date

FROM dim_users du
LEFT JOIN milestones  m   ON m.user_id   = du.user_id
LEFT JOIN progression p   ON p.user_id   = du.user_id
LEFT JOIN monetization mon ON mon.user_id = du.user_id
;