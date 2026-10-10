-- ============================================================
-- Chapter 2 - data profiling
-- Investigates the full extract before any cleaning.
-- ============================================================

USE RetailFinancials;
GO

-- checking the size and shape of the extract per company

SELECT
    company,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT tag) AS distinct_tags,
    COUNT(DISTINCT unit) AS distinct_units,
    MIN(period_end) AS earliest_period,
    MAX(period_end) AS latest_period
FROM src.raw_financials
GROUP BY company
ORDER BY company;

-- checking which units are present, since not every figure is in dollars

SELECT
    unit,
    COUNT(*) AS row_count
FROM src.raw_financials
GROUP BY unit
ORDER BY row_count DESC;

-- checking which filing types came through

SELECT
    form,
    COUNT(*) AS row_count,
    COUNT(DISTINCT company) AS companies
FROM src.raw_financials
GROUP BY form
ORDER BY row_count DESC;

-- checking how many tags are shared by all five companies

WITH tag_reach AS (
    SELECT
        tag,
        COUNT(DISTINCT company) AS companies_using
    FROM src.raw_financials
    GROUP BY tag
)
SELECT
    companies_using,
    COUNT(*) AS tag_count
FROM tag_reach
GROUP BY companies_using
ORDER BY companies_using DESC;

-- checking coverage of the tags the ratio analysis needs

SELECT
    tag,
    SUM(CASE WHEN company = 'Walmart' THEN 1 ELSE 0 END) AS walmart,
    SUM(CASE WHEN company = 'Costco' THEN 1 ELSE 0 END) AS costco,
    SUM(CASE WHEN company = 'Target' THEN 1 ELSE 0 END) AS target_,
    SUM(CASE WHEN company = 'Best Buy' THEN 1 ELSE 0 END) AS best_buy,
    SUM(CASE WHEN company = 'Home Depot' THEN 1 ELSE 0 END) AS home_depot
FROM src.raw_financials
WHERE unit = 'USD'
    AND tag IN (
        'Assets', 'AssetsCurrent', 'Liabilities', 'LiabilitiesCurrent',
        'StockholdersEquity', 'StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest', 'MinorityInterest',
        'Revenues', 'RevenueFromContractWithCustomerExcludingAssessedTax', 'RevenueFromContractWithCustomerIncludingAssessedTax',
        'CostOfRevenue', 'CostOfGoodsAndServicesSold', 'CostOfGoodsSold',
        'NetIncomeLoss', 'NetIncomeLossAvailableToCommonStockholdersBasic', 'ProfitLoss',
        'InventoryNet'
    )
GROUP BY tag
ORDER BY tag;

-- checking the frame column, SEC's own calendar period label

SELECT
    CASE WHEN NULLIF(TRIM(frame), '') IS NULL THEN 'No frame' ELSE 'Has frame' END AS frame_status,
    COUNT(*) AS row_count
FROM src.raw_financials
GROUP BY CASE WHEN NULLIF(TRIM(frame), '') IS NULL THEN 'No frame' ELSE 'Has frame' END;

-- measuring how many times the same figure was reported and how often it changed

WITH duplicate_check AS (
    SELECT
        company,
        tag,
        period_end,
        COUNT(*) AS times_reported,
        COUNT(DISTINCT value) AS distinct_values
    FROM src.raw_financials
    WHERE form = '10-K'
        AND unit = 'USD'
    GROUP BY company, tag, period_end
)
SELECT
    times_reported,
    COUNT(*) AS combinations,
    SUM(CASE WHEN distinct_values > 1 THEN 1 ELSE 0 END) AS with_conflicting_values
FROM duplicate_check
GROUP BY times_reported
ORDER BY times_reported;

-- looking at one duplicated figure up close

SELECT
    company,
    tag,
    period_end,
    accession_number,
    value,
    filed_date
FROM src.raw_financials
WHERE company = 'Walmart'
    AND tag = 'Assets'
    AND form = '10-K'
    AND unit = 'USD'
    AND period_end = '2023-01-31'
ORDER BY filed_date;

-- checking for nulls, blanks and values that will not convert to a number

SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN NULLIF(TRIM(value), '') IS NULL THEN 1 ELSE 0 END) AS missing_value,
    SUM(CASE WHEN NULLIF(TRIM(period_start), '') IS NULL THEN 1 ELSE 0 END) AS missing_period_start,
    SUM(CASE WHEN NULLIF(TRIM(accession_number), '') IS NULL THEN 1 ELSE 0 END) AS missing_accession,
    SUM(CASE WHEN NULLIF(TRIM(frame), '') IS NULL THEN 1 ELSE 0 END) AS missing_frame,
    SUM(CASE WHEN TRY_CAST(value AS DECIMAL(20,2)) IS NULL AND NULLIF(TRIM(value), '') IS NOT NULL THEN 1 ELSE 0 END) AS unconvertible_value
FROM src.raw_financials;

-- checking how rows split between annual, quarterly and balance sheet figures

WITH period_buckets AS (
    SELECT
        CASE
            WHEN NULLIF(TRIM(period_start), '') IS NULL THEN 'Balance sheet (no start date)'
            WHEN DATEDIFF(DAY, TRY_CAST(period_start AS DATE), TRY_CAST(period_end AS DATE)) BETWEEN 350 AND 380 THEN 'Annual (350-380 days)'
            WHEN DATEDIFF(DAY, TRY_CAST(period_start AS DATE), TRY_CAST(period_end AS DATE)) BETWEEN 80 AND 100 THEN 'Quarterly (80-100 days)'
            ELSE 'Other'
        END AS period_bucket
    FROM src.raw_financials
    WHERE form = '10-K'
        AND unit = 'USD'
)
SELECT
    period_bucket,
    COUNT(*) AS row_count
FROM period_buckets
GROUP BY period_bucket
ORDER BY row_count DESC;

-- proving the fiscal_year column is unreliable (same period, different labels)

WITH fy_variants AS (
    SELECT
        company,
        period_end,
        COUNT(DISTINCT fiscal_year) AS distinct_fy_labels
    FROM src.raw_financials
    WHERE form = '10-K'
        AND unit = 'USD'
    GROUP BY company, period_end
)
SELECT
    company,
    COUNT(*) AS periods_checked,
    SUM(CASE WHEN distinct_fy_labels > 1 THEN 1 ELSE 0 END) AS periods_with_conflicting_fy
FROM fy_variants
GROUP BY company
ORDER BY company;

-- checking which revenue tag each company uses for annual figures

SELECT
    company,
    tag,
    COUNT(*) AS annual_rows
FROM src.raw_financials
WHERE form = '10-K'
    AND unit = 'USD'
    AND NULLIF(TRIM(period_start), '') IS NOT NULL
    AND DATEDIFF(DAY, TRY_CAST(period_start AS DATE), TRY_CAST(period_end AS DATE)) BETWEEN 350 AND 380
    AND tag IN ('Revenues', 'RevenueFromContractWithCustomerExcludingAssessedTax', 'RevenueFromContractWithCustomerIncludingAssessedTax')
GROUP BY company, tag
ORDER BY company, tag;
