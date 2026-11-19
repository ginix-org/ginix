# the base a providers.services test builds on: a machine whose daemons are contract units
#
# lives under tests/lib because the harness treats every .nix file under tests/ as a test, and
# this is a module rather than one.
#
# without it a test would enable services.mdevd and services.getty, both of which write finit
# stanzas directly - and then a regression in the contract could be masked by finit doing the
# work anyway. driving the same daemons through the contract means every test exercises the
# thing under test.
{
  pkgs,
  config,
  lib,
  ...
}:
{
  # the device manager is a contract unit in the module itself now, so enabling it is the whole
  # of what this needs to say. It used to be reproduced here, with the module's finit stanzas
  # switched off, because the module only knew how to write stanzas.
  services.mdevd.enable = true;

  # one login prompt, on tty1, attached to nothing: a machine which stalls should still offer a
  # console to look at
  services.getty = {
    enable = true;
    ttys = [ "tty1" ];
  };
  providers.services.units.tty-tty1.requires = [ ];

  providers.services.backend = "finit";
}
