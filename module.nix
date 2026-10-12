{
  config,
  lib,
  ...
}:
let
  cfg = config.services.timeline-embed;
in
{
  options.services.timeline-embed = {
    enable = lib.mkEnableOption "the server that renders timeline's /embed.svg";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The timeline-embed package to run.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to listen on; the web server proxies /embed.svg here.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8790;
      description = "Port to listen on.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.timeline-embed = {
      description = "timeline /embed.svg renderer";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      # Bun otherwise looks for a writable cache directory to keep transpiled
      # sources in, which a DynamicUser service does not have.
      environment.BUN_RUNTIME_TRANSPILER_CACHE_PATH = "0";

      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} --host ${cfg.host} --port ${toString cfg.port}";
        Restart = "on-failure";
        RestartSec = 5;

        DynamicUser = true;
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
  };
}
