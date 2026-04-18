-- =============================================================
-- gold/mart/monetization/mart_revenue_daily.sql
-- Doanh thu hàng ngày, breakdown theo product và acquisition channel.
--
-- Câu hỏi business trả lời:
--   "Hôm nay doanh thu từng sản phẩm là bao nhiêu?"
--   "Kênh nào mang lại paying user có giá trị nhất?"
--   "Bundle nào đang bán chạy nhất tuần này?"
--
-- Grain: 1 row per (revenue_date, product_id, acquisition_channel)
-- Source: fact_purchases, dim_users
-- Load: REPLACE INTO
-- Schedule: sau load_gold.py
-- =============================================================
USE game_gold;

CREATE TABLE IF NOT EXISTS mart_revenue_daily (

    revenue_date            DATE            NOT NULL,
    product_id              VARCHAR(100)    NOT NULL,
    acquisition_channel     VARCHAR(100)    NOT NULL    DEFAULT 'unknown',
    store                   VARCHAR(20)     NOT NULL,

    -- ── Revenue metrics ───────────────────────────────────────
    total_revenue_usd       DECIMAL(14, 4)  NOT NULL    DEFAULT 0,
    transaction_count       INT UNSIGNED    NOT NULL    DEFAULT 0,
    unique_buyers           INT UNSIGNED    NOT NULL    DEFAULT 0,
    new_buyer_count         INT UNSIGNED    NOT NULL    DEFAULT 0   COMMENT 'is_first_purchase = 1',
    returning_buyer_count   INT UNSIGNED    NOT NULL    DEFAULT 0,

    -- ── Derived ───────────────────────────────────────────────
    avg_revenue_per_txn     DECIMAL(10, 4)  NOT NULL    DEFAULT 0   COMMENT 'revenue / transaction_count',

    -- ── Audit ─────────────────────────────────────────────────
    updated_at              DATETIME        NOT NULL    DEFAULT CURRENT_TIMESTAMP
                                                        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (revenue_date, product_id, acquisition_channel, store),
    INDEX idx_revenue_date          (revenue_date),
    INDEX idx_product_id            (product_id),
    INDEX idx_acquisition_channel   (acquisition_channel, revenue_date)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COMMENT = 'Mart: doanh thu hàng ngày breakdown theo product × channel × store';


-- =============================================================
-- LOAD LOGIC
-- =============================================================

REPLACE INTO mart_revenue_daily (
    revenue_date,
    product_id,
    acquisition_channel,
    store,
    total_revenue_usd,
    transaction_count,
    unique_buyers,
    new_buyer_count,
    returning_buyer_count,
    avg_revenue_per_txn
)
SELECT
    fp.purchase_date                                AS revenue_date,
    fp.product_id,
    COALESCE(du.acquisition_channel, 'unknown')     AS acquisition_channel,
    fp.store,

    SUM(fp.revenue_usd)                             AS total_revenue_usd,
    COUNT(*)                                        AS transaction_count,
    COUNT(DISTINCT fp.user_id)                      AS unique_buyers,
    SUM(fp.is_first_purchase)                       AS new_buyer_count,
    SUM(1 - fp.is_first_purchase)                   AS returning_buyer_count,

    CASE WHEN COUNT(*) > 0
         THEN ROUND(SUM(fp.revenue_usd) / COUNT(*), 4)
         ELSE 0 END                                 AS avg_revenue_per_txn

FROM fact_purchases fp
LEFT JOIN dim_users du ON du.user_id = fp.user_id
GROUP BY
    fp.purchase_date,
    fp.product_id,
    COALESCE(du.acquisition_channel, 'unknown'),
    fp.store
;