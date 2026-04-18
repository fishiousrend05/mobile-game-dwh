-- =============================================================
-- gold/mart/engagement/vw_daily_engagement.sql
-- Daily engagement dashboard — join DAU/MAU với session metrics
-- thành một row duy nhất mỗi ngày cho Tableau time-series chart.
--
-- Nguồn: mart_dau_mau + mart_session (platform = 'all')
-- Mục đích:
--   - Homepage dashboard: DAU, stickiness, session duration trend
--   - Phát hiện ngày bất thường (spike/drop) nhanh
-- =============================================================
USE game_gold;

CREATE OR REPLACE VIEW vw_daily_engagement AS
SELECT
    dm.report_date,

    -- ── Active users ──────────────────────────────────────────
    dm.dau,
    dm.wau,
    dm.mau,
    dm.new_users_today,

    -- ── Stickiness ────────────────────────────────────────────
    dm.stickiness,                          -- DAU / MAU
    dm.wau_mau_ratio,
    ROUND(dm.stickiness * 100, 2)           AS stickiness_pct,  -- format cho Tableau label

    -- ── Sessions ──────────────────────────────────────────────
    dm.total_sessions_today,
    dm.avg_sessions_per_dau,
    s.avg_session_duration_sec,
    s.median_session_duration_sec,
    s.p90_session_duration_sec,
    s.single_session_users,
    s.multi_session_users,

    -- ── Derived ───────────────────────────────────────────────
    -- Tỷ lệ new user trong DAU — spike cho thấy campaign mới
    CASE WHEN dm.dau > 0
         THEN ROUND(dm.new_users_today / dm.dau, 4)
         ELSE 0
    END                                     AS new_user_ratio,

    -- Session duration bucket (dùng cho color coding trong Tableau)
    CASE
        WHEN s.avg_session_duration_sec >= 600  THEN 'high'    -- >= 10 phút
        WHEN s.avg_session_duration_sec >= 180  THEN 'medium'  -- 3-10 phút
        ELSE                                         'low'
    END                                     AS session_quality,

    dm.updated_at                           AS updated_at

FROM mart_dau_mau dm
LEFT JOIN mart_session s
       ON s.session_date = dm.report_date
      AND s.platform     = 'all'
WHERE dm.platform = 'all'
;