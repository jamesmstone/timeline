-- Copies the purifier recorder's status table into a SQLite file the private
-- instance can attach. Variables:
--   live   the recorder's DuckDB file, opened read-only for the length of one copy
--   out    path of the SQLite file to write
ATTACH getvariable('live') AS live (READ_ONLY);
ATTACH getvariable('out') AS snap (TYPE sqlite);

-- SQLite has no timestamp type the scanner round-trips, so the time is text.
CREATE TABLE snap.status AS
  SELECT * REPLACE (CAST(recorded_at AS VARCHAR) AS recorded_at) FROM live.status;
