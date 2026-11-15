# The oneshot service, user and timer that run the sanitiser over the Garmin
# snapshots and leave the rollups file a server attaches. Each instance gets its
# own file and user, so neither can be pointed at the other's state.
{
  exe,
  name,
  stateName,
  snapshotDir,
  out,
  groups,
  schedule,
}:
{
  service = {
    description = "timeline: publish sanitised Garmin rollups (${name})";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${exe} ${snapshotDir} ${out}";
      # Not DynamicUser: its state directory lives under the 0700 /var/lib/private,
      # which the server's own dynamic user could not traverse to read the result.
      User = name;
      Group = name;
      SupplementaryGroups = groups;
      StateDirectory = stateName;
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

  user = {
    isSystemUser = true;
    group = name;
  };

  timer = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = schedule;
      Persistent = true;
    };
  };
}
