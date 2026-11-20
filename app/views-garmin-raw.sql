-- The raw Garmin lanes behind /embed.svg: per-sample heart rate and stress, from
-- the full snapshots garmin_monitoring and garmin_full. Private instance only.
-- Nothing here is ever exported or attached to the public instance.
-- Times are naive UTC epoch seconds, as in views-shared.sql.

CREATE OR REPLACE VIEW garmin_raw_points AS
  SELECT 'hr' AS lane, epoch(CAST(h."timestamp" AS TIMESTAMP))::BIGINT AS t0, h.heart_rate::DOUBLE AS value
    FROM garmin_monitoring.monitoring_hr h WHERE h.heart_rate IS NOT NULL
  UNION ALL
  SELECT 'stress', epoch(CAST(s."timestamp" AS TIMESTAMP))::BIGINT, s.stress::DOUBLE
    FROM garmin_full.stress s WHERE s.stress > 0;

CREATE OR REPLACE VIEW garmin_raw_items AS
  SELECT 'hr' AS lane, x.t0, x.t0 + 60 AS t1, h.heart_rate::DOUBLE AS value, h.heart_rate || ' bpm' AS label
    FROM garmin_monitoring.monitoring_hr h, LATERAL (SELECT epoch(CAST(h."timestamp" AS TIMESTAMP))::BIGINT AS t0) x
    WHERE h.heart_rate IS NOT NULL
  UNION ALL
  SELECT 'stress', x.t0, x.t0 + 180, s.stress::DOUBLE, 'stress ' || s.stress
    FROM garmin_full.stress s, LATERAL (SELECT epoch(CAST(s."timestamp" AS TIMESTAMP))::BIGINT AS t0) x
    WHERE s.stress > 0;
