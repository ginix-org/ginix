# how services.networkmanager runs, as providers.services units
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
  cfg = config.services.networkmanager;
in
{
  config = lib.mkIf cfg.enable {
    providers.services.units.network-manager = {
      description = "network manager service";

      # the bus, which is how it is driven, its state, the logger, and the firewall where there
      # is one. wpa_supplicant is named so that it is on the bus before NetworkManager first
      # looks for it, rather than NetworkManager starting with wifi unavailable and waiting for
      # the name to appear.
      requires = [
        "tmpfiles-setup"
      ]
      ++ config.providers.services.lib.present [
        "dbus"
        "syslogd"
        "nftables"
        "wpa_supplicant"
      ];

      # read from a fixed path and named nowhere else, so a changed configuration
      # would otherwise leave the daemon running with the old one
      type.service.reloadTriggers = [ cfg.configFile ];

      type.service = {
        # the config is named here because nothing else in the unit mentions it: NetworkManager
        # reads /etc/NetworkManager/conf.d and takes no argument saying so, so without this a
        # changed 00-nixos.conf left the unit identical, the switch found nothing to do, and the
        # reload below could never fire. The daemon would go on running the settings it was
        # started with until something else happened to restart it.
        command = "${cfg.package}/bin/NetworkManager -n";

        # and it is a reload rather than a restart: NetworkManager rereads its configuration on
        # SIGHUP, so a switch which only changed settings keeps the interfaces up instead of
        # taking the network down and bringing it back.
        reload = "${lib.getExe' pkgs.procps "pkill"} -HUP -x NetworkManager";
      };
    };
  };
}
