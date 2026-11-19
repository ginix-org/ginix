# the providers.services contract, driven on dinit as PID 1
#
# the finit backend is proven in a VM; this is the same contract on a second init system,
# to find out whether the parts dinit expresses natively actually behave as documented:
#
#   1. `depends-ms` - a milestone dependency, which the manual says the dependant survives
#      the dependency stopping. that is the contract's start-only edge, and on finit it has
#      to be faked with a companion latch task. does it hold here?
#
#   2. the shutdown units. dinit has no runlevels, so they cannot be services which simply do
#      not exist while the system runs. instead they are one script, the stop-command of a
#      latch service every root of the graph depends on - so it starts first and stops last.
#      does it hold?
{
  name = "providers.services-dinit";

  nodes.machine =
    { pkgs, ... }:
    let
      daemon =
        name:
        pkgs.writeShellScript "${name}-daemon" ''
          export PATH=${pkgs.coreutils}/bin:$PATH
          mkdir -p /run/svc-test
          touch /run/svc-test/${name}.running
          exec ${pkgs.coreutils}/bin/sleep infinity
        '';
    in
    {
      # so the test script can call dinitctl
      environment.systemPackages = [ pkgs.dinit ];
      services.mdevd.enable = true;

      # one choice, and it is the whole of the configuration's opinion about init: dinit
      # supervises the units and dinit is what the kernel starts.
      providers.services.backend = "dinit";

      providers.services.units = {
        early = {
          type.oneshot.command = pkgs.writeShellScript "early" ''
            export PATH=${pkgs.coreutils}/bin:$PATH
            mkdir -p /run/svc-test
            touch /run/svc-test/early.ran
          '';
          requires = [ ];
        };

        alpha = {
          type.service.command = daemon "alpha";
          requires = [ "tmpfiles-setup" ];
        };

        # the start-only edge under test: alpha is a milestone dependency, so stopping alpha
        # must leave beta running
        beta = {
          type.service.command = daemon "beta";
          requires = [ "alpha" ];
        };

        gamma = {
          type.service.command = daemon "gamma";
          requires = [ "tmpfiles-setup" ];
        };

        # two shutdown units, the second requiring the first so their order is unambiguous
        late = {
          type.shutdown.command = pkgs.writeShellScript "late" ''
            echo "DINIT-SHUTDOWN-1-late" > /dev/console
          '';
        };

        later = {
          requires = [ "late" ];
          type.shutdown.command = pkgs.writeShellScript "later" ''
            echo "DINIT-SHUTDOWN-2-later" > /dev/console
          '';
        };
      };
    };

  testScript = ''
    def state(svc):
        return machine.succeed(f"dinitctl status {svc}").strip()

    machine.start()

    # no finit runlevel to wait for - dinit is PID 1 here, and `entering runlevel 2` is a
    # finit message which never arrives, so waiting for it blocks until the test times out.
    # dinit reaching its boot service is the same gate and is what this asks for instead.
    machine.wait_until_succeeds("dinitctl status boot | grep -q STARTED", timeout=120)

    with subtest("the units started"):
        machine.succeed("test -f /run/svc-test/early.ran")
        for svc in ["alpha", "beta", "gamma"]:
            machine.wait_until_succeeds(f"dinitctl status {svc} | grep -q 'State: STARTED'")
            machine.succeed(f"test -f /run/svc-test/{svc}.running")

    with subtest("the latch is up, and the shutdown units are not services at all"):
        # the shutdown units are steps in the latch's stop-command, not services of their own
        machine.succeed("dinitctl status providers-services-shutdown | grep -q 'State: STARTED'")
        for svc in ["late", "later"]:
            machine.fail(f"dinitctl status {svc}")

    # question 1: is depends-ms genuinely a start-only edge?

    with subtest("QUESTION 1: stopping a milestone dependency leaves its dependant running"):
        machine.succeed("dinitctl stop alpha")
        machine.sleep(2)
        print("alpha: " + state("alpha"))
        print("beta:  " + state("beta"))
        machine.succeed("dinitctl status beta | grep -q 'State: STARTED'")

    machine.shutdown()
  '';
}
