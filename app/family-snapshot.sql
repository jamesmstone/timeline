ATTACH getvariable('out') AS snap (TYPE sqlite);

CREATE TABLE snap.individuals AS
  SELECT n.id AS id, n.name.fullName AS name,
         n.birth.date AS birth, n.death.date AS death, coalesce(n.death.died, false) AS died
  FROM (SELECT unnest(data.allIndividual.nodes) AS n FROM read_json(getvariable('json')));
