-- Normalises every public source into two shapes the lane timeline reads.
-- The catalogs lastfm, reading, parkrun, chess and garmin are attached by the
-- caller (the NixOS module, or the check's fixtures); nothing else is visible.
--
-- lane_points(lane, t0, value): one row per event or per day, cheap to scan.
-- lane_items(lane, t0, t1, value, label): the same rows with a span and a
--   tooltip, which for music costs a join, so it is only read for narrow windows.
-- Times are naive UTC epoch seconds: Garmin stores wall-clock strings and
-- formatting a TIMESTAMPTZ in the reader's zone has inverted days before.

CREATE OR REPLACE VIEW lane_points AS
  SELECT 'music' AS lane, l.date_uts::BIGINT AS t0, 1.0 AS value FROM lastfm.listens l
  UNION ALL
  SELECT 'read', epoch(strptime(left(r."date", 19), '%Y-%m-%dT%H:%M:%S'))::BIGINT, 1.0
    FROM reading."read" r WHERE r."date" IS NOT NULL
  UNION ALL
  SELECT 'parkrun', epoch(CAST(p.RunDate AS TIMESTAMP))::BIGINT + 9 * 3600, 1.0 FROM parkrun.runs p
  UNION ALL
  SELECT 'chess', epoch(strptime(c."date", '%Y.%m.%d'))::BIGINT, 1.0
    FROM chess.games c WHERE c."date" IS NOT NULL
  UNION ALL
  SELECT 'sleep', s.start_ts, s.hours FROM garmin.sleep s
  UNION ALL
  SELECT 'heart', epoch(CAST(d."day" AS TIMESTAMP))::BIGINT, d.hr_avg FROM garmin.daily d WHERE d.hr_avg IS NOT NULL
  UNION ALL
  SELECT 'steps', epoch(CAST(d."day" AS TIMESTAMP))::BIGINT, d.steps FROM garmin.daily d WHERE d.steps IS NOT NULL;

CREATE OR REPLACE VIEW lane_items AS
  SELECT 'music' AS lane, l.date_uts::BIGINT AS t0,
         l.date_uts::BIGINT + coalesce(t.avg_estimated_duration, 300)::BIGINT AS t1,
         1.0 AS value,
         t.name || coalesce(' — ' || ar.name, '') AS label
    FROM lastfm.listens l
    JOIN lastfm.tracks t ON t.id = l.tracks_id
    LEFT JOIN lastfm.albums al ON al.id = t.albums_id
    LEFT JOIN lastfm.artists ar ON ar.id = al.artists_id
  UNION ALL
  SELECT 'read', x.t0, x.t0 + 1800, 1.0, x.title
    FROM (SELECT epoch(strptime(left(r."date", 19), '%Y-%m-%dT%H:%M:%S'))::BIGINT AS t0, r.title
            FROM reading."read" r WHERE r."date" IS NOT NULL) x
  UNION ALL
  SELECT 'parkrun', x.t0, x.t0 + coalesce(epoch(TRY_CAST(p."Time" AS TIME)), 1800)::BIGINT, 1.0,
         p.Event || ' #' || p.RunNumber || ' — ' || p."Time" || ', position ' || p.Pos
    FROM parkrun.runs p, LATERAL (SELECT epoch(CAST(p.RunDate AS TIMESTAMP))::BIGINT + 9 * 3600 AS t0) x
  UNION ALL
  SELECT 'chess', x.t0, x.t0 + 86400, 1.0,
         c.white || ' v ' || c.black || ' ' || coalesce(c.result, '')
    FROM chess.games c, LATERAL (SELECT epoch(strptime(c."date", '%Y.%m.%d'))::BIGINT AS t0) x
    WHERE c."date" IS NOT NULL
  UNION ALL
  SELECT 'sleep', s.start_ts, s.end_ts, s.hours,
         printf('%.1f h', s.hours) || coalesce(' · ' || lower(s.qualifier), '')
           || coalesce(', score ' || s.score, '')
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
