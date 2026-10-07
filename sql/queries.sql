-- =====================================================================================
-- PROJECT 1: LOAN DEFAULT RISK  |  SQL ANALYSIS
-- Dialect: SQLite (runs anywhere). Syntax is standard - works in PostgreSQL/MySQL 8+
-- with tiny changes (noted inline).
--
-- `loans_v` is a VIEW over the raw `loans` table that adds:
--     is_default = 1 if loan_status = 'Charged Off' else 0
--     issue_year / issue_quarter extracted from issue_date
--
-- Each query starts with "-- name:" so run_sql.py can execute and export them one by one.
-- =====================================================================================


-- name: 01_portfolio_kpis
-- question: What does the overall portfolio look like?
SELECT
    COUNT(*)                                            AS total_loans,
    ROUND(SUM(loan_amount) / 1e6, 2)                    AS total_disbursed_mn,
    ROUND(AVG(int_rate), 2)                             AS avg_interest_rate_pct,
    ROUND(100.0 * AVG(is_default), 2)                   AS default_rate_pct,
    ROUND(SUM(CASE WHEN is_default = 1 THEN loan_amount END) / 1e6, 2) AS defaulted_amount_mn,
    ROUND(SUM(total_payment - loan_amount) / 1e6, 2)    AS net_profit_mn
FROM loans_v;


-- name: 02_default_rate_by_grade
-- question: Does the lender's grade actually rank risk correctly?
SELECT
    grade,
    COUNT(*)                                  AS loans,
    ROUND(AVG(int_rate), 2)                   AS avg_int_rate,
    ROUND(100.0 * AVG(is_default), 2)         AS default_rate_pct,
    ROUND(AVG(total_payment - loan_amount), 0) AS avg_profit_per_loan
FROM loans_v
GROUP BY grade
ORDER BY grade;


-- name: 03_default_rate_by_dti_band
-- question: How does debt-to-income (DTI) relate to default? (CASE WHEN banding)
SELECT
    CASE
        WHEN dti < 10 THEN '1) <10'
        WHEN dti < 20 THEN '2) 10-20'
        WHEN dti < 30 THEN '3) 20-30'
        ELSE               '4) 30+'
    END                                       AS dti_band,
    COUNT(*)                                  AS loans,
    ROUND(100.0 * AVG(is_default), 2)         AS default_rate_pct
FROM loans_v
GROUP BY dti_band
ORDER BY dti_band;


-- name: 04_default_rate_by_purpose
-- question: Which loan purposes are riskiest? (HAVING filters out tiny groups)
SELECT
    purpose,
    COUNT(*)                                  AS loans,
    ROUND(100.0 * AVG(is_default), 2)         AS default_rate_pct,
    ROUND(SUM(CASE WHEN is_default = 1 THEN loan_amount END) / 1e6, 2) AS defaulted_amount_mn
FROM loans_v
GROUP BY purpose
HAVING COUNT(*) >= 500
ORDER BY default_rate_pct DESC;


-- name: 05_state_risk_ranking
-- question: Rank states by default rate (window function RANK)
WITH state_stats AS (
    SELECT
        state,
        COUNT(*)                          AS loans,
        AVG(is_default)                   AS default_rate
    FROM loans_v
    GROUP BY state
)
SELECT
    state,
    loans,
    ROUND(100 * default_rate, 2)                              AS default_rate_pct,
    RANK() OVER (ORDER BY default_rate DESC)                  AS risk_rank,
    ROUND(100 * (default_rate - (SELECT AVG(is_default) FROM loans_v)), 2) AS gap_vs_portfolio_pp
FROM state_stats
ORDER BY risk_rank;


-- name: 06_vintage_analysis_yearly
-- question: Is underwriting quality getting better or worse? (LAG for year-over-year change)
WITH yearly AS (
    SELECT
        issue_year,
        COUNT(*)                          AS loans,
        ROUND(SUM(loan_amount) / 1e6, 2)  AS disbursed_mn,
        100.0 * AVG(is_default)           AS default_rate_pct
    FROM loans_v
    GROUP BY issue_year
)
SELECT
    issue_year,
    loans,
    disbursed_mn,
    ROUND(default_rate_pct, 2)                                         AS default_rate_pct,
    ROUND(default_rate_pct - LAG(default_rate_pct) OVER (ORDER BY issue_year), 2) AS yoy_change_pp
FROM yearly
ORDER BY issue_year;


-- name: 07_cumulative_disbursement
-- question: Running total of money lent per quarter (SUM() OVER running total)
WITH quarterly AS (
    SELECT
        issue_year,
        issue_quarter,
        SUM(loan_amount) AS disbursed
    FROM loans_v
    GROUP BY issue_year, issue_quarter
)
SELECT
    issue_year || '-Q' || issue_quarter                                        AS quarter,
    ROUND(disbursed / 1e6, 2)                                                  AS disbursed_mn,
    ROUND(SUM(disbursed) OVER (ORDER BY issue_year, issue_quarter) / 1e6, 2)   AS cumulative_mn
FROM quarterly
ORDER BY issue_year, issue_quarter;


-- name: 08_grade_by_term_matrix
-- question: Do 60-month loans hurt more in the weaker grades? (two-way segmentation)
SELECT
    grade,
    ROUND(100.0 * AVG(CASE WHEN term_months = 36 THEN is_default END), 2) AS default_pct_36m,
    ROUND(100.0 * AVG(CASE WHEN term_months = 60 THEN is_default END), 2) AS default_pct_60m,
    COUNT(CASE WHEN term_months = 60 THEN 1 END)                          AS loans_60m
FROM loans_v
GROUP BY grade
ORDER BY grade;


-- name: 09_interest_rate_deciles
-- question: Is the lender being paid enough for risk? (NTILE deciles of interest rate)
WITH ranked AS (
    SELECT
        loan_id, is_default, int_rate, total_payment, loan_amount,
        NTILE(10) OVER (ORDER BY int_rate) AS rate_decile
    FROM loans_v
)
SELECT
    rate_decile,
    ROUND(MIN(int_rate), 1)                      AS min_rate,
    ROUND(MAX(int_rate), 1)                      AS max_rate,
    ROUND(100.0 * AVG(is_default), 2)            AS default_rate_pct,
    ROUND(AVG(total_payment - loan_amount), 0)   AS avg_profit_per_loan
FROM ranked
GROUP BY rate_decile
ORDER BY rate_decile;


-- name: 10_high_risk_segment_rule
-- question: How much damage does a simple rule 'DTI >= 30 AND employed < 2 yrs' cause?
-- (This is the rule tested in the Python policy simulation.)
WITH flagged AS (
    SELECT
        *,
        CASE WHEN dti >= 30 AND emp_length_yrs < 2 THEN 'High-risk rule' ELSE 'Rest of book' END AS segment
    FROM loans_v
)
SELECT
    segment,
    COUNT(*)                                       AS loans,
    ROUND(100.0 * AVG(is_default), 2)              AS default_rate_pct,
    ROUND(AVG(total_payment - loan_amount), 0)     AS avg_profit_per_loan,
    ROUND(SUM(total_payment - loan_amount) / 1e6, 3) AS total_profit_mn
FROM flagged
GROUP BY segment;


-- name: 11_top_risk_combinations
-- question: Which grade x purpose combinations have the worst default rates? (min volume filter)
SELECT
    grade,
    purpose,
    COUNT(*)                          AS loans,
    ROUND(100.0 * AVG(is_default), 2) AS default_rate_pct
FROM loans_v
GROUP BY grade, purpose
HAVING COUNT(*) >= 150
ORDER BY default_rate_pct DESC
LIMIT 10;
