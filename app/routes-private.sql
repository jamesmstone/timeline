-- The private instance's route table: the shared routes plus the chat page and
-- its explicit search.

-- Matches contain the query as a plain substring, so % and _ are not patterns.
CREATE OR REPLACE MACRO chat_min_query() AS 3;
CREATE OR REPLACE MACRO chat_search_cap() AS 50;

CREATE OR REPLACE MACRO chat_page(q) AS (
  doc_open('timeline chat') || site_nav('/chat')
  || '<main id=main-content class=container tabindex=-1><h1>Chat</h1>'
  || '<p>Message counts by network. Message text is not shown here; search it explicitly below.</p>'
  || '<table><thead><tr><th>Network</th><th>Messages</th><th>First</th><th>Last</th></tr></thead><tbody>'
  || coalesce((SELECT string_agg('<tr><td>' || duckweb_escape(network) || '</td><td>' || format('{:,}', n)
        || '</td><td>' || first_day || '</td><td>' || last_day || '</td></tr>', '' ORDER BY n DESC)
      FROM (SELECT network, sum(messages) AS n, min("day") AS first_day, max("day") AS last_day
              FROM chat_daily GROUP BY network)), '')
  || '</tbody></table>'
  || '<h2>Search messages</h2>'
  || '<form method=get action=/chat/search><label>Text<input name=q type=search minlength=' || chat_min_query()
  || ' required value="' || duckweb_escape(q) || '"></label><button type=submit>Search</button></form>'
  || '</main></body></html>');

CREATE OR REPLACE MACRO chat_search_page(q) AS (
  doc_open('timeline chat search') || site_nav('/chat')
  || '<main id=main-content class=container tabindex=-1><h1>Chat search</h1>'
  || '<form method=get action=/chat/search><label>Text<input name=q type=search minlength=' || chat_min_query()
  || ' required value="' || duckweb_escape(q) || '"></label><button type=submit>Search</button></form>'
  || CASE WHEN length(q) < chat_min_query()
       THEN '<p>Enter at least ' || chat_min_query() || ' characters.</p>'
       ELSE '<p>Newest ' || chat_search_cap() || ' matches, newest first.</p>' END);

CREATE OR REPLACE MACRO route_chat(method, route) AS TABLE (
            SELECT duckweb_head(200, 'text/html; charset=utf-8', duckweb_header('Cache-Control', 'no-store'))
              FROM duckweb_match(route, '/chat') WHERE method = 'GET'
  UNION ALL SELECT duckweb_chunk(chat_page(coalesce(duckweb_query(route, 'q'), '')))
              FROM duckweb_match(route, '/chat') WHERE method = 'GET'
  UNION ALL SELECT duckweb_end() FROM duckweb_match(route, '/chat') WHERE method = 'GET'

  UNION ALL SELECT duckweb_head(200, 'text/html; charset=utf-8', duckweb_header('Cache-Control', 'no-store'))
              FROM duckweb_match(route, '/chat/search') WHERE method = 'GET'
  UNION ALL SELECT duckweb_chunk(chat_search_page(coalesce(duckweb_query(route, 'q'), '')))
              FROM duckweb_match(route, '/chat/search') WHERE method = 'GET'
  UNION ALL SELECT duckweb_chunk('<article data-match><p><small>' || duckweb_escape(m.sent_at) || ' · '
                || duckweb_escape(coalesce(m.network, 'local')) || ' · ' || duckweb_escape(coalesce(m.sender_name, m.sender, ''))
                || '</small></p><p>' || duckweb_escape(coalesce(m.body, '')) || '</p></article>')
              FROM duckweb_match(route, '/chat/search'),
                   (SELECT * FROM chat_messages
                     WHERE contains(lower(body), lower(coalesce(duckweb_query(route, 'q'), '')))
                       AND length(coalesce(duckweb_query(route, 'q'), '')) >= chat_min_query()
                     ORDER BY ts DESC LIMIT chat_search_cap()) m
              WHERE method = 'GET'
  UNION ALL SELECT duckweb_chunk('</main></body></html>')
              FROM duckweb_match(route, '/chat/search') WHERE method = 'GET'
  UNION ALL SELECT duckweb_end() FROM duckweb_match(route, '/chat/search') WHERE method = 'GET'
);

CREATE OR REPLACE MACRO render(method, route, headers, body) AS TABLE (
            SELECT * FROM route_home(method, route)
  UNION ALL SELECT * FROM route_home_scroll(method, route)
  UNION ALL SELECT * FROM route_lanes(method, route)
  UNION ALL SELECT * FROM route_sql(method, route, headers)
  UNION ALL SELECT * FROM route_chat(method, route)
  UNION ALL SELECT * FROM route_embed(method, route)
  UNION ALL SELECT * FROM route_not_found(method, route)
);
