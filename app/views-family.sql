-- The family lane: one span per person from birth to death, or to now while alive.
-- Times are naive UTC epoch seconds, as in views-shared.sql.

CREATE OR REPLACE VIEW family_spans AS
  SELECT i.name, epoch(CAST(i.birth AS TIMESTAMP))::BIGINT AS t0,
         CASE WHEN i.death IS NOT NULL THEN epoch(CAST(i.death AS TIMESTAMP))::BIGINT
              WHEN NOT i.died THEN epoch(now())::BIGINT END AS t1
    FROM family.individuals i
    WHERE TRY_CAST(i.birth AS TIMESTAMP) IS NOT NULL AND (i.death IS NULL OR TRY_CAST(i.death AS TIMESTAMP) IS NOT NULL);

CREATE OR REPLACE VIEW family_points AS
  SELECT 'family' AS lane, t0, 1.0 AS value FROM family_spans;

CREATE OR REPLACE VIEW family_items AS
  SELECT 'family' AS lane, t0, coalesce(t1, t0 + 86400) AS t1, 1.0 AS value, name AS label FROM family_spans;
