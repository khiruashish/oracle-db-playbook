-- =============================================================================
-- FreshMart sample data (small on purpose: every result can be checked by hand)
-- One INSERT per row, explicit column lists and explicit key values so that the
-- expected outputs in the documentation are reproducible.
-- tests/verify_outputs.py parses this file: keep the single-line INSERT format.
-- =============================================================================

-- categories
INSERT INTO categories (category_id, category_name, parent_category_id) VALUES (1, 'Fresh Produce', NULL);
INSERT INTO categories (category_id, category_name, parent_category_id) VALUES (2, 'Fruits', 1);
INSERT INTO categories (category_id, category_name, parent_category_id) VALUES (3, 'Vegetables', 1);
INSERT INTO categories (category_id, category_name, parent_category_id) VALUES (4, 'Dairy and Eggs', NULL);
INSERT INTO categories (category_id, category_name, parent_category_id) VALUES (5, 'Bakery', NULL);
INSERT INTO categories (category_id, category_name, parent_category_id) VALUES (6, 'Beverages', NULL);
INSERT INTO categories (category_id, category_name, parent_category_id) VALUES (7, 'Staples', NULL);

-- suppliers
INSERT INTO suppliers (supplier_id, supplier_name, contact_email, phone, city) VALUES (1, 'GreenFields Agro', 'sales@greenfields.example', '+91-2530000001', 'Nashik');
INSERT INTO suppliers (supplier_id, supplier_name, contact_email, phone, city) VALUES (2, 'DairyPure Ltd', 'orders@dairypure.example', '+91-2692000002', 'Anand');
INSERT INTO suppliers (supplier_id, supplier_name, contact_email, phone, city) VALUES (3, 'BakeHouse Foods', 'hello@bakehouse.example', '+91-2200000003', 'Mumbai');
INSERT INTO suppliers (supplier_id, supplier_name, contact_email, phone, city) VALUES (4, 'SipWell Beverages', 'trade@sipwell.example', NULL, 'Bengaluru');
INSERT INTO suppliers (supplier_id, supplier_name, contact_email, phone, city) VALUES (5, 'GrainMasters', 'supply@grainmasters.example', '+91-1100000005', 'Delhi');

-- products
INSERT INTO products (product_id, sku, product_name, category_id, supplier_id, unit_price, unit_of_measure) VALUES (1, 'FRU-APL-001', 'Apple Royal Gala 1kg', 2, 1, 180.00, 'KG');
INSERT INTO products (product_id, sku, product_name, category_id, supplier_id, unit_price, unit_of_measure) VALUES (2, 'FRU-BAN-001', 'Banana Robusta 1 dozen', 2, 1, 60.00, 'DOZEN');
INSERT INTO products (product_id, sku, product_name, category_id, supplier_id, unit_price, unit_of_measure) VALUES (3, 'VEG-TOM-001', 'Tomato 1kg', 3, 1, 40.00, 'KG');
INSERT INTO products (product_id, sku, product_name, category_id, supplier_id, unit_price, unit_of_measure) VALUES (4, 'VEG-ONI-001', 'Onion 1kg', 3, 1, 35.00, 'KG');
INSERT INTO products (product_id, sku, product_name, category_id, supplier_id, unit_price, unit_of_measure) VALUES (5, 'DAI-MLK-001', 'Full Cream Milk 1L', 4, 2, 68.00, 'LITRE');
INSERT INTO products (product_id, sku, product_name, category_id, supplier_id, unit_price, unit_of_measure) VALUES (6, 'DAI-EGG-001', 'Eggs 12 pack', 4, 2, 84.00, 'PACK');
INSERT INTO products (product_id, sku, product_name, category_id, supplier_id, unit_price, unit_of_measure) VALUES (7, 'DAI-PNR-001', 'Paneer 200g', 4, 2, 95.00, 'PACK');
INSERT INTO products (product_id, sku, product_name, category_id, supplier_id, unit_price, unit_of_measure) VALUES (8, 'BAK-BRD-001', 'Whole Wheat Bread 400g', 5, 3, 45.00, 'PACK');
INSERT INTO products (product_id, sku, product_name, category_id, supplier_id, unit_price, unit_of_measure) VALUES (9, 'BEV-OJ-001', 'Orange Juice 1L', 6, 4, 120.00, 'LITRE');
INSERT INTO products (product_id, sku, product_name, category_id, supplier_id, unit_price, unit_of_measure) VALUES (10, 'BEV-TEA-001', 'Assam Tea 250g', 6, 4, 150.00, 'PACK');
INSERT INTO products (product_id, sku, product_name, category_id, supplier_id, unit_price, unit_of_measure) VALUES (11, 'STA-RIC-001', 'Basmati Rice 5kg', 7, 5, 650.00, 'BAG');
INSERT INTO products (product_id, sku, product_name, category_id, supplier_id, unit_price, unit_of_measure) VALUES (12, 'STA-ATA-001', 'Wheat Flour 5kg', 7, 5, 260.00, 'BAG');

-- warehouses
INSERT INTO warehouses (warehouse_id, warehouse_name, city) VALUES (1, 'Mumbai Central FC', 'Mumbai');
INSERT INTO warehouses (warehouse_id, warehouse_name, city) VALUES (2, 'Bengaluru South FC', 'Bengaluru');
INSERT INTO warehouses (warehouse_id, warehouse_name, city) VALUES (3, 'Delhi NCR FC', 'Delhi');

-- employees
INSERT INTO employees (employee_id, employee_name, email, job_title, manager_id, warehouse_id, hire_date, salary) VALUES (1, 'Anita Desai', 'anita.desai@freshmart.example', 'Operations Head', NULL, NULL, DATE '2022-04-01', 250000);
INSERT INTO employees (employee_id, employee_name, email, job_title, manager_id, warehouse_id, hire_date, salary) VALUES (2, 'Vikram Rao', 'vikram.rao@freshmart.example', 'Warehouse Manager', 1, 1, DATE '2022-06-15', 120000);
INSERT INTO employees (employee_id, employee_name, email, job_title, manager_id, warehouse_id, hire_date, salary) VALUES (3, 'Meera Pillai', 'meera.pillai@freshmart.example', 'Warehouse Manager', 1, 2, DATE '2023-01-10', 115000);
INSERT INTO employees (employee_id, employee_name, email, job_title, manager_id, warehouse_id, hire_date, salary) VALUES (4, 'Arjun Singh', 'arjun.singh@freshmart.example', 'Warehouse Manager', 1, 3, DATE '2023-03-20', 118000);
INSERT INTO employees (employee_id, employee_name, email, job_title, manager_id, warehouse_id, hire_date, salary) VALUES (5, 'Sunil Kumar', 'sunil.kumar@freshmart.example', 'Picker', 2, 1, DATE '2023-07-01', 32000);
INSERT INTO employees (employee_id, employee_name, email, job_title, manager_id, warehouse_id, hire_date, salary) VALUES (6, 'Fatima Khan', 'fatima.khan@freshmart.example', 'Delivery Associate', 2, 1, DATE '2024-02-12', 30000);
INSERT INTO employees (employee_id, employee_name, email, job_title, manager_id, warehouse_id, hire_date, salary) VALUES (7, 'Ravi Teja', 'ravi.teja@freshmart.example', 'Picker', 3, 2, DATE '2024-05-05', 31000);
INSERT INTO employees (employee_id, employee_name, email, job_title, manager_id, warehouse_id, hire_date, salary) VALUES (8, 'Pooja Yadav', 'pooja.yadav@freshmart.example', 'Delivery Associate', 4, 3, DATE '2024-08-19', 30000);

-- customers
INSERT INTO customers (customer_id, customer_name, email, phone, city, status, registered_on) VALUES (101, 'Rahul Sharma', 'rahul.sharma@example.com', '+91-9800000101', 'Mumbai', 'ACTIVE', DATE '2025-01-10');
INSERT INTO customers (customer_id, customer_name, email, phone, city, status, registered_on) VALUES (102, 'Priya Nair', 'priya.nair@example.com', '+91-9800000102', 'Bengaluru', 'ACTIVE', DATE '2025-01-15');
INSERT INTO customers (customer_id, customer_name, email, phone, city, status, registered_on) VALUES (103, 'Amit Verma', 'amit.verma@example.com', NULL, 'Delhi', 'ACTIVE', DATE '2025-02-01');
INSERT INTO customers (customer_id, customer_name, email, phone, city, status, registered_on) VALUES (104, 'Sneha Iyer', 'sneha.iyer@example.com', '+91-9800000104', 'Mumbai', 'ACTIVE', DATE '2025-02-20');
INSERT INTO customers (customer_id, customer_name, email, phone, city, status, registered_on) VALUES (105, 'Karan Mehta', 'karan.mehta@example.com', '+91-9800000105', 'Mumbai', 'ACTIVE', DATE '2025-03-05');
INSERT INTO customers (customer_id, customer_name, email, phone, city, status, registered_on) VALUES (106, 'Neha Gupta', 'neha.gupta@example.com', NULL, 'Delhi', 'INACTIVE', DATE '2025-03-12');

-- addresses
INSERT INTO addresses (address_id, customer_id, address_type, line1, city, state, pincode, is_default) VALUES (201, 101, 'HOME', '12 Marine Drive', 'Mumbai', 'Maharashtra', '400002', 'Y');
INSERT INTO addresses (address_id, customer_id, address_type, line1, city, state, pincode, is_default) VALUES (202, 102, 'HOME', '45 Indiranagar 100ft Road', 'Bengaluru', 'Karnataka', '560038', 'Y');
INSERT INTO addresses (address_id, customer_id, address_type, line1, city, state, pincode, is_default) VALUES (203, 103, 'HOME', '7 Connaught Place', 'Delhi', 'Delhi', '110001', 'Y');
INSERT INTO addresses (address_id, customer_id, address_type, line1, city, state, pincode, is_default) VALUES (204, 104, 'HOME', '88 Bandra West', 'Mumbai', 'Maharashtra', '400050', 'Y');
INSERT INTO addresses (address_id, customer_id, address_type, line1, city, state, pincode, is_default) VALUES (205, 105, 'HOME', '3 Powai Lake Road', 'Mumbai', 'Maharashtra', '400076', 'Y');
INSERT INTO addresses (address_id, customer_id, address_type, line1, city, state, pincode, is_default) VALUES (206, 106, 'HOME', '21 Karol Bagh', 'Delhi', 'Delhi', '110005', 'Y');
INSERT INTO addresses (address_id, customer_id, address_type, line1, city, state, pincode, is_default) VALUES (207, 101, 'OFFICE', '5 BKC Tower', 'Mumbai', 'Maharashtra', '400051', 'N');

-- inventory
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (1, 1, 120, 0, 30);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (1, 2, 80, 0, 20);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (1, 5, 200, 2, 50);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (1, 6, 60, 0, 20);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (1, 7, 15, 0, 20);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (1, 8, 40, 0, 15);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (1, 9, 25, 0, 10);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (1, 10, 50, 0, 10);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (1, 11, 30, 1, 10);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (2, 1, 60, 0, 20);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (2, 8, 10, 0, 15);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (2, 9, 30, 0, 10);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (2, 10, 40, 0, 10);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (2, 11, 45, 0, 10);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (2, 12, 20, 0, 10);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (3, 3, 90, 0, 25);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (3, 4, 110, 0, 25);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (3, 5, 75, 0, 30);
INSERT INTO inventory (warehouse_id, product_id, qty_on_hand, qty_reserved, reorder_level) VALUES (3, 12, 8, 0, 10);

-- promotions
INSERT INTO promotions (promotion_id, promotion_name, discount_type, discount_value, start_date, end_date) VALUES (1, 'Welcome Offer', 'PERCENT', 10, DATE '2025-01-01', DATE '2025-12-31');
INSERT INTO promotions (promotion_id, promotion_name, discount_type, discount_value, start_date, end_date) VALUES (2, 'Fresh Savings', 'FLAT', 50, DATE '2025-04-01', DATE '2025-04-30');

-- coupons
INSERT INTO coupons (coupon_id, coupon_code, promotion_id, min_order_amount, max_uses, used_count, valid_from, valid_to, is_active) VALUES (1, 'WELCOME10', 1, 500, 1000, 1, DATE '2025-01-01', DATE '2025-12-31', 'Y');
INSERT INTO coupons (coupon_id, coupon_code, promotion_id, min_order_amount, max_uses, used_count, valid_from, valid_to, is_active) VALUES (2, 'FRESH50', 2, 500, 500, 1, DATE '2025-04-01', DATE '2025-04-30', 'Y');
INSERT INTO coupons (coupon_id, coupon_code, promotion_id, min_order_amount, max_uses, used_count, valid_from, valid_to, is_active) VALUES (3, 'NEWYEAR5', 1, 200, 100, 0, DATE '2025-01-01', DATE '2025-02-28', 'N');

-- carts
INSERT INTO carts (cart_id, customer_id, status) VALUES (1, 103, 'ACTIVE');
INSERT INTO carts (cart_id, customer_id, status) VALUES (2, 106, 'ACTIVE');
INSERT INTO carts (cart_id, customer_id, status) VALUES (3, 101, 'CONVERTED');

-- cart_items
INSERT INTO cart_items (cart_id, product_id, quantity) VALUES (1, 1, 1);
INSERT INTO cart_items (cart_id, product_id, quantity) VALUES (1, 10, 1);
INSERT INTO cart_items (cart_id, product_id, quantity) VALUES (2, 8, 2);

-- orders
INSERT INTO orders (order_id, customer_id, address_id, warehouse_id, coupon_id, order_date, status, subtotal, discount_amount, delivery_fee, total_amount) VALUES (1001, 101, 201, 1, NULL, DATE '2025-03-01', 'DELIVERED', 609, 0, 30, 639);
INSERT INTO orders (order_id, customer_id, address_id, warehouse_id, coupon_id, order_date, status, subtotal, discount_amount, delivery_fee, total_amount) VALUES (1002, 102, 202, 2, 1, DATE '2025-03-03', 'DELIVERED', 800, 80, 0, 720);
INSERT INTO orders (order_id, customer_id, address_id, warehouse_id, coupon_id, order_date, status, subtotal, discount_amount, delivery_fee, total_amount) VALUES (1003, 101, 201, 1, NULL, DATE '2025-03-10', 'DELIVERED', 394, 0, 30, 424);
INSERT INTO orders (order_id, customer_id, address_id, warehouse_id, coupon_id, order_date, status, subtotal, discount_amount, delivery_fee, total_amount) VALUES (1004, 103, 203, 3, NULL, DATE '2025-03-15', 'SHIPPED', 326, 0, 30, 356);
INSERT INTO orders (order_id, customer_id, address_id, warehouse_id, coupon_id, order_date, status, subtotal, discount_amount, delivery_fee, total_amount) VALUES (1005, 104, 204, 1, NULL, DATE '2025-03-18', 'CANCELLED', 240, 0, 30, 270);
INSERT INTO orders (order_id, customer_id, address_id, warehouse_id, coupon_id, order_date, status, subtotal, discount_amount, delivery_fee, total_amount) VALUES (1006, 102, 202, 2, NULL, DATE '2025-04-02', 'DELIVERED', 390, 0, 30, 420);
INSERT INTO orders (order_id, customer_id, address_id, warehouse_id, coupon_id, order_date, status, subtotal, discount_amount, delivery_fee, total_amount) VALUES (1007, 101, 207, 1, 2, DATE '2025-04-05', 'PLACED', 786, 50, 0, 736);
INSERT INTO orders (order_id, customer_id, address_id, warehouse_id, coupon_id, order_date, status, subtotal, discount_amount, delivery_fee, total_amount) VALUES (1008, 105, 205, 1, NULL, DATE '2025-04-08', 'DELIVERED', 363, 0, 30, 393);

-- order_items
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1001, 1, 1, 2, 180);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1001, 2, 5, 3, 68);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1001, 3, 8, 1, 45);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1002, 1, 11, 1, 650);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1002, 2, 10, 1, 150);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1003, 1, 2, 2, 60);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1003, 2, 6, 1, 84);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1003, 3, 7, 2, 95);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1004, 1, 3, 3, 40);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1004, 2, 4, 2, 35);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1004, 3, 5, 2, 68);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1005, 1, 9, 2, 120);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1006, 1, 1, 1, 180);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1006, 2, 9, 1, 120);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1006, 3, 8, 2, 45);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1007, 1, 11, 1, 650);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1007, 2, 5, 2, 68);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1008, 1, 6, 2, 84);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1008, 2, 8, 1, 45);
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price) VALUES (1008, 3, 10, 1, 150);

-- payments
INSERT INTO payments (payment_id, order_id, payment_method, amount, status, txn_reference, paid_at) VALUES (1, 1001, 'UPI', 639, 'SUCCESS', 'TXN-1001-A', TIMESTAMP '2025-03-01 10:15:00');
INSERT INTO payments (payment_id, order_id, payment_method, amount, status, txn_reference, paid_at) VALUES (2, 1002, 'CARD', 720, 'SUCCESS', 'TXN-1002-A', TIMESTAMP '2025-03-03 18:40:00');
INSERT INTO payments (payment_id, order_id, payment_method, amount, status, txn_reference, paid_at) VALUES (3, 1003, 'UPI', 424, 'SUCCESS', 'TXN-1003-A', TIMESTAMP '2025-03-10 09:05:00');
INSERT INTO payments (payment_id, order_id, payment_method, amount, status, txn_reference, paid_at) VALUES (4, 1004, 'COD', 356, 'PENDING', NULL, TIMESTAMP '2025-03-15 12:00:00');
INSERT INTO payments (payment_id, order_id, payment_method, amount, status, txn_reference, paid_at) VALUES (5, 1005, 'CARD', 270, 'REFUNDED', 'TXN-1005-A', TIMESTAMP '2025-03-18 20:30:00');
INSERT INTO payments (payment_id, order_id, payment_method, amount, status, txn_reference, paid_at) VALUES (6, 1006, 'WALLET', 420, 'SUCCESS', 'TXN-1006-A', TIMESTAMP '2025-04-02 08:20:00');
INSERT INTO payments (payment_id, order_id, payment_method, amount, status, txn_reference, paid_at) VALUES (7, 1007, 'UPI', 736, 'FAILED', 'TXN-1007-A', TIMESTAMP '2025-04-05 19:00:00');
INSERT INTO payments (payment_id, order_id, payment_method, amount, status, txn_reference, paid_at) VALUES (8, 1007, 'CARD', 736, 'SUCCESS', 'TXN-1007-B', TIMESTAMP '2025-04-05 19:03:00');
INSERT INTO payments (payment_id, order_id, payment_method, amount, status, txn_reference, paid_at) VALUES (9, 1008, 'NETBANKING', 393, 'SUCCESS', 'TXN-1008-A', TIMESTAMP '2025-04-08 11:45:00');

-- shipments
INSERT INTO shipments (shipment_id, order_id, carrier, tracking_number, status, delivered_by, shipped_at, delivered_at) VALUES (1, 1001, 'FreshMart Fleet', 'FM-TRK-0001', 'DELIVERED', 6, TIMESTAMP '2025-03-01 12:00:00', TIMESTAMP '2025-03-01 15:30:00');
INSERT INTO shipments (shipment_id, order_id, carrier, tracking_number, status, delivered_by, shipped_at, delivered_at) VALUES (2, 1002, 'QuickShip', 'QS-TRK-0002', 'DELIVERED', NULL, TIMESTAMP '2025-03-04 09:00:00', TIMESTAMP '2025-03-04 13:10:00');
INSERT INTO shipments (shipment_id, order_id, carrier, tracking_number, status, delivered_by, shipped_at, delivered_at) VALUES (3, 1003, 'FreshMart Fleet', 'FM-TRK-0003', 'DELIVERED', 6, TIMESTAMP '2025-03-10 11:00:00', TIMESTAMP '2025-03-10 13:45:00');
INSERT INTO shipments (shipment_id, order_id, carrier, tracking_number, status, delivered_by, shipped_at, delivered_at) VALUES (4, 1004, 'FreshMart Fleet', 'FM-TRK-0004', 'IN_TRANSIT', 8, TIMESTAMP '2025-03-15 16:00:00', NULL);
INSERT INTO shipments (shipment_id, order_id, carrier, tracking_number, status, delivered_by, shipped_at, delivered_at) VALUES (5, 1006, 'QuickShip', 'QS-TRK-0005', 'DELIVERED', NULL, TIMESTAMP '2025-04-02 10:00:00', TIMESTAMP '2025-04-02 14:00:00');
INSERT INTO shipments (shipment_id, order_id, carrier, tracking_number, status, delivered_by, shipped_at, delivered_at) VALUES (6, 1008, 'FreshMart Fleet', 'FM-TRK-0006', 'DELIVERED', 6, TIMESTAMP '2025-04-08 13:00:00', TIMESTAMP '2025-04-08 16:20:00');

-- returns
INSERT INTO returns (return_id, order_id, line_no, quantity, reason, status, refund_amount) VALUES (1, 1003, 3, 1, 'Damaged packaging', 'REFUNDED', 95);
INSERT INTO returns (return_id, order_id, line_no, quantity, reason, status, refund_amount) VALUES (2, 1006, 2, 1, 'Product near expiry', 'REQUESTED', 120);

-- reviews
INSERT INTO reviews (review_id, product_id, customer_id, rating, review_text) VALUES (1, 1, 101, 5, 'Crisp and sweet');
INSERT INTO reviews (review_id, product_id, customer_id, rating, review_text) VALUES (2, 1, 102, 4, 'Good quality');
INSERT INTO reviews (review_id, product_id, customer_id, rating, review_text) VALUES (3, 5, 101, 4, 'Always fresh');
INSERT INTO reviews (review_id, product_id, customer_id, rating, review_text) VALUES (4, 11, 102, 5, 'Excellent aroma');
INSERT INTO reviews (review_id, product_id, customer_id, rating, review_text) VALUES (5, 8, 105, 3, NULL);
INSERT INTO reviews (review_id, product_id, customer_id, rating, review_text) VALUES (6, 6, 105, 4, 'No broken eggs');
INSERT INTO reviews (review_id, product_id, customer_id, rating, review_text) VALUES (7, 7, 101, 2, 'Pack was damaged');

-- stock_movements
INSERT INTO stock_movements (movement_id, warehouse_id, product_id, movement_type, quantity, reference_type, reference_id) VALUES (1, 1, 1, 'RECEIPT', 122, 'PURCHASE', 1);
INSERT INTO stock_movements (movement_id, warehouse_id, product_id, movement_type, quantity, reference_type, reference_id) VALUES (2, 1, 1, 'SALE', -2, 'ORDER', 1001);
INSERT INTO stock_movements (movement_id, warehouse_id, product_id, movement_type, quantity, reference_type, reference_id) VALUES (3, 1, 7, 'RECEIPT', 16, 'PURCHASE', 2);
INSERT INTO stock_movements (movement_id, warehouse_id, product_id, movement_type, quantity, reference_type, reference_id) VALUES (4, 1, 7, 'SALE', -2, 'ORDER', 1003);
INSERT INTO stock_movements (movement_id, warehouse_id, product_id, movement_type, quantity, reference_type, reference_id) VALUES (5, 1, 7, 'RETURN', 1, 'RETURN', 1);

COMMIT;
