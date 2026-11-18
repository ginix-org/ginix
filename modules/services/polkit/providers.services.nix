# how services.polkit runs, as providers.services units
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
  cfg = config.services.polkit;
in
{
  # the agent, in every user's tree. Said by extending the tree's own submodule rather than by
  # defining `providers.services.users.<name>` for a list of names: which users have trees is
  # whatever the rest of the machine declares, and reading that back to decide what to declare
  # into it is a recursion. A submodule extension is merged into each tree that exists and
  # creates none that does not.
  options.providers.services.users = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config.units.polkit-agent = lib.mkIf (cfg.enable && cfg.agent.enable) {
          description = "polkit authentication agent";
          type.service.command = cfg.agent.command;
        };
      }
    );
  };

  config = lib.mkIf cfg.enable {
    providers.services.units.polkit = {
      description = "policykit authorization manager";

      # the bus, the logger, and whichever of the session trackers this machine has: polkit
      # answers "is this an active local session", which it asks of them.
      requires = [
        "tmpfiles-setup"
      ]
      ++ config.providers.services.lib.present [
        "dbus"
        "syslogd"
        "elogind"
        "sessiond"
      ];

      type.service.command =
        "${cfg.package.out}/lib/polkit-1/polkitd --no-debug "
        + lib.optionalString cfg.debug "--log-level=debug";
    };
  };
}
