# Per-source DuckDB exports of the public sources, for the static site: each
# source's SQLite file is copied into its own .duckdb file under outDir, which
# a web server serves as plain files and the browser attaches by range request.
# Closed over the flake's own outputs like site-module.nix.
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.timeline-export;
  site = self.packages.${pkgs.stdenv.hostPlatform.system};

  # Nothing private is ever exported: no raw Garmin snapshot, no chat, no
  # archive, no purifier. Garmin goes out as the sanitised rollups only.
  forbidden = name: lib.hasPrefix "garmin_" name || lib.elem name [ "chat" "archive" "purifier" ];
  rawGarmin = path: lib.hasInfix "james_garmin" (toString path);

  exportOne = name: path: ''
    ${lib.getExe site.timeline-export} ${lib.escapeShellArg (toString path)} ${lib.escapeShellArg "${cfg.outDirectory}/${name}.duckdb"} \
      || { echo "export of ${name} failed" >&2; failed=1; }
  '';
in
{
  options.services.timeline-export = {
    enable = lib.mkEnableOption "exporting the public sources as per-source DuckDB files";

    sources = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {
        lastfm = "/var/lib/dbs/lastfm/music.db";
        reading = "/var/lib/dbs/api-read/readingList.db";
        parkrun = "/var/lib/dbs/parkrun/parkruns.db";
        chess = "/var/lib/dbs/chess/chess.db";
        garmin = "/var/lib/timeline/garmin-public.sqlite";
      };
      description = ''
        SQLite files to export, by name: each becomes <outDirectory>/<name>.duckdb.
        Only public sources belong here. `garmin` must be the sanitised rollups
        from services.timeline.garmin, never the raw snapshots.
      '';
    };

    outDirectory = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/timeline-export";
      description = "Where the exports land, world-readable, for a web server to serve as static files.";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "*:35";
      description = "OnCalendar expression; the scrapers run every hour or two.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (n: !forbidden n) (lib.attrNames cfg.sources);
        message = "services.timeline-export.sources: raw Garmin, chat, archive and purifier are private and never exported.";
      }
      {
        assertion = lib.all (p: !rawGarmin p) (lib.attrValues cfg.sources);
        message = "services.timeline-export.sources: a raw Garmin snapshot is never exported; point `garmin` at the sanitised rollups.";
      }
    ];

    users.users.timeline-export = {
      isSystemUser = true;
      group = "timeline-export";
    };
    users.groups.timeline-export = { };

    systemd.services.timeline-export = {
      description = "timeline: export the public sources as DuckDB files";
      serviceConfig = {
        Type = "oneshot";
        User = "timeline-export";
        Group = "timeline-export";
        StateDirectory = "timeline-export";
        StateDirectoryMode = "0755";
        UMask = "0022";
        PrivateNetwork = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.outDirectory ];
      };
      # A source that has not been scraped yet is skipped, not a failure of the rest.
      script = ''
        failed=0
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: path: ''
              if [ -r ${lib.escapeShellArg (toString path)} ]; then
                ${exportOne name path}
              else
                echo "${name}: ${toString path} not readable yet, skipped" >&2
              fi
            ''
          ) cfg.sources
        )}
        exit $failed
      '';
    };

    systemd.timers.timeline-export = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
      };
    };
  };
}
