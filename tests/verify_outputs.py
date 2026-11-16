#!/usr/bin/env python3
"""Cross-check documented query results against the FreshMart sample data.

No Oracle instance is required. The script loads sql/sample-data/01_sample_data.sql
into an in-memory SQLite database and runs standard-SQL equivalents of the
queries whose results are printed in the documentation.

This proves that the *numbers* in the docs match the sample data. It does NOT
prove that the Oracle syntax is valid: only running the scripts on Oracle does.
"""
import pathlib
import re
import sqlite3
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "sql" / "sample-data" / "01_sample_data.sql"

INSERT_RE = re.compile(r"^INSERT INTO (\w+) \(([^)]*)\) VALUES \((.*)\);$")


def load() -> sqlite3.Connection:
    con = sqlite3.connect(":memory:")
    created = set()
    for line in DATA.read_text().splitlines():
        m = INSERT_RE.match(line.strip())
        if not m:
            continue
        table, cols, values = m.groups()
        if table not in created:
            con.execute(f"CREATE TABLE {table} ({cols})")
            created.add(table)
        values = re.sub(r"(?:DATE|TIMESTAMP) ('[^']*')", r"\1", values)
        con.execute(f"INSERT INTO {table} ({cols}) VALUES ({values})")
    # ORDER_ITEMS.LINE_TOTAL is a virtual column in Oracle.
    con.execute("ALTER TABLE order_items ADD COLUMN line_total")
    con.execute("UPDATE order_items SET line_total = quantity * unit_price")
    return con


CHECKS = [
    ("orders per customer (LEFT JOIN + COUNT)",
     """SELECT c.customer_id, c.customer_name, COUNT(o.order_id)
        FROM customers c LEFT JOIN orders o ON o.customer_id = c.customer_id
        GROUP BY c.customer_id, c.customer_name
        ORDER BY 3 DESC, 1""",
     [(101, "Rahul Sharma", 3), (102, "Priya Nair", 2), (103, "Amit Verma", 1),
      (104, "Sneha Iyer", 1), (105, "Karan Mehta", 1), (106, "Neha Gupta", 0)]),

    ("products priced above 100",
     "SELECT product_id FROM products WHERE unit_price > 100 ORDER BY unit_price DESC, product_id",
     [(11,), (12,), (1,), (10,), (9,)]),

    ("customers without phone",
     "SELECT customer_id FROM customers WHERE phone IS NULL ORDER BY 1",
     [(103,), (106,)]),

    ("customers per city",
     "SELECT city, COUNT(*) FROM customers GROUP BY city ORDER BY 2 DESC, 1",
     [("Mumbai", 3), ("Delhi", 2), ("Bengaluru", 1)]),

    ("order status counts",
     "SELECT status, COUNT(*), SUM(total_amount) FROM orders GROUP BY status ORDER BY 1",
     [("CANCELLED", 1, 270), ("DELIVERED", 5, 2596), ("PLACED", 1, 736), ("SHIPPED", 1, 356)]),

    ("product sales excluding cancelled orders",
     """SELECT p.product_id, SUM(oi.quantity), SUM(oi.line_total)
        FROM products p JOIN order_items oi ON oi.product_id = p.product_id
        JOIN orders o ON o.order_id = oi.order_id
        WHERE o.status <> 'CANCELLED'
        GROUP BY p.product_id ORDER BY 3 DESC, 1""",
     [(11, 2, 1300), (1, 3, 540), (5, 7, 476), (10, 2, 300), (6, 3, 252), (7, 2, 190),
      (8, 4, 180), (2, 2, 120), (3, 3, 120), (9, 1, 120), (4, 2, 70)]),

    ("products never ordered (anti join)",
     """SELECT p.product_id FROM products p
        WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.product_id = p.product_id)""",
     [(12,)]),

    ("customers with at least one order (semi join)",
     """SELECT COUNT(*) FROM customers c
        WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id)""",
     [(5,)]),

    ("monthly net sales",
     """SELECT substr(order_date, 1, 7), COUNT(*), SUM(total_amount)
        FROM orders WHERE status <> 'CANCELLED' GROUP BY 1 ORDER BY 1""",
     [("2025-03", 4, 2139), ("2025-04", 3, 1549)]),

    ("category revenue",
     """SELECT c.category_name, SUM(oi.line_total)
        FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
        JOIN products p ON p.product_id = oi.product_id
        JOIN categories c ON c.category_id = p.category_id
        WHERE o.status <> 'CANCELLED' GROUP BY c.category_name ORDER BY 2 DESC""",
     [("Staples", 1300), ("Dairy and Eggs", 918), ("Fruits", 660), ("Beverages", 420),
      ("Vegetables", 190), ("Bakery", 180)]),

    ("low stock",
     """SELECT warehouse_id, product_id, qty_on_hand - qty_reserved FROM inventory
        WHERE qty_on_hand - qty_reserved <= reorder_level ORDER BY 1, 2""",
     [(1, 7, 15), (2, 8, 10), (3, 12, 8)]),

    ("running total per customer 101 (window)",
     """SELECT order_id, total_amount,
               SUM(total_amount) OVER (ORDER BY order_date)
        FROM orders WHERE customer_id = 101 ORDER BY order_date""",
     [(1001, 639, 639), (1003, 424, 1063), (1007, 736, 1799)]),

    ("rank customers by net spend (window)",
     """SELECT customer_id, SUM(total_amount),
               RANK() OVER (ORDER BY SUM(total_amount) DESC)
        FROM orders WHERE status <> 'CANCELLED' GROUP BY customer_id ORDER BY 3""",
     [(101, 1799, 1), (102, 1140, 2), (105, 393, 3), (103, 356, 4)]),

    ("top product per category by revenue",
     """SELECT category_id, product_id, rev FROM (
          SELECT p.category_id, p.product_id, SUM(oi.line_total) rev,
                 ROW_NUMBER() OVER (PARTITION BY p.category_id
                                    ORDER BY SUM(oi.line_total) DESC, p.product_id) rn
          FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
          JOIN products p ON p.product_id = oi.product_id
          WHERE o.status <> 'CANCELLED' GROUP BY p.category_id, p.product_id)
        WHERE rn = 1 ORDER BY 1""",
     [(2, 1, 540), (3, 3, 120), (4, 5, 476), (5, 8, 180), (6, 10, 300), (7, 11, 1300)]),

    ("LAG: days since previous order for customer 101",
     """SELECT order_id,
               CAST(julianday(order_date) - julianday(LAG(order_date) OVER (ORDER BY order_date)) AS INT)
        FROM orders WHERE customer_id = 101 ORDER BY order_date""",
     [(1001, None), (1003, 9), (1007, 26)]),

    ("average rating per product",
     """SELECT product_id, COUNT(*), AVG(rating) FROM reviews
        GROUP BY product_id HAVING COUNT(*) >= 2""",
     [(1, 2, 4.5)]),

    ("employee hierarchy depth (recursive CTE)",
     """WITH RECURSIVE org (employee_id, lvl) AS (
          SELECT employee_id, 1 FROM employees WHERE manager_id IS NULL
          UNION ALL
          SELECT e.employee_id, org.lvl + 1 FROM employees e JOIN org ON e.manager_id = org.employee_id)
        SELECT lvl, COUNT(*) FROM org GROUP BY lvl ORDER BY lvl""",
     [(1, 1), (2, 3), (3, 4)]),

    ("payments by method (successful only)",
     """SELECT payment_method, COUNT(*), SUM(amount) FROM payments
        WHERE status = 'SUCCESS' GROUP BY payment_method ORDER BY 3 DESC""",
     [("UPI", 2, 1063), ("CARD", 2, 1456), ("WALLET", 1, 420), ("NETBANKING", 1, 393)]),

    ("frequently bought together with Milk (product 5)",
     """SELECT b.product_id, COUNT(*) FROM order_items a
        JOIN order_items b ON b.order_id = a.order_id AND b.product_id <> a.product_id
        WHERE a.product_id = 5 GROUP BY b.product_id ORDER BY 2 DESC, 1""",
     [(1, 1), (3, 1), (4, 1), (8, 1), (11, 1)]),

    ("warehouse stock value",
     """SELECT i.warehouse_id, SUM(i.qty_on_hand), SUM(i.qty_on_hand * p.unit_price)
        FROM inventory i JOIN products p ON p.product_id = i.product_id
        GROUP BY i.warehouse_id ORDER BY 1""",
     [(1, 620, 78265), (2, 205, 55300), (3, 283, 14630)]),

    ("orders above the average order value",
     """SELECT order_id FROM orders
        WHERE total_amount > (SELECT AVG(total_amount) FROM orders) ORDER BY 1""",
     [(1001,), (1002,), (1007,)]),

    ("subtotal equals sum of lines",
     """SELECT COUNT(*) FROM orders o WHERE subtotal <>
        (SELECT SUM(line_total) FROM order_items oi WHERE oi.order_id = o.order_id)""",
     [(0,)]),
]


def main() -> int:
    con = load()
    failed = 0
    for name, sql, expected in CHECKS:
        actual = con.execute(sql).fetchall()
        # The "payments by method" check is ordered by amount: sort both sides.
        ok = sorted(map(repr, actual)) == sorted(map(repr, expected)) if "payments by method" in name \
            else actual == expected
        print(("PASS " if ok else "FAIL ") + name)
        if not ok:
            failed += 1
            print("   expected:", expected)
            print("   actual:  ", actual)
    print(f"\n{len(CHECKS) - failed}/{len(CHECKS)} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
