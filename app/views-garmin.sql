-- The Garmin lanes, read from the sanitised rollups catalog `garmin` (sleep
-- nights and daily aggregates). Both instances draw from the rollups; the full
-- snapshots are only ever attached for the private instance's SQL box.
-- Times are naive UTC epoch seconds, as in views-shared.sql.

CREATE OR REPLACE VIEW garmin_points AS
SELECT 'sleep' AS lane, s.start_ts AS t0, s.hours AS value FROM garmin.sleep s
  UNION ALL
  SELECT 'heart', epoch(CAST(d."day" AS TIMESTAMP))::BIGINT, d.hr_avg FROM garmin.daily d WHERE d.hr_avg IS NOT NULL
  UNION ALL
  SELECT 'steps', epoch(CAST(d."day" AS TIMESTAMP))::BIGINT, d.steps FROM garmin.daily d WHERE d.steps IS NOT NULL;

CREATE OR REPLACE VIEW garmin_items AS
SELECT 'sleep' AS lane, s.start_ts AS t0, s.end_ts AS t1, s.hours AS value,
         printf('%.1f h', s.hours) || coalesce(' · ' || lower(s.qualifier), '')
           || coalesce(', score ' || s.score, '') AS label
    FROM garmin.sleep s
  UNION ALL
  SELECT 'heart', x.t0, x.t0 + 86400, d.hr_avg,
         printf('avg %.0f bpm', d.hr_avg) || coalesce(printf(' (%.0f–%.0f)', d.hr_min, d.hr_max), '')
    FROM garmin.daily d, LATERAL (SELECT epoch(CAST(d."day" AS TIMESTAMP))::BIGINT AS t0) x
    WHERE d.hr_avg IS NOT NULL
  UNION ALL
  SELECT 'steps', x.t0, x.t0 + 86400, d.steps, format('{:,} steps', d.steps)
    FROM garmin.daily d, LATERAL (SELECT epoch(CAST(d."day" AS TIMESTAMP))::BIGINT AS t0) x
    WHERE d.steps IS NOT NULL;