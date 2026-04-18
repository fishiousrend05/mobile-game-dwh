-- =============================================================
-- gold/mart/engagement/mart_retention.sql
-- Cohort Retention tại D1, D7, D30 — một trong hai KPI cốt lõi
-- của project ("Người chơi có quay lại không?").
--
-- Câu hỏi business trả lời:
--   "Cohort ngày 1/3 có bao nhiêu % user quay lại vào ngày 7?"
--   "D7 retention của iOS vs Android khác nhau thế nào?"
--   "Tuần nào có D1 retention tốt nhất sau khi thay đổi tutorial?"
--
-- Grain: 1 row per (cohort_date, acquisition_channel)
--
-- Định nghĩa retention:
--   D1  = user có event trong khoảng [day1, day1]     (ngày thứ 2)
--   D7  = user có event trong khoảng [day6, day8]     (window ±1 ngày)
--   D30 = user có event trong khoảng [day29, day31]   (window ±1 ngày)
--
--   Window ±1 ngày là industry standard để tránh bỏ sót user
--   do timezone shift hoặc người chơi về đêm.
--
-- Source: dim_users, fact_events
-- Load: REPLACE INTO
-- Schedule: sau load_gold.py
-- =============================================================
USE game_gold;

CREATE TABLE IF NOT EXISTS mart_retention (

    cohort_date             DATE            NOT NULL    COMMENT 'account_created_date của nhóm user',
    acquisition_channel     VARCHAR(100)    NOT NULL    DEFAULT 'all',

    -- ── Cohort size ───────────────────────────────────────────
    cohort_size             INT UNSIGNED    NOT NULL    DEFAULT 0,

    -- ── Retained user counts ──────────────────────────────────
    retained_d1             INT UNSIGNED    NOT NULL    DEFAULT 0,
    retained_d7             INT UNSIGNED    NOT NULL    DEFAULT 0,
    retained_d30            INT UNSIGNED    NOT NULL    DEFAULT 0,

    -- ── Retention rates ───────────────────────────────────────
    retention_d1            DECIMAL(6, 4)   NOT NULL    DEFAULT 0   COMMENT '0.0–1.0',
    retention_d7            DECIMAL(6, 4)   NOT NULL    DEFAULT 0,
    retention_d30           DECIMAL(6, 4)   NOT NULL    DEFAULT 0,

    -- ── Data availability flags ───────────────────────────────
    -- NULL = chưa đủ ngày để tính (cohort quá mới)
    -- 0/1  = đã có đủ data
    d7_available            TINYINT(1)      NOT NULL    DEFAULT 0   COMMENT '1 nếu cohort_date <= CURDATE() - 8',
    d30_available           TINYINT(1)      NOT NULL    DEFAULT 0   COMMENT '1 nếu cohort_date <= CURDATE() - 31',

    -- ── Audit ─────────────────────────────────────────────────
    updated_at              DATETIME        NOT NULL    DEFAULT CURRENT_TIMESTAMP
                                                        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (cohort_date, acquisition_channel),
    INDEX idx_cohort_date           (cohort_date),
    INDEX idx_acquisition_channel   (acquisition_channel),
    INDEX idx_retention_d1          (retention_d1),
    INDEX idx_retention_d7          (retention_d7)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COMMENT = 'Mart: cohort retention D1/D7/D30 theo ngày tạo tài khoản × channel';


-- =============================================================
-- LOAD LOGIC
-- Two passes: per-channel và 'all' tổng hợp.
-- =============================================================

-- ── Per acquisition_channel ───────────────────────────────────
REPLACE INTO mart_retention (
    cohort_date,
    acquisition_channel,
    cohort_size,
    retained_d1, retained_d7, retained_d30,
    retention_d1, retention_d7, retention_d30,
    d7_available, d30_available
)
WITH

-- Mỗi user với cohort_date và channel
cohort_users AS (
    SELECT
        user_id,
        account_created_date                        AS cohort_date,
        COALESCE(acquisition_channel, 'unknown')    AS acquisition_channel
    FROM dim_users
),

-- Ngày active của từng user (deduplicated)
user_active_dates AS (
    SELECT DISTINCT user_id, local_event_date
    FROM fact_events
),

-- Cohort size theo ngày × channel
cohort_sizes AS (
    SELECT
        cohort_date,
        acquisition_channel,
        COUNT(DISTINCT user_id) AS cohort_size
    FROM cohort_users
    GROUP BY cohort_date, acquisition_channel
),

-- Retained users tại từng mốc
-- D1  window: day 1 chính xác (tránh count ngày tạo tài khoản)
-- D7  window: [day6, day8]  — ±1 ngày
-- D30 window: [day29, day31] — ±1 ngày
retained AS (
    SELECT
        cu.cohort_date,
        cu.acquisition_channel,

        COUNT(DISTINCT CASE
            WHEN DATEDIFF(uad.local_event_date, cu.cohort_date) = 1
            THEN cu.user_id END)                    AS retained_d1,

        COUNT(DISTINCT CASE
            WHEN DATEDIFF(uad.local_event_date, cu.cohort_date) BETWEEN 6 AND 8
            THEN cu.user_id END)                    AS retained_d7,

        COUNT(DISTINCT CASE
            WHEN DATEDIFF(uad.local_event_date, cu.cohort_date) BETWEEN 29 AND 31
            THEN cu.user_id END)                    AS retained_d30

    FROM cohort_users cu
    LEFT JOIN user_active_dates uad ON uad.user_id = cu.user_id
    GROUP BY cu.cohort_date, cu.acquisition_channel
)

SELECT
    cs.cohort_date,
    cs.acquisition_channel,
    cs.cohort_size,

    r.retained_d1,
    r.retained_d7,
    r.retained_d30,

    -- Retention rates
    CASE WHEN cs.cohort_size > 0
         THEN ROUND(r.retained_d1  / cs.cohort_size, 4) ELSE 0 END AS retention_d1,
    CASE WHEN cs.cohort_size > 0
         THEN ROUND(r.retained_d7  / cs.cohort_size, 4) ELSE 0 END AS retention_d7,
    CASE WHEN cs.cohort_size > 0
         THEN ROUND(r.retained_d30 / cs.cohort_size, 4) ELSE 0 END AS retention_d30,

    -- Availability flags: chỉ hiển thị khi đã đủ ngày trôi qua
    CASE WHEN DATEDIFF(CURDATE(), cs.cohort_date) >= 8  THEN 1 ELSE 0 END AS d7_available,
    CASE WHEN DATEDIFF(CURDATE(), cs.cohort_date) >= 31 THEN 1 ELSE 0 END AS d30_available

FROM cohort_sizes cs
LEFT JOIN retained r
       ON r.cohort_date          = cs.cohort_date
      AND r.acquisition_channel  = cs.acquisition_channel
;


-- ── acquisition_channel = 'all' — tổng hợp toàn bộ channel ───
REPLACE INTO mart_retention (
    cohort_date,
    acquisition_channel,
    cohort_size,
    retained_d1, retained_d7, retained_d30,
    retention_d1, retention_d7, retention_d30,
    d7_available, d30_available
)
WITH

all_cohort_sizes AS (
    SELECT
        account_created_date    AS cohort_date,
        COUNT(DISTINCT user_id) AS cohort_size
    FROM dim_users
    GROUP BY account_created_date
),

user_active_dates AS (
    SELECT DISTINCT user_id, local_event_date
    FROM fact_events
),

all_retained AS (
    SELECT
        du.account_created_date AS cohort_date,

        COUNT(DISTINCT CASE
            WHEN DATEDIFF(uad.local_event_date, du.account_created_date) = 1
            THEN du.user_id END)                    AS retained_d1,

        COUNT(DISTINCT CASE
            WHEN DATEDIFF(uad.local_event_date, du.account_created_date) BETWEEN 6 AND 8
            THEN du.user_id END)                    AS retained_d7,

        COUNT(DISTINCT CASE
            WHEN DATEDIFF(uad.local_event_date, du.account_created_date) BETWEEN 29 AND 31
            THEN du.user_id END)                    AS retained_d30

    FROM dim_users du
    LEFT JOIN user_active_dates uad ON uad.user_id = du.user_id
    GROUP BY du.account_created_date
)

SELECT
    acs.cohort_date,
    'all'                                           AS acquisition_channel,
    acs.cohort_size,

    ar.retained_d1,
    ar.retained_d7,
    ar.retained_d30,

    CASE WHEN acs.cohort_size > 0
         THEN ROUND(ar.retained_d1  / acs.cohort_size, 4) ELSE 0 END,
    CASE WHEN acs.cohort_size > 0
         THEN ROUND(ar.retained_d7  / acs.cohort_size, 4) ELSE 0 END,
    CASE WHEN acs.cohort_size > 0
         THEN ROUND(ar.retained_d30 / acs.cohort_size, 4) ELSE 0 END,

    CASE WHEN DATEDIFF(CURDATE(), acs.cohort_date) >= 8  THEN 1 ELSE 0 END,
    CASE WHEN DATEDIFF(CURDATE(), acs.cohort_date) >= 31 THEN 1 ELSE 0 END

FROM all_cohort_sizes acs
LEFT JOIN all_retained ar ON ar.cohort_date = acs.cohort_date
;