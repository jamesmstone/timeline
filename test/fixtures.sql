-- Small SQLite files shaped like the real sources, written by DuckDB. Variable
-- out is the directory they go in. Dates sit in January 2026 so a check can ask
-- for a fixed window.
SET VARIABLE out = getvariable('out');

ATTACH getvariable('out') || '/lastfm.db' AS lastfm (TYPE sqlite);
CREATE TABLE lastfm.artists(id INTEGER, mbid VARCHAR, name VARCHAR, image VARCHAR, plays INTEGER);
CREATE TABLE lastfm.albums(id INTEGER, artists_id INTEGER, mbid VARCHAR, name VARCHAR, image VARCHAR, plays INTEGER);
CREATE TABLE lastfm.tracks(id INTEGER, albums_id INTEGER, mbid VARCHAR, name VARCHAR, image VARCHAR, url VARCHAR,
  streamable VARCHAR, tracks_id INTEGER, avg_estimated_duration DOUBLE, plays INTEGER, total_estimated_listen_time DOUBLE);
CREATE TABLE lastfm.listens(tracks_id INTEGER, date_uts BIGINT, "date_#text" VARCHAR, loved VARCHAR, "@attr_nowplaying" VARCHAR);
INSERT INTO lastfm.artists VALUES (1, '', 'Fixture Band & Co', '', 1);
INSERT INTO lastfm.albums VALUES (1, 1, '', 'Fixture Album', '', 1);
INSERT INTO lastfm.tracks VALUES
  (1, 1, '', 'Marker <b>Song</b>', '', '', '0', 1, 200.0, 1, 200.0),
  (2, 1, '', 'Filler', '', '', '0', 2, NULL, 1, 0.0);
-- One play on the 10th that the narrow-window checks look for, and 600 more
-- across the 20th so a month-wide window has to fall back to density bars.
INSERT INTO lastfm.listens VALUES (1, epoch(TIMESTAMP '2026-01-10 12:00:00')::BIGINT, '', '0', NULL);
INSERT INTO lastfm.listens
  SELECT 2, epoch(TIMESTAMP '2026-01-20 00:00:00')::BIGINT + i * 100, '', '0', NULL FROM range(600) t(i);

ATTACH getvariable('out') || '/readingList.db' AS reading (TYPE sqlite);
CREATE TABLE reading."read"(url VARCHAR, title VARCHAR, description VARCHAR, image VARCHAR, "date" VARCHAR,
  hnurl VARCHAR, screenshot VARCHAR, pdf VARCHAR, domain VARCHAR);
INSERT INTO reading."read" VALUES
  ('https://example.org/a', 'An article', 'About a thing', '', '2026-01-12T10:17:58.763847135Z', '', '', '', 'example.org');

ATTACH getvariable('out') || '/parkruns.db' AS parkrun (TYPE sqlite);
CREATE TABLE parkrun.runs(Event VARCHAR, RunDate VARCHAR, RunNumber INTEGER, Pos INTEGER, "Time" VARCHAR,
  AgeGrade DOUBLE, PB INTEGER, Latitude DOUBLE, Longitude DOUBLE);
INSERT INTO parkrun.runs VALUES ('Fixture Common', '2026-01-17', 12, 3, '00:19:40', 70.5, 0, 0.0, 0.0);

ATTACH getvariable('out') || '/chess.db' AS chess (TYPE sqlite);
CREATE TABLE chess.games(id INTEGER, event VARCHAR, site VARCHAR, "date" VARCHAR, round VARCHAR, white VARCHAR,
  black VARCHAR, result VARCHAR, eco VARCHAR, white_elo INTEGER, black_elo INTEGER, variant VARCHAR,
  time_control VARCHAR, termination VARCHAR, moves VARCHAR);
INSERT INTO chess.games VALUES (1, '', '', '2026.01.05', '', 'alice', 'bob', '1-0', '', 1500, 1500, '', '', '', '');
