{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.getty;
  # ESC byte via JSON's \u escape
  esc = builtins.fromJSON ''"\u001b"'';

  loginLib = import ./login.nix { inherit pkgs lib; };

  # a getty's argument syntax: a function, or the name of one login.nix provides
  argsType =
    with lib.types;
    coercedTo (enum (lib.attrNames loginLib.args)) (name: loginLib.args.${name}) (
      functionTo (listOf str)
    );
in
{
  imports = [ ./providers.services.nix ];

  options.services.getty = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable `getty`.
      '';
    };

    package = lib.mkOption {
      type = with lib.types; nullOr package;
      default = null;
      description = ''
        The package to use for `getty`.
      '';
      example = lib.literalExpression ''
        pkgs.util-linux // {
          mainProgram = "agetty";
        };
      '';
    };

    args = lib.mkOption {
      type = argsType;
      default = "agetty";
      description = ''
        How {option}`services.getty.package` is invoked: `"agetty"`, `"busybox"`, or a function
        from `{ device, login, autologin, extraArgs }` to its argument list. It has to match the
        package - a busybox `getty` handed agetty's flags refuses them and respawns forever.

        `autologin` is a user name or `null`; a getty which cannot log anyone in without a prompt
        should throw when it is set.
      '';
      example = lib.literalExpression ''
        {
          package = pkgs.busybox // { meta.mainProgram = "getty"; };
          args = "busybox";
        }
      '';
    };

    extraArgs = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = ''
        Additional arguments to pass to {option}`services.getty.package`.
      '';
    };

    ttys = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "tty1"
        "tty2"
        "tty3"
        "tty4"
        "tty5"
        "tty6"
      ];
      description = ''
        The list of tty devices on which to start a login prompt.

        Each is the unit `tty-<device>`, and that name is how a terminal is claimed. The prompt's
        command, description and `requires` are set at `mkDefault`, so a display manager or an
        autologin which wants the same device defines `tty-<device>` with its own command and
        wins; two of them wanting one device is a merge conflict which names both. Anything
        which runs on a terminal should use the same name, whether or not this module is
        enabled, or it will hold the device at the same time as a getty does.
      '';
    };

    autologinUser = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      example = "bella";
      description = ''
        A user to log in as on the first of {option}`ttys`, with no password asked for.

        The terminal is claimed the way anything else claims one: by defining it, at normal
        priority, over the `mkDefault` prompt this module offers on every tty in the list. A
        display manager which wants that same terminal still wins in the ordinary way, by
        saying so - nothing about it is special.

        Anyone who can open the lid gets that user's session. That is what it is for, and it
        is the whole of the security model around it: set it only where physical access to the
        machine is already the boundary.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc.issue = lib.mkDefault {
      text = ''

        ${esc}[1;32m<<< welcome to finix >>>${esc}[0m

      '';
    };

  };
}
