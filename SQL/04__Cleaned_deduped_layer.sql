-- ============================================================
-- Chapter 4 - cleaned deduped layer
-- Filters to audited annual dollar figures and keeps one row
-- per company + tag + period, from the most recent filing.
-- ============================================================

USE RetailFinancials;
GO

-- keeping one row per figure, preferring the most recently filed version

CREATE OR ALTER VIEW cleaned.financials_deduped AS
WITH analysable AS (
    SELECT *
    FROM cleaned.financials_typed
    WHERE form = '10-K'
        AND unit = 'USD'
        AND period_type IN ('Balance Sheet', 'Annual')
),
value_counts AS (
    SELECT
        company,
        tag,
        period_end,
        COUNT(*) AS times_reported,
        COUNT(DISTINCT value) AS distinct_values_reported
    FROM analysable
    GROUP BY company, tag, period_end
),
ranked AS (
    SELECT
        a.row_id,
        a.company,
        a.ticker,
        a.business_model,
        a.fiscal_year_end,
        a.tag,
        a.period_start,
        a.period_end,
        a.accession_number,
        a.fiscal_year_derived,
        a.frame,
        a.value,
        a.filed_date,
        a.period_type,
        v.times_reported,
        v.distinct_values_reported,
        ROW_NUMBER() OVER (
            PARTITION BY a.company, a.tag, a.period_end
            ORDER BY a.filed_date DESC, a.accession_number DESC
        ) AS filing_rank
    FROM analysable AS a
    JOIN value_counts AS v
        ON a.company = v.company
        AND a.tag = v.tag
        AND a.period_end = v.period_end
)
SELECT
    row_id,
    company,
    ticker,
    business_model,
    fiscal_year_end,
    tag,
    period_start,
    period_end,
    accession_number,
    fiscal_year_derived,
    frame,
    value,
    filed_date,
    period_type,
    times_reported,
    -- flags figures the company later revised
    CASE WHEN distinct_values_reported > 1 THEN 1 ELSE 0 END AS was_restated
FROM ranked
WHERE filing_rank = 1;
GO


-- checking how many rows the filter and dedupe removed

SELECT
    (SELECT COUNT(*) FROM cleaned.financials_typed) AS all_rows,
    (SELECT COUNT(*) FROM cleaned.financials_typed
     WHERE form = '10-K' AND unit = 'USD' AND period_type IN ('Balance Sheet', 'Annual')) AS analysable_rows,
    (SELECT COUNT(*) FROM cleaned.financials_deduped) AS after_dedupe;


-- confirming no duplicates survived

SELECT
    company,
    tag,
    period_end,
    COUNT(*) AS row_count
FROM cleaned.financials_deduped
GROUP BY company, tag, period_end
HAVING COUNT(*) > 1;


-- checking the Walmart example now returns exactly one row

SELECT
    company,
    tag,
    period_end,
    accession_number,
    value,
    filed_date,
    times_reported,
    was_restated
FROM cleaned.financials_deduped
WHERE company = 'Walmart'
    AND tag = 'Assets'
    AND period_end = '2023-01-31';

-- which company-years carry a restatement, in the analysis tag set
SELECT
    company,
    fiscal_year_derived AS fiscal_year,
    SUM(was_restated)   AS restated_figures
FROM cleaned.financials_deduped
WHERE tag IN (
    'Assets','AssetsCurrent','Liabilities','LiabilitiesCurrent',
    'StockholdersEquity','StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest',
    'MinorityInterest','Revenues',
    'RevenueFromContractWithCustomerExcludingAssessedTax',
    'RevenueFromContractWithCustomerIncludingAssessedTax',
    'CostOfRevenue','CostOfGoodsAndServicesSold','CostOfGoodsSold',
    'NetIncomeLoss','NetIncomeLossAvailableToCommonStockholdersBasic',
    'ProfitLoss','InventoryNet')
  AND fiscal_year_derived BETWEEN 2019 AND 2025
GROUP BY company, fiscal_year_derived
HAVING SUM(was_restated) > 0
ORDER BY company, fiscal_year_derived;

-- what is the gap in the restatements

SELECT t.tag, t.period_end, t.value, t.filed_date, t.accession_number
FROM cleaned.financials_typed AS t
JOIN (
    SELECT tag, period_end
    FROM cleaned.financials_typed
    WHERE company = 'Target'
      AND form = '10-K' AND unit = 'USD'
      AND period_type IN ('Balance Sheet', 'Annual')
      AND fiscal_year_derived IN (2022, 2023)
      AND tag IN (
        'Assets','AssetsCurrent','Liabilities','LiabilitiesCurrent',
        'StockholdersEquity','StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest',
        'MinorityInterest','Revenues',
        'RevenueFromContractWithCustomerExcludingAssessedTax',
        'RevenueFromContractWithCustomerIncludingAssessedTax',
        'CostOfRevenue','CostOfGoodsAndServicesSold','CostOfGoodsSold',
        'NetIncomeLoss','NetIncomeLossAvailableToCommonStockholdersBasic',
        'ProfitLoss','InventoryNet')
    GROUP BY tag, period_end
    HAVING COUNT(DISTINCT value) > 1
) AS r
    ON t.tag = r.tag AND t.period_end = r.period_end
WHERE t.company = 'Target'
  AND t.form = '10-K' AND t.unit = 'USD'
ORDER BY t.tag, t.period_end, t.filed_date;