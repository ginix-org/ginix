# how services.ddccontrol runs, as providers.services units
#
# Separated from the module's own options and configuration so that what this module asks of
# the service contract is in one place, the same way a module implementing a `providers.*`
# contract keeps its implementation in a file named for it.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.ddccontrol;
in
{
  config = lib.mkIf cfg.enable {
    providers.services.units.ddccontrol = {
      description = "control monitor parameters, like brightness, contrast, and other...";

      # the bus, which is how it is reached, and the logger
      requires = [
        "tmpfiles-setup"
      ]
      ++ config.providers.services.lib.present [
        "syslogd"
        "dbus"
      ];

      type.service.command = "${pkgs.ddccontrol}/libexec/ddccontrol/ddccontrol_service";
    };
  };
}
