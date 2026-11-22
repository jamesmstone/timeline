# The private timeline instance: the same lane timeline over every source,
# bound to the tailnet. Closed over the flake's own outputs like site-module.nix.
{ self, duckweb }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.timeline-private;
  publicCfg = config.services.timeline;
  system = pkgs.stdenv.hostPlatform.system;
  site = self.packages.${system};
  duckwebPkgs = duckweb.packages.${system};

  sqlStr = v: "'${lib.replaceStrings [ "'" ] [ "''" ] (toString v)}'";

  rollupsFile = "${cfg.garmin.rollupsDirectory}/garmin-rollups.sqlite";

  rollup = import ./nix/garmin-rollup.nix {
    exe = lib.getExe site.garmin-public;
    name = "timeline-private-garmin";
    stateName = "timeline-private";
    snapshotDir = cfg.garmin.directory;
    inherit (cfg.garmin) groups schedule;
    out = rollupsFile;
  };

  # The lane timeline reads the sanitised rollups, as the public instance does.
  # The full snapshots are attached for the SQL box alone.
  sources =
    cfg.sources
    // {
      garmin = rollupsFile;
      garmin_full = "${cfg.garmin.directory}/james_garmin.db";
      garmin_summary = "${cfg.garmin.directory}/james_garmin_summary.db";
      garmin_activities = "${cfg.garmin.directory}/james_garmin_activities.db";
      garmin_monitoring = "${cfg.garmin.directory}/james_garmin_monitoring.db";
      chat = cfg.chat.snapshot;
      purifier = cfg.purifier.snapshot;
    }
    // lib.optionalAttrs (cfg.chat.archive != null) { archive = cfg.chat.archive; };

  # Each source is attached by the path the module is given and by nothing
  # else; see site-module.nix. The purifier is a snapshot in SQLite for the
  # same reason as the Garmin rollups: sqlite_scanner re-opens a file replaced
  # by an atomic rename, and a long-attached DuckDB file does not.
  attaches = lib.mapAttrsToList (
    name: path: "ATTACH ${sqlStr path} AS ${name} (TYPE sqlite, READ_ONLY)"
  ) sources;

  waitForSources = pkgs.writeShellApplication {
    name = "timeline-private-wait";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      for _ in $(seq 1 60); do
        missing=""
        for f in "$@"; do [ -r "$f" ] || missing="$missing $f"; done
        [ -z "$missing" ] && exit 0
        sleep 1
      done
      echo "sources not readable:$missing" >&2
      exit 1
    '';
  };
in
{
  options.services.timeline-private = {
    enable = lib.mkEnableOption "the private timeline instance (every source, tailnet only)";

    address = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address to bind. Loopback by default; a deployment sets the tailnet
        address, and nothing publishes this instance on a public name.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8792;
      description = "Port to listen on.";
    };

    sources = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {
        lastfm = "/var/lib/dbs/lastfm/music.db";
        reading = "/var/lib/dbs/api-read/readingList.db";
        parkrun = "/var/lib/dbs/parkrun/parkruns.db";
        chess = "/var/lib/dbs/chess/chess.db";
      };
      description = ''
        The public sources, attached read-only by catalog name. The lane views
        read these names, so a deployment overrides paths and does not add or
        drop names.
      '';
    };

    garmin = {
      directory = lib.mkOption {
        type = lib.types.path;
        default = "/garmin_datasette";
        description = ''
          Directory with the full Garmin snapshots, attached whole for the SQL
          box as garmin_full, garmin_summary, garmin_activities and
          garmin_monitoring. GPS and raw samples live here.
        '';
      };

      groups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "users" ];
        description = "Supplementary groups the snapshots need, for the server and for the sanitiser.";
      };

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "*:20";
        description = "OnCalendar expression for refreshing the rollups.";
      };

      rollupsDirectory = lib.mkOption {
        type = lib.types.path;
        readOnly = true;
        default = "/var/lib/timeline-private";
        description = "Where the sanitised rollups are written, world-readable.";
      };
    };

    chat = {
      snapshot = lib.mkOption {
        type = lib.types.path;
        default = "/data/seagate/search/dbs/chat.db";
        description = ''
          The chat snapshot, a copy of Synapse's database. Lanes and /chat read
          counts from its events; bodies are reachable through /chat/search and
          the SQL box.
        '';
      };

      archive = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          The frozen chat archive, attached as archive for the SQL box. Off by
          default: it carries FTS tables the scanner has not been tried on.
        '';
      };

      groups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Supplementary groups the server needs to read the chat files.";
      };
    };

    purifier = {
      snapshot = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/timeline-private/purifier.sqlite";
        description = ''
          A SQLite snapshot with the recorder's `status` table, written elsewhere
          by copy-then-rename. The server never opens the recorder's live DuckDB
          file: the recorder opens it read-write every minute and a reader's lock
          would fail those ticks.
        '';
      };

      groups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Supplementary groups the server needs to read the snapshot.";
      };
    };

    quack = {
      enable = lib.mkEnableOption ''
        Quack, DuckDB's client protocol, on this instance's own DuckDB. Whoever holds
        the token can run SQL over every catalog this instance attaches, raw Garmin
        and chat bodies included. Quack has no read-only token: what keeps it read-only
        is the process, whose sources are attached READ_ONLY with file access off
      '';

      address = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Address to listen on; a deployment sets the tailnet address. A wildcard fails evaluation.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 9494;
        description = "Quack port.";
      };

      tokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/secrets/timeline-quack-token";
        description = ''
          File holding the token (at least four characters). It reaches the process as a
          systemd credential and never the Nix store or the command line. Plain HTTP:
          the listener is for the tailnet, which encrypts the hop.
        '';
      };
    };

    memoryMax = lib.mkOption {
      type = lib.types.str;
      default = "3G";
      description = "systemd MemoryMax for the server; the SQL box has no statement timeout, so this is the cap.";
    };

    cpuQuota = lib.mkOption {
      type = lib.types.str;
      default = "400%";
      description = "systemd CPUQuota for the server.";
    };

    memoryLimit = lib.mkOption {
      type = lib.types.str;
      default = "2GB";
      description = "DuckDB's own memory_limit, below memoryMax so a query errors before the unit is killed.";
    };

    threads = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "DuckDB worker threads.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(lib.hasSuffix ".duckdb" (toString cfg.purifier.snapshot));
        message = "services.timeline-private.purifier.snapshot must be a SQLite snapshot, not the recorder's live .duckdb file.";
      }
      {
        assertion = !(lib.elem cfg.address [ "0.0.0.0" "::" "[::]" "" ]);
        message = "services.timeline-private.address must be one interface, not a wildcard: this instance holds private data.";
      }
      {
        assertion = cfg.port != publicCfg.port || !publicCfg.enable;
        message = "services.timeline-private.port clashes with services.timeline.port.";
      }
      {
        assertion = !cfg.quack.enable || cfg.quack.tokenFile != null;
        message = "services.timeline-private.quack.enable needs quack.tokenFile.";
      }
      {
        assertion = !(lib.elem cfg.quack.address [ "0.0.0.0" "::" "[::]" "" ]);
        message = "services.timeline-private.quack.address must be one interface, not a wildcard.";
      }
    ];

    services.duckweb.enable = true;
    services.duckweb.servers.timeline-private = {
      inherit (cfg) address port memoryMax;
      extensions = [
        duckwebPkgs.duckweb.extensionFile
        duckwebPkgs.svg-charts.extensionFile
        "${site.sqlite-scanner}/sqlite_scanner.duckdb_extension"
      ]
      ++ lib.optionals cfg.quack.enable [
        "${site.httpfs}/httpfs.duckdb_extension"
        "${site.quack}/quack.duckdb_extension"
      ];
      setup = [
        "SET memory_limit = ${sqlStr cfg.memoryLimit}"
        "SET threads = ${toString cfg.threads}"
        "SET temp_directory = '/var/lib/timeline-private-web/tmp'"
        "SET max_temp_directory_size = '4GB'"
      ]
      ++ attaches
      ++ [
        ".read ${site.app}/views-shared.sql"
        ".read ${site.app}/views-garmin.sql"
        ".read ${site.app}/views-chat.sql"
        ".read ${site.app}/views-air.sql"
        ".read ${site.app}/views-garmin-raw.sql"
        ".read ${site.app}/lanes-private.sql"
        ".read ${site.app}/examples-public.sql"
        ".read ${site.app}/examples-private.sql"
        ".read ${site.app}/instance-private.sql"
        ".read ${site.app}/core.sql"
        ".read ${site.app}/embed.sql"
        ".read ${site.app}/routes-private.sql"
      ]
      ++ lib.optionals cfg.quack.enable [
        # quack_serve prints the token it was given; the journal is not for that.
        "SET VARIABLE quack_token = (SELECT trim(content, chr(10) || chr(13) || ' ') FROM read_text('/run/credentials/duckweb-timeline-private.service/quack-token'))"
        ".output /dev/null"
        "CALL quack_serve(${sqlStr "quack:${cfg.quack.address}:${toString cfg.quack.port}"}, token = getvariable('quack_token'), allow_other_hostname = true, disable_ssl = true)"
        ".output"
      ]
      ++ [
        # Last, as in the public instance: the SQL box reaches every catalog
        # above and nothing outside them.
        "SET enable_external_access = false"
      ];
      sites.timeline-private = {
        assets = site.assets;
        searchPath = "memory.main," + lib.concatStringsSep "," (map (n: "${n}.main") (lib.attrNames sources));
      };
    };

    systemd.services.duckweb-timeline-private = {
      wants = [ "timeline-private-garmin.service" ];
      after = [ "timeline-private-garmin.service" ];
      # The snapshots arrive from other units, and Garmin's rewrites its
      # directory in place, so a missing file is a wait, not a failure of the
      # configuration. Without this the unit would burn its start limit.
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = (import ./nix/hardening.nix) // {
        StateDirectory = "timeline-private-web";
        LoadCredential = lib.mkIf cfg.quack.enable "quack-token:${toString cfg.quack.tokenFile}";
        CPUQuota = cfg.cpuQuota;
        SupplementaryGroups = cfg.garmin.groups ++ cfg.chat.groups ++ cfg.purifier.groups;
        ExecStartPre = "${lib.getExe waitForSources} ${lib.escapeShellArgs (lib.attrValues (lib.removeAttrs sources [ "garmin" ]))}";
        RestartSec = 30;
      };
    };

    systemd.services.timeline-private-garmin = rollup.service;
    users.users.timeline-private-garmin = rollup.user;
    users.groups.timeline-private-garmin = { };
    systemd.timers.timeline-private-garmin = rollup.timer;
  };
}
