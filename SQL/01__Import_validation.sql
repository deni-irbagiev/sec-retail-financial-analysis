-- ============================================================
-- Chapter 1 - import validation
-- Schemas, source tables, CSV load, row count verification
-- ============================================================

USE RetailFinancials;
GO

IF SCHEMA_ID('src') IS NULL EXEC('CREATE SCHEMA src');
IF SCHEMA_ID('cleaned') IS NULL EXEC('CREATE SCHEMA cleaned');
IF SCHEMA_ID('analytics') IS NULL EXEC('CREATE SCHEMA analytics');
IF SCHEMA_ID('reporting') IS NULL EXEC('CREATE SCHEMA reporting');
GO

-- rebuilding the source table for the full extract

DROP TABLE IF EXISTS src.raw_financials;
GO

CREATE TABLE src.raw_financials (
    company NVARCHAR(50),
    tag NVARCHAR(200),
    unit NVARCHAR(40),
    period_start NVARCHAR(20),
    period_end NVARCHAR(20),
    accession_number NVARCHAR(30),
    fiscal_year NVARCHAR(10),
    fiscal_period NVARCHAR(10),
    form NVARCHAR(10),
    value NVARCHAR(40),
    filed_date NVARCHAR(20),
    frame NVARCHAR(20)
);
GO

DROP TABLE IF EXISTS src.dim_company;
GO


-- creating company dimension table 

CREATE TABLE src.dim_company (
    company NVARCHAR(50) PRIMARY KEY,
    ticker NVARCHAR(10),
    cik NVARCHAR(15),
    fiscal_year_end NVARCHAR(30),
    business_model NVARCHAR(50)
);
GO

INSERT INTO src.dim_company (company, ticker, cik, fiscal_year_end, business_model)
VALUES
    ('Walmart',    'WMT',  '0000104169', '31 January',  'General Merchandise'),
    ('Costco',     'COST', '0000909832', 'Late August',   'Membership Warehouse'),
    ('Target',     'TGT',  '0000027419', 'Late Jan / early Feb',  'General Merchandise'),
    ('Best Buy',   'BBY',  '0000764478', 'Late Jan / early Feb',  'Electronics Specialty'),
    ('Home Depot', 'HD',   '0000354950', 'Late Jan / early Feb',  'Home Improvement');
GO


-- loading the CSV files
BULK INSERT src.raw_financials FROM 'C:\SEC_data\walmart.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"', FIELDTERMINATOR=',', ROWTERMINATOR='0x0a');

BULK INSERT src.raw_financials FROM 'C:\SEC_data\costco.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"', FIELDTERMINATOR=',', ROWTERMINATOR='0x0a');

BULK INSERT src.raw_financials FROM 'C:\SEC_data\target.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"', FIELDTERMINATOR=',', ROWTERMINATOR='0x0a');

BULK INSERT src.raw_financials FROM 'C:\SEC_data\bestbuy.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"', FIELDTERMINATOR=',', ROWTERMINATOR='0x0a');

BULK INSERT src.raw_financials FROM 'C:\SEC_data\homedepot.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"', FIELDTERMINATOR=',', ROWTERMINATOR='0x0a');
GO

-- adding the surrogate key after loading

ALTER TABLE src.raw_financials
    ADD row_id INT IDENTITY(1,1) NOT NULL;
GO

ALTER TABLE src.raw_financials
    ADD CONSTRAINT pk_raw_financials PRIMARY KEY (row_id);
GO

-- checking the load succeeded

SELECT
    company,
    COUNT(*) AS rows_loaded,
    COUNT(DISTINCT tag) AS distinct_tags,
    COUNT(DISTINCT unit) AS distinct_units
FROM src.raw_financials
GROUP BY company
ORDER BY company;

-- checking the dimension table joins

SELECT DISTINCT r.company
FROM src.raw_financials AS r
LEFT JOIN src.dim_company AS d
    ON r.company = d.company
WHERE d.company IS NULL;
