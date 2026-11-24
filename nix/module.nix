{ self }:
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  cfg = config.services.blueferry;
  btcfg = config.hardware.bluetooth;

  # Mirrors packaging/arch/blueferry-bluetooth.conf: BlueFerry's ANCS bearer
  # needs BlueZ's experimental Bearer.LE1/BREDR1 interfaces, so bluetoothd
  # must run with -E/--experimental. NixOS builds bluetoothd's ExecStart from
  # hardware.bluetooth.disabledPlugins itself (see
  # nixos/modules/services/hardware/bluetooth.nix); rebuild the same argv
  # here so that option keeps working, then add --experimental and override.
  bluetoothdArgs = [
    "-f"
    "/etc/bluetooth/main.conf"
  ]
  ++ lib.optional (
    btcfg.disabledPlugins != [ ]
  ) "--noplugin=${lib.concatStringsSep "," btcfg.disabledPlugins}"
  ++ [ "--experimental" ];
in
{
  options.services.blueferry = {
    enable = lib.mkEnableOption "BlueFerry, the iPhone-to-Linux Bluetooth bridge";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.blueferry;
      defaultText = lib.literalExpression "blueferry.packages.\${pkgs.stdenv.hostPlatform.system}.blueferry";
      description = "The BlueFerry package (backend + GTK client) to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.bluetooth.enable = lib.mkDefault true;

    systemd.services.bluetooth.serviceConfig.ExecStart = lib.mkForce [
      ""
      "${btcfg.package}/libexec/bluetooth/bluetoothd ${utils.escapeSystemdExecArgs bluetoothdArgs}"
    ];

    # blueferry-gtk performs first-run pairing through Polkit-authorized
    # helpers (see src/blueferry/bluez_setup.py, bluetooth_capabilities.py).
    security.polkit.enable = true;

    # Makes the CLI/TUI/GTK client available on PATH and installs the
    # desktop entry, icon, and AppStream metainfo via the system profile.
    environment.systemPackages = [ cfg.package ];

    # Registers io.weirdware.BlueFerry.xml and the session D-Bus service
    # file (share/dbus-1/services) so opening the GTK client D-Bus-activates
    # the backend; see the systemd.user.services.blueferry unit below.
    services.dbus.packages = [ cfg.package ];

    # A user-instance unit, not a system service: it runs as the desktop
    # user and talks to BlueZ over the session's system-bus proxy. Content
    # mirrors the packaged systemd/blueferry.service, with ExecStart
    # pointed at this closure instead of /usr/bin.
    systemd.user.services.blueferry = {
      description = "BlueFerry — iPhone <-> Linux Bluetooth bridge";
      unitConfig = {
        # Only users who completed pairing have configuration and should
        # start a daemon.
        ConditionPathExists = "%h/.config/blueferry/local.env";
      };
      serviceConfig = {
        Type = "dbus";
        BusName = "io.weirdware.BlueFerry";
        ExecStart = "${cfg.package}/bin/blueferry run";
        Restart = "on-failure";
        # EX_TEMPFAIL is the daemon's deliberate package-upgrade restart
        # request.
        RestartForceExitStatus = 75;
        RestartSec = 5;
        # The worker cancels queued jobs, then lets one in-flight Bluetooth
        # operation and its session cleanup finish. Incoming transfers have
        # a 120-second bound.
        TimeoutStopSec = 180;
        UMask = "0077";
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        PrivateDevices = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        # Python's D-Bus/GObject bindings may use libffi executable
        # trampolines, so MemoryDenyWriteExecute is intentionally omitted.
        RestrictNamespaces = true;
        SystemCallArchitectures = "native";
        # The backend reaches Bluetooth exclusively through local D-Bus
        # sockets; it never needs IP networking or raw AF_BLUETOOTH sockets.
        RestrictAddressFamilies = "AF_UNIX";
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };
}
