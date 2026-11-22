-- The queries the SQL page offers as buttons. Each is a plain SELECT over what
-- the public instance already exposes. A column holding what svg_chart returns
-- is drawn as a chart by the page; `aspect_ratio` keeps them short enough to
-- stack. Times from Last.fm are UTC, as stored.
-- Columns: group number, group name, order within the group, button text,
-- one line under the button, the query.

CREATE OR REPLACE TABLE examples AS SELECT * FROM (VALUES
  (1, 'Music', 1, 'Top artists',
   'The artists played most, with how many tracks and the first and last play.',
   $$SELECT ar.name AS artist, count(*) AS plays, count(DISTINCT t.id) AS tracks,
       strftime(to_timestamp(min(l.date_uts)::BIGINT), '%Y-%m-%d') AS first_play,
       strftime(to_timestamp(max(l.date_uts)::BIGINT), '%Y-%m-%d') AS last_play
FROM lastfm.listens l
JOIN lastfm.tracks t ON t.id = l.tracks_id
JOIN lastfm.albums al ON al.id = t.albums_id
JOIN lastfm.artists ar ON ar.id = al.artists_id
GROUP BY ar.name
ORDER BY plays DESC
LIMIT 25$$),
  (1, 'Music', 2, 'Plays per month',
   'A bar chart of scrobbles by calendar month.',
   $$SELECT svg_chart(
  list({'month': m, 'plays': plays} ORDER BY m),
  {'type': 'bar', 'title': 'Scrobbles per month', 'aspect_ratio': 3}
) AS chart
FROM (
  SELECT strftime(to_timestamp(date_uts::BIGINT), '%Y-%m') AS m, count(*)::INTEGER AS plays
  FROM lastfm.listens
  GROUP BY 1
)$$),
  (1, 'Music', 3, 'Time of day',
   'Plays by hour of the day, UTC.',
   $$SELECT svg_chart(
  list({'hour': printf('%02d', h), 'plays': plays} ORDER BY h),
  {'type': 'bar', 'title': 'Plays by hour of day (UTC)', 'aspect_ratio': 3}
) AS chart
FROM (
  SELECT hour(to_timestamp(date_uts::BIGINT)) AS h, count(*)::INTEGER AS plays
  FROM lastfm.listens
  GROUP BY 1
)$$),
  (1, 'Music', 4, 'Top artists, as a chart',
   'The ten artists played most.',
   $$SELECT svg_chart(
  list({'artist': artist, 'plays': plays} ORDER BY plays DESC),
  {'type': 'bar', 'title': 'Plays by artist', 'aspect_ratio': 2.4}
) AS chart
FROM (
  SELECT ar.name AS artist, count(*)::INTEGER AS plays
  FROM lastfm.listens l
  JOIN lastfm.tracks t ON t.id = l.tracks_id
  JOIN lastfm.albums al ON al.id = t.albums_id
  JOIN lastfm.artists ar ON ar.id = al.artists_id
  GROUP BY ar.name
  ORDER BY plays DESC
  LIMIT 10
)$$),
  (2, 'Reading', 1, 'Where the reading comes from',
   'Domains in the reading list, with how many articles and the latest.',
   $$SELECT domain, count(*) AS articles, max(left("date", 10)) AS latest
FROM reading."read"
WHERE domain IS NOT NULL
GROUP BY domain
ORDER BY articles DESC
LIMIT 25$$),
  (2, 'Reading', 2, 'Articles per month',
   'A bar chart of reading-list entries by month.',
   $$SELECT svg_chart(
  list({'month': m, 'articles': n} ORDER BY m),
  {'type': 'bar', 'title': 'Articles read per month', 'aspect_ratio': 3}
) AS chart
FROM (
  SELECT left("date", 7) AS m, count(*)::INTEGER AS n
  FROM reading."read"
  WHERE "date" IS NOT NULL
  GROUP BY 1
)$$),
  (2, 'Reading', 3, 'Busiest sites, as a chart',
   'The ten domains read most.',
   $$SELECT svg_chart(
  list({'domain': domain, 'articles': n} ORDER BY n DESC),
  {'type': 'bar', 'title': 'Articles by domain', 'aspect_ratio': 2.4}
) AS chart
FROM (
  SELECT domain, count(*)::INTEGER AS n
  FROM reading."read"
  WHERE domain IS NOT NULL
  GROUP BY domain
  ORDER BY n DESC
  LIMIT 10
)$$),
  (3, 'Parkrun', 1, 'Every run',
   'Event, date, position, time and age grade, newest first.',
   $$SELECT Event AS event, RunDate AS run_date, RunNumber AS run_number, Pos AS position, "Time" AS finish_time, AgeGrade AS age_grade
FROM parkrun.runs
ORDER BY RunDate DESC
LIMIT 100$$),
  (3, 'Parkrun', 2, 'Finish times',
   'A line chart of finish time in minutes, run by run.',
   $$SELECT svg_chart(
  list({'date': RunDate, 'minutes': minutes} ORDER BY RunDate),
  {'type': 'line', 'title': 'Parkrun finish time (minutes)', 'aspect_ratio': 3}
) AS chart
FROM (
  SELECT RunDate, round(epoch(TRY_CAST("Time" AS TIME)) / 60.0, 2) AS minutes
  FROM parkrun.runs
  WHERE TRY_CAST("Time" AS TIME) IS NOT NULL
)$$),
  (3, 'Parkrun', 3, 'Age grade over time',
   'The age-graded percentage for each run.',
   $$SELECT svg_chart(
  list({'date': RunDate, 'age grade': AgeGrade} ORDER BY RunDate),
  {'type': 'line', 'title': 'Parkrun age grade (%)', 'aspect_ratio': 3}
) AS chart
FROM parkrun.runs
WHERE AgeGrade IS NOT NULL$$),
  (3, 'Parkrun', 4, 'Runs per year',
   'How many parkruns in each year, stacked by whether it was a personal best.',
   $$SELECT svg_chart(
  list({'year': y, 'personal best': pb, 'other': n - pb} ORDER BY y),
  {'type': 'bar', 'title': 'Parkruns per year', 'aspect_ratio': 3,
   'series': [{'key': 'personal best', 'stack_id': 'a'}, {'key': 'other', 'stack_id': 'a'}]}
) AS chart
FROM (
  SELECT left(RunDate, 4) AS y, count(*)::INTEGER AS n, count(*) FILTER (PB = 1)::INTEGER AS pb
  FROM parkrun.runs
  GROUP BY 1
)$$),
  (4, 'Chess', 1, 'Games per month',
   'A bar chart of games by month.',
   $$SELECT svg_chart(
  list({'month': m, 'games': n} ORDER BY m),
  {'type': 'bar', 'title': 'Chess games per month', 'aspect_ratio': 3}
) AS chart
FROM (
  SELECT replace(left("date", 7), '.', '-') AS m, count(*)::INTEGER AS n
  FROM chess.games
  WHERE "date" IS NOT NULL
  GROUP BY 1
)$$),
  (4, 'Chess', 2, 'Results',
   'Wins for white, wins for black and draws, as a chart.',
   $$SELECT svg_chart(
  list({'result': CASE result WHEN '1-0' THEN 'white won' WHEN '0-1' THEN 'black won' ELSE 'draw' END, 'games': n} ORDER BY n DESC),
  {'type': 'bar', 'title': 'Chess results', 'aspect_ratio': 2.4}
) AS chart
FROM (
  SELECT result, count(*)::INTEGER AS n
  FROM chess.games
  WHERE result IN ('1-0', '0-1', '1/2-1/2')
  GROUP BY result
)$$),
  (4, 'Chess', 3, 'Openings and time controls',
   'The most common ECO codes, with the time control each was most often played at.',
   $$SELECT eco, count(*) AS games, mode(time_control) AS usual_time_control
FROM chess.games
WHERE eco IS NOT NULL AND eco <> ''
GROUP BY eco
ORDER BY games DESC
LIMIT 25$$),
  (4, 'Chess', 4, 'Ratings over time',
   'The higher of the two players'' ratings in each month, as a line.',
   $$SELECT svg_chart(
  list({'month': m, 'top rating': r} ORDER BY m),
  {'type': 'line', 'title': 'Highest rating seen per month', 'aspect_ratio': 3}
) AS chart
FROM (
  SELECT replace(left("date", 7), '.', '-') AS m, max(greatest(white_elo, black_elo))::INTEGER AS r
  FROM chess.games
  WHERE "date" IS NOT NULL AND white_elo IS NOT NULL AND black_elo IS NOT NULL
  GROUP BY 1
)$$),
  (5, 'Sleep, heart rate and steps', 1, 'Sleep, night by night',
   'Hours slept on each of the last 90 nights.',
   $$SELECT svg_chart(
  list({'night': "day", 'hours': hours} ORDER BY "day"),
  {'type': 'bar', 'title': 'Hours slept, last 90 nights', 'aspect_ratio': 3}
) AS chart
FROM (SELECT "day", round(hours, 2) AS hours FROM garmin.sleep ORDER BY "day" DESC LIMIT 90)$$),
  (5, 'Sleep, heart rate and steps', 2, 'Sleep stages by month',
   'Average deep, light and REM sleep and time awake, per month.',
   $$SELECT svg_chart(
  list({'month': m, 'deep': deep, 'light': light, 'rem': rem, 'awake': awake} ORDER BY m),
  {'type': 'bar', 'title': 'Average sleep stages (hours)', 'aspect_ratio': 2.4,
   'series': [{'key': 'deep', 'stack_id': 'a'}, {'key': 'light', 'stack_id': 'a'},
              {'key': 'rem', 'stack_id': 'a'}, {'key': 'awake', 'stack_id': 'a'}]}
) AS chart
FROM (
  SELECT left("day", 7) AS m, round(avg(deep_hours), 2) AS deep, round(avg(light_hours), 2) AS light,
         round(avg(rem_hours), 2) AS rem, round(avg(awake_hours), 2) AS awake
  FROM garmin.sleep
  WHERE hours > 0
  GROUP BY 1
)$$),
  (5, 'Sleep, heart rate and steps', 3, 'Resting heart rate',
   'Daily resting and average heart rate over the last 180 days.',
   $$SELECT svg_chart(
  list({'day': "day", 'resting': rhr, 'average': hr_avg} ORDER BY "day"),
  {'type': 'line', 'title': 'Heart rate, last 180 days (bpm)', 'aspect_ratio': 3}
) AS chart
FROM (SELECT * FROM garmin.daily WHERE rhr IS NOT NULL OR hr_avg IS NOT NULL ORDER BY "day" DESC LIMIT 180)$$),
  (5, 'Sleep, heart rate and steps', 4, 'Steps per week',
   'Average daily steps in each week.',
   $$SELECT svg_chart(
  list({'week': wk, 'steps': steps} ORDER BY wk),
  {'type': 'bar', 'title': 'Average daily steps by week', 'aspect_ratio': 3}
) AS chart
FROM (
  SELECT strftime(date_trunc('week', CAST("day" AS DATE)), '%Y-%m-%d') AS wk, round(avg(steps))::INTEGER AS steps
  FROM garmin.daily
  WHERE steps IS NOT NULL
  GROUP BY 1
)$$),
  (5, 'Sleep, heart rate and steps', 5, 'Does more sleep mean more steps?',
   'Nights grouped by whole hours slept, with the steps taken on the day they ended and the average sleep score.',
   $$SELECT floor(s.hours) AS hours_slept, count(*) AS nights,
       round(avg(d.steps)) AS avg_steps_next_day, round(avg(s.score), 1) AS avg_score
FROM garmin.sleep s
JOIN garmin.daily d ON d."day" = s."day"
WHERE s.hours > 0 AND d.steps IS NOT NULL
GROUP BY 1
ORDER BY 1$$)
) t(gn, grp, ord, title, descr, sql);
