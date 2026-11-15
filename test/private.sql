-- The private-only sources that DuckDB writes: the frozen archive, and the
-- purifier recorder's live DuckDB file, which the snapshot tool copies from.
-- Variable out is the directory they go in.
ATTACH getvariable('out') || '/archive.db' AS archive (TYPE sqlite);
CREATE TABLE archive.archived(id INTEGER, body VARCHAR);
INSERT INTO archive.archived VALUES (1, 'ARCHIVE-CANARY');

ATTACH getvariable('out') || '/status.duckdb' AS live;
CREATE TABLE live.status(recorded_at TIMESTAMP, power BOOLEAN, mode VARCHAR, pm25_ugm3 DOUBLE, fan_level INTEGER);
INSERT INTO live.status VALUES
  (TIMESTAMP '2026-01-10 08:00:00', true, 'auto', 12.0, 2),
  (TIMESTAMP '2026-01-10 08:01:00', true, 'auto', 18.0, 3);
