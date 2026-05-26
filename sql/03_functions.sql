CREATE OR REPLACE FUNCTION get_subscriber_balance(p_sub_id INT)
RETURNS NUMERIC
LANGUAGE plpgsql AS $$
DECLARE
    v_balance NUMERIC;
BEGIN
    SELECT balance INTO v_balance
    FROM subscribers
    WHERE sub_id = p_sub_id;
    RETURN v_balance;   -- returns NULL automatically if no row
END;
$$;

CREATE OR REPLACE FUNCTION get_subscriber_status_label(p_sub_id INT)
RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
    v_status  VARCHAR(20);
    v_balance NUMERIC;
BEGIN
    SELECT status, balance INTO v_status, v_balance
    FROM subscribers WHERE sub_id = p_sub_id;

    IF NOT FOUND THEN
        RETURN 'Subscriber not found';
    END IF;

    RETURN CASE v_status
        WHEN 'active'    THEN 'Active'
        WHEN 'blocked'   THEN 'Blocked by operator'
        WHEN 'suspended' THEN 'Suspended on request'
        WHEN 'cancelled' THEN 'Contract cancelled'
        ELSE 'Unknown status: ' || v_status
    END;
END;
$$;


CREATE OR REPLACE FUNCTION classify_balance(p_sub_id INT)
RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
    v_balance NUMERIC;
BEGIN
    SELECT balance INTO v_balance FROM subscribers WHERE sub_id = p_sub_id;

    IF NOT FOUND THEN RETURN 'Subscriber not found'; END IF;

    IF    v_balance < -1000  THEN RETURN 'Critical debt';
    ELSIF v_balance < 0      THEN RETURN 'Debt';
    ELSIF v_balance < 100    THEN RETURN 'Low balance';
    ELSIF v_balance < 1000   THEN RETURN 'Normal';
    ELSE                          RETURN 'High balance';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION get_total_data_gb(p_sub_id INT)
RETURNS NUMERIC
LANGUAGE plpgsql AS $$
DECLARE
    v_total_bytes BIGINT := 0;
    rec           RECORD;
BEGIN
    FOR rec IN
        SELECT ds.bytes_down + ds.bytes_up AS total
        FROM data_sessions ds
        JOIN subscriber_terminals t ON t.terminal_id = ds.terminal_id
        WHERE t.sub_id = p_sub_id
    LOOP
        v_total_bytes := v_total_bytes + rec.total;
    END LOOP;

    RETURN ROUND(v_total_bytes / 1073741824.0, 4);  -- bytes → GB
END;
$$;

CREATE OR REPLACE FUNCTION count_anomalies(p_sat_id INT, p_days INT DEFAULT 7)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM telemetry
    WHERE sat_id      = p_sat_id
      AND anomaly_flag = TRUE
      AND recorded_at >= NOW() - (p_days || ' days')::INTERVAL;
    RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION can_subscribe_plan(p_sub_id INT, p_plan_id INT)
RETURNS BOOLEAN
LANGUAGE plpgsql AS $$
DECLARE
    v_overdue  INT;
    v_active   BOOLEAN;
BEGIN
    SELECT COUNT(*) INTO v_overdue
    FROM invoices WHERE sub_id = p_sub_id AND status = 'overdue';

    SELECT is_active INTO v_active FROM service_plans WHERE plan_id = p_plan_id;

    IF NOT FOUND OR v_active = FALSE THEN RETURN FALSE; END IF;
    RETURN v_overdue = 0;
END;
$$;


CREATE OR REPLACE FUNCTION get_subscriber_finance_card(p_sub_id INT)
RETURNS TABLE (
    full_name      TEXT,
    email          VARCHAR,
    phone          VARCHAR,
    plan_name      VARCHAR,
    monthly_fee    NUMERIC,
    balance        NUMERIC,
    status         VARCHAR,
    terminals      BIGINT,
    total_invoices BIGINT,
    total_paid     NUMERIC
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.full_name::TEXT,
        s.email,
        s.phone,
        sp.plan_name,
        sp.monthly_fee,
        s.balance,
        s.status,
        (SELECT COUNT(*) FROM subscriber_terminals WHERE sub_id = s.sub_id),
        (SELECT COUNT(*) FROM invoices             WHERE sub_id = s.sub_id),
        COALESCE((SELECT SUM(amount) FROM payments WHERE sub_id = s.sub_id), 0)
    FROM subscribers s
    JOIN service_plans sp ON sp.plan_id = s.plan_id
    WHERE s.sub_id = p_sub_id;
END;
$$;

CREATE OR REPLACE FUNCTION get_top_revenue_subscribers(p_limit INT DEFAULT 10)
RETURNS TABLE (
    sub_id        INT,
    full_name     TEXT,
    plan_name     VARCHAR,
    total_revenue NUMERIC
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.sub_id,
        s.full_name::TEXT,
        sp.plan_name,
        COALESCE(SUM(p.amount), 0) AS total_revenue
    FROM subscribers   s
    JOIN service_plans sp ON sp.plan_id = s.plan_id
    LEFT JOIN payments p  ON p.sub_id   = s.sub_id
    GROUP BY s.sub_id, s.full_name, sp.plan_name
    ORDER BY total_revenue DESC
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION get_overdue_subscribers(p_min_debt NUMERIC DEFAULT 0)
RETURNS TABLE (
    sub_id        INT,
    full_name     TEXT,
    phone         VARCHAR,
    overdue_count BIGINT,
    total_debt    NUMERIC
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.sub_id,
        s.full_name::TEXT,
        s.phone,
        COUNT(i.invoice_id)       AS overdue_count,
        SUM(i.total_amount)       AS total_debt
    FROM subscribers s
    JOIN invoices i ON i.sub_id = s.sub_id
    WHERE i.status = 'overdue'
    GROUP BY s.sub_id, s.full_name, s.phone
    HAVING SUM(i.total_amount) > p_min_debt
    ORDER BY total_debt DESC;
END;
$$;

CREATE OR REPLACE FUNCTION recalculate_overage_cost(p_billing_period VARCHAR)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    rec          RECORD;
    v_used_gb    NUMERIC;
    v_overage_gb NUMERIC;
    v_charge     NUMERIC;
    v_updated    INT := 0;
BEGIN
    FOR rec IN
        SELECT
            s.sub_id,
            sp.data_gb_month  AS quota_gb,
            sp.price_per_gb   AS price_per_gb,
            i.invoice_id
        FROM subscribers   s
        JOIN service_plans sp ON sp.plan_id   = s.plan_id
        JOIN invoices      i  ON i.sub_id     = s.sub_id
        WHERE i.billing_period = p_billing_period
          AND i.status         != 'cancelled'
    LOOP
        -- Sum all session bytes for this subscriber in that month
        SELECT COALESCE(SUM(ds.bytes_down + ds.bytes_up), 0) / 1073741824.0
        INTO v_used_gb
        FROM data_sessions ds
        JOIN subscriber_terminals t ON t.terminal_id = ds.terminal_id
        WHERE t.sub_id = rec.sub_id
          AND DATE_TRUNC('month', ds.start_time) = TO_DATE(p_billing_period || '-01', 'YYYY-MM-DD');

        v_overage_gb := GREATEST(v_used_gb - rec.quota_gb, 0);
        v_charge     := ROUND(v_overage_gb * rec.price_per_gb, 2);

        UPDATE invoices
        SET amount_overage = v_charge,
            total_amount   = amount_base + v_charge
        WHERE invoice_id = rec.invoice_id;

        v_updated := v_updated + 1;
    END LOOP;

    RETURN v_updated;
END;
$$;
