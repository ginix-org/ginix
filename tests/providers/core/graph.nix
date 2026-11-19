# the rendered unit graph says what the configuration said
#
# Not a VM test, and deliberately: the renderer is a pure function from a configuration to a
# `.mmd` file, so a machine would add a kernel and twenty minutes and tell us nothing the
# evaluation does not. What it would not catch either way is whether the picture is *legible* -
# that is a judgement, and it is made by looking at one.
#
# So what is asserted here is the part which is not a judgement: that every shape the chart has
# a rule for appears when the configuration calls for it, that an edge is drawn as declared, and
# that the one claim the chart makes on its own - "this unit starts with the boot, waiting for
# nothing" - is made only when it is true.
{
  lib,
  pkgs,
  testLib,
}:
let
  node =
    { ... }:
    {
      providers.services.backend = "finit";
      services.getty.enable = true;
      services.mdevd.enable = true;

      providers.services.units = {
        # an ordinary daemon, behind the unit which puts its state in place
        demo = {
          description = "a demonstration daemon";
          requires = [ "tmpfiles-setup" ];
          type.service.command = "/bin/demo";
        };

        # behind the daemon as well, so the chart has an edge between two units of the
        # configuration's own
        after-demo = {
          requires = [
            "tmpfiles-setup"
            "demo"
          ];
          type.oneshot.command = "/bin/after-demo";
        };

        # requires nothing, so it starts with the boot - which the chart draws hanging off start
        aaa-early = {
          type.oneshot.command = "/bin/early";
        };

        # and one on the way down
        on-the-way-out = {
          type.shutdown.command = "/bin/out";
        };
      };
    };

  graph = (testLib.evalNode "machine" node).config.system.build.serviceGraph;

  # each is a line which must be there, or one which must not, with the reason it matters.
  # Written as fixed strings rather than patterns: the assertion is about the exact text the
  # renderer emits, and a pattern that drifts into matching something else is worse than no
  # check at all.
  present = [
    {
      # double-quoted, because a single-line `''…''` has its indentation stripped and the
      # indentation is part of what is being asserted
      line = "  u_tmpfiles_setup --> u_demo";
      why = "a unit hangs off what it requires, which is the edge it declared";
    }
    {
      line = "  u_demo(\"demo<br/>service · fork\"):::service";
      why = "a service is drawn as a service, with the readiness it resolved to on this backend";
    }
    {
      line = "  u_after_demo[\"after-demo<br/>oneshot\"]:::oneshot";
      why = "a oneshot is drawn as a oneshot";
    }
    {
      line = "  u_demo --> u_after_demo";
      why = "an edge between two of the configuration's own units is drawn like any other";
    }
    {
      line = "  u_on_the_way_out[/\"on-the-way-out<br/>shutdown\"\\]:::shutdown";
      why = "a shutdown unit is drawn as one";
    }
    {
      line = "  g_start((start)):::entry";
      why = "the boot has one entry point, so the picture does";
    }
    {
      line = "  g_start -.-> u_aaa_early";
      why = "a unit which requires nothing hangs off start, since it starts with the boot";
    }
    {
      line = "  g_stop -.-> u_on_the_way_out";
      why = "a shutdown unit which requires nothing hangs off stop, since it runs first on the way down";
    }
  ];

  absent = [
    {
      line = "subgraph";
      why = "the graph is drawn as it is - units, and the edges between them - with nothing boxed, grouped or collapsed";
    }
    {
      line = "g_start -.-> u_demo";
      why = "a unit which requires something is not a root";
    }
    {
      line = "g_start -.-> u_on_the_way_out";
      why = "a shutdown unit is not started at all, so it is not a root either";
    }
  ];

  checkOf =
    kind: entry:
    let
      grep = "${lib.getExe' pkgs.gnugrep "grep"} -qF ${lib.escapeShellArg entry.line} graph.mmd";
    in
    ''
      # `present` fails when the line is missing, `absent` when it is there. Written this way
      # round because the first version had it backwards and reported every satisfied check as
      # a failure, which reads at a glance exactly like a renderer that emits nothing.
      if ${lib.optionalString (kind == "present") "! "}${grep}; then
        printf '%s\n' ${lib.escapeShellArg "  ${kind}: ${entry.line}"} >> failures
        printf '%s\n' ${lib.escapeShellArg "    ${entry.why}"} >> failures
      fi
    '';
in
pkgs.runCommand "check-services-graph" { } ''
  cp ${graph} graph.mmd
  : > failures

  ${lib.concatMapStrings (checkOf "present") present}
  ${lib.concatMapStrings (checkOf "absent") absent}

  if [ -s failures ]; then
    echo "the rendered unit graph is not what the configuration said:" >&2
    cat failures >&2
    echo >&2
    echo "what was rendered:" >&2
    cat graph.mmd >&2
    exit 1
  fi

  cp graph.mmd $out
''
