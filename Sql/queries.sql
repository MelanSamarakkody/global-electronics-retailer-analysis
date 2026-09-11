-- ============================================================
-- Global Electronics Retailer — SQL Analysis
-- Excel -> MySQL -> Power BI end-to-end BA project
-- ============================================================
-- All queries below were validated by cross-checking totals
-- against independently built Power BI DAX measures.
-- ============================================================


-- ============================================================
-- SCHEMA
-- Star schema: one fact table (Sales) + four dimension tables
-- ============================================================

CREATE DATABASE global_electronics_retailer;
USE global_electronics_retailer;

CREATE TABLE Products (
    ProductKey INT PRIMARY KEY,
    ProductName VARCHAR(255),
    Brand VARCHAR(100),
    Color VARCHAR(50),
    UnitCostUSD DECIMAL(10,2),
    UnitPriceUSD DECIMAL(10,2),
    SubcategoryKey VARCHAR(10),
    Subcategory VARCHAR(100),
    CategoryKey VARCHAR(10),
    Category VARCHAR(100)
);

CREATE TABLE Customers (
    CustomerKey INT PRIMARY KEY,
    Gender VARCHAR(255),
    Name VARCHAR(100),
    City VARCHAR(50),
    StateCode VARCHAR(50),
    State VARCHAR(50),
    ZipCode VARCHAR(20),
    Country VARCHAR(100),
    Continent VARCHAR(100),
    Birthday DATE
);

CREATE TABLE Stores (
    StoreKey INT PRIMARY KEY,
    Country VARCHAR(255),
    State VARCHAR(100),
    SquareMeters INT,
    OpenDate DATE
);

-- Exchange_Rates has no single natural ID column — a rate is only
-- unique by the combination of Date + Currency, so that pair
-- becomes a composite primary key.
CREATE TABLE Exchange_Rates (
    Date DATE,
    Currency VARCHAR(10),
    Exchange DECIMAL(10,4),
    PRIMARY KEY (Date, Currency)
);

-- Sales is the fact table — one row per order line item.
-- Also uses a composite key: one order can have multiple line items,
-- so OrderNumber alone isn't unique, but OrderNumber + LineItem is.
-- CurrencyCode is intentionally NOT a foreign key to Exchange_Rates,
-- since Currency alone isn't unique there (many dates share a currency) —
-- the relationship only makes sense at query time, joining on both
-- CurrencyCode AND OrderDate together (see queries below).
CREATE TABLE Sales (
    OrderNumber INT,
    LineItem INT,
    OrderDate DATE,
    DeliveryDate DATE,
    CustomerKey INT,
    StoreKey INT,
    ProductKey INT,
    Quantity INT,
    CurrencyCode VARCHAR(10),
    PRIMARY KEY (OrderNumber, LineItem),
    FOREIGN KEY (CustomerKey) REFERENCES Customers(CustomerKey),
    FOREIGN KEY (StoreKey) REFERENCES Stores(StoreKey),
    FOREIGN KEY (ProductKey) REFERENCES Products(ProductKey)
);


-- ============================================================
-- KPI 1 — Profit by Product
-- No currency conversion needed: Products.UnitCostUSD/UnitPriceUSD
-- are the company's fixed global list prices, already in USD.
-- ============================================================

-- Highest profit
SELECT
    p.ProductKey,
    p.ProductName,
    SUM(s.Quantity * (p.UnitPriceUSD - p.UnitCostUSD)) AS TotalProfit
FROM Sales s
JOIN Products p ON s.ProductKey = p.ProductKey
GROUP BY p.ProductKey, p.ProductName
ORDER BY TotalProfit DESC
LIMIT 10;

-- Lowest profit (same query, ascending)
SELECT
    p.ProductKey,
    p.ProductName,
    SUM(s.Quantity * (p.UnitPriceUSD - p.UnitCostUSD)) AS TotalProfit
FROM Sales s
JOIN Products p ON s.ProductKey = p.ProductKey
GROUP BY p.ProductKey, p.ProductName
ORDER BY TotalProfit ASC
LIMIT 10;


-- ============================================================
-- KPI 2 — Revenue by Store
-- Revenue reflects what was actually charged, in the customer's
-- local currency, so it DOES need converting to a common USD
-- basis using that day's exchange rate.
--
-- Exchange rate is defined as "1 USD = X units of foreign currency"
-- (confirmed: USD rows always show Exchange = 1.0000), so converting
-- a foreign-currency amount back to USD means DIVIDING by the rate,
-- not multiplying.
-- ============================================================

SELECT
    st.Country,
    st.State,
    SUM(s.Quantity * p.UnitPriceUSD / er.Exchange) AS TotalRevenueUSD
FROM Sales s
JOIN Products p ON s.ProductKey = p.ProductKey
JOIN Stores st ON s.StoreKey = st.StoreKey
JOIN Exchange_Rates er
    ON s.CurrencyCode = er.Currency
    AND s.OrderDate = er.Date
GROUP BY st.StoreKey, st.Country, st.State
ORDER BY TotalRevenueUSD DESC;


-- ============================================================
-- KPI 3 — Monthly Revenue Trend
-- DATE_FORMAT collapses each date down to just its Year-Month,
-- so every sale within the same month groups together regardless
-- of which exact day it happened.
-- ============================================================

SELECT
    DATE_FORMAT(s.OrderDate, '%Y-%m') AS SalesMonth,
    SUM(s.Quantity * p.UnitPriceUSD / er.Exchange) AS TotalRevenueUSD,
    SUM(s.Quantity) AS TotalQuantity
FROM Sales s
JOIN Products p ON s.ProductKey = p.ProductKey
JOIN Exchange_Rates er
    ON s.CurrencyCode = er.Currency
    AND s.OrderDate = er.Date
GROUP BY SalesMonth
ORDER BY SalesMonth ASC;


-- ============================================================
-- KPI 4 — Quantity by Product
-- ============================================================

-- Most units sold
SELECT
    p.ProductKey,
    p.ProductName,
    SUM(s.Quantity) AS TotalQuantity
FROM Sales s
JOIN Products p ON s.ProductKey = p.ProductKey
GROUP BY p.ProductKey, p.ProductName
ORDER BY TotalQuantity DESC
LIMIT 10;

-- Fewest units sold
SELECT
    p.ProductKey,
    p.ProductName,
    SUM(s.Quantity) AS TotalQuantity
FROM Sales s
JOIN Products p ON s.ProductKey = p.ProductKey
GROUP BY p.ProductKey, p.ProductName
ORDER BY TotalQuantity ASC
LIMIT 10;


-- ============================================================
-- KPI 5 — Revenue by Customer Country
-- Same revenue logic as KPI 2, but grouped by the customer's
-- own country instead of the store's country — a different,
-- equally valid way of slicing the same money (e.g. a US
-- customer's online order counts as "US" here, but as "Online"
-- in the by-store view).
-- ============================================================

SELECT
    c.Country,
    SUM(s.Quantity * p.UnitPriceUSD / er.Exchange) AS TotalRevenue
FROM Sales s
JOIN Customers c ON s.CustomerKey = c.CustomerKey
JOIN Products p ON s.ProductKey = p.ProductKey
JOIN Exchange_Rates er
    ON s.CurrencyCode = er.Currency
    AND s.OrderDate = er.Date
GROUP BY c.Country
ORDER BY TotalRevenue DESC;


-- ============================================================
-- KPI 6 — Revenue by Customer Age Group
-- Age is calculated as of OrderDate (the customer's age at the
-- time they actually bought something), not today's date — more
-- analytically correct than a "current age" snapshot.
-- CASE WHEN buckets each row into one of four age ranges.
-- ============================================================

SELECT
    CASE
        WHEN TIMESTAMPDIFF(YEAR, c.Birthday, s.OrderDate) BETWEEN 18 AND 25 THEN '18-25'
        WHEN TIMESTAMPDIFF(YEAR, c.Birthday, s.OrderDate) BETWEEN 26 AND 35 THEN '26-35'
        WHEN TIMESTAMPDIFF(YEAR, c.Birthday, s.OrderDate) BETWEEN 36 AND 45 THEN '36-45'
        ELSE '46+'
    END AS AgeGroup,
    SUM(s.Quantity * p.UnitPriceUSD / er.Exchange) AS TotalRevenue
FROM Sales s
JOIN Customers c ON s.CustomerKey = c.CustomerKey
JOIN Products p ON s.ProductKey = p.ProductKey
JOIN Exchange_Rates er
    ON s.CurrencyCode = er.Currency
    AND s.OrderDate = er.Date
GROUP BY AgeGroup
ORDER BY TotalRevenue DESC;
