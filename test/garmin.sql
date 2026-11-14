-- The full Garmin snapshots as the sanitiser finds them, canaries included:
-- anything below that reaches the public file or the SQL box is a leak.
ATTACH getvariable('out') || '/james_garmin.db' AS g (TYPE sqlite);
CREATE TABLE g.sleep("day" VARCHAR, start VARCHAR, "end" VARCHAR, total_sleep VARCHAR, deep_sleep VARCHAR,
  light_sleep VARCHAR, rem_sleep VARCHAR, awake VARCHAR, avg_spo2 DOUBLE, avg_rr DOUBLE, avg_stress DOUBLE,
  score INTEGER, qualifier VARCHAR);
INSERT INTO g.sleep VALUES
  ('2026-01-11', '2026-01-10 22:30:00.000000', '2026-01-11 06:00:00.000000', '07:30:00.000000', '01:30:00.000000',
   '04:30:00.000000', '01:30:00.000000', '00:30:00.000000', 95.0, 14.0, 20.0, 81, 'GOOD'),
  ('2026-01-12', NULL, NULL, '00:00:00.000000', '00:00:00.000000', '00:00:00.000000', '00:00:00.000000', '00:00:00.000000',
   NULL, NULL, NULL, NULL, NULL);

ATTACH getvariable('out') || '/james_garmin_summary.db' AS s (TYPE sqlite);
CREATE TABLE s.days_summary("day" VARCHAR, hr_avg DOUBLE, hr_min DOUBLE, hr_max DOUBLE, rhr_avg DOUBLE,
  steps INTEGER, stress_avg INTEGER, weight_avg DOUBLE);
INSERT INTO s.days_summary VALUES
  ('2026-01-10', 62.5, 45.0, 120.0, 50.0, 8000, 30, 80.5),
  ('2026-01-11', 64.0, 46.0, 130.0, 51.0, 12000, 28, 80.4);

ATTACH getvariable('out') || '/james_garmin_activities.db' AS a (TYPE sqlite);
CREATE TABLE a.activity_records(timestamp VARCHAR, position_lat DOUBLE, position_long DOUBLE, canary VARCHAR);
INSERT INTO a.activity_records VALUES ('2026-01-10 08:00:00', -37.81, 144.96, 'GPS-CANARY');

ATTACH getvariable('out') || '/james_garmin_monitoring.db' AS m (TYPE sqlite);
CREATE TABLE m.monitoring_hr("timestamp" VARCHAR, heart_rate INTEGER);
INSERT INTO m.monitoring_hr VALUES ('2026-01-10 08:00:00', 77);
