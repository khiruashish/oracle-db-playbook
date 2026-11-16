---
tags: [freshmart]
---

# FreshMart: the project that runs through the playbook

FreshMart is an online grocery store. Customers browse products, fill a cart,
place and pay for orders, and receive deliveries from city warehouses. Every
example in the study path uses this one schema, so that by the end you know one
realistic system in depth rather than fifty toy tables.

## Project phases

| Phase | Page | Read after |
|---|---|---|
| 1. Business analysis: requirements and rules | [Business analysis](01-business-analysis.md) | Stage 1 |
| 2. Data model: ER diagram, entities, normalization | [Data model](02-data-model.md) | Stage 1 |
| 3. Implementation: tables, constraints, indexes, PL/SQL | [Implementation](03-implementation.md) | 2.9 |
| 4. Twenty business queries | [Business queries](04-business-queries.md) | 2.6 |
| 5. Scaling from 10 thousand to 10 million customers | [Scaling](05-scaling.md) | Stage 3 |
| 6. Production architecture | [Production architecture](06-architecture.md) | Stage 4 |
| Spring Boot integration | [Chapter 4.8](../spring-boot-integration/01-spring-boot.md) | Stage 2 |
| Performance incidents | [Twelve incidents](../performance-incidents/01-incidents.md) | Stage 3 |

## Files

| Path | Content |
|---|---|
| `sql/grocery-application/00_create_user.sql` | Creates the `FRESHMART` schema owner |
| `sql/grocery-application/install.sql` | One-step install: tables, data, PL/SQL, verification |
| `sql/schema/01_tables.sql` | 20 tables with constraints, indexes and comments |
| `sql/sample-data/01_sample_data.sql` | Sample rows (the data behind every printed result) |
| `sql/schema/02_identity_reset.sql` | Moves identity values past the loaded keys |
| `sql/plsql/` | Views, triggers and `ORDER_PKG` |
| `sql/queries/business_queries.sql` | The 20 business queries |
| `sql/schema/99_drop_all.sql` | Removes everything (lab use only) |
| `tests/verify_outputs.py` | Cross-checks documented results against the sample data |

Install instructions: [Set up your lab database](../getting-started/setup.md).

## The sample data at a glance

| Fact | Value |
|---|---|
| Customers | 6 (101 to 106); 106 has never ordered |
| Products | 12 in 6 leaf categories; product 12 has never been ordered |
| Orders | 8 (1001 to 1008): 5 delivered, 1 shipped, 1 placed, 1 cancelled |
| Net merchandise value (not cancelled) | 3,668 |
| Net order total (not cancelled) | 3,688 |
| Warehouses | Mumbai (1), Bengaluru (2), Delhi (3) |
| Low-stock rows | 3 |

These figures are checked by `sql/grocery-application/verify.sql` on Oracle and
by `tests/verify_outputs.py` without Oracle.
