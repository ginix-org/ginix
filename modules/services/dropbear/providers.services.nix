# how services.dropbear runs, as providers.services units
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
  cfg = config.services.dropbear;
  stateDir = "/var/lib/dropbear";

in
{
  config = lib.mkIf cfg.enable {
    providers.services.units.dropbear-keygen = {
      description = "generate ssh host keys";

      # before anything can serve with them, and after the filesystem they are kept on
      requires = [ "tmpfiles-setup" ];

      type.oneshot.command =
        let
          script = lib.concatMapStringsSep "\n" (key: ''
            if ! [ -s "${key.path}" ]; then
              ${cfg.package}/bin/dropbearkey -t ${key.type} -f "${key.path}" ${
                lib.optionalString (key.bits != null) "-s ${toString key.bits}"
              } ${lib.optionalString (key.comment != null) "-C \"${key.comment}\""}
            fi
          '') config.services.dropbear.hostKeys;
        in
        pkgs.writeShellScript "ssh-keygen.sh" script;
    };

    providers.services.units.dropbear = {
      description = "dropbear ssh daemon";

      # the keys, because a daemon serving before they exist offers a host identity it then
      # changes; the logger, which is what `service/syslogd/ready` said; and the firewall where
      # there is one, since this is the machine listening.
      requires = [
        "tmpfiles-setup"
        "dropbear-keygen"
      ]
      ++ config.providers.services.lib.present [
        "syslogd"
        "nftables"
      ];

      type.service.command = "${cfg.package}/bin/dropbear -F " + lib.escapeShellArgs cfg.extraArgs;

      # TODO: dropbear doesn't use PAM so we need to keep these variables in sync with security.pam.environment!
      # NOTE: dropbear will only respect PATH and LD_LIBRARY_PATH
      path = [
        (dirOf config.security.wrapperDir)
        "/run/current-system/sw"
      ];
    };

    providers.services.tmpfiles.rules = [
      {
        path = stateDir;
        type.directory.mode = "0755";
      }
    ];
  };
}
