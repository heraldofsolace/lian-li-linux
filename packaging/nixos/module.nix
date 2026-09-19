{ config, lib, pkgs, ... }:

let
  cfg = config.services.lianli-linux;
in
{
  options.services.lianli-linux = {
    enable = lib.mkEnableOption "Lian Li Linux (fan, RGB/LED and LCD control for Lian Li hardware)";

    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        The `lian-li-linux` package to use. When this module is imported via
        the flake's `nixosModules.default`, this already defaults to that
        flake's own package; set it explicitly if you import this module
        another way.
      '';
    };

    daemonMode = lib.mkOption {
      type = lib.types.enum [ "none" "user" "system" ];
      default = "none";
      description = ''
        Which `lianli-daemon` service to run, mirroring the two mutually
        exclusive modes documented in docs/service-modes.md:

        - `"none"`: install everything (udev rules, the `lianli` user/group,
          the GUI) but don't start any daemon. Start one yourself with
          `systemctl --user enable --now lianli-daemon.service` (per-user) or
          run it once with the desktop GUI.
        - `"user"`: run `lianli-daemon` as a systemd *user* service in every
          graphical session (equivalent to the packaged
          `lianli-daemon.service`, using `~/.config/lianli/config.json`).
        - `"system"`: run `lianli-daemon --system` as a systemd *system*
          service under the dedicated `lianli` user (equivalent to the
          packaged `lianli-daemon-system.service`, using
          `/var/lib/lianli/config.json`), so hardware is controlled even
          when nobody is logged in.

        Only one mode should be active at a time; both share the same host
        lock at `/run/lianli-daemon.lock`.
      '';
    };

    session.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run `lianli-session --login-start` as a systemd user service in
        every graphical session (equivalent to the packaged
        `lianli-session.service`). This is the desktop-side capture helper
        for EVDI desktop-mode LCDs; it is unrelated to `daemonMode` and can
        be enabled with either daemon mode.
      '';
    };

    evdi.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Load the `evdi` kernel module at boot for EVDI desktop-mode LCDs,
        using nixpkgs' `linuxPackages.evdi`. This only wires up the kernel
        module (equivalent to the packaged
        `packaging/modules-load.d/lianli-evdi.conf`); the matching userspace
        `libevdi.so` is not built by this flake (upstream ships it as a
        separate bundled library built from the DisplayLink/evdi source, see
        `packaging/fedora/lian-li-linux.spec`), so desktop-mode LCDs will
        still report EVDI as unavailable until that library is installed
        some other way.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    services.udev.packages = [ cfg.package ];
    systemd.tmpfiles.packages = [ cfg.package ];

    users.groups.lianli = { };
    users.users.lianli = {
      isSystemUser = true;
      group = "lianli";
      description = "Lian Li daemon";
    };

    systemd.services.lianli-daemon-system = lib.mkIf (cfg.daemonMode == "system") {
      description = "Lian Li Device Daemon (system service)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "lianli";
        Group = "lianli";
        RuntimeDirectory = "lianli";
        StateDirectory = "lianli";
        ExecStart = "${cfg.package}/bin/lianli-daemon --system";
        Restart = "on-failure";
        RestartSec = 5;
        KillMode = "mixed";
        SendSIGKILL = "no";
        TimeoutStopSec = 30;
        NoNewPrivileges = true;
      };
    };

    systemd.user.services.lianli-daemon = lib.mkIf (cfg.daemonMode == "user") {
      description = "Lian Li Device Daemon";
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/lianli-daemon";
        Restart = "on-failure";
        RestartSec = 5;
        KillMode = "mixed";
        SendSIGKILL = "no";
        TimeoutStopSec = 30;
      };
    };

    systemd.user.services.lianli-session = lib.mkIf cfg.session.enable {
      description = "Lian Li desktop session capture";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/lianli-session --login-start";
        Restart = "always";
        RestartSec = 5;
      };
    };

    boot.kernelModules = lib.mkIf cfg.evdi.enable [ "evdi" ];
    boot.extraModulePackages = lib.mkIf cfg.evdi.enable [ config.boot.kernelPackages.evdi ];
  };
}
