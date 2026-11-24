-- Colours are spelled out per theme because some rasterisers ignore custom properties.

CREATE OR REPLACE MACRO embed_lanes() AS ['hr', 'stress', 'sleep', 'steps', 'music', 'family', 'read'];

CREATE OR REPLACE MACRO embed_time(v) AS
  (CASE WHEN lower(v) = 'now' THEN (epoch(now())::BIGINT // 60) * 60
        ELSE epoch(TRY_CAST(replace(v, ' ', '+') AS TIMESTAMPTZ))::BIGINT END);

CREATE OR REPLACE MACRO embed_duration(v) AS
  ((TRY_CAST(nullif(regexp_extract(v, '^(\d+(?:\.\d+)?)[hdwHDW]$', 1), '') AS DOUBLE)
    * CASE lower(right(v, 1)) WHEN 'h' THEN 3600 WHEN 'd' THEN 86400 ELSE 604800 END)::BIGINT);

CREATE OR REPLACE MACRO embed_size(v, dflt) AS
  (least(2400, greatest(200, round(coalesce(
     TRY_CAST(nullif(regexp_extract(v, '^(\d+(?:\.\d+)?)(?:px)?$', 1), '') AS DOUBLE), dflt))::BIGINT)));

-- bad is true when a parameter was given and did not parse, or the range is
-- shorter than an hour or longer than five years.
CREATE OR REPLACE MACRO embed_params(route) AS (
  WITH q AS (SELECT nullif(duckweb_query(route, 'start'), '') AS s, nullif(duckweb_query(route, 'end'), '') AS e,
                    nullif(duckweb_query(route, 'duration'), '') AS d, nullif(duckweb_query(route, 'width'), '') AS w,
                    nullif(duckweb_query(route, 'maxWidth'), '') AS mw, nullif(duckweb_query(route, 'height'), '') AS h),
  r AS (SELECT q.*, embed_time(q.s) AS ts, embed_time(q.e) AS te, embed_duration(q.d) AS td,
               coalesce(embed_duration(q.d), 604800) AS dur, (epoch(now())::BIGINT // 60) * 60 AS now_ FROM q),
  f AS (SELECT r.*,
          CASE WHEN ts IS NOT NULL AND te IS NOT NULL THEN ts
               WHEN te IS NOT NULL THEN te - dur WHEN ts IS NOT NULL THEN ts ELSE now_ - dur END AS f,
          CASE WHEN ts IS NOT NULL AND te IS NOT NULL THEN te
               WHEN te IS NOT NULL THEN te WHEN ts IS NOT NULL THEN ts + dur ELSE now_ END AS t FROM r)
  SELECT {
    'f': f, 't': t,
    'w': least(embed_size(mw, 1e9), embed_size(w, 1200)), 'h': embed_size(h, 520),
    'bad': (s IS NOT NULL AND ts IS NULL) OR (e IS NOT NULL AND te IS NULL) OR (d IS NOT NULL AND td IS NULL)
           OR (w IS NOT NULL AND TRY_CAST(nullif(regexp_extract(w, '^(\d+(?:\.\d+)?)(?:px)?$', 1), '') AS DOUBLE) IS NULL)
           OR (h IS NOT NULL AND TRY_CAST(nullif(regexp_extract(h, '^(\d+(?:\.\d+)?)(?:px)?$', 1), '') AS DOUBLE) IS NULL)
           OR (mw IS NOT NULL AND TRY_CAST(nullif(regexp_extract(mw, '^(\d+(?:\.\d+)?)(?:px)?$', 1), '') AS DOUBLE) IS NULL)
           OR t - f < 3600 OR t - f > 157852800 } FROM f);

CREATE OR REPLACE MACRO embed_style() AS
  '<style>text{font-family:ui-sans-serif,system-ui,-apple-system,sans-serif;stroke:none;font-size:12px}'
  || '.band[data-odd="0"]{fill:#f3f5f9}.band[data-odd="1"]{fill:#fff}'
  || '.grid line{stroke:#d3dae5}.grid text,.name{fill:#5b6b7c}'
  || '[data-lane=hr]{fill:#e11d48}[data-lane=stress]{fill:#c2410c}[data-lane=sleep]{fill:#4338ca}'
  || '[data-lane=steps]{fill:#075985}[data-lane=music]{fill:#6d28d9}[data-lane=family]{fill:#15803d}[data-lane=read]{fill:#0f766e}'
  || '.marks rect{fill-opacity:.85}'
  || '@media (prefers-color-scheme:dark){.band[data-odd="0"]{fill:#111827}.band[data-odd="1"]{fill:#0b111c}'
  || '.grid line{stroke:#2b3549}.grid text,.name{fill:#8b98ab}'
  || '[data-lane=hr]{fill:#fb7185}[data-lane=stress]{fill:#fb923c}[data-lane=sleep]{fill:#818cf8}'
  || '[data-lane=steps]{fill:#38bdf8}[data-lane=music]{fill:#c084fc}[data-lane=family]{fill:#4ade80}[data-lane=read]{fill:#2dd4bf}}</style>';

-- lanes_svg_of writes HTML attributes (unquoted values, a bare data-timeline-svg),
-- which the pages inline but an image/svg+xml document may not: a browser refuses
-- to draw it as an <img>. Quote them here so only the embed pays for it. A value
-- that is already quoted starts with a quote and is left alone.
CREATE OR REPLACE MACRO xml_attrs(svg) AS
  (regexp_replace(replace(svg, ' data-timeline-svg ', ' data-timeline-svg="" '),
                  '(\s[\w:-]+)=([^\s"''>]+)', '\1="\2"', 'g'));

-- Taller or shorter than the natural height stretches the lanes' bands and marks only,
-- so the text stays undistorted.
CREATE OR REPLACE MACRO embed_svg(f, t, w, h) AS (
  WITH nat AS (SELECT lanes_h(embed_lanes()) AS lh),
       k AS (SELECT (h - axis_h()) / (lh - axis_h())::DOUBLE AS k, lh FROM nat),
       raw AS (SELECT lanes_svg_of(f, t, t - f, f, w, embed_lanes()) AS svg)
  SELECT xml_attrs(replace(replace(replace(replace(replace(replace(raw.svg,
      '<svg xmlns="http://www.w3.org/2000/svg" ',
      '<svg xmlns="http://www.w3.org/2000/svg" width=' || w || ' height=' || h || ' '),
    ' 0 ' || w || ' ' || k.lh || '"', ' 0 ' || w || ' ' || h || '"'),
    'preserveAspectRatio="xMinYMin slice">', 'preserveAspectRatio="xMinYMin slice">' || embed_style()),
    '<g class=bands>', '<g class=bands transform="translate(0 ' || axis_h() || ') scale(1 ' || k.k || ') translate(0 -' || axis_h() || ')">'),
    '<g class=marks>', '<g class=marks transform="translate(0 ' || axis_h() || ') scale(1 ' || k.k || ') translate(0 -' || axis_h() || ')">'),
    '</svg>',
    (SELECT string_agg('<text class=name x=6 y=' || round(axis_h() + (l.ord - 1) * lane_h() * k.k + 16, 2) || '>' || duckweb_escape(l.label) || '</text>', '' ORDER BY l.ord)
       FROM (SELECT id, label, row_number() OVER (ORDER BY list_position(embed_lanes(), id)) AS ord FROM lanes WHERE list_contains(embed_lanes(), id)) l)
    || '</svg>'))
  FROM raw, k);

CREATE OR REPLACE MACRO route_embed(method, route) AS TABLE (
            SELECT duckweb_head(400, 'text/plain; charset=utf-8', '')
              FROM duckweb_match(route, '/embed.svg') WHERE method = 'GET' AND embed_params(route)['bad']
  UNION ALL SELECT duckweb_chunk('bad parameters: start and end are ISO 8601 or now, duration is Nh, Nd or Nw (1h to 5 years), width and height are 200 to 2400' || chr(10))
              FROM duckweb_match(route, '/embed.svg') WHERE method = 'GET' AND embed_params(route)['bad']
  UNION ALL SELECT duckweb_head(200, 'image/svg+xml; charset=utf-8',
                duckweb_header('Cache-Control', 'public, max-age=60, s-maxage=300')
                || duckweb_header('Access-Control-Allow-Origin', '*')
                || duckweb_header('X-Content-Type-Options', 'nosniff')
                || duckweb_header('Content-Security-Policy', 'default-src ''none''; style-src ''unsafe-inline'''))
              FROM duckweb_match(route, '/embed.svg') WHERE method = 'GET' AND NOT embed_params(route)['bad']
  UNION ALL SELECT duckweb_chunk(embed_svg(p['f'], p['t'], p['w'], p['h']))
              FROM duckweb_match(route, '/embed.svg'), (SELECT embed_params(route) AS p) x
              WHERE method = 'GET' AND NOT p['bad']
  UNION ALL SELECT duckweb_end() FROM duckweb_match(route, '/embed.svg') WHERE method = 'GET'
);

-- The private homepage, also at `/?view=scroll`: an endless-feeling strip of /embed.svg tiles, newest at the
-- right, with no script. One <svg> holds a <foreignObject><img loading=lazy> per tile, so the
-- browser fetches a tile only as it nears the viewport (an SVG <image> has no loading attribute
-- and is fetched at once). Older time is a lazy <iframe> at the left that is this same page,
-- one `more` shorter: it loads when scrolled to, and brings its own tiles and its own older
-- frame. Zoom links set `step`, the time one tile spans. Params: end (default now), step (Nh/Nd/Nw, default 1w), count tiles per page,
-- more older pages, w and h per tile.
-- This is the private instance's homepage. The draggable lanes page stays at /?view=lanes, and
-- at the span and at links it has always had.
CREATE OR REPLACE MACRO home_scroll(route) AS (
  coalesce(duckweb_query(route, 'view'), '') = 'scroll'
  OR (coalesce(duckweb_query(route, 'view'), '') <> 'lanes'
      AND coalesce(duckweb_query(route, 'span'), '') = '' AND coalesce(duckweb_query(route, 'at'), '') = ''));

CREATE OR REPLACE MACRO scroll_iso(e) AS (strftime(make_timestamp(e::BIGINT * 1000000), '%Y-%m-%dT%H:%M:%SZ'));

CREATE OR REPLACE MACRO scroll_params(route) AS (
  SELECT {
    'e': coalesce(embed_time(nullif(duckweb_query(route, 'end'), '')), (epoch(now())::BIGINT // 3600) * 3600),
    'sraw': CASE WHEN embed_duration(nullif(duckweb_query(route, 'step'), '')) BETWEEN 3600 AND 157680000
                 THEN duckweb_query(route, 'step') ELSE '1w' END,
    'step': least(157680000, greatest(3600, coalesce(embed_duration(nullif(duckweb_query(route, 'step'), '')), 604800))),
    'count': num_param(route, 'count', 26, 1, 104), 'more': num_param(route, 'more', 8, 0, 20), 'm0': num_param(route, 'm0', num_param(route, 'more', 8, 0, 20), 0, 20),
    'w': embed_size(nullif(duckweb_query(route, 'w'), ''), 400), 'h': embed_size(nullif(duckweb_query(route, 'h'), ''), 520),
    'given': nullif(duckweb_query(route, 'end'), '') IS NOT NULL, 'frame': duckweb_query(route, 'frame') = '1' });

-- The innermost page (more = 0) starts with an "Earlier" link instead of a frame. It opens the
-- same view ending where the strip does, with all the pages again, so the strip can go on.
-- off is where this page's own tiles start: after its older frame, or after the link.
CREATE OR REPLACE MACRO scroll_cap() AS 160;

CREATE OR REPLACE MACRO scroll_total(more, pw) AS
  ((more + 1) * pw + scroll_cap());

CREATE OR REPLACE MACRO scroll_strip(p) AS (
  WITH g AS (SELECT p['e'] AS e, p['step'] AS step, p['count'] AS n, p['more'] AS more, p['m0'] AS m0,
                    p['w'] AS tw, p['h'] AS h, p['sraw'] AS sraw),
       dims AS (SELECT g.*, n * tw AS pw FROM g),
       lay AS (SELECT dims.*, scroll_total(more, pw) AS total,
                      CASE WHEN more = 0 THEN scroll_cap() ELSE scroll_total(more - 1, pw) END AS off FROM dims)
  SELECT '<svg class=scroll-strip role=img aria-label="Timeline, older to the left" width=' || total || ' height=' || h
      || ' viewBox="0 0 ' || total || ' ' || h || '">'
      || CASE WHEN more > 0
           THEN '<foreignObject x=0 y=0 width=' || off || ' height=' || h || '><iframe loading=lazy title="Earlier" width='
                || off || ' height=' || h || ' src="/?view=scroll&amp;frame=1&amp;end=' || scroll_iso(e - n * step)
                || '&amp;step=' || sraw || '&amp;count=' || n || '&amp;more=' || more - 1 || '&amp;m0=' || m0
                || '&amp;w=' || tw || '&amp;h=' || h || '"></iframe></foreignObject>'
           ELSE '<a target=_top href="/?view=scroll&amp;end=' || scroll_iso(e - n * step) || '&amp;step=' || sraw
                || '&amp;count=' || n || '&amp;more=' || m0 || '&amp;w=' || tw || '&amp;h=' || h
                || '"><rect class=scroll-earlier x=0 y=0 width=' || scroll_cap() || ' height=' || h
                || ' fill="#e4e9f1"/><text x=' || scroll_cap() // 2 || ' y=' || h // 2
                || ' text-anchor=middle fill="#1f2937" font-size=16>← Earlier</text></a>' END
      || (SELECT string_agg('<foreignObject x=' || (off + i * tw) || ' y=0 width=' || tw || ' height=' || h
            || '><img loading=lazy decoding=async alt="' || scroll_iso(e - (n - i) * step) || '" width=' || tw || ' height=' || h
            || ' src="/embed.svg?start=' || scroll_iso(e - (n - i) * step) || '&amp;end=' || scroll_iso(e - (n - i - 1) * step)
            || '&amp;width=' || tw || '&amp;height=' || h || '"></foreignObject>', '' ORDER BY i)
          FROM range(n) r(i))
      || '</svg>'
  FROM lay);

CREATE OR REPLACE MACRO scroll_page(p) AS (
  CASE WHEN p['frame']
    THEN '<!doctype html><html lang=en><head><meta charset=utf-8><title>Earlier</title>'
         || '<style>html,body{margin:0;overflow:hidden}svg,iframe{display:block;border:0}svg{outline:1px dashed #8b98ab;outline-offset:-1px}</style></head><body>'
         || scroll_strip(p) || '</body></html>'
    ELSE doc_open('timeline') || site_nav('/')
         || '<main id=main-content class=container tabindex=-1><h1>Timeline</h1>'
         || '<nav aria-label="Zoom" data-zoom-nav><ul>'
         || (SELECT string_agg('<li><a href="/?view=scroll&amp;step=' || (z.secs // 3600) || 'h'
               || CASE WHEN p['given'] THEN '&amp;end=' || scroll_iso(p['e']) ELSE '' END || '"'
               || CASE WHEN z.secs = p['step'] THEN ' aria-current=true' ELSE '' END || '>' || z.label || ' a tile</a></li>', '' ORDER BY z.ord)
             FROM zooms z)
         || '</ul></nav>'
         || '<style>.scroll-track{overflow-x:auto;direction:rtl;border:1px solid #d3dae5}.scroll-strip{display:block;direction:ltr;max-width:none}'
         || '.scroll-strip iframe{border:0}</style>'
         || '<div class=scroll-track tabindex=0 role=region aria-label="Timeline strip">' || scroll_strip(p) || '</div>'
         || '</main></body></html>' END);

CREATE OR REPLACE MACRO route_home_scroll(method, route) AS TABLE (
            SELECT duckweb_head(200, 'text/html; charset=utf-8', duckweb_header('Cache-Control', 'public, max-age=300'))
              FROM duckweb_match(route, '/') WHERE method = 'GET' AND home_scroll(route)
  UNION ALL SELECT duckweb_chunk(scroll_page(scroll_params(route)))
              FROM duckweb_match(route, '/') WHERE method = 'GET' AND home_scroll(route)
  UNION ALL SELECT duckweb_end() FROM duckweb_match(route, '/') WHERE method = 'GET' AND home_scroll(route)
);
