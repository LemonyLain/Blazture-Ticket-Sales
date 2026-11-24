-- =====================================================================
-- Blazture ticket sales 2025 vs 2026  |  MySQL 8.0 (MySQL Workbench)
-- Ticket COUNTS only (no revenue). Run section by section (Ctrl+Enter
-- runs the current statement; select a block and press Ctrl+Shift+Enter
-- to run it all).
-- NOTE: written for MySQL 8.0+ (needs window functions and CTEs).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. DATABASE
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS blazture;
USE blazture;


-- ---------------------------------------------------------------------
-- 1. STAGING TABLE (a "landing zone" for the CSV, everything permissive)
--    Then: right-click stg_sales in the left panel ->
--    "Table Data Import Wizard" -> choose staging_sales.csv ->
--    "Use existing table: blazture.stg_sales" -> finish.
--    (If the table is not visible, click the refresh icon in SCHEMAS.)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_sales;
CREATE TABLE stg_sales (
  edition         SMALLINT,
  channel         VARCHAR(30),
  source_row      INT,           -- row number in the original Excel sheet
  purchase_date   VARCHAR(10),   -- text on purpose: '' means "unknown"
  purchase_time   VARCHAR(8),    -- only the web (Tiptip) sheets have times
  ticket_type_raw VARCHAR(60),
  quantity        INT,
  date_status     VARCHAR(40)    -- how the date was repaired (audit trail)
);

-- After the import, check the load:
SELECT edition, channel, COUNT(*) AS row_count, SUM(quantity) AS tickets
FROM stg_sales
GROUP BY edition, channel
ORDER BY edition, channel;
-- Expected: 2025 Manual 248 rows / 472 tickets, 2025 Web 1500 / 1500,
--           2026 Manual 80 rows / 207 tickets,  2026 Web 2780 / 2780.
-- The 2 extra 2026 manual rows are 'recap_only' rows: 6 Bundling + 35 OTS
-- tickets from your ticket recap that were missing from the Excel sheet.
-- They are totals with no date and no individual transactions.
-- INTERVIEW POINT: the two channels have DIFFERENT GRAIN. A web row is one
-- ticket (quantity = 1); a manual (WhatsApp) row is one transaction with
-- quantity tickets. So tickets = SUM(quantity), never COUNT(*).


-- ---------------------------------------------------------------------
-- 2. AUDIT THE STAGING DATA
-- ---------------------------------------------------------------------
-- 2a. Which raw ticket labels exist? (spots typos and naming changes)
SELECT edition, channel, ticket_type_raw, COUNT(*) AS row_count, SUM(quantity) AS tickets
FROM stg_sales
GROUP BY edition, channel, ticket_type_raw
ORDER BY edition, channel, ticket_type_raw;

-- 2b. Bad or missing values?
SELECT
  SUM(quantity IS NULL OR quantity <= 0)            AS bad_quantity,
  SUM(purchase_date IS NULL OR purchase_date = '')  AS missing_date,
  SUM(ticket_type_raw IS NULL OR ticket_type_raw = '') AS missing_type
FROM stg_sales;

-- 2c. How were dates repaired? (see the notes that came with the CSV)
SELECT date_status, COUNT(*) AS row_count
FROM stg_sales
GROUP BY date_status
ORDER BY row_count DESC;


-- ---------------------------------------------------------------------
-- 3. LOOKUP TABLE: map messy labels to clean ones
--    Special offers differ by year (different products each edition), so
--    they are grouped but NOT compared across years.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ticket_type_map;
CREATE TABLE ticket_type_map (
  ticket_type_raw VARCHAR(60) PRIMARY KEY,
  ticket_type     VARCHAR(30) NOT NULL,   -- clean name
  ticket_group    VARCHAR(30) NOT NULL    -- broader group for charts
);

INSERT INTO ticket_type_map (ticket_type_raw, ticket_type, ticket_group) VALUES
  ('Early Bird',                'Early Bird',        'Regular phase'),
  ('Early Bird Blazture 2026',  'Early Bird',        'Regular phase'),
  ('Presale 1',                 'Presale 1',         'Regular phase'),
  ('PreSale 1 - Blazture 2026', 'Presale 1',         'Regular phase'),
  ('Presale 2',                 'Presale 2',         'Regular phase'),
  ('PreSale 2 - Blazture 2026', 'Presale 2',         'Regular phase'),
  ('Presale 3',                 'Presale 3',         'Regular phase'),
  ('Presale3',                  'Presale 3',         'Regular phase'),  -- typo in 2025 web sheet
  ('PreSale 3 - Blazture 2026', 'Presale 3',         'Regular phase'),
  ('BUNDLE',                    'Bundle',            'Special offer'),
  ('Bundling Presale 3',        'Bundle',            'Special offer'),
  ('PROMO PRESALE 3',           'Promo Presale 3',   'Special offer'),
  ('PROMO DIESNATALIS',         'Promo Diesnatalis', 'Special offer'),
  ('OTS',                       'On-the-spot',       'Special offer'),
  ('Pre-Event',                 'Blood Donor (50%)', 'Special offer');  -- 2026 'Donor Darah', matches 23 tickets in your recap

-- Safety check BEFORE building the clean table: any label with no mapping?
-- Must return 0 rows (an INNER JOIN would silently drop them otherwise).
SELECT DISTINCT s.ticket_type_raw
FROM stg_sales s
LEFT JOIN ticket_type_map m ON m.ticket_type_raw = s.ticket_type_raw
WHERE m.ticket_type_raw IS NULL;


-- ---------------------------------------------------------------------
-- 4. CLEAN TABLE
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS sales;
CREATE TABLE sales (
  sale_id       INT AUTO_INCREMENT PRIMARY KEY,
  edition       SMALLINT    NOT NULL,                 -- 2025 or 2026
  channel       VARCHAR(30) NOT NULL,                 -- 'Web (Tiptip)' or 'Manual (WhatsApp)'
  purchase_date DATE        NULL,                     -- NULL = could not be recovered
  purchase_time TIME        NULL,                     -- web only
  ticket_type   VARCHAR(30) NOT NULL,
  ticket_group  VARCHAR(30) NOT NULL,
  quantity      INT         NOT NULL,
  date_status   VARCHAR(40) NULL,
  CONSTRAINT chk_quantity CHECK (quantity > 0),
  CONSTRAINT chk_edition  CHECK (edition IN (2025, 2026)),
  CONSTRAINT chk_channel  CHECK (channel IN ('Web (Tiptip)', 'Manual (WhatsApp)'))
);

INSERT INTO sales (edition, channel, purchase_date, purchase_time,
                   ticket_type, ticket_group, quantity, date_status)
SELECT s.edition,
       s.channel,
       STR_TO_DATE(NULLIF(s.purchase_date, ''), '%Y-%m-%d'),  -- '' -> NULL -> DATE
       NULLIF(s.purchase_time, ''),                           -- '' -> NULL -> TIME
       m.ticket_type,
       m.ticket_group,
       s.quantity,
       s.date_status
FROM stg_sales s
JOIN ticket_type_map m ON m.ticket_type_raw = s.ticket_type_raw;
-- INTERVIEW POINT: constraints (NOT NULL, CHECK) make bad data fail loudly
-- instead of silently flowing into the dashboard.


-- ---------------------------------------------------------------------
-- 5. RECONCILIATION: compare with the totals you reported for each edition
--    (1,977 and 2,987). The file may not match, so check before analysing.
-- ---------------------------------------------------------------------
SELECT edition,
       SUM(quantity) AS tickets_in_file,
       CASE edition WHEN 2025 THEN 1977 WHEN 2026 THEN 2987 END AS reported_total,
       CASE edition WHEN 2025 THEN 1977 WHEN 2026 THEN 2987 END - SUM(quantity) AS gap
FROM sales
GROUP BY edition;
-- 2026 should show gap 0 (the 41 missing tickets came from the recap).
-- 2025 shows a gap of 5 against the earlier figure of 1,977. DECISION: the
-- project uses 1,972 for 2025 (the tickets that are actually in the data).
-- State this limitation in the write-up; do not quote 1,977.

-- Rows with no date (kept in ticket counts, excluded from timing queries):
-- 1 row from 2025 + the 2 recap_only rows (41 tickets) from 2026.
SELECT * FROM sales WHERE purchase_date IS NULL;


-- ---------------------------------------------------------------------
-- 6. THE BUSINESS QUESTIONS (saved as views so they export cleanly)
-- ---------------------------------------------------------------------

-- Q1. WHEN DO SALES SPIKE? Daily tickets + cumulative % by day of sales.
-- Event dates are not in the data, so "day 0" = the first sale of each
-- edition. That makes the two editions comparable. (With event dates you
-- could switch to days-to-event.)
CREATE OR REPLACE VIEW v_q1_daily AS
WITH daily AS (                                   -- step 1: one row per edition per day
  SELECT edition, purchase_date, SUM(quantity) AS tickets
  FROM sales
  WHERE purchase_date IS NOT NULL
  GROUP BY edition, purchase_date
)
SELECT edition,
       purchase_date,
       DATEDIFF(purchase_date, MIN(purchase_date) OVER (PARTITION BY edition)) AS day_of_sales,
       tickets,
       SUM(tickets) OVER (PARTITION BY edition ORDER BY purchase_date)         AS cumulative_tickets,
       ROUND(100 * SUM(tickets) OVER (PARTITION BY edition ORDER BY purchase_date)
                 / SUM(tickets) OVER (PARTITION BY edition), 1)                AS cumulative_pct
FROM daily;
-- INTERVIEW POINT: the CTE (WITH) collapses transactions to daily totals;
-- window functions (OVER ... PARTITION BY edition) then compute running
-- totals per edition WITHOUT collapsing the rows.

SELECT * FROM v_q1_daily ORDER BY edition, purchase_date;

-- Top 5 busiest days per edition:
SELECT edition, purchase_date, tickets
FROM (
  SELECT edition, purchase_date, SUM(quantity) AS tickets,
         ROW_NUMBER() OVER (PARTITION BY edition ORDER BY SUM(quantity) DESC) AS rnk
  FROM sales
  WHERE purchase_date IS NOT NULL
  GROUP BY edition, purchase_date
) ranked
WHERE rnk <= 5
ORDER BY edition, rnk;


-- Q2. WHICH TICKET TYPES SELL BEST? Tickets and share of each edition.
CREATE OR REPLACE VIEW v_q2_ticket_type AS
SELECT edition, ticket_group, ticket_type,
       SUM(quantity) AS tickets,
       ROUND(100 * SUM(quantity) / SUM(SUM(quantity)) OVER (PARTITION BY edition), 1) AS pct_of_edition
FROM sales
GROUP BY edition, ticket_group, ticket_type;
-- INTERVIEW POINT: SUM(SUM(quantity)) OVER (...) = sum per type first, then
-- the edition total, so each row gets its share of the edition.

SELECT * FROM v_q2_ticket_type ORDER BY edition, tickets DESC;


-- Q3. WHICH CHANNEL SELLS BEST? Web (Tiptip) vs Manual (WhatsApp).
CREATE OR REPLACE VIEW v_q3_channel AS
SELECT edition, channel,
       SUM(quantity) AS tickets,
       ROUND(100 * SUM(quantity) / SUM(SUM(quantity)) OVER (PARTITION BY edition), 1) AS pct_of_edition
FROM sales
GROUP BY edition, channel;

SELECT * FROM v_q3_channel ORDER BY edition, tickets DESC;

-- Manual orders only: how many tickets per WhatsApp transaction? (group buying)
CREATE OR REPLACE VIEW v_q3_manual_group_size AS
SELECT edition,
       quantity AS tickets_per_transaction,
       COUNT(*) AS transactions,
       SUM(quantity) AS tickets
FROM sales
WHERE channel = 'Manual (WhatsApp)' AND date_status <> 'recap_only'
GROUP BY edition, quantity;

SELECT * FROM v_q3_manual_group_size ORDER BY edition, tickets_per_transaction;
SELECT edition, ROUND(AVG(quantity), 2) AS avg_tickets_per_transaction
FROM sales WHERE channel = 'Manual (WhatsApp)' AND date_status <> 'recap_only' GROUP BY edition;
-- recap_only rows are excluded: they are totals, not transactions.
-- This is only valid for the manual channel: web rows are single tickets,
-- so you cannot tell which web tickets were bought together.


-- Q4. HOW DID 2026 DIFFER FROM 2025?
-- Only the regular phases (Early Bird, Presale 1-3) are the same product
-- in both years, so only those get a growth %. Special offers (bundle,
-- promos, on-the-spot, blood donor) changed each year and are listed
-- side by side WITHOUT growth.
CREATE OR REPLACE VIEW v_q4_edition_compare AS
WITH pivoted AS (
  SELECT ticket_group, ticket_type,
         SUM(CASE WHEN edition = 2025 THEN quantity ELSE 0 END) AS tickets_2025,
         SUM(CASE WHEN edition = 2026 THEN quantity ELSE 0 END) AS tickets_2026
  FROM sales
  GROUP BY ticket_group, ticket_type
)
SELECT ticket_group, ticket_type, tickets_2025, tickets_2026,
       tickets_2026 - tickets_2025 AS change_tickets,
       CASE WHEN ticket_group = 'Regular phase'
            THEN ROUND(100 * (tickets_2026 - tickets_2025) / NULLIF(tickets_2025, 0), 1)
       END AS growth_pct            -- NULL for special offers on purpose
FROM pivoted;
-- CASE WHEN in SUM(...) = manual pivot (rows -> columns). NULLIF(...,0)
-- avoids dividing by zero. INTERVIEW POINT: knowing when NOT to compute a
-- growth rate (different products) is as important as the formula.

SELECT * FROM v_q4_edition_compare ORDER BY ticket_group, ticket_type;


-- Q5. WHEN DURING THE DAY / WEEK DO PEOPLE BUY? (web only: manual rows have no time)
CREATE OR REPLACE VIEW v_q5_hour AS
SELECT edition, HOUR(purchase_time) AS hour_of_day, SUM(quantity) AS tickets
FROM sales
WHERE channel = 'Web (Tiptip)' AND purchase_time IS NOT NULL
GROUP BY edition, HOUR(purchase_time);

CREATE OR REPLACE VIEW v_q5_weekday AS
SELECT edition,
       WEEKDAY(purchase_date) AS weekday_num,        -- 0 = Monday ... 6 = Sunday
       DAYNAME(purchase_date) AS weekday_name,
       SUM(quantity) AS tickets
FROM sales
WHERE channel = 'Web (Tiptip)' AND purchase_date IS NOT NULL
GROUP BY edition, WEEKDAY(purchase_date), DAYNAME(purchase_date);

SELECT * FROM v_q5_hour ORDER BY edition, hour_of_day;
SELECT * FROM v_q5_weekday ORDER BY edition, weekday_num;


-- ---------------------------------------------------------------------
-- 7. EXPORT FOR THE DASHBOARD
--    Run each SELECT * FROM v_... and use the "Export recordset to an
--    external file" icon above the result grid -> CSV.
--    Export: v_q1_daily, v_q2_ticket_type, v_q3_channel,
--            v_q4_edition_compare, v_q5_hour (and v_q5_weekday if used).
-- ---------------------------------------------------------------------
