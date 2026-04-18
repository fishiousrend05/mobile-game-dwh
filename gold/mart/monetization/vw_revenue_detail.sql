-- =============================================================
-- gold/mart/monetization/vw_revenue_detail.sql
-- Revenue breakdown với rolling totals — dùng cho Tableau
-- time-series + drill-down theo product/channel.
--
-- Nguồn: mart_revenue_daily + mart_arpu (period_type = 'daily')
-- Mục đích:
--   - Trend doanh thu hàng ngày với 7-day rolling average
--   - Drill-down: tổng → product → channel → store
--   - So sánh ARPU vs ARPPU trên cùng trục
-- =============================================================
 USE game_gold;

CREATE OR REPLACE VIEW vw_revenue_detail AS
WITH

-- Rolling 7-day revenue total (dùng subquery vì MySQL view
-- không hỗ trợ window function trực tiếp trong một số version)
daily_totals AS (
    SELECT
        revenue_date,
        SUM(total_revenue_usd)      AS day_revenue,
        SUM(transaction_count)      AS day_transactions,
        SUM(unique_buyers)          AS day_buyers
    FROM mart_revenue_daily
    GROUP BY revenue_date
)

SELECT
    rd.revenue_date,
    rd.product_id,
    rd.acquisition_channel,
    rd.store,

    -- ── Revenue ───────────────────────────────────────────────
    rd.total_revenue_usd,
    rd.transaction_count,
    rd.unique_buyers,
    rd.new_buyer_count,
    rd.returning_buyer_count,
    rd.avg_revenue_per_txn,

    -- ── Day totals (dùng cho % contribution) ─────────────────
    dt.day_revenue                              AS total_revenue_that_day,
    dt.day_transactions                         AS total_transactions_that_day,

    -- Product revenue share trong ngày (cho Tableau pie/bar %)
    CASE WHEN dt.day_revenue > 0
         THEN ROUND(rd.total_revenue_usd / dt.day_revenue, 4)
         ELSE 0
    END                                         AS revenue_share_of_day,

    -- ── ARPU / ARPPU (từ mart_arpu daily) ────────────────────
    ma.arpu,
    ma.arppu,
    ma.paying_user_rate,
    ma.total_active_users,
    ma.total_paying_users,

    -- ── 7-day rolling revenue (subquery per row) ──────────────
    -- Dùng subquery thay vì window function để tương thích
    -- với MySQL View limitation
    (
        SELECT SUM(d2.day_revenue)
        FROM daily_totals d2
        WHERE d2.revenue_date BETWEEN
              DATE_SUB(rd.revenue_date, INTERVAL 6 DAY)
              AND rd.revenue_date
    )                                           AS rolling_7d_revenue,

    rd.updated_at

FROM mart_revenue_daily rd
LEFT JOIN daily_totals dt
       ON dt.revenue_date = rd.revenue_date
LEFT JOIN mart_arpu ma
       ON ma.period_start = rd.revenue_date
      AND ma.period_type  = 'daily'
;