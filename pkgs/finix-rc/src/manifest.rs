//! What Nix knows at evaluation time, handed over as one file.
//!
//! The shell this replaces had the generation baked into it: a job script per unit with that
//! unit's dependencies, environment and command substituted in, and an rc.init naming every
//! one of them. That is a legitimate way to carry the information and it is the reason the
//! backend was fast - there is no graph to build at boot, only scripts that run.
//!
//! This keeps that property and moves where the substitution lands. The graph is still
//! computed in Nix and still fully resolved before the machine boots; what changes is that it
//! arrives as data a program reads rather than as text a shell interprets. Nothing here
//! searches, orders or resolves anything - `requires` is already the exact list of latches to
//! wait for, in no particular order because they are all waited for.
//!
//! One file for the whole generation rather than one per unit, because two of the seven
//! subcommands need to see units they are not running: `activate` has to map a name read off
//! stdin to a unit, and `shutdown` needs every unit to know what to stop.

use serde::Deserialize;
use std::collections::BTreeMap;

#[derive(Debug, Deserialize)]
pub struct Manifest {
    /// `/run/providers-services`. Not hardcoded, because the tests run a generation in a
    /// container where it is somewhere else, and because it is the one piece of this that is a
    /// path on the running system rather than a fact about the configuration.
    pub latch_dir: String,

    /// the shell a unit's `command` is handed to. See `job::command_argv`: the contract types
    /// `command` as "main program, path or command", so it is a command *line* and something
    /// has to parse it.
    pub shell: String,

    /// `chpst -u user[:group]`, from runit. See `job::privileged_argv` for why this is still a
    /// command rather than a setuid call in this process.
    pub chpst: String,

    /// the shutdown units, lowered by `providers/services/shutdown.nix` into one script in
    /// dependency order - or absent when this generation has none. They are not in `units`: a
    /// shutdown unit has no job, only a step in this script.
    #[serde(default)]
    pub shutdown_command: Option<String>,

    pub units: BTreeMap<String, Unit>,
}

#[derive(Debug, Deserialize)]
pub struct Unit {
    /// what `switch.list` reports and what `switch` compares generations by. Written by the
    /// job the moment it starts, which is what makes "active" mean "a job for this definition
    /// has been launched" rather than "and it finished starting".
    pub fingerprint: String,

    /// the latches to wait for, already resolved: the unit's `requires`, exactly.
    #[serde(default)]
    pub requires: Vec<String>,

    pub kind: Kind,

    /// `None` for an anchor, which is a name to synchronise on and has nothing to run.
    #[serde(default)]
    pub command: Option<String>,

    #[serde(default)]
    pub user: Option<String>,
    #[serde(default)]
    pub group: Option<String>,

    /// prepended to PATH, not replacing it - the same as the `export PATH=...:$PATH` it
    /// replaces.
    #[serde(default)]
    pub path: Vec<String>,

    #[serde(default)]
    pub environment: BTreeMap<String, String>,

    /// `None` means `fork` readiness: up the moment it is running. Otherwise a command which
    /// blocks until the daemon is live, which is `finix-wait` for every kind but
    /// `waitFor.check`, where it is the unit's own.
    #[serde(default)]
    pub readiness_command: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    /// a name with nothing behind it: latch and exit.
    Anchor,
    /// runs once and is expected to finish. Latches on success and only on success.
    Oneshot,
    /// runs until stopped, and is restarted if it stops on its own.
    Service,
}

impl Manifest {
    pub fn load(path: &str) -> Result<Self, String> {
        let text =
            std::fs::read_to_string(path).map_err(|e| format!("reading manifest {path}: {e}"))?;
        serde_json::from_str(&text).map_err(|e| format!("parsing manifest {path}: {e}"))
    }
}
