-- ============================================================
-- Chapter 5 - cleaned normalized layer
--
-- This is where line items are selected. src holds all 1212
-- tags the five companies filed. The ratio analysis needs nine
-- concepts:
--
--   assets, current assets, liabilities, current liabilities,
--   equity, revenue, cost of goods sold, net income, inventory
--
-- Two further tags are pulled that feed no ratio directly:
-- non-controlling interests and equity including NCI. Three of
-- the five companies never report total liabilities, so it is
-- derived as Assets - Equity - NCI, and the second tag gives an
-- independent check on that derivation.
--
-- Filers do not all use the same tag for the same concept, so
-- each concept lists every variant found in the data and picks
-- between them with COALESCE. Every other tag in src is a
-- footnote or sub-component and feeds none of the ratios.
-- ============================================================

USE RetailFinancials;
GO

-- selecting the analysis tags, pivoting to one row per company-year

CREATE OR ALTER VIEW cleaned.financials_normalized AS
WITH pivoted AS (
    SELECT
        company,
        ticker,
        business_model,
        fiscal_year_end,
        fiscal_year_derived,
        MAX(period_end) AS period_end,

        -- balance sheet
        MAX(CASE WHEN tag = 'Assets' THEN value END) AS assets,
        MAX(CASE WHEN tag = 'AssetsCurrent' THEN value END) AS assets_current,
        MAX(CASE WHEN tag = 'Liabilities' THEN value END) AS liabilities_reported,
        MAX(CASE WHEN tag = 'LiabilitiesCurrent' THEN value END) AS liabilities_current,
        MAX(CASE WHEN tag = 'StockholdersEquity' THEN value END) AS equity,
        MAX(CASE WHEN tag = 'StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest' THEN value END) AS equity_incl_nci,
        MAX(CASE WHEN tag = 'MinorityInterest' THEN value END) AS minority_interest,
        MAX(CASE WHEN tag = 'InventoryNet' THEN value END) AS inventory,

        -- income statement, variants kept apart so the choice stays visible
        MAX(CASE WHEN tag = 'RevenueFromContractWithCustomerExcludingAssessedTax' THEN value END) AS revenue_excl_tax,
        MAX(CASE WHEN tag = 'RevenueFromContractWithCustomerIncludingAssessedTax' THEN value END) AS revenue_incl_tax,
        MAX(CASE WHEN tag = 'Revenues' THEN value END) AS revenue_legacy,
        MAX(CASE WHEN tag = 'CostOfGoodsAndServicesSold' THEN value END) AS cogs_goods_services,
        MAX(CASE WHEN tag = 'CostOfGoodsSold' THEN value END) AS cogs_goods,
        MAX(CASE WHEN tag = 'CostOfRevenue' THEN value END) AS cogs_revenue,
        MAX(CASE WHEN tag = 'NetIncomeLoss' THEN value END) AS net_income_primary,
        MAX(CASE WHEN tag = 'NetIncomeLossAvailableToCommonStockholdersBasic' THEN value END) AS net_income_common,
        MAX(CASE WHEN tag = 'ProfitLoss' THEN value END) AS profit_loss,

        SUM(was_restated) AS restated_figures
    FROM cleaned.financials_deduped
    WHERE tag IN (
        'Assets', 'AssetsCurrent', 'Liabilities', 'LiabilitiesCurrent',
        'StockholdersEquity', 'StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest', 'MinorityInterest',
        'Revenues', 'RevenueFromContractWithCustomerExcludingAssessedTax', 'RevenueFromContractWithCustomerIncludingAssessedTax',
        'CostOfRevenue', 'CostOfGoodsAndServicesSold', 'CostOfGoodsSold',
        'NetIncomeLoss', 'NetIncomeLossAvailableToCommonStockholdersBasic', 'ProfitLoss',
        'InventoryNet'
    )
    GROUP BY
        company,
        ticker,
        business_model,
        fiscal_year_end,
        fiscal_year_derived
)
SELECT
    company,
    ticker,
    business_model,
    fiscal_year_end,
    fiscal_year_derived AS fiscal_year,
    period_end,

    assets,
    assets_current,
    liabilities_current,
    equity,
    equity_incl_nci,
    minority_interest,
    inventory,

    -- ASC 606 tags preferred, legacy Revenues tag as fallback
    COALESCE(revenue_excl_tax, revenue_incl_tax, revenue_legacy) AS revenue,

    -- whichever of the three cost tags the filer used
    COALESCE(cogs_goods_services, cogs_goods, cogs_revenue) AS cogs,

    -- primary tag first, then the filer-specific variants
    COALESCE(net_income_primary, net_income_common, profit_loss) AS net_income,

    -- reported liabilities, otherwise derived from Assets = Liabilities + Parent Equity + Non-controlling interests
    COALESCE(liabilities_reported, assets - equity - ISNULL(minority_interest, 0)) AS liabilities,

    -- keeping every substitution visible for the write-up
    CASE
        WHEN revenue_excl_tax IS NOT NULL THEN 'ASC 606 excluding tax'
        WHEN revenue_incl_tax IS NOT NULL THEN 'ASC 606 including tax'
        WHEN revenue_legacy IS NOT NULL THEN 'Legacy Revenues tag'
        ELSE 'Missing'
    END AS revenue_source,

    CASE
        WHEN net_income_primary IS NOT NULL THEN 'NetIncomeLoss'
        WHEN net_income_common IS NOT NULL THEN 'Available to common stockholders'
        WHEN profit_loss IS NOT NULL THEN 'ProfitLoss'
        ELSE 'Missing'
    END AS net_income_source,

    CASE
        WHEN liabilities_reported IS NOT NULL THEN 'Reported'
        WHEN assets IS NOT NULL AND equity IS NOT NULL THEN 'Derived (Assets - Equity - NCI)'
        ELSE 'Missing'
    END AS liabilities_source,

    restated_figures
FROM pivoted;
GO


-- documenting how many tags exist versus how many the analysis uses

SELECT
    (SELECT COUNT(DISTINCT tag) FROM src.raw_financials) AS tags_in_source,
    (SELECT COUNT(DISTINCT tag) FROM cleaned.financials_deduped) AS tags_after_filtering,
    (SELECT COUNT(DISTINCT tag) FROM cleaned.financials_deduped
     WHERE tag IN (
        'Assets', 'AssetsCurrent', 'Liabilities', 'LiabilitiesCurrent',
        'StockholdersEquity', 'StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest', 'MinorityInterest',
        'Revenues', 'RevenueFromContractWithCustomerExcludingAssessedTax', 'RevenueFromContractWithCustomerIncludingAssessedTax',
        'CostOfRevenue', 'CostOfGoodsAndServicesSold', 'CostOfGoodsSold',
        'NetIncomeLoss', 'NetIncomeLossAvailableToCommonStockholdersBasic', 'ProfitLoss',
        'InventoryNet')) AS tags_used_in_analysis;


-- checking how many company-years we ended up with

SELECT
    company,
    COUNT(*) AS company_years,
    MIN(fiscal_year) AS earliest_fy,
    MAX(fiscal_year) AS latest_fy
FROM cleaned.financials_normalized
GROUP BY company
ORDER BY company;


-- checking which revenue tag each company relies on, by year

SELECT
    company,
    revenue_source,
    COUNT(*) AS years,
    MIN(fiscal_year) AS from_fy,
    MAX(fiscal_year) AS to_fy
FROM cleaned.financials_normalized
GROUP BY company, revenue_source
ORDER BY company, from_fy;


-- checking which net income tag each company relies on

SELECT
    company,
    net_income_source,
    COUNT(*) AS years,
    MIN(fiscal_year) AS from_fy,
    MAX(fiscal_year) AS to_fy
FROM cleaned.financials_normalized
GROUP BY company, net_income_source
ORDER BY company, from_fy;


-- checking where liabilities had to be derived

SELECT
    company,
    liabilities_source,
    COUNT(*) AS years
FROM cleaned.financials_normalized
GROUP BY company, liabilities_source
ORDER BY company;


-- checking the accounting identity and how much sits with outside shareholders

SELECT
    company,
    fiscal_year,
    assets,
    liabilities,
    equity,
    minority_interest,
    assets - (liabilities + equity) AS identity_gap
FROM cleaned.financials_normalized
WHERE liabilities_source = 'Reported'
    AND ABS(assets - (liabilities + equity)) > 1000000
ORDER BY company, fiscal_year;


-- flagging negative equity, which breaks ROE and debt to equity

SELECT
    company,
    fiscal_year,
    equity,
    net_income
FROM cleaned.financials_normalized
WHERE equity <= 0
    AND fiscal_year BETWEEN 2019 AND 2025
ORDER BY company, fiscal_year;


-- checking for gaps in the years the analysis will use

SELECT
    company,
    fiscal_year,
    CASE WHEN assets IS NULL THEN 'X' ELSE '' END AS no_assets,
    CASE WHEN assets_current IS NULL THEN 'X' ELSE '' END AS no_curr_assets,
    CASE WHEN liabilities_current IS NULL THEN 'X' ELSE '' END AS no_curr_liab,
    CASE WHEN equity IS NULL THEN 'X' ELSE '' END AS no_equity,
    CASE WHEN revenue IS NULL THEN 'X' ELSE '' END AS no_revenue,
    CASE WHEN cogs IS NULL THEN 'X' ELSE '' END AS no_cogs,
    CASE WHEN net_income IS NULL THEN 'X' ELSE '' END AS no_net_income,
    CASE WHEN inventory IS NULL THEN 'X' ELSE '' END AS no_inventory
FROM cleaned.financials_normalized
WHERE fiscal_year BETWEEN 2019 AND 2025
    AND (assets IS NULL OR assets_current IS NULL OR liabilities_current IS NULL
         OR equity IS NULL OR revenue IS NULL OR cogs IS NULL
         OR net_income IS NULL OR inventory IS NULL)
ORDER BY company, fiscal_year;

-- confirming the two ways of derived liabilities agree
SELECT
    company,
    fiscal_year,
    equity,
    equity_incl_nci,
    minority_interest,
    equity_incl_nci - equity - ISNULL(minority_interest, 0) AS unexplained_gap
FROM cleaned.financials_normalized
WHERE equity_incl_nci IS NOT NULL
  AND ABS(equity_incl_nci - equity - ISNULL(minority_interest, 0)) > 0
ORDER BY company, fiscal_year;
