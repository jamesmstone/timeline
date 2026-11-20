-- The public instance's route table, with nothing private in it.

CREATE OR REPLACE MACRO render(method, route, headers, body) AS TABLE (
            SELECT * FROM route_home(method, route)
  UNION ALL SELECT * FROM route_lanes(method, route)
  UNION ALL SELECT * FROM route_sql(method, route, headers)
  UNION ALL SELECT * FROM route_not_found(method, route)
);
