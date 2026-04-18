-- =============================================================
-- gold/mart/engagement/mart_dau_mau.sql
-- DAU, WAU, MAU và tỷ lệ Stickiness (DAU/MAU).
--
-- Câu hỏi business trả lời:
--   "Hôm nay có bao nhiêu user active?"
--   "DAU/MAU ratio tuần này là bao nhiêu? (stickiness)"
--   "Platform nào có engagement cao hơn: iOS hay Android?"
--
-- Grain: 1 row per (report_date, platform)
--   platform = 'iOS' | 'Android' | 'all' (tổng hợp)
--   Dùng thêm cột platform thay vì tách bảng → Tableau filter dễ hơn.
--
-- Định nghĩa:
--   DAU = distinct users có event trong ngày report_date
--   WAU = distinct users có event trong 7 ngày kết thúc tại report_date
--   MAU = distinct users có event trong 30 ngày kết thúc tại report_date
--   Stickiness = DAU / MAU (đo mức độ habit-forming của game)
--
-- Source: fact_events, dim_device
-- Load: REPLACE INTO
-- Schedule: sau load_gold.py
-- =============================================================
USE game_gold;

CREATE TABLE IF NOT EXISTS mart_dau_mau (

    report_date             DATE            NOT NULL,
    platform                VARCHAR(10)     NOT NULL    COMMENT 'iOS | Android | all',

    -- ── Active user counts ────────────────────────────────────
    dau                     INT UNSIGNED    NOT NULL    DEFAULT 0,
    wau                     INT UNSIGNED    NOT NULL    DEFAULT 0,
    mau                     INT UNSIGNED    NOT NULL    DEFAULT 0,

    -- ── New users ─────────────────────────────────────────────
    new_users_today         INT UNSIGNED    NOT NULL    DEFAULT 0   COMMENT 'account_created_date = report_date',

    -- ── Session metrics ───────────────────────────────────────
    total_sessions_today    INT UNSIGNED    NOT NULL    DEFAULT 0,
    avg_sessions_per_dau    DECIMAL(6, 2)   NOT NULL    DEFAULT 0,

    -- ── Stickiness ────────────────────────────────────────────
    stickiness              DECIMAL(6, 4)   NOT NULL    DEFAULT 0   COMMENT 'DAU / MAU',
    wau_mau_ratio           DECIMAL(6, 4)   NOT NULL    DEFAULT 0   COMMENT 'WAU / MAU',

    -- ── Audit ─────────────────────────────────────────────────
    updated_at              DATETIME        NOT NULL    DEFAULT CURRENT_TIMESTAMP
                                                        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (report_date, platform),
    INDEX idx_report_date   (report_date),
    INDEX idx_platform      (platform)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COMMENT = 'Mart: DAU/WAU/MAU + stickiness theo ngày × platform';


-- =============================================================
-- LOAD LOGIC (TỐI ƯU HÓA CHO MYSQL BẰNG RANGE JOIN)
-- =============================================================

-- ── 1. Per platform ───────────────────────────────────────────
REPLACE INTO mart_dau_mau (
    report_date, platform,
    dau, wau, mau,
    new_users_today,
    total_sessions_today, avg_sessions_per_dau,
    stickiness, wau_mau_ratio
)
WITH
-- BƯỚC 1: Rút gọn tối đa dữ liệu. Mỗi user chỉ còn 1 dòng/ngày
daily_user_active AS (
    SELECT DISTINCT
        fe.local_event_date                 AS activity_date,
        fe.user_id,
        COALESCE(dd.platform, 'unknown')    AS platform
    FROM fact_events fe
    LEFT JOIN dim_device dd ON dd.device_id = fe.device_id
),

-- BƯỚC 2: Tạo trục ngày báo cáo chuẩn
date_spine AS (
    SELECT DISTINCT activity_date AS report_date, platform
    FROM daily_user_active
),

-- BƯỚC 3: Tuyệt kỹ Range Join (Gom WAU, MAU, DAU bằng 1 lần quét)
rolling_counts AS (
    SELECT
        ds.report_date,
        ds.platform,
        -- DAU: Chỉ đếm user có activity_date đúng bằng ngày báo cáo
        COUNT(DISTINCT CASE WHEN dua.activity_date = ds.report_date THEN dua.user_id END) AS dau,
        -- WAU: Đếm user có activity trong 7 ngày qua
        COUNT(DISTINCT CASE WHEN dua.activity_date >= DATE_SUB(ds.report_date, INTERVAL 6 DAY) THEN dua.user_id END) AS wau,
        -- MAU: Toàn bộ user lấy được từ lệnh JOIN 30 ngày bên dưới
        COUNT(DISTINCT dua.user_id) AS mau
    FROM date_spine ds
    -- JOIN dữ liệu của 30 ngày đổ lại đây cho mỗi ngày báo cáo
    JOIN daily_user_active dua
      ON dua.platform = ds.platform
     AND dua.activity_date BETWEEN DATE_SUB(ds.report_date, INTERVAL 29 DAY) AND ds.report_date
    GROUP BY ds.report_date, ds.platform
),

-- Các chỉ số Session và New User tách riêng cho nhẹ
daily_stats AS (
    SELECT
        fe.local_event_date                 AS report_date,
        COALESCE(dd.platform, 'unknown')    AS platform,
        COUNT(DISTINCT fe.session_id)       AS total_sessions
    FROM fact_events fe
    LEFT JOIN dim_device dd ON dd.device_id = fe.device_id
    GROUP BY fe.local_event_date, COALESCE(dd.platform, 'unknown')
),
new_users AS (
    SELECT
        du.account_created_date             AS report_date,
        COALESCE(dd.platform, 'unknown')    AS platform,
        COUNT(DISTINCT du.user_id)          AS new_users_today
    FROM dim_users du
    LEFT JOIN fact_events fe ON fe.user_id = du.user_id AND fe.event_name = 'account_created'
    LEFT JOIN dim_device dd ON dd.device_id = fe.device_id
    GROUP BY du.account_created_date, COALESCE(dd.platform, 'unknown')
)

SELECT
    rc.report_date,
    rc.platform,
    rc.dau, rc.wau, rc.mau,
    COALESCE(nu.new_users_today, 0),
    COALESCE(ds.total_sessions, 0),

    CASE WHEN rc.dau > 0 THEN ROUND(COALESCE(ds.total_sessions, 0) / rc.dau, 2) ELSE 0 END AS avg_sessions_per_dau,
    CASE WHEN rc.mau > 0 THEN ROUND(rc.dau / rc.mau, 4) ELSE 0 END AS stickiness,
    CASE WHEN rc.mau > 0 THEN ROUND(rc.wau / rc.mau, 4) ELSE 0 END AS wau_mau_ratio

FROM rolling_counts rc
LEFT JOIN daily_stats ds ON ds.report_date = rc.report_date AND ds.platform = rc.platform
LEFT JOIN new_users nu ON nu.report_date = rc.report_date AND nu.platform = rc.platform;


-- ── 2. platform = 'all' ───────────────────────────────────────
REPLACE INTO mart_dau_mau (
    report_date, platform,
    dau, wau, mau,
    new_users_today,
    total_sessions_today, avg_sessions_per_dau,
    stickiness, wau_mau_ratio
)
WITH
daily_user_active_all AS (
    SELECT DISTINCT local_event_date AS activity_date, user_id
    FROM fact_events
),
date_spine_all AS (
    SELECT DISTINCT activity_date AS report_date
    FROM daily_user_active_all
),
rolling_counts_all AS (
    SELECT
        ds.report_date,
        COUNT(DISTINCT CASE WHEN dua.activity_date = ds.report_date THEN dua.user_id END) AS dau,
        COUNT(DISTINCT CASE WHEN dua.activity_date >= DATE_SUB(ds.report_date, INTERVAL 6 DAY) THEN dua.user_id END) AS wau,
        COUNT(DISTINCT dua.user_id) AS mau
    FROM date_spine_all ds
    JOIN daily_user_active_all dua
      ON dua.activity_date BETWEEN DATE_SUB(ds.report_date, INTERVAL 29 DAY) AND ds.report_date
    GROUP BY ds.report_date
),
daily_stats_all AS (
    SELECT local_event_date AS report_date, COUNT(DISTINCT session_id) AS total_sessions
    FROM fact_events
    GROUP BY local_event_date
),
new_users_all AS (
    SELECT account_created_date AS report_date, COUNT(DISTINCT user_id) AS new_users_today
    FROM dim_users
    GROUP BY account_created_date
)

SELECT
    rc.report_date,
    'all' AS platform,
    rc.dau, rc.wau, rc.mau,
    COALESCE(nu.new_users_today, 0),
    COALESCE(ds.total_sessions, 0),

    CASE WHEN rc.dau > 0 THEN ROUND(COALESCE(ds.total_sessions, 0) / rc.dau, 2) ELSE 0 END AS avg_sessions_per_dau,
    CASE WHEN rc.mau > 0 THEN ROUND(rc.dau / rc.mau, 4) ELSE 0 END AS stickiness,
    CASE WHEN rc.mau > 0 THEN ROUND(rc.wau / rc.mau, 4) ELSE 0 END AS wau_mau_ratio

FROM rolling_counts_all rc
LEFT JOIN daily_stats_all ds ON ds.report_date = rc.report_date
LEFT JOIN new_users_all nu ON nu.report_date = rc.report_date;