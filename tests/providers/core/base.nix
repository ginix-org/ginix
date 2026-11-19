# the machine a core test runs on, once per implementation
#
# The only thing that differs between the four instantiations is the name in
# `providers.services.backend` and the module that name refers to. Everything else is identical,
# which is what makes a difference in the result attributable to the implementation rather than
# to the configuration.
{
  backend,
  coreLib,
}:
{
  config,
  lib,
  modules,
  ...
}:
{
  # finit is in the default module set; the other three are opted into by name
  imports = lib.optional (backend != "finit") modules.${backend};

  providers.services.backend = backend;

  # a device manager, which every one of these needs and none of them has to describe: the
  # module emits contract units, so this is the same daemon on all four.
  services.mdevd.enable = true;

  # one login prompt, on tty1, said once for every backend. It used to be a `finit.ttys` stanza
  # under an `mkIf`, because a terminal was only expressible to finit.
  #
  # Attached to nothing: nothing in these tests is waiting for the system to be up before a
  # prompt is useful, and a test which stalls the boot is one where a prompt is the only way
  # to see why.
  services.getty = {
    enable = true;
    ttys = [ "tty1" ];
  };
  providers.services.units.tty-tty1.requires = [ ];

  # the marker directory, made once before any unit runs rather than by each unit for itself.
  # 1777 because a unit running as somebody else writes here too, and `mkdir -p` from whichever
  # unit happened to be first would leave it owned by root and unwritable by them - which looks
  # exactly like the unit never having started.
  providers.services.tmpfiles.rules = [
    {
      path = coreLib.markerDir;
      type.directory.mode = "1777";
    }
  ];

  providers.services.units.booted = coreLib.bootedUnit config.providers.services.units;
}
