-- =============================================================
-- gold/mart/monetization/mart_arpu.sql
-- ARPU / ARPPU theo ngày, tuần, tháng.
--
-- Câu hỏi business trả lời:
--   "Trung bình mỗi user mang lại bao nhiêu doanh thu?"
--   "Paying users trung bình chi bao nhiêu?"
--   "Tuần này ARPPU tăng hay giảm so với tuần trước?"
--
-- Grain: 1 row per (period_type, period_start)
--   period_type = 'daily'   → period_start = ngày đó
--   period_type = 'weekly'  → period_start = thứ Hai đầu tuần
--   period_type = 'monthly' → period_start = ngày 1 của tháng
--
-- Công thức:
--   ARPU  = total_revenue / total_active_users
--   ARPPU = total_revenue / total_paying_users
--
-- Source: fact_purchases, fact_events
-- Load: REPLACE INTO (idempotent theo period_type + period_start)
-- Schedule: sau load_gold.py
-- =============================================================
USE game_gold;

CREATE TABLE IF NOT EXISTS mart_arpu (

    period_type             VARCHAR(10)     NOT NULL    COMMENT 'daily | weekly | monthly',
    period_start            DATE            NOT NULL    COMMENT 'ngày bắt đầu của period',
    period_end              DATE            NOT NULL    COMMENT 'ngày kết thúc (inclusive)',

    -- ── Revenue ───────────────────────────────────────────────
    total_revenue_usd       DECIMAL(14, 4)  NOT NULL    DEFAULT 0,
    total_transactions      INT UNSIGNED    NOT NULL    DEFAULT 0,

    -- ── User counts ───────────────────────────────────────────
    total_active_users      INT UNSIGNED    NOT NULL    DEFAULT 0   COMMENT 'có ít nhất 1 event trong period',
    total_paying_users      INT UNSIGNED    NOT NULL    DEFAULT 0   COMMENT 'có ít nhất 1 purchase trong period',
    new_paying_users        INT UNSIGNED    NOT NULL    DEFAULT 0   COMMENT 'is_first_purchase = 1',

    -- ── Metrics ───────────────────────────────────────────────
    arpu                    DECIMAL(10, 4)  NOT NULL    DEFAULT 0   COMMENT 'revenue / active_users',
    arppu                   DECIMAL(10, 4)  NOT NULL    DEFAULT 0   COMMENT 'revenue / paying_users',
    paying_user_rate        DECIMAL(6, 4)   NOT NULL    DEFAULT 0   COMMENT 'paying / active — conversion rate',

    -- ── Audit ─────────────────────────────────────────────────
    updated_at              DATETIME        NOT NULL    DEFAULT CURRENT_TIMESTAMP
                                                        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (period_type, period_start),
    INDEX idx_period_start  (period_start),
    INDEX idx_period_type   (period_type)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COMMENT = 'Mart: ARPU/ARPPU theo daily/weekly/monthly';


-- =============================================================
-- LOAD LOGIC
-- Ba INSERT liên tiếp cho ba granularity.
-- REPLACE INTO đảm bảo re-run cùng ngày không duplicate.
-- =============================================================

-- ── Daily ─────────────────────────────────────────────────────
REPLACE INTO mart_arpu (
    period_type, period_start, period_end,
    total_revenue_usd, total_transactions,
    total_active_users, total_paying_users, new_paying_users,
    arpu, arppu, paying_user_rate
)
WITH
daily_revenue AS (
    SELECT
        purchase_date                       AS period_start,
        SUM(revenue_usd)                    AS total_revenue_usd,
        COUNT(*)                            AS total_transactions,
        COUNT(DISTINCT user_id)             AS total_paying_users,
        SUM(is_first_purchase)              AS new_paying_users
    FROM fact_purchases
    GROUP BY purchase_date
),
daily_active AS (
    SELECT
        local_event_date                    AS period_start,
        COUNT(DISTINCT user_id)             AS total_active_users
    FROM fact_events
    GROUP BY local_event_date
)
SELECT
    'daily'                                 AS period_type,
    da.period_start,
    da.period_start                         AS period_end,
    COALESCE(dr.total_revenue_usd, 0),
    COALESCE(dr.total_transactions, 0),
    da.total_active_users,
    COALESCE(dr.total_paying_users, 0),
    COALESCE(dr.new_paying_users, 0),
    -- ARPU: tránh division by zero
    CASE WHEN da.total_active_users > 0
         THEN ROUND(COALESCE(dr.total_revenue_usd, 0) / da.total_active_users, 4)
         ELSE 0 END                         AS arpu,
    CASE WHEN COALESCE(dr.total_paying_users, 0) > 0
         THEN ROUND(dr.total_revenue_usd / dr.total_paying_users, 4)
         ELSE 0 END                         AS arppu,
    CASE WHEN da.total_active_users > 0
         THEN ROUND(COALESCE(dr.total_paying_users, 0) / da.total_active_users, 4)
         ELSE 0 END                         AS paying_user_rate
FROM daily_active da
LEFT JOIN daily_revenue dr ON dr.period_start = da.period_start
;

-- ── Weekly (ISO: Thứ Hai → Chủ Nhật) ─────────────────────────
REPLACE INTO mart_arpu (
    period_type, period_start, period_end,
    total_revenue_usd, total_transactions,
    total_active_users, total_paying_users, new_paying_users,
    arpu, arppu, paying_user_rate
)
WITH
weekly_revenue AS (
    SELECT
        -- Lùi về thứ Hai của tuần đó
        DATE_SUB(purchase_date, INTERVAL WEEKDAY(purchase_date) DAY) AS period_start,
        SUM(revenue_usd)                    AS total_revenue_usd,
        COUNT(*)                            AS total_transactions,
        COUNT(DISTINCT user_id)             AS total_paying_users,
        SUM(is_first_purchase)              AS new_paying_users
    FROM fact_purchases
    GROUP BY period_start
),
weekly_active AS (
    SELECT
        DATE_SUB(local_event_date, INTERVAL WEEKDAY(local_event_date) DAY) AS period_start,
        COUNT(DISTINCT user_id)             AS total_active_users
    FROM fact_events
    GROUP BY period_start
)
SELECT
    'weekly'                                AS period_type,
    wa.period_start,
    DATE_ADD(wa.period_start, INTERVAL 6 DAY) AS period_end,
    COALESCE(wr.total_revenue_usd, 0),
    COALESCE(wr.total_transactions, 0),
    wa.total_active_users,
    COALESCE(wr.total_paying_users, 0),
    COALESCE(wr.new_paying_users, 0),
    CASE WHEN wa.total_active_users > 0
         THEN ROUND(COALESCE(wr.total_revenue_usd, 0) / wa.total_active_users, 4)
         ELSE 0 END,
    CASE WHEN COALESCE(wr.total_paying_users, 0) > 0
         THEN ROUND(wr.total_revenue_usd / wr.total_paying_users, 4)
         ELSE 0 END,
    CASE WHEN wa.total_active_users > 0
         THEN ROUND(COALESCE(wr.total_paying_users, 0) / wa.total_active_users, 4)
         ELSE 0 END
FROM weekly_active wa
LEFT JOIN weekly_revenue wr ON wr.period_start = wa.period_start
;

-- ── Monthly ───────────────────────────────────────────────────
REPLACE INTO mart_arpu (
    period_type, period_start, period_end,
    total_revenue_usd, total_transactions,
    total_active_users, total_paying_users, new_paying_users,
    arpu, arppu, paying_user_rate
)
WITH
monthly_revenue AS (
    SELECT
        DATE_FORMAT(purchase_date, '%Y-%m-01')  AS period_start,
        SUM(revenue_usd)                        AS total_revenue_usd,
        COUNT(*)                                AS total_transactions,
        COUNT(DISTINCT user_id)                 AS total_paying_users,
        SUM(is_first_purchase)                  AS new_paying_users
    FROM fact_purchases
    GROUP BY period_start
),
monthly_active AS (
    SELECT
        DATE_FORMAT(local_event_date, '%Y-%m-01') AS period_start,
        COUNT(DISTINCT user_id)                   AS total_active_users
    FROM fact_events
    GROUP BY period_start
)
SELECT
    'monthly'                               AS period_type,
    ma.period_start,
    LAST_DAY(ma.period_start)              AS period_end,
    COALESCE(mr.total_revenue_usd, 0),
    COALESCE(mr.total_transactions, 0),
    ma.total_active_users,
    COALESCE(mr.total_paying_users, 0),
    COALESCE(mr.new_paying_users, 0),
    CASE WHEN ma.total_active_users > 0
         THEN ROUND(COALESCE(mr.total_revenue_usd, 0) / ma.total_active_users, 4)
         ELSE 0 END,
    CASE WHEN COALESCE(mr.total_paying_users, 0) > 0
         THEN ROUND(mr.total_revenue_usd / mr.total_paying_users, 4)
         ELSE 0 END,
    CASE WHEN ma.total_active_users > 0
         THEN ROUND(COALESCE(mr.total_paying_users, 0) / ma.total_active_users, 4)
         ELSE 0 END
FROM monthly_active ma
LEFT JOIN monthly_revenue mr ON mr.period_start = ma.period_start;