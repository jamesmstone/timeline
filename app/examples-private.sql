-- Examples that only make sense where the private sources are attached: chat
-- volume by network and the purifier's air quality. Counts and averages only;
-- no message body is read. Loaded after examples-public.sql.

INSERT INTO examples SELECT * FROM (VALUES
  (6, 'Chat and air', 1, 'Messages per network',
   'Message counts by network, as a chart.',
   $$SELECT svg_chart(
  list({'network': network, 'messages': n} ORDER BY n DESC),
  {'type': 'bar', 'title': 'Messages by network', 'aspect_ratio': 2.4}
) AS chart
FROM (SELECT network, sum(messages)::INTEGER AS n FROM chat_daily GROUP BY network)$$),
  (6, 'Chat and air', 2, 'Message volume by month',
   'Messages per month, stacked by network.',
   $$SELECT svg_chart(
  list(m ORDER BY m.month),
  {'type': 'bar', 'title': 'Messages per month', 'aspect_ratio': 3, 'series': [
     {'key': 'whatsapp', 'stack_id': 'a'}, {'key': 'signal', 'stack_id': 'a'}, {'key': 'telegram', 'stack_id': 'a'},
     {'key': 'sms', 'stack_id': 'a'}, {'key': 'messenger', 'stack_id': 'a'}, {'key': 'slack', 'stack_id': 'a'},
     {'key': 'local', 'stack_id': 'a'}]}
) AS chart
FROM (
  SELECT left("day", 7) AS month,
         coalesce(sum(messages) FILTER (network = 'whatsapp'), 0)::INTEGER AS whatsapp,
         coalesce(sum(messages) FILTER (network = 'signal'), 0)::INTEGER AS signal,
         coalesce(sum(messages) FILTER (network = 'telegram'), 0)::INTEGER AS telegram,
         coalesce(sum(messages) FILTER (network = 'sms'), 0)::INTEGER AS sms,
         coalesce(sum(messages) FILTER (network = 'messenger'), 0)::INTEGER AS messenger,
         coalesce(sum(messages) FILTER (network = 'slack'), 0)::INTEGER AS slack,
         coalesce(sum(messages) FILTER (network = 'local'), 0)::INTEGER AS "local"
  FROM chat_daily
  GROUP BY 1
) m$$),
  (6, 'Chat and air', 3, 'Air quality by day',
   'The purifier''s average PM2.5 for each of the last 60 days it recorded.',
   $$SELECT svg_chart(
  list({'day': d, 'PM2.5 (µg/m³)': pm25} ORDER BY d),
  {'type': 'line', 'title': 'Average PM2.5 per day', 'aspect_ratio': 3}
) AS chart
FROM (
  SELECT strftime(to_timestamp(t0), '%Y-%m-%d') AS d, round(avg(value), 1) AS pm25
  FROM air_points
  GROUP BY 1
  ORDER BY d DESC
  LIMIT 60
)$$),
  (6, 'Chat and air', 4, 'Air quality by hour of day',
   'Average PM2.5 for each hour of the day, UTC.',
   $$SELECT svg_chart(
  list({'hour': printf('%02d', h), 'PM2.5 (µg/m³)': pm25} ORDER BY h),
  {'type': 'bar', 'title': 'Average PM2.5 by hour of day (UTC)', 'aspect_ratio': 3}
) AS chart
FROM (
  SELECT hour(to_timestamp(t0)) AS h, round(avg(value), 1) AS pm25
  FROM air_points
  GROUP BY 1
)$$)
) t(gn, grp, ord, title, descr, sql);
