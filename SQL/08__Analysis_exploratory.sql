-- ============================================================
-- Chapter 8 - analysis
--
-- Answers the five business questions. Read only, exploratory.
-- Findings here decide what Chapter 9 exposes to Power BI.
--
-- Cross company comparisons use asset denominated metrics, since
-- equity ratios are not comparable for Home Depot.
-- ============================================================

USE RetailFinancials;
GO

/*
Q1 — Which retailer is in the strongest financial position today?
-- ranking each company on five metrics for the latest year, then
-- summing the ranks into a single score
*/

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
        current_ratio,
        RANK() OVER (ORDER BY current_ratio DESC) AS rank_liquidity,
        net_margin_pct,
        RANK() OVER (ORDER BY net_margin_pct DESC) AS rank_margin,
        roa_pct,
        RANK() OVER (ORDER BY roa_pct DESC) AS rank_return,
        liabilities_to_assets_pct,
        RANK() OVER (ORDER BY liabilities_to_assets_pct ASC) AS rank_leverage,
        inventory_turnover,
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
FROM ranked
ORDER BY total_score;

-- Q2 - how has profitability moved since 2019
-- margins by company and year across the window

SELECT
    company,
    fiscal_year,
    gross_margin_pct,
    net_margin_pct,
    roa_pct
FROM analytics.financial_ratios
WHERE fiscal_year BETWEEN 2019 AND 2025
ORDER BY company, fiscal_year;

-- comparing the latest year to the FY2019 baseline, and finding each
-- company's worst year for net margin within the window

WITH windowed AS (
    SELECT
        company,
        fiscal_year,
        net_margin_pct
    FROM analytics.financial_ratios
    WHERE fiscal_year BETWEEN 2019 AND 2025
),
baseline AS (
    SELECT
        company,
        MAX(CASE WHEN fiscal_year = 2019 THEN net_margin_pct END) AS net_margin_2019,
        MAX(CASE WHEN fiscal_year = 2025 THEN net_margin_pct END) AS net_margin_2025,
        MIN(net_margin_pct) AS worst_net_margin,
        MAX(net_margin_pct) AS best_net_margin
    FROM windowed
    GROUP BY company
),
worst_year AS (
    SELECT
        w.company,
        MIN(w.fiscal_year) AS worst_year
    FROM windowed AS w
    JOIN baseline AS b
        ON w.company = b.company
        AND w.net_margin_pct = b.worst_net_margin
    GROUP BY w.company
)
SELECT
    b.company,
    b.net_margin_2019,
    b.net_margin_2025,
    CAST(b.net_margin_2025 - b.net_margin_2019 AS DECIMAL(12,2)) AS change_since_2019,
    b.worst_net_margin,
    w.worst_year,
    b.best_net_margin,
    CASE
        WHEN b.net_margin_2025 >= b.net_margin_2019 THEN 'Recovered or improved'
        ELSE 'Still below 2019'
    END AS recovery_status
FROM baseline AS b
JOIN worst_year AS w
    ON b.company = w.company
ORDER BY change_since_2019 DESC;

-- Q3 - who converts inventory to sales most efficiently
-- inventory turnover trend, with the direction of travel

WITH turnover_span AS (
    SELECT
        company,
        business_model,
        MAX(CASE WHEN fiscal_year = 2019 THEN inventory_turnover END) AS turnover_2019,
        MAX(CASE WHEN fiscal_year = 2025 THEN inventory_turnover END) AS turnover_2025,
        AVG(inventory_turnover) AS avg_turnover,
        MAX(CASE WHEN fiscal_year = 2019 THEN days_inventory_outstanding END) AS dio_2019,
        MAX(CASE WHEN fiscal_year = 2025 THEN days_inventory_outstanding END) AS dio_2025
    FROM analytics.financial_ratios
    WHERE fiscal_year BETWEEN 2019 AND 2025
    GROUP BY company, business_model
)
SELECT
    company,
    business_model,
    turnover_2019,
    turnover_2025,
    CAST(turnover_2025 - turnover_2019 AS DECIMAL(12,2)) AS turnover_change,
    CAST(avg_turnover AS DECIMAL(12,2)) AS avg_turnover,
    dio_2019,
    dio_2025,
    CAST(dio_2025 - dio_2019 AS DECIMAL(12,1)) AS days_change,
    CASE
        WHEN turnover_2025 > turnover_2019 THEN 'Improving'
        WHEN turnover_2025 < turnover_2019 THEN 'Declining'
        ELSE 'Flat'
    END AS direction
FROM turnover_span
ORDER BY turnover_2025 DESC;

-- Q4 - which companies carry the most balance sheet risk
-- scoring balance sheet risk on leverage and liquidity

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
FROM risk
ORDER BY risk_flags DESC, liabilities_to_assets_pct DESC;

-- checking whether leverage rose or fell across the window

SELECT
    company,
    MAX(CASE WHEN fiscal_year = 2019 THEN liabilities_to_assets_pct END) AS leverage_2019,
    MAX(CASE WHEN fiscal_year = 2025 THEN liabilities_to_assets_pct END) AS leverage_2025,
    CAST(MAX(CASE WHEN fiscal_year = 2025 THEN liabilities_to_assets_pct END)
       - MAX(CASE WHEN fiscal_year = 2019 THEN liabilities_to_assets_pct END) AS DECIMAL(12,2)) AS leverage_change
FROM analytics.financial_ratios
WHERE fiscal_year BETWEEN 2019 AND 2025
GROUP BY company
ORDER BY leverage_change DESC;

-- Q5 - are the fast growing retailers growing profitably
-- placing each company on a growth versus margin quadrant

WITH growth_quality AS (
    SELECT
        company,
        business_model,
        fiscal_year,
        revenue_growth_pct,
        net_margin_pct,
        net_margin_pct - LAG(net_margin_pct) OVER (PARTITION BY company ORDER BY fiscal_year) AS margin_change
    FROM analytics.financial_ratios
)
SELECT
    company,
    business_model,
    fiscal_year,
    revenue_growth_pct,
    net_margin_pct,
    CAST(margin_change AS DECIMAL(12,2)) AS margin_change,
    CASE
        WHEN revenue_growth_pct > 0 AND margin_change >= 0 THEN 'Profitable'
        WHEN revenue_growth_pct > 0 AND margin_change < 0 THEN 'Growth at margin cost'
        WHEN revenue_growth_pct <= 0 AND margin_change >= 0 THEN 'Defending margin'
        WHEN revenue_growth_pct IS NULL OR margin_change IS NULL THEN 'No prior year'
        ELSE 'Losing both'
    END AS growth_quality
FROM growth_quality
WHERE fiscal_year = 2025
ORDER BY revenue_growth_pct DESC;

--- counting how often each company landed in each quadrant across the window

WITH with_change AS (
    SELECT
        company,
        fiscal_year,
        revenue_growth_pct,
        net_margin_pct - LAG(net_margin_pct) OVER (PARTITION BY company ORDER BY fiscal_year) AS margin_change
    FROM analytics.financial_ratios
),
quadrants AS (
    SELECT
        company,
        fiscal_year,
        CASE
            WHEN revenue_growth_pct > 0 AND margin_change >= 0 THEN 'Profitable'
            WHEN revenue_growth_pct > 0 AND margin_change < 0 THEN 'Growth at margin cost'
            WHEN revenue_growth_pct <= 0 AND margin_change >= 0 THEN 'Defending margin'
            WHEN revenue_growth_pct IS NULL OR margin_change IS NULL THEN 'No prior year'
            ELSE 'Losing both'
        END AS quadrant
    FROM with_change
)
SELECT
    company,
    quadrant,
    COUNT(*) AS years
FROM quadrants
WHERE fiscal_year BETWEEN 2019 AND 2025
GROUP BY company, quadrant
ORDER BY company, years DESC;