-- gold/analytics/dau_mau.sql
-- DAU / MAU trend với % thay đổi WoW và MoM.
--
-- Khác với mart_dau_mau:
--   mart_dau_mau lưu snapshot từng ngày.
--   Query này thêm WoW (so ngày tương ứng tuần trước) và
--   MoM (so ngày tương ứng tháng trước) để thấy trend tăng/giảm.
--
-- Dùng cho: Power BI Custom SQL hoặc chạy tay phân tích trend.
-- =============================================================
Use game_gold;

WITH

dau_series AS (
    SELECT
        report_date,
        dau,
        mau,
        stickiness,
        new_users_today,
        total_sessions_today
    FROM mart_dau_mau
    WHERE platform = 'all'
),

-- Gắn giá trị 7 ngày trước và 30 ngày trước bằng self-join
-- LAG() không đảm bảo đúng nếu có ngày missing → dùng join trên date
with_comparison AS (
    SELECT
        t.report_date,
        t.dau,
        t.mau,
        t.stickiness,
        t.new_users_today,
        t.total_sessions_today,

        -- WoW: so với cùng ngày tuần trước
        prev7.dau                                       AS dau_7d_ago,
        prev7.mau                                       AS mau_7d_ago,

        -- MoM: so với cùng ngày tháng trước
        prev30.dau                                      AS dau_30d_ago,
        prev30.mau                                      AS mau_30d_ago

    FROM dau_series t
    LEFT JOIN dau_series prev7
           ON prev7.report_date = DATE_SUB(t.report_date, INTERVAL 7 DAY)
    LEFT JOIN dau_series prev30
           ON prev30.report_date = DATE_SUB(t.report_date, INTERVAL 30 DAY)
)

SELECT
    report_date,
    dau,
    mau,
    new_users_today,
    total_sessions_today,
    ROUND(stickiness * 100, 2)                           AS stickiness_pct,

    -- ── WoW change ────────────────────────────────────────────
    dau_7d_ago,
    CASE WHEN dau_7d_ago > 0
         THEN ROUND((CAST(dau AS SIGNED) - CAST(dau_7d_ago AS SIGNED)) / dau_7d_ago * 100, 2)
         ELSE NULL
    END                                                  AS dau_wow_pct,

    -- ── MoM change ────────────────────────────────────────────
    dau_30d_ago,
    CASE WHEN dau_30d_ago > 0
         THEN ROUND((CAST(dau AS SIGNED) - CAST(dau_30d_ago AS SIGNED)) / dau_30d_ago * 100, 2)
         ELSE NULL
    END                                                  AS dau_mom_pct,

    -- MAU WoW (MAU thay đổi chậm hơn DAU — useful để track growth)
    CASE WHEN mau_7d_ago > 0
         THEN ROUND((CAST(mau AS SIGNED) - CAST(mau_7d_ago AS SIGNED)) / mau_7d_ago * 100, 2)
         ELSE NULL
    END                                                  AS mau_wow_pct,

    -- ── Signal flags ──────────────────────────────────────────
    -- Dùng để filter ngày cần điều tra ngay
    CASE
        WHEN dau_7d_ago > 0
         AND (CAST(dau AS SIGNED) - CAST(dau_7d_ago AS SIGNED)) / dau_7d_ago < -0.20   THEN 'drop_alert'    -- DAU giảm >20% so tuần trước
        WHEN dau_7d_ago > 0
         AND (CAST(dau AS SIGNED) - CAST(dau_7d_ago AS SIGNED)) / dau_7d_ago >  0.30   THEN 'spike'         -- DAU tăng >30%
        ELSE                                                  'normal'
    END                                                  AS dau_signal

FROM with_comparison
ORDER BY report_date DESC;