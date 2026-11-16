---
tags: [freshmart, sql]
---

# FreshMart 4: Business queries

Twenty queries the application and the business actually run. The SQL is
included from `sql/queries/business_queries.sql`, so the page and the script
cannot drift apart. `:name` values are bind variables.

Results marked *verified* are checked by `tests/verify_outputs.py`; the others
are derived by hand from the sample data. Nothing on this page was executed on
Oracle.

## Customer and catalog

### 1. Customer registration

```sql
--8<-- "sql/queries/business_queries.sql:q01"
```

`RETURNING` gives the generated key without a second query. A duplicate email
fails with `ORA-00001 (UQ_CUSTOMERS_EMAIL)`: map it to "account already exists".

### 2. Product catalog (keyset pagination)

```sql
--8<-- "sql/queries/business_queries.sql:q02"
```

First page (`:last_name` null):

| PRODUCT_ID | PRODUCT_NAME | UNIT_PRICE | CATEGORY_NAME |
|---:|---|---:|---|
| 1 | Apple Royal Gala 1kg | 180 | Fruits |
| 10 | Assam Tea 250g | 150 | Beverages |
| 2 | Banana Robusta 1 dozen | 60 | Fruits |
| 11 | Basmati Rice 5kg | 650 | Staples |
| 6 | Eggs 12 pack | 84 | Dairy and Eggs |

### 3. Product search

```sql
--8<-- "sql/queries/business_queries.sql:q03"
```

`:term = 'b'` returns Banana Robusta 1 dozen and Basmati Rice 5kg.

### 4. Category browsing

```sql
--8<-- "sql/queries/business_queries.sql:q04"
```

`:category_id = 1` (Fresh Produce) returns the four products of its
subcategories: Apple, Banana, Onion, Tomato.

## Cart and checkout

### 5. Shopping cart

```sql
--8<-- "sql/queries/business_queries.sql:q05"
```

For customer 103:

| PRODUCT_NAME | QUANTITY | UNIT_PRICE | LINE_TOTAL | CART_TOTAL |
|---|---:|---:|---:|---:|
| Apple Royal Gala 1kg | 1 | 180 | 180 | 330 |
| Assam Tea 250g | 1 | 150 | 150 | 330 |

### 6. Add and remove cart items

```sql
--8<-- "sql/queries/business_queries.sql:q06"
```

### 7. Order placement

```sql
--8<-- "sql/queries/business_queries.sql:q07"
```

The procedure reserves stock, validates the coupon, writes the order and its
lines and closes the cart, in one transaction
([implementation](03-implementation.md)).

### 8. Inventory reservation

```sql
--8<-- "sql/queries/business_queries.sql:q08"
```

The statement that makes overselling impossible
([2.11](../transactions/01-transactions-concurrency.md)).

### 9. Payment records

```sql
--8<-- "sql/queries/business_queries.sql:q09"
```

For order 1007 (one failed UPI attempt, then a successful card payment):

| ORDER_ID | TOTAL_AMOUNT | PAID | FAILED_ATTEMPTS |
|---:|---:|---:|---:|
| 1007 | 736 | 736 | 1 |

### 10. Order cancellation

```sql
--8<-- "sql/queries/business_queries.sql:q10"
```

Order 1007 (`PLACED`) can be cancelled: its reserved Milk (2) and Rice (1) are
released. Order 1001 (`DELIVERED`) raises `ORA-20004`.

## After the sale

### 11. Refunds

```sql
--8<-- "sql/queries/business_queries.sql:q11"
```

| ORDER_ID | STATUS | PAYMENT_REFUNDED | RETURN_REFUNDED |
|---:|---|---:|---:|
| 1003 | DELIVERED | 0 | 95 |
| 1005 | CANCELLED | 270 | 0 |

### 12. Returns

```sql
--8<-- "sql/queries/business_queries.sql:q12"
```

The insert enforces three rules in one statement: the order is delivered, the
line exists, and the quantity does not exceed what is still returnable. Open
requests on the sample data:

| RETURN_ID | ORDER_ID | PRODUCT_NAME | QUANTITY | REASON | REFUND_AMOUNT |
|---:|---:|---|---:|---|---:|
| 2 | 1006 | Orange Juice 1L | 1 | Product near expiry | 120 |

### 13. Shipment tracking

```sql
--8<-- "sql/queries/business_queries.sql:q13"
```

For customer 101 (timestamps abbreviated):

| ORDER_ID | ORDER_STATUS | CARRIER | TRACKING_NUMBER | SHIPMENT_STATUS | DELIVERED_BY |
|---:|---|---|---|---|---|
| 1007 | PLACED | *(null)* | *(null)* | *(null)* | *(null)* |
| 1003 | DELIVERED | FreshMart Fleet | FM-TRK-0003 | DELIVERED | Fatima Khan |
| 1001 | DELIVERED | FreshMart Fleet | FM-TRK-0001 | DELIVERED | Fatima Khan |

### 14. Coupon validation

```sql
--8<-- "sql/queries/business_queries.sql:q14"
```

| Coupon, subtotal, date | Result |
|---|---|
| `WELCOME10`, 800, 2025-03-03 | 80 (10%) |
| `FRESH50`, 786, 2025-04-05 | 50 (flat) |
| `FRESH50`, 400, 2025-04-05 | `ORA-20003` (below the minimum of 500) |
| `NEWYEAR5`, 800, 2025-01-15 | `ORA-20003` (inactive) |

## Analytics

### 15. Product recommendations

```sql
--8<-- "sql/queries/business_queries.sql:q15"
```

For `:product_id = 5` (Milk), *verified*: Apple, Basmati Rice, Onion, Tomato
and Whole Wheat Bread, each bought together once.

### 16. Low-stock report

```sql
--8<-- "sql/queries/business_queries.sql:q16"
```

*Verified:*

| WAREHOUSE_NAME | PRODUCT_NAME | QTY_AVAILABLE | REORDER_LEVEL | SUGGESTED_ORDER_QTY |
|---|---|---:|---:|---:|
| Bengaluru South FC | Whole Wheat Bread 400g | 10 | 15 | 20 |
| Delhi NCR FC | Wheat Flour 5kg | 8 | 10 | 12 |
| Mumbai Central FC | Paneer 200g | 15 | 20 | 25 |

### 17. Sales report

```sql
--8<-- "sql/queries/business_queries.sql:q17"
```

*Verified:*

| MONTH | ORDERS | REVENUE | CHANGE_VS_PREVIOUS |
|---|---:|---:|---:|
| 2025-03 | 4 | 2139 | *(null)* |
| 2025-04 | 3 | 1549 | -590 |

### 18. Customer purchase history

```sql
--8<-- "sql/queries/business_queries.sql:q18"
```

For customer 102:

| ORDER_ID | ORDER_DATE | STATUS | TOTAL_AMOUNT | ITEMS |
|---:|---|---|---:|---|
| 1006 | 2025-04-02 | DELIVERED | 420 | Apple Royal Gala 1kg x1, Orange Juice 1L x1, Whole Wheat Bread 400g x2 |
| 1002 | 2025-03-03 | DELIVERED | 720 | Basmati Rice 5kg x1, Assam Tea 250g x1 |

### 19. Best-selling products

```sql
--8<-- "sql/queries/business_queries.sql:q19"
```

*Verified:*

| PRODUCT_NAME | UNITS_SOLD | REVENUE | REVENUE_RANK |
|---|---:|---:|---:|
| Basmati Rice 5kg | 2 | 1300 | 1 |
| Apple Royal Gala 1kg | 3 | 540 | 2 |
| Full Cream Milk 1L | 7 | 476 | 3 |
| Assam Tea 250g | 2 | 300 | 4 |
| Eggs 12 pack | 3 | 252 | 5 |

### 20. Warehouse inventory report

```sql
--8<-- "sql/queries/business_queries.sql:q20"
```

*Verified (units and value):*

| WAREHOUSE_NAME | PRODUCTS_STOCKED | UNITS_ON_HAND | UNITS_RESERVED | STOCK_VALUE |
|---|---:|---:|---:|---:|
| Bengaluru South FC | 6 | 205 | 0 | 55300 |
| Delhi NCR FC | 4 | 283 | 0 | 14630 |
| Mumbai Central FC | 9 | 620 | 3 | 78265 |

## Index support for these queries

| Query | Index used (expected) |
|---|---|
| 2 | A composite on `(product_name, product_id)` would be added at scale |
| 3 | `ix_products_name_upper` |
| 5, 6 | `pk_cart_items`, `ix_carts_customer` |
| 8 | `pk_inventory` |
| 13, 18 | `ix_orders_cust_date`, `pk_order_items`, `uq_shipments_order` |
| 15 | `ix_order_items_product`, `pk_order_items` |
| 16, 17, 19, 20 | Full scans today; materialized views or partition pruning at scale ([scaling](05-scaling.md)) |

Next: [Scaling](05-scaling.md).
