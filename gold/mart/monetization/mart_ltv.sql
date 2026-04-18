-- =============================================================
-- gold/mart/monetization/mart_ltv.sql
-- Lifetime Value (LTV) theo cohort tháng tạo tài khoản.
--
-- Câu hỏi business trả lời:
--   "Cohort tháng 3 sau 30 ngày mang lại bao nhiêu doanh thu?"
--   "LTV D7 của user từ facebook_ads vs organic chênh nhau bao nhiêu?"
--   "Cần bao nhiêu ngày để thu hồi chi phí acquisition?"
--
-- Grain: 1 row per (cohort_month, acquisition_channel, days_since_install_bucket)
--
-- days_since_install_bucket:
--   d1   = revenue trong ngày 0–1
--   d7   = revenue tích lũy đến ngày 7
--   d30  = revenue tích lũy đến ngày 30
--   d90  = revenue tích lũy đến ngày 90
--   total = toàn bộ revenue đến hiện tại
--
-- Source: fact_purchases, dim_users
-- Load: REPLACE INTO
-- Schedule: sau load_gold.py
-- =============================================================
USE game_gold;

CREATE TABLE IF NOT EXISTS mart_ltv (

    cohort_month            VARCHAR(7)      NOT NULL    COMMENT 'YYYY-MM — tháng tạo tài khoản',
    acquisition_channel     VARCHAR(100)    NOT NULL    DEFAULT 'unknown',

    -- ── Cohort size ───────────────────────────────────────────
    cohort_size             INT UNSIGNED    NOT NULL    DEFAULT 0   COMMENT 'tổng user trong cohort',
    paying_users_ever       INT UNSIGNED    NOT NULL    DEFAULT 0   COMMENT 'có ít nhất 1 purchase mọi thời điểm',

    -- ── Cumulative revenue tại từng mốc (per cohort, không chia) ─
    revenue_d1              DECIMAL(14, 4)  NOT NULL    DEFAULT 0,
    revenue_d7              DECIMAL(14, 4)  NOT NULL    DEFAULT 0,
    revenue_d30             DECIMAL(14, 4)  NOT NULL    DEFAULT 0,
    revenue_d90             DECIMAL(14, 4)  NOT NULL    DEFAULT 0,
    revenue_total           DECIMAL(14, 4)  NOT NULL    DEFAULT 0,

    -- ── LTV per user (revenue / cohort_size) ─────────────────
    ltv_d1                  DECIMAL(10, 4)  NOT NULL    DEFAULT 0,
    ltv_d7                  DECIMAL(10, 4)  NOT NULL    DEFAULT 0,
    ltv_d30                 DECIMAL(10, 4)  NOT NULL    DEFAULT 0,
    ltv_d90                 DECIMAL(10, 4)  NOT NULL    DEFAULT 0,
    ltv_total               DECIMAL(10, 4)  NOT NULL    DEFAULT 0,

    -- ── Conversion rate ───────────────────────────────────────
    conversion_rate         DECIMAL(6, 4)   NOT NULL    DEFAULT 0   COMMENT 'paying_users_ever / cohort_size',

    -- ── Audit ─────────────────────────────────────────────────
    updated_at              DATETIME        NOT NULL    DEFAULT CURRENT_TIMESTAMP
                                                        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (cohort_month, acquisition_channel),
    INDEX idx_cohort_month          (cohort_month),
    INDEX idx_acquisition_channel   (acquisition_channel)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COMMENT = 'Mart: LTV theo cohort tháng × acquisition channel, tích lũy tại D1/D7/D30/D90';


-- =============================================================
-- LOAD LOGIC
-- =============================================================

REPLACE INTO mart_ltv (
    cohort_month,
    acquisition_channel,
    cohort_size,
    paying_users_ever,
    revenue_d1,
    revenue_d7,
    revenue_d30,
    revenue_d90,
    revenue_total,
    ltv_d1,
    ltv_d7,
    ltv_d30,
    ltv_d90,
    ltv_total,
    conversion_rate
)
WITH

-- Mỗi user thuộc cohort nào, channel nào
user_cohorts AS (
    SELECT
        user_id,
        DATE_FORMAT(account_created_date, '%Y-%m') AS cohort_month,
        account_created_date,
        COALESCE(acquisition_channel, 'unknown')   AS acquisition_channel
    FROM dim_users
),

-- Revenue mỗi purchase + số ngày kể từ khi user tạo tài khoản
purchase_with_age AS (
    SELECT
        fp.user_id,
        fp.revenue_usd,
        DATEDIFF(fp.purchase_date, uc.account_created_date) AS days_since_created
    FROM fact_purchases fp
    JOIN user_cohorts uc ON uc.user_id = fp.user_id
),

-- Aggregate revenue theo cohort × channel × mốc ngày
cohort_revenue AS (
    SELECT
        uc.cohort_month,
        uc.acquisition_channel,

        COUNT(DISTINCT uc.user_id)                                          AS cohort_size,
        COUNT(DISTINCT pwa.user_id)                                         AS paying_users_ever,

        -- Tích lũy tại từng mốc — COALESCE vì LEFT JOIN có thể NULL
        COALESCE(SUM(CASE WHEN pwa.days_since_created <= 1  THEN pwa.revenue_usd END), 0) AS revenue_d1,
        COALESCE(SUM(CASE WHEN pwa.days_since_created <= 7  THEN pwa.revenue_usd END), 0) AS revenue_d7,
        COALESCE(SUM(CASE WHEN pwa.days_since_created <= 30 THEN pwa.revenue_usd END), 0) AS revenue_d30,
        COALESCE(SUM(CASE WHEN pwa.days_since_created <= 90 THEN pwa.revenue_usd END), 0) AS revenue_d90,
        COALESCE(SUM(pwa.revenue_usd), 0)                                   AS revenue_total

    FROM user_cohorts uc
    LEFT JOIN purchase_with_age pwa ON pwa.user_id = uc.user_id
    GROUP BY uc.cohort_month, uc.acquisition_channel
)

SELECT
    cohort_month,
    acquisition_channel,
    cohort_size,
    paying_users_ever,

    revenue_d1,
    revenue_d7,
    revenue_d30,
    revenue_d90,
    revenue_total,

    -- LTV = revenue / cohort_size — tránh division by zero
    CASE WHEN cohort_size > 0 THEN ROUND(revenue_d1    / cohort_size, 4) ELSE 0 END AS ltv_d1,
    CASE WHEN cohort_size > 0 THEN ROUND(revenue_d7    / cohort_size, 4) ELSE 0 END AS ltv_d7,
    CASE WHEN cohort_size > 0 THEN ROUND(revenue_d30   / cohort_size, 4) ELSE 0 END AS ltv_d30,
    CASE WHEN cohort_size > 0 THEN ROUND(revenue_d90   / cohort_size, 4) ELSE 0 END AS ltv_d90,
    CASE WHEN cohort_size > 0 THEN ROUND(revenue_total / cohort_size, 4) ELSE 0 END AS ltv_total,

    CASE WHEN cohort_size > 0
         THEN ROUND(paying_users_ever / cohort_size, 4)
         ELSE 0 END                                                         AS conversion_rate

FROM cohort_revenue
;