# a machine with no initrd, on something which is not finit
#
# tests/no-initrd boots finit, and finit is the one implementation which does not use the
# contract's activation script: it has a plugin of its own, and it mounts /proc before that
# plugin runs. So every no-initrd test there was passed while the path the other four take was
# broken - `finix-activate` reads /proc/cmdline to find the system it is meant to activate, and
# with no initrd nothing has mounted /proc. The machine reported "no init= on the kernel command
# line" while having a perfectly correct one.
#
# This is that path: sinit, which is the barest of the five, booting from a disk with no stage 1
# at all. It also prints how long the boot took, which is not asserted - a machine which is
# slow is not the failure being looked for - but is the only measurement of a no-initrd boot
# anywhere here, and cheap to keep.
{
  name = "no-initrd-sinit";

  nodes.machine =
    {
      config,
      pkgs,
      lib,
      modules,
      ...
    }:
    {
      imports = [ modules.sinit ];

      boot.initrd.enable = false;
      sinit.enable = true;
      services.mdevd.enable = true;

      # the scaffolding every other sinit test has: a terminal attached to nothing, so a
      # stalled machine still offers a prompt: one getty, on tty1
      services.getty = {
        enable = true;
        ttys = [ "tty1" ];
      };
      providers.services.units.tty-tty1.requires = [ ];

      fileSystems."/" = {
        device = "/dev/vda";
        fsType = "ext4";
      };

      # /proc/uptime at two points in the boot: seconds since the kernel started,
      # which is the only clock that means the same thing on every backend.
      providers.services.units = {
        stamp-multi-user = {
          description = "stamp when the filesystems and volatile files are in place";
          requires = [ "tmpfiles-setup" ];
          type.oneshot.command = pkgs.writeShellScript "stamp-mu" ''
            ${pkgs.coreutils}/bin/mkdir -p /run/timing
            ${pkgs.coreutils}/bin/cut -d' ' -f1 /proc/uptime > /run/timing/multi-user
          '';
        };

        stamp-running = {
          description = "stamp when every other unit is up";
          requires = lib.attrNames (
            lib.filterAttrs (
              name: unit: name != "stamp-running" && unit.enable && !(unit.type ? shutdown)
            ) config.providers.services.units
          );
          type.oneshot.command = pkgs.writeShellScript "stamp-running" ''
            ${pkgs.coreutils}/bin/mkdir -p /run/timing
            ${pkgs.coreutils}/bin/cut -d' ' -f1 /proc/uptime > /run/timing/running
          '';
        };
      };

      virtualisation.qemu.rootImage =
        let
          image = pkgs.callPackage "${pkgs.path}/nixos/lib/make-ext4-fs.nix" {
            storePaths = [ config.system.topLevel ];
            volumeLabel = "finix-root";
            populateImageCommands = ''
              mkdir -p ./files/{dev,proc,run,sys,tmp,var,etc,mnt}
              chmod 1777 ./files/tmp
            '';
          };
        in
        pkgs.runCommand "finix-root-sinit.img" { nativeBuildInputs = [ pkgs.e2fsprogs ]; } ''
          cp ${image} $out
          chmod +w $out
          truncate -s +512M $out
          e2fsck -fp $out || true
          resize2fs $out
        '';
    };

  testScript = ''
    machine.start()
    machine.wait_until_succeeds("test -e /run/timing/running", timeout=300)

    with subtest("activation found the system with no initrd to mount /proc for it"):
        # the failure this guards is not a missing file, it is a machine which says its kernel
        # command line has no init= when it does - because /proc/cmdline could not be read
        machine.succeed("grep -q 'root=/dev/vda' /proc/cmdline")
        machine.succeed("test -L /run/current-system")

    with subtest("and the boot completed"):
        machine.succeed("test -e /run/timing/multi-user")

    mu = machine.succeed("cat /run/timing/multi-user").strip()
    run = machine.succeed("cat /run/timing/running").strip()
    print(f"TIMING sinit, no initrd: early boot at {mu}s, everything up at {run}s since kernel start")

    machine.shutdown()
  '';
}
