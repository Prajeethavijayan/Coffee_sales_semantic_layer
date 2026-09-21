-- Coffee Shop Semantic Layer
-- Run from Terminal with:
-- ~/.duckdb/cli/latest/duckdb coffee_shop.duckdb < semantic_layer.sql

-- ============================================================
-- 1. RAW TABLES
-- These preserve the CSV fields as text.
-- ============================================================

CREATE OR REPLACE TABLE customers_raw AS
SELECT *
FROM read_csv(
    '/Users/prajeethavijayan/Desktop/Prajeetha/projects - prac/coffee sales/walkin_case_study_analytics_consultant/learning semantic layer/customer_level_data_cleaned.csv',
    header = true,
    all_varchar = true
);

CREATE OR REPLACE TABLE transactions_raw AS
SELECT *
FROM read_csv(
    '/Users/prajeethavijayan/Desktop/Prajeetha/projects - prac/coffee sales/walkin_case_study_analytics_consultant/learning semantic layer/transaction_level_data_cleaned.csv',
    header = true,
    all_varchar = true
);

CREATE OR REPLACE TABLE items_raw AS
SELECT *
FROM read_csv(
    '/Users/prajeethavijayan/Desktop/Prajeetha/projects - prac/coffee sales/walkin_case_study_analytics_consultant/learning semantic layer/item_level_data_cleaned.csv',
    header = true,
    all_varchar = true
);

-- ============================================================
-- 2. CLEAN SEMANTIC VIEWS
-- ============================================================

CREATE OR REPLACE VIEW customers_clean AS
WITH parsed AS (
    SELECT
        CAST(customer_number AS INTEGER) AS customer_number,
        COALESCE(
            TRY_STRPTIME(app_install_time, '%Y-%m-%d %H:%M:%S'),
            TRY_STRPTIME(app_install_time, '%m/%d/%y %H:%M')
        ) AS app_install_timestamp,
        NULLIF(UPPER(TRIM(gender)), 'NA') AS gender,
        NULLIF(UPPER(TRIM(marital_status)), 'NA') AS marital_status,
        CAST(
            TRY_STRPTIME(
                NULLIF(NULLIF(TRIM(date_of_birth), '1900-01-00'), '0000-00-00'),
                '%Y-%m-%d'
            ) AS DATE
        ) AS date_of_birth,
        referral_as_source_of_app_install = 'Installed_through_referral'
            AS installed_through_referral
    FROM customers_raw
)
SELECT
    customer_number,
    app_install_timestamp,
    CAST(app_install_timestamp AS DATE) AS app_install_date,
    gender,
    marital_status,
    date_of_birth,
    installed_through_referral
FROM parsed;

CREATE OR REPLACE VIEW transactions_clean AS
WITH parsed AS (
    SELECT
        CAST(transaction_number AS INTEGER) AS transaction_number,
        CAST(customer_number AS INTEGER) AS customer_number,
        TRY_STRPTIME(transaction_time, '%Y-%m-%d %H:%M:%S')
            AS transaction_timestamp,
        UPPER(TRIM(store_name)) AS store_name,
        CAST(sale_amount_including_loyalty_points_used AS DECIMAL(12,2))
            AS gross_sale_amount,
        CAST(loyalty_points_used_by_customer AS DECIMAL(12,2))
            AS loyalty_points_used,
        NULLIF(TRIM(offer_used_by_customer_to_earn_loyalty_points), 'NA')
            AS offer_name
    FROM transactions_raw
)
SELECT
    transaction_number,
    customer_number,
    transaction_timestamp,
    CAST(transaction_timestamp AS DATE) AS transaction_date,
    DATE_TRUNC('month', transaction_timestamp) AS transaction_month,
    EXTRACT(HOUR FROM transaction_timestamp) AS transaction_hour,
    DAYNAME(transaction_timestamp) AS day_of_week,
    store_name,
    REGEXP_REPLACE(store_name, ' STORE [0-9]+$', '') AS store_city,
    gross_sale_amount,
    loyalty_points_used,
    gross_sale_amount - loyalty_points_used AS cash_or_digital_paid,
    offer_name IS NOT NULL AS offer_used,
    offer_name
FROM parsed;

CREATE OR REPLACE VIEW items_clean AS
SELECT
    CAST(transaction_number AS INTEGER) AS transaction_number,
    CAST(customer_number AS INTEGER) AS customer_number,
    item_name AS item_name_raw,
    CASE
        WHEN COALESCE(UPPER(TRIM(item_name)), '') IN
            ('', 'NA', '#N/A', 'N/A', 'MISCELLANEOUS')
        THEN NULL
        ELSE UPPER(TRIM(item_name))
    END AS item_name,
    COALESCE(UPPER(TRIM(item_name)), '') IN
        ('', 'NA', '#N/A', 'N/A', 'MISCELLANEOUS') AS unknown_item,
    CAST(sale_amount AS DECIMAL(12,2)) AS item_sale_amount
FROM items_raw;

-- ============================================================
-- 3. BUSINESS METRIC VIEWS
-- ============================================================

CREATE OR REPLACE VIEW monthly_business_performance AS
WITH customer_month AS (
    SELECT
        transaction_month,
        customer_number,
        COUNT(*) AS customer_transactions,
        SUM(gross_sale_amount) AS customer_sales
    FROM transactions_clean
    GROUP BY transaction_month, customer_number
)
SELECT
    transaction_month,
    SUM(customer_sales) AS total_sales,
    SUM(customer_transactions) AS transactions,
    COUNT(*) AS active_customers,
    ROUND(SUM(customer_sales) / SUM(customer_transactions), 2)
        AS average_transaction_value,
    COUNT(*) FILTER (WHERE customer_transactions >= 2) AS repeat_customers,
    ROUND(
        COUNT(*) FILTER (WHERE customer_transactions >= 2)
        * 100.0 / COUNT(*),
        2
    ) AS repeat_customer_rate_pct
FROM customer_month
GROUP BY transaction_month
ORDER BY transaction_month;

CREATE OR REPLACE VIEW customer_activity AS
WITH transaction_summary AS (
    SELECT
        customer_number,
        MIN(transaction_timestamp) AS first_purchase_timestamp,
        MAX(transaction_timestamp) AS last_purchase_timestamp,
        COUNT(*) AS transaction_count,
        SUM(gross_sale_amount) AS lifetime_sales,
        ROUND(AVG(gross_sale_amount), 2) AS average_transaction_value,
        SUM(loyalty_points_used) AS lifetime_points_used,
        COUNT(*) FILTER (WHERE offer_used) AS offer_transactions
    FROM transactions_clean
    GROUP BY customer_number
)
SELECT
    c.customer_number,
    c.app_install_timestamp,
    c.app_install_date,
    c.gender,
    c.marital_status,
    c.date_of_birth,
    c.installed_through_referral,
    t.first_purchase_timestamp,
    t.last_purchase_timestamp,
    COALESCE(t.transaction_count, 0) AS transaction_count,
    COALESCE(t.lifetime_sales, 0) AS lifetime_sales,
    COALESCE(t.average_transaction_value, 0) AS average_transaction_value,
    COALESCE(t.lifetime_points_used, 0) AS lifetime_points_used,
    COALESCE(t.offer_transactions, 0) AS offer_transactions,
    t.customer_number IS NOT NULL AS is_active_customer,
    COALESCE(t.transaction_count, 0) >= 2 AS is_repeat_customer
FROM customers_clean c
LEFT JOIN transaction_summary t
    ON c.customer_number = t.customer_number;

CREATE OR REPLACE VIEW product_performance AS
SELECT
    CASE
        WHEN COALESCE(UPPER(TRIM(item_name_raw)), '') IN ('', 'NA', '#N/A', 'N/A')
            THEN 'UNKNOWN_ITEM'
        WHEN UPPER(TRIM(item_name_raw)) = 'MISCELLANEOUS'
            THEN 'MISCELLANEOUS'
        ELSE item_name
    END AS product_name,
    COUNT(*) AS item_records,
    COUNT(DISTINCT transaction_number) AS transactions,
    COUNT(DISTINCT customer_number) AS customers,
    SUM(item_sale_amount) AS product_sales,
    ROUND(AVG(item_sale_amount), 2) AS average_item_record_value
FROM items_clean
GROUP BY 1;

CREATE OR REPLACE VIEW store_performance AS
SELECT
    store_name,
    store_city,
    COUNT(*) AS transactions,
    COUNT(DISTINCT customer_number) AS customers,
    SUM(gross_sale_amount) AS total_sales,
    ROUND(AVG(gross_sale_amount), 2) AS average_transaction_value,
    SUM(loyalty_points_used) AS loyalty_points_used,
    ROUND(
        COUNT(*) FILTER (WHERE offer_used) * 100.0 / COUNT(*),
        2
    ) AS offer_usage_rate_pct
FROM transactions_clean
GROUP BY store_name, store_city;

CREATE OR REPLACE VIEW offer_performance AS
SELECT
    CASE
        WHEN offer_name IS NULL THEN 'NO_OFFER'
        WHEN UPPER(offer_name) LIKE '%FREE%' THEN 'FREE_ITEM'
        WHEN STRPOS(offer_name, '%') > 0
          OR UPPER(offer_name) LIKE '%CASHBACK%'
            THEN 'PERCENT_CASHBACK'
        WHEN UPPER(offer_name) LIKE '%LOYALTY POINT%'
            THEN 'FIXED_POINTS'
        ELSE 'OTHER_OFFER'
    END AS offer_type,
    COUNT(*) AS transactions,
    COUNT(DISTINCT customer_number) AS customers,
    SUM(gross_sale_amount) AS total_sales,
    ROUND(AVG(gross_sale_amount), 2) AS average_transaction_value,
    SUM(loyalty_points_used) AS loyalty_points_redeemed,
    ROUND(
        SUM(loyalty_points_used) * 100.0
        / NULLIF(SUM(gross_sale_amount), 0),
        2
    ) AS points_share_of_sales_pct
FROM transactions_clean
GROUP BY 1;

-- ============================================================
-- 4. METRIC DICTIONARY
-- ============================================================

CREATE OR REPLACE TABLE metric_definitions (
    metric_name VARCHAR,
    description VARCHAR,
    source_view VARCHAR,
    calculation VARCHAR,
    grain VARCHAR
);

INSERT INTO metric_definitions VALUES
('total_sales',
 'Total purchase value including loyalty points redeemed',
 'transactions_clean', 'SUM(gross_sale_amount)', 'Selected reporting period'),
('transactions',
 'Number of completed purchase transactions',
 'transactions_clean', 'COUNT(*)', 'Selected reporting period'),
('active_customers',
 'Customers completing at least one purchase',
 'transactions_clean', 'COUNT(DISTINCT customer_number)', 'Selected reporting period'),
('average_transaction_value',
 'Average purchase value per transaction',
 'transactions_clean', 'SUM(gross_sale_amount) / COUNT(*)', 'Selected reporting period'),
('repeat_customer_rate',
 'Percentage of active customers with at least two purchases in the selected period',
 'monthly_business_performance',
 'repeat_customers * 100.0 / active_customers', 'Calendar month'),
('loyalty_points_redeemed',
 'Total loyalty-point value used as payment',
 'transactions_clean', 'SUM(loyalty_points_used)', 'Selected reporting period'),
('offer_usage_rate',
 'Percentage of transactions where an earning offer was used',
 'transactions_clean',
 'COUNT(*) FILTER (WHERE offer_used) * 100.0 / COUNT(*)',
 'Selected reporting period');

-- ============================================================
-- 5. VALIDATION OUTPUT
-- Expected counts: 10,767 customers; 17,164 transactions;
-- 17,972 item records. Expected sales: 4,905,720.50.
-- ============================================================

SELECT
    (SELECT COUNT(*) FROM customers_raw) AS raw_customers,
    (SELECT COUNT(*) FROM customers_clean) AS clean_customers,
    (SELECT COUNT(*) FROM transactions_raw) AS raw_transactions,
    (SELECT COUNT(*) FROM transactions_clean) AS clean_transactions,
    (SELECT COUNT(*) FROM items_raw) AS raw_items,
    (SELECT COUNT(*) FROM items_clean) AS clean_items,
    (SELECT SUM(gross_sale_amount) FROM transactions_clean) AS transaction_sales,
    (SELECT SUM(item_sale_amount) FROM items_clean) AS item_sales;

SELECT * FROM monthly_business_performance;

