# Closed over the flake's own outputs so the defaults resolve for whatever
# system the host is.
{ self, duckweb }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.timeline;
  system = pkgs.stdenv.hostPlatform.system;
  site = self.packages.${system};
  duckwebPkgs = duckweb.packages.${system};

  sqlStr = v: "'${lib.replaceStrings [ "'" ] [ "''" ] (toString v)}'";

  garminDb =
    if cfg.garmin.enable then
      "${cfg.garmin.stateDirectory}/garmin-public.sqlite"
    else
      site.garmin-empty;

  # Each source is attached by the path the module is given and by nothing
  # else, and the attach set is the permission boundary: this process holds no
  # descriptor for a file it was not handed, whatever SQL arrives on /sql.
  attaches = lib.mapAttrsToList (
    name: path: "ATTACH ${sqlStr path} AS ${name} (TYPE sqlite, READ_ONLY)"
  ) (cfg.sources // { garmin = garminDb; });
in
{
  options.services.timeline = {
    enable = lib.mkEnableOption "the public timeline site (duckweb over the public-safe sources)";

    address = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address to bind. Loopback by default: the edge that fronts the site reaches
        it over the tailnet, so a deployment sets this to the tailnet address.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8791;
      description = "Port to listen on.";
    };

    sources = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {
        lastfm = "/var/lib/datasette-sites/lastfm/music.db";
        reading = "/var/lib/datasette-sites/api-read/readingList.db";
        parkrun = "/var/lib/datasette-sites/parkrun/parkruns.db";
        chess = "/var/lib/datasette-sites/chess/chess.db";
      };
      description = ''
        SQLite files attached read-only, by catalog name. These names are what
        the lane views read, so a deployment overrides paths and does not add
        or drop names. Nothing private belongs here: whatever is attached can
        be queried from /sql.
      '';
    };

    garmin = {
      enable = lib.mkEnableOption "publishing sanitised Garmin rollups (sleep nights and daily aggregates, no GPS and no raw samples)";

      snapshotDir = lib.mkOption {
        type = lib.types.path;
        default = "/garmin_datasette";
        description = "Directory with the full Garmin snapshots the sanitiser reads.";
      };

      groups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "users" ];
        description = "Supplementary groups the sanitiser needs to read the snapshots.";
      };

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "*:20";
        description = "OnCalendar expression for refreshing the public set; Garmin is scraped every few hours.";
      };

      stateDirectory = lib.mkOption {
        type = lib.types.path;
        readOnly = true;
        default = "/var/lib/timeline";
        description = "Where the sanitised file is written, world-readable.";
      };
    };

    memoryMax = lib.mkOption {
      type = lib.types.str;
      default = "1G";
      description = "systemd MemoryMax for the server; the public SQL box has no statement timeout, so this is the cap.";
    };

    cpuQuota = lib.mkOption {
      type = lib.types.str;
      default = "200%";
      description = "systemd CPUQuota for the server.";
    };

    memoryLimit = lib.mkOption {
      type = lib.types.str;
      default = "768MB";
      description = "DuckDB's own memory_limit, below memoryMax so a query errors before the unit is killed.";
    };

    threads = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "DuckDB worker threads.";
    };
  };

  imports = [ duckweb.nixosModules.duckweb ];

  config = lib.mkIf cfg.enable {
    services.duckweb.enable = true;
    services.duckweb.servers.timeline = {
      inherit (cfg) address port memoryMax;
      extensions = [
        duckwebPkgs.duckweb.extensionFile
        "${site.sqlite-scanner}/sqlite_scanner.duckdb_extension"
      ];
      setup = [
        "SET memory_limit = ${sqlStr cfg.memoryLimit}"
        "SET threads = ${toString cfg.threads}"
        "SET temp_directory = '/var/lib/timeline-web/tmp'"
        "SET max_temp_directory_size = '1GB'"
      ]
      ++ attaches
      ++ [
        ".read ${site.app}/views.sql"
        ".read ${site.app}/app.sql"
        # Last, so everything above could still read files. duckweb_serve runs
        # after setup and sets preserve_insertion_order itself, which a locked
        # configuration refuses, so the lock is not taken; the SQL box only ever
        # runs a single SELECT, which cannot SET anything.
        "SET enable_external_access = false"
      ];
      sites.timeline = {
        assets = site.assets;
        searchPath =
          "memory.main,"
          + lib.concatStringsSep "," (map (n: "${n}.main") (lib.attrNames cfg.sources ++ [ "garmin" ]));
      };
    };

    systemd.services.duckweb-timeline = {
      wants = lib.mkIf cfg.garmin.enable [ "timeline-garmin-public.service" ];
      after = lib.mkIf cfg.garmin.enable [ "timeline-garmin-public.service" ];
      serviceConfig = {
        StateDirectory = "timeline-web";
        CPUQuota = cfg.cpuQuota;
        TasksMax = 256;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
      };
    };

    systemd.services.timeline-garmin-public = lib.mkIf cfg.garmin.enable {
      description = "timeline: publish sanitised Garmin rollups";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe site.garmin-public} ${cfg.garmin.snapshotDir} ${cfg.garmin.stateDirectory}/garmin-public.sqlite";
        # Not DynamicUser: its state directory lives under the 0700 /var/lib/private,
        # which the server's own dynamic user could not traverse to read the result.
        User = "timeline-garmin";
        Group = "timeline-garmin";
        SupplementaryGroups = cfg.garmin.groups;
        StateDirectory = "timeline";
        StateDirectoryMode = "0755";
        UMask = "0022";
        # Reads one directory and writes one file; it never needs the network.
        PrivateNetwork = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    users.users.timeline-garmin = lib.mkIf cfg.garmin.enable {
      isSystemUser = true;
      group = "timeline-garmin";
    };
    users.groups.timeline-garmin = lib.mkIf cfg.garmin.enable { };

    systemd.timers.timeline-garmin-public = lib.mkIf cfg.garmin.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.garmin.schedule;
        Persistent = true;
      };
    };
  };
}
