-- ============================================================
-- Chapter 3 - cleaned typed layer
--
-- Converts text to real types and adds derived columns.
-- Stays 1:1 with src, no filtering.
--
-- Fiscal year is derived from period_end because SEC's own
-- fiscal_year column is unreliable (proven in Chapter 2). The
-- June cutoff suits this peer group: four companies close in
-- late January or early February and take the prior calendar
-- year, Costco closes in late August and keeps the current one.
-- A mid-year filer such as 30 June would be mislabelled.
-- ============================================================

USE RetailFinancials;
GO

-- typing every column and deriving fiscal year and period classification

CREATE OR ALTER VIEW cleaned.financials_typed AS
SELECT
    r.row_id,
    r.company,
    d.ticker,
    d.business_model,
    d.fiscal_year_end,
    r.tag,
    r.unit,
    TRY_CAST(NULLIF(TRIM(r.period_start), '') AS DATE) AS period_start,
    TRY_CAST(r.period_end AS DATE) AS period_end,
    r.accession_number,
    TRY_CAST(r.fiscal_year AS INT) AS fiscal_year_reported,
    r.form,
    NULLIF(TRIM(r.frame), '') AS frame,
    TRY_CAST(r.value AS DECIMAL(20,2)) AS value,
    TRY_CAST(r.filed_date AS DATE) AS filed_date,

    -- derived, not SEC's label -- see header
    CASE
        WHEN MONTH(TRY_CAST(r.period_end AS DATE)) <= 6
            THEN YEAR(TRY_CAST(r.period_end AS DATE)) - 1
        ELSE YEAR(TRY_CAST(r.period_end AS DATE))
    END AS fiscal_year_derived,

    -- how many days the figure covers, NULL for balance sheet rows
    DATEDIFF(DAY, TRY_CAST(NULLIF(TRIM(r.period_start), '') AS DATE), TRY_CAST(r.period_end AS DATE)) AS period_days,

    -- what kind of figure this row is
    CASE
        WHEN NULLIF(TRIM(r.period_start), '') IS NULL THEN 'Balance Sheet'
        WHEN DATEDIFF(DAY, TRY_CAST(NULLIF(TRIM(r.period_start), '') AS DATE), TRY_CAST(r.period_end AS DATE)) BETWEEN 350 AND 380 THEN 'Annual'
        ELSE 'Interim'
    END AS period_type

FROM src.raw_financials AS r
LEFT JOIN src.dim_company AS d
    ON r.company = d.company;
GO


-- checking the view is still 1:1 with the source table

SELECT
    (SELECT COUNT(*) FROM src.raw_financials) AS src_rows,
    (SELECT COUNT(*) FROM cleaned.financials_typed) AS typed_rows;


-- checking nothing failed to convert

SELECT
    SUM(CASE WHEN period_end IS NULL THEN 1 ELSE 0 END) AS bad_period_end,
    SUM(CASE WHEN value IS NULL THEN 1 ELSE 0 END) AS bad_value,
    SUM(CASE WHEN filed_date IS NULL THEN 1 ELSE 0 END) AS bad_filed_date
FROM cleaned.financials_typed;


-- checking the derived fiscal year makes sense for each company

SELECT DISTINCT
    company,
    fiscal_year_end,
    period_end,
    fiscal_year_reported,
    fiscal_year_derived
FROM cleaned.financials_typed
WHERE form = '10-K'
    AND unit = 'USD'
    AND period_type = 'Annual'
    AND period_end >= '2024-01-01'
ORDER BY company, period_end;