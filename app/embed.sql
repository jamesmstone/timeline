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
