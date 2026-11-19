# how services.uptime-kuma runs, as providers.services units
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
  cfg = config.services.uptime-kuma;
in
{
  config = lib.mkIf cfg.enable {
    providers.services.units.uptime-kuma = {
      inherit (cfg) user group;

      description = "uptime kuma";

      # a route, since what it monitors is elsewhere; the logger; and the firewall where there
      # is one, since this is the machine listening
      requires = [
        "tmpfiles-setup"
        "network-online"
      ]
      ++ config.providers.services.lib.present [
        "syslogd"
        "nftables"
      ];

      # `kill = 10` becomes the contract's stopTimeout, which every implementation bounds
      # except runit - and says so.
      type.service.stopTimeout = lib.mkDefault 10;

      # uptime-kuma runs ping by name for its monitors
      path = [ pkgs.unixtools.ping ];

      type.service.command = lib.getExe cfg.package;

      # the settings are typed as what they are - PORT is a `types.port`, which is a number -
      # and an environment is strings. Converted here, at the boundary where one becomes the
      # other, rather than by weakening the option to `str` and losing the check.
      environment = lib.mapAttrs (
        _: v: if lib.isBool v then lib.boolToString v else toString v
      ) cfg.settings;
    };

    providers.services.tmpfiles.rules = lib.optional (cfg.settings.DATA_DIR == "/var/lib/uptime-kuma") {
      path = cfg.settings.DATA_DIR;
      type.directory = {
        mode = "0750";
        inherit (cfg) user group;
      };
    };
  };
}
