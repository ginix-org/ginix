# how services.udev runs, as providers.services units
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
  cfg = config.services.udev;
in
{
  config = lib.mkIf cfg.enable {
    providers.services.units.udevd = {
      description = "device event daemon (${cfg.package.pname})";

      type.service = {
        # `--ready-notify=%n` is gone with the finit stanza: %n is finit substituting the
        # descriptor it chose, which no other init has an equivalent for. Readiness is the
        # daemon being up, and the coldplug unit below waits for it to answer rather than
        # trusting the moment it was spawned.
        command = "${cfg.package}/bin/udevd" + lib.optionalString cfg.debug " -D";
        readiness = "fork";
      };

    };

    # the trigger, which has to happen and is quick, and the wait, which does not and is not.
    #
    # These were one unit everything early in the boot waited for, so nothing else could proceed
    # until the whole device tree had settled. On a laptop with 1319 devices under /sys that is
    # about two seconds, and it is two seconds nothing overlaps: every other early unit finished
    # inside one.
    #
    # Splitting them is what lets the rest of the boot proceed. `udevadm trigger` only queues
    # the events - it returns as soon as the kernel has been asked - so the coldplug follows the
    # daemon straight away, and costs nothing to wait for. The settle is what takes the time,
    # and almost nothing actually needs it.
    providers.services.units.udev-coldplug = {
      description = "trigger coldplug events";

      requires = [ "udevd" ];

      # It needs no logging of its own: udevadm reports to its supervisor, not to /dev/log.
      type.oneshot.command = pkgs.writeShellScript "udev-coldplug" ''
        # udevd is "ready" as soon as it has forked, which is before its control socket
        # exists. The first thing wanting to talk to it therefore waits for an answer.
        until ${cfg.package}/bin/udevadm control --reload 2>/dev/null; do
          ${lib.getExe' pkgs.coreutils "sleep"} 0.1
        done

        ${cfg.package}/bin/udevadm trigger -c add -t devices
        ${cfg.package}/bin/udevadm trigger -c add -t subsystems
      '';
    };

    # and the wait, which nothing waits for unless it says so.
    #
    # This was once something the whole boot waited for, the device tree draining before the
    # rest of it could proceed - about two seconds on a laptop with 1319 devices under /sys, in
    # which nothing else happened. What it bought was an implicit guarantee that anything later
    # had device nodes without saying so, which is a dependency nobody wrote down.
    #
    # It runs for whoever asks for it by name. Most consumers should not. A daemon which
    # subscribes to udev events handles a device appearing late by construction, and one which
    # looks once for a known path wants a `waitFor` - as its readiness, or as a gate oneshot -
    # which says which device and is observable by every implementation of this contract.
    #
    # It exists because some consumers genuinely want the global property and there is no
    # per-device way to express it. Interface renaming is the clearest: `ifupdown-ng` is waiting
    # for `wlan0` to have become `wlp1s0f0`, and what it needs to know is that no further
    # renames are coming - which is the absence of an event, not the presence of a path. keyd
    # grabbing every input device is the same shape. Deleting this and leaving those modules to
    # poll something was tried first and is worse: it replaces one honest wait with several
    # guesses.
    #
    # `devices-settled` is the name every device manager gives its settle, so a consumer names
    # the one thing whichever of them is enabled.
    providers.services.units.devices-settled = {
      description = "wait for the device queue to drain";

      requires = [ "udev-coldplug" ];

      type.oneshot.command = "${cfg.package}/bin/udevadm settle -t 30";
    };
  };
}
