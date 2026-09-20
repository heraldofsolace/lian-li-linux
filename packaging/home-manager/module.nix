{ config, lib, pkgs, ... }:

let
  cfg = config.services.lianli-linux;
in
{
  options.services.lianli-linux = {
    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        The `lian-li-linux` package to use. When this module is imported via
        the flake's `homeManagerModules.default`, this already defaults to
        that flake's own package; set it explicitly if you import this
        module another way.
      '';
    };

    session.enable = lib.mkEnableOption ''
      the Lian Li desktop session capture helper (lianli-session
      --login-start, equivalent to the packaged lianli-session.service) as
      a per-user systemd service started automatically at every graphical
      login. This is the desktop-side capture for EVDI desktop-mode LCDs;
      it is unrelated to lianli-daemon itself, which the flake's NixOS
      module (services.lianli-linux.daemonMode) or your own unit handles
    '';
  };

  config = lib.mkIf cfg.session.enable {
    systemd.user.services.lianli-session = {
      Unit = {
        Description = "Lian Li desktop session capture";
        ConditionUser = "!root";
      };
      Service = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/lianli-session --login-start";
        Restart = "always";
        RestartSec = 5;
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
