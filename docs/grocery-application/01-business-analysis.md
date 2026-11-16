---
tags: [freshmart, requirements]
---

# FreshMart 1: Business analysis

Before any table exists, write down what the business does, what must always be
true, and how much of it there will be. Every later design decision is traced
back to a line on this page.

## Business model

FreshMart sells groceries online in several Indian cities. Each city is served
by a fulfilment center (warehouse). Customers browse a catalog, build a cart,
check out with a delivery address and a payment method, and receive a delivery
the same or next day. They can return items and review products.

## Actors

| Actor | Does |
|---|---|
| Customer | Registers, browses, manages a cart, orders, pays, tracks, returns, reviews |
| Catalog administrator | Maintains categories, products, prices, promotions |
| Warehouse staff | Receive stock, pick and pack orders, adjust inventory |
| Delivery associate | Delivers shipments |
| Customer support | Looks up customers and orders, processes returns |
| Finance and management | Sales, refund and inventory reports |

## Functional requirements

| ID | Requirement |
|---|---|
| F1 | Register customers with a unique email; several delivery addresses per customer |
| F2 | Browse products by category (two levels) and search by name |
| F3 | One active cart per customer; add, change and remove items |
| F4 | Place an order from a cart for one address, fulfilled by one warehouse |
| F5 | Reserve stock at order time; never sell stock that does not exist |
| F6 | Record every payment attempt and its outcome; several payment methods |
| F7 | Track order status: placed, packed, shipped, delivered, cancelled |
| F8 | Cancel before shipping, releasing stock and refunding payment |
| F9 | Create one shipment per order with carrier and tracking |
| F10 | Return delivered items, fully or partly, with a refund |
| F11 | Promotions (percentage or flat) redeemed through coupon codes with limits |
| F12 | One review (rating 1 to 5) per customer per product |
| F13 | Maintain stock per warehouse and product with reorder levels and a movement history |
| F14 | Reports: sales, best sellers, low stock, purchase history, warehouse inventory |
| F15 | Audit changes to prices and order status |

## Business rules

| ID | Rule | Enforced by |
|---|---|---|
| R1 | Email identifies a customer | `uq_customers_email` |
| R2 | A product has exactly one category and one supplier; SKU is unique | Foreign keys, `uq_products_sku` |
| R3 | Prices are positive | `ck_products_price` |
| R4 | Reserved stock never exceeds stock on hand; neither is negative | `ck_inventory_reserved`, `ck_inventory_on_hand` |
| R5 | An order line records the price **at order time** | `order_items.unit_price` snapshot |
| R6 | Order total = subtotal − discount + delivery fee | `ck_orders_total` |
| R7 | Delivery is free from a subtotal of 700; otherwise 30 | `order_pkg` constants |
| R8 | A coupon is valid only when active, in date, under its usage limit, and the order meets the minimum | `order_pkg.coupon_discount` |
| R9 | Only `PLACED` or `PACKED` orders can be cancelled | `order_pkg.cancel_order` |
| R10 | A product appears once per order and once per cart | `uq_order_items_product`, `pk_cart_items` |
| R11 | One shipment per order | `uq_shipments_order` |
| R12 | Returned quantity cannot exceed the delivered quantity | Query 12 in [business queries](04-business-queries.md) |
| R13 | One review per customer and product, rating 1 to 5 | `uq_reviews_product_customer`, `ck_reviews_rating` |
| R14 | A payment gateway reference is recorded at most once | `uq_payments_txn` |

Rules that a constraint can express are constraints. Rules that span rows or
tables live in one place, `order_pkg`, which is the only write path for orders.

## Data requirements

| Subject | Must store | Retention (assumed) |
|---|---|---|
| Customers and addresses | Identity, contact, delivery locations | Life of the account + legal period |
| Catalog | Products, categories, suppliers, prices | Indefinite; price changes audited |
| Inventory | Stock, reservations, reorder levels, movements | Movements 3 years |
| Orders, lines, payments, shipments, returns | Complete commercial record | 7 years (tax) |
| Carts | Current contents | 30 days after last activity |
| Reviews | Rating and text | Life of the product |
| Audit log | Who changed what and when | 7 years |

Personal data: customer name, email, phone, addresses. It must be encrypted at
rest, masked outside production, and deletable or anonymizable on request
subject to the tax retention of orders.

## Transaction requirements

| Transaction | Must be atomic across | Isolation concern |
|---|---|---|
| Place order | Stock reservation, order, lines, coupon use, cart closure | Two shoppers competing for the last units |
| Cancel order | Order status, stock release, payment refund marker | Cancel racing with packing |
| Record payment | Payment row (idempotent) | Gateway retries |
| Process return | Return status, refund, stock movement | Double refund |
| Receive stock | Inventory quantity, movement row | Concurrent receipts |

## Non-functional requirements

Illustrative targets for the 1-million-customer tier; the full tiering is in
[Scaling](05-scaling.md).

| Category | Requirement |
|---|---|
| Performance | Catalog and cart reads p95 under 50 ms at the database; checkout transaction p95 under 200 ms |
| Throughput | Peak 60 orders per second during promotions |
| Availability | 99.95% for ordering, measured monthly |
| Recovery | RPO 0 for a server or zone failure; RPO 30 s and RTO 15 min for a regional failure |
| Scalability | 10x growth in customers without redesign of the data model |
| Security | TLS in transit, TDE at rest, least-privilege accounts, audit of privileged and non-application access |
| Maintainability | All schema changes through versioned migrations; no manual production DDL |
| Observability | Lag, space, sessions, top SQL and business KPIs monitored with alerts |
| Compliance | Indian tax record retention; personal data protection requirements |

## Expected growth

| Driver | Assumption |
|---|---|
| Active customers | Grow from 10 thousand to 10 million across the tiers studied |
| Orders per active customer | 1.5 per month |
| Lines per order | 4 on average (the sample data has 2.5) |
| Peak factor | Peak hour carries 12% of a day; promotion days are 3x a normal day |
| Catalog | 50 thousand to 2 million products |

## Out of scope

Payment processing itself (handled by a gateway), delivery route planning,
supplier purchasing, and loyalty points. Naming what is excluded prevents the
model from growing columns "just in case".

## Check yourself

??? example "Exercises"
    1. Which business rules above could **not** be enforced by a constraint on 19c, and why? *R7 to R9 and R12: they depend on other rows, other tables or the current date.*
    2. Add a requirement for delivery time slots. Which new rules and entities appear?
    3. Write the RTO and RPO for three failure classes for this system.

Next: [Data model](02-data-model.md).
