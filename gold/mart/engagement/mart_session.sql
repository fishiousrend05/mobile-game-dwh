-- =============================================================
-- gold/mart/engagement/mart_session.sql
-- Session-level engagement metrics theo ngày.
--
-- Câu hỏi business trả lời:
--   "Session trung bình hôm nay kéo dài bao lâu?"
--   "User trung bình chơi mấy session mỗi ngày?"
--   "Có bao nhiêu user chỉ chơi 1 session rồi bỏ (single-session users)?"
--
-- Grain: 1 row per (session_date, platform)
--   platform = 'iOS' | 'Android' | 'all'
--
-- Cách tính session duration:
--   MAX(server_timestamp_utc) - MIN(server_timestamp_utc) trong cùng session_id.
--   Session dưới 10 giây bị loại — thường là crash hoặc test event.
--
-- Source: fact_events, dim_device
-- Load: REPLACE INTO
-- Schedule: sau load_gold.py
-- =============================================================
USE game_gold;

CREATE TABLE IF NOT EXISTS mart_session (

    session_date            DATE            NOT NULL,
    platform                VARCHAR(10)     NOT NULL    COMMENT 'iOS | Android | all',

    -- ── Volume ────────────────────────────────────────────────
    total_sessions          INT UNSIGNED    NOT NULL    DEFAULT 0,
    total_active_users      INT UNSIGNED    NOT NULL    DEFAULT 0,

    -- ── Duration (giây) ───────────────────────────────────────
    avg_session_duration_sec    INT UNSIGNED    NOT NULL    DEFAULT 0,
    median_session_duration_sec INT UNSIGNED    NOT NULL    DEFAULT 0,
    p90_session_duration_sec    INT UNSIGNED    NOT NULL    DEFAULT 0   COMMENT '90th percentile',

    -- ── Sessions per user ─────────────────────────────────────
    avg_sessions_per_user   DECIMAL(6, 2)   NOT NULL    DEFAULT 0,
    single_session_users    INT UNSIGNED    NOT NULL    DEFAULT 0   COMMENT 'user chỉ có 1 session trong ngày',
    multi_session_users     INT UNSIGNED    NOT NULL    DEFAULT 0,

    -- ── Audit ─────────────────────────────────────────────────
    updated_at              DATETIME        NOT NULL    DEFAULT CURRENT_TIMESTAMP
                                                        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (session_date, platform),
    INDEX idx_session_date  (session_date),
    INDEX idx_platform      (platform)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COMMENT = 'Mart: session engagement metrics theo ngày × platform';


-- =============================================================
-- LOAD LOGIC (Đã fix lỗi PERCENTILE_CONT cho MySQL)
-- =============================================================

-- ── Per platform ──────────────────────────────────────────────
REPLACE INTO mart_session (
    session_date, platform,
    total_sessions, total_active_users,
    avg_session_duration_sec,
    median_session_duration_sec,
    p90_session_duration_sec,
    avg_sessions_per_user,
    single_session_users, multi_session_users
)
WITH
-- 1. Tính duration từng session
session_durations AS (
    SELECT
        fe.session_id,
        fe.user_id,
        fe.local_event_date                             AS session_date,
        COALESCE(dd.platform, 'unknown')                AS platform,
        TIMESTAMPDIFF(
            SECOND,
            MIN(fe.server_timestamp_utc),
            MAX(fe.server_timestamp_utc)
        )                                               AS duration_sec
    FROM fact_events fe
    LEFT JOIN dim_device dd ON dd.device_id = fe.device_id
    GROUP BY fe.session_id, fe.user_id, fe.local_event_date, COALESCE(dd.platform, 'unknown')
    HAVING duration_sec >= 10
),
-- 2. Xếp hạng phần trăm (Percentile) cho MySQL
session_percentiles AS (
    SELECT
        session_date,
        platform,
        duration_sec,
        PERCENT_RANK() OVER (PARTITION BY session_date, platform ORDER BY duration_sec) AS pct
    FROM session_durations
),
-- 3. Số session mỗi user
user_session_counts AS (
    SELECT
        user_id, session_date, platform,
        COUNT(DISTINCT session_id) AS session_count
    FROM session_durations
    GROUP BY user_id, session_date, platform
),
-- 4. Aggregate chính (Dùng Subquery móc % rank ra)
session_agg AS (
    SELECT
        sd.session_date,
        sd.platform,
        COUNT(DISTINCT sd.session_id)          AS total_sessions,
        COUNT(DISTINCT sd.user_id)             AS total_active_users,
        AVG(sd.duration_sec)                   AS avg_duration,
        (SELECT MIN(duration_sec) FROM session_percentiles sp WHERE sp.session_date = sd.session_date AND sp.platform = sd.platform AND sp.pct >= 0.5) AS median_duration,
        (SELECT MIN(duration_sec) FROM session_percentiles sp WHERE sp.session_date = sd.session_date AND sp.platform = sd.platform AND sp.pct >= 0.9) AS p90_duration
    FROM session_durations sd
    GROUP BY sd.session_date, sd.platform
),
-- 5. User type (Single vs Multi)
session_type AS (
    SELECT
        session_date,
        platform,
        SUM(CASE WHEN session_count = 1 THEN 1 ELSE 0 END)  AS single_session_users,
        SUM(CASE WHEN session_count > 1 THEN 1 ELSE 0 END)  AS multi_session_users,
        AVG(session_count)                                  AS avg_sessions_per_user
    FROM user_session_counts
    GROUP BY session_date, platform
)
SELECT
    sa.session_date,
    sa.platform,
    sa.total_sessions,
    sa.total_active_users,
    ROUND(sa.avg_duration)                  AS avg_session_duration_sec,
    COALESCE(ROUND(sa.median_duration), 0)  AS median_session_duration_sec,
    COALESCE(ROUND(sa.p90_duration), 0)     AS p90_session_duration_sec,
    ROUND(st.avg_sessions_per_user, 2)      AS avg_sessions_per_user,
    COALESCE(st.single_session_users, 0)    AS single_session_users,
    COALESCE(st.multi_session_users, 0)     AS multi_session_users
FROM session_agg sa
LEFT JOIN session_type st
       ON st.session_date = sa.session_date
      AND st.platform     = sa.platform;


-- ── platform = 'all' ──────────────────────────────────────────
REPLACE INTO mart_session (
    session_date, platform,
    total_sessions, total_active_users,
    avg_session_duration_sec,
    median_session_duration_sec,
    p90_session_duration_sec,
    avg_sessions_per_user,
    single_session_users, multi_session_users
)
WITH
all_session_durations AS (
    SELECT
        session_id,
        user_id,
        local_event_date                AS session_date,
        TIMESTAMPDIFF(
            SECOND,
            MIN(server_timestamp_utc),
            MAX(server_timestamp_utc)
        )                               AS duration_sec
    FROM fact_events
    GROUP BY session_id, user_id, local_event_date
    HAVING duration_sec >= 10
),
all_session_percentiles AS (
    SELECT
        session_date,
        duration_sec,
        PERCENT_RANK() OVER (PARTITION BY session_date ORDER BY duration_sec) AS pct
    FROM all_session_durations
),
all_user_counts AS (
    SELECT
        user_id, session_date,
        COUNT(DISTINCT session_id)      AS session_count
    FROM all_session_durations
    GROUP BY user_id, session_date
),
all_session_agg AS (
    SELECT
        session_date,
        COUNT(DISTINCT session_id)      AS total_sessions,
        COUNT(DISTINCT user_id)         AS total_active_users,
        AVG(duration_sec)               AS avg_duration,
        (SELECT MIN(duration_sec) FROM all_session_percentiles sp WHERE sp.session_date = asd.session_date AND sp.pct >= 0.5) AS median_duration,
        (SELECT MIN(duration_sec) FROM all_session_percentiles sp WHERE sp.session_date = asd.session_date AND sp.pct >= 0.9) AS p90_duration
    FROM all_session_durations asd
    GROUP BY session_date
),
all_session_type AS (
    SELECT
        session_date,
        SUM(CASE WHEN session_count = 1 THEN 1 ELSE 0 END)  AS single_session_users,
        SUM(CASE WHEN session_count > 1 THEN 1 ELSE 0 END)  AS multi_session_users,
        AVG(session_count)                                  AS avg_sessions_per_user
    FROM all_user_counts
    GROUP BY session_date
)
SELECT
    sa.session_date,
    'all'                                   AS platform,
    sa.total_sessions,
    sa.total_active_users,
    ROUND(sa.avg_duration)                  AS avg_session_duration_sec,
    COALESCE(ROUND(sa.median_duration), 0)  AS median_session_duration_sec,
    COALESCE(ROUND(sa.p90_duration), 0)     AS p90_session_duration_sec,
    ROUND(st.avg_sessions_per_user, 2)      AS avg_sessions_per_user,
    COALESCE(st.single_session_users, 0)    AS single_session_users,
    COALESCE(st.multi_session_users, 0)     AS multi_session_users
FROM all_session_agg sa
LEFT JOIN all_session_type st
       ON st.session_date = sa.session_date;
