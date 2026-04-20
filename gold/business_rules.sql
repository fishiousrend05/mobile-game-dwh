-- =============================================================
-- gold/business_rules.sql
-- Single source of truth cho toàn bộ business logic dùng chung.
--
-- Mục đích:
--   Tập trung tất cả threshold, segment definition, và benchmark
--   vào một file. Khi PM/Game Designer muốn thay đổi định nghĩa
--   "whale" từ $50 lên $100, chỉ sửa ở đây — không cần tìm
--   và sửa rải rác trong 8 view + 4 analytics files.
--
-- Cách dùng trong MySQL:
--   Không thể IMPORT file SQL như Python module.
--   Ba cách thực tế:
--
--   1. STORED FUNCTIONS — gọi như hàm trong bất kỳ query nào:
--      SELECT fn_value_segment(total_revenue_usd) FROM mart_user_profile;
--
--   2. REFERENCE COMMENTS — file này là tài liệu sống,
--      dev đọc định nghĩa ở đây rồi copy CASE WHEN vào query.
--      Có thể dùng sqlfluff hoặc custom linter để enforce.
--
--   3. CONFIG TABLE — INSERT threshold vào bảng
--      business_config, JOIN hoặc subquery khi cần dynamic threshold.
--
--   Project này dùng cả ba: Functions cho segment phức tạp,
--   Config table cho threshold có thể thay đổi theo game season,
--   Comments làm tài liệu cho những gì còn lại.
--
-- Chạy file này một lần khi setup, chạy lại khi thay đổi rules.
-- =============================================================


-- =============================================================
-- PHẦN 1: CONFIG TABLE — dynamic thresholds
-- =============================================================

CREATE TABLE IF NOT EXISTS business_config (
    config_key      VARCHAR(100)    NOT NULL                    COMMENT 'tên rule',
    config_value    VARCHAR(200)    NOT NULL                    COMMENT 'giá trị — luôn store dạng string, cast khi dùng',
    value_type      VARCHAR(20)     NOT NULL                    COMMENT 'DECIMAL | INT | STRING',
    category        VARCHAR(50)     NOT NULL                    COMMENT 'nhóm rule: monetization | engagement | retention | ...',
    description     VARCHAR(500)    DEFAULT NULL,
    updated_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (config_key)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4
  COMMENT = 'Dynamic business thresholds — sửa ở đây thay vì sửa trong query';

-- ── Monetization thresholds ───────────────────────────────────────
INSERT INTO business_config (config_key, config_value, value_type, category, description)
VALUES
    ('whale_min_revenue_usd',   '50',   'DECIMAL', 'monetization', 'User chi >= $50 lifetime → whale'),
    ('dolphin_min_revenue_usd', '10',   'DECIMAL', 'monetization', 'User chi >= $10 và < $50 → dolphin'),
    ('minnow_min_revenue_usd',  '0.01', 'DECIMAL', 'monetization', 'User chi > $0 và < $10 → minnow')
ON DUPLICATE KEY UPDATE
    config_value = VALUES(config_value),
    updated_at   = CURRENT_TIMESTAMP;

-- ── Lifecycle / churn thresholds ──────────────────────────────────
INSERT INTO business_config (config_key, config_value, value_type, category, description)
VALUES
    ('churn_days_inactive',    '30', 'INT', 'lifecycle', 'Không active quá N ngày → churned'),
    ('at_risk_days_inactive',  '7',  'INT', 'lifecycle', 'Không active N+1 đến churn_days → at_risk'),
    ('new_user_days',          '1',  'INT', 'lifecycle', 'User tạo tài khoản trong N ngày → new segment')
ON DUPLICATE KEY UPDATE
    config_value = VALUES(config_value),
    updated_at   = CURRENT_TIMESTAMP;

-- ── Retention benchmarks (industry standard mobile game) ──────────
INSERT INTO business_config (config_key, config_value, value_type, category, description)
VALUES
    ('retention_d1_good',   '0.40', 'DECIMAL', 'retention', 'D1 retention >= 40% → above benchmark'),
    ('retention_d1_avg',    '0.25', 'DECIMAL', 'retention', 'D1 retention >= 25% → at benchmark'),
    ('retention_d7_good',   '0.15', 'DECIMAL', 'retention', 'D7 retention >= 15% → above benchmark'),
    ('retention_d7_avg',    '0.08', 'DECIMAL', 'retention', 'D7 retention >= 8%  → at benchmark'),
    ('retention_d30_good',  '0.05', 'DECIMAL', 'retention', 'D30 retention >= 5% → above benchmark'),
    ('retention_d30_avg',   '0.02', 'DECIMAL', 'retention', 'D30 retention >= 2% → at benchmark')
ON DUPLICATE KEY UPDATE
    config_value = VALUES(config_value),
    updated_at   = CURRENT_TIMESTAMP;

-- ── Funnel health thresholds ──────────────────────────────────────
INSERT INTO business_config (config_key, config_value, value_type, category, description)
VALUES
    ('funnel_cr_healthy',  '0.05', 'DECIMAL', 'funnel', 'Overall CR register→purchase >= 5% → healthy'),
    ('funnel_cr_warning',  '0.02', 'DECIMAL', 'funnel', 'Overall CR >= 2% và < 5% → warning')
ON DUPLICATE KEY UPDATE
    config_value = VALUES(config_value),
    updated_at   = CURRENT_TIMESTAMP;

-- ── Session quality thresholds (giây) ─────────────────────────────
INSERT INTO business_config (config_key, config_value, value_type, category, description)
VALUES
    ('session_high_quality_sec',   '600', 'INT', 'engagement', 'Avg session >= 10 phút → high quality'),
    ('session_medium_quality_sec', '180', 'INT', 'engagement', 'Avg session >= 3 phút → medium quality'),
    ('session_min_valid_sec',      '10',  'INT', 'engagement', 'Session < 10 giây bị loại (crash/test)')
ON DUPLICATE KEY UPDATE
    config_value = VALUES(config_value),
    updated_at   = CURRENT_TIMESTAMP;

-- ── DAU signal thresholds ─────────────────────────────────────────
INSERT INTO business_config (config_key, config_value, value_type, category, description)
VALUES
    ('dau_drop_alert_threshold',  '-0.20', 'DECIMAL', 'engagement', 'DAU giảm > 20% WoW → drop_alert'),
    ('dau_spike_threshold',        '0.30', 'DECIMAL', 'engagement', 'DAU tăng > 30% WoW → spike')
ON DUPLICATE KEY UPDATE
    config_value = VALUES(config_value),
    updated_at   = CURRENT_TIMESTAMP;

-- ── Level band definitions ────────────────────────────────────────
INSERT INTO business_config (config_key, config_value, value_type, category, description)
VALUES
    ('level_band_early_max',  '10', 'INT', 'progression', 'Level <= N → early_game'),
    ('level_band_mid_max',    '30', 'INT', 'progression', 'Level <= N và > early_max → mid_game')
ON DUPLICATE KEY UPDATE
    config_value = VALUES(config_value),
    updated_at   = CURRENT_TIMESTAMP;


-- =============================================================
-- PHẦN 2: STORED FUNCTIONS — segment logic tái sử dụng
-- =============================================================

DROP FUNCTION IF EXISTS fn_value_segment;
DROP FUNCTION IF EXISTS fn_lifecycle_stage;
DROP FUNCTION IF EXISTS fn_engagement_segment;
DROP FUNCTION IF EXISTS fn_retention_benchmark;
DROP FUNCTION IF EXISTS fn_funnel_health;
DROP FUNCTION IF EXISTS fn_level_band;

DELIMITER $$

-- ── fn_value_segment ─────────────────────────────────────────────
-- Input : lifetime revenue USD của một user
-- Output: 'whale' | 'dolphin' | 'minnow' | 'non_payer'
-- Dùng  : SELECT fn_value_segment(total_revenue_usd) FROM mart_user_profile
CREATE FUNCTION fn_value_segment(revenue_usd DECIMAL(12,4))
RETURNS VARCHAR(20)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE whale_min   DECIMAL(10,4);
    DECLARE dolphin_min DECIMAL(10,4);

    SELECT CAST(config_value AS DECIMAL(10,4))
    INTO whale_min
    FROM business_config WHERE config_key = 'whale_min_revenue_usd';

    SELECT CAST(config_value AS DECIMAL(10,4))
    INTO dolphin_min
    FROM business_config WHERE config_key = 'dolphin_min_revenue_usd';

    RETURN CASE
        WHEN revenue_usd >= whale_min   THEN 'whale'
        WHEN revenue_usd >= dolphin_min THEN 'dolphin'
        WHEN revenue_usd >  0           THEN 'minnow'
        ELSE                                 'non_payer'
    END;
END$$


-- ── fn_lifecycle_stage ────────────────────────────────────────────
-- Input : days_since_last_active (NULL = chưa có activity)
-- Output: 'new' | 'active' | 'at_risk' | 'churned'
CREATE FUNCTION fn_lifecycle_stage(days_inactive SMALLINT)
RETURNS VARCHAR(20)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE churn_days   INT;
    DECLARE at_risk_days INT;

    SELECT CAST(config_value AS UNSIGNED)
    INTO churn_days
    FROM business_config WHERE config_key = 'churn_days_inactive';

    SELECT CAST(config_value AS UNSIGNED)
    INTO at_risk_days
    FROM business_config WHERE config_key = 'at_risk_days_inactive';

    RETURN CASE
        WHEN days_inactive IS NULL              THEN 'new'
        WHEN days_inactive <= at_risk_days      THEN 'active'
        WHEN days_inactive <= churn_days        THEN 'at_risk'
        ELSE                                         'churned'
    END;
END$$


-- ── fn_engagement_segment ────────────────────────────────────────
-- Input : days_since_last_active
-- Output: 'new' | 'daily' | 'weekly' | 'casual' | 'churned'
CREATE FUNCTION fn_engagement_segment(days_inactive SMALLINT)
RETURNS VARCHAR(20)
DETERMINISTIC
NO SQL
BEGIN
    RETURN CASE
        WHEN days_inactive IS NULL  THEN 'new'
        WHEN days_inactive <= 1     THEN 'daily'
        WHEN days_inactive <= 7     THEN 'weekly'
        WHEN days_inactive <= 30    THEN 'casual'
        ELSE                             'churned'
    END;
END$$


-- ── fn_retention_benchmark ───────────────────────────────────────
-- Input : retention rate (0.0–1.0), day_bucket ('d1'|'d7'|'d30')
-- Output: 'above_benchmark' | 'at_benchmark' | 'below_benchmark' | 'pending'
CREATE FUNCTION fn_retention_benchmark(rate DECIMAL(6,4), day_bucket VARCHAR(5))
RETURNS VARCHAR(20)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE good_key VARCHAR(100);
    DECLARE avg_key  VARCHAR(100);
    DECLARE good_val DECIMAL(6,4);
    DECLARE avg_val  DECIMAL(6,4);

    SET good_key = CONCAT('retention_', day_bucket, '_good');
    SET avg_key  = CONCAT('retention_', day_bucket, '_avg');

    SELECT CAST(config_value AS DECIMAL(6,4)) INTO good_val
    FROM business_config WHERE config_key = good_key;

    SELECT CAST(config_value AS DECIMAL(6,4)) INTO avg_val
    FROM business_config WHERE config_key = avg_key;

    IF rate IS NULL THEN
        RETURN 'pending';
    ELSEIF rate >= good_val THEN
        RETURN 'above_benchmark';
    ELSEIF rate >= avg_val THEN
        RETURN 'at_benchmark';
    ELSE
        RETURN 'below_benchmark';
    END IF;
END$$


-- ── fn_funnel_health ─────────────────────────────────────────────
-- Input : overall conversion rate (0.0–1.0)
-- Output: 'healthy' | 'warning' | 'critical'
CREATE FUNCTION fn_funnel_health(cr DECIMAL(6,4))
RETURNS VARCHAR(20)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE healthy_min DECIMAL(6,4);
    DECLARE warning_min DECIMAL(6,4);

    SELECT CAST(config_value AS DECIMAL(6,4)) INTO healthy_min
    FROM business_config WHERE config_key = 'funnel_cr_healthy';

    SELECT CAST(config_value AS DECIMAL(6,4)) INTO warning_min
    FROM business_config WHERE config_key = 'funnel_cr_warning';

    RETURN CASE
        WHEN cr >= healthy_min  THEN 'healthy'
        WHEN cr >= warning_min  THEN 'warning'
        ELSE                         'critical'
    END;
END$$


-- ── fn_level_band ────────────────────────────────────────────────
-- Input : level number
-- Output: 'early_game' | 'mid_game' | 'late_game'
CREATE FUNCTION fn_level_band(level_num SMALLINT)
RETURNS VARCHAR(20)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE early_max INT;
    DECLARE mid_max   INT;

    SELECT CAST(config_value AS UNSIGNED) INTO early_max
    FROM business_config WHERE config_key = 'level_band_early_max';

    SELECT CAST(config_value AS UNSIGNED) INTO mid_max
    FROM business_config WHERE config_key = 'level_band_mid_max';

    RETURN CASE
        WHEN level_num <= early_max THEN 'early_game'
        WHEN level_num <= mid_max   THEN 'mid_game'
        ELSE                             'late_game'
    END;
END$$

DELIMITER ;


-- =============================================================
-- PHẦN 3: USAGE REFERENCE
-- Ví dụ cách dùng functions trong query thực tế.
-- Uncomment để chạy thử.
-- =============================================================


-- Kiểm tra toàn bộ config hiện tại
SELECT category, config_key, config_value, description
FROM business_config
ORDER BY category, config_key;

-- Dùng functions trong query
SELECT
    user_id,
    total_revenue_usd,
    fn_value_segment(total_revenue_usd)         AS value_segment,
    fn_lifecycle_stage(days_since_last_active)  AS lifecycle_stage,
    fn_engagement_segment(days_since_last_active) AS engagement_segment,
    fn_level_band(current_level)                AS level_band
FROM mart_user_profile
LIMIT 10;

-- Thay đổi threshold: nâng whale lên $100
UPDATE business_config
SET config_value = '100'
WHERE config_key = 'whale_min_revenue_usd';
-- Sau đó tất cả query dùng fn_value_segment() tự động reflect threshold mới.

-- Kiểm tra retention benchmark
SELECT
    cohort_date,
    retention_d1,
    fn_retention_benchmark(retention_d1, 'd1')  AS d1_grade,
    fn_retention_benchmark(retention_d7, 'd7')  AS d7_grade
FROM mart_retention
WHERE acquisition_channel = 'all'
ORDER BY cohort_date DESC
LIMIT 30;
