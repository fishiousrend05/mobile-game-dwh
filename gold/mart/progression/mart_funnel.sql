-- =============================================================
-- gold/mart/progression/mart_funnel.sql
-- Conversion Funnel: Register → Tutorial → First Purchase.
-- KPI cốt lõi thứ hai của project ("Họ nạp tiền ở giai đoạn nào?").
--
-- Câu hỏi business trả lời:
--   "Bao nhiêu % user hoàn thành tutorial sau khi đăng ký?"
--   "Drop-off lớn nhất xảy ra ở bước nào trong funnel?"
--   "Cohort nào có conversion rate tốt nhất?"
--   "Kênh facebook_ads vs organic: funnel khác nhau thế nào?"
--
-- Grain: 1 row per (cohort_date, acquisition_channel)
--   cohort_date = account_created_date
--
-- Các bước funnel:
--   Step 1: registered        → tất cả user có account_created event
--   Step 2: tutorial_done     → user có tutorial_completed event
--   Step 3: first_purchase    → user có is_first_purchase = 1
--
-- Drop-off tính theo:
--   registered → tutorial : bao nhiêu % bỏ cuộc trước tutorial
--   tutorial   → purchase : bao nhiêu % hoàn thành tutorial nhưng không mua
--   overall               : registered → purchase
--
-- Source: dim_users, fact_events, fact_purchases
-- Load: REPLACE INTO
-- Schedule: sau load_gold.py
-- =============================================================
Use game_gold;
CREATE TABLE IF NOT EXISTS mart_funnel (

    cohort_date             DATE            NOT NULL    COMMENT 'account_created_date',
    acquisition_channel     VARCHAR(100)    NOT NULL    DEFAULT 'all',

    -- ── Funnel counts ─────────────────────────────────────────
    step1_registered        INT UNSIGNED    NOT NULL    DEFAULT 0   COMMENT 'user tạo tài khoản',
    step2_tutorial_done     INT UNSIGNED    NOT NULL    DEFAULT 0   COMMENT 'user hoàn thành tutorial',
    step3_first_purchase    INT UNSIGNED    NOT NULL    DEFAULT 0   COMMENT 'user thực hiện mua hàng đầu tiên',

    -- ── Conversion rates (step-over-step) ────────────────────
    cr_reg_to_tutorial      DECIMAL(6, 4)   NOT NULL    DEFAULT 0   COMMENT 'step2 / step1',
    cr_tutorial_to_purchase DECIMAL(6, 4)   NOT NULL    DEFAULT 0   COMMENT 'step3 / step2',
    cr_overall              DECIMAL(6, 4)   NOT NULL    DEFAULT 0   COMMENT 'step3 / step1 — overall funnel',

    -- ── Drop-off counts ───────────────────────────────────────
    dropoff_at_tutorial     INT UNSIGNED    NOT NULL    DEFAULT 0   COMMENT 'step1 - step2',
    dropoff_after_tutorial  INT UNSIGNED    NOT NULL    DEFAULT 0   COMMENT 'step2 - step3',

    -- ── Time-to-convert (median, ngày) ────────────────────────
    -- NULL nếu step chưa đạt hoặc chưa đủ data
    median_days_to_tutorial     DECIMAL(6, 1)   DEFAULT NULL COMMENT 'từ register đến tutorial_completed',
    median_days_to_purchase     DECIMAL(6, 1)   DEFAULT NULL COMMENT 'từ register đến first_purchase',

    -- ── Audit ─────────────────────────────────────────────────
    updated_at              DATETIME        NOT NULL    DEFAULT CURRENT_TIMESTAMP
                                                        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (cohort_date, acquisition_channel),
    INDEX idx_cohort_date           (cohort_date),
    INDEX idx_acquisition_channel   (acquisition_channel),
    INDEX idx_cr_overall            (cr_overall)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COMMENT = 'Mart: conversion funnel Register→Tutorial→FirstPurchase theo cohort_date × channel';


-- =============================================================
-- LOAD LOGIC
-- =============================================================

-- ── Per acquisition_channel ───────────────────────────────────
REPLACE INTO mart_funnel (
    cohort_date,
    acquisition_channel,
    step1_registered,
    step2_tutorial_done,
    step3_first_purchase,
    cr_reg_to_tutorial,
    cr_tutorial_to_purchase,
    cr_overall,
    dropoff_at_tutorial,
    dropoff_after_tutorial,
    median_days_to_tutorial,
    median_days_to_purchase
)
WITH

-- Base cohort: tất cả user đã đăng ký
cohort AS (
    SELECT
        user_id,
        account_created_date                        AS cohort_date,
        COALESCE(acquisition_channel, 'unknown')    AS acquisition_channel
    FROM dim_users
),

-- Step 2: user đã hoàn thành tutorial
tutorial AS (
    SELECT DISTINCT user_id
    FROM fact_events
    WHERE event_name = 'tutorial_completed'
),

-- Step 3: user đã thực hiện first purchase
first_purchase AS (
    SELECT DISTINCT user_id
    FROM fact_purchases
    WHERE is_first_purchase = 1
),

-- Days từ register đến tutorial (per user)
days_to_tutorial AS (
    SELECT
        du.user_id,
        DATEDIFF(MIN(fe.local_event_date), du.account_created_date) AS days
    FROM dim_users du
    JOIN fact_events fe
      ON fe.user_id    = du.user_id
     AND fe.event_name = 'tutorial_completed'
    GROUP BY du.user_id, du.account_created_date
),

-- Days từ register đến first purchase (per user)
days_to_purchase AS (
    SELECT
        du.user_id,
        DATEDIFF(MIN(fp.purchase_date), du.account_created_date) AS days
    FROM dim_users du
    JOIN fact_purchases fp
      ON fp.user_id          = du.user_id
     AND fp.is_first_purchase = 1
    GROUP BY du.user_id, du.account_created_date
),

-- Funnel aggregate per cohort × channel
funnel_counts AS (
    SELECT
        c.cohort_date,
        c.acquisition_channel,

        COUNT(DISTINCT c.user_id)                   AS step1_registered,
        COUNT(DISTINCT t.user_id)                   AS step2_tutorial_done,
        COUNT(DISTINCT p.user_id)                   AS step3_first_purchase

    FROM cohort c
    LEFT JOIN tutorial      t  ON t.user_id = c.user_id
    LEFT JOIN first_purchase p ON p.user_id = c.user_id
    GROUP BY c.cohort_date, c.acquisition_channel
),

-- Median days per cohort × channel (dùng AVG làm proxy khi dataset nhỏ)
-- Với dataset lớn hơn: thay bằng PERCENTILE_CONT
median_tutorial AS (
    SELECT
        c.cohort_date,
        c.acquisition_channel,
        ROUND(AVG(dtt.days), 1)                     AS median_days
    FROM cohort c
    JOIN days_to_tutorial dtt ON dtt.user_id = c.user_id
    GROUP BY c.cohort_date, c.acquisition_channel
),

median_purchase AS (
    SELECT
        c.cohort_date,
        c.acquisition_channel,
        ROUND(AVG(dtp.days), 1)                     AS median_days
    FROM cohort c
    JOIN days_to_purchase dtp ON dtp.user_id = c.user_id
    GROUP BY c.cohort_date, c.acquisition_channel
)

SELECT
    fc.cohort_date,
    fc.acquisition_channel,
    fc.step1_registered,
    fc.step2_tutorial_done,
    fc.step3_first_purchase,

    -- Conversion rates — tránh division by zero
    CASE WHEN fc.step1_registered > 0
         THEN ROUND(fc.step2_tutorial_done  / fc.step1_registered, 4) ELSE 0 END
                                                    AS cr_reg_to_tutorial,
    CASE WHEN fc.step2_tutorial_done > 0
         THEN ROUND(fc.step3_first_purchase / fc.step2_tutorial_done, 4) ELSE 0 END
                                                    AS cr_tutorial_to_purchase,
    CASE WHEN fc.step1_registered > 0
         THEN ROUND(fc.step3_first_purchase / fc.step1_registered, 4) ELSE 0 END
                                                    AS cr_overall,

    -- Drop-off
-- Chống dội số âm làm crash cột UNSIGNED
    CASE WHEN fc.step1_registered > fc.step2_tutorial_done
         THEN fc.step1_registered - fc.step2_tutorial_done ELSE 0 END AS dropoff_at_tutorial,

    CASE WHEN fc.step2_tutorial_done > fc.step3_first_purchase
         THEN fc.step2_tutorial_done - fc.step3_first_purchase ELSE 0 END AS dropoff_after_tutorial,

    mt.median_days                                  AS median_days_to_tutorial,
    mp.median_days                                  AS median_days_to_purchase

FROM funnel_counts fc
LEFT JOIN median_tutorial mt
       ON mt.cohort_date          = fc.cohort_date
      AND mt.acquisition_channel  = fc.acquisition_channel
LEFT JOIN median_purchase mp
       ON mp.cohort_date          = fc.cohort_date
      AND mp.acquisition_channel  = fc.acquisition_channel
;


-- ── acquisition_channel = 'all' ───────────────────────────────
REPLACE INTO mart_funnel (
    cohort_date,
    acquisition_channel,
    step1_registered,
    step2_tutorial_done,
    step3_first_purchase,
    cr_reg_to_tutorial,
    cr_tutorial_to_purchase,
    cr_overall,
    dropoff_at_tutorial,
    dropoff_after_tutorial,
    median_days_to_tutorial,
    median_days_to_purchase
)
WITH

all_funnel AS (
    SELECT
        du.account_created_date             AS cohort_date,
        COUNT(DISTINCT du.user_id)          AS step1_registered,
        COUNT(DISTINCT CASE WHEN fe_tut.user_id IS NOT NULL
                            THEN du.user_id END) AS step2_tutorial_done,
        COUNT(DISTINCT CASE WHEN fp_first.user_id IS NOT NULL
                            THEN du.user_id END) AS step3_first_purchase
    FROM dim_users du
    LEFT JOIN (
        SELECT DISTINCT user_id
        FROM fact_events
        WHERE event_name = 'tutorial_completed'
    ) fe_tut ON fe_tut.user_id = du.user_id
    LEFT JOIN (
        SELECT DISTINCT user_id
        FROM fact_purchases
        WHERE is_first_purchase = 1
    ) fp_first ON fp_first.user_id = du.user_id
    GROUP BY du.account_created_date
),

all_median_tutorial AS (
    SELECT
        du.account_created_date             AS cohort_date,
        ROUND(AVG(DATEDIFF(fe.local_event_date, du.account_created_date)), 1) AS median_days
    FROM dim_users du
    JOIN fact_events fe
      ON fe.user_id    = du.user_id
     AND fe.event_name = 'tutorial_completed'
    GROUP BY du.account_created_date
),

all_median_purchase AS (
    SELECT
        du.account_created_date             AS cohort_date,
        ROUND(AVG(DATEDIFF(fp.purchase_date, du.account_created_date)), 1) AS median_days
    FROM dim_users du
    JOIN fact_purchases fp
      ON fp.user_id          = du.user_id
     AND fp.is_first_purchase = 1
    GROUP BY du.account_created_date
)

SELECT
    af.cohort_date,
    'all'                                   AS acquisition_channel,
    CASE WHEN af.step1_registered > af.step2_tutorial_done
         THEN af.step1_registered - af.step2_tutorial_done ELSE 0 END,

    CASE WHEN af.step2_tutorial_done > af.step3_first_purchase
         THEN af.step2_tutorial_done - af.step3_first_purchase ELSE 0 END,
    af.step3_first_purchase,

    CASE WHEN af.step1_registered > 0
         THEN ROUND(af.step2_tutorial_done  / af.step1_registered, 4)   ELSE 0 END,
    CASE WHEN af.step2_tutorial_done > 0
         THEN ROUND(af.step3_first_purchase / af.step2_tutorial_done, 4) ELSE 0 END,
    CASE WHEN af.step1_registered > 0
         THEN ROUND(af.step3_first_purchase / af.step1_registered, 4)   ELSE 0 END,

    af.step1_registered   - af.step2_tutorial_done,
    af.step2_tutorial_done - af.step3_first_purchase,

    amt.median_days,
    amp.median_days

FROM all_funnel af
LEFT JOIN all_median_tutorial amt ON amt.cohort_date = af.cohort_date
LEFT JOIN all_median_purchase amp ON amp.cohort_date = af.cohort_date
;