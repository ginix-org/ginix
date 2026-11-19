# the `waitFor` readiness kinds, as a command which blocks until the unit is live
#
# Imported by the implementations rather than reached through an option, because it is a
# function and every one of them needs the same answer: given a unit's waitFor, a program which
# returns once that unit is genuinely up. Modules get the bare waits as
# `providers.services.lib.waitFor`, for a oneshot whose whole job is to wait.
#
# Where a backend has a native mechanism for a kind it should use that instead - finit and
# dinit both observe a forking daemon directly - and fall back to this for the rest. What each
# of them does with the command differs: finit runs it as the unit's companion task, runit
# inside the run script, s6 before notifying on its descriptor. The waiting itself is the same
# everywhere, so it is written once.
#
# What this returns is an argv, not a script. It used to generate shell per unit, and the shell
# was correct about what to wait for and could not be correct about how: it polled on a
# whole-second interval because that is what `sleep` takes, it used inotify to avoid that and
# could not close the window between arming a backgrounded watch and re-checking, and every
# attempt cost a fork - bash, dirname, inotifywait, socat, sleep - on every dependency edge in
# the system. `finix-wait` is one static binary doing the same waiting in a few microseconds
# per check; see pkgs/finix-wait/src/main.rs for why it polls rather than watching.
{
  pkgs,
  lib,
}:
let
  finixWait = lib.getExe (pkgs.callPackage ../../../pkgs/finix-wait { });

  # these end up in a backend's own config format, and dinit's `command` is split on whitespace
  # honouring double quotes and not single ones - so a path with a space in it cannot be passed
  # through as one argument whatever is done to it here. Refused where it is written rather than
  # mis-split where it is read.
  arg =
    name: path:
    if builtins.match ".*[[:space:]].*" path != null then
      throw "providers.services.units.${name}: readiness path '${path}' contains whitespace, which cannot survive a backend's command line"
    else
      path;
in
rec {
  # blocks until `path` exists. Also how a unit waits for its dependencies' latches, which is
  # the highest-volume caller: one of these per edge, per unit, on every backend.
  #
  # The trailing newline is part of the contract and not decoration: callers concatenate these
  # with no separator - `lib.concatMapStrings (dep: waitForPath (latch dep)) unit.requires` -
  # which worked when this returned a multi-line shell block and silently did not when it became
  # one line. Two waits then ran together into `...a.readyfinix-wait path ...b.ready`, which is
  # five arguments rather than two, so every unit with more than one dependency printed a usage
  # message and latched nothing.
  waitForPath = path: "${finixWait} path ${arg "<latch>" path}\n";

  # each wait as a command, for a module to use as a oneshot's - which is how a unit gates its
  # dependants on something appearing. Exposed as `providers.services.lib.waitFor`.
  #
  # `check` is not here: its command does its own waiting, so as a oneshot it is simply the
  # command.
  waitFor = waitForNamed "<waitFor>";

  # the same, with the unit's name for the error a bad path raises
  waitForNamed = name: {
    path = path: "${finixWait} path ${arg name path}";
    socket = path: "${finixWait} socket ${arg name path}";
    pidfile = file: "${finixWait} pidfile ${arg name file}";
  };

  # null when the kind needs no command - either the unit reports readiness itself, or the
  # backend is expected to observe it natively
  scriptFor =
    name: readiness:
    let
      kind = lib.head (lib.attrNames readiness);
      spec = readiness.waitFor or null;
      wait = if spec == null then null else lib.head (lib.attrNames spec);
      named = waitForNamed name;
    in
    if kind != "waitFor" then
      null

    else if wait == "check" then
      # the command does its own waiting; returning is the signal
      spec.check.command

    else if wait == "socket" then
      named.socket spec.socket.path

    else if wait == "pidfile" then
      named.pidfile spec.pidfile.file

    else
      named.path spec.path.path;
}
