-- Flattens the family tree's individualsAPI.json into a SQLite file the private
-- instance can attach. Variables:
--   json   the downloaded file
--   out    path of the SQLite file to write
ATTACH getvariable('out') AS snap (TYPE sqlite);

CREATE TABLE snap.individuals AS
  SELECT n.id AS id, n.name.fullName AS name,
         n.birth.date AS birth, n.death.date AS death, coalesce(n.death.died, false) AS died
  FROM (SELECT unnest(data.allIndividual.nodes) AS n FROM read_json(getvariable('json')));
