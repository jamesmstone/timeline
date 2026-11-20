-- The public instance's lanes: the four public sources and the sanitised Garmin rollups.

CREATE OR REPLACE TABLE lanes AS SELECT * FROM (VALUES
  ('music',   1, 'Music',      'events'),
  ('read',    2, 'Read',       'events'),
  ('parkrun', 3, 'Parkrun',    'events'),
  ('chess',   4, 'Chess',      'events'),
  ('sleep',   5, 'Sleep',      'level'),
  ('heart',   6, 'Heart rate', 'level'),
  ('steps',   7, 'Steps',      'level')
) t(id, ord, label, kind);

CREATE OR REPLACE VIEW lane_points AS
  SELECT * FROM shared_points UNION ALL SELECT * FROM garmin_points;
CREATE OR REPLACE VIEW lane_items AS
  SELECT * FROM shared_items UNION ALL SELECT * FROM garmin_items;

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
    FROM lane_points WHERE lane = 'steps';


-- The lanes the pages draw: all of them.
CREATE OR REPLACE MACRO default_lanes() AS (SELECT list(id ORDER BY ord) FROM lanes);
