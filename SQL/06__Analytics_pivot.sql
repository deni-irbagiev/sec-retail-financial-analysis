-- ============================================================
-- Chapter 6 - analytics annual base
--
-- Adds prior year values and average balances across the full
-- filing history. No window is applied here.
--
-- Averages and year on year changes need the year before the
-- first displayed year, so all calculation happens across every
-- year available. The FY2019-2025 window is a display decision
-- and is applied in the reporting layer in Chapter 9.
-- ============================================================

USE RetailFinancials;
GO

-- adding prior year values and average balances

CREATE OR ALTER VIEW analytics.financials_annual AS
WITH with_prior AS (
    SELECT
        company,
        ticker,
        business_model,
        fiscal_year_end,
        fiscal_year,
        period_end,
        assets,
        assets_current,
        liabilities,
        liabilities_current,
        equity,
        minority_interest,
        inventory,
        revenue,
        cogs,
        net_income,
        revenue_source,
        net_income_source,
        liabilities_source,
        restated_figures,

        LAG(fiscal_year) OVER (PARTITION BY company ORDER BY fiscal_year) AS prior_fiscal_year,
        LAG(revenue) OVER (PARTITION BY company ORDER BY fiscal_year) AS prior_revenue,
        LAG(net_income) OVER (PARTITION BY company ORDER BY fiscal_year) AS prior_net_income,
        LAG(assets) OVER (PARTITION BY company ORDER BY fiscal_year) AS prior_assets,
        LAG(equity) OVER (PARTITION BY company ORDER BY fiscal_year) AS prior_equity,
        LAG(inventory) OVER (PARTITION BY company ORDER BY fiscal_year) AS prior_inventory
    FROM cleaned.financials_normalized
)
SELECT
    company,
    ticker,
    business_model,
    fiscal_year_end,
    fiscal_year,
    period_end,

    assets,
    assets_current,
    liabilities,
    liabilities_current,
    equity,
    minority_interest,
    inventory,
    revenue,
    cogs,
    net_income,
    prior_revenue,
    prior_net_income,

    -- average balances, used where a full-year flow is compared to a balance
    CAST((assets + prior_assets) / 2 AS DECIMAL(20,2)) AS avg_assets,
    CAST((equity + prior_equity) / 2 AS DECIMAL(20,2)) AS avg_equity,
    CAST((inventory + prior_inventory) / 2 AS DECIMAL(20,2)) AS avg_inventory,

    -- flags for cases the ratios have to treat carefully
    CASE WHEN equity <= 0 OR prior_equity <= 0 THEN 1 ELSE 0 END AS avg_equity_affected_by_negative,
    CASE WHEN prior_fiscal_year = fiscal_year - 1 THEN 1 ELSE 0 END AS prior_year_is_consecutive,

    revenue_source,
    net_income_source,
    liabilities_source,
    restated_figures
FROM with_prior;
GO

-- checking the window and row count

SELECT
    company,
    COUNT(*) AS years,
    MIN(fiscal_year) AS from_fy,
    MAX(fiscal_year) AS to_fy
FROM analytics.financials_annual
GROUP BY company
ORDER BY company;

-- confirming every row after the first has a genuine prior year

SELECT
    company,
    fiscal_year,
    prior_year_is_consecutive
FROM analytics.financials_annual
WHERE prior_year_is_consecutive = 0
    AND prior_revenue IS NOT NULL
ORDER BY company, fiscal_year;

-- checking the average balances landed

SELECT
    company,
    fiscal_year,
    assets,
    avg_assets,
    equity,
    avg_equity,
    inventory,
    avg_inventory,
    avg_equity_affected_by_negative
FROM analytics.financials_annual
WHERE company = 'Home Depot'
ORDER BY fiscal_year;

-- checking the full history is present, with the analysis window inside it

SELECT
    company,
    COUNT(*) AS total_years,
    MIN(fiscal_year) AS earliest_fy,
    MAX(fiscal_year) AS latest_fy,
    SUM(CASE WHEN fiscal_year BETWEEN 2019 AND 2025 THEN 1 ELSE 0 END) AS years_in_window
FROM analytics.financials_annual
GROUP BY company
ORDER BY company;