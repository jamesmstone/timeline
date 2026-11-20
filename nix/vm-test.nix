{
  self,
  pkgs,
  system,
  duckweb,
  duckwebModule,
}:
let
  site = self.packages.${system};

  fixtures = pkgs.runCommand "timeline-fixtures" { nativeBuildInputs = [ duckweb.duckdbStatic pkgs.sqlite ]; } ''
    mkdir -p $out/garmin
    run() {
      duckdb -unsigned -noheader -list \
        -cmd "LOAD '${site.sqlite-scanner}/sqlite_scanner.duckdb_extension'" \
        -cmd "SET VARIABLE out = '$1'" -f "$2"
    }
    run $out ${../test/fixtures.sql}
    run $out/garmin ${../test/garmin.sql}
    run $out ${../test/private.sql}
    sqlite3 $out/chat.db < ${../test/chat.sqlite.sql}
    ${pkgs.lib.getExe site.purifier-snapshot} $out/status.duckdb $out/purifier.sqlite
    cp ${../test/family.json} $out/family.json
  '';

  # January 2026 whole, where 601 plays force density bars, and the 4th to the
  # 19th, where every source has a few events and the busy day is out.
  month = "from=1767225600&to=1769904000&span=2592000&at=1767225600";
  fortnight = "from=1767571200&to=1768867200&span=1296000&at=1767571200";
in
pkgs.testers.runNixOSTest {
  name = "timeline-sites";

  nodes.machine =
    { ... }:
    {
      imports = [
        self.nixosModules.default
        duckwebModule
      ];

      virtualisation.graphics = false;
      virtualisation.memorySize = 4096;
      # Stands in for the edge's /data: range requests over plain files.
      services.caddy = {
        enable = true;
        virtualHosts.":8099".extraConfig = ''
          handle_path /data/* {
            root * /var/lib/timeline-export
            file_server
          }
          handle {
            reverse_proxy 127.0.0.1:8791
          }
        '';
      };

      environment.systemPackages = [
        pkgs.curl
        pkgs.sqlite
        pkgs.jq
        duckweb.duckdbStatic
        site.purifier-snapshot
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

      services.timeline-export = {
        enable = true;
        sources = {
          lastfm = "${fixtures}/lastfm.db";
          reading = "${fixtures}/readingList.db";
          parkrun = "${fixtures}/parkruns.db";
          chess = "${fixtures}/chess.db";
          garmin = "/var/lib/timeline/garmin-public.sqlite";
        };
      };

      # Both instances on one host, as deployed: the public one must still not
      # see what only the private one is handed.
      services.timeline-private = {
        enable = true;
        port = 8792;
        sources = {
          lastfm = "${fixtures}/lastfm.db";
          reading = "${fixtures}/readingList.db";
          parkrun = "${fixtures}/parkruns.db";
          chess = "${fixtures}/chess.db";
        };
        garmin = {
          directory = "${fixtures}/garmin";
          groups = [ ];
        };
        chat = {
          snapshot = "${fixtures}/chat.db";
          archive = "${fixtures}/archive.db";
        };
        purifier.snapshot = "${fixtures}/purifier.sqlite";
        family.url = "file://${fixtures}/family.json";
        quack = {
          enable = true;
          tokenFile = pkgs.writeText "quack-token" "fixture-quack-token\n";
        };
      };
    };

  # No Garmin at all: the instance must come up and draw the other lanes.
  nodes.lean =
    { ... }:
    {
      imports = [
        self.nixosModules.default
        duckwebModule
      ];
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
    import re

    def get(node, path, *flags, port=8791):
        return node.succeed(f"curl -sS {' '.join(flags)} 'http://127.0.0.1:{port}{path}'")

    def status(node, path, port=8791):
        return node.succeed(
            f"curl -sS -o /dev/null -w '%{{http_code}}' 'http://127.0.0.1:{port}{path}'"
        ).strip()

    def enc(q):
        return q.replace(" ", "+").replace("'", "%27").replace(";", "%3B")

    def sql(node, q, port=8791):
        return get(node, "/sql?q=" + enc(q), port=port)

    def rows(node, q, port=8791):
        body = sql(node, q, port)
        inner = body.split("<pre data-result>", 1)[1].split("</pre>", 1)[0]
        return [json.loads(l.replace("&quot;", '"')) for l in inner.splitlines() if l]

    import shlex

    def client(q, header="'X-Duckweb-Client: 1' || chr(13) || chr(10)"):
        # What the page's worker does, natively: attach the exports over HTTP and render the route.
        ver = machine.succeed("cat /var/lib/timeline-export/version").strip()
        base = f"http://127.0.0.1:8099/data/v/{ver}"
        stmts = ["LOAD '${site.httpfs}/httpfs.duckdb_extension'", "LOAD '${duckweb.duckweb.extensionFile}'"]
        stmts += [f"ATTACH '{base}/{n}.duckdb' AS {n} (READ_ONLY)" for n in ["lastfm", "reading", "parkrun", "chess", "garmin"]]
        stmts += [f"ATTACH '{base}/app.duckdb' AS app (READ_ONLY)", "SET search_path='memory.main,app.main'"]
        sel = "SELECT string_agg(chunk, substr('x', 1, 0)) FROM render('GET', '/sql?q=" + enc(q) + "', " + header + ", substr('x', 1, 0)) AS r(chunk)"
        return "duckdb -unsigned -bail -noheader -list " + " ".join("-cmd " + shlex.quote(x) for x in stmts) + " -c " + shlex.quote(sel)

    def crows(q):
        body = machine.succeed(client(q))
        inner = body.split("<pre data-result>", 1)[1].split("</pre>", 1)[0]
        return [json.loads(l.replace("&quot;", '"')) for l in inner.splitlines() if l.startswith("{")]

    start_all()
    machine.wait_for_unit("duckweb-timeline.service")
    machine.wait_for_open_port(8791)
    machine.wait_for_unit("duckweb-timeline-private.service")
    machine.wait_for_open_port(8792)
    lean.wait_for_unit("duckweb-timeline.service")
    lean.wait_for_open_port(8791)

    with subtest("the export is one versioned directory of per-source DuckDB files, with nothing private"):
        machine.succeed("systemctl start timeline-garmin-public.service")
        machine.succeed("systemctl start timeline-export.service")
        out = "/var/lib/timeline-export"
        ver = machine.succeed(f"cat {out}/version").strip()
        files = sorted(machine.succeed(f"ls {out}/v/{ver}").split())
        assert files == sorted(f"{n}.duckdb{x}" for n in ["app", "chess", "garmin", "lastfm", "parkrun", "reading"] for x in ["", ".wal"]), files
        assert machine.succeed(f"duckdb -noheader -list {out}/v/{ver}/lastfm.duckdb 'select count(*) from listens'").strip() == "601"
        assert machine.succeed(f"duckdb -noheader -list {out}/v/{ver}/garmin.duckdb 'select count(*) from sleep'").strip() == "1"
        machine.fail(f"grep -qa GPS-CANARY {out}/v/{ver}/garmin.duckdb")
        machine.fail(f"ls {out}/v/{ver} | grep -E 'tmp|chat|archive|purifier|monitoring'")
        # Over HTTP with range requests, as the page's worker reads it.
        machine.wait_for_open_port(8099)
        assert machine.succeed(f"curl -sS -r 0-15 http://127.0.0.1:8099/data/v/{ver}/lastfm.duckdb | wc -c").strip() == "16"
        assert machine.succeed("curl -sS http://127.0.0.1:8099/data/version").strip() == ver
        # A second run with nothing changed is the same version; a changed source is a new one.
        machine.succeed("systemctl start timeline-export.service")
        assert machine.succeed(f"cat {out}/version").strip() == ver

    with subtest("the page arrives complete, with the drawing already in it"):
        page = get(machine, "/?span=345600&at=1767960000")
        assert "data-timeline-svg" in page, page[:500]
        assert 'data-lane-label="sleep"' in page, page[:500]
        assert "Marker &lt;b&gt;Song" in page

    with subtest("the pan script and the stylesheets are served"):
        assert status(machine, "/_duckweb/timeline.js") == "200"
        assert "javascript" in machine.succeed("curl -sS -o /dev/null -w '%{content_type}' 'http://127.0.0.1:8791/_duckweb/timeline.js'")
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

    with subtest("the published Garmin file holds aggregates and nothing with a location"):
        machine.succeed("systemctl start timeline-garmin-public.service")
        out = "/var/lib/timeline/garmin-public.sqlite"
        assert machine.succeed(f"sqlite3 {out} 'select count(*) from sleep'").strip() == "1"
        assert machine.succeed(f"sqlite3 {out} 'select count(*) from daily'").strip() == "2"
        machine.fail(f"grep -qa GPS-CANARY {out}")
        assert "GPS-CANARY" not in get(machine, "/lanes.svg?${month}&w=1000")

    with subtest("the public /sql is a shell: the server runs none of the visitor's SQL"):
        for q in ["select 'SERVER-RAN-IT' as x", "select * from read_text('/etc/passwd')", "copy (select 1) to '/tmp/pwned.csv'"]:
            assert status(machine, "/sql?q=" + enc(q)) == "200", q
            body = sql(machine, q)
            assert "<pre data-result>" not in body and "root:" not in body, (q, body)
        machine.fail("test -e /tmp/pwned.csv")
        page = get(machine, "/sql")
        for want in ["id=duckweb-root", "window.__duckweb=", '"hydrate":true', "/_duckweb/client.js", "/data/v/%VERSION%/app.duckdb"]:
            assert want in page, want
        # The client header changes nothing on the server: it only ever answers documents.
        assert "<!doctype html>" in machine.succeed("curl -sS -H 'X-Duckweb-Client: 1' http://127.0.0.1:8791/sql")
        for asset in ["client.js", "duckweb.duckdb_extension.wasm", "httpfs.duckdb_extension.wasm", "duckdb-base.wasm"]:
            assert status(machine, "/_duckweb/" + asset) == "200", asset

    with subtest("the browser's path runs the SQL over the exported files"):
        assert crows("select count(*) n from lastfm.listens") == [{"n": 601}]
        assert len(crows("select * from range(100000)")) == 500
        names = sorted(r["database_name"] for r in crows("select distinct database_name from duckdb_databases()"))
        assert names == ["app", "chess", "garmin", "lastfm", "memory", "parkrun", "reading", "system", "temp"], names
        assert sorted(r["table_name"] for r in crows("select table_name from duckdb_tables() where database_name = 'garmin'")) == ["daily", "sleep"]
        fragment = machine.succeed(client("select 1 as one"))
        assert "<title>timeline SQL</title>" in fragment and "<!doctype" not in fragment and "window.__duckweb" not in fragment
        document = machine.succeed(client("select 1 as one", header="substr('x', 1, 0)"))
        assert "<!doctype html>" in document and "window.__duckweb=" in document
        for q in ["insert into lastfm.listens values (1, 1, 'x', 'x', null)", "create table app.t as select 1", "select 1; select 2"]:
            machine.fail(client(q))

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

    with subtest("the private instance sees the private sources and the public one does not"):
        private_names = sorted(r["database_name"] for r in rows(machine, "select distinct database_name from duckdb_databases()", 8792))
        assert private_names == [
            "archive", "chat", "chess", "family", "garmin", "garmin_activities", "garmin_full", "garmin_monitoring",
            "garmin_summary", "lastfm", "memory", "parkrun", "purifier", "reading", "system", "temp",
        ], private_names
        # Full Garmin, GPS included, answers on the private box only.
        assert rows(machine, "select canary from garmin_activities.activity_records", 8792) == [{"canary": "GPS-CANARY"}]
        assert rows(machine, "select heart_rate from garmin_monitoring.monitoring_hr", 8792) == [{"heart_rate": 77}]
        assert rows(machine, "select count(*) n from chat_events", 8792) == [{"n": 3}]
        assert rows(machine, "select body from archive.archived", 8792) == [{"body": "ARCHIVE-CANARY"}]
        assert rows(machine, "select count(*) n from purifier.status", 8792) == [{"n": 2}]
        for q in [
            "select * from garmin_activities.activity_records",
            "select * from garmin_monitoring.monitoring_hr",
            "select * from garmin_full.sleep",
            "select * from chat.events",
            "select * from chat_messages",
            "select * from archive.archived",
            "select * from purifier.status",
            "select * from air_points",
            "select * from chat_daily",
        ]:
            # The browser's catalogs are the exports; none of these exist there.
            machine.fail(client(q))

    with subtest("the public instance has no chat or air routes, the private one does"):
        for path in ["/chat", "/chat/search?q=needle"]:
            assert status(machine, path) == "404", (path, get(machine, path)[:300])
            assert status(machine, path, port=8792) == "200", (path, get(machine, path, port=8792)[:600])
        public_page = get(machine, "/?span=345600&at=1767960000")
        assert 'data-lane-label="chat"' not in public_page and 'data-lane-label="air"' not in public_page

    with subtest("the private lane timeline draws chat and air next to the public lanes"):
        page = get(machine, "/?span=345600&at=1767960000", port=8792)
        for lane in ["music", "sleep", "chat", "air"]:
            assert f'data-lane-label="{lane}"' in page, lane
        svg = get(machine, "/lanes.svg?${fortnight}&w=1000", port=8792)
        for lane in ["music", "read", "parkrun", "chess", "sleep", "heart", "steps", "chat", "air"]:
            assert f"data-lane={lane}" in svg, lane
        assert "whatsapp message" in svg
        assert "PM2.5 12" in svg

    with subtest("message bodies and coordinates stay off the pages and out of the lanes"):
        for path in ["/", "/?span=all", "/lanes.svg?${fortnight}&w=1000", "/lanes.svg?${month}&w=1000", "/chat", "/chat/search"]:
            body = get(machine, path, port=8792)
            assert "CHAT-BODY-CANARY" not in body and "ARCHIVE-CANARY" not in body and "GPS-CANARY" not in body, path
        assert "whatsapp" in get(machine, "/chat", port=8792)

    with subtest("the explicit search route is the only page that shows bodies"):
        found = get(machine, "/chat/search?q=NEEDLE", port=8792)
        assert "CHAT-BODY-CANARY hello needle" in found, found
        assert "unrelated" not in found
        assert get(machine, "/chat/search?q=%3Cb%3Ereply", port=8792).count("<b>reply") == 0
        assert "&lt;b&gt;reply&lt;/b&gt;" in get(machine, "/chat/search?q=%3Cb%3Ereply", port=8792)
        # Too short a query is not a way to list everything; neither is a wildcard.
        assert "data-match" not in get(machine, "/chat/search?q=ne", port=8792)
        assert "data-match" not in get(machine, "/chat/search?q=%25%25%25", port=8792)
        assert "data-match" not in get(machine, "/chat/search", port=8792)

    with subtest("the private SQL box can read bodies but not write, read files or reconfigure"):
        assert rows(machine, "select count(*) n from chat_messages where contains(body, 'CANARY')", 8792) == [{"n": 2}]
        for q in [
            "create table lanes2 as select 1",
            "copy (select 1) to '/tmp/pwned-private.csv'",
            "select * from read_text('/etc/passwd')",
            "attach '${fixtures}/status.duckdb' as live",
            "select * from read_blob('${fixtures}/status.duckdb')",
            "set enable_external_access = true",
        ]:
            assert status(machine, "/sql?q=" + enc(q), port=8792) == "500", q
        machine.fail("test -e /tmp/pwned-private.csv")

    with subtest("the private instance never holds the live purifier file"):
        # The recorder opens its file read-write each minute; a reader's lock
        # would fail that tick, so a write must succeed while the server runs.
        machine.succeed("cp ${fixtures}/status.duckdb /tmp/live.duckdb && chmod u+w /tmp/live.duckdb")
        pid = machine.succeed("systemctl show -p MainPID --value duckweb-timeline-private.service").strip()
        assert pid != "0"
        machine.fail(f"ls -l /proc/{pid}/fd | grep -F status.duckdb")
        machine.succeed("duckdb /tmp/live.duckdb \"insert into status values (now()::timestamp, true, 'auto', 5.0, 1)\"")
        assert rows(machine, "select path from duckdb_databases() where database_name = 'purifier'", 8792) == [{"path": "${fixtures}/purifier.sqlite"}]
        assert rows(machine, "select count(*) n from purifier.status", 8792) == [{"n": 2}]
        machine.succeed("timeline-purifier-snapshot /tmp/live.duckdb /tmp/purifier.sqlite")
        assert machine.succeed("sqlite3 /tmp/purifier.sqlite 'select count(*) from status'").strip() == "3"

    with subtest("the private instance is capped by its own limits"):
        show = machine.succeed("systemctl show duckweb-timeline-private.service -p MemoryMax -p CPUQuotaPerSecUSec")
        assert "MemoryMax=3221225472" in show, show
        assert "CPUQuotaPerSecUSec=4s" in show, show

    with subtest("/embed.svg draws the raw heart rate and stress lanes next to the others"):
        svg = get(machine, "/embed.svg?start=2026-01-04T00:00:00Z&end=2026-01-19T00:00:00Z&width=1000", port=8792)
        assert svg.startswith("<svg") and "<style>" in svg, svg[:300]
        assert 'width=1000' in svg
        for lane in ["hr", "stress", "sleep", "steps", "music", "family", "read"]:
            assert f"data-lane={lane}" in svg, lane
        assert "77 bpm" in svg and "stress 41" in svg and "Ada Lovelace" in svg
        assert "data-lane=chat" not in svg and "data-lane=air" not in svg
        assert "GPS-CANARY" not in svg and "CHAT-BODY-CANARY" not in svg
        headers = machine.succeed("curl -sS -D - -o /dev/null 'http://127.0.0.1:8792/embed.svg?end=now&duration=1w'")
        assert "image/svg+xml" in headers and "access-control-allow-origin: *" in headers.lower(), headers
        assert "height=520" in svg and "No Birth" not in svg
        tall = get(machine, "/embed.svg?start=2026-01-04T00:00:00Z&end=2026-01-19T00:00:00Z&width=1000&height=700", port=8792)
        assert "height=700" in tall and 'viewBox="0.00 0 1000 700"' in tall, tall[:400]
        for bad in ["start=x", "duration=1y", "duration=10m", "start=2026-01-02T00:00:00Z&end=2026-01-01T00:00:00Z", "width=abc", "height=abc"]:
            assert status(machine, "/embed.svg?" + bad, port=8792) == "400", bad

    with subtest("the pages do not draw the raw lanes, and the public instance has no embed"):
        svg = get(machine, "/lanes.svg?${fortnight}&w=1000", port=8792)
        assert "data-lane=hr " not in svg and "data-lane=stress" not in svg, sorted(set(re.findall(r"data-lane=\w+", svg)))
        page = get(machine, "/?span=345600&at=1767960000", port=8792)
        assert 'data-lane-label="hr"' not in page and 'data-lane-label="stress"' not in page, page[:300]
        assert status(machine, "/embed.svg") == "404"

    with subtest("Quack answers with the token and refuses without it"):
        def quack(q, token="fixture-quack-token"):
            return (
                "duckdb -unsigned -noheader -list -cmd \"LOAD '${site.httpfs}/httpfs.duckdb_extension'\" -cmd \"LOAD '${site.quack}/quack.duckdb_extension'\" -c "
                + json.dumps(f"FROM quack_query('quack:127.0.0.1:9494', '{q}', token = '{token}', disable_ssl = true)")
            )
        assert machine.succeed(quack("select count(*) from lastfm.listens")).strip().splitlines()[-1] == "601"
        assert machine.succeed(quack("select heart_rate from garmin_monitoring.monitoring_hr")).strip().splitlines()[-1] == "77"
        machine.fail(quack("select 1", token="wrong-token"))
        assert "fixture-quack-token" not in machine.succeed("journalctl -u duckweb-timeline-private.service --no-pager")

    with subtest("a Quack client cannot write sources or read files either"):
        for q in [
            "insert into lastfm.listens values (1, 1, 1, 1, null)",
            "copy (select 1) to '/tmp/pwned-quack.csv'",
            "select * from read_text('/etc/passwd')",
            "attach '/tmp/x.sqlite' as x (type sqlite)",
        ]:
            machine.fail(quack(q))
        machine.fail("test -e /tmp/pwned-quack.csv")
  '';
}
