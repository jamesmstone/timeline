{
  self,
  pkgs,
  system,
  duckweb,
}:
let
  site = self.packages.${system};

  fixtures = pkgs.runCommand "timeline-fixtures" { nativeBuildInputs = [ duckweb.duckdbStatic ]; } ''
    mkdir -p $out/garmin
    run() {
      duckdb -unsigned -noheader -list \
        -cmd "LOAD '${site.sqlite-scanner}/sqlite_scanner.duckdb_extension'" \
        -cmd "SET VARIABLE out = '$1'" -f "$2"
    }
    run $out ${../test/fixtures.sql}
    run $out/garmin ${../test/garmin.sql}
  '';

  # January 2026 whole, where 601 plays force density bars, and the 4th to the
  # 19th, where every source has a few events and the busy day is out.
  month = "from=1767225600&to=1769904000&span=2592000&at=1767225600";
  fortnight = "from=1767571200&to=1768867200&span=1296000&at=1767571200";
in
pkgs.testers.runNixOSTest {
  name = "timeline-public-site";

  nodes.machine =
    { ... }:
    {
      imports = [ self.nixosModules.default ];

      virtualisation.graphics = false;
      virtualisation.memorySize = 2048;
      environment.systemPackages = [
        pkgs.curl
        pkgs.sqlite
        pkgs.jq
      ];

      services.timeline = {
        enable = true;
        sources = {
          lastfm = "${fixtures}/lastfm.db";
          reading = "${fixtures}/readingList.db";
          parkrun = "${fixtures}/parkruns.db";
          chess = "${fixtures}/chess.db";
        };
        garmin = {
          enable = true;
          snapshotDir = "${fixtures}/garmin";
          groups = [ ];
        };
      };
    };

  # No Garmin at all: the instance must come up and draw the other lanes.
  nodes.lean =
    { ... }:
    {
      imports = [ self.nixosModules.default ];
      virtualisation.graphics = false;
      virtualisation.memorySize = 2048;
      environment.systemPackages = [ pkgs.curl ];
      services.timeline = {
        enable = true;
        sources = {
          lastfm = "${fixtures}/lastfm.db";
          reading = "${fixtures}/readingList.db";
          parkrun = "${fixtures}/parkruns.db";
          chess = "${fixtures}/chess.db";
        };
      };
    };

  testScript = ''
    import json

    def get(node, path, *flags):
        return node.succeed(f"curl -sS {' '.join(flags)} 'http://127.0.0.1:8791{path}'")

    def status(node, path):
        return node.succeed(
            f"curl -sS -o /dev/null -w '%{{http_code}}' 'http://127.0.0.1:8791{path}'"
        ).strip()

    def enc(q):
        return q.replace(" ", "+").replace("'", "%27").replace(";", "%3B")

    def sql(node, q):
        return get(node, "/sql?q=" + enc(q))

    def rows(node, q):
        body = sql(node, q)
        inner = body.split("<pre data-result>", 1)[1].split("</pre>", 1)[0]
        return [json.loads(l.replace("&quot;", '"')) for l in inner.splitlines() if l]

    start_all()
    machine.wait_for_unit("duckweb-timeline.service")
    machine.wait_for_open_port(8791)
    lean.wait_for_unit("duckweb-timeline.service")
    lean.wait_for_open_port(8791)

    with subtest("the page arrives complete, with the drawing already in it"):
        page = get(machine, "/?span=345600&at=1767960000")
        assert "data-timeline-svg" in page, page[:500]
        assert 'data-lane-label="sleep"' in page, page[:500]
        assert "Marker &lt;b&gt;Song" in page

    with subtest("the pan script and the stylesheets are served"):
        js = get(machine, "/_duckweb/timeline.js")
        assert "panned" in js and "TimelinePan" in js
        assert status(machine, "/_duckweb/timeline.css") == "200"
        assert status(machine, "/_duckweb/design/css/style.css") == "200"

    with subtest("a narrow window draws every event as its own item"):
        svg = get(machine, "/lanes.svg?${fortnight}&w=1000")
        assert svg.startswith("<svg"), svg[:200]
        assert 'data-lane=music' in svg
        # Names are escaped, never interpreted.
        assert "Marker &lt;b&gt;Song&lt;/b&gt; — Fixture Band &amp; Co" in svg, svg[:3000]
        assert "<b>Song" not in svg
        for lane in ["read", "parkrun", "chess", "sleep", "heart", "steps"]:
            assert f"data-lane={lane}" in svg, lane
        assert "7.5 h · good, score 81" in svg
        assert "An article" in svg
        assert "position 3" in svg
        assert "alice v bob 1-0" in svg

    with subtest("a busy lane falls back to density bars"):
        svg = get(machine, "/lanes.svg?${month}&w=1000")
        # 601 plays in the window is over the item limit, so no per-play titles.
        assert "Filler" not in svg
        assert svg.count("data-lane=music") < 400

    with subtest("the public instance has no private source to read"):
        names = sorted(r["database_name"] for r in rows(machine, "select distinct database_name from duckdb_databases()"))
        assert names == ["chess", "garmin", "lastfm", "memory", "parkrun", "reading", "system", "temp"], names
        tables = sorted(r["table_name"] for r in rows(machine, "select table_name from duckdb_tables() where database_name = 'garmin'"))
        assert tables == ["daily", "sleep"], tables

    with subtest("the published Garmin file holds aggregates and nothing with a location"):
        machine.succeed("systemctl start timeline-garmin-public.service")
        out = "/var/lib/timeline/garmin-public.sqlite"
        schema = machine.succeed(f"sqlite3 {out} .schema")
        assert "lat" not in schema.lower() and "long" not in schema.lower(), schema
        assert machine.succeed(f"sqlite3 {out} 'select count(*) from sleep'").strip() == "1"
        assert machine.succeed(f"sqlite3 {out} 'select count(*) from daily'").strip() == "2"
        machine.fail(f"grep -qa GPS-CANARY {out}")
        assert "GPS-CANARY" not in get(machine, "/lanes.svg?${month}&w=1000")

    with subtest("the SQL box answers a SELECT and is capped"):
        assert rows(machine, "select count(*) n from lastfm.listens") == [{"n": 601}]
        assert len(rows(machine, "select * from range(100000)")) == 500

    with subtest("the SQL box cannot write, read files, attach or reconfigure"):
        for q in [
            "create table lanes2 as select 1",
            "insert into lastfm.listens values (1, 1, 'x', 'x', null)",
            "select 1; select 2",
            "copy (select 1) to '/tmp/pwned.csv'",
            "select * from read_text('/etc/passwd')",
            "select * from read_csv('/etc/passwd')",
            "attach '/var/lib/timeline/garmin-public.sqlite' as x (type sqlite)",
            "select * from sqlite_scan('${fixtures}/garmin/james_garmin_activities.db', 'activity_records')",
            "set enable_external_access = true",
            "set memory_limit = '64GB'",
            "install httpfs",
        ]:
            code = status(machine, "/sql?q=" + enc(q))
            body = sql(machine, q)
            assert code == "500", (q, code, body)
            assert "root:" not in body and "GPS-CANARY" not in body, (q, body)
        machine.fail("test -e /tmp/pwned.csv")
        machine.succeed("systemctl is-active duckweb-timeline.service")

    with subtest("resource caps are in place on the unit"):
        show = machine.succeed("systemctl show duckweb-timeline.service -p MemoryMax -p CPUQuotaPerSecUSec")
        assert "MemoryMax=1073741824" in show, show
        assert "CPUQuotaPerSecUSec=2s" in show, show

    with subtest("an unknown route is a 404 and only GET is served"):
        assert status(machine, "/nope") == "404"
        assert machine.succeed("curl -sS -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8791/").strip() == "404"

    with subtest("without Garmin the other lanes still draw"):
        svg = get(lean, "/lanes.svg?${fortnight}&w=1000")
        assert "data-lane=music" in svg and "data-lane=read" in svg
        assert "data-lane=sleep" not in svg
        assert status(lean, "/") == "200"
  '';
}
