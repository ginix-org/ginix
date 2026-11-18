# what services.getty runs on each terminal, as providers.services units
#
# A terminal is claimed by its unit's name: `tty-<device>`. This module offers a login prompt on
# each of its ttys with the parts that say what runs there - command, description, requires - at
# `mkDefault`, so a display manager or an autologin claims a device simply by defining that unit
# with a command of its own. Nothing has to be subtracted from anything, and nothing has to know
# which init is running. Two of them claiming one device is a merge conflict which names both.
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
  cfg = config.services.getty;

  loginLib = import ./login.nix { inherit pkgs lib; };

  commandFor =
    device: autologin:
    loginLib.commandFor {
      inherit device autologin;
      inherit (cfg) package args extraArgs;
    };

  # the autologin, where one is asked for: the first of the ttys, at normal priority so that it
  # wins over this module's own prompt for that device - the mechanism above, used rather than
  # worked around. A display manager wanting the same terminal still wins the ordinary way, by
  # saying so.
  autologinDevice = if cfg.autologinUser != null then lib.head cfg.ttys else null;
in
{
  config = lib.mkIf cfg.enable {
    providers.services.units = lib.genAttrs (map (device: "tty-${device}") cfg.ttys) (
      unit:
      let
        device = lib.removePrefix "tty-" unit;
      in
      {
        # above the contract's own default of the unit's name, and below any definition - so a
        # display manager claiming the terminal replaces it without having to force anything
        description = lib.mkOverride 900 "getty on /dev/${device}";

        # what a session needs: the filesystems it lives on - /home among them - the logger, and
        # whichever session tracker this machine has, which is what PAM registers the session
        # with. Not every daemon on the machine, which is what this used to wait for: a prompt
        # is useful as soon as somebody can log in at it.
        requires = lib.mkDefault (
          [ "tmpfiles-setup" ]
          ++ config.providers.services.lib.present [
            "syslogd"
            "elogind"
            "sessiond"
            "seatd"
          ]
        );

        type.service = {
          # whatever runs here opens the device and makes it its stdio, so its output is the
          # terminal's and not the log's - and capturing it anyway breaks every login
          terminal = true;

          command =
            if device == autologinDevice then
              # the getty's own `args` says how it logs a user in, or throws if it cannot -
              # busybox's has no autologin at all
              commandFor device cfg.autologinUser
            else
              lib.mkDefault (commandFor device null);
        };
      }
      // lib.optionalAttrs (device == autologinDevice) {
        description = "autologin as ${cfg.autologinUser} on /dev/${device}";
      }
    );
  };
}
