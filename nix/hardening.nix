# The systemd sandbox both instances run in. The unit holds the files it is
# attached to and nothing else; a deployment adds only what its sources need
# (supplementary groups, a state directory).
{
  StateDirectory = "timeline-web";
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
}
