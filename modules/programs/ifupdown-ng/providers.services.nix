# how programs.ifupdown-ng runs, as providers.services units
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
  cfg = config.programs.ifupdown-ng;
in
{
  config = lib.mkIf cfg.enable {
    providers.services.units.ifupdown-ng = {
      description = "bring up network interfaces";

      # the logger - which is what the old `service/syslogd/ready` condition said - its state,
      # and the firewall where there is one: an interface coming up is the machine becoming
      # reachable, which it should not be before its ruleset is loaded.
      #
      # The device manager's settle is named outright, because this is one of the few things
      # that genuinely wants the global property rather than a device. Interfaces are renamed by
      # the device manager - `wlan0` becomes `wlp1s0f0` - and what this needs to know is that no
      # further renames are coming. That is the absence of an event, so there is no path to wait
      # for: `waitFor.path` cannot express it and the settle is the only thing that can. Bringing
      # up an interface under a name that is about to change is a configuration applied to
      # nothing.
      requires = [
        "tmpfiles-setup"
      ]
      ++ config.providers.services.lib.present [
        "syslogd"
        "nftables"
        "devices-settled"
      ];

      type.oneshot.command = pkgs.writeShellScript "ifup" ''
        ${lib.concatMapStrings (iface: ''
          # `net/${iface}/exist` was a finit netlink condition, which nothing else has. The
          # portable form of the same question is whether the kernel has made the directory.
          #
          # Bounded, and deliberately: an unsatisfied finit condition meant the task simply
          # never ran and the boot carried on, but a unit is something whatever requires it waits
          # for - so an unbounded wait for a NIC which is not present would stall
          # the boot rather than skip the interface.
          for _ in $(${lib.getExe' pkgs.coreutils "seq"} 1 100); do
            [ -d /sys/class/net/${iface} ] && break
            ${lib.getExe' pkgs.coreutils "sleep"} 0.1
          done
        '') cfg.auto}
        exec ${cfg.package}/bin/ifup -E ${cfg.package}/libexec/ifupdown-ng ${lib.escapeShellArgs cfg.extraArgs}
      '';
    };

    providers.services.units.ifupdown-ng-down = {
      description = "bring down network interfaces";
      type.shutdown.command = pkgs.writeShellScript "ifdown" ''
        ${cfg.package}/bin/ifdown -E ${cfg.package}/libexec/ifupdown-ng ${lib.escapeShellArgs cfg.extraArgs}
      '';
    };
  };
}
