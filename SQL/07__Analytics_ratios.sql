-- ============================================================
-- Chapter 7 - analytics ratios
--
-- Every ratio is calculated for every company year. Nothing is
-- suppressed, so the numbers can be inspected and explained
-- rather than hidden.
--
-- Equity denominated ratios need care in this peer group. Home
-- Depot's share buybacks pushed book equity negative in FY2019
-- and FY2021, which inverts the sign of ROE: FY2019 net income
-- was positive 11.2bn but ROE reads negative 361%. No company
-- here reported a loss in FY2019-2025, so any negative ROE in
-- this dataset comes from the denominator, not from a bad year.
--
-- Asset denominated metrics (roa_pct, liabilities_to_assets_pct)
-- work for every company in every year and are used for
-- cross company comparison. Equity ratios are kept for single
-- company views, with flags so they can be annotated.
-- ============================================================

USE RetailFinancials;
GO

-- calculating liquidity, profitability, leverage, efficiency and growth ratios

CREATE OR ALTER VIEW analytics.financial_ratios AS
SELECT
    company,
    ticker,
    business_model,
    fiscal_year,
    fiscal_year_end,
    period_end,
    revenue,
    net_income,
    assets,
    equity,
    inventory,
    assets_current,
    liabilities,
    liabilities_current,
    cogs,
    minority_interest,
    avg_assets,
    avg_equity,
    avg_inventory,

    -- liquidity, both sides measured on the same date
    CAST(ROUND(assets_current / NULLIF(liabilities_current, 0), 2) AS DECIMAL(12,2)) AS current_ratio,
    CAST(ROUND((assets_current - inventory) / NULLIF(liabilities_current, 0), 2) AS DECIMAL(12,2)) AS quick_ratio,

    -- profitability, both sides are full year flows
    CAST(ROUND((revenue - cogs) * 100.0 / NULLIF(revenue, 0), 2) AS DECIMAL(12,2)) AS gross_margin_pct,
    CAST(ROUND(net_income * 100.0 / NULLIF(revenue, 0), 2) AS DECIMAL(12,2)) AS net_margin_pct,

    -- primary return metric, comparable across all companies and years
    CAST(ROUND(net_income * 100.0 / NULLIF(avg_assets, 0), 2) AS DECIMAL(12,2)) AS roa_pct,

    -- primary leverage metrics, measured against assets
    CAST(ROUND(liabilities * 100.0 / NULLIF(assets, 0), 2) AS DECIMAL(12,2)) AS liabilities_to_assets_pct,
    CAST(ROUND(equity * 100.0 / NULLIF(assets, 0), 2) AS DECIMAL(12,2)) AS equity_ratio_pct,

    -- ROE on average equity, the textbook method
    CAST(ROUND(net_income * 100.0 / NULLIF(avg_equity, 0), 2) AS DECIMAL(12,2)) AS roe_avg_equity_pct,

    -- ROE on ending equity, the method most data providers use
    CAST(ROUND(net_income * 100.0 / NULLIF(equity, 0), 2) AS DECIMAL(12,2)) AS roe_ending_equity_pct,

    -- total liabilities over equity, not interest bearing debt over equity
    CAST(ROUND(liabilities / NULLIF(equity, 0), 2) AS DECIMAL(12,2)) AS liabilities_to_equity,

    -- efficiency, a full year flow against an average balance
    CAST(ROUND(cogs / NULLIF(avg_inventory, 0), 2) AS DECIMAL(12,2)) AS inventory_turnover,
    CAST(ROUND(365 / NULLIF(cogs / NULLIF(avg_inventory, 0), 0), 1) AS DECIMAL(12,1)) AS days_inventory_outstanding,
    CAST(ROUND(revenue / NULLIF(avg_assets, 0), 2) AS DECIMAL(12,2)) AS asset_turnover,

    -- growth
    CAST(ROUND((revenue - prior_revenue) * 100.0 / NULLIF(prior_revenue, 0), 2) AS DECIMAL(12,2)) AS revenue_growth_pct,
    CAST(ROUND((net_income - prior_net_income) * 100.0 / NULLIF(prior_net_income, 0), 2) AS DECIMAL(12,2)) AS net_income_growth_pct,

    -- equity is negative, so equity ratios carry an inverted sign
    CASE WHEN equity <= 0 THEN 1 ELSE 0 END AS equity_negative,

    -- the equity average is unreliable, either negative or a near zero
    -- denominator caused by equity changing sign between years
    CASE
        WHEN avg_equity <= 0 THEN 1
        WHEN equity > 0 AND avg_equity < equity / 2 THEN 1
        ELSE 0
    END AS equity_average_unstable,

    -- equity is positive but under 10 percent of assets, so ratios are inflated
    CASE WHEN equity > 0 AND equity * 100.0 / NULLIF(assets, 0) < 10 THEN 1 ELSE 0 END AS equity_thin,

    -- single flag for the dashboard: equity ratios are not comparable here
    CASE
        WHEN equity <= 0
            OR avg_equity <= 0
            OR equity * 100.0 / NULLIF(assets, 0) < 10
        THEN 0 ELSE 1
    END AS equity_ratios_comparable,

    -- confirms no company reported a loss, so negative equity ratios
    -- can only come from the denominator
    CASE WHEN net_income < 0 THEN 1 ELSE 0 END AS reported_net_loss,

    revenue_source,
    net_income_source,
    liabilities_source,
    restated_figures
FROM analytics.financials_annual;
GO

-- adding year on year change for each headline ratio

CREATE OR ALTER VIEW analytics.ratio_trends AS
SELECT
    company,
    ticker,
    business_model,
    fiscal_year,

    current_ratio,
    net_margin_pct,
    roa_pct,
    liabilities_to_assets_pct,
    inventory_turnover,
    revenue_growth_pct,
    equity_ratios_comparable,

    CAST(current_ratio - LAG(current_ratio) OVER (PARTITION BY company ORDER BY fiscal_year) AS DECIMAL(12,2)) AS current_ratio_change,
    CAST(net_margin_pct - LAG(net_margin_pct) OVER (PARTITION BY company ORDER BY fiscal_year) AS DECIMAL(12,2)) AS net_margin_change,
    CAST(roa_pct - LAG(roa_pct) OVER (PARTITION BY company ORDER BY fiscal_year) AS DECIMAL(12,2)) AS roa_change,
    CAST(liabilities_to_assets_pct - LAG(liabilities_to_assets_pct) OVER (PARTITION BY company ORDER BY fiscal_year) AS DECIMAL(12,2)) AS liabilities_to_assets_change,
    CAST(inventory_turnover - LAG(inventory_turnover) OVER (PARTITION BY company ORDER BY fiscal_year) AS DECIMAL(12,2)) AS inventory_turnover_change
FROM analytics.financial_ratios;
GO

-- confirming no company reported a loss in the analysis window, so any
-- negative equity ratio comes from the denominator and not from a bad year

SELECT
    COUNT(*) AS total_company_years,
    SUM(reported_net_loss) AS years_with_a_loss
FROM analytics.financial_ratios
WHERE fiscal_year BETWEEN 2019 AND 2025;

-- the metrics that are safe to compare across companies, latest year

SELECT
    company,
    fiscal_year,
    current_ratio,
    quick_ratio,
    gross_margin_pct,
    net_margin_pct,
    roa_pct,
    liabilities_to_assets_pct,
    inventory_turnover,
    revenue_growth_pct
FROM analytics.financial_ratios
WHERE fiscal_year = 2025
ORDER BY roa_pct DESC;

-- showing every case where equity ratios are not comparable, and why

SELECT
    company,
    fiscal_year,
    net_income,
    equity,
    avg_equity,
    equity_ratio_pct,
    roe_avg_equity_pct,
    roe_ending_equity_pct,
    liabilities_to_equity,
    equity_negative,
    equity_average_unstable,
    equity_thin,
    equity_ratios_comparable
FROM analytics.financial_ratios
WHERE equity_ratios_comparable = 0
    AND fiscal_year BETWEEN 2019 AND 2025
ORDER BY company, fiscal_year;

-- inventory turnover across the window, the retail specific metric

SELECT
    company,
    business_model,
    fiscal_year,
    inventory_turnover,
    days_inventory_outstanding
FROM analytics.financial_ratios
WHERE fiscal_year BETWEEN 2019 AND 2025
ORDER BY company, fiscal_year;

-- checking the comparable metrics stay in a believable range

SELECT
    company,
    fiscal_year,
    current_ratio,
    gross_margin_pct,
    net_margin_pct,
    roa_pct,
    liabilities_to_assets_pct,
    inventory_turnover
FROM analytics.financial_ratios
WHERE fiscal_year BETWEEN 2019 AND 2025
    AND (current_ratio NOT BETWEEN 0.3 AND 3
        OR gross_margin_pct NOT BETWEEN 0 AND 60
        OR net_margin_pct NOT BETWEEN -20 AND 20
        OR roa_pct NOT BETWEEN -20 AND 30
        OR liabilities_to_assets_pct NOT BETWEEN 20 AND 130
        OR inventory_turnover NOT BETWEEN 3 AND 15)
ORDER BY company, fiscal_year;