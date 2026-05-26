DROP TABLE IF EXISTS telemetry          CASCADE;
DROP TABLE IF EXISTS data_sessions      CASCADE;
DROP TABLE IF EXISTS beam_coverage      CASCADE;
DROP TABLE IF EXISTS subscriber_terminals CASCADE;
DROP TABLE IF EXISTS invoices           CASCADE;
DROP TABLE IF EXISTS payments           CASCADE;
DROP TABLE IF EXISTS plan_changes       CASCADE;
DROP TABLE IF EXISTS subscribers        CASCADE;
DROP TABLE IF EXISTS service_plans      CASCADE;
DROP TABLE IF EXISTS satellite_beams    CASCADE;
DROP TABLE IF EXISTS satellites         CASCADE;
DROP TABLE IF EXISTS orbital_planes     CASCADE;


CREATE TABLE orbital_planes (
    plane_id        SERIAL          PRIMARY KEY,
    plane_name      VARCHAR(50)     NOT NULL UNIQUE,
    altitude_km     INTEGER         NOT NULL CHECK (altitude_km BETWEEN 200 AND 2000),
    inclination_deg NUMERIC(6,3)    NOT NULL CHECK (inclination_deg BETWEEN 0 AND 180),
    sat_count_design INTEGER        NOT NULL CHECK (sat_count_design > 0),
    constellation   VARCHAR(50)     NOT NULL DEFAULT 'LeoTrack-1',
    created_at      TIMESTAMP       NOT NULL DEFAULT NOW()
);


CREATE TABLE satellites (
    sat_id          SERIAL          PRIMARY KEY,
    norad_id        VARCHAR(10)     NOT NULL UNIQUE,
    sat_name        VARCHAR(60)     NOT NULL,
    plane_id        INTEGER         NOT NULL
                        REFERENCES orbital_planes(plane_id) ON DELETE RESTRICT,
    slot_number     INTEGER         NOT NULL CHECK (slot_number > 0),
    launch_date     DATE            NOT NULL,
    status          VARCHAR(20)     NOT NULL DEFAULT 'operational'
                        CHECK (status IN ('operational','degraded','decommissioned','standby')),
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    UNIQUE (plane_id, slot_number)
);


CREATE TABLE satellite_beams (
    beam_id         SERIAL          PRIMARY KEY,
    sat_id          INTEGER         NOT NULL
                        REFERENCES satellites(sat_id) ON DELETE CASCADE,
    beam_index      INTEGER         NOT NULL CHECK (beam_index > 0),
    center_lat      NUMERIC(8,5)    NOT NULL CHECK (center_lat  BETWEEN -90  AND  90),
    center_lon      NUMERIC(8,5)    NOT NULL CHECK (center_lon  BETWEEN -180 AND 180),
    bandwidth_mhz   INTEGER         NOT NULL CHECK (bandwidth_mhz > 0),
    polarization    VARCHAR(4)      NOT NULL DEFAULT 'RHCP'
                        CHECK (polarization IN ('RHCP','LHCP','LINEAR')),
    UNIQUE (sat_id, beam_index)
);


CREATE TABLE service_plans (
    plan_id         SERIAL          PRIMARY KEY,
    plan_name       VARCHAR(80)     NOT NULL UNIQUE,
    monthly_fee     NUMERIC(10,2)   NOT NULL CHECK (monthly_fee >= 0),
    data_gb_month   INTEGER         NOT NULL CHECK (data_gb_month > 0),
    speed_dl_mbps   INTEGER         NOT NULL CHECK (speed_dl_mbps > 0),
    speed_ul_mbps   INTEGER         NOT NULL CHECK (speed_ul_mbps > 0),
    sla_uptime_pct  NUMERIC(5,2)    NOT NULL DEFAULT 99.00
                        CHECK (sla_uptime_pct BETWEEN 0 AND 100),
    price_per_gb    NUMERIC(8,4)    NOT NULL DEFAULT 0.0 CHECK (price_per_gb >= 0),
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP       NOT NULL DEFAULT NOW()
);


CREATE TABLE subscribers (
    sub_id          SERIAL          PRIMARY KEY,
    full_name       VARCHAR(120)    NOT NULL,
    email           VARCHAR(120)    NOT NULL UNIQUE,
    phone           VARCHAR(20)     NOT NULL UNIQUE,
    plan_id         INTEGER         NOT NULL
                        REFERENCES service_plans(plan_id) ON DELETE RESTRICT,
    balance         NUMERIC(12,2)   NOT NULL DEFAULT 0.00
                        CHECK (balance >= -5000.00),
    status          VARCHAR(20)     NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active','blocked','suspended','cancelled')),
    registration_date DATE          NOT NULL DEFAULT CURRENT_DATE,
    passport_number VARCHAR(20),
    birth_date      DATE,
    updated_at      TIMESTAMP,
    CONSTRAINT chk_email_format CHECK (email LIKE '%@%')
);


CREATE TABLE subscriber_terminals (
    terminal_id     SERIAL          PRIMARY KEY,
    sub_id          INTEGER         NOT NULL
                        REFERENCES subscribers(sub_id) ON DELETE CASCADE,
    serial_number   VARCHAR(30)     NOT NULL UNIQUE,
    hardware_model  VARCHAR(60)     NOT NULL,
    firmware_ver    VARCHAR(20),
    lat             NUMERIC(8,5)    CHECK (lat  BETWEEN -90  AND  90),
    lon             NUMERIC(8,5)    CHECK (lon  BETWEEN -180 AND 180),
    install_date    DATE            NOT NULL DEFAULT CURRENT_DATE,
    status          VARCHAR(20)     NOT NULL DEFAULT 'online'
                        CHECK (status IN ('online','offline','faulty','decommissioned'))
);


CREATE TABLE beam_coverage (
    coverage_id     SERIAL          PRIMARY KEY,
    terminal_id     INTEGER         NOT NULL
                        REFERENCES subscriber_terminals(terminal_id) ON DELETE CASCADE,
    beam_id         INTEGER         NOT NULL
                        REFERENCES satellite_beams(beam_id) ON DELETE CASCADE,
    assigned_at     TIMESTAMP       NOT NULL DEFAULT NOW(),
    released_at     TIMESTAMP,
    snr_db          NUMERIC(6,2),
    CONSTRAINT chk_release_after_assign CHECK (released_at IS NULL OR released_at > assigned_at)
);


CREATE TABLE data_sessions (
    session_id      BIGSERIAL       PRIMARY KEY,
    terminal_id     INTEGER         NOT NULL
                        REFERENCES subscriber_terminals(terminal_id) ON DELETE CASCADE,
    beam_id         INTEGER
                        REFERENCES satellite_beams(beam_id) ON DELETE SET NULL,
    start_time      TIMESTAMP       NOT NULL,
    end_time        TIMESTAMP,
    bytes_down      BIGINT          NOT NULL DEFAULT 0 CHECK (bytes_down >= 0),
    bytes_up        BIGINT          NOT NULL DEFAULT 0 CHECK (bytes_up >= 0),
    avg_latency_ms  INTEGER         CHECK (avg_latency_ms >= 0),
    session_cost    NUMERIC(10,4)   NOT NULL DEFAULT 0.0000 CHECK (session_cost >= 0),
    CONSTRAINT chk_end_after_start CHECK (end_time IS NULL OR end_time > start_time)
);


CREATE TABLE telemetry (
    tlm_id          BIGSERIAL       PRIMARY KEY,
    sat_id          INTEGER         NOT NULL
                        REFERENCES satellites(sat_id) ON DELETE CASCADE,
    recorded_at     TIMESTAMP       NOT NULL DEFAULT NOW(),
    battery_pct     NUMERIC(5,2)    CHECK (battery_pct BETWEEN 0 AND 100),
    solar_watts     NUMERIC(8,2)    CHECK (solar_watts >= 0),
    temp_c          NUMERIC(6,2),
    downlink_eirp   NUMERIC(7,3),
    anomaly_flag    BOOLEAN         NOT NULL DEFAULT FALSE
);


CREATE TABLE invoices (
    invoice_id      SERIAL          PRIMARY KEY,
    sub_id          INTEGER         NOT NULL
                        REFERENCES subscribers(sub_id) ON DELETE CASCADE,
    billing_period  VARCHAR(7)      NOT NULL,           -- 'YYYY-MM'
    issue_date      DATE            NOT NULL DEFAULT CURRENT_DATE,
    due_date        DATE            NOT NULL,
    amount_base     NUMERIC(10,2)   NOT NULL CHECK (amount_base >= 0),
    amount_overage  NUMERIC(10,2)   NOT NULL DEFAULT 0.00 CHECK (amount_overage >= 0),
    total_amount    NUMERIC(10,2)   NOT NULL CHECK (total_amount >= 0),
    status          VARCHAR(20)     NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','paid','overdue','cancelled')),
    UNIQUE (sub_id, billing_period),
    CONSTRAINT chk_due_after_issue CHECK (due_date >= issue_date)
);


CREATE TABLE payments (
    payment_id      SERIAL          PRIMARY KEY,
    sub_id          INTEGER         NOT NULL
                        REFERENCES subscribers(sub_id) ON DELETE RESTRICT,
    invoice_id      INTEGER         REFERENCES invoices(invoice_id) ON DELETE SET NULL,
    amount          NUMERIC(10,2)   NOT NULL CHECK (amount > 0),
    payment_date    TIMESTAMP       NOT NULL DEFAULT NOW(),
    method          VARCHAR(30)     NOT NULL DEFAULT 'card'
                        CHECK (method IN ('card','bank_transfer','crypto','voucher','cash')),
    transaction_ref VARCHAR(60)     NOT NULL UNIQUE
);


CREATE TABLE plan_changes (
    change_id       SERIAL          PRIMARY KEY,
    sub_id          INTEGER         NOT NULL
                        REFERENCES subscribers(sub_id) ON DELETE CASCADE,
    old_plan_id     INTEGER         REFERENCES service_plans(plan_id) ON DELETE SET NULL,
    new_plan_id     INTEGER         NOT NULL
                        REFERENCES service_plans(plan_id) ON DELETE RESTRICT,
    changed_at      TIMESTAMP       NOT NULL DEFAULT NOW(),
    reason          TEXT
);




CREATE INDEX idx_satellites_plane      ON satellites      (plane_id);
CREATE INDEX idx_satellites_status     ON satellites      (status);


CREATE INDEX idx_beams_sat             ON satellite_beams (sat_id);


CREATE INDEX idx_subs_plan             ON subscribers     (plan_id);
CREATE INDEX idx_subs_status           ON subscribers     (status);
CREATE INDEX idx_subs_balance          ON subscribers     (balance);


CREATE INDEX idx_terminals_sub         ON subscriber_terminals (sub_id);
CREATE INDEX idx_terminals_status      ON subscriber_terminals (status);


CREATE INDEX idx_sessions_terminal     ON data_sessions (terminal_id);
CREATE INDEX idx_sessions_start        ON data_sessions (start_time DESC);
CREATE INDEX idx_sessions_terminal_start ON data_sessions (terminal_id, start_time DESC);


CREATE INDEX idx_tlm_sat               ON telemetry (sat_id);
CREATE INDEX idx_tlm_time              ON telemetry (recorded_at DESC);
CREATE INDEX idx_tlm_sat_time          ON telemetry (sat_id, recorded_at DESC);
CREATE INDEX idx_tlm_anomaly           ON telemetry (anomaly_flag) WHERE anomaly_flag = TRUE;


CREATE INDEX idx_inv_sub               ON invoices (sub_id);
CREATE INDEX idx_inv_status            ON invoices (status);
CREATE INDEX idx_inv_period            ON invoices (billing_period);


CREATE INDEX idx_pay_sub               ON payments (sub_id);
CREATE INDEX idx_pay_date              ON payments (payment_date DESC);
