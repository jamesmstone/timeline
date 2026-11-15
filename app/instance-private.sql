-- What makes this the private instance: its copy, its navigation, and the list
-- of routes it answers. Loaded before core.sql, which reads these macros.
-- Chat bodies are served by /chat/search and /sql alone; the lanes and /chat
-- carry counts.

CREATE OR REPLACE MACRO site_nav(here) AS (
  '<a href="#main-content">Skip to main content</a><header data-site><nav aria-label=Main>'
  || '<a href="/">timeline (private)</a><ul>'
  || '<li><a href="/"' || CASE WHEN here = '/' THEN ' aria-current=page' ELSE '' END || '>Lanes</a></li>'
  || '<li><a href="/chat"' || CASE WHEN here = '/chat' THEN ' aria-current=page' ELSE '' END || '>Chat</a></li>'
  || '<li><a href="/sql"' || CASE WHEN here = '/sql' THEN ' aria-current=page' ELSE '' END || '>SQL</a></li>'
  || '</ul></nav></header>');

CREATE OR REPLACE MACRO home_intro() AS
  'Music, reading, parkrun, chess, sleep, heart rate and steps, with message volume and air quality.';

CREATE OR REPLACE MACRO home_sources() AS
  'Sources: the public ones plus Garmin rollups, chat message counts by network, and the purifier''s '
  || 'PM2.5. Full Garmin, chat bodies and the archive are reachable through the SQL box only.';

CREATE OR REPLACE MACRO sql_intro() AS
  'Read-only access to every source, as DuckDB SQL: the public tables (<code>lastfm.*</code>, <code>reading.*</code>, '
  || '<code>parkrun.*</code>, <code>chess.*</code>), the Garmin rollups <code>garmin.*</code> and the full snapshots '
  || '<code>garmin_full.*</code>, <code>garmin_summary.*</code>, <code>garmin_activities.*</code> and '
  || '<code>garmin_monitoring.*</code>, the chat snapshot <code>chat.*</code> with <code>chat_messages</code> (bodies) and <code>archive.*</code>, '
  || 'and the purifier snapshot <code>purifier.*</code>.';

CREATE OR REPLACE MACRO known(method, route) AS TABLE (
            SELECT 1 FROM duckweb_match(route, '/') WHERE method = 'GET'
  UNION ALL SELECT 1 FROM duckweb_match(route, '/lanes.svg') WHERE method = 'GET'
  UNION ALL SELECT 1 FROM duckweb_match(route, '/sql') WHERE method = 'GET'
  UNION ALL SELECT 1 FROM duckweb_match(route, '/chat') WHERE method = 'GET'
  UNION ALL SELECT 1 FROM duckweb_match(route, '/chat/search') WHERE method = 'GET'
);
