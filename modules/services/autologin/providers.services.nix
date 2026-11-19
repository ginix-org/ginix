# what services.autologin runs on its terminal, as a providers.services unit
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
  cfg = config.services.autologin;
in
{
  config = lib.mkIf cfg.enable {
    # autologin is hardcoded to run on tty1, so it claims it - by defining `tty-tty1`, the unit
    # services.getty offers its prompt as at `mkDefault`. That claim is the whole of what used
    # to be `finit.ttys.tty1.enable = lib.mkForce false` plus a service of its own - and the
    # force only ever reached finit, so on any other init a getty held tty1 at the same time and
    # the two fought over the keyboard.
    providers.services.units.tty-tty1 = {
      description = "autologin";

      # what any login prompt waits for: the filesystems a session lives on, the logger, and
      # whichever session tracker this machine has, which is what PAM registers the session
      # with. It used to name five things one at a time and then none, leaving it to a tier;
      # these are the ones a session actually uses. The device manager is not among them: a
      # login prompt needs a tty, which is devtmpfs, not an enumerated device.
      requires = [
        "tmpfiles-setup"
      ]
      ++ config.providers.services.lib.present [
        "syslogd"
        "elogind"
        "sessiond"
        "seatd"
      ];

      type.service = {
        terminal = true;

        # the redirect is autologin's own business: unlike a getty it does not take a device,
        # so the terminal has to be its standard streams before it is exec'd. Which is what
        # finit was arranging on its behalf when this was a `tty` stanza with no command.
        command = pkgs.writeShellScript "autologin-tty1" ''
          exec </dev/tty1 >/dev/tty1 2>&1
          exec ${lib.getExe pkgs.autologin} ${cfg.user} ${cfg.command}
        '';
      };
    };
  };
}
