CREATE TABLE IF NOT EXISTS subscriber_audit (
    audit_id      BIGSERIAL   PRIMARY KEY,
    sub_id        INT         NOT NULL,
    operation     VARCHAR(10) NOT NULL,   -- INSERT | UPDATE | DELETE
    changed_at    TIMESTAMP   NOT NULL DEFAULT NOW(),
    old_status    VARCHAR(20),
    new_status    VARCHAR(20),
    old_balance   NUMERIC,
    new_balance   NUMERIC,
    changed_by    TEXT        DEFAULT CURRENT_USER
);

CREATE TABLE IF NOT EXISTS invoice_archive (
    archive_id    BIGSERIAL   PRIMARY KEY,
    invoice_id    INT         NOT NULL,
    sub_id        INT         NOT NULL,
    billing_period VARCHAR(7) NOT NULL,
    total_amount  NUMERIC     NOT NULL,
    status        VARCHAR(20) NOT NULL,
    archived_at   TIMESTAMP   NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS satellite_health_log (
    log_id        BIGSERIAL   PRIMARY KEY,
    sat_id        INT         NOT NULL,
    recorded_at   TIMESTAMP   NOT NULL,
    anomaly_flag  BOOLEAN,
    battery_pct   NUMERIC,
    logged_at     TIMESTAMP   NOT NULL DEFAULT NOW()
);


CREATE OR REPLACE FUNCTION trg_fn_protect_balance()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.balance < -5000.00 THEN
        RAISE EXCEPTION
            'Balance cannot drop below -5000. Attempted value: %', NEW.balance;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_balance ON subscribers;
CREATE TRIGGER trg_protect_balance
BEFORE UPDATE OF balance ON subscribers
FOR EACH ROW EXECUTE FUNCTION trg_fn_protect_balance();


CREATE OR REPLACE FUNCTION trg_fn_subscriber_audit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO subscriber_audit
            (sub_id, operation, new_status, new_balance)
        VALUES (NEW.sub_id, 'INSERT', NEW.status, NEW.balance);
        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO subscriber_audit
            (sub_id, operation, old_status, new_status, old_balance, new_balance)
        VALUES (NEW.sub_id, 'UPDATE',
                OLD.status, NEW.status,
                OLD.balance, NEW.balance);
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO subscriber_audit
            (sub_id, operation, old_status, old_balance)
        VALUES (OLD.sub_id, 'DELETE', OLD.status, OLD.balance);
        RETURN OLD;
    END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_subscriber_audit ON subscribers;
CREATE TRIGGER trg_subscriber_audit
AFTER INSERT OR UPDATE OR DELETE ON subscribers
FOR EACH ROW EXECUTE FUNCTION trg_fn_subscriber_audit();



CREATE OR REPLACE FUNCTION trg_fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_updated_at ON subscribers;
CREATE TRIGGER trg_set_updated_at
BEFORE UPDATE ON subscribers
FOR EACH ROW EXECUTE FUNCTION trg_fn_set_updated_at();



CREATE OR REPLACE FUNCTION trg_fn_invoice_status_guard()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status = 'paid' AND NEW.status != 'paid' THEN
        RAISE EXCEPTION
            'Cannot change status of a paid invoice (id=%). Current: %, Attempted: %',
            OLD.invoice_id, OLD.status, NEW.status;
    END IF;
    IF OLD.status = 'overdue' AND NEW.status = 'pending' THEN
        RAISE EXCEPTION
            'Cannot revert overdue invoice (id=%) back to pending.',
            OLD.invoice_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_invoice_status_guard ON invoices;
CREATE TRIGGER trg_invoice_status_guard
BEFORE UPDATE OF status ON invoices
FOR EACH ROW EXECUTE FUNCTION trg_fn_invoice_status_guard();



CREATE OR REPLACE FUNCTION trg_fn_archive_invoice()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO invoice_archive
        (invoice_id, sub_id, billing_period, total_amount, status)
    VALUES
        (OLD.invoice_id, OLD.sub_id, OLD.billing_period, OLD.total_amount, OLD.status);
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_archive_invoice ON invoices;
CREATE TRIGGER trg_archive_invoice
AFTER DELETE ON invoices
FOR EACH ROW EXECUTE FUNCTION trg_fn_archive_invoice();



CREATE OR REPLACE FUNCTION trg_fn_protect_active_plan()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.is_active = TRUE THEN
        RAISE EXCEPTION
            'Cannot delete active service plan "%" (id=%). Deactivate it first.',
            OLD.plan_name, OLD.plan_id;
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_active_plan ON service_plans;
CREATE TRIGGER trg_protect_active_plan
BEFORE DELETE ON service_plans
FOR EACH ROW EXECUTE FUNCTION trg_fn_protect_active_plan();



CREATE OR REPLACE FUNCTION trg_fn_log_sat_anomaly()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.anomaly_flag = TRUE THEN
        INSERT INTO satellite_health_log
            (sat_id, recorded_at, anomaly_flag, battery_pct)
        VALUES
            (NEW.sat_id, NEW.recorded_at, NEW.anomaly_flag, NEW.battery_pct);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_sat_anomaly ON telemetry;
CREATE TRIGGER trg_log_sat_anomaly
AFTER INSERT ON telemetry
FOR EACH ROW EXECUTE FUNCTION trg_fn_log_sat_anomaly();
