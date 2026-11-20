# Per-source DuckDB exports of the public sources, for the browser's worker: a web
# server serves outDirectory as plain files and the worker attaches them by range request.
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
        SQLite files to export, by name: each becomes <outDirectory>/v/<hash>/<name>.duckdb.
        Only public sources belong here. `garmin` must be the sanitised rollups
        from services.timeline.garmin, never the raw snapshots.
      '';
    };

    outDirectory = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/timeline-export";
      description = ''
        Where the exports land, world-readable, for a web server to serve as /data: `version`
        names the newest of the `v/<hash>/` directories, each with every source and app.duckdb.
      '';
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
        assertion = lib.sort lib.lessThan (lib.attrNames cfg.sources) == [ "chess" "garmin" "lastfm" "parkrun" "reading" ];
        message = "services.timeline-export.sources must be exactly the five the page's macros read: chess, garmin, lastfm, parkrun, reading.";
      }
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
      script = "${lib.getExe site.timeline-export} ${lib.escapeShellArg cfg.outDirectory} ${
        lib.escapeShellArgs (lib.mapAttrsToList (name: path: "${name}=${toString path}") cfg.sources)
      }";
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
