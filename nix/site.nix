{
  lib,
  runCommand,
  writeShellApplication,
  writeText,
  coreutils,
  duckdb,
  sqliteScanner,
  designCss,
  curl,
  duckwebExtension,
  duckwebWasm,
  duckwebAssets,
  duckwebClient,
  duckdbVersion,
}:
let
  appSrc = lib.fileset.toSource {
    root = ./..;
    fileset = lib.fileset.unions [
      ../app
      ../web/timeline.js
      ../web/timeline.css
    ];
  };

  # The sanitiser is the only thing that ever reads the full Garmin databases.
  # It always leaves a file behind, empty when the source is not there, so the
  # public server has something to attach on a host that has no Garmin data yet.
  garminPublic = writeShellApplication {
    name = "timeline-garmin-public";
    runtimeInputs = [
      coreutils
      duckdb
    ];
    text = ''
      usage="usage: timeline-garmin-public <garmin-dir> <out.sqlite>"
      dir=''${1:?$usage}
      out=''${2:?$usage}
      tmp="$out.tmp"
      rm -f "$tmp"

      cd ${appSrc}/app
      if [ -f "$dir/james_garmin.db" ] && [ -f "$dir/james_garmin_summary.db" ]; then
        duckdb -unsigned -noheader -list \
          -cmd "LOAD '${sqliteScanner}/sqlite_scanner.duckdb_extension'" \
          -cmd "SET VARIABLE garmin_dir = '$dir'" \
          -cmd "SET VARIABLE out = '$tmp'" \
          -f garmin-public.sql
      else
        echo "no Garmin snapshots in $dir; publishing an empty set" >&2
        duckdb -unsigned -noheader -list \
          -cmd "LOAD '${sqliteScanner}/sqlite_scanner.duckdb_extension'" \
          -cmd "ATTACH '$tmp' AS pub (TYPE sqlite)" \
          -f garmin-schema.sql
      fi
      mv -f "$tmp" "$out"
    '';
  };

  # The recorder opens its DuckDB file read-write every minute and a reader's
  # lock fails that tick, so this holds the live file only for one copy and
  # retries if the recorder has it. The server only ever sees the result.
  purifierSnapshot = writeShellApplication {
    name = "timeline-purifier-snapshot";
    runtimeInputs = [
      coreutils
      duckdb
    ];
    text = ''
      usage="usage: timeline-purifier-snapshot <status.duckdb> <out.sqlite>"
      live=''${1:?$usage}
      out=''${2:?$usage}
      tmp="$out.tmp"

      cd ${appSrc}/app
      for attempt in 1 2 3 4 5; do
        rm -f "$tmp"
        if duckdb -unsigned -noheader -list \
          -cmd "LOAD '${sqliteScanner}/sqlite_scanner.duckdb_extension'" \
          -cmd "SET VARIABLE live = '$live'" \
          -cmd "SET VARIABLE out = '$tmp'" \
          -f purifier-snapshot.sql; then
          mv -f "$tmp" "$out"
          exit 0
        fi
        echo "attempt $attempt failed, retrying" >&2
        sleep 2
      done
      rm -f "$tmp"
      exit 1
    '';
  };

  # A failed download keeps the last snapshot: the tree changes rarely and its
  # host can be down. With none yet, an empty table, so the server still starts.
  familySnapshot = writeShellApplication {
    name = "timeline-family-snapshot";
    runtimeInputs = [
      coreutils
      curl
      duckdb
    ];
    text = ''
      usage="usage: timeline-family-snapshot <url> <out.sqlite>"
      url=''${1:?$usage}
      out=''${2:?$usage}
      tmp="$out.tmp"
      json=$(mktemp)
      trap 'rm -f "$json" "$tmp"' EXIT

      cd ${appSrc}/app
      rm -f "$tmp"
      if curl -fsS --max-time 60 -o "$json" "$url"; then
        duckdb -unsigned -bail -noheader -list \
          -cmd "LOAD '${sqliteScanner}/sqlite_scanner.duckdb_extension'" \
          -cmd "SET VARIABLE json = '$json'" \
          -cmd "SET VARIABLE out = '$tmp'" \
          -f family-snapshot.sql
        mv -f "$tmp" "$out"
      elif [ ! -e "$out" ]; then
        duckdb -unsigned -bail -noheader -list \
          -cmd "LOAD '${sqliteScanner}/sqlite_scanner.duckdb_extension'" \
          -cmd "ATTACH '$tmp' AS snap (TYPE sqlite)" \
          -cmd "CREATE TABLE snap.individuals(id VARCHAR, name VARCHAR, birth VARCHAR, death VARCHAR, died BOOLEAN)"
        mv -f "$tmp" "$out"
      fi
    '';
  };

  # Copy-then-rename, so a reader never sees a half-written file.
  exportOne = writeShellApplication {
    name = "timeline-export-one";
    runtimeInputs = [
      coreutils
      duckdb
    ];
    text = ''
      usage="usage: timeline-export-one <in.sqlite> <out.duckdb>"
      in=''${1:?$usage}
      out=''${2:?$usage}
      tmp="$out.tmp"
      rm -f "$tmp" "$tmp.wal"

      load="LOAD '${sqliteScanner}/sqlite_scanner.duckdb_extension'"
      attach="ATTACH '$in' AS src (TYPE sqlite, READ_ONLY)"

      # COPY FROM DATABASE replays the SQLite index DDL through DuckDB's
      # parser, which rejects the [bracket] quoting some scrapers emit.
      script=$(mktemp)
      trap 'rm -f "$script"' EXIT
      duckdb -unsigned -bail -noheader -list \
        -cmd "$load" -cmd "$attach" \
        -c "SELECT format('CREATE TABLE dst.main.\"{}\" AS FROM src.main.\"{}\";', q, q) FROM (SELECT replace(table_name, '\"', '\"\"') AS q FROM duckdb_tables() WHERE database_name = 'src' ORDER BY table_name)" \
        > "$script"

      duckdb -unsigned -bail -noheader -list \
        -cmd "$load" -cmd "$attach" \
        -cmd "ATTACH '$tmp' AS dst" \
        -cmd ".read $script" \
        -cmd "CHECKPOINT dst" \
        -cmd "SELECT 1 WHERE false"
      if [ -e "$tmp.wal" ]; then
        echo "$tmp.wal survived CHECKPOINT; the export is not self-contained" >&2
        exit 1
      fi
      chmod 0644 "$tmp"
      mv -f "$tmp" "$out"
    '';
  };

  sources = [ "lastfm" "reading" "parkrun" "chess" "garmin" ];

  # The exports of the fixtures, which the page's macros are bound against.
  fixtureExports = runCommand "timeline-fixture-exports" { nativeBuildInputs = [ duckdb exportOne garminPublic ]; } ''
    mkdir -p sq garmin $out
    run() {
      duckdb -unsigned -noheader -list \
        -cmd "LOAD '${sqliteScanner}/sqlite_scanner.duckdb_extension'" \
        -cmd "SET VARIABLE out = '$1'" -f "$2"
    }
    run $PWD/sq ${../test/fixtures.sql}
    run $PWD/garmin ${../test/garmin.sql}
    timeline-garmin-public $PWD/garmin $PWD/sq/garmin.db
    timeline-export-one sq/lastfm.db $out/lastfm.duckdb
    timeline-export-one sq/readingList.db $out/reading.duckdb
    timeline-export-one sq/parkruns.db $out/parkrun.duckdb
    timeline-export-one sq/chess.db $out/chess.duckdb
    timeline-export-one sq/garmin.db $out/garmin.duckdb
  '';

  # What the browser's worker loads: the exports attach by range request from
  # the version directory the page read first, so macros and tables always match.
  clientConfig = builtins.toJSON {
    extensions = [ "/_duckweb/duckweb.duckdb_extension.wasm" ];
    app = "/data/v/%VERSION%/app.duckdb";
    version = "/data/version";
    setup = map (n: "ATTACH '%ORIGIN%/data/v/%VERSION%/${n}.duckdb' AS ${n} (READ_ONLY)") sources;
    hydrate = true;
  };

  clientConfigSql = writeText "client-config.sql" ''
    CREATE OR REPLACE MACRO client_config() AS '${lib.replaceStrings [ "'" ] [ "''" ] clientConfig}';
  '';

  appFiles = [
    clientConfigSql
    "${appSrc}/app/views-shared.sql"
    "${appSrc}/app/views-garmin.sql"
    "${appSrc}/app/lanes-public.sql"
    "${appSrc}/app/instance-public.sql"
    "${appSrc}/app/core.sql"
    "${appSrc}/app/routes-public.sql"
  ];

  # Macros and views only; the data arrives separately, as the exports.
  appDb = runCommand "timeline-app-db" { nativeBuildInputs = [ duckdb ]; } ''
    got=$(duckdb -noheader -list -c 'SELECT version()')
    if [ "$got" != "${duckdbVersion}" ]; then
      echo "duckdb is $got but duckweb's extensions are built for ${duckdbVersion}" >&2
      exit 1
    fi
    {
      echo "LOAD '${duckwebExtension}';"
      for n in ${lib.concatStringsSep " " sources}; do
        echo "ATTACH '${fixtureExports}/$n.duckdb' AS $n (READ_ONLY);"
      done
      echo "ATTACH 'app.duckdb' AS built (BLOCK_SIZE 16384);"
      echo "USE built;"
      cat ${lib.concatStringsSep " " appFiles}
      echo "CHECKPOINT built;"
    } | duckdb -unsigned -bail
    if [ -e app.duckdb.wal ]; then
      echo "app.duckdb.wal survived CHECKPOINT; the database is not self-contained" >&2
      exit 1
    fi
    cp app.duckdb $out
  '';

  # Publishes one consistent export: every source and the macros in a directory named
  # for their content, then `version` last, which is what new visits are pointed at.
  timelineExport = writeShellApplication {
    name = "timeline-export";
    runtimeInputs = [
      coreutils
      exportOne
    ];
    text = ''
      usage="usage: timeline-export <out dir> <name>=<sqlite file>..."
      out=''${1:?$usage}
      shift
      mkdir -p "$out/v"
      work=$(mktemp -d "$out/v/.work.XXXXXX")
      trap 'rm -rf "$work"' EXIT
      cur=""
      [ -r "$out/version" ] && cur=$(tr -d '[:space:]' < "$out/version")

      # Named for the inputs, since a DuckDB file differs byte for byte on every write.
      keys=$(sha256sum ${appDb})
      for spec in "$@"; do
        name=''${spec%%=*}
        path=''${spec#*=}
        if [ -r "$path" ]; then
          keys="$keys$(sha256sum < "$path")"
        elif [ -n "$cur" ] && [ -r "$out/v/$cur/$name.duckdb" ]; then
          keys="$keys$(sha256sum < "$out/v/$cur/$name.duckdb")"
        else
          echo "$name: $path is not readable and there is no earlier export" >&2
          exit 1
        fi
      done
      ver=$(printf '%s' "$keys" | sha256sum | cut -c1-12)

      if [ ! -d "$out/v/$ver" ]; then
        for spec in "$@"; do
          name=''${spec%%=*}
          path=''${spec#*=}
          if [ -r "$path" ]; then
            timeline-export-one "$path" "$work/$name.duckdb"
          else
            cp "$out/v/$cur/$name.duckdb" "$work/$name.duckdb"
          fi
        done
        cp ${appDb} "$work/app.duckdb"
        chmod 0644 "$work"/*.duckdb
        # A remote ATTACH probes for <db>.wal; an empty 200 beats a 404 there.
        for f in "$work"/*.duckdb; do : > "$f.wal"; done
        chmod 0755 "$work"
        mv "$work" "$out/v/$ver"
      fi
      # Tabs still on an older version keep working for a while.
      # shellcheck disable=SC2012
      ls -1t "$out/v" | tail -n +4 | while read -r old; do rm -rf "''${out:?}/v/$old"; done
      printf '%s\n' "$ver" > "$out/version.tmp"
      chmod 0644 "$out/version.tmp"
      mv -f "$out/version.tmp" "$out/version"
    '';
  };

  emptyGarmin = runCommand "timeline-garmin-empty.sqlite" { nativeBuildInputs = [ duckdb ]; } ''
    cd ${appSrc}/app
    duckdb -unsigned -noheader -list \
      -cmd "LOAD '${sqliteScanner}/sqlite_scanner.duckdb_extension'" \
      -cmd "ATTACH '$TMPDIR/empty.sqlite' AS pub (TYPE sqlite)" \
      -f garmin-schema.sql
    cp $TMPDIR/empty.sqlite $out
  '';
in
{
  inherit garminPublic purifierSnapshot emptyGarmin timelineExport familySnapshot appDb fixtureExports;

  # Served under /_duckweb/ by duckweb itself: the stylesheet, its fonts and
  # the pan script. The design library's fonts are referenced as ../fonts/, so
  # css/ and fonts/ stay siblings.
  assets = runCommand "timeline-assets" { } ''
    mkdir -p $out/design
    cp -r ${designCss}/css ${designCss}/fonts $out/design/
    cp ${appSrc}/web/timeline.js ${appSrc}/web/timeline.css $out/
    cp ${duckwebClient}/client.js ${duckwebClient}/host.js $out/
    cp ${duckwebAssets}/duckdb-blocking.js ${duckwebAssets}/duckdb-base.wasm $out/
    cp ${duckwebWasm} $out/duckweb.duckdb_extension.wasm
  '';

  app = runCommand "timeline-app" { } ''
    cp -r ${appSrc}/app $out
    chmod u+w $out
    cp ${clientConfigSql} $out/client-config.sql
  '';
}
