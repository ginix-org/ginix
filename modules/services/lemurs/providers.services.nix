# what services.lemurs runs on its terminal, as a providers.services unit
#
# Separated from the module's own options and configuration so that what this module asks of
# the contract is in one place.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.lemurs;
  device = "tty${toString cfg.settings.tty}";
in
{
  config = lib.mkIf cfg.enable {
    # lemurs takes the terminal it runs on, which is the whole of what it has to say: the getty
    # which would otherwise be there is services.getty's `mkDefault` definition of this same
    # unit, and this overrides it. Disabling that getty separately -
    # `finit.ttys.<dev>.enable = false` - was a thing only finit heard, so on any other init
    # both held the device at once.
    providers.services.units."tty-${device}" = {
      description = "lemurs terminal user interface display/login manager";

      # a greeter: the filesystems, the logger, the bus and polkit, and whichever seat and
      # session managers this machine has
      requires = [
        "tmpfiles-setup"
      ]
      ++ config.providers.services.lib.present [
        "syslogd"
        "dbus"
        "polkit"
        "elogind"
        "sessiond"
        "seatd"
      ];

      type.service = {
        terminal = true;

        # agetty opens the terminal and hands the session to lemurs, which is how a greeter
        # gets a device it can take over
        command = "${pkgs.util-linux}/bin/agetty -nil ${cfg.package}/bin/lemurs ${device}";
      };
    };
  };
}
