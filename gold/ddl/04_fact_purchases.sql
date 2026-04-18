USE game_gold;
-- =============================================================
-- 04_fact_purchases.sql
-- FACT_PURCHASES: Mỗi row = 1 giao dịch in-app purchase.
-- Source: Silver FACT_EVENT_PARAMS (event_name = 'in_app_purchase')
--         + FACT_EVENT_ITEMS  (items_received của transaction đó)
-- Load:   INSERT IGNORE — idempotent theo transaction_id
--
-- FK notes:
--   → dim_users(user_id)      : FK chuẩn, dim không partition
--   → fact_events(event_uuid) : MySQL không cho FK vào partitioned table
--                               → giữ idx_event_uuid, enforce ở load_gold.py
-- =============================================================

CREATE TABLE IF NOT EXISTS fact_purchases (

    -- ── Primary key ───────────────────────────────────────────
    transaction_id          VARCHAR(100)    NOT NULL
                                            COMMENT 'ID từ app store — natural PK, idempotency key',

    -- ── References ────────────────────────────────────────────
    event_uuid              VARCHAR(36)     NOT NULL
                                            COMMENT 'Ref → fact_events.event_uuid (no FK, table is partitioned)',
    user_id                 VARCHAR(50)     NOT NULL
                                            COMMENT 'Denormalized từ fact_events — tránh join khi query monetization',

    -- ── Transaction details ───────────────────────────────────
    store                   VARCHAR(20)     NOT NULL
                                            COMMENT 'app_store | google_play',
    product_id              VARCHAR(100)    NOT NULL
                                            COMMENT 'bundle_monthly_pass | gem_pack_1000 | ...',
    revenue_usd             DECIMAL(10, 4)  NOT NULL
                                            COMMENT 'DECIMAL tránh floating-point error khi SUM nhiều row',
    is_first_purchase       TINYINT(1)      NOT NULL    DEFAULT 0
                                            COMMENT '1 = lần mua đầu tiên của user này',
    purchase_context        VARCHAR(50)     DEFAULT NULL
                                            COMMENT 'stuck_progression | event_offer | organic | ...',

    -- ── Timestamps ────────────────────────────────────────────
    purchased_at            DATETIME(3)     NOT NULL
                                            COMMENT 'server_timestamp_utc của event tương ứng',
    purchase_date           DATE            NOT NULL
                                            COMMENT 'DATE(purchased_at) — GROUP BY daily revenue',

    -- ── Audit ─────────────────────────────────────────────────
    event_date              DATE            NOT NULL
                                            COMMENT 'Silver partition date của batch load',

    -- ── Constraints & Indexes ─────────────────────────────────
    PRIMARY KEY (transaction_id),
    INDEX idx_user_date         (user_id, purchase_date),
    INDEX idx_product_date      (product_id, purchase_date),
    INDEX idx_purchase_date     (purchase_date),
    INDEX idx_event_uuid        (event_uuid),
    INDEX idx_is_first_purchase (is_first_purchase, purchase_date),

    CONSTRAINT fk_fp_user FOREIGN KEY (user_id) REFERENCES dim_users (user_id)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COMMENT = 'Fact: mỗi row = 1 in_app_purchase. DECIMAL revenue, FK → dim_users only.';