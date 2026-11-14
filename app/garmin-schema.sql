-- The shape of the Garmin data the public instance may hold. The tables are
-- written into a SQLite file attached as pub: sqlite_scanner re-opens such a
-- file after an atomic rename, which a DuckDB file attached long-term does not.
CREATE TABLE pub.sleep(
  "day" VARCHAR, start_ts BIGINT, end_ts BIGINT,
  "hours" DOUBLE, deep_hours DOUBLE, light_hours DOUBLE, rem_hours DOUBLE, awake_hours DOUBLE,
  score BIGINT, qualifier VARCHAR);
CREATE TABLE pub.daily(
  "day" VARCHAR, hr_avg DOUBLE, hr_min DOUBLE, hr_max DOUBLE, rhr DOUBLE,
  steps BIGINT, stress_avg DOUBLE);
