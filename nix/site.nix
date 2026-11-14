{
  lib,
  runCommand,
  writeShellApplication,
  coreutils,
  duckdb,
  sqliteScanner,
  designCss,
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
  inherit garminPublic emptyGarmin;

  # Served under /_duckweb/ by duckweb itself: the stylesheet, its fonts and
  # the pan script. The design library's fonts are referenced as ../fonts/, so
  # css/ and fonts/ stay siblings.
  assets = runCommand "timeline-assets" { } ''
    mkdir -p $out/design
    cp -r ${designCss}/css ${designCss}/fonts $out/design/
    cp ${appSrc}/web/timeline.js ${appSrc}/web/timeline.css $out/
  '';

  app = runCommand "timeline-app" { } ''
    cp -r ${appSrc}/app $out
  '';
}
