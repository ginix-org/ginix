# how services.keyd runs, as providers.services units
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
  cfg = config.services.keyd;
in
{
  config = lib.mkIf cfg.enable {
    providers.services.units.keyd = {
      description = "keyd, a key remapping daemon";

      # The device manager's settle, named outright.
      #
      # keyd opens every keyboard under /dev/input and grabs it, which is a look-once
      # enumeration of a set rather than a wait for one device - so `waitFor.path` has nothing
      # to name, and a keyboard whose driver probes late is simply one keyd never grabbed. This
      # once worked because the boot waited for the settle before anything later started; it
      # does not any more, and the dependency is real, so it is written down.
      requires = [
        "tmpfiles-setup"
      ]
      ++ config.providers.services.lib.present [
        "syslogd"
        "devices-settled"
      ];

      # keyd reads /etc/keyd and names none of it, so every file the tree was generated
      # from is listed: a changed keymap is then a changed unit. It has a `reload` below,
      # so that is a re-read rather than a restart - which matters here, since restarting
      # keyd drops the grabs on every keyboard.
      type.service.reloadTriggers = lib.mapAttrsToList (_: v: v.source) cfg.configTree;

      type.service = {
        command = "${cfg.package}/bin/keyd";

        # keyd is asked to re-read its own configuration, so a changed keymap no longer drops
        # the grabs on every keyboard
        reload = "${cfg.package}/bin/keyd reload";
      };

      environment = lib.optionalAttrs cfg.debug { KEYD_DEBUG = "2"; };
    };
  };
}
