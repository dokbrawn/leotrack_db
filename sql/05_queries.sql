SELECT
    s.sub_id,
    s.full_name,
    s.email,
    s.phone,
    sp.plan_name,
    sp.monthly_fee,
    s.balance,
    s.status,
    s.registration_date
FROM subscribers s
JOIN service_plans sp ON sp.plan_id = s.plan_id
ORDER BY s.sub_id;

SELECT
    s.sub_id,
    s.full_name,
    s.phone,
    s.balance,
    s.status,
    sp.plan_name
FROM subscribers s
JOIN service_plans sp ON sp.plan_id = s.plan_id
WHERE s.balance < 0
ORDER BY s.balance ASC;

SELECT
    i.billing_period,
    COUNT(*)                                    AS invoices_total,
    SUM(i.total_amount)                         AS billed_total,
    SUM(CASE WHEN i.status = 'paid'
             THEN i.total_amount ELSE 0 END)    AS collected,
    SUM(CASE WHEN i.status IN ('pending','overdue')
             THEN i.total_amount ELSE 0 END)    AS outstanding
FROM invoices i
GROUP BY i.billing_period
ORDER BY i.billing_period;



SELECT
    s.sub_id,
    s.full_name,
    sp.plan_name,
    sp.monthly_fee,
    s.balance,
    s.status,
    COUNT(DISTINCT t.terminal_id)               AS terminals,
    COALESCE(SUM(p.amount), 0)                  AS total_paid_all_time
FROM subscribers s
JOIN  service_plans       sp ON sp.plan_id    = s.plan_id
LEFT JOIN subscriber_terminals t  ON t.sub_id = s.sub_id
LEFT JOIN payments        p  ON p.sub_id      = s.sub_id
GROUP BY s.sub_id, s.full_name, sp.plan_name, sp.monthly_fee, s.balance, s.status
ORDER BY total_paid_all_time DESC;



SELECT
    sp.plan_name,
    COUNT(DISTINCT s.sub_id)        AS subscriber_count,
    ROUND(AVG(i.total_amount), 2)   AS avg_invoice_amount,
    SUM(i.total_amount)             AS total_revenue
FROM service_plans sp
JOIN subscribers  s  ON s.plan_id  = sp.plan_id
JOIN invoices     i  ON i.sub_id   = s.sub_id
WHERE i.status = 'paid'
GROUP BY sp.plan_id, sp.plan_name
HAVING AVG(i.total_amount) > 200
ORDER BY avg_invoice_amount DESC;


WITH session_totals AS (
    SELECT
        t.sub_id,
        SUM(ds.bytes_down + ds.bytes_up) / 1073741824.0  AS used_gb
    FROM data_sessions ds
    JOIN subscriber_terminals t ON t.terminal_id = ds.terminal_id
    WHERE ds.start_time >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
      AND ds.start_time <  DATE_TRUNC('month', CURRENT_DATE)
    GROUP BY t.sub_id
)
SELECT
    s.sub_id,
    s.full_name,
    sp.plan_name,
    sp.data_gb_month                        AS plan_quota_gb,
    ROUND(st.used_gb::NUMERIC, 2)           AS used_gb,
    ROUND((st.used_gb / sp.data_gb_month * 100)::NUMERIC, 1) AS usage_pct
FROM session_totals st
JOIN subscribers   s  ON s.sub_id  = st.sub_id
JOIN service_plans sp ON sp.plan_id = s.plan_id
WHERE st.used_gb > sp.data_gb_month * 0.80   -- >80% quota used
ORDER BY usage_pct DESC;



SELECT
    sat.sat_id,
    sat.norad_id,
    sat.sat_name,
    sat.status,
    op.plane_name,
    COUNT(*) FILTER (WHERE tlm.anomaly_flag = TRUE) AS anomaly_count,
    ROUND(AVG(tlm.battery_pct), 1)                  AS avg_battery_pct
FROM satellites sat
JOIN orbital_planes    op  ON op.plane_id = sat.plane_id
JOIN telemetry         tlm ON tlm.sat_id  = sat.sat_id
WHERE tlm.recorded_at >= NOW() - INTERVAL '30 days'
GROUP BY sat.sat_id, sat.norad_id, sat.sat_name, sat.status, op.plane_name
ORDER BY anomaly_count DESC, avg_battery_pct ASC
LIMIT 5;



SELECT
    op.plane_name,
    DATE_TRUNC('day', ds.start_time)::DATE          AS traffic_date,
    COUNT(*)                                         AS session_count,
    ROUND(SUM(ds.bytes_down + ds.bytes_up) / 1073741824.0, 3) AS total_gb,
    ROUND(AVG(ds.avg_latency_ms), 1)                AS avg_latency_ms
FROM data_sessions ds
JOIN satellite_beams   sb  ON sb.beam_id  = ds.beam_id
JOIN satellites        sat ON sat.sat_id  = sb.sat_id
JOIN orbital_planes    op  ON op.plane_id = sat.plane_id
WHERE ds.start_time >= '2026-03-01'
  AND ds.start_time <  '2026-06-01'
GROUP BY op.plane_name, DATE_TRUNC('day', ds.start_time)
ORDER BY traffic_date, total_gb DESC;



SELECT
    s.sub_id,
    s.full_name,
    s.phone,
    s.balance,
    i.invoice_id,
    i.billing_period,
    i.total_amount,
    i.status                                AS invoice_status,
    (CURRENT_DATE - i.due_date)             AS days_overdue
FROM subscribers s
JOIN invoices i ON i.sub_id = s.sub_id
WHERE i.status IN ('overdue', 'pending')
  AND i.due_date < CURRENT_DATE
ORDER BY days_overdue DESC, s.balance ASC;



SELECT
    sat.sat_name,
    sat.norad_id,
    sb.beam_index,
    op.plane_name,
    COUNT(bc.coverage_id)               AS terminals_served,
    ROUND(AVG(bc.snr_db), 2)            AS avg_snr_db,
    MIN(bc.snr_db)                      AS min_snr_db
FROM satellite_beams   sb
JOIN satellites        sat ON sat.sat_id  = sb.sat_id
JOIN orbital_planes    op  ON op.plane_id = sat.plane_id
LEFT JOIN beam_coverage bc  ON bc.beam_id = sb.beam_id
                           AND bc.released_at IS NULL   -- active assignments only
GROUP BY sat.sat_id, sat.sat_name, sat.norad_id, sb.beam_index, op.plane_name
HAVING COUNT(bc.coverage_id) > 0
ORDER BY avg_snr_db ASC
LIMIT 10;
