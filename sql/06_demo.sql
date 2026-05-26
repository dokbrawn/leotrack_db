-- ─── SECTION 1: Scalar functions ────────────────────────────

-- 1a. Balance of subscriber #1 (Anisimov Timur – hidden owner)
SELECT get_subscriber_balance(1) AS balance_owner;

-- 1b. Balance of a debtor
SELECT get_subscriber_balance(5) AS balance_debtor;

-- 1c. Non-existent subscriber
SELECT get_subscriber_balance(9999) AS balance_null;

-- 2. Status labels for all subscribers
SELECT sub_id, full_name, get_subscriber_status_label(sub_id) AS status_label
FROM subscribers ORDER BY sub_id;

-- 3. Balance classification sweep
SELECT sub_id, full_name, balance, classify_balance(sub_id) AS category
FROM subscribers ORDER BY balance;

-- 4. Total data consumed per subscriber (GB)
SELECT s.sub_id, s.full_name, get_total_data_gb(s.sub_id) AS used_gb
FROM subscribers s ORDER BY used_gb DESC;

-- 5. Anomaly counts (last 30 days)
SELECT sat_id, sat_name, count_anomalies(sat_id, 30) AS anomalies
FROM satellites ORDER BY anomalies DESC;

-- 6. Plan-change eligibility checks
SELECT
    can_subscribe_plan(1, 4) AS owner_can_enterprise,     -- should be TRUE
    can_subscribe_plan(5, 3) AS debtor_can_professional;   -- should be FALSE (overdue)

-- ─── SECTION 2: Table-returning functions ───────────────────

-- 7. Full finance card for subscriber #1
SELECT * FROM get_subscriber_finance_card(1);

-- 8. Top 5 revenue subscribers
SELECT * FROM get_top_revenue_subscribers(5);

-- 9. Overdue subscribers with any debt
SELECT * FROM get_overdue_subscribers(0);

-- 10. Recalculate overage for May-2025
SELECT recalculate_overage_cost('2026-05') AS invoices_updated;

-- ─── SECTION 3: Trigger demos ───────────────────────────────

-- TRIGGER 1: Balance guard – this MUST raise an exception
DO $$
BEGIN
    BEGIN
        UPDATE subscribers SET balance = -9999.00 WHERE sub_id = 7;
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'TRIGGER 1 OK: %', SQLERRM;
    END;
END;
$$;

-- TRIGGER 2: Audit log – update a subscriber and check the log
UPDATE subscribers SET balance = balance + 100 WHERE sub_id = 3;
SELECT * FROM subscriber_audit ORDER BY audit_id DESC LIMIT 5;

-- TRIGGER 3: updated_at auto-set
UPDATE subscribers SET status = 'active' WHERE sub_id = 9;
SELECT sub_id, full_name, updated_at FROM subscribers WHERE sub_id = 9;

-- TRIGGER 4: Invoice status guard – paid → pending must fail
DO $$
BEGIN
    BEGIN
        UPDATE invoices SET status = 'pending' WHERE invoice_id = 1;
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'TRIGGER 4 OK: %', SQLERRM;
    END;
END;
$$;

-- TRIGGER 5: Archive on delete – delete and check archive
INSERT INTO invoices (sub_id, billing_period, issue_date, due_date,
                      amount_base, total_amount, status)
VALUES (7, '2026-06', CURRENT_DATE, CURRENT_DATE + 30, 29.99, 29.99, 'pending');

DELETE FROM invoices WHERE sub_id = 7 AND billing_period = '2026-06';
SELECT * FROM invoice_archive ORDER BY archived_at DESC LIMIT 3;

-- TRIGGER 6: Protect active plan – must fail
DO $$
BEGIN
    BEGIN
        DELETE FROM service_plans WHERE plan_id = 1;
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'TRIGGER 6 OK: %', SQLERRM;
    END;
END;
$$;

-- TRIGGER 7: Anomaly log – insert a telemetry record with anomaly
INSERT INTO telemetry (sat_id, recorded_at, battery_pct, anomaly_flag)
VALUES (3, NOW(), 45.0, TRUE);
SELECT * FROM satellite_health_log ORDER BY logged_at DESC LIMIT 3;
