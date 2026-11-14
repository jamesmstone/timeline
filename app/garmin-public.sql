-- Reads the full Garmin snapshots and fills the only Garmin data the public
-- instance may hold: one row per night of sleep and one per day of rollups.
-- Nothing in here may carry a coordinate or a sub-day sample. Variables:
--   garmin_dir   directory holding james_garmin.db and james_garmin_summary.db
--   out          path of the SQLite file to write
-- The scanner maps declared TIME columns to TIMESTAMP and then fails to parse
-- them, so everything is read as text and cast here.
SET GLOBAL sqlite_all_varchar = true;
ATTACH getvariable('garmin_dir') || '/james_garmin.db' AS g (TYPE sqlite, READ_ONLY);
ATTACH getvariable('garmin_dir') || '/james_garmin_summary.db' AS s (TYPE sqlite, READ_ONLY);
ATTACH getvariable('out') AS pub (TYPE sqlite);

.read garmin-schema.sql

INSERT INTO pub.sleep
SELECT
  CAST(CAST(day AS DATE) AS VARCHAR),
  epoch(CAST(start AS TIMESTAMP))::BIGINT,
  epoch(CAST("end" AS TIMESTAMP))::BIGINT,
  epoch(CAST(total_sleep AS TIME)) / 3600.0,
  epoch(CAST(deep_sleep AS TIME)) / 3600.0,
  epoch(CAST(light_sleep AS TIME)) / 3600.0,
  epoch(CAST(rem_sleep AS TIME)) / 3600.0,
  epoch(CAST(awake AS TIME)) / 3600.0,
  CAST(score AS BIGINT),
  qualifier
FROM g.sleep
WHERE start IS NOT NULL AND "end" IS NOT NULL AND CAST(total_sleep AS TIME) > TIME '00:00:00'
ORDER BY day;

INSERT INTO pub.daily
SELECT
  CAST(CAST(day AS DATE) AS VARCHAR),
  CAST(hr_avg AS DOUBLE), CAST(hr_min AS DOUBLE), CAST(hr_max AS DOUBLE),
  CAST(rhr_avg AS DOUBLE), CAST(steps AS BIGINT), CAST(stress_avg AS DOUBLE)
FROM s.days_summary
ORDER BY day;
