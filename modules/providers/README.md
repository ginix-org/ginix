- `providers.` namespace is a mechanism to abstract software implementations from high level concepts
- `providers.scheduler` - a high level abstraction over `cron` (`fcron`, `mcron`, `jobber`, `systemd.timers`, etc...), for example:

```
  providers.scheduler.tasks = {
    logrotate = {
      interval = "hourly";
      command = "${cfg.package}/bin/logrotate ${configFile}";
    };
  };
```

- `providers.services` - a high level abstraction over the init system (`finit`, `dinit`, `systemd`, etc...). Units
  are a dependency graph and nothing else: a unit starts once every unit it requires is ready, and there is no other
  mechanism for starting one - no runlevels, no enablement, no activation events. Dependencies gate starting only, so
  a unit is unaffected by what later happens to what it required. For example:

```
  providers.services.units = {
    pg-init = {
      type.oneshot.command = "${cfg.package}/bin/initdb -D ${cfg.dataDir}";
      requires = [ "tmpfiles-setup" ];
    };

    postgres = {
      type.service = {
        command = "${cfg.package}/bin/postgres -D ${cfg.dataDir}";
        stopTimeout = 120;
      };
      requires = [ "pg-init" ] ++ config.providers.services.lib.present [ "syslogd" ];
    };

    # runs once, on the way down, after everything else has stopped
    pg-cleanup.type.shutdown.command = "${pkgs.coreutils}/bin/rm -f /run/postgresql/.s.PGSQL.*";
  };
```

  Nothing is implied: a unit which requires nothing starts with the boot. Interchangeable implementations define the
  same unit name, so dependants name the concept rather than the implementation - `syslogd` whichever logger is in
  use, `devices-settled` whichever device manager - and `providers.services.lib.present` keeps the names this machine
  has, so a unit can name one without failing where there is none.

- `providers.privileges` - a high level abstraction over `sudo` (`sudo-rs`, `doas`, `please`, etc...), for example:

```
  providers.privileges.rules = [
    { command = "/run/current-system/sw/bin/reboot";
      groups = [ "automation" ];
    }
  ];
```
