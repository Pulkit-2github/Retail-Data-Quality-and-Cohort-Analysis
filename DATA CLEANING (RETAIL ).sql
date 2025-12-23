--Data Auditing and Cleaning

--1 Removing special charaters present in customer_city colun in customer table

select * from [dbo].[Customers]

select [customer_city] from [dbo].[Customers]
WHERE customer_city LIKE '%@%';

UPDATE Customers_104
SET customer_city = REPLACE(customer_city, '@', ' ')
WHERE customer_city LIKE '%@%';
--_______________________________________________________________________________

--2 filling the missing values as unknown in category column in product info table 

select * from [dbo].[product_info]

select Category from [dbo].[product_info]
where Category like '#N/A'

UPDATE [dbo].[ProductsInfo_104]
SET Category = 'Unknown'
WHERE Category = '#N/A';
--___________________________________________________________________________________

--3 Dropping the dates where orders are placed in 2020

select * from [dbo].[orders]

SELECT COUNT(*) AS total_orders_2020
FROM [dbo].[orders]
WHERE YEAR(TRY_CAST(Bill_date_timestamp AS datetime)) = 2020;

DELETE FROM [dbo].[Orders_104]
WHERE YEAR(TRY_CAST(Bill_date_timestamp AS datetime)) = 2020;

--_____________________________________________________________________________________________-

--4 Deleting the duplicates in Stores_info table 

SELECT StoreID, seller_city, seller_state, Region, 
COUNT(*) AS duplicate_count FROM 
StoresInfo_104 GROUP BY 
StoreID, seller_city, seller_state, Region
HAVING COUNT(*) > 1;

WITH Duplicates AS (SELECT 
StoreID, seller_city, seller_state, Region,
ROW_NUMBER() OVER (PARTITION BY StoreID, seller_city, seller_state, Region ORDER BY (SELECT NULL)) AS row_num
FROM StoresInfo_104)
DELETE FROM Duplicates
WHERE row_num > 1;

select * from [dbo].[stores_info]
--___________________________________________________________________________

--5 In OrderReview_Ratings table  any duplicates - aggregate the data at order id level, take average score

SELECT o.order_id, 
AVG(orr.Customer_Satisfaction_Score) AS avg_satisfaction_score
FROM 
[dbo].[OrderReview_Ratings_104] orr
JOIN 
orders o ON orr.order_id = o.order_id
GROUP BY o.order_id;

SELECT o.order_id, 
AVG(orr.Customer_Satisfaction_Score) AS avg_satisfaction_score
INTO #AggregatedReviewRatings
FROM 
[dbo].[OrderReview_Ratings_104] orr
JOIN 
orders o ON orr.order_id = o.order_id
GROUP BY o.order_id;

DELETE FROM [dbo].[OrderReview_Ratings_104]
WHERE order_id IN (SELECT order_id FROM #AggregatedReviewRatings);

INSERT INTO [dbo].[OrderReview_Ratings_104] (order_id, Customer_Satisfaction_Score)
SELECT order_id, avg_satisfaction_score
FROM #AggregatedReviewRatings;

DROP TABLE #AggregatedReviewRatings;

select * from [dbo].[OrderReview_Ratings_104]
--_______________________________________________________________________________

--6 Rounding the Amount columns to 2 decimal points 

-- For Orders Table
UPDATE Orders_104
SET [Total Amount] = ROUND([Total Amount], 2);

UPDATE Orders_104
SET [MRP] = ROUND([MRP], 2);

UPDATE Orders_104
SET [Cost Per Unit] = ROUND([Cost Per Unit], 2);

select * from [dbo].[Orders_104]

-- For Order Payment Table
UPDATE [dbo].[OrderPayments_104]
SET payment_value = ROUND(payment_value, 2)

select * from [dbo].[OrderPayments_104]
--_________________________________________________________________________________

--7 Identifying and Removing Duplicate Records in the orders_payment Table

SELECT order_id, payment_type, payment_value, COUNT(*) AS count_duplicates
FROM [dbo].[OrderPayments_104]
GROUP BY order_id, payment_type, payment_value
HAVING COUNT(*) > 1;

WITH CTE_Duplicates AS (SELECT 
ROW_NUMBER() OVER (PARTITION BY order_id, payment_type, payment_value ORDER BY (SELECT NULL)) AS row_num,
*FROM [dbo].[OrderPayments_104])

DELETE FROM CTE_Duplicates
WHERE row_num > 1;
--_________________________________________________________________________________

--8 To check the mismatch in total_amount in orders table and payment value in orderspayment 
SELECT 
o.order_id, o.orders_total_amount, p.payment_total_amount, 
(o.orders_total_amount - p.payment_total_amount) AS mismatch_amount
FROM (SELECT order_id, 
SUM([Total Amount]) AS orders_total_amount
FROM Orders_104
GROUP BY order_id) o
LEFT JOIN (SELECT order_id, 
SUM(payment_value) AS payment_total_amount
FROM [dbo].[OrderPayments_104]
GROUP BY order_id) p
ON o.order_id = p.order_id
WHERE ABS(o.orders_total_amount - p.payment_total_amount) > 1;
--______________________________________________________________________________________________

--Finding the maximum quantity for each combination of Customer_id, order_id, and product_id where 
--all three are same

WITH MaxQuantityOrders AS (SELECT 
Customer_id, order_id, product_id, 
MAX(Quantity) AS max_quantity
FROM Orders_104
GROUP BY 
Customer_id, order_id, product_id)
SELECT o.Customer_id, o.order_id, o.product_id, o.Quantity, mqo.max_quantity
FROM Orders_104 o
JOIN MaxQuantityOrders mqo
ON o.Customer_id = mqo.Customer_id
AND o.order_id = mqo.order_id
AND o.product_id = mqo.product_id
WHERE o.Quantity < mqo.max_quantity;

--Deleting the records where the quantity is less than the maximum quantity for that case.

WITH MaxQuantityOrders AS (SELECT 
Customer_id, order_id, product_id, 
MAX(Quantity) AS max_quantity
FROM Orders_104
GROUP BY 
Customer_id, order_id, product_id)
DELETE o
FROM Orders_104 o
JOIN MaxQuantityOrders mqo
ON o.Customer_id = mqo.Customer_id
AND o.order_id = mqo.order_id
AND o.product_id = mqo.product_id
WHERE o.Quantity < mqo.max_quantity;

select * from [dbo].[Orders_104]

------------------------------------------------
-- if customerid, orderid is same and product id is different and having multiple products with cumulative
--quantity, replace quantity with 1

WITH CumulativeQuantityOrders AS (SELECT 
Customer_id, order_id, 
COUNT(DISTINCT product_id) AS product_count
FROM Orders_104
GROUP BY 
Customer_id, order_id
HAVING COUNT(DISTINCT product_id) > 1)

SELECT o.Customer_id, o.order_id, o.product_id, o.Quantity
FROM Orders_104 o
JOIN CumulativeQuantityOrders cqo
ON o.Customer_id = cqo.Customer_id
AND o.order_id = cqo.order_id
WHERE cqo.product_count > 1;

-- updating

WITH CumulativeQuantityOrders AS (SELECT 
Customer_id, order_id, 
COUNT(DISTINCT product_id) AS product_count
FROM Orders_104
GROUP BY Customer_id, order_id
HAVING COUNT(DISTINCT product_id) > 1)
UPDATE o
SET o.Quantity = 1
FROM Orders_104 o
JOIN CumulativeQuantityOrders cqo
ON o.Customer_id = cqo.Customer_id
AND o.order_id = cqo.order_id
WHERE cqo.product_count > 1;
--_________________________________________________________________________
 -- total amount is not calulated properly therefore recalulating the total amount 
 select * from [dbo].[Orders_104]

UPDATE Orders_104
SET [Total Amount] = (Quantity * MRP - discount)
WHERE [Total Amount] <> (Quantity * MRP - discount);

------------------------------------------------------------------------------------------------

--____________________________________________________________________________________

--10 Calculate new columns Total Cost, Profit

ALTER TABLE [dbo].[orders_104]
ADD Total_Cost FLOAT, 
    Profit FLOAT;

UPDATE [dbo].[Orders_104]
SET 
    Total_Cost = Quantity * [Cost Per Unit],  
    Profit = [Total Amount] - (Quantity *[Cost Per Unit]);
	
UPDATE Orders_104
SET Profit = ROUND(Profit, 2);

select * from [dbo].[Orders_104]
----------------------------------------------------------------------------------------------------------------
                               ---Creating customer Level data------


CREATE TABLE Customer_Level_360 (
Custid Bigint,
customer_city VARCHAR(255),
customer_state VARCHAR(255),
Gender VARCHAR(50),
First_Transaction_Date DATE,
Last_Transaction_Date DATE,
Tenure INT,
Inactive_Days INT,
Frequency INT,
Monetary FLOAT,
Profit FLOAT,
Discount FLOAT,
Total_Quantity INT,
Distinct_Items_Purchased INT,
Distinct_Categories_Purchased INT,
Transactions_With_Discount INT,
Transactions_With_Loss INT,
Channels_Used INT,
Distinct_Stores_Purchased INT,
Distinct_Cities_Purchased INT,
Distinct_Payment_Types_Used INT,
Transactions_Paid_With_Voucher INT,
Transactions_Paid_With_Credit_Card INT,
Transactions_Paid_With_Debit_Card INT,
Transactions_Paid_With_UPI INT,
Preferred_Payment_Method VARCHAR(50));

select * from [dbo].[Customer_Level_360]

--Inserting Records

WITH PaymentSummary AS (SELECT 
TRY_CAST(o.Customer_id AS BIGINT) AS Custid, -- Explicit conversion
p.payment_type,
COUNT(p.payment_type) AS Payment_Count,
ROW_NUMBER() OVER (PARTITION BY o.Customer_id ORDER BY COUNT(p.payment_type) DESC) AS rn
FROM Orders_104 o
LEFT JOIN OrderPayments_104 p ON o.order_id = p.order_id
WHERE ISNUMERIC(o.Customer_id) = 1 -- Ensure numeric values only
GROUP BY o.Customer_id, p.payment_type),
CustomerData AS (SELECT 
TRY_CAST(o.Customer_id AS BIGINT) AS Custid, -- Explicit conversion
MIN(CAST(o.Bill_date_timestamp AS DATE)) AS First_Transaction_Date,
MAX(CAST(o.Bill_date_timestamp AS DATE)) AS Last_Transaction_Date,
DATEDIFF(DAY, MIN(CAST(o.Bill_date_timestamp AS DATE)), MAX(CAST(o.Bill_date_timestamp AS DATE))) AS Tenure,
COUNT(DISTINCT CAST(o.Bill_date_timestamp AS DATE)) AS Frequency,
SUM(o.[Cost Per Unit]) AS Monetary,
SUM((o.MRP - o.[Cost Per Unit]) * o.Quantity) AS Profit,
SUM(o.Discount) AS Discount,
SUM(o.Quantity) AS Total_Quantity,
COUNT(DISTINCT o.product_id) AS Distinct_Items_Purchased,
COUNT(DISTINCT p.Category) AS Distinct_Categories_Purchased,
SUM(CASE WHEN o.Discount > 0 THEN 1 ELSE 0 END) AS Transactions_With_Discount,
SUM(CASE WHEN o.MRP < o.[Cost Per Unit] THEN 1 ELSE 0 END) AS Transactions_With_Loss,
COUNT(DISTINCT o.Channel) AS Channels_Used,
COUNT(DISTINCT o.Delivered_StoreID) AS Distinct_Stores_Purchased,
COUNT(DISTINCT si.seller_city) AS Distinct_Cities_Purchased
FROM Orders_104 o
LEFT JOIN ProductsInfo_104 p ON o.product_id = p.product_id
LEFT JOIN StoresInfo_104 si ON o.Delivered_StoreID = si.StoreID
WHERE ISNUMERIC(o.Customer_id) = 1 -- Ensure numeric values only
GROUP BY o.Customer_id)
INSERT INTO Customer_Level_360(
Custid, 
customer_city, 
customer_state, 
Gender, 
First_Transaction_Date, 
Last_Transaction_Date, 
Tenure, 
Inactive_Days, 
Frequency, 
Monetary, 
Profit, 
Discount, 
Total_Quantity, 
Distinct_Items_Purchased, 
Distinct_Categories_Purchased, 
Transactions_With_Discount, 
Transactions_With_Loss, 
Channels_Used, 
Distinct_Stores_Purchased, 
Distinct_Cities_Purchased, 
Distinct_Payment_Types_Used, 
Transactions_Paid_With_Voucher, 
Transactions_Paid_With_Credit_Card, 
Transactions_Paid_With_Debit_Card, 
Transactions_Paid_With_UPI, 
Preferred_Payment_Method)
SELECT 
    cd.Custid,
    c.customer_city,
    c.customer_state,
    c.Gender,
    cd.First_Transaction_Date,
    cd.Last_Transaction_Date,
    cd.Tenure,
    DATEDIFF(DAY, cd.Last_Transaction_Date, GETDATE()) AS Inactive_Days,
    cd.Frequency,
    cd.Monetary,
    cd.Profit,
    cd.Discount,
    cd.Total_Quantity,
    cd.Distinct_Items_Purchased,
    cd.Distinct_Categories_Purchased,
    cd.Transactions_With_Discount,
    cd.Transactions_With_Loss,
    cd.Channels_Used,
    cd.Distinct_Stores_Purchased,
    cd.Distinct_Cities_Purchased,
    COUNT(DISTINCT ps.payment_type) AS Distinct_Payment_Types_Used,
    SUM(CASE WHEN ps.payment_type = 'Voucher' THEN ps.Payment_Count ELSE 0 END) AS Transactions_Paid_With_Voucher,
    SUM(CASE WHEN ps.payment_type = 'Credit Card' THEN ps.Payment_Count ELSE 0 END) AS Transactions_Paid_With_Credit_Card,
    SUM(CASE WHEN ps.payment_type = 'Debit Card' THEN ps.Payment_Count ELSE 0 END) AS Transactions_Paid_With_Debit_Card,
    SUM(CASE WHEN ps.payment_type = 'UPI' THEN ps.Payment_Count ELSE 0 END) AS Transactions_Paid_With_UPI,
    MAX(CASE WHEN ps.rn = 1 THEN ps.payment_type ELSE NULL END) AS Preferred_Payment_Method
FROM 
CustomerData cd
LEFT JOIN 
Customers_104 c ON cd.Custid = c.Custid
LEFT JOIN 
PaymentSummary ps ON cd.Custid = ps.Custid
GROUP BY 
    cd.Custid, 
    c.customer_city, 
    c.customer_state, 
    c.Gender, 
    cd.First_Transaction_Date, 
    cd.Last_Transaction_Date, 
    cd.Tenure, 
    cd.Frequency, 
    cd.Monetary, 
    cd.Profit, 
    cd.Discount, 
    cd.Total_Quantity, 
    cd.Distinct_Items_Purchased, 
    cd.Distinct_Categories_Purchased, 
    cd.Transactions_With_Discount, 
    cd.Transactions_With_Loss, 
    cd.Channels_Used, 
    cd.Distinct_Stores_Purchased, 
    cd.Distinct_Cities_Purchased;


select * from [dbo].[Customer_Level_360]
--_______________________________________________________________________________________---

                             -- creating order level data--

CREATE TABLE Order_Level_360 (
OrderID VARCHAR(50),
Custid BIGINT,
OrderDate DATETIME,
ProductID VARCHAR(50),
ProductCategory VARCHAR(255),
Quantity INT,
TotalAmount FLOAT,
Discount INT,
PaymentType VARCHAR(50),
PaymentAmount FLOAT,
SatisfactionScore INT,
StoreID VARCHAR(50),
StoreCity VARCHAR(255),
StoreState VARCHAR(255),
Region VARCHAR(255));

--Inserting records

WITH OrderPayment AS (SELECT 
order_id,
payment_type,
payment_value,
ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY payment_value DESC) AS rn
FROM [dbo].[OrderPayments_104]),
OrderReview AS (SELECT 
order_id,Customer_Satisfaction_Score,
ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY Customer_Satisfaction_Score DESC) AS rn
FROM [dbo].[OrderReview_Ratings_104]),
ProductInfo AS (
SELECT product_id,Category,
ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY product_id) AS rn
FROM ProductsInfo_104),
StoreInfo AS (
SELECT StoreID,seller_city,seller_state,Region,
ROW_NUMBER() OVER (PARTITION BY StoreID ORDER BY StoreID) AS rn
FROM StoresInfo_104)
INSERT INTO Order_Level_360(
    OrderID,
    Custid,
    OrderDate,
    ProductID,
    ProductCategory,
    Quantity,
    TotalAmount,
    Discount,
    PaymentType,
    PaymentAmount,
    SatisfactionScore,
    StoreID,
    StoreCity,
    StoreState,
    Region
)
SELECT
    o.order_id AS OrderID,
    o.Customer_id AS Custid,
    o.Bill_date_timestamp AS OrderDate, -- Keep date and time intact
    o.product_id AS ProductID,
    pi.Category AS ProductCategory,
    o.Quantity AS Quantity,
    o.[Total Amount] AS TotalAmount,
    o.Discount AS Discount,
    op.payment_type AS PaymentType,
    op.payment_value AS PaymentAmount,
    rr.Customer_Satisfaction_Score AS SatisfactionScore,
    o.Delivered_StoreID AS StoreID,
    si.seller_city AS StoreCity,
    si.seller_state AS StoreState,
    si.Region AS Region
FROM Orders_104 o
LEFT JOIN OrderPayment op ON o.order_id = op.order_id AND op.rn = 1
LEFT JOIN OrderReview rr ON o.order_id = rr.order_id AND rr.rn = 1
LEFT JOIN ProductInfo pi ON o.product_id = pi.product_id AND pi.rn = 1
LEFT JOIN StoreInfo si ON o.Delivered_StoreID = si.StoreID AND si.rn = 1;


select *from [dbo].[Order_Level_360]

--Adding some columns 
ALTER TABLE Order_Level_360
ADD total_cost FLOAT;

UPDATE old
SET old.Total_cost  = o.Total_Cost
FROM Order_Level_360 old
JOIN Orders_104 o ON old.OrderID = o.order_id;

ALTER TABLE order_level_360
ADD Profit FLOAT;

UPDATE Order_Level_360
SET Profit = [TotalAmount]-Total_cost

ALTER TABLE order_level_360
ADD channel NVARCHAR(255); 

UPDATE old
SET old.channel = o.channel
FROM Order_Level_360 AS old
JOIN Orders_104 AS o
    ON old.OrderID = o.order_id; 

ALTER TABLE order_level_360
ADD [Cost Per Unit] DECIMAL(18, 2); 

UPDATE old
SET old.[Cost Per Unit] = o.[Cost Per Unit]
FROM Order_Level_360 AS old
JOIN Orders_104 AS o
    ON old.OrderID = o.order_id;

ALTER TABLE order_level_360
ADD MRP FLOAT;

UPDATE old
SET old.MRP = o.MRP
FROM Order_Level_360 AS old
JOIN Orders_104 AS o
    ON old.OrderID = o.order_id

ALTER TABLE order_level_360
ADD Gender VARCHAR(10);  

UPDATE ol
SET ol.Gender = cl.Gender
FROM Order_Level_360 ol
JOIN Customer_Level_360 cl
    ON ol.CustID = cl.CustID;

ALTER TABLE order_level_360
ADD Store_state VARCHAR(30); 

UPDATE ol
SET ol.Store_state = cl.customer_state
FROM Order_Level_360 ol
JOIN [dbo].[Customers_104] cl
    ON ol.CustID = cl.CustID;


--________________________________________________________________________________________-

                                --creating store level data--

CREATE TABLE Store_Level_360 (
    StoreID VARCHAR(50),
    seller_city VARCHAR(255),
    seller_state VARCHAR(255),
    Region VARCHAR(255),
    Total_Transactions INT,
    Total_Quantity_Sold INT,
    Total_Sales FLOAT,
    Average_Discount FLOAT,
    Total_Profit FLOAT,
    Distinct_Customers_Visited INT,
    Distinct_Products_Sold INT,
    Distinct_Categories_Sold INT,
    Highest_Selling_Product VARCHAR(50),
    Most_Frequent_Customer VARCHAR(50),
    Transactions_With_Discount INT,
    Transactions_With_Loss INT,
    Most_Common_Payment_Type VARCHAR(50),
    Average_Customer_Satisfaction FLOAT,
    Active_Days INT,
    Max_Transaction_Date DATE,
    Min_Transaction_Date DATE);

select * from Store_Level_360

WITH HighestSellingProduct AS (
SELECT o.Delivered_StoreID AS StoreID,
o.product_id,
SUM(o.Quantity) AS Total_Quantity,
ROW_NUMBER() OVER (PARTITION BY o.Delivered_StoreID ORDER BY SUM(o.Quantity) DESC) AS rn
FROM Orders_104 o
GROUP BY o.Delivered_StoreID, o.product_id),
MostFrequentCustomer AS (SELECT 
o.Delivered_StoreID AS StoreID,
o.Customer_id,
COUNT(o.order_id) AS Total_Orders,
ROW_NUMBER() OVER (PARTITION BY o.Delivered_StoreID ORDER BY COUNT(o.order_id) DESC) AS rn
FROM Orders_104 o
GROUP BY o.Delivered_StoreID, o.Customer_id),
MostCommonPaymentType AS (
SELECT o.Delivered_StoreID AS StoreID,op.payment_type,
COUNT(op.order_id) AS PaymentCount,
ROW_NUMBER() OVER (PARTITION BY o.Delivered_StoreID ORDER BY COUNT(op.order_id) DESC) AS rn
FROM OrderPayments_104 op
JOIN Orders_104 o ON o.order_id = op.order_id
GROUP BY o.Delivered_StoreID, op.payment_type)
INSERT INTO Store_Level_360(
    StoreID,
    seller_city,
    seller_state,
    Region,
    Total_Transactions,
    Total_Quantity_Sold,
    Total_Sales,
    Average_Discount,
    Total_Profit,
    Distinct_Customers_Visited,
    Distinct_Products_Sold,
    Distinct_Categories_Sold,
    Highest_Selling_Product,
    Most_Frequent_Customer,
    Transactions_With_Discount,
    Transactions_With_Loss,
    Most_Common_Payment_Type,
    Average_Customer_Satisfaction,
    Active_Days,
    Max_Transaction_Date,
    Min_Transaction_Date
)
SELECT
    o.Delivered_StoreID AS StoreID,
    si.seller_city,
    si.seller_state,
    si.Region,
    COUNT(o.order_id) AS Total_Transactions,
    SUM(o.Quantity) AS Total_Quantity_Sold,
    SUM(o.[Total Amount]) AS Total_Sales,
    AVG(o.Discount) AS Average_Discount,
    SUM((o.MRP - o.[Cost Per Unit]) * o.Quantity) AS Total_Profit,
    COUNT(DISTINCT o.Customer_id) AS Distinct_Customers_Visited,
    COUNT(DISTINCT o.product_id) AS Distinct_Products_Sold,
    COUNT(DISTINCT pi.Category) AS Distinct_Categories_Sold,
    hsp.product_id AS Highest_Selling_Product,
    mfc.Customer_id AS Most_Frequent_Customer,
    SUM(CASE WHEN o.Discount > 0 THEN 1 ELSE 0 END) AS Transactions_With_Discount,
    SUM(CASE WHEN (o.MRP - o.[Cost Per Unit]) * o.Quantity < 0 THEN 1 ELSE 0 END) AS Transactions_With_Loss,
    mcp.payment_type AS Most_Common_Payment_Type,
    AVG(rr.Customer_Satisfaction_Score) AS Average_Customer_Satisfaction,
    COUNT(DISTINCT CAST(o.Bill_date_timestamp AS DATE)) AS Active_Days,
    MAX(CAST(o.Bill_date_timestamp AS DATE)) AS Max_Transaction_Date,
    MIN(CAST(o.Bill_date_timestamp AS DATE)) AS Min_Transaction_Date
FROM Orders_104 o
LEFT JOIN StoresInfo_104 si ON o.Delivered_StoreID = si.StoreID
LEFT JOIN ProductsInfo_104 pi ON o.product_id = pi.product_id
LEFT JOIN OrderReview_Ratings_104 rr ON o.order_id = rr.order_id
LEFT JOIN HighestSellingProduct hsp ON o.Delivered_StoreID = hsp.StoreID AND hsp.rn = 1
LEFT JOIN MostFrequentCustomer mfc ON o.Delivered_StoreID = mfc.StoreID AND mfc.rn = 1
LEFT JOIN MostCommonPaymentType mcp ON o.Delivered_StoreID = mcp.StoreID AND mcp.rn = 1
GROUP BY 
    o.Delivered_StoreID, si.seller_city, si.seller_state, si.Region, hsp.product_id, mfc.Customer_id, mcp.payment_type;
