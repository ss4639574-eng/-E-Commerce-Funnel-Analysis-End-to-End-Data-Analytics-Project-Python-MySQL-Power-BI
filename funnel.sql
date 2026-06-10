create database if not exists ecommerce_funnel;
use ecommerce_funnel;

--- Create Table -----
CREATE TABLE IF NOT EXISTS funnel_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(20),
    session_id VARCHAR(50),
    event_timestamp DATETIME,
    event_stage VARCHAR(30),
    device VARCHAR(20),
    source VARCHAR(30),
    country VARCHAR(30),
    product_id VARCHAR(20),
    product_category VARCHAR(30),
    product_price DECIMAL(10,2),
    quantity INT,
    order_id VARCHAR(20),
    payment_method VARCHAR(20),
    revenue DECIMAL(10,2),
    time_on_page_sec DECIMAL(10,1),
    event_date date,
    stage_order int,
    INDEX idx_user_id (user_id),
    INDEX idx_event_stage (event_stage),
    INDEX idx_event_date (event_date),
    INDEX idx_session_id (session_id),
    INDEX idx_order_id (order_id)
);
 
 -- Load Data from CSV
 
set global local_infile = 1 ;
load data local infile 'C:/Users/HP/Documents/python_le/.vscode/ecommerce_funnel_cleaned.csv' 
into table funnel_events fields terminated by ','
optionally enclosed by '"'
lines terminated by '\n'
ignore 1 rows
(user_id, session_id, event_timestamp, event_stage, device, 
 source, country, product_id, product_category, product_price, quantity, 
 order_id, payment_method, revenue, time_on_page_sec,@event_date,
 @var1, @var2,stage_order)
SET event_date = STR_TO_DATE(@event_date, '%Y-%m-%d');


-- ADVANCED SQL QUERIES FOR FUNNEL ANALYSIS

-- QUERY 1: Basic Funnel Stage Counts (Unique Users)

select event_stage,stage_order,
    count( distinct user_id) as unique_users,
    count(*) as total_events
from funnel_events
group by event_stage,stage_order
order by stage_order;

-- QUERY 2: Funnel Conversion Rates (Stage-to-Stage)

WITH funnel_counts AS (
    SELECT 
        event_stage,
        stage_order,
        COUNT(DISTINCT user_id) AS users
    FROM funnel_events
    GROUP BY event_stage, stage_order
),
funnel_with_prev AS (
    SELECT 
        f.event_stage,
        f.stage_order,
        f.users,
        LAG(f.users) OVER (ORDER BY f.stage_order) AS prev_stage_users
    FROM funnel_counts f
)
SELECT 
    event_stage,
    stage_order,
    users,
    prev_stage_users,
    ROUND(users * 100.0 / MAX(users) OVER(), 2) AS pct_of_initial,
    ROUND(users * 100.0 / prev_stage_users, 2) AS conversion_rate_from_prev,
    ROUND((1 - users * 1.0 / prev_stage_users) * 100, 2) AS drop_off_rate
FROM funnel_with_prev
WHERE prev_stage_users IS NOT NULL
ORDER BY stage_order;

-- QUERY 3: Overall Conversion Rate

select
    COUNT(DISTINCT CASE WHEN event_stage = 'page_view' THEN user_id END) AS page_view_users,
    COUNT(DISTINCT CASE WHEN event_stage = 'confirmation' THEN user_id END) AS converted_users,
    ROUND(
        COUNT(DISTINCT CASE WHEN event_stage = 'confirmation' THEN user_id END) * 100.0 /
        COUNT(DISTINCT CASE WHEN event_stage = 'page_view' THEN user_id END),
        2
    ) AS overall_conversion_rate_pct
FROM funnel_events;

-- QUERY 4: Funnel by Device Type

select device,
	COUNT(DISTINCT CASE WHEN event_stage = 'page_view' THEN user_id END) AS page_view_users,
    COUNT(DISTINCT CASE WHEN event_stage = 'product_view' THEN user_id END) as product_view_users,
	COUNT(DISTINCT CASE WHEN event_stage = 'add_to_cart' THEN user_id END) as added_to_cart,
    COUNT(DISTINCT CASE WHEN event_stage = 'confirmation' THEN user_id END) AS converted_users,
    ROUND(
        COUNT(DISTINCT CASE WHEN event_stage = 'confirmation' THEN user_id END) * 100.0 /
        COUNT(DISTINCT CASE WHEN event_stage = 'page_view' THEN user_id END),
        2
    ) AS conversion_rate
from funnel_events
group by device
order by conversion_rate;


-- QUERY 5: Funnel by Traffic Source
select source,
     count(distinct user_id) as total_users,
     count(distinct case when event_stage = 'confirmation' then user_id end) as converted_users,
     round(count(distinct case when event_stage = 'confirmation' then user_id end) * 100 /
     count(distinct user_id) ,2) as conversion_rate,
     round(sum(coalesce(revenue,0)),2) as total_revenue
from funnel_events
group by source
order by total_revenue desc;

-- QUERY 6: Drop-off Analysis (Where Users Leave the Funnel)

WITH user_funnel AS (
    SELECT 
        user_id,
        MAX(stage_order) AS max_stage_reached,
        MAX(event_stage) AS last_stage
    FROM funnel_events
    GROUP BY user_id
)
SELECT 
    last_stage,
    COUNT(*) AS users_stopped_here,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_of_all_users
FROM user_funnel
WHERE last_stage != 'confirmation'
GROUP BY last_stage
ORDER BY COUNT(*) DESC
LIMIT 10;

-- QUERY 7: Revenue Analysis by Product Category

SELECT 
    product_category,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT user_id) AS unique_customers,
    ROUND(SUM(revenue), 2) AS total_revenue,
    ROUND(AVG(revenue), 2) AS avg_order_value,
    ROUND(SUM(revenue) / COUNT(DISTINCT user_id), 2) AS revenue_per_customer
FROM funnel_events
WHERE event_stage = 'confirmation' AND revenue IS NOT NULL
GROUP BY product_category
ORDER BY total_revenue DESC;

-- QUERY 8: Payment Method Performance

SELECT 
    payment_method,
    COUNT(DISTINCT order_id) AS orders,
    COUNT(DISTINCT user_id) AS customers,
    ROUND(SUM(revenue), 2) AS total_revenue,
    ROUND(AVG(revenue), 2) AS avg_order_value,
    ROUND(SUM(revenue) * 100.0 / (SELECT SUM(revenue) FROM funnel_events 
                                   WHERE event_stage = 'confirmation'), 2) AS revenue_share_pct
FROM funnel_events
WHERE event_stage = 'confirmation' AND payment_method IS NOT NULL
GROUP BY payment_method
ORDER BY total_revenue DESC;

-- QUERY 9: Daily Trend Analysis

select
   event_date,
   count(distinct user_id) as daily_users,
   count(distinct case when event_stage = 'confirmation' then user_id end) as daily_conversion_users,
   round(count(distinct case when event_stage = 'confirmation' then user_id end) * 100 /
      count(distinct user_id),2 ) as daily_conversion_pct,
   round(sum(coalesce(revenue,0)),2) as daily_revenue
from funnel_events
group by event_date
order by event_date;

-- QUERY 10: Hourly Activity Pattern

select
    hour(event_timestamp) as hour_of_day,
    count(distinct user_id) as users,
    count(*) as total_event,
    count(distinct case when event_stage = 'confirmation' then user_id end) as coversion
from funnel_events
group by hour(event_timestamp)
order by hour(event_timestamp);

-- QUERY 11: Country-wise Funnel Performance

select 
    country,
    count(distinct user_id) as total_user,
    count(distinct case when event_stage = 'confirmation' then user_id end) as conversions,
    round(count(distinct case when event_stage = 'confirmation' then user_id end) * 100 /
         count(distinct user_id),2) as conversion_rate,
	round(sum(coalesce(revenue,0)),2) as total_revenue
from funnel_events
group by country
order by conversion_rate desc;

-- QUERY 12: Customer Segmentation by Purchase Behavior

with customer_metrics as (
   select
      user_id,
      count(distinct session_id) as sessions,
      max(stage_order) as max_funnel_stage,
      count(distinct case when event_stage = 'confirmation' then user_id end) as orders,
      sum(coalesce(revenue,0)) as total_spent
	from funnel_events
	group by user_id
)
select 
    case 
      when orders > 0 then 'converter'
      when max_funnel_stage >= 4 then 'cart abandoner'
      when max_funnel_stage >= 3 then 'Product Viewer'
      when max_funnel_stage >= 2 then 'Searcher'
      else 'Bouncer'
	end as customer_segment,
    count(*) as customer_count,
    round(avg(total_spent),2) as avg_total_spent,
    round(avg(sessions),2) as avg_session
from customer_metrics
group by customer_segment
order by customer_count desc;

-- QUERY 13: Average Time in Funnel (Page View to Conversion)

WITH first_visit AS (
    SELECT 
        user_id,
        MIN(event_timestamp) AS first_page_view
    FROM funnel_events
    WHERE event_stage = 'page_view'
    GROUP BY user_id
),
conversion AS (
    SELECT 
        user_id,
        MIN(event_timestamp) AS conversion_time
    FROM funnel_events
    WHERE event_stage = 'confirmation'
    GROUP BY user_id
)
SELECT 
    ROUND(AVG(TIMESTAMPDIFF(MINUTE, fv.first_page_view, c.conversion_time)), 2) AS avg_minutes_to_convert,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, fv.first_page_view, c.conversion_time)), 2) AS avg_hours_to_convert,
    COUNT(*) AS total_converters
FROM first_visit fv
INNER JOIN conversion c ON fv.user_id = c.user_id;

-- QUERY 14: Session-to-Conversion Rate (Multi-session Analysis)

with user_sessions as (
    select 
      user_id,
      count(distinct session_id) as session_count,
      max(case when event_stage = 'confirmation' then 1 else 0 end) as converted
	from funnel_events
    group by user_id
)
select 
    session_count,
    count(*) as user_count,
    sum(converted) as converters,
    round(sum(converted) * 100 / count(*),2) as conversion_rate
from user_sessions
group by session_count
order by session_count;

-- QUERY 15: Cohort Analysis (Weekly Retention)

WITH weekly_cohorts AS (
    SELECT 
        user_id,
        date_sub( MIN(event_date),interval weekday(min(event_date)) day ) AS cohort_week
    FROM funnel_events
    GROUP BY user_id
),
weekly_activity AS (
    SELECT 
        wc.cohort_week,
        date_sub(fe.event_date, interval weekday(fe.event_date) day) AS activity_week,
        COUNT(DISTINCT fe.user_id) AS active_users
    FROM weekly_cohorts wc
    JOIN funnel_events fe ON wc.user_id = fe.user_id
    GROUP BY wc.cohort_week, date_sub(fe.event_date, interval weekday(fe.event_date) day)
)
SELECT 
    cohort_week,
    activity_week,
    timestampdiff(week,cohort_week,activity_week) AS weeks_since_cohort,
    active_users
FROM weekly_activity
order by cohort_week,activity_week;


-- QUERY 16: Top Products by Conversion
SELECT 
    product_id,
    product_category,
    COUNT(DISTINCT user_id) AS viewers,
    COUNT(DISTINCT CASE WHEN event_stage = 'add_to_cart' THEN user_id END) AS added_to_cart,
    COUNT(DISTINCT CASE WHEN event_stage = 'confirmation' THEN user_id END) AS purchased,
    ROUND(
        COUNT(DISTINCT CASE WHEN event_stage = 'confirmation' THEN user_id END) * 100.0 /
        COUNT(DISTINCT user_id),
        2
    ) AS view_to_purchase_rate,
    ROUND(SUM(COALESCE(revenue, 0)), 2) AS total_revenue
FROM funnel_events
WHERE product_id IS NOT NULL
GROUP BY product_id, product_category
HAVING viewers >= 100
ORDER BY total_revenue DESC
LIMIT 20;

--  QUERY 17: Abandoned Cart Analysis

SELECT 
    fe1.user_id,
    fe1.session_id,
    fe1.product_id,
    fe1.product_category,
    fe1.product_price,
    fe1.quantity,
    fe1.product_price * fe1.quantity AS cart_value,
    fe1.event_timestamp AS added_to_cart_time
FROM funnel_events fe1
WHERE fe1.event_stage = 'add_to_cart'
AND NOT EXISTS (
    SELECT 1 FROM funnel_events fe2
    WHERE fe2.user_id = fe1.user_id
    AND fe2.session_id = fe1.session_id
    AND fe2.event_stage = 'confirmation'
)
ORDER BY cart_value DESC
LIMIT 50;