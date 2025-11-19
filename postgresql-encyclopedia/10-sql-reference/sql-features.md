# PostgreSQL SQL Reference: Dialect and Advanced Features

PostgreSQL extends the SQL standard with powerful features and a rich type system that make it uniquely capable for complex data applications. This chapter provides a reference guide to PostgreSQL's SQL dialect, highlighting features that distinguish it from other database systems.

## 1. PostgreSQL's Rich Type System

### 1.1 Built-in Data Types

PostgreSQL includes an extensive collection of data types beyond the SQL standard:

#### Numeric Types
- **Integer Types**: `smallint` (2 bytes), `integer` (4 bytes), `bigint` (8 bytes)
- **Decimal Types**: `numeric(precision, scale)` for exact arithmetic, `decimal` (alias for numeric)
- **Floating Point**: `real` (4 bytes, ~6 decimal digits), `double precision` (8 bytes, ~15 decimal digits)
- **Serial Types**: `smallserial`, `serial`, `bigserial` for auto-incrementing integers

#### Text Types
- **Character**: `char(n)` (fixed-length), `varchar(n)` (variable-length), `text` (unlimited)
- **Text Search**: Full-text search support with `tsvector` and `tsquery` types

#### Temporal Types
- **Date/Time**: `date`, `time`, `timestamp`, `timestamptz` (timezone-aware)
- **Intervals**: `interval` for durations, supporting arithmetic with timestamps
- **Time Zones**: Native timezone handling with `timestamptz` type

#### Binary and Encoding
- **Bytea**: Binary data storage with hex or escape encoding
- **UUID**: Universally unique identifiers (standard 128-bit)
- **Bit Strings**: `bit(n)` and `bit varying(n)` for bit-level operations

#### Geometric Types
PostgreSQL includes specialized types for geometric data:
- **Points**: `point` for 2D points (x, y)
- **Line Segments**: `lseg` for line segments
- **Rectangles**: `box` for axis-aligned rectangles
- **Circles**: `circle` for circles with center and radius
- **Polygons**: `polygon` for general polygons
- **Paths**: `path` for open and closed paths

#### Network Types
- **inet**: IPv4 or IPv6 network address
- **cidr**: IPv4 or IPv6 network specification (CIDR notation)
- **macaddr**: MAC (hardware) addresses

#### Range Types
```sql
-- Built-in range types
int4range, int8range           -- Integer ranges
numrange                       -- Numeric ranges
tsrange, tstzrange             -- Timestamp ranges
daterange                      -- Date ranges

-- Example usage
CREATE TABLE availability (
    slot_id SERIAL PRIMARY KEY,
    available_hours tsrange NOT NULL
);

INSERT INTO availability VALUES
    (1, '[2024-01-01 09:00, 2024-01-01 17:00)'),
    (2, '[2024-01-02 10:00, 2024-01-02 18:00)');

-- Query overlapping ranges
SELECT * FROM availability
WHERE available_hours @> '2024-01-01 12:00'::timestamp;
```

#### JSON and JSONB
- **json**: Text-based JSON storage (slower parsing, preserves order, allows duplicates)
- **jsonb**: Binary JSON storage (faster processing, normalized, index support)

### 1.2 Composite Types

Create custom composite types for structured data:

```sql
-- Define a composite type
CREATE TYPE address AS (
    street VARCHAR(100),
    city VARCHAR(50),
    state CHAR(2),
    postal_code VARCHAR(10)
);

-- Use in a table
CREATE TABLE companies (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    headquarters address
);

-- Insert values
INSERT INTO companies VALUES
    (1, 'Acme Corp', ('123 Main St', 'New York', 'NY', '10001'));

-- Access individual fields
SELECT name, (headquarters).city FROM companies;
```

### 1.3 Custom Types and Domains

Define domain types with constraints:

```sql
-- Create a domain
CREATE DOMAIN email AS varchar(255) CHECK (
    value ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$'
);

-- Use the domain
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email_address email NOT NULL UNIQUE
);

-- Type constraints are automatically checked
INSERT INTO users VALUES (1, 'invalid-email'); -- ERROR: violates check constraint
```

---

## 2. Advanced SQL Features

### 2.1 Window Functions

Window functions perform calculations across a set of rows related to the current row, without collapsing results into a single row.

```sql
-- Basic syntax
SELECT
    employee_id,
    salary,
    department_id,
    AVG(salary) OVER (PARTITION BY department_id) as dept_avg,
    ROW_NUMBER() OVER (PARTITION BY department_id ORDER BY salary DESC) as rank
FROM employees;
```

#### Window Function Categories

**Aggregate Functions as Window Functions:**
```sql
-- Running totals
SELECT
    order_date,
    amount,
    SUM(amount) OVER (ORDER BY order_date) as running_total
FROM orders
ORDER BY order_date;

-- Partition-level aggregates
SELECT
    customer_id,
    amount,
    AVG(amount) OVER (PARTITION BY customer_id) as customer_avg
FROM orders;
```

**Ranking Functions:**
```sql
-- ROW_NUMBER(): Unique rank even for ties
SELECT
    product_id,
    sales,
    ROW_NUMBER() OVER (ORDER BY sales DESC) as row_num
FROM product_performance;

-- RANK(): Ties get same rank, gaps in numbering
SELECT
    product_id,
    sales,
    RANK() OVER (ORDER BY sales DESC) as rank
FROM product_performance;

-- DENSE_RANK(): Ties get same rank, no gaps
SELECT
    product_id,
    sales,
    DENSE_RANK() OVER (ORDER BY sales DESC) as dense_rank
FROM product_performance;

-- PERCENT_RANK(): Percentile of partition (0 to 1)
SELECT
    product_id,
    sales,
    PERCENT_RANK() OVER (ORDER BY sales DESC) as pct_rank
FROM product_performance;
```

**Offset Functions:**
```sql
-- LAG/LEAD: Access previous/next row values
SELECT
    order_date,
    amount,
    LAG(amount) OVER (ORDER BY order_date) as previous_amount,
    LEAD(amount) OVER (ORDER BY order_date) as next_amount
FROM orders;

-- First/Last value in window
SELECT
    order_date,
    amount,
    FIRST_VALUE(amount) OVER (ORDER BY order_date) as first_amount,
    LAST_VALUE(amount) OVER (ORDER BY order_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as last_amount
FROM orders;

-- NTH_VALUE: Get value at specific position
SELECT
    order_date,
    amount,
    NTH_VALUE(amount, 3) OVER (ORDER BY order_date) as third_value
FROM orders;
```

**Frame Specifications:**
```sql
-- Control which rows participate in the window
SELECT
    order_date,
    amount,
    -- Moving average over 3 rows
    AVG(amount) OVER (ORDER BY order_date
        ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) as moving_avg,
    -- Cumulative sum from start
    SUM(amount) OVER (ORDER BY order_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as cumulative
FROM orders;
```

### 2.2 Common Table Expressions (CTEs) and Recursive Queries

CTEs provide a way to define temporary named result sets that can be referenced in SELECT, INSERT, UPDATE, or DELETE statements.

#### Simple CTEs

```sql
-- WITH clause for reusable subqueries
WITH department_summary AS (
    SELECT
        department_id,
        AVG(salary) as avg_salary,
        COUNT(*) as emp_count
    FROM employees
    GROUP BY department_id
)
SELECT
    e.name,
    e.salary,
    ds.avg_salary,
    e.salary - ds.avg_salary as salary_diff
FROM employees e
JOIN department_summary ds ON e.department_id = ds.department_id
WHERE e.salary > ds.avg_salary;
```

#### Multiple CTEs

```sql
WITH sales_summary AS (
    SELECT
        customer_id,
        SUM(amount) as total_sales
    FROM orders
    GROUP BY customer_id
),
customer_ranks AS (
    SELECT
        customer_id,
        total_sales,
        RANK() OVER (ORDER BY total_sales DESC) as sales_rank
    FROM sales_summary
)
SELECT * FROM customer_ranks WHERE sales_rank <= 10;
```

#### Recursive CTEs

Recursive CTEs enable hierarchical and tree-like query patterns:

```sql
-- Organizational hierarchy
WITH RECURSIVE org_hierarchy AS (
    -- Anchor: Start with top-level employees
    SELECT
        employee_id,
        name,
        manager_id,
        1 as level
    FROM employees
    WHERE manager_id IS NULL

    UNION ALL

    -- Recursive: Find direct reports
    SELECT
        e.employee_id,
        e.name,
        e.manager_id,
        oh.level + 1
    FROM employees e
    INNER JOIN org_hierarchy oh ON e.manager_id = oh.employee_id
    WHERE oh.level < 10  -- Prevent infinite recursion
)
SELECT * FROM org_hierarchy
ORDER BY level, name;
```

#### Recursive CTE: Graph Traversal

```sql
-- Find all connected nodes in a graph
WITH RECURSIVE graph_traversal AS (
    -- Start with a specific node
    SELECT
        node_id,
        target_id,
        1 as depth
    FROM edges
    WHERE node_id = 'A'

    UNION ALL

    -- Find reachable nodes
    SELECT
        gt.node_id,
        e.target_id,
        gt.depth + 1
    FROM graph_traversal gt
    JOIN edges e ON gt.target_id = e.node_id
    WHERE gt.depth < 20
)
SELECT DISTINCT target_id FROM graph_traversal
ORDER BY target_id;
```

#### Materialized CTEs

Use `MATERIALIZED` keyword to force materialization (vs. inlining):

```sql
WITH expensive_calc AS MATERIALIZED (
    SELECT
        id,
        complex_computation(data) as result
    FROM large_table
)
SELECT * FROM expensive_calc
WHERE result > 1000;
```

### 2.3 LATERAL Joins

LATERAL subqueries allow the subquery to reference columns from preceding tables, enabling powerful row-by-row processing:

```sql
-- Find top 3 purchases for each customer
SELECT
    c.customer_id,
    c.name,
    p.order_date,
    p.amount
FROM customers c
CROSS JOIN LATERAL (
    SELECT order_date, amount
    FROM orders
    WHERE customer_id = c.customer_id
    ORDER BY amount DESC
    LIMIT 3
) p;
```

#### LATERAL with Function Calls

```sql
-- Apply set-returning function to each row
SELECT
    product_id,
    product_name,
    tags
FROM products
CROSS JOIN LATERAL unnest(product_tags) AS tags;

-- Using json_each_text with LATERAL
SELECT
    id,
    key,
    value
FROM json_data
CROSS JOIN LATERAL json_each_text(data) AS kv(key, value);
```

#### LATERAL with JOIN Conditions

```sql
-- Find related products based on category affinity
SELECT
    p1.product_id,
    p1.name,
    p2.product_id,
    p2.name
FROM products p1
JOIN LATERAL (
    SELECT product_id, name
    FROM products
    WHERE category = p1.category
        AND product_id != p1.product_id
    LIMIT 5
) p2 ON TRUE;
```

### 2.4 GROUPING SETS, CUBE, and ROLLUP

These features enable multi-level aggregation with a single query:

```sql
-- GROUPING SETS: Multiple independent groupings
SELECT
    year,
    quarter,
    region,
    SUM(sales) as total_sales
FROM sales_data
GROUP BY GROUPING SETS (
    (year, quarter, region),
    (year, quarter),
    (year),
    ()
)
ORDER BY year, quarter, region;

-- Identify which grouping is used with GROUPING()
SELECT
    year,
    quarter,
    region,
    SUM(sales) as total_sales,
    GROUPING(year, quarter, region) as grouping_id
FROM sales_data
GROUP BY GROUPING SETS (
    (year, quarter, region),
    (year, quarter),
    (year),
    ()
)
ORDER BY grouping_id;
```

#### ROLLUP: Hierarchical Aggregation

```sql
-- ROLLUP creates progressively aggregated rows
SELECT
    year,
    quarter,
    month,
    SUM(sales) as total_sales
FROM sales_data
GROUP BY ROLLUP (year, quarter, month)
ORDER BY year, quarter, month;

-- Equivalent to:
-- GROUP BY (year, quarter, month), (year, quarter), (year), ()
```

#### CUBE: All Possible Groupings

```sql
-- CUBE generates all combinations of grouping
SELECT
    product_category,
    region,
    sales_channel,
    SUM(amount) as total
FROM sales
GROUP BY CUBE (product_category, region, sales_channel)
ORDER BY product_category, region, sales_channel;

-- Generates 2^3 = 8 grouping combinations
```

### 2.5 JSON and JSONB Operations

PostgreSQL provides comprehensive JSON support with powerful operators:

#### JSON vs JSONB

```sql
-- json: Text-based (slower, preserves format/duplicates)
CREATE TABLE config_json (data json);

-- jsonb: Binary (faster, normalized, supports indexing)
CREATE TABLE config_jsonb (data jsonb);

-- JSONB is generally preferred for most applications
INSERT INTO config_jsonb VALUES ('{"name": "Alice", "age": 30}');
```

#### Accessing JSON Data

```sql
-- -> returns value as JSON
-- ->> returns value as text
-- #> returns nested value as JSON
-- #>> returns nested value as text

SELECT
    data->'name' as name_json,
    data->>'name' as name_text,
    data->'address'->>'city' as city
FROM config_jsonb
WHERE (data->'age')::int > 25;
```

#### Querying JSON Arrays

```sql
-- jsonb_array_elements: Expand JSON array
SELECT jsonb_array_elements(tags) as tag
FROM products
WHERE name = 'Widget';

-- jsonb_array_length: Array size
SELECT
    name,
    jsonb_array_length(tags) as tag_count
FROM products;

-- Containment operators
SELECT * FROM products
WHERE tags @> '["electronics", "gadget"]'::jsonb;
```

#### Building and Modifying JSON

```sql
-- jsonb_build_object: Build JSON object
SELECT jsonb_build_object(
    'id', id,
    'name', name,
    'email', email
) as customer_json
FROM customers;

-- jsonb_build_array: Build JSON array
SELECT jsonb_build_array(id, name, email)
FROM customers;

-- || operator: Merge JSON objects
SELECT
    data || '{"updated": true}'::jsonb as updated_data
FROM config_jsonb;

-- jsonb_set: Update nested values
SELECT jsonb_set(
    data,
    '{address, city}',
    '"New York"'::jsonb
)
FROM customers;

-- jsonb_insert: Insert value at path
SELECT jsonb_insert(
    data,
    '{tags, 0}',
    '"new_tag"'::jsonb
)
FROM products;
```

#### JSON Aggregation

```sql
-- json_object_agg: Create JSON object from rows
SELECT
    category,
    json_object_agg(name, price) as products
FROM products
GROUP BY category;

-- json_agg: Create JSON array
SELECT
    customer_id,
    json_agg(json_build_object('id', id, 'amount', amount)) as orders
FROM orders
GROUP BY customer_id;
```

#### Path Queries

```sql
-- jsonb_path_exists: Check if path exists
SELECT * FROM documents
WHERE jsonb_path_exists(data, '$.author.email');

-- jsonb_path_query: Query using JSONPath
SELECT
    id,
    jsonb_path_query(data, '$.items[*].price') as prices
FROM orders;
```

---

## 3. PL/pgSQL: Procedural SQL Language

PL/pgSQL is PostgreSQL's procedural language, enabling complex business logic in stored procedures, functions, and triggers.

### 3.1 Basic Function Structure

```sql
CREATE OR REPLACE FUNCTION calculate_age(birth_date date)
RETURNS int AS $$
DECLARE
    age int;
BEGIN
    age := DATE_PART('year', AGE(birth_date));
    RETURN age;
END;
$$ LANGUAGE plpgsql;

-- Usage
SELECT calculate_age('1990-05-15'::date);
```

### 3.2 Variables and Control Flow

```sql
CREATE OR REPLACE FUNCTION process_employee(emp_id int)
RETURNS TABLE(name varchar, salary numeric, category text) AS $$
DECLARE
    v_salary numeric;
    v_name varchar;
    v_category text;
BEGIN
    -- Get employee data
    SELECT name, salary INTO v_name, v_salary
    FROM employees
    WHERE employee_id = emp_id;

    -- Conditional logic
    IF v_salary > 150000 THEN
        v_category := 'Executive';
    ELSIF v_salary > 100000 THEN
        v_category := 'Senior';
    ELSIF v_salary > 50000 THEN
        v_category := 'Mid-level';
    ELSE
        v_category := 'Junior';
    END IF;

    RETURN QUERY SELECT v_name, v_salary, v_category;
END;
$$ LANGUAGE plpgsql;
```

### 3.3 Loops and Iteration

```sql
CREATE OR REPLACE FUNCTION batch_update()
RETURNS void AS $$
DECLARE
    emp_record employees%ROWTYPE;
BEGIN
    -- Loop through all records
    FOR emp_record IN SELECT * FROM employees WHERE status = 'active'
    LOOP
        UPDATE employees
        SET last_review = CURRENT_DATE
        WHERE employee_id = emp_record.employee_id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

### 3.4 Error Handling

```sql
CREATE OR REPLACE FUNCTION safe_insert_user(
    p_name varchar,
    p_email varchar
) RETURNS int AS $$
DECLARE
    v_user_id int;
BEGIN
    INSERT INTO users (name, email)
    VALUES (p_name, p_email)
    RETURNING user_id INTO v_user_id;

    RETURN v_user_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'Email % already exists', p_email;
        RETURN -1;
    WHEN OTHERS THEN
        RAISE NOTICE 'Error: %', SQLERRM;
        RETURN -1;
END;
$$ LANGUAGE plpgsql;
```

---

## 4. Performance Features

### 4.1 Prepared Statements

Prepared statements compile once and execute multiple times, improving performance for repeated queries:

```sql
-- In application code (pseudo-code):
PREPARE stmt_get_user AS
    SELECT id, name, email FROM users WHERE id = $1;

EXECUTE stmt_get_user(123);
EXECUTE stmt_get_user(456);

-- Cleanup
DEALLOCATE stmt_get_user;
```

#### Prepared Statements with Multiple Parameters

```sql
PREPARE insert_product (varchar, numeric, int) AS
    INSERT INTO products (name, price, stock)
    VALUES ($1, $2, $3)
    RETURNING product_id;

EXECUTE insert_product('Widget', 19.99, 100);
```

### 4.2 Query Hints Pattern (pg_hint_plan Extension)

While PostgreSQL doesn't have built-in query hints like some other databases, the `pg_hint_plan` extension provides this capability:

```sql
-- Install extension
CREATE EXTENSION pg_hint_plan;

-- Example: Force index usage
/*+ IndexScan(orders idx_orders_customer) */
SELECT * FROM orders WHERE customer_id = 123;

-- Force join method
/*+ HashJoin(o c) */
SELECT * FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.total > 1000;

-- Nested loop join
/*+ NestLoop(o l) */
SELECT * FROM orders o
JOIN line_items l ON o.order_id = l.order_id;
```

#### Without Extensions: Query Optimization

Use PostgreSQL's native features for query optimization:

```sql
-- Analyze table statistics
ANALYZE products;

-- Use EXPLAIN to understand query plans
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE customer_id = 123;

-- Check and rebuild indexes
REINDEX TABLE products;

-- Force sequential scan (for comparison)
SET enable_seqscan = off;
SELECT * FROM products WHERE price > 1000;
RESET enable_seqscan;
```

---

## 5. Extensions to SQL Standard

### 5.1 DISTINCT ON

PostgreSQL's DISTINCT ON extension allows selecting distinct values based on specific columns while keeping other columns:

```sql
-- Standard DISTINCT (requires all columns in ORDER BY)
SELECT DISTINCT ON (customer_id)
    customer_id,
    order_date,
    amount
FROM orders
ORDER BY customer_id, order_date DESC;

-- Returns one order per customer (most recent)
-- Standard SQL would be more complex

-- With DISTINCT ON and multiple columns
SELECT DISTINCT ON (category, subcategory)
    category,
    subcategory,
    product_id,
    price
FROM products
ORDER BY category, subcategory, price DESC;
```

#### Use Cases

```sql
-- Latest record per group
SELECT DISTINCT ON (user_id)
    user_id,
    login_timestamp,
    ip_address
FROM user_logins
ORDER BY user_id, login_timestamp DESC;

-- First occurrence per group
SELECT DISTINCT ON (product_category)
    product_id,
    product_category,
    launch_date
FROM products
ORDER BY product_category, launch_date ASC;
```

### 5.2 RETURNING Clause

RETURNING returns affected rows from INSERT, UPDATE, DELETE, or UPSERT operations:

#### With INSERT

```sql
-- Return generated ID
INSERT INTO users (name, email)
VALUES ('Alice', 'alice@example.com')
RETURNING user_id, name, created_at;

-- Return multiple rows
INSERT INTO products (name, price)
VALUES
    ('Widget', 9.99),
    ('Gadget', 19.99),
    ('Gizmo', 14.99)
RETURNING product_id, name;
```

#### With UPDATE

```sql
-- Track what was changed
UPDATE employees
SET salary = salary * 1.1
WHERE department_id = 5
RETURNING employee_id, name, salary;

-- Atomic read-modify-write
UPDATE account_balance
SET balance = balance - 100
WHERE account_id = 123
RETURNING balance;
```

#### With DELETE

```sql
-- Archive deleted records
WITH deleted_orders AS (
    DELETE FROM orders
    WHERE created_at < CURRENT_DATE - INTERVAL '1 year'
    RETURNING *
)
INSERT INTO archived_orders
SELECT * FROM deleted_orders;
```

### 5.3 INSERT ... ON CONFLICT (UPSERT)

PostgreSQL's INSERT ... ON CONFLICT provides upsert functionality (SQL:2015 standard):

#### Basic UPSERT

```sql
-- Update on conflict with unique constraint
INSERT INTO users (email, name, updated_at)
VALUES ('alice@example.com', 'Alice Smith', CURRENT_TIMESTAMP)
ON CONFLICT (email)
DO UPDATE SET
    name = EXCLUDED.name,
    updated_at = EXCLUDED.updated_at;
```

#### Conflict Resolution Strategies

```sql
-- Strategy 1: DO NOTHING
INSERT INTO unique_tags (tag_name)
VALUES ('new-tag')
ON CONFLICT (tag_name) DO NOTHING;

-- Strategy 2: DO UPDATE with conditions
INSERT INTO user_sessions (user_id, session_token, expires_at)
VALUES (123, 'token_abc', CURRENT_TIMESTAMP + INTERVAL '1 day')
ON CONFLICT (user_id) DO UPDATE SET
    session_token = EXCLUDED.session_token,
    expires_at = EXCLUDED.expires_at
WHERE users_sessions.expires_at < CURRENT_TIMESTAMP;
```

#### Multiple Conflict Targets

```sql
-- Conflict on multiple columns
INSERT INTO user_preferences (user_id, preference_key, preference_value)
VALUES (1, 'theme', 'dark')
ON CONFLICT (user_id, preference_key)
DO UPDATE SET
    preference_value = EXCLUDED.preference_value,
    updated_at = CURRENT_TIMESTAMP;
```

#### Using EXCLUDED

```sql
-- EXCLUDED references the proposed row values
INSERT INTO products (sku, name, price, last_updated)
VALUES ('SKU-123', 'Widget', 29.99, CURRENT_TIMESTAMP)
ON CONFLICT (sku)
DO UPDATE SET
    name = EXCLUDED.name,
    price = EXCLUDED.price,
    last_updated = EXCLUDED.last_updated
WHERE products.price != EXCLUDED.price;  -- Only update if price changed
```

#### Bulk Upsert Pattern

```sql
-- Efficient bulk upsert
INSERT INTO users (email, name, verified_at)
VALUES
    ('alice@example.com', 'Alice', CURRENT_TIMESTAMP),
    ('bob@example.com', 'Bob', NULL),
    ('charlie@example.com', 'Charlie', CURRENT_TIMESTAMP)
ON CONFLICT (email)
DO UPDATE SET
    name = EXCLUDED.name,
    verified_at = COALESCE(users.verified_at, EXCLUDED.verified_at);
```

---

## 6. Advanced Query Patterns

### 6.1 CTE with Window Functions

Combine CTEs with window functions for powerful analytical queries:

```sql
WITH ranked_sales AS (
    SELECT
        sales_date,
        amount,
        ROW_NUMBER() OVER (ORDER BY amount DESC) as rank,
        PERCENT_RANK() OVER (ORDER BY amount DESC) as pct_rank
    FROM sales
),
quartiles AS (
    SELECT
        amount,
        NTILE(4) OVER (ORDER BY amount) as quartile
    FROM sales
)
SELECT
    rs.sales_date,
    rs.amount,
    rs.rank,
    ROUND(rs.pct_rank * 100, 2) as pct_rank,
    q.quartile
FROM ranked_sales rs
JOIN quartiles q ON rs.amount = q.amount
ORDER BY rs.rank
LIMIT 10;
```

### 6.2 JSON Aggregation with Complex Structures

```sql
-- Build hierarchical JSON structures
SELECT
    c.customer_id,
    c.name,
    jsonb_agg(
        jsonb_build_object(
            'order_id', o.order_id,
            'order_date', o.order_date,
            'total', o.total,
            'items', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'product_id', oi.product_id,
                        'quantity', oi.quantity,
                        'price', oi.unit_price
                    )
                )
                FROM order_items oi
                WHERE oi.order_id = o.order_id
            )
        ) ORDER BY o.order_date DESC
    ) as orders
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.name;
```

### 6.3 Recursive CTE for Path Finding

```sql
-- Find shortest path in a graph
WITH RECURSIVE path_search AS (
    -- Start node
    SELECT
        node_id,
        target_id,
        ARRAY[node_id, target_id] as path,
        1 as distance
    FROM edges
    WHERE node_id = 'START'

    UNION ALL

    -- Extend path
    SELECT
        ps.node_id,
        e.target_id,
        ps.path || e.target_id,
        ps.distance + 1
    FROM path_search ps
    JOIN edges e ON ps.target_id = e.node_id
    WHERE NOT e.target_id = ANY(ps.path)  -- Avoid cycles
        AND ps.distance < 10
)
SELECT * FROM path_search
WHERE target_id = 'END'
ORDER BY distance
LIMIT 1;
```

---

## 7. Performance Considerations

### 7.1 Index Selection for Advanced Features

```sql
-- GIN index for JSON containment queries
CREATE INDEX idx_config_data ON config_jsonb USING GIN (data);

-- Expression index for computed columns
CREATE INDEX idx_lower_email ON users (LOWER(email));

-- BRIN index for large tables with natural ordering
CREATE INDEX idx_events_timestamp ON events USING BRIN (timestamp);

-- Partial index for filtered queries
CREATE INDEX idx_active_users ON users (user_id)
WHERE status = 'active';
```

### 7.2 Query Planning for Window Functions

```sql
-- Window functions are generally efficient but check plans
EXPLAIN (ANALYZE)
SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC) as rank
FROM employees;

-- For large partitions, ensure proper indexes on partition columns
CREATE INDEX idx_employees_dept ON employees (department_id);
```

---

## Summary

PostgreSQL's SQL dialect extends the SQL standard with:

1. **Rich Type System**: Comprehensive built-in types and ability to create custom types
2. **Advanced Analytics**: Window functions and CTEs for complex analytical queries
3. **JSON Support**: Native JSONB with efficient indexing and querying
4. **Procedural Logic**: PL/pgSQL for complex business logic
5. **Practical Extensions**: DISTINCT ON, RETURNING, and UPSERT (INSERT ... ON CONFLICT)
6. **Performance Features**: Prepared statements and strategic indexing

These features make PostgreSQL exceptionally capable for diverse application requirements, from simple transactional systems to complex analytical platforms.
