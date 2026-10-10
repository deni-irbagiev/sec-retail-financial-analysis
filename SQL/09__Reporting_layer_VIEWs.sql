-- ============================================================
-- Chapter 9 - reporting layer
--
-- The contract Power BI connects to. Nothing downstream should
-- reach into analytics or cleaned directly.
--
-- The FY2019-2025 window is applied here, not in analytics.
-- Analytics computes ratios and trends across the full filing
-- history, so anything needing a prior year (average equity,
-- year on year change) reaches back to FY2018 correctly. The
-- window is a display decision, not a calculation boundary.
-- ============================================================

USE RetailFinancials;
GO

-- removing views that were folded into fact_financials

DROP VIEW IF EXISTS reporting.kpi_latest_year;
DROP VIEW IF EXISTS reporting.growth_quality;
DROP VIEW IF EXISTS reporting.profitability_trend;
DROP VIEW IF EXISTS reporting.inventory_efficiency;
GO

-- company dimension

CREATE OR ALTER VIEW reporting.dim_company AS
SELECT DISTINCT
    company,
    ticker,
    business_model,
    fiscal_year_end
FROM analytics.financial_ratios;
GO

-- fiscal year dimension, giving Power BI a clean axis and an era grouping

CREATE OR ALTER VIEW reporting.dim_fiscal_year AS
SELECT DISTINCT
    fiscal_year,
    CASE
        WHEN fiscal_year = 2019 THEN 'Pre-pandemic'
        WHEN fiscal_year IN (2020, 2021) THEN 'Pandemic'
        WHEN fiscal_year IN (2022, 2023) THEN 'Inflation'
        ELSE 'Normalisation'
    END AS period_label
FROM analytics.financial_ratios
WHERE fiscal_year BETWEEN 2019 AND 2025;
GO

-- main fact view, one row per company and fiscal year
-- includes the FY2019 baseline and turnover span so Power BI needs no DAX for them

CREATE OR ALTER VIEW reporting.fact_financials AS
WITH baseline AS (
    SELECT
        company,
        MAX(CASE WHEN fiscal_year = 2019 THEN net_margin_pct END) AS net_margin_2019,
        MAX(CASE WHEN fiscal_year = 2019 THEN inventory_turnover END) AS turnover_2019,
        MAX(CASE WHEN fiscal_year = 2025 THEN inventory_turnover END) AS turnover_2025,
        MAX(CASE WHEN fiscal_year = 2019 THEN days_inventory_outstanding END) AS dio_2019,
        MAX(CASE WHEN fiscal_year = 2025 THEN days_inventory_outstanding END) AS dio_2025
    FROM analytics.financial_ratios
    GROUP BY company
)
SELECT
    r.company,
    r.fiscal_year,
    r.period_end,

    r.revenue,
    r.net_income,
    r.assets,
    r.equity,
    r.inventory,
    r.assets_current,
    r.liabilities,
    r.liabilities_current,
    r.cogs,
    r.minority_interest,
    -- average balances, so measures can use the same method as the columns
    r.avg_assets,
    r.avg_equity,
    r.avg_inventory,

    r.current_ratio,
    r.quick_ratio,
    r.gross_margin_pct,
    r.net_margin_pct,
    r.roa_pct,
    r.liabilities_to_assets_pct,
    r.equity_ratio_pct,
    r.inventory_turnover,
    r.days_inventory_outstanding,
    r.asset_turnover,
    r.revenue_growth_pct,
    r.net_income_growth_pct,

    r.roe_avg_equity_pct,
    r.roe_ending_equity_pct,
    r.liabilities_to_equity,
    r.equity_ratios_comparable,

    t.net_margin_change,
    t.roa_change,
    t.inventory_turnover_change,
    t.liabilities_to_assets_change,
    t.current_ratio_change,

    -- profitability against the FY2019 baseline
    b.net_margin_2019,
    CAST(r.net_margin_pct - b.net_margin_2019 AS DECIMAL(12,2)) AS net_margin_vs_2019,
    CASE
        WHEN r.net_margin_pct >= b.net_margin_2019 THEN 'At or above 2019'
        ELSE 'Below 2019'
    END AS versus_baseline,

    -- inventory efficiency across the window
    b.turnover_2019,
    b.turnover_2025,
    CAST(b.turnover_2025 - b.turnover_2019 AS DECIMAL(12,2)) AS turnover_change,
    CAST(b.dio_2025 - b.dio_2019 AS DECIMAL(12,1)) AS days_change,
    CASE
        WHEN b.turnover_2025 > b.turnover_2019 THEN 'Improving'
        WHEN b.turnover_2025 < b.turnover_2019 THEN 'Declining'
        ELSE 'Flat'
    END AS turnover_direction,

    -- growth quadrant
    CASE
        WHEN r.revenue_growth_pct > 0 AND t.net_margin_change >= 0 THEN 'Profitable'
        WHEN r.revenue_growth_pct > 0 AND t.net_margin_change < 0 THEN 'Growth at margin cost'
        WHEN r.revenue_growth_pct <= 0 AND t.net_margin_change >= 0 THEN 'Defending margin'
        WHEN r.revenue_growth_pct IS NULL OR t.net_margin_change IS NULL THEN 'No prior year'
        ELSE 'Losing both'
    END AS growth_quality,

    ISNULL(r.revenue_source, 'Unknown source') AS revenue_source,
    ISNULL(r.net_income_source, 'Unknown source') AS net_income_source,
    ISNULL(r.liabilities_source, 'Unknown source') AS liabilities_source
FROM analytics.financial_ratios AS r
LEFT JOIN analytics.ratio_trends AS t
    ON r.company = t.company
    AND r.fiscal_year = t.fiscal_year
JOIN baseline AS b
    ON r.company = b.company
WHERE r.fiscal_year BETWEEN 2019 AND 2025;
GO

-- financial health scorecard, the answer to question one

CREATE OR ALTER VIEW reporting.scorecard AS
WITH latest AS (
    SELECT
        company,
        business_model,
        current_ratio,
        net_margin_pct,
        roa_pct,
        liabilities_to_assets_pct,
        inventory_turnover
    FROM analytics.financial_ratios
    WHERE fiscal_year = 2025
),
ranked AS (
    SELECT
        company,
        business_model,
        RANK() OVER (ORDER BY current_ratio DESC) AS rank_liquidity,
        RANK() OVER (ORDER BY net_margin_pct DESC) AS rank_margin,
        RANK() OVER (ORDER BY roa_pct DESC) AS rank_return,
        RANK() OVER (ORDER BY liabilities_to_assets_pct ASC) AS rank_leverage,
        RANK() OVER (ORDER BY inventory_turnover DESC) AS rank_efficiency
    FROM latest
)
SELECT
    company,
    business_model,
    rank_liquidity,
    rank_margin,
    rank_return,
    rank_leverage,
    rank_efficiency,
    rank_liquidity + rank_margin + rank_return + rank_leverage + rank_efficiency AS total_score,
    RANK() OVER (ORDER BY rank_liquidity + rank_margin + rank_return + rank_leverage + rank_efficiency ASC) AS overall_rank
FROM ranked;
GO

-- risk assessment, the answer to question four

CREATE OR ALTER VIEW reporting.risk_assessment AS
WITH risk AS (
    SELECT
        company,
        business_model,
        liabilities_to_assets_pct,
        equity_ratio_pct,
        current_ratio,
        quick_ratio,
        CASE WHEN liabilities_to_assets_pct > 80 THEN 1 ELSE 0 END AS flag_high_leverage,
        CASE WHEN current_ratio < 1 THEN 1 ELSE 0 END AS flag_low_liquidity,
        CASE WHEN equity_ratio_pct < 10 THEN 1 ELSE 0 END AS flag_thin_equity
    FROM analytics.financial_ratios
    WHERE fiscal_year = 2025
)
SELECT
    company,
    business_model,
    liabilities_to_assets_pct,
    equity_ratio_pct,
    current_ratio,
    quick_ratio,
    flag_high_leverage,
    flag_low_liquidity,
    flag_thin_equity,
    flag_high_leverage + flag_low_liquidity + flag_thin_equity AS risk_flags,
    CASE
        WHEN flag_high_leverage + flag_low_liquidity + flag_thin_equity >= 2 THEN 'High'
        WHEN flag_high_leverage + flag_low_liquidity + flag_thin_equity = 1 THEN 'Moderate'
        ELSE 'Low'
    END AS risk_level
FROM risk;
GO

-- data quality summary, so the methodology can be shown on the dashboard

CREATE OR ALTER VIEW reporting.data_quality AS
SELECT
    (SELECT COUNT(*) FROM src.raw_financials) AS source_rows,
    (SELECT COUNT(DISTINCT tag) FROM src.raw_financials) AS source_tags,
    (SELECT COUNT(*) FROM cleaned.financials_deduped) AS rows_after_dedupe,
    (SELECT COUNT(*) FROM analytics.financial_ratios
     WHERE fiscal_year BETWEEN 2019 AND 2025) AS company_years_analysed,
    (SELECT COUNT(*) FROM analytics.financial_ratios
     WHERE fiscal_year BETWEEN 2019 AND 2025 AND equity_ratios_comparable = 0) AS company_years_unusable_equity,
    (SELECT SUM(reported_net_loss) FROM analytics.financial_ratios
     WHERE fiscal_year BETWEEN 2019 AND 2025) AS company_years_with_a_loss,
     (SELECT SUM(restated_figures) FROM analytics.financial_ratios
     WHERE fiscal_year BETWEEN 2019 AND 2025) AS restated_figures;
GO

-- checking every reporting view returns the expected number of rows

SELECT 'dim_company' AS view_name, COUNT(*) AS row_count FROM reporting.dim_company
UNION ALL SELECT 'dim_fiscal_year', COUNT(*) FROM reporting.dim_fiscal_year
UNION ALL SELECT 'fact_financials', COUNT(*) FROM reporting.fact_financials
UNION ALL SELECT 'scorecard', COUNT(*) FROM reporting.scorecard
UNION ALL SELECT 'risk_assessment', COUNT(*) FROM reporting.risk_assessment
UNION ALL SELECT 'data_quality', COUNT(*) FROM reporting.data_quality
ORDER BY view_name;

-- confirming the fact view joins cleanly to both dimensions

SELECT COUNT(*) AS unmatched_rows
FROM reporting.fact_financials AS f
LEFT JOIN reporting.dim_company AS c
    ON f.company = c.company
LEFT JOIN reporting.dim_fiscal_year AS y
    ON f.fiscal_year = y.fiscal_year
WHERE c.company IS NULL
    OR y.fiscal_year IS NULL;

-- confirming FY2019 has a real margin change and a growth quadrant

SELECT
    company,
    fiscal_year,
    net_margin_pct,
    net_margin_change,
    growth_quality,
    net_margin_vs_2019,
    turnover_direction
FROM reporting.fact_financials
WHERE fiscal_year = 2019
ORDER BY company;

-- confirming the full pipeline funnel, source through to analysis

SELECT
    source_rows,
    source_tags,
    rows_after_dedupe,
    company_years_analysed,
    company_years_unusable_equity,
    company_years_with_a_loss,
    restated_figures
FROM reporting.data_quality;
