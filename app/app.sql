-- timeline (public): the lane timeline over sources that are safe to publish.
-- Everything render reads is created here or in views.sql, before serving.

CREATE OR REPLACE TABLE lanes AS SELECT * FROM (VALUES
  ('music',   1, 'Music',      'events'),
  ('read',    2, 'Read',       'events'),
  ('parkrun', 3, 'Parkrun',    'events'),
  ('chess',   4, 'Chess',      'events'),
  ('sleep',   5, 'Sleep',      'level'),
  ('heart',   6, 'Heart rate', 'level'),
  ('steps',   7, 'Steps',      'level')
) t(id, ord, label, kind);

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

CREATE OR REPLACE TABLE tick_units AS SELECT * FROM (VALUES
  (3600,      's', 3600,    'hm'),
  (10800,     's', 10800,   'hm'),
  (21600,     's', 21600,   'hm'),
  (43200,     's', 43200,   'hm'),
  (86400,     's', 86400,   'd'),
  (172800,    's', 172800,  'd'),
  (604800,    's', 604800,  'd'),
  (2592000,   'm', 1,       'my'),
  (7776000,   'm', 3,       'my'),
  (15552000,  'm', 6,       'my'),
  (31536000,  'm', 12,      'y'),
  (63072000,  'm', 24,      'y'),
  (157680000, 'm', 60,      'y'),
  (315360000, 'm', 120,     'y')
) t(approx, kind, n, fmt);

-- Geometry, in SVG user units. The client passes its width in CSS pixels as
-- w, so a unit is a pixel and text keeps its size at any screen width.
CREATE OR REPLACE MACRO lane_h()   AS 56;
CREATE OR REPLACE MACRO lane_pad() AS 6;
CREATE OR REPLACE MACRO axis_h()   AS 28;
-- Past this many events in a window a lane is drawn as density bars instead of
-- one rectangle per event.
CREATE OR REPLACE MACRO item_max() AS 400;
CREATE OR REPLACE MACRO bar_units() AS 4;

-- strftime wants a constant format, so the unit table names one instead.
CREATE OR REPLACE MACRO tick_label(ts, fmt) AS
  (CASE fmt WHEN 'hm' THEN strftime(ts, '%-d %b %H:%M')
            WHEN 'd'  THEN strftime(ts, '%-d %b')
            WHEN 'my' THEN strftime(ts, '%b %Y')
            ELSE strftime(ts, '%Y') END);

CREATE OR REPLACE MACRO num_param(route, key, dflt, lo, hi) AS
  (least(hi, greatest(lo, coalesce(TRY_CAST(nullif(duckweb_query(route, key), '') AS BIGINT), dflt))));

-- The whole drawing for [f, t) at a given visible span. The svg is wider than
-- the viewport so the browser can pan inside it without asking for more.
CREATE OR REPLACE MACRO lanes_svg(f, t, span, vstart, w) AS (
  WITH
  p AS (SELECT f::BIGINT AS f, t::BIGINT AS t, span::BIGINT AS span,
               w / span::DOUBLE AS u,
               greatest(1, ceil(span / (w / bar_units())))::BIGINT AS bw),
  pts AS (SELECT lp.lane, lp.t0, lp.value FROM lane_points lp, p
          WHERE lp.t0 >= p.f - 86400 AND lp.t0 < p.t),
  modes AS (SELECT lane, count(*) AS n, count(*) <= item_max() AS as_items FROM pts GROUP BY lane),
  items AS (SELECT i.lane, i.t0, i.t1, i.value, i.label
            FROM lane_items i, p, modes m
            WHERE i.lane = m.lane AND m.as_items AND i.t0 >= p.f - 86400 AND i.t0 < p.t),
  bars AS (SELECT pt.lane, (pt.t0 - p.f) // p.bw AS b, count(*) AS c, avg(pt.value) AS v
           FROM pts pt, p, modes m
           WHERE pt.lane = m.lane AND NOT m.as_items AND pt.t0 >= p.f GROUP BY ALL),
  barmax AS (SELECT lane, max(c) AS c FROM bars GROUP BY lane),
  drawn AS (
    SELECT l.ord, l.label AS lane_label,
      '<rect data-lane=' || l.id || ' x=' || printf('%.2f', (i.t0 - p.f) * p.u)
      || ' y=' || printf('%.2f', (l.ord - 1) * lane_h() + axis_h()
           + CASE WHEN l.kind = 'level' THEN lane_h() - lane_pad() - h.h ELSE lane_pad() END)
      || ' width=' || printf('%.2f', greatest((i.t1 - i.t0) * p.u, 1.5))
      || ' height=' || printf('%.2f', h.h) || '><title>'
      || duckweb_escape(strftime(epoch_ms(i.t0 * 1000), '%-d %b %Y %H:%M') || ' · ' || i.label)
      || '</title></rect>' AS el
    FROM items i JOIN lanes l ON l.id = i.lane
    JOIN p ON true
    LEFT JOIN lane_scale sc ON sc.lane = l.id,
    LATERAL (SELECT CASE WHEN l.kind = 'level'
                   THEN (lane_h() - 2 * lane_pad())
                        * least(1.0, greatest(0.04, (i.value - sc.vmin) / nullif(sc.vmax - sc.vmin, 0)))
                   ELSE lane_h() - 2 * lane_pad() END AS h) h
    UNION ALL
    SELECT l.ord, l.label,
      '<rect data-lane=' || l.id || ' x=' || printf('%.2f', b.b * p.bw * p.u)
      || ' y=' || printf('%.2f', (l.ord - 1) * lane_h() + axis_h() + lane_h() - lane_pad() - h.h)
      || ' width=' || printf('%.2f', greatest(p.bw * p.u - 0.6, 0.8))
      || ' height=' || printf('%.2f', h.h) || '><title>'
      || duckweb_escape(strftime(epoch_ms((p.f + b.b * p.bw) * 1000), '%-d %b %Y'))
      || CASE WHEN l.kind = 'level' THEN printf(' · avg %.1f', b.v) ELSE format(' · {:,}', b.c) END
      || '</title></rect>'
    FROM bars b JOIN lanes l ON l.id = b.lane
    JOIN p ON true
    JOIN barmax bm ON bm.lane = b.lane
    LEFT JOIN lane_scale sc ON sc.lane = l.id,
    LATERAL (SELECT (lane_h() - 2 * lane_pad())
                    * CASE WHEN l.kind = 'level'
                        THEN least(1.0, greatest(0.04, (b.v - sc.vmin) / nullif(sc.vmax - sc.vmin, 0)))
                        ELSE greatest(0.04, sqrt(b.c::DOUBLE / bm.c)) END AS h) h),
  -- The smallest unit whose spacing leaves room for a label, about 110 units.
  unit AS (SELECT tu.* FROM tick_units tu, p WHERE tu.approx >= p.span * 110.0 / w
           UNION ALL SELECT tu.* FROM tick_units tu WHERE tu.approx = (SELECT max(approx) FROM tick_units)
           ORDER BY approx LIMIT 1),
  ticks AS (
    SELECT g.s AS ts, un.fmt FROM unit un, p,
      LATERAL (SELECT unnest(generate_series((ceil(p.f / un.n::DOUBLE) * un.n)::BIGINT, p.t, un.n::BIGINT)) AS s) g
    WHERE un.kind = 's'
    UNION ALL
    SELECT epoch(m)::BIGINT, un.fmt FROM unit un, p,
      LATERAL (SELECT unnest(generate_series(TIMESTAMP '1970-01-01', epoch_ms(p.t * 1000), to_months(un.n::INTEGER))) AS m) g
    WHERE un.kind = 'm' AND epoch(m) >= p.f),
  grid AS (
    SELECT '<line x1=' || printf('%.2f', (tk.ts - p.f) * p.u) || ' x2=' || printf('%.2f', (tk.ts - p.f) * p.u)
           || ' y1=' || axis_h() - 6 || ' y2=' || (axis_h() + 7 * lane_h()) || '></line>'
           || '<text x=' || printf('%.2f', (tk.ts - p.f) * p.u + 4) || ' y=' || axis_h() - 10 || '>'
           || tick_label(epoch_ms(tk.ts * 1000), tk.fmt) || '</text>' AS el
    FROM ticks tk, p)
  SELECT '<svg xmlns="http://www.w3.org/2000/svg" role=img aria-label="Timeline lanes" data-timeline-svg'
    || ' data-from=' || p.f || ' data-to=' || p.t || ' data-span=' || p.span
    || ' viewBox="' || printf('%.2f', (vstart - p.f) * p.u) || ' 0 ' || w || ' ' || (axis_h() + 7 * lane_h()) || '"'
    || ' preserveAspectRatio="xMinYMin slice">'
    || '<g class=bands>'
    || (SELECT string_agg('<rect class=band x=0 width=' || printf('%.2f', (p.t - p.f) * p.u) || ' y=' || ((l.ord - 1) * lane_h() + axis_h())
          || ' height=' || lane_h() || ' data-odd=' || (l.ord % 2) || '></rect>', '' ORDER BY l.ord) FROM lanes l)
    || '</g><g class=grid>' || coalesce((SELECT string_agg(el, '') FROM grid), '') || '</g>'
    || '<g class=marks>' || coalesce((SELECT string_agg(el, '' ORDER BY ord) FROM drawn), '') || '</g></svg>'
  FROM p);

CREATE OR REPLACE MACRO doc_open(title) AS (
  '<!doctype html><html lang=en><head><meta charset=utf-8>'
  || '<meta name=viewport content="width=device-width,initial-scale=1">'
  || '<title>' || duckweb_escape(title) || '</title>'
  || '<link rel=stylesheet href="/_duckweb/design/css/style.css">'
  || '<link rel=stylesheet href="/_duckweb/timeline.css"></head><body>');

CREATE OR REPLACE MACRO site_nav(here) AS (
  '<a href="#main-content">Skip to main content</a><header data-site><nav aria-label=Main>'
  || '<a href="/">timeline</a><ul>'
  || '<li><a href="/"' || CASE WHEN here = '/' THEN ' aria-current=page' ELSE '' END || '>Lanes</a></li>'
  || '<li><a href="/sql"' || CASE WHEN here = '/sql' THEN ' aria-current=page' ELSE '' END || '>SQL</a></li>'
  || '</ul></nav></header>');

-- The unit labels a duration is quoted in on the zoom links.
CREATE OR REPLACE TABLE zooms AS SELECT * FROM (VALUES
  (1, '1 day',     86400),
  (2, '1 week',    604800),
  (3, '1 month',   2592000),
  (4, '1 year',    31536000),
  (5, '5 years',   157680000)
) t(ord, label, secs);

CREATE OR REPLACE MACRO lane_labels() AS (
  SELECT string_agg('<span data-lane-label="' || l.id || '" style="top:'
           || printf('%.3f', 100.0 * (axis_h() + (l.ord - 1) * lane_h() + lane_pad()) / (axis_h() + 7 * lane_h()))
           || '%">' || duckweb_escape(l.label) || '</span>', '' ORDER BY l.ord)
  FROM lanes l);

CREATE OR REPLACE MACRO timeline_page(vstart, span) AS (
  doc_open('timeline') || site_nav('/')
  || '<main id=main-content class=container tabindex=-1><h1>Timeline</h1>'
  || '<p>Music, reading, parkrun, chess and the daily shape of sleep, heart rate and steps. '
  || 'Drag the lanes to move through time; zoom with the links, the buttons, or ctrl + scroll.</p>'
  || '<nav aria-label="Zoom" data-zoom-nav><ul>'
  || (SELECT string_agg('<li><a data-zoom=' || z.secs || ' href="/?span=' || z.secs || '&amp;at='
        || (vstart + span // 2 - z.secs // 2) || '">' || z.label || '</a></li>', '' ORDER BY z.ord) FROM zooms z)
  || '<li><a data-zoom=all href="/?span=all">All time</a></li>'
  || '</ul><span data-pan-buttons><button type=button data-pan=-1 aria-label="Earlier">←</button>'
  || '<button type=button data-pan=1 aria-label="Later">→</button>'
  || '<button type=button data-scale=2 aria-label="Zoom out">−</button>'
  || '<button type=button data-scale=0.5 aria-label="Zoom in">+</button></span></nav>'
  || '<section data-timeline aria-label="Lane timeline">'
  || '<div data-viewport tabindex=0 role=region aria-label="Timeline lanes. Drag, or use the arrow keys, to move through time.">'
  || lanes_svg(vstart - span, vstart + 2 * span, span, vstart, 1200)
  || lane_labels() || '</div>'
  || '<p data-range aria-live=polite></p></section>'
  || '<p><small>Sources: Last.fm scrobbles, the reading list, parkrun results, chess games and daily Garmin '
  || 'aggregates (sleep, heart-rate and step rollups; no location data).</small></p>'
  || '</main><script src="/_duckweb/timeline.js" defer></script></body></html>');

CREATE OR REPLACE MACRO sql_row_cap() AS 500;

-- query() is bound before duckweb_match prunes a branch, so on every other
-- route it still parses its argument; an empty one is an error, hence the stand-in.
CREATE OR REPLACE MACRO sql_page(q) AS (
  doc_open('timeline SQL') || site_nav('/sql')
  || '<main id=main-content class=container tabindex=-1><h1>SQL</h1>'
  || '<p>Read-only access to the public tables, as DuckDB SQL: <code>lanes</code>, <code>lane_points</code>, '
  || '<code>lastfm.*</code>, <code>reading.*</code>, <code>parkrun.*</code>, <code>chess.*</code> and the sanitised '
  || '<code>garmin.sleep</code> and <code>garmin.daily</code>. One SELECT per request, at most '
  || sql_row_cap() || ' rows.</p>'
  || '<form method=get action=/sql><label>Query<textarea name=q rows=6 spellcheck=false>'
  || duckweb_escape(q) || '</textarea></label><button type=submit>Run</button></form>');


CREATE OR REPLACE MACRO known(method, route) AS TABLE (
            SELECT 1 FROM duckweb_match(route, '/') WHERE method = 'GET'
  UNION ALL SELECT 1 FROM duckweb_match(route, '/lanes.svg') WHERE method = 'GET'
  UNION ALL SELECT 1 FROM duckweb_match(route, '/sql') WHERE method = 'GET'
);

CREATE OR REPLACE MACRO render(method, route, headers, body) AS TABLE (
            SELECT duckweb_head(200, 'text/html; charset=utf-8', duckweb_header('Cache-Control', 'public, max-age=300'))
              FROM duckweb_match(route, '/') WHERE method = 'GET'
  UNION ALL SELECT duckweb_chunk(timeline_page(s.vstart, s.span))
              FROM duckweb_match(route, '/'),
                   LATERAL (SELECT
                     CASE WHEN duckweb_query(route, 'span') = 'all'
                          THEN greatest(86400, epoch(now())::BIGINT - (SELECT min(t0) FROM lane_points) + 86400)
                          ELSE num_param(route, 'span', 7776000, 3600, 631152000) END AS span) sp,
                   LATERAL (SELECT sp.span AS span,
                     CASE WHEN duckweb_query(route, 'span') = 'all'
                          THEN (SELECT min(t0) FROM lane_points) - 43200
                          ELSE num_param(route, 'at', epoch(now())::BIGINT - sp.span * 9 // 10, 0, 4102444800) END AS vstart) s
              WHERE method = 'GET'
  UNION ALL SELECT duckweb_end() FROM duckweb_match(route, '/') WHERE method = 'GET'

  UNION ALL SELECT duckweb_head(200, 'image/svg+xml; charset=utf-8', duckweb_header('Cache-Control', 'public, max-age=300'))
              FROM duckweb_match(route, '/lanes.svg') WHERE method = 'GET'
  UNION ALL SELECT duckweb_chunk(lanes_svg(
                     num_param(route, 'from', 0, 0, 4102444800),
                     num_param(route, 'to', 1, 1, 4102444800),
                     num_param(route, 'span', 7776000, 3600, 631152000),
                     num_param(route, 'at', 0, 0, 4102444800),
                     num_param(route, 'w', 1200, 320, 4000)))
              FROM duckweb_match(route, '/lanes.svg') WHERE method = 'GET'
  UNION ALL SELECT duckweb_end() FROM duckweb_match(route, '/lanes.svg') WHERE method = 'GET'

  UNION ALL SELECT duckweb_head(200, 'text/html; charset=utf-8', duckweb_header('Cache-Control', 'no-store'))
              FROM duckweb_match(route, '/sql') WHERE method = 'GET'
  UNION ALL SELECT duckweb_chunk(sql_page(duckweb_query(route, 'q')))
              FROM duckweb_match(route, '/sql') WHERE method = 'GET'
  UNION ALL SELECT duckweb_chunk('<pre data-result>')
              FROM duckweb_match(route, '/sql') WHERE method = 'GET' AND duckweb_query(route, 'q') <> ''
  UNION ALL SELECT duckweb_chunk(duckweb_escape(to_json(t)::VARCHAR) || chr(10))
              FROM duckweb_match(route, '/sql'),
                   (SELECT * FROM query(coalesce(nullif(duckweb_query(route, 'q'), ''), 'SELECT 1 WHERE false'))
                    LIMIT sql_row_cap()) t
              WHERE method = 'GET' AND duckweb_query(route, 'q') <> ''
  UNION ALL SELECT duckweb_chunk('</pre>')
              FROM duckweb_match(route, '/sql') WHERE method = 'GET' AND duckweb_query(route, 'q') <> ''
  UNION ALL SELECT duckweb_chunk('</main></body></html>')
              FROM duckweb_match(route, '/sql') WHERE method = 'GET'
  UNION ALL SELECT duckweb_end() FROM duckweb_match(route, '/sql') WHERE method = 'GET'

  UNION ALL SELECT duckweb_head(404, 'text/plain; charset=utf-8', '') WHERE NOT EXISTS (SELECT 1 FROM known(method, route))
  UNION ALL SELECT duckweb_chunk('not found') WHERE NOT EXISTS (SELECT 1 FROM known(method, route))
  UNION ALL SELECT duckweb_end() WHERE NOT EXISTS (SELECT 1 FROM known(method, route))
);
