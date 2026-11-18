# the unit graph, as a picture
#
# A configuration's units are a graph, and the questions people actually have about one are
# shaped like a graph: what starts before what, what is waiting on the thing that hangs, what
# starts the moment the machine does. Reading that out of `providers.services.units` means
# holding two hundred `requires` lists in your head at once, which nobody does - so this renders
# it.
#
# Mermaid because it needs no tooling to look at: a `.mmd` file pastes into anything which
# renders markdown, and the graph is text, so two generations of it diff.
#
# What is drawn is the *contract's* graph, not the backend's. An implementation adds units of
# its own - finit's companion latches, dinit's `-ready` services and shutdown latch, runit's
# synthesised edges - and those are the translation rather than the configuration, so they are
# deliberately absent: the point of the picture is what this machine asked for, which is the
# same on every backend.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.providers.services;

  enabled = lib.filterAttrs (_: u: u.enable) cfg.units;

  kindOf = unit: lib.head (lib.attrNames unit.type);
  variantOf = unit: unit.type.${kindOf unit};

  # the readiness a unit ended up with, as the tag which names it. By the time this runs the
  # contract has already resolved the preference list against the backend, so what is drawn is
  # the one that was chosen rather than the ones that were offered.
  tagOf =
    r:
    let
      k = if lib.isString r then r else lib.head (lib.attrNames r);
    in
    if k == "waitFor" && !(lib.isString r) then "waitFor.${lib.head (lib.attrNames r.waitFor)}" else k;

  readinessOf =
    unit:
    let
      v = variantOf unit;
    in
    if !(v ? readiness) then
      null
    else if lib.isList v.readiness then
      (if v.readiness == [ ] then null else tagOf (lib.head v.readiness))
    else
      tagOf v.readiness;

  # mermaid ids are bare words, and a unit name is not: `network-online` would be read as a
  # subtraction. The prefix keeps a unit called `end` or `graph` from colliding with the
  # language's own keywords.
  idOf =
    prefix: name:
    prefix + lib.stringAsChars (c: if builtins.match "[A-Za-z0-9_]" c != null then c else "_") name;

  unitId = idOf "u_";

  # a unit which requires nothing, and so starts the moment the machine does, beside the
  # filesystems being mounted. Nothing about where it is drawn changes, but it is outlined for
  # it, because that is the shape a missing edge takes: a daemon which forgot to name
  # `tmpfiles-setup` starts before its state directory exists and looks, here, like a root.
  #
  # Not a shutdown unit, which runs once everything has stopped and is not started at all.
  isRoot = unit: unit.requires == [ ] && kindOf unit != "shutdown";

  # shape carries the kind, so the picture says what a node is without a legend: a rounded box
  # is a long-running service, a square box something which runs once, and a trapezoid a step
  # on the way down.
  shapeFor =
    kind: id: label:
    if kind == "service" then
      "${id}(${label}):::service"
    else if kind == "oneshot" then
      "${id}[${label}]:::oneshot"
    else
      "${id}[/${label}\\]:::shutdown";

  nodeFor =
    name: unit:
    let
      readiness = readinessOf unit;

      # what kind of unit it is, spelled out on a second line rather than left to the shape -
      # and for a service, the readiness it resolved to, which is the part of a unit most likely
      # to be wrong and least likely to be visible
      note = if readiness != null then " · ${readiness}" else "";
      label = ''"${name}<br/>${kindOf unit}${note}"'';
    in
    shapeFor (kindOf unit) (unitId name) label;

  # every edge the configuration declared, drawn as declared - there is nothing to collapse or
  # group, and grouping it was the thing which made the first version of this unreadable
  edgesOf =
    name: unit:
    map (dep: "  ${unitId dep} --> ${unitId name}") (lib.filter (dep: enabled ? ${dep}) unit.requires);

  roots = lib.attrNames (lib.filterAttrs (_: isRoot) enabled);

  # a user's tree, drawn beside the system's rather than in it.
  #
  # It is a graph of its own in the strongest sense: a different supervisor runs it, started by
  # that user's session, and the contract refuses an edge leaving it - so there is nothing to draw
  # between the two and drawing them in one flow would imply an ordering that does not exist. A
  # mermaid subgraph is exactly that statement: these nodes belong together and to nothing else.
  #
  # Ids are prefixed per user because the namespaces are genuinely separate: two users may each
  # have a unit of the same name, and a single id would quietly merge them into one node with
  # edges from everywhere.
  userTree =
    user: u:
    let
      units = lib.filterAttrs (_: v: v.enable) u.units;
      # the username through the same sanitiser the unit names go through, then that as the prefix
      # every node in this tree carries
      prefix = idOf "s_" user + "_";
      nid = idOf prefix;
    in
    [
      "  subgraph ${prefix}tree[\"${user} · ${toString (lib.length (lib.attrNames units))} units\"]"
      "    direction LR"
    ]
    ++ lib.mapAttrsToList (
      name: unit: "    ${shapeFor (kindOf unit) (nid name) ''"${name}<br/>${kindOf unit}"''}"
    ) units
    ++ lib.concatLists (
      lib.mapAttrsToList (
        name: unit:
        map (dep: "    ${nid dep} --> ${nid name}") (lib.filter (dep: units ? ${dep}) unit.requires)
      ) units
    )
    ++ [ "  end" ];

  mermaid = lib.concatStringsSep "\n" (
    [
      "---"
      "title: ${
        config.networking.hostName or "finix"
      } · ${cfg.backend} · ${toString (lib.length (lib.attrNames enabled))} units"
      "---"

      # left to right, because that is the direction the boot runs in
      "flowchart LR"
      "  %% rounded: service. square: oneshot. trapezoid: shutdown, run once on the way down."
      "  %% dashed outline: requires nothing, so starts the moment the machine does."
      "  classDef service fill:#0b3b57,stroke:#3b9fd9,color:#e6f4ff"
      "  classDef oneshot fill:#2e2712,stroke:#a98520,color:#fdf3d8"
      "  classDef shutdown fill:#2a1b3d,stroke:#8b6cc4,color:#efe7fb"
      "  classDef root stroke-dasharray:4 3,stroke-width:2px"
      ""
    ]

    # the nodes first and the edges after, so that a node is declared once with its shape and
    # class rather than picking them up from whichever edge happened to mention it first
    ++ lib.mapAttrsToList (name: unit: "  ${nodeFor name unit}") enabled
    ++ [ "" ]
    ++ lib.concatLists (lib.mapAttrsToList edgesOf enabled)
    ++ [ "" ]

    # a second class on top of the kind's, so a root keeps its kind's colour
    ++ lib.optional (roots != [ ]) "  class ${lib.concatMapStringsSep "," unitId roots} root"
    ++ [ "" ]

    # the per-user trees last, so the system graph reads top to bottom before them
    ++ lib.concatLists (lib.mapAttrsToList userTree cfg.users)
    ++ [ "" ]
  );
in
{
  config = {
    # a file rather than an option holding a string: it is something to look at, and
    # `nix-build -A config.system.build.serviceGraph` then `cat` is the whole workflow.
    system.build.serviceGraph = pkgs.writeText "service-graph-${config.networking.hostName or "finix"}.mmd" mermaid;
  };
}
