# the hostname and the wait for a route, as providers.services units
#
# Separated from the module's own options and configuration so that what it asks of the
# contract is in one place, the same way a module implementing a `providers.*` contract keeps
# its implementation in a file named for it.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = {
    providers.services.units.set-hostname = {
      description = "apply the configured hostname";
      type.oneshot.command = "${lib.getExe' pkgs.nettools "hostname"} -F /etc/hostname";

      # requires nothing, so it starts with the boot. Anything which logs or announces the
      # name - the logger, mDNS - names this unit.
    };

    providers.services.units.network-online = {
      description = "wait for a default route";

      # after whichever of the things that make a route this machine has, since a wait which
      # starts before them cannot observe what it is waiting for.
      #
      # It once ran a tier ahead of dhcpcd and iwd - so it ran before anything had tried to bring
      # a link up, could only pass on a machine which already had a route, and on a wireless one
      # spent its whole five seconds and gave up every boot. That made it two things at once: a
      # wait which could not observe what it was waiting for, and five seconds in front of
      # everything later, including a login prompt. A machine with no route took five seconds
      # longer to show anybody anything, for a check that had already failed.
      #
      # Nothing waits for it unless it says so, so a unit which genuinely needs a route still
      # waits, and nothing which merely needs a session does.
      requires = config.providers.services.lib.present [
        "ifupdown-ng"
        "dhcpcd"
        "network-manager"
        "iwd"
      ];

      type.oneshot.command = pkgs.writeShellScript "network-online" ''
        for _ in $(${lib.getExe' pkgs.coreutils "seq"} 1 50); do
          if [ -s /proc/net/route ] && ${lib.getExe' pkgs.gnugrep "grep"} -qE '^[^	]+	00000000	' /proc/net/route; then
            exit 0
          fi
          ${lib.getExe' pkgs.coreutils "sleep"} 0.1
        done

        echo "network-online: no default route after 5s, continuing" >&2
      '';
    };
  };
}
