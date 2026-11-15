-- The private instance's lanes: everything the public one draws, plus chat
-- volume and the purifier's PM2.5. The Garmin lanes stay on the rollups; the
-- full snapshots are for the SQL box.

CREATE OR REPLACE TABLE lanes AS SELECT * FROM (VALUES
  ('music',   1, 'Music',      'events'),
  ('read',    2, 'Read',       'events'),
  ('parkrun', 3, 'Parkrun',    'events'),
  ('chess',   4, 'Chess',      'events'),
  ('sleep',   5, 'Sleep',      'level'),
  ('heart',   6, 'Heart rate', 'level'),
  ('steps',   7, 'Steps',      'level'),
  ('chat',    8, 'Chat',       'events'),
  ('air',     9, 'Air (PM2.5)', 'level')
) t(id, ord, label, kind);

CREATE OR REPLACE VIEW lane_points AS
  SELECT * FROM shared_points UNION ALL SELECT * FROM garmin_points
  UNION ALL SELECT * FROM chat_points UNION ALL SELECT * FROM air_points;
CREATE OR REPLACE VIEW lane_items AS
  SELECT * FROM shared_items UNION ALL SELECT * FROM garmin_items
  UNION ALL SELECT * FROM chat_items UNION ALL SELECT * FROM air_items;

-- Level lanes are drawn against a fixed range so bars keep their height while
-- the window pans; the tails are clipped so one outlier day cannot flatten the
-- rest.
CREATE OR REPLACE VIEW lane_scale AS
  SELECT 'sleep' AS lane, 0.0 AS vmin, coalesce(max(value), 12.0) AS vmax
    FROM lane_points WHERE lane = 'sleep'
  UNION ALL
  SELECT 'heart', coalesce(quantile_cont(value, 0.01), 40.0), coalesce(quantile_cont(value, 0.99), 100.0)
    FROM lane_points WHERE lane = 'heart'
  UNION ALL
  SELECT 'steps', 0.0, coalesce(quantile_cont(value, 0.99), 10000.0)
    FROM lane_points WHERE lane = 'steps'
  UNION ALL
  SELECT 'air', 0.0, coalesce(quantile_cont(value, 0.99), 50.0)
    FROM lane_points WHERE lane = 'air';

