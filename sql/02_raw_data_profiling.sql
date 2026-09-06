USE RetailAnalytics;
GO

/*
Read-only profiling of raw.online_retail.
Implements Phases 0–6. Phases 7–9 are out of scope in this file.

Percentages always use actual COUNT(*) from the table (dynamic total).
The literal 541909 is used only as a load-quality assertion in Phase 0.
No INSERT/UPDATE/DELETE/MERGE/TRUNCATE/DROP/ALTER/CREATE TABLE/SELECT INTO.
*/


-- =============================================================================
-- Phase 0 — Baseline
-- Business purpose: confirm the load, the analysis window, key cardinality,
-- and that the grain is invoice line (many lines per InvoiceNo).
-- =============================================================================

-- 0.1 Load-quality assertion (541909 is expected only here, not for percentages)
SELECT
    COUNT(*) AS actual_row_count,
    541909 AS expected_row_count,
    CASE
        WHEN COUNT(*) = 541909 THEN 'PASS'
        ELSE 'FAIL'
    END AS load_row_count_check
FROM raw.online_retail;

-- 0.2 Date range of the loaded extract
SELECT
    MIN(InvoiceDate) AS min_invoice_date,
    MAX(InvoiceDate) AS max_invoice_date
FROM raw.online_retail;

-- 0.3 Distinct keys (null CustomerID is excluded from distinct identified customers)
SELECT
    COUNT(DISTINCT InvoiceNo) AS distinct_invoices,
    COUNT(DISTINCT StockCode) AS distinct_stock_codes,
    COUNT(DISTINCT CustomerID) AS distinct_identified_customers,
    COUNT(DISTINCT Country) AS distinct_countries
FROM raw.online_retail;

-- 0.4 Grain check: lines per invoice (pass if typical invoices have many lines)
SELECT
    MIN(lines_per_invoice) AS min_lines_per_invoice,
    MAX(lines_per_invoice) AS max_lines_per_invoice,
    AVG(CAST(lines_per_invoice AS decimal(18, 4))) AS avg_lines_per_invoice
FROM (
    SELECT InvoiceNo, COUNT(*) AS lines_per_invoice
    FROM raw.online_retail
    GROUP BY InvoiceNo
) AS invoice_grain;

-- 0.5 Load-quality: CustomerID must not retain Excel-style ".0"
-- Business purpose: the raw load was meant to store IDs as strings without ".0".
SELECT
    i.issue_rows AS customer_id_with_dot_zero_rows,
    100.0 * i.issue_rows / NULLIF(t.total_rows, 0) AS pct_of_loaded_rows
FROM (
    SELECT COUNT(*) AS issue_rows
    FROM raw.online_retail
    WHERE CustomerID LIKE '%.0'
) AS i
CROSS JOIN (
    SELECT COUNT(*) AS total_rows
    FROM raw.online_retail
) AS t;

-- 0.6 Load-quality: identifier strings should not look like float leftovers
SELECT
    SUM(CASE WHEN InvoiceNo LIKE '%.0' THEN 1 ELSE 0 END) AS invoice_no_with_dot_zero_rows,
    100.0 * SUM(CASE WHEN InvoiceNo LIKE '%.0' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS invoice_no_dot_zero_pct,
    SUM(CASE WHEN StockCode LIKE '%.0' THEN 1 ELSE 0 END) AS stock_code_with_dot_zero_rows,
    100.0 * SUM(CASE WHEN StockCode LIKE '%.0' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS stock_code_dot_zero_pct
FROM raw.online_retail;

-- 0.7 Column metadata (read-only catalog; types and nullability, not content)
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    NUMERIC_PRECISION,
    NUMERIC_SCALE,
    DATETIME_PRECISION,
    IS_NULLABLE,
    ORDINAL_POSITION
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = N'raw'
  AND TABLE_NAME = N'online_retail'
ORDER BY ORDINAL_POSITION;


-- =============================================================================
-- Phase 1 — Completeness
-- Business purpose: see which columns are missing. Null CustomerID is an
-- unidentified customer, not a load error. Blank Description values were
-- observed in SQL; the cause of that representation has not been verified.
-- =============================================================================

-- 1.1 Completeness summary (count and % of actual loaded rows)
SELECT
    SUM(CASE WHEN InvoiceNo IS NULL OR LTRIM(RTRIM(InvoiceNo)) = '' THEN 1 ELSE 0 END)
        AS blank_invoice_no_rows,
    100.0 * SUM(CASE WHEN InvoiceNo IS NULL OR LTRIM(RTRIM(InvoiceNo)) = '' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS blank_invoice_no_pct,

    SUM(CASE WHEN StockCode IS NULL OR LTRIM(RTRIM(StockCode)) = '' THEN 1 ELSE 0 END)
        AS blank_stock_code_rows,
    100.0 * SUM(CASE WHEN StockCode IS NULL OR LTRIM(RTRIM(StockCode)) = '' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS blank_stock_code_pct,

    SUM(CASE WHEN Description IS NULL OR LTRIM(RTRIM(Description)) = '' THEN 1 ELSE 0 END)
        AS blank_description_rows,
    100.0 * SUM(CASE WHEN Description IS NULL OR LTRIM(RTRIM(Description)) = '' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS blank_description_pct,

    SUM(CASE WHEN Quantity IS NULL THEN 1 ELSE 0 END) AS null_quantity_rows,
    100.0 * SUM(CASE WHEN Quantity IS NULL THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS null_quantity_pct,

    SUM(CASE WHEN InvoiceDate IS NULL THEN 1 ELSE 0 END) AS null_invoice_date_rows,
    100.0 * SUM(CASE WHEN InvoiceDate IS NULL THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS null_invoice_date_pct,

    SUM(CASE WHEN UnitPrice IS NULL THEN 1 ELSE 0 END) AS null_unit_price_rows,
    100.0 * SUM(CASE WHEN UnitPrice IS NULL THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS null_unit_price_pct,

    SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) AS null_customer_id_rows,
    100.0 * SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS null_customer_id_pct,

    SUM(CASE WHEN Country IS NULL OR LTRIM(RTRIM(Country)) = '' THEN 1 ELSE 0 END)
        AS blank_country_rows,
    100.0 * SUM(CASE WHEN Country IS NULL OR LTRIM(RTRIM(Country)) = '' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS blank_country_pct
FROM raw.online_retail;

-- 1.2 Null CustomerID (unidentified customer) — count and %
SELECT
    i.issue_rows AS null_customer_id_rows,
    100.0 * i.issue_rows / NULLIF(t.total_rows, 0) AS pct_of_loaded_rows
FROM (
    SELECT COUNT(*) AS issue_rows
    FROM raw.online_retail
    WHERE CustomerID IS NULL
) AS i
CROSS JOIN (
    SELECT COUNT(*) AS total_rows
    FROM raw.online_retail
) AS t;

-- 1.3 Example unidentified-customer lines
SELECT TOP (10)
    raw_row_id,
    InvoiceNo,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Country
FROM raw.online_retail
WHERE CustomerID IS NULL
ORDER BY InvoiceDate, InvoiceNo, raw_row_id;

-- 1.4 Empty or whitespace-only Description — count and %
SELECT
    i.issue_rows AS blank_description_rows,
    100.0 * i.issue_rows / NULLIF(t.total_rows, 0) AS pct_of_loaded_rows
FROM (
    SELECT COUNT(*) AS issue_rows
    FROM raw.online_retail
    WHERE Description IS NULL
       OR LTRIM(RTRIM(Description)) = ''
) AS i
CROSS JOIN (
    SELECT COUNT(*) AS total_rows
    FROM raw.online_retail
) AS t;

-- 1.5 Example missing-description lines
SELECT TOP (10)
    raw_row_id,
    InvoiceNo,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Country
FROM raw.online_retail
WHERE Description IS NULL
   OR LTRIM(RTRIM(Description)) = ''
ORDER BY InvoiceDate, InvoiceNo, raw_row_id;

-- 1.6 Unexpected blanks on InvoiceNo / StockCode / Country (expect none)
SELECT
    i.issue_rows AS blank_required_text_rows,
    100.0 * i.issue_rows / NULLIF(t.total_rows, 0) AS pct_of_loaded_rows
FROM (
    SELECT COUNT(*) AS issue_rows
    FROM raw.online_retail
    WHERE InvoiceNo IS NULL OR LTRIM(RTRIM(InvoiceNo)) = ''
       OR StockCode IS NULL OR LTRIM(RTRIM(StockCode)) = ''
       OR Country IS NULL OR LTRIM(RTRIM(Country)) = ''
) AS i
CROSS JOIN (
    SELECT COUNT(*) AS total_rows
    FROM raw.online_retail
) AS t;

SELECT TOP (10)
    raw_row_id,
    InvoiceNo,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Country
FROM raw.online_retail
WHERE InvoiceNo IS NULL OR LTRIM(RTRIM(InvoiceNo)) = ''
   OR StockCode IS NULL OR LTRIM(RTRIM(StockCode)) = ''
   OR Country IS NULL OR LTRIM(RTRIM(Country)) = ''
ORDER BY InvoiceDate, InvoiceNo, raw_row_id;


-- =============================================================================
-- Phase 2 — Transaction behaviour
-- Business purpose: cancellations and negative quantities must stay in raw.
-- Cross-tab C-prefix vs quantity sign so silver can flag is_cancellation
-- without deleting rows. Mismatches (C with positive qty, negative qty
-- without C) need examples.
-- =============================================================================

-- 2.1 Cancellation invoices (InvoiceNo like 'C%') — count and %
SELECT
    i.issue_rows AS cancellation_prefix_rows,
    100.0 * i.issue_rows / NULLIF(t.total_rows, 0) AS pct_of_loaded_rows
FROM (
    SELECT COUNT(*) AS issue_rows
    FROM raw.online_retail
    WHERE InvoiceNo LIKE 'C%'
) AS i
CROSS JOIN (
    SELECT COUNT(*) AS total_rows
    FROM raw.online_retail
) AS t;

-- 2.2 Negative quantity — count and %
SELECT
    i.issue_rows AS negative_quantity_rows,
    100.0 * i.issue_rows / NULLIF(t.total_rows, 0) AS pct_of_loaded_rows
FROM (
    SELECT COUNT(*) AS issue_rows
    FROM raw.online_retail
    WHERE Quantity < 0
) AS i
CROSS JOIN (
    SELECT COUNT(*) AS total_rows
    FROM raw.online_retail
) AS t;

-- 2.3 Zero quantity — count and %
SELECT
    i.issue_rows AS zero_quantity_rows,
    100.0 * i.issue_rows / NULLIF(t.total_rows, 0) AS pct_of_loaded_rows
FROM (
    SELECT COUNT(*) AS issue_rows
    FROM raw.online_retail
    WHERE Quantity = 0
) AS i
CROSS JOIN (
    SELECT COUNT(*) AS total_rows
    FROM raw.online_retail
) AS t;

-- 2.4 Cross-tab: cancellation prefix vs sign of Quantity
-- Percentages use an independent full-table total, not COUNT(*) of each group.
SELECT
    CASE WHEN r.InvoiceNo LIKE 'C%' THEN 1 ELSE 0 END AS is_cancellation_prefix,
    CASE
        WHEN r.Quantity < 0 THEN 'negative'
        WHEN r.Quantity = 0 THEN 'zero'
        ELSE 'positive'
    END AS quantity_sign,
    COUNT(*) AS row_count,
    100.0 * COUNT(*) / NULLIF(MAX(t.total_rows), 0) AS pct_of_loaded_rows
FROM raw.online_retail AS r
CROSS JOIN (
    SELECT COUNT(*) AS total_rows FROM raw.online_retail
) AS t
GROUP BY
    CASE WHEN r.InvoiceNo LIKE 'C%' THEN 1 ELSE 0 END,
    CASE
        WHEN r.Quantity < 0 THEN 'negative'
        WHEN r.Quantity = 0 THEN 'zero'
        ELSE 'positive'
    END
ORDER BY is_cancellation_prefix, quantity_sign;

-- 2.5 Example cancelled lines
SELECT TOP (10)
    raw_row_id,
    InvoiceNo,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Country
FROM raw.online_retail
WHERE InvoiceNo LIKE 'C%'
ORDER BY InvoiceDate, InvoiceNo, raw_row_id;

-- 2.6 Mismatch: C-prefix with non-negative quantity
SELECT
    i.issue_rows AS c_prefix_non_negative_qty_rows,
    100.0 * i.issue_rows / NULLIF(t.total_rows, 0) AS pct_of_loaded_rows
FROM (
    SELECT COUNT(*) AS issue_rows
    FROM raw.online_retail
    WHERE InvoiceNo LIKE 'C%'
      AND Quantity >= 0
) AS i
CROSS JOIN (
    SELECT COUNT(*) AS total_rows
    FROM raw.online_retail
) AS t;

SELECT TOP (10)
    raw_row_id,
    InvoiceNo,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Country
FROM raw.online_retail
WHERE InvoiceNo LIKE 'C%'
  AND Quantity >= 0
ORDER BY InvoiceDate, InvoiceNo, raw_row_id;

-- 2.7 Mismatch: negative quantity without C-prefix
SELECT
    i.issue_rows AS negative_qty_without_c_prefix_rows,
    100.0 * i.issue_rows / NULLIF(t.total_rows, 0) AS pct_of_loaded_rows
FROM (
    SELECT COUNT(*) AS issue_rows
    FROM raw.online_retail
    WHERE Quantity < 0
      AND InvoiceNo NOT LIKE 'C%'
) AS i
CROSS JOIN (
    SELECT COUNT(*) AS total_rows
    FROM raw.online_retail
) AS t;

SELECT TOP (10)
    raw_row_id,
    InvoiceNo,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Country
FROM raw.online_retail
WHERE Quantity < 0
  AND InvoiceNo NOT LIKE 'C%'
ORDER BY InvoiceDate, InvoiceNo, raw_row_id;

-- 2.8 Example zero-quantity lines (if any)
SELECT TOP (10)
    raw_row_id,
    InvoiceNo,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Country
FROM raw.online_retail
WHERE Quantity = 0
ORDER BY InvoiceDate, InvoiceNo, raw_row_id;


-- =============================================================================
-- Phase 3 — Price and value
-- Business purpose: show how price sign and quantity sign affect revenue
-- before any silver filter. LineValue is computed in the query only.
-- Value buckets:
--   gross_sales_value  = Quantity > 0 AND UnitPrice > 0
--   refund_value       = signed Quantity * UnitPrice where Quantity < 0
--                        AND UnitPrice > 0 (provisional; adjustment lines
--                        are not classified yet)
--   refund_amount_abs  = positive magnitude of refund_value
--   net_line_value     = all Quantity * UnitPrice
--   zero_price         = UnitPrice = 0 (rows and value)
--   negative_price     = UnitPrice < 0 (rows and value)
-- =============================================================================

-- 3.1 UnitPrice sign — count and %
-- Percentages use an independent full-table total, not COUNT(*) of each group.
SELECT
    CASE
        WHEN r.UnitPrice < 0 THEN 'negative'
        WHEN r.UnitPrice = 0 THEN 'zero'
        ELSE 'positive'
    END AS unit_price_sign,
    COUNT(*) AS row_count,
    100.0 * COUNT(*) / NULLIF(MAX(t.total_rows), 0) AS pct_of_loaded_rows
FROM raw.online_retail AS r
CROSS JOIN (
    SELECT COUNT(*) AS total_rows FROM raw.online_retail
) AS t
GROUP BY
    CASE
        WHEN r.UnitPrice < 0 THEN 'negative'
        WHEN r.UnitPrice = 0 THEN 'zero'
        ELSE 'positive'
    END
ORDER BY unit_price_sign;

-- 3.2 Separated value measures (LineValue not stored in raw)
-- refund_value is signed (typically negative). refund_amount_abs is its
-- positive magnitude. Both are provisional pending classification of
-- adjustment lines (for example postage or manual codes) in a later phase.
SELECT
    SUM(CASE WHEN Quantity > 0 AND UnitPrice > 0 THEN Quantity * UnitPrice ELSE 0 END)
        AS gross_sales_value,
    SUM(CASE WHEN Quantity < 0 AND UnitPrice > 0 THEN Quantity * UnitPrice ELSE 0 END)
        AS refund_value,
    ABS(SUM(CASE WHEN Quantity < 0 AND UnitPrice > 0 THEN Quantity * UnitPrice ELSE 0 END))
        AS refund_amount_abs,
    SUM(Quantity * UnitPrice) AS net_line_value,

    SUM(CASE WHEN UnitPrice = 0 THEN 1 ELSE 0 END) AS zero_price_rows,
    100.0 * SUM(CASE WHEN UnitPrice = 0 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS zero_price_row_pct,
    SUM(CASE WHEN UnitPrice = 0 THEN Quantity * UnitPrice ELSE 0 END) AS zero_price_value,

    SUM(CASE WHEN UnitPrice < 0 THEN 1 ELSE 0 END) AS negative_price_rows,
    100.0 * SUM(CASE WHEN UnitPrice < 0 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) AS negative_price_row_pct,
    SUM(CASE WHEN UnitPrice < 0 THEN Quantity * UnitPrice ELSE 0 END) AS negative_price_value
FROM raw.online_retail;

-- 3.3 Min / max / percentiles for Quantity and UnitPrice
-- Business purpose: outliers can dominate revenue; percentiles show typical scale.
SELECT DISTINCT
    MIN(Quantity) OVER () AS min_quantity,
    MAX(Quantity) OVER () AS max_quantity,
    PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY Quantity) OVER () AS quantity_p01,
    PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY Quantity) OVER () AS quantity_p05,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY Quantity) OVER () AS quantity_p50,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY Quantity) OVER () AS quantity_p95,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY Quantity) OVER () AS quantity_p99,
    MIN(UnitPrice) OVER () AS min_unit_price,
    MAX(UnitPrice) OVER () AS max_unit_price,
    PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY UnitPrice) OVER () AS unit_price_p01,
    PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY UnitPrice) OVER () AS unit_price_p05,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY UnitPrice) OVER () AS unit_price_p50,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY UnitPrice) OVER () AS unit_price_p95,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY UnitPrice) OVER () AS unit_price_p99
FROM raw.online_retail;

-- 3.4 Extreme |Quantity| examples
SELECT TOP (10)
    raw_row_id,
    InvoiceNo,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Country,
    Quantity * UnitPrice AS line_value
FROM raw.online_retail
ORDER BY ABS(Quantity) DESC, InvoiceDate, raw_row_id;

-- 3.5 Extreme UnitPrice examples
SELECT TOP (10)
    raw_row_id,
    InvoiceNo,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Country,
    Quantity * UnitPrice AS line_value
FROM raw.online_retail
ORDER BY ABS(UnitPrice) DESC, InvoiceDate, raw_row_id;

-- 3.6 Zero UnitPrice — count, %, examples
SELECT
    i.issue_rows AS zero_price_rows,
    100.0 * i.issue_rows / NULLIF(t.total_rows, 0) AS pct_of_loaded_rows
FROM (
    SELECT COUNT(*) AS issue_rows
    FROM raw.online_retail
    WHERE UnitPrice = 0
) AS i
CROSS JOIN (
    SELECT COUNT(*) AS total_rows
    FROM raw.online_retail
) AS t;

SELECT TOP (10)
    raw_row_id,
    InvoiceNo,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Country
FROM raw.online_retail
WHERE UnitPrice = 0
ORDER BY InvoiceDate, InvoiceNo, raw_row_id;

-- 3.7 Negative UnitPrice — count, %, examples
SELECT
    i.issue_rows AS negative_price_rows,
    100.0 * i.issue_rows / NULLIF(t.total_rows, 0) AS pct_of_loaded_rows
FROM (
    SELECT COUNT(*) AS issue_rows
    FROM raw.online_retail
    WHERE UnitPrice < 0
) AS i
CROSS JOIN (
    SELECT COUNT(*) AS total_rows
    FROM raw.online_retail
) AS t;

SELECT TOP (10)
    raw_row_id,
    InvoiceNo,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Country
FROM raw.online_retail
WHERE UnitPrice < 0
ORDER BY UnitPrice, InvoiceDate, raw_row_id;


-- =============================================================================
-- Phase 4 — Product, service and adjustment codes
-- Business purpose: find StockCodes that may be postage, fees, manuals or
-- other adjustments so Phase 3 value totals can be re-cut later.
-- Classifications in this phase are proposals only, not Silver rules.
-- Do not treat a code as non-product merely because it contains letters.
-- Value definitions (provisional, same as Phase 3):
--   gross_sales_value              = Quantity > 0 AND UnitPrice > 0
--   signed_negative_quantity_value = Quantity < 0 AND UnitPrice > 0
--   negative_price_value           = UnitPrice < 0
--   net_line_value                 = Quantity * UnitPrice
-- =============================================================================

-- 4.1 Seed candidate StockCodes (named list plus "Adjust bad debt" text)
-- Proposed labels are hypotheses for later review, not confirmed classes.
SELECT
    r.StockCode,
    CASE r.StockCode
        WHEN N'POST' THEN N'proposed_postage'
        WHEN N'DOT' THEN N'proposed_postage'
        WHEN N'D' THEN N'proposed_discount'
        WHEN N'M' THEN N'proposed_manual'
        WHEN N'CRUK' THEN N'proposed_commission_or_fee'
        WHEN N'BANK CHARGES' THEN N'proposed_bank_charges'
        WHEN N'AMAZONFEE' THEN N'proposed_amazon_fee'
        WHEN N'B' THEN N'proposed_bad_debt_adjustment'
        ELSE N'proposed_review'
    END AS proposed_classification,
    MIN(r.Description) AS sample_description_min,
    MAX(r.Description) AS sample_description_max,
    COUNT(*) AS line_count,
    COUNT(DISTINCT r.InvoiceNo) AS distinct_invoices,
    100.0 * COUNT(*) / NULLIF(MAX(t.total_rows), 0) AS pct_of_loaded_rows,
    SUM(CASE WHEN r.Quantity > 0 AND r.UnitPrice > 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS gross_sales_value,
    SUM(CASE WHEN r.Quantity < 0 AND r.UnitPrice > 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS signed_negative_quantity_value,
    SUM(CASE WHEN r.UnitPrice < 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS negative_price_value,
    SUM(r.Quantity * r.UnitPrice) AS net_line_value
FROM raw.online_retail AS r
CROSS JOIN (
    SELECT COUNT(*) AS total_rows FROM raw.online_retail
) AS t
WHERE r.StockCode IN (
        N'POST', N'D', N'M', N'DOT', N'CRUK', N'BANK CHARGES', N'AMAZONFEE', N'B'
    )
    OR r.Description LIKE N'%Adjust bad debt%'
GROUP BY r.StockCode
ORDER BY line_count DESC, r.StockCode;

-- 4.2 Quantity and UnitPrice sign breakdown for seed candidates
-- Percentages are of the full Raw table, not of the candidate subset.
SELECT
    r.StockCode,
    CASE
        WHEN r.Quantity < 0 THEN N'negative'
        WHEN r.Quantity = 0 THEN N'zero'
        ELSE N'positive'
    END AS quantity_sign,
    CASE
        WHEN r.UnitPrice < 0 THEN N'negative'
        WHEN r.UnitPrice = 0 THEN N'zero'
        ELSE N'positive'
    END AS unit_price_sign,
    COUNT(*) AS line_count,
    COUNT(DISTINCT r.InvoiceNo) AS distinct_invoices,
    100.0 * COUNT(*) / NULLIF(MAX(t.total_rows), 0) AS pct_of_loaded_rows
FROM raw.online_retail AS r
CROSS JOIN (
    SELECT COUNT(*) AS total_rows FROM raw.online_retail
) AS t
WHERE r.StockCode IN (
        N'POST', N'D', N'M', N'DOT', N'CRUK', N'BANK CHARGES', N'AMAZONFEE', N'B'
    )
    OR r.Description LIKE N'%Adjust bad debt%'
GROUP BY
    r.StockCode,
    CASE
        WHEN r.Quantity < 0 THEN N'negative'
        WHEN r.Quantity = 0 THEN N'zero'
        ELSE N'positive'
    END,
    CASE
        WHEN r.UnitPrice < 0 THEN N'negative'
        WHEN r.UnitPrice = 0 THEN N'zero'
        ELSE N'positive'
    END
ORDER BY r.StockCode, quantity_sign, unit_price_sign;

-- 4.3 Additional candidates from descriptions (exclude the seed StockCodes)
-- Discovery uses wording and observed values, not alphanumeric format.
SELECT
    r.StockCode,
    MIN(r.Description) AS sample_description_min,
    MAX(r.Description) AS sample_description_max,
    COUNT(*) AS line_count,
    COUNT(DISTINCT r.InvoiceNo) AS distinct_invoices,
    100.0 * COUNT(*) / NULLIF(MAX(t.total_rows), 0) AS pct_of_loaded_rows,
    SUM(CASE WHEN r.Quantity > 0 AND r.UnitPrice > 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS gross_sales_value,
    SUM(CASE WHEN r.Quantity < 0 AND r.UnitPrice > 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS signed_negative_quantity_value,
    SUM(CASE WHEN r.UnitPrice < 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS negative_price_value,
    SUM(r.Quantity * r.UnitPrice) AS net_line_value
FROM raw.online_retail AS r
CROSS JOIN (
    SELECT COUNT(*) AS total_rows FROM raw.online_retail
) AS t
WHERE r.StockCode NOT IN (
        N'POST', N'D', N'M', N'DOT', N'CRUK', N'BANK CHARGES', N'AMAZONFEE', N'B'
    )
  AND (
        UPPER(LTRIM(RTRIM(r.Description))) LIKE N'%POSTAGE%'
        OR UPPER(LTRIM(RTRIM(r.Description))) LIKE N'%MANUAL%'
        OR UPPER(LTRIM(RTRIM(r.Description))) LIKE N'%DISCOUNT%'
        OR UPPER(LTRIM(RTRIM(r.Description))) LIKE N'%AMAZON%'
        OR UPPER(LTRIM(RTRIM(r.Description))) LIKE N'%ADJUST%'
        OR UPPER(LTRIM(RTRIM(r.Description))) LIKE N'%BANK CHARGE%'
        OR UPPER(LTRIM(RTRIM(r.Description))) LIKE N'%DOTCOM%'
        OR UPPER(LTRIM(RTRIM(r.Description))) LIKE N'%CRUK%'
        OR UPPER(LTRIM(RTRIM(r.Description))) LIKE N'%GIFT%'
        OR UPPER(LTRIM(RTRIM(r.Description))) LIKE N'%CARRIAGE%'
        OR UPPER(LTRIM(RTRIM(r.Description))) LIKE N'%SAMPLES%'
    )
GROUP BY r.StockCode
ORDER BY ABS(SUM(r.Quantity * r.UnitPrice)) DESC, line_count DESC, r.StockCode;

-- 4.4 TOP (10) example lines per seed StockCode
SELECT
    e.raw_row_id,
    e.InvoiceNo,
    e.StockCode,
    e.Description,
    e.Quantity,
    e.InvoiceDate,
    e.UnitPrice,
    e.CustomerID,
    e.Country,
    e.Quantity * e.UnitPrice AS line_value
FROM (
    SELECT
        r.raw_row_id,
        r.InvoiceNo,
        r.StockCode,
        r.Description,
        r.Quantity,
        r.InvoiceDate,
        r.UnitPrice,
        r.CustomerID,
        r.Country,
        ROW_NUMBER() OVER (
            PARTITION BY r.StockCode
            ORDER BY r.InvoiceDate, r.InvoiceNo, r.raw_row_id
        ) AS example_rank
    FROM raw.online_retail AS r
    WHERE r.StockCode IN (
            N'POST', N'D', N'M', N'DOT', N'CRUK', N'BANK CHARGES', N'AMAZONFEE', N'B'
        )
        OR r.Description LIKE N'%Adjust bad debt%'
) AS e
WHERE e.example_rank <= 10
ORDER BY e.StockCode, e.InvoiceDate, e.InvoiceNo, e.raw_row_id;

-- 4.5 Table-level identity: net should equal gross + signed negative-qty
--     (positive price) + negative-price value. Zero-price lines add 0.
-- Do not hard-code Phase 3 totals; recompute from Raw.
SELECT
    SUM(CASE WHEN Quantity > 0 AND UnitPrice > 0 THEN Quantity * UnitPrice ELSE 0 END)
        AS gross_sales_value,
    SUM(CASE WHEN Quantity < 0 AND UnitPrice > 0 THEN Quantity * UnitPrice ELSE 0 END)
        AS signed_refund_value,
    SUM(CASE WHEN UnitPrice < 0 THEN Quantity * UnitPrice ELSE 0 END)
        AS negative_price_value,
    SUM(Quantity * UnitPrice) AS net_line_value,
    SUM(CASE WHEN Quantity > 0 AND UnitPrice > 0 THEN Quantity * UnitPrice ELSE 0 END)
        + SUM(CASE WHEN Quantity < 0 AND UnitPrice > 0 THEN Quantity * UnitPrice ELSE 0 END)
        + SUM(CASE WHEN UnitPrice < 0 THEN Quantity * UnitPrice ELSE 0 END)
        AS reconstructed_net_line_value,
    SUM(Quantity * UnitPrice)
        - (
            SUM(CASE WHEN Quantity > 0 AND UnitPrice > 0 THEN Quantity * UnitPrice ELSE 0 END)
            + SUM(CASE WHEN Quantity < 0 AND UnitPrice > 0 THEN Quantity * UnitPrice ELSE 0 END)
            + SUM(CASE WHEN UnitPrice < 0 THEN Quantity * UnitPrice ELSE 0 END)
        ) AS identity_difference
FROM raw.online_retail;

-- 4.6 Negative-price lines vs "Adjust bad debt" (computed, not hard-coded)
SELECT
    np.negative_price_line_count,
    np.negative_price_value,
    adj.adjust_bad_debt_line_count,
    adj.adjust_bad_debt_value,
    np.negative_price_value - adj.adjust_bad_debt_value AS negative_price_minus_adjust_bad_debt
FROM (
    SELECT
        COUNT(*) AS negative_price_line_count,
        SUM(Quantity * UnitPrice) AS negative_price_value
    FROM raw.online_retail
    WHERE UnitPrice < 0
) AS np
CROSS JOIN (
    SELECT
        COUNT(*) AS adjust_bad_debt_line_count,
        SUM(Quantity * UnitPrice) AS adjust_bad_debt_value
    FROM raw.online_retail
    WHERE Description LIKE N'%Adjust bad debt%'
) AS adj;


-- =============================================================================
-- Phase 5 — Duplicates and invoice consistency
-- Business purpose: measure exact and near-duplicate lines and invoice-key
-- consistency. Do not delete or collapse any records.
-- Exact duplicates use the eight original business columns only
-- (InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice,
-- CustomerID, Country). raw_row_id, source_file and loaded_at are excluded.
-- Text equality follows each column's collation (typically case-insensitive
-- on SQL Server). 'POST' and 'post' would match under CI collation.
-- =============================================================================

-- 5.1 Collation of text business columns (read-only catalog)
SELECT
    c.name AS column_name,
    c.collation_name,
    DATABASEPROPERTYEX(DB_NAME(), 'Collation') AS database_collation
FROM sys.columns AS c
INNER JOIN sys.tables AS t
    ON c.object_id = t.object_id
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = N'raw'
  AND t.name = N'online_retail'
  AND c.name IN (
        N'InvoiceNo', N'StockCode', N'Description', N'CustomerID', N'Country'
    )
ORDER BY c.column_id;

-- 5.2 Exact duplicate groups (eight business columns)
SELECT
    g.duplicate_group_count,
    g.rows_in_duplicate_groups,
    g.extra_rows_beyond_first,
    100.0 * g.rows_in_duplicate_groups / NULLIF(t.total_rows, 0)
        AS pct_rows_in_duplicate_groups,
    100.0 * g.extra_rows_beyond_first / NULLIF(t.total_rows, 0)
        AS pct_extra_rows_beyond_first
FROM (
    SELECT
        COUNT(*) AS duplicate_group_count,
        ISNULL(SUM(rows_in_group), 0) AS rows_in_duplicate_groups,
        ISNULL(SUM(rows_in_group - 1), 0) AS extra_rows_beyond_first
    FROM (
        SELECT COUNT(*) AS rows_in_group
        FROM raw.online_retail
        GROUP BY
            InvoiceNo,
            StockCode,
            Description,
            Quantity,
            InvoiceDate,
            UnitPrice,
            CustomerID,
            Country
        HAVING COUNT(*) > 1
    ) AS dup_groups
) AS g
CROSS JOIN (
    SELECT COUNT(*) AS total_rows FROM raw.online_retail
) AS t;

-- 5.3 Example exact-duplicate groups with raw_row_ids
SELECT TOP (10)
    d.InvoiceNo,
    d.StockCode,
    d.Description,
    d.Quantity,
    d.InvoiceDate,
    d.UnitPrice,
    d.CustomerID,
    d.Country,
    d.rows_in_group,
    d.raw_row_ids
FROM (
    SELECT
        InvoiceNo,
        StockCode,
        Description,
        Quantity,
        InvoiceDate,
        UnitPrice,
        CustomerID,
        Country,
        COUNT(*) AS rows_in_group,
        STRING_AGG(CAST(raw_row_id AS nvarchar(max)), N',')
            WITHIN GROUP (ORDER BY raw_row_id) AS raw_row_ids
    FROM raw.online_retail
    GROUP BY
        InvoiceNo,
        StockCode,
        Description,
        Quantity,
        InvoiceDate,
        UnitPrice,
        CustomerID,
        Country
    HAVING COUNT(*) > 1
) AS d
ORDER BY d.rows_in_group DESC, d.InvoiceNo, d.StockCode, d.InvoiceDate;

-- 5.4 Repeated (InvoiceNo, StockCode, Quantity, UnitPrice, CustomerID)
-- Potential duplicates only; Description/InvoiceDate/Country may still differ.
SELECT
    g.repeat_group_count,
    g.rows_in_repeat_groups,
    g.extra_rows_beyond_first,
    100.0 * g.rows_in_repeat_groups / NULLIF(t.total_rows, 0)
        AS pct_rows_in_repeat_groups
FROM (
    SELECT
        COUNT(*) AS repeat_group_count,
        ISNULL(SUM(rows_in_group), 0) AS rows_in_repeat_groups,
        ISNULL(SUM(rows_in_group - 1), 0) AS extra_rows_beyond_first
    FROM (
        SELECT COUNT(*) AS rows_in_group
        FROM raw.online_retail
        GROUP BY InvoiceNo, StockCode, Quantity, UnitPrice, CustomerID
        HAVING COUNT(*) > 1
    ) AS rpt
) AS g
CROSS JOIN (
    SELECT COUNT(*) AS total_rows FROM raw.online_retail
) AS t;

-- 5.5 Example potential-duplicate groups (five-column key)
SELECT TOP (10)
    d.InvoiceNo,
    d.StockCode,
    d.Quantity,
    d.UnitPrice,
    d.CustomerID,
    d.rows_in_group,
    d.distinct_descriptions,
    d.distinct_invoice_dates,
    d.raw_row_ids
FROM (
    SELECT
        InvoiceNo,
        StockCode,
        Quantity,
        UnitPrice,
        CustomerID,
        COUNT(*) AS rows_in_group,
        COUNT(DISTINCT Description) AS distinct_descriptions,
        COUNT(DISTINCT InvoiceDate) AS distinct_invoice_dates,
        STRING_AGG(CAST(raw_row_id AS nvarchar(max)), N',')
            WITHIN GROUP (ORDER BY raw_row_id) AS raw_row_ids
    FROM raw.online_retail
    GROUP BY InvoiceNo, StockCode, Quantity, UnitPrice, CustomerID
    HAVING COUNT(*) > 1
) AS d
ORDER BY d.rows_in_group DESC, d.InvoiceNo, d.StockCode;

-- 5.6 StockCodes with more than one distinct Description
SELECT
    i.stock_codes_with_multiple_descriptions,
    100.0 * i.stock_codes_with_multiple_descriptions
        / NULLIF(c.distinct_stock_codes, 0) AS pct_of_distinct_stock_codes
FROM (
    SELECT COUNT(*) AS stock_codes_with_multiple_descriptions
    FROM (
        SELECT StockCode
        FROM raw.online_retail
        GROUP BY StockCode
        HAVING COUNT(DISTINCT Description) > 1
    ) AS multi
) AS i
CROSS JOIN (
    SELECT COUNT(DISTINCT StockCode) AS distinct_stock_codes
    FROM raw.online_retail
) AS c;

-- 5.7 Example StockCodes with description drift
SELECT TOP (10)
    StockCode,
    COUNT(DISTINCT Description) AS distinct_description_count,
    COUNT(*) AS line_count,
    MIN(Description) AS sample_description_min,
    MAX(Description) AS sample_description_max
FROM raw.online_retail
GROUP BY StockCode
HAVING COUNT(DISTINCT Description) > 1
ORDER BY COUNT(DISTINCT Description) DESC, line_count DESC, StockCode;

-- 5.8 Invoices with more than one non-null CustomerID
-- COUNT(DISTINCT CustomerID) ignores NULL, so this is non-null keys only.
SELECT
    i.invoice_count,
    i.line_count,
    100.0 * i.invoice_count / NULLIF(d.distinct_invoices, 0) AS pct_of_invoices
FROM (
    SELECT
        COUNT(*) AS invoice_count,
        ISNULL(SUM(line_count), 0) AS line_count
    FROM (
        SELECT InvoiceNo, COUNT(*) AS line_count
        FROM raw.online_retail
        WHERE CustomerID IS NOT NULL
        GROUP BY InvoiceNo
        HAVING COUNT(DISTINCT CustomerID) > 1
    ) AS mixed
) AS i
CROSS JOIN (
    SELECT COUNT(DISTINCT InvoiceNo) AS distinct_invoices
    FROM raw.online_retail
) AS d;

-- 5.9 Invoices with both null and non-null CustomerID (separate from 5.8)
SELECT
    i.invoice_count,
    i.line_count,
    100.0 * i.invoice_count / NULLIF(d.distinct_invoices, 0) AS pct_of_invoices
FROM (
    SELECT
        COUNT(*) AS invoice_count,
        ISNULL(SUM(line_count), 0) AS line_count
    FROM (
        SELECT InvoiceNo, COUNT(*) AS line_count
        FROM raw.online_retail
        GROUP BY InvoiceNo
        HAVING SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) > 0
           AND SUM(CASE WHEN CustomerID IS NOT NULL THEN 1 ELSE 0 END) > 0
    ) AS mixed_null
) AS i
CROSS JOIN (
    SELECT COUNT(DISTINCT InvoiceNo) AS distinct_invoices
    FROM raw.online_retail
) AS d;

SELECT TOP (10)
    m.InvoiceNo,
    m.line_count,
    m.null_customer_lines,
    m.identified_customer_lines,
    m.raw_row_ids
FROM (
    SELECT
        InvoiceNo,
        COUNT(*) AS line_count,
        SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) AS null_customer_lines,
        SUM(CASE WHEN CustomerID IS NOT NULL THEN 1 ELSE 0 END) AS identified_customer_lines,
        STRING_AGG(CAST(raw_row_id AS nvarchar(max)), N',')
            WITHIN GROUP (ORDER BY raw_row_id) AS raw_row_ids
    FROM raw.online_retail
    GROUP BY InvoiceNo
    HAVING SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) > 0
       AND SUM(CASE WHEN CustomerID IS NOT NULL THEN 1 ELSE 0 END) > 0
) AS m
ORDER BY m.line_count DESC, m.InvoiceNo;

-- 5.10 Invoices with more than one Country
SELECT
    i.invoice_count,
    i.line_count,
    100.0 * i.invoice_count / NULLIF(d.distinct_invoices, 0) AS pct_of_invoices
FROM (
    SELECT
        COUNT(*) AS invoice_count,
        ISNULL(SUM(line_count), 0) AS line_count
    FROM (
        SELECT InvoiceNo, COUNT(*) AS line_count
        FROM raw.online_retail
        GROUP BY InvoiceNo
        HAVING COUNT(DISTINCT Country) > 1
    ) AS mixed
) AS i
CROSS JOIN (
    SELECT COUNT(DISTINCT InvoiceNo) AS distinct_invoices
    FROM raw.online_retail
) AS d;

SELECT TOP (10)
    m.InvoiceNo,
    m.distinct_countries,
    m.line_count,
    m.raw_row_ids
FROM (
    SELECT
        InvoiceNo,
        COUNT(DISTINCT Country) AS distinct_countries,
        COUNT(*) AS line_count,
        STRING_AGG(CAST(raw_row_id AS nvarchar(max)), N',')
            WITHIN GROUP (ORDER BY raw_row_id) AS raw_row_ids
    FROM raw.online_retail
    GROUP BY InvoiceNo
    HAVING COUNT(DISTINCT Country) > 1
) AS m
ORDER BY m.line_count DESC, m.InvoiceNo;

-- 5.11 Invoices with more than one InvoiceDate
SELECT
    i.invoice_count,
    i.line_count,
    100.0 * i.invoice_count / NULLIF(d.distinct_invoices, 0) AS pct_of_invoices
FROM (
    SELECT
        COUNT(*) AS invoice_count,
        ISNULL(SUM(line_count), 0) AS line_count
    FROM (
        SELECT InvoiceNo, COUNT(*) AS line_count
        FROM raw.online_retail
        GROUP BY InvoiceNo
        HAVING COUNT(DISTINCT InvoiceDate) > 1
    ) AS mixed
) AS i
CROSS JOIN (
    SELECT COUNT(DISTINCT InvoiceNo) AS distinct_invoices
    FROM raw.online_retail
) AS d;

SELECT TOP (10)
    m.InvoiceNo,
    m.distinct_invoice_dates,
    m.min_invoice_date,
    m.max_invoice_date,
    m.line_count,
    m.raw_row_ids
FROM (
    SELECT
        InvoiceNo,
        COUNT(DISTINCT InvoiceDate) AS distinct_invoice_dates,
        MIN(InvoiceDate) AS min_invoice_date,
        MAX(InvoiceDate) AS max_invoice_date,
        COUNT(*) AS line_count,
        STRING_AGG(CAST(raw_row_id AS nvarchar(max)), N',')
            WITHIN GROUP (ORDER BY raw_row_id) AS raw_row_ids
    FROM raw.online_retail
    GROUP BY InvoiceNo
    HAVING COUNT(DISTINCT InvoiceDate) > 1
) AS m
ORDER BY m.line_count DESC, m.InvoiceNo;


-- =============================================================================
-- Phase 6 — Time and geography
-- Business purpose: monthly coverage and country mix for later RFM/sales.
-- Values remain provisional until Phase 4 classifications are approved.
-- Flag the calendar month that contains the extract's last timestamp as
-- potentially incomplete (dataset ends 2011-12-09). A missing last calendar
-- day alone does not prove incompleteness.
-- =============================================================================

-- 6.1 Calendar month (line counts vs distinct invoices vs identified customers)
SELECT
    YEAR(r.InvoiceDate) AS invoice_year,
    MONTH(r.InvoiceDate) AS invoice_month,
    MIN(r.InvoiceDate) AS min_invoice_date_in_month,
    MAX(r.InvoiceDate) AS max_invoice_date_in_month,
    CASE
        WHEN YEAR(r.InvoiceDate) = YEAR(mx.max_invoice_date)
         AND MONTH(r.InvoiceDate) = MONTH(mx.max_invoice_date)
            THEN N'potentially_incomplete_final_month'
        ELSE N'observed_month'
    END AS month_completeness_flag,
    COUNT(*) AS line_count,
    COUNT(DISTINCT r.InvoiceNo) AS distinct_invoices,
    COUNT(DISTINCT r.CustomerID) AS identified_customers,
    100.0 * COUNT(*) / NULLIF(MAX(t.total_rows), 0) AS pct_of_loaded_rows,
    SUM(CASE WHEN r.Quantity > 0 AND r.UnitPrice > 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS gross_sales_value,
    SUM(CASE WHEN r.Quantity < 0 AND r.UnitPrice > 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS signed_negative_quantity_value,
    SUM(CASE WHEN r.UnitPrice < 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS negative_price_value,
    SUM(r.Quantity * r.UnitPrice) AS net_line_value
FROM raw.online_retail AS r
CROSS JOIN (
    SELECT COUNT(*) AS total_rows FROM raw.online_retail
) AS t
CROSS JOIN (
    SELECT MAX(InvoiceDate) AS max_invoice_date FROM raw.online_retail
) AS mx
GROUP BY
    YEAR(r.InvoiceDate),
    MONTH(r.InvoiceDate),
    CASE
        WHEN YEAR(r.InvoiceDate) = YEAR(mx.max_invoice_date)
         AND MONTH(r.InvoiceDate) = MONTH(mx.max_invoice_date)
            THEN N'potentially_incomplete_final_month'
        ELSE N'observed_month'
    END
ORDER BY invoice_year, invoice_month;

-- 6.2 Country-level activity and provisional value
SELECT
    r.Country,
    COUNT(*) AS line_count,
    COUNT(DISTINCT r.InvoiceNo) AS distinct_invoices,
    COUNT(DISTINCT r.CustomerID) AS identified_customers,
    100.0 * COUNT(*) / NULLIF(MAX(t.total_rows), 0) AS pct_of_loaded_rows,
    SUM(CASE WHEN r.Quantity > 0 AND r.UnitPrice > 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS gross_sales_value,
    SUM(CASE WHEN r.Quantity < 0 AND r.UnitPrice > 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS signed_negative_quantity_value,
    SUM(CASE WHEN r.UnitPrice < 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS negative_price_value,
    SUM(r.Quantity * r.UnitPrice) AS net_line_value,
    100.0 * SUM(r.Quantity * r.UnitPrice)
        / NULLIF(MAX(t.total_net_line_value), 0) AS pct_of_net_line_value
FROM raw.online_retail AS r
CROSS JOIN (
    SELECT
        COUNT(*) AS total_rows,
        SUM(Quantity * UnitPrice) AS total_net_line_value
    FROM raw.online_retail
) AS t
GROUP BY r.Country
ORDER BY SUM(r.Quantity * UnitPrice) DESC, line_count DESC, r.Country;

-- 6.3 United Kingdom vs other countries
SELECT
    CASE
        WHEN r.Country = N'United Kingdom' THEN N'United Kingdom'
        ELSE N'non_UK'
    END AS country_group,
    COUNT(*) AS line_count,
    COUNT(DISTINCT r.InvoiceNo) AS distinct_invoices,
    COUNT(DISTINCT r.CustomerID) AS identified_customers,
    100.0 * COUNT(*) / NULLIF(MAX(t.total_rows), 0) AS pct_of_loaded_rows,
    SUM(CASE WHEN r.Quantity > 0 AND r.UnitPrice > 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS gross_sales_value,
    SUM(CASE WHEN r.Quantity < 0 AND r.UnitPrice > 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS signed_negative_quantity_value,
    SUM(CASE WHEN r.UnitPrice < 0 THEN r.Quantity * r.UnitPrice ELSE 0 END)
        AS negative_price_value,
    SUM(r.Quantity * r.UnitPrice) AS net_line_value,
    100.0 * SUM(r.Quantity * r.UnitPrice)
        / NULLIF(MAX(t.total_net_line_value), 0) AS pct_of_net_line_value
FROM raw.online_retail AS r
CROSS JOIN (
    SELECT
        COUNT(*) AS total_rows,
        SUM(Quantity * UnitPrice) AS total_net_line_value
    FROM raw.online_retail
) AS t
GROUP BY
    CASE
        WHEN r.Country = N'United Kingdom' THEN N'United Kingdom'
        ELSE N'non_UK'
    END
ORDER BY country_group;
