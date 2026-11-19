# the shutdown side, as one script
#
# A `shutdown` unit runs once, on the way down, after every other unit has stopped. That asks
# two things of an implementation - that such a unit runs only during shutdown, and that the
# shutdown units run in the order their `requires` say - and no init reliably offers the second:
#
#   finit  `run` stanzas are ordered against other commands, not against the power-off, so the
#          sequence could be outrun entirely and the machine go down before it executed.
#   dinit  an inverted depends-on chain is correct on paper and not honoured during a full
#          shutdown; the later step ran first.
#   runit  no dependency mechanism and no runlevels at all.
#   s6-rc  the bundle comes up at boot, so the timing is wrong even where the order is right.
#
# So ordering is not asked of the init. The shutdown units are lowered here into a single
# script, in dependency order, and each implementation hands that one script to the single
# point it does reach reliably on the way down - `HOOK_SHUTDOWN` on finit, a latch's
# `stop-command` on dinit, stage 3 on runit, `rc.shutdown` on s6. Ordering becomes the shell's
# job, which is a guarantee that does hold.
#
# The other half is the implementation's own: a shutdown unit is not a process to supervise, so
# it is never emitted as one. It exists only as a step in this script.
{ pkgs, lib }:
rec {
  isShutdown = unit: unit.type ? shutdown;

  # the units an implementation emits and supervises: everything enabled which is not a step
  # in the shutdown script
  bootSideOf = units: lib.filterAttrs (_: u: u.enable && !(isShutdown u)) units;

  # the shutdown units of a configuration, in the order they must run.
  #
  # A topological sort over their `requires`, which the contract restricts to other shutdown
  # units. Ties are broken by name - the input is `attrNames`, which is sorted, and the sort is
  # stable - so the script is the same from one evaluation to the next. A cycle cannot reach
  # here: the contract refuses one across the whole graph.
  orderedFor =
    cfg:
    let
      steps = lib.filterAttrs (_: u: u.enable && isShutdown u) cfg.units;
      named = lib.mapAttrsToList (name: unit: unit // { inherit name; }) steps;
      sorted = lib.toposort (a: b: lib.elem a.name b.requires) named;
    in
    sorted.result or (throw "providers.services: the shutdown units form a cycle");

  # `setpriv` rather than `su`: it becomes the user and their groups and execs, with no PAM
  # session, no login shell and no password database lookup beyond resolving the name. A
  # machine on its way down is the worst place to discover that PAM needs something which has
  # already been stopped.
  #
  # Without this the whole script would run as root, and a step belonging to a unit which asked
  # to run as somebody else would run with more privilege than it asked for - the same failure
  # the contract warns about for `supportedFeatures.user`, arrived at by the back door.
  asUser =
    unit:
    if unit.user == null then
      ""
    else
      "${lib.getExe' pkgs.util-linux "setpriv"} --reuid ${unit.user}"
      + lib.optionalString (unit.group != null) " --regid ${unit.group}"
      + " --init-groups -- ";

  # each step's environment and PATH, the same as a boot-side unit is given them
  stepEnvironment =
    unit:
    lib.optionalString (unit.path != [ ]) "PATH=${lib.makeBinPath unit.path}:$PATH "
    + lib.concatStrings (lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg v} ") unit.environment);

  # null when a configuration has no shutdown units
  scriptFor =
    cfg:
    let
      steps = orderedFor cfg;
    in
    if steps == [ ] then
      null
    else
      pkgs.writeShellScript "providers-services-shutdown" (
        lib.concatMapStringsSep "\n" (unit: ''
          echo "shutdown: ${unit.name}" > /dev/kmsg 2>/dev/null || true
          ${stepEnvironment unit}${asUser unit}${unit.type.shutdown.command}
        '') steps
      );
}
