# How to read a chapter

## The chapter template

Every chapter opens with a **chapter card**:

!!! abstract "Chapter card (example)"
    **Stage:** 2 · **Prerequisites:** 1.10 · **Time:** 3 hours ·
    **Applies to:** 19c and later (version notes inline)

Major topics then follow the same order, so you always know where to look:

| # | Section | Question it answers |
|---|---|---|
| 1 | Overview | What is it, in plain language? |
| 2 | Why it exists | What goes wrong without it? |
| 3 | How Oracle does it | What happens inside the database? |
| 4 | Syntax | What do I type? |
| 5 | Examples and output | What does it return on FreshMart data? |
| 6 | Real-world use | Where does this appear in a real system? |
| 7 | Trade-offs | Advantages, disadvantages, performance, security |
| 8 | Production guidance | Recommendations, anti-patterns, common mistakes |
| 9 | Check yourself | Interview questions and exercises with solutions |
| 10 | Related | What to read next |

Smaller subtopics use a shorter form (what, syntax, example, pitfalls). Sections
that would only repeat generic filler are left out on purpose.

## Conventions

| Marker | Meaning |
|---|---|
| :material-tag: **23ai+** | Needs that release or later. Unmarked content works on 19c. |
| **Standard SQL** / **Oracle-specific** | Whether the syntax is in the ISO SQL standard or only in Oracle |
| :material-license: **Option** | Needs a separately licensed option or pack (for example Partitioning, Diagnostics Pack) |
| *Verified result* | Numbers cross-checked against the sample data by `tests/verify_outputs.py` |
| *Illustrative* | Shape is right, exact values on your system will differ (all plans and DBA output) |

!!! danger "Destructive commands"
    Commands that remove data or stop a database appear inside a red box like
    this one, with the backup and approval you need before running them.

## The sample schema

All examples use the FreshMart schema. The rows are few enough to check any
result by hand:

| Table | Rows | Holds |
|---|---:|---|
| `customers` | 6 | 101 Rahul, 102 Priya, 103 Amit, 104 Sneha, 105 Karan, 106 Neha (no orders) |
| `products` | 12 | Product 12 (Wheat Flour) has never been ordered |
| `orders` | 8 | 1001 to 1008; 1005 is CANCELLED, 1007 is PLACED, 1004 is SHIPPED |
| `order_items` | 20 | 1 to 3 lines per order |
| `inventory` | 19 | Stock per warehouse and product; 3 rows are below reorder level |

The full model is in [FreshMart data model](../grocery-application/02-data-model.md).

## Study technique that works

1. Read the overview and the "why".
2. Type the example. Predict the output **before** you run it.
3. Break it on purpose: remove a join condition, violate a constraint, read the error.
4. Do the exercises with the solution collapsed.
5. Explain the topic aloud in two minutes. If you cannot, reread section 3.
