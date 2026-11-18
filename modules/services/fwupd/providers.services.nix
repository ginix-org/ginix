# how services.fwupd runs, as providers.services units
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
  cfg = config.services.fwupd;
in
{
  config = lib.mkIf cfg.enable {
    providers.services.units.fwupd = {
      description = "firmware update daemon";

      # its state, the bus, the logger, and polkit where there is one - fwupd runs without it,
      # less able to authorise.
      requires = [
        "tmpfiles-setup"
      ]
      ++ config.providers.services.lib.present [
        "dbus"
        "syslogd"
        "polkit"
      ];

      type.service.command =
        "${cfg.package}/libexec/fwupd/fwupd --no-timestamp" + lib.optionalString cfg.debug " --verbose";

      environment = lib.optionalAttrs (config.programs.limine.secureBoot.enable or false) {
        FWUPD_EFIAPPDIR = "${cfg.package}/libexec/fwupd/efi";
      };
    };

    providers.services.tmpfiles.rules =
      map
        (path: {
          type = "directory";
          inherit path;
        })
        [
          "/var/lib/fwupd"
          "/var/cache/fwupd"
        ];
  };
}
