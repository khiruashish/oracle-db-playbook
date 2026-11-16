---
tags: [freshmart, data-modeling]
---

# FreshMart 2: Data model

## ER diagram

The same diagram is kept as a standalone file in `diagrams/er/freshmart.mmd`.

```mermaid
--8<-- "diagrams/er/freshmart.mmd"
```

## Entities

| Entity | Kind | Primary key | Purpose |
|---|---|---|---|
| `categories` | Strong, recursive | `category_id` | Two-level product classification |
| `suppliers` | Strong | `supplier_id` | Who supplies a product |
| `products` | Strong | `product_id` (alternate: `sku`) | Catalog items and current prices |
| `warehouses` | Strong | `warehouse_id` | Fulfilment centers, one per city |
| `employees` | Strong, recursive | `employee_id` | Staff and reporting line |
| `customers` | Strong | `customer_id` (alternate: `email`) | Registered shoppers |
| `addresses` | Dependent on customer | `address_id` | Delivery locations |
| `inventory` | Associative (warehouse × product) | `(warehouse_id, product_id)` | Stock and reservations |
| `stock_movements` | Event | `movement_id` | History of stock changes |
| `carts` | Strong | `cart_id` | A customer's basket |
| `cart_items` | Weak, associative (cart × product) | `(cart_id, product_id)` | Basket lines |
| `promotions` | Strong | `promotion_id` | Discount definitions |
| `coupons` | Strong | `coupon_id` (alternate: `coupon_code`) | Redeemable codes for a promotion |
| `orders` | Strong | `order_id` | The commercial transaction |
| `order_items` | Weak, associative (order × product) | `(order_id, line_no)` | Order lines with price snapshot |
| `payments` | Dependent on order | `payment_id` | Payment attempts |
| `shipments` | Dependent on order (1:1) | `shipment_id` | Delivery |
| `returns` | Dependent on order item | `return_id` | Returned quantities and refunds |
| `reviews` | Associative (customer × product) | `review_id` (alternate: the pair) | Ratings |
| `audit_log` | Event | `audit_id` | Change history |

## Relationships and cardinality

| Parent | Child | Cardinality | Mandatory for child | On delete |
|---|---|---|---|---|
| categories | categories | 1 : 0..N | No (top level has none) | Restrict |
| categories | products | 1 : 0..N | Yes | Restrict |
| suppliers | products | 1 : 0..N | Yes | Restrict |
| customers | addresses | 1 : 0..N | Yes | **Cascade** |
| customers | carts | 1 : 0..N | Yes | Restrict |
| carts | cart_items | 1 : 0..N | Yes | **Cascade** |
| products | cart_items | 1 : 0..N | Yes | Restrict |
| warehouses | inventory | 1 : 0..N | Yes | Restrict |
| products | inventory | 1 : 0..N | Yes | Restrict |
| inventory | stock_movements | 1 : 0..N | Yes | Restrict |
| customers | orders | 1 : 0..N | Yes | Restrict |
| addresses | orders | 1 : 0..N | Yes | Restrict |
| warehouses | orders | 1 : 0..N | Yes | Restrict |
| coupons | orders | 1 : 0..N | No | Restrict |
| orders | order_items | 1 : 1..N | Yes | Restrict |
| products | order_items | 1 : 0..N | Yes | Restrict |
| orders | payments | 1 : 0..N | Yes | Restrict |
| orders | shipments | 1 : 0..1 | Yes | Restrict |
| employees | shipments | 1 : 0..N | No (third-party carriers) | Restrict |
| order_items | returns | 1 : 0..N | Yes | Restrict |
| promotions | coupons | 1 : 0..N | Yes | Restrict |
| products, customers | reviews | 1 : 0..N each | Yes | Restrict |
| employees | employees | 1 : 0..N | No (the head has no manager) | Restrict |
| warehouses | employees | 1 : 0..N | No (head office staff) | Restrict |

Cascade is used only for true parts of a whole. Deleting a customer with
orders is refused: commercial records are never removed by a cascade.

One relationship cannot be declared: `orders.address_id` should belong to the
same customer as `orders.customer_id`. It can be made declarative by adding a
unique constraint on `addresses (address_id, customer_id)` and a composite
foreign key from `orders`; FreshMart leaves this as an exercise and enforces it
in the application layer.

## Normalization review

| Table | Check | Result |
|---|---|---|
| `order_items` | Does `unit_price` duplicate `products.unit_price`? | No: it is the price at order time, a different fact |
| `order_items.line_total` | Derived | Virtual column: computed, never stored |
| `orders.subtotal`, `total_amount` | Derived from lines | Deliberate denormalization for read speed; guarded by `ck_orders_total` and written only by `order_pkg` |
| `customers.city` and `addresses.city` | Same fact twice? | No: registration city (marketing segment) versus delivery city |
| `coupons.used_count` | Derivable from `orders.coupon_id` | Deliberate: checked on every redemption under a row lock |
| `inventory.qty_reserved` | Derivable from open order lines | Deliberate: the hot path cannot aggregate order lines |
| `products` | `supplier_id → supplier city` transitive? | No: supplier attributes live in `suppliers` |
| `employees` | `job_title` repeated | Acceptable at this size; a `jobs` table if titles gain attributes |

All tables are in 3NF apart from the three documented, guarded derivations.

## Logical to physical decisions

| Decision | Choice | Reason |
|---|---|---|
| Keys | Surrogate identity columns; natural keys enforced by unique constraints | Stable joins; business keys can change |
| Identity mode | `GENERATED BY DEFAULT ON NULL` (audit log: `ALWAYS`) | Allows loading known ids; audit ids must never be supplied |
| Money | `NUMBER(p,2)` | Exact decimals |
| Flags | `CHAR(1)` with `CHECK ('Y','N')` | Works on 19c; `BOOLEAN` on 23ai+ |
| Status columns | `VARCHAR2` with `CHECK` lists | Readable; a lookup table when statuses gain attributes |
| Dates | `DATE` for business dates, `TIMESTAMP` for event times | Precision where needed |
| Audit columns | `created_at`, `updated_at`; `row_version` on contended tables | Support optimistic locking and debugging |
| Foreign keys | All declared, all indexed | Integrity; no child-table locks |
| Composite keys | For pure associations (`inventory`, `cart_items`, `order_items`) | The pair is the identity and the access path |
| Naming | `pk_`, `fk_`, `uq_`, `ck_`, `ix_` prefixes | Errors name the rule that failed |

## What changes at scale

| Table | Change | From tier |
|---|---|---|
| `orders`, `order_items`, `payments`, `shipments` | Range-partition by order date; reference-partition children | 1 million customers |
| `stock_movements`, `audit_log` | Interval-partition by month; drop old partitions | 1 million |
| `carts`, `cart_items` | Purge abandoned carts on a schedule | 100 thousand |
| `inventory` | Lock-free reservations (23ai+) for hot products | 10 million |
| `products` | Text or vector index for search | 100 thousand |

Details: [Scaling](05-scaling.md).

## Check yourself

??? example "Exercises"
    1. Draw the model from memory, then compare.
    2. Add the composite foreign key that guarantees an order's address belongs to its customer.
       ```sql
       ALTER TABLE addresses ADD CONSTRAINT uq_addresses_id_customer UNIQUE (address_id, customer_id);
       ALTER TABLE orders ADD CONSTRAINT fk_orders_address_customer
           FOREIGN KEY (address_id, customer_id) REFERENCES addresses (address_id, customer_id);
       ```
    3. A product may now belong to several categories. Redraw the affected part.

Next: [Implementation](03-implementation.md).
