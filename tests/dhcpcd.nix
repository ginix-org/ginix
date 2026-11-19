# test for dhcpcd service
#
# this test verifies that dhcpcd can obtain an ip address from a dhcp
# server (dnsmasq) running on another node.
{
  name = "dhcpcd";

  nodes.server =
    { pkgs, ... }:
    {
      services.mdevd.enable = true;

      # finit is PID 1 here: the contract needs a backend named before it can point boot.init
      # at one. getty supplies the terminal finix asserts exists - on finit it reduces to a
      # finit tty stanza, which is what a hand-written finit.ttys would have been.
      providers.services.backend = "finit";
      services.getty.enable = true;

      # a contract unit rather than a finit stanza: the contract's initctl, which the test
      # script asks, only knows units declared through it.
      #
      # ifupdown-ng is what brings eth0 up with its static address, so it stands in for the
      # finit-only `net/eth0/up` condition: --bind-interfaces needs the interface there to bind.
      providers.services.units.dnsmasq = {
        description = "dhcp server";
        requires = [
          "tmpfiles-setup"
          "syslogd"
          "ifupdown-ng"
        ];
        type.service.command = "${pkgs.dnsmasq}/bin/dnsmasq --keep-in-foreground --dhcp-range=192.168.1.100,192.168.1.200,255.255.255.0,1h --interface=eth0 --bind-interfaces --no-resolv --no-hosts";
      };

      # dnsmasq's default lease file directory, which nothing else creates off finit
      providers.services.tmpfiles.rules = [
        {
          path = "/var/lib/misc";
          type = "directory";
        }
      ];
    };

  nodes.client =
    { lib, ... }:
    {
      services.mdevd.enable = true;

      # finit is PID 1 here: the contract needs a backend named before it can point boot.init
      # at one. getty supplies the terminal finix asserts exists - on finit it reduces to a
      # finit tty stanza, which is what a hand-written finit.ttys would have been.
      providers.services.backend = "finit";
      services.getty.enable = true;
      services.dhcpcd.enable = true;

      # don't assign a static ip to eth0 - let dhcpcd handle it
      programs.ifupdown-ng.auto = lib.mkForce [ ];
      programs.ifupdown-ng.iface = lib.mkForce { };
    };

  testScript = ''
    import datetime

    start_all()

    server.wait_for_console_text("entering runlevel 2")
    client.wait_for_console_text("entering runlevel 2")

    with subtest("server has static ip"):
        server.wait_until_succeeds("ip addr show eth0 | grep 'inet 192.168.1.2'", timeout=datetime.timedelta(seconds=30))

    with subtest("dnsmasq is running"):
        server.wait_until_succeeds("initctl status dnsmasq | grep running", timeout=datetime.timedelta(seconds=30))

    with subtest("client obtains dhcp lease"):
        client.wait_until_succeeds("ip addr show eth0 | grep 'inet 192.168.1'", timeout=datetime.timedelta(seconds=30))

    with subtest("client can ping server"):
        client.succeed("ping -c 1 192.168.1.2")

    client.shutdown()
    server.shutdown()
  '';
}
