-- The lane timeline and the routes both instances share. Each instance reads
-- lane_points, lane_items, lane_scale and lanes from its own lanes-*.sql, and
-- defines the macros named below in instance-*.sql:
--   site_nav(here), home_intro(), sql_intro(), known(), render()

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
CREATE OR REPLACE MACRO lanes_h(ids) AS axis_h() + (SELECT count(*) FROM lanes WHERE list_contains(ids, id)) * lane_h();
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

-- Drawn for [f, t), wider than the viewport so the browser can pan without asking for more.
CREATE OR REPLACE MACRO lanes_svg_of(f, t, span, vstart, w, ids) AS (
  WITH
  sel AS (SELECT l.id, l.label, l.kind, row_number() OVER (ORDER BY list_position(ids, l.id)) AS ord
          FROM lanes l WHERE list_contains(ids, l.id)),
  p AS (SELECT f::BIGINT AS f, t::BIGINT AS t, span::BIGINT AS span,
               w / span::DOUBLE AS u,
               greatest(1, ceil(span / (w / bar_units())))::BIGINT AS bw),
  pts AS (SELECT lp.lane, lp.t0, lp.value FROM lane_points lp, p
          WHERE list_contains(ids, lp.lane) AND lp.t0 >= p.f - 86400 AND lp.t0 < p.t),
  modes AS (SELECT lane, count(*) AS n, count(*) <= item_max() AS as_items FROM pts GROUP BY lane),
  items AS (SELECT i.lane, i.t0, i.t1, i.value, i.label
            FROM lane_items i, p, modes m
            WHERE list_contains(ids, i.lane) AND i.lane = m.lane AND m.as_items AND i.t0 >= p.f - 86400 AND i.t0 < p.t),
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
    FROM items i JOIN sel l ON l.id = i.lane
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
    FROM bars b JOIN sel l ON l.id = b.lane
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
           || ' y1=' || axis_h() - 6 || ' y2=' || lanes_h(ids) || '></line>'
           || '<text x=' || printf('%.2f', (tk.ts - p.f) * p.u + 4) || ' y=' || axis_h() - 10 || '>'
           || tick_label(epoch_ms(tk.ts * 1000), tk.fmt) || '</text>' AS el
    FROM ticks tk, p)
  SELECT '<svg xmlns="http://www.w3.org/2000/svg" role=img aria-label="Timeline lanes" data-timeline-svg'
    || ' data-from=' || p.f || ' data-to=' || p.t || ' data-span=' || p.span
    || ' viewBox="' || printf('%.2f', (vstart - p.f) * p.u) || ' 0 ' || w || ' ' || lanes_h(ids) || '"'
    || ' preserveAspectRatio="xMinYMin slice">'
    || '<g class=bands>'
    || (SELECT string_agg('<rect class=band x=0 width=' || printf('%.2f', (p.t - p.f) * p.u) || ' y=' || ((l.ord - 1) * lane_h() + axis_h())
          || ' height=' || lane_h() || ' data-odd=' || (l.ord % 2) || '></rect>', '' ORDER BY l.ord) FROM sel l)
    || '</g><g class=grid>' || coalesce((SELECT string_agg(el, '') FROM grid), '') || '</g>'
    || '<g class=marks>' || coalesce((SELECT string_agg(el, '' ORDER BY ord) FROM drawn), '') || '</g></svg>'
  FROM p);

-- Lanes the pages show.
CREATE OR REPLACE MACRO lanes_svg(f, t, span, vstart, w) AS
  (lanes_svg_of(f, t, span, vstart, w, default_lanes()));

CREATE OR REPLACE MACRO doc_open(title) AS (
  '<!doctype html><html lang=en><head><meta charset=utf-8>'
  || '<meta name=viewport content="width=device-width,initial-scale=1">'
  || '<title>' || duckweb_escape(title) || '</title>'
  || '<link rel=stylesheet href="/_duckweb/design/css/style.css">'
  || '<link rel=stylesheet href="/_duckweb/timeline.css"></head><body>');

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
           || printf('%.3f', 100.0 * (axis_h() + (l.ord - 1) * lane_h() + lane_pad()) / lanes_h(default_lanes()))
           || '%">' || duckweb_escape(l.label) || '</span>', '' ORDER BY l.ord)
  FROM (SELECT *, row_number() OVER (ORDER BY ord) AS pos FROM lanes WHERE list_contains(default_lanes(), id)) l);

CREATE OR REPLACE MACRO timeline_page(vstart, span) AS (
  doc_open('timeline') || site_nav('/')
  || '<main id=main-content class=container tabindex=-1><h1>Timeline</h1>'
  || '<p>' || home_intro() || ' Drag the lanes to move through time; zoom with the links, the buttons, or ctrl + scroll.</p>'
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
  || '</main><script src="/_duckweb/timeline.js" defer></script></body></html>');

CREATE OR REPLACE MACRO sql_row_cap() AS 500;

-- Charts are drawn for this many rows; each one is a data URI in the response.
CREATE OR REPLACE MACRO sql_chart_cap() AS 24;

-- A result value that is a whole <svg> document, such as svg_chart returns, is
-- shown as a picture. It is only ever the source of an <img>, whose content the
-- browser does not run, so a query cannot use it to script the page.
CREATE OR REPLACE MACRO chart_img(v) AS (
  CASE WHEN regexp_matches(v, '^\s*<svg[\s>]') AND regexp_matches(v, '</svg>\s*$')
       THEN '<img data-chart alt="' || duckweb_escape(coalesce(nullif(
              replace(replace(replace(regexp_extract(v, '<title[^>]*>([^<]*)</title>', 1), '&amp;', '&'), '&lt;', '<'), '&gt;', '>'),
              ''), 'Chart')) || '" src="data:image/svg+xml;base64,' || to_base64(encode(v)) || '">'
       ELSE '' END);

-- The result row as a line of JSON, with each chart named rather than spelled
-- out, followed by the pictures it holds.
CREATE OR REPLACE MACRO result_line(j, n) AS (
  duckweb_escape(regexp_replace(j::VARCHAR, '"<svg(?:\\.|[^"\\])*"', '"[chart]"', 'g')) || chr(10)
  || CASE WHEN n <= sql_chart_cap()
          THEN coalesce((SELECT string_agg(chart_img(e.value->>'$'), '') FROM json_each(j) e), '') ELSE '' END);

CREATE OR REPLACE MACRO examples_html(q) AS (
  '<section data-examples aria-labelledby=sql-examples><h2 id=sql-examples>Example queries</h2>'
  || '<p>Choose one to load it into the box above and run it. A column holding what <code>svg_chart</code> returns is drawn as a chart, for the first '
  || sql_chart_cap() || ' rows.</p>'
  || (SELECT string_agg(g.html, '' ORDER BY g.gn) FROM (
        SELECT e.gn,
               '<div role=group aria-labelledby=sql-ex-' || e.gn || '><h3 id=sql-ex-' || e.gn || '>' || duckweb_escape(any_value(e.grp)) || '</h3><ul>'
               || string_agg('<li><form method=get action=/sql><input type=hidden name=q value="' || duckweb_escape(e.sql) || '">'
                             || '<button type=submit' || CASE WHEN e.sql = replace(coalesce(q, ''), chr(13), '') THEN ' aria-current=true' ELSE '' END || '>'
                             || duckweb_escape(e.title) || '</button> <small>' || duckweb_escape(e.descr) || '</small></form></li>', '' ORDER BY e.ord)
               || '</ul></div>' AS html
        FROM examples e GROUP BY e.gn) g)
  || '</section>');


-- The public instance's /sql is a shell the browser fills in: the server never runs the
-- visitor's SQL (is_server()), the page's worker does, over the exported files.
CREATE OR REPLACE MACRO is_server() AS (false);
CREATE OR REPLACE MACRO is_doc(headers) AS (is_server() OR duckweb_header_value(headers, 'X-Duckweb-Client') = '');
CREATE OR REPLACE MACRO sql_exec() AS (NOT hydrates() OR NOT is_server());

CREATE OR REPLACE MACRO sql_open(headers, title) AS (
  CASE WHEN hydrates() AND NOT is_doc(headers) THEN '<title>' || duckweb_escape(title) || '</title>'
       ELSE doc_open(title) || CASE WHEN hydrates() THEN '<div id=duckweb-root>' ELSE '' END END);
CREATE OR REPLACE MACRO sql_close(headers) AS (
  '</main>' || CASE WHEN NOT hydrates() THEN '</body></html>'
    WHEN is_doc(headers) THEN '</div><script>window.__duckweb=' || client_config() || ';</script>'
      || '<script type=module src="/_duckweb/client.js"></script></body></html>'
    ELSE '' END);

CREATE OR REPLACE MACRO sql_page(headers, q) AS (
  sql_open(headers, 'timeline SQL') || site_nav('/sql')
  || '<main id=main-content class=container tabindex=-1><h1>SQL</h1>'
  || '<p>' || sql_intro() || ' One SELECT per request, at most ' || sql_row_cap() || ' rows.</p>'
  || '<form method=get action=/sql><label>Query<textarea name=q rows=6 spellcheck=false>'
  || duckweb_escape(q) || '</textarea></label><button type=submit>Run</button></form>');


-- The routes both instances serve. An instance's render() unions these with
-- its own and ends with the 404 branch.
-- The scrolling homepage view needs /embed.svg, so only the instance that has it
-- (embed.sql, read after this file) turns it on.
CREATE OR REPLACE MACRO home_scroll(route) AS (false);

CREATE OR REPLACE MACRO route_home(method, route) AS TABLE (
            SELECT duckweb_head(200, 'text/html; charset=utf-8', duckweb_header('Cache-Control', 'public, max-age=300'))
              FROM duckweb_match(route, '/') WHERE method = 'GET' AND NOT home_scroll(route)
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
              WHERE method = 'GET' AND NOT home_scroll(route)
  UNION ALL SELECT duckweb_end() FROM duckweb_match(route, '/') WHERE method = 'GET' AND NOT home_scroll(route)
);

CREATE OR REPLACE MACRO route_lanes(method, route) AS TABLE (
            SELECT duckweb_head(200, 'image/svg+xml; charset=utf-8', duckweb_header('Cache-Control', 'public, max-age=300'))
              FROM duckweb_match(route, '/lanes.svg') WHERE method = 'GET'
  UNION ALL SELECT duckweb_chunk(lanes_svg(
                     num_param(route, 'from', 0, 0, 4102444800),
                     num_param(route, 'to', 1, 1, 4102444800),
                     num_param(route, 'span', 7776000, 3600, 631152000),
                     num_param(route, 'at', 0, 0, 4102444800),
                     num_param(route, 'w', 1200, 320, 4000)))
              FROM duckweb_match(route, '/lanes.svg') WHERE method = 'GET'
  UNION ALL SELECT duckweb_end() FROM duckweb_match(route, '/lanes.svg') WHERE method = 'GET'
);

-- query() is bound before duckweb_match prunes a branch, so on every other
-- route it still parses its argument. A q parameter belonging to another route
-- (/chat/search?q=...) must therefore not reach it; an empty statement is an
-- error too, hence the stand-in.
CREATE OR REPLACE MACRO sql_text(route) AS
  (CASE WHEN route = '/sql' OR starts_with(route, '/sql?')
        THEN coalesce(nullif(CASE WHEN sql_exec() THEN duckweb_query(route, 'q') END, ''), 'SELECT 1 WHERE false')
        ELSE 'SELECT 1 WHERE false' END);

CREATE OR REPLACE MACRO route_sql(method, route, headers) AS TABLE (
            SELECT duckweb_head(200, 'text/html; charset=utf-8', duckweb_header('Cache-Control', 'no-store'))
              FROM duckweb_match(route, '/sql') WHERE method = 'GET'
  UNION ALL SELECT duckweb_chunk(sql_page(headers, duckweb_query(route, 'q')))
              FROM duckweb_match(route, '/sql') WHERE method = 'GET'
  UNION ALL SELECT duckweb_chunk('<pre data-result>')
              FROM duckweb_match(route, '/sql') WHERE method = 'GET' AND duckweb_query(route, 'q') <> '' AND sql_exec()
  UNION ALL SELECT duckweb_chunk(result_line(t.j, t.n))
              FROM duckweb_match(route, '/sql'),
                   (SELECT to_json(r) AS j, row_number() OVER () AS n
                      FROM (SELECT * FROM query(sql_text(route)) LIMIT sql_row_cap()) r) t
              WHERE method = 'GET' AND duckweb_query(route, 'q') <> '' AND sql_exec()
  UNION ALL SELECT duckweb_chunk('</pre>')
              FROM duckweb_match(route, '/sql') WHERE method = 'GET' AND duckweb_query(route, 'q') <> '' AND sql_exec()
  UNION ALL SELECT duckweb_chunk(examples_html(duckweb_query(route, 'q')))
              FROM duckweb_match(route, '/sql') WHERE method = 'GET'
  UNION ALL SELECT duckweb_chunk(sql_close(headers))
              FROM duckweb_match(route, '/sql') WHERE method = 'GET'
  UNION ALL SELECT duckweb_end() FROM duckweb_match(route, '/sql') WHERE method = 'GET'
);

CREATE OR REPLACE MACRO route_not_found(method, route) AS TABLE (
            SELECT duckweb_head(404, 'text/plain; charset=utf-8', '') WHERE NOT EXISTS (SELECT 1 FROM known(method, route))
  UNION ALL SELECT duckweb_chunk('not found') WHERE NOT EXISTS (SELECT 1 FROM known(method, route))
  UNION ALL SELECT duckweb_end() WHERE NOT EXISTS (SELECT 1 FROM known(method, route))
);
