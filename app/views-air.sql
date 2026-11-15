-- The air lane, from the purifier recorder's status table as snapshotted into
-- a SQLite file. Naive UTC epoch seconds, as everywhere else.

CREATE OR REPLACE VIEW air_points AS
  SELECT 'air' AS lane, epoch(CAST(a.recorded_at AS TIMESTAMP))::BIGINT AS t0, a.pm25_ugm3::DOUBLE AS value
    FROM purifier.status a WHERE a.pm25_ugm3 IS NOT NULL;

CREATE OR REPLACE VIEW air_items AS
  SELECT 'air' AS lane, x.t0, x.t0 + 60 AS t1, a.pm25_ugm3::DOUBLE AS value,
         printf('PM2.5 %.0f µg/m³', a.pm25_ugm3) || coalesce(', fan ' || a.fan_level, '') AS label
    FROM purifier.status a, LATERAL (SELECT epoch(CAST(a.recorded_at AS TIMESTAMP))::BIGINT AS t0) x
    WHERE a.pm25_ugm3 IS NOT NULL;
