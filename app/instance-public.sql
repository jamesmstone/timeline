-- What makes this the public instance: its copy, its navigation, and the list of
-- routes it answers. Loaded before core.sql, which reads these macros.

CREATE OR REPLACE MACRO site_nav(here) AS (
  '<a href="#main-content">Skip to main content</a><header data-site><nav aria-label=Main>'
  || '<a href="/" target=_top>timeline</a><ul>'
  || '<li><a href="/" target=_top' || CASE WHEN here = '/' THEN ' aria-current=page' ELSE '' END || '>Lanes</a></li>'
  || '<li><a href="/sql"' || CASE WHEN here = '/sql' THEN ' aria-current=page' ELSE '' END || '>SQL</a></li>'
  || '</ul></nav></header>');

-- /sql boots the browser worker; the other pages stay plain server documents, which is why their
-- links leave the client (target=_top).
CREATE OR REPLACE MACRO hydrates() AS (true);

CREATE OR REPLACE MACRO home_intro() AS
  'Music, reading, parkrun, chess and the daily shape of sleep, heart rate and steps.';

CREATE OR REPLACE MACRO home_sources() AS
  'Sources: Last.fm scrobbles, the reading list, parkrun results, chess games and daily Garmin '
  || 'aggregates (sleep, heart-rate and step rollups; no location data).';

CREATE OR REPLACE MACRO sql_intro() AS
  'Read-only access to the public tables, run in your browser as DuckDB SQL: <code>lanes</code>, <code>lane_points</code>, '
  || '<code>lastfm.*</code>, <code>reading.*</code>, <code>parkrun.*</code>, <code>chess.*</code> and the sanitised '
  || '<code>garmin.sleep</code> and <code>garmin.daily</code>.';

CREATE OR REPLACE MACRO known(method, route) AS TABLE (
            SELECT 1 FROM duckweb_match(route, '/') WHERE method = 'GET'
  UNION ALL SELECT 1 FROM duckweb_match(route, '/lanes.svg') WHERE method = 'GET'
  UNION ALL SELECT 1 FROM duckweb_match(route, '/sql') WHERE method = 'GET'
);
