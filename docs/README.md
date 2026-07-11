# Homeworld — Reference

<p align="center">
  <img src="banner.png" alt="Homeworld — a personal provisioning runtime" style="border-radius: 16px; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12); max-width: 100%; height: auto;">
</p>

<p align="center"><i>Full reference for modules, manifests, commands, assets, packages, configuration linking, the CLI, and the runtime layout.</i></p>

New to Homeworld? Start with the [main README](../README.md) for the pitch, installation, and quick start.

## Contents

- [Source modes](#source-modes)
- [The root module](#the-root-module)
- [Module structure](#module-structure)
  - [Manifest](#manifest)
  - [Commands](#commands)
  - [Assets](#assets)
  - [System packages](#system-packages)
  - [install.sh](#installsh)
  - [Configuration linking](#configuration-linking)
- [CLI reference](#cli-reference)
- [Repository layout](#repository-layout)
- [Runtime layout](#runtime-layout)
- [Shell environment](#shell-environment)
- [Updates](#updates)

---

## Source modes

Homeworld treats local and managed sources differently.

**Local source** — `homeworld init <path>`

Homeworld never fetches, pulls, resets, or modifies the directory. It reads and provisions from it as-is. `homeworld update` prints a message and does nothing:

```
Source is a local directory. Update it with Git, then run `homeworld install`.
```

**Managed source** — `homeworld init <git-url>`

Homeworld clones the repository into `~/.cache/homeworld/repo` and uses that clone as the source. `homeworld update` runs `git fetch`, shows the incoming commit range, and — after confirmation — fast-forwards the clone and installs the new revision into a fresh generation.

In both modes, `homeworld init` validates that the source contains a `.homeworld-module` at its root, records the source path, and runs the first install.

---

## The root module

The root `.homeworld-module` is an ordinary module. It participates in dependency ordering normally and may declare `HOMEWORLD_DEPENDS`. Its `assets/`, `commands/`, and `config/` directories belong exclusively to it.

What makes it special is its selection: the root module is always included in the installation plan regardless of `HOMEWORLD_AUTO_INSTALL`. If its platform, distro, or version requirements are not satisfied, the entire installation fails rather than skipping it.

The root manifest is also the only place `HOMEWORLD_REQUIRES` is read — version compatibility is a property of the provisioning source, not individual modules:

| Field | Description |
|---|---|
| `HOMEWORLD_REQUIRES` | Minimum Homeworld version (`MAJOR.MINOR` or `MAJOR.MINOR.PATCH`, compared numerically). Homeworld rejects the installation plan if the installed CLI is older. |

---

## Module structure

A module is any directory containing a `.homeworld-module` file. Its conventional subdirectories:

```
shells/zsh/
├── .homeworld-module        # manifest
├── install.sh               # optional post-install logic
├── packages/                # system package lists
│   ├── pacman.txt
│   └── brew.txt
├── config/                  # managed configuration files and directories
│   └── .zshrc
├── assets/                  # shared static files
│   └── themes/
│       └── default.zsh
└── commands/                # public commands exposed to PATH
    └── greeting/
        ├── run              # entry point — must be executable
        ├── banner.txt
        └── system-info.sh
```

### Manifest

`.homeworld-module` is a bash-sourceable file. It is sourced in an isolated subshell with all supported fields cleared beforehand. Unknown `HOMEWORLD_*` fields are rejected to catch typos.

```bash
HOMEWORLD_MODULE_NAME="zsh"
HOMEWORLD_DESCRIPTION="Zsh configuration and interactive tools"
HOMEWORLD_PLATFORMS="linux macos"
HOMEWORLD_DISTROS=""
HOMEWORLD_DEPENDS=""
HOMEWORLD_AUTO_INSTALL="true"
```

| Field | Required | Default | Description |
|---|---|---|---|
| `HOMEWORLD_MODULE_NAME` | Yes | — | Stable identifier. Must match `[a-z0-9][a-z0-9._-]*`. Globally unique. |
| `HOMEWORLD_DESCRIPTION` | No | `""` | Human-readable summary shown by `homeworld list` |
| `HOMEWORLD_PLATFORMS` | No | all | Space-separated: `linux`, `macos` |
| `HOMEWORLD_DISTROS` | No | all | Space-separated: `arch`, `debian`, `fedora`, etc. |
| `HOMEWORLD_DEPENDS` | No | `""` | Space-separated module names that must complete first |
| `HOMEWORLD_AUTO_INSTALL` | No | `true` | If `false`, skipped by bare `homeworld install` |

`HOMEWORLD_AUTO_INSTALL=false` affects only initial selection. A non-auto-install module is still installed when it is a transitive dependency of a selected module.

**Manifests are trusted code.** `.homeworld-module` files are sourced as Bash and execute with the same trust as `install.sh`. Treat them as repository code, not inert data.

**Platform and distro filtering is visible, not silent.** When a module is inapplicable, it is reported as skipped with a reason. Skips are suppressed only with `--quiet`.

```
INSTALL  programs          Generic utilities
INSTALL  zsh               Zsh configuration and interactive tools
SKIP     awesomewm         unsupported on macos
SKIP     decompilation     no package provider for this distro
```

Explicitly requesting a skipped module is an error:

```sh
homeworld install awesomewm   # fails on macos with a clear message
```

**Dependency cycles and missing dependencies are rejected before any installation begins.**

### Commands

Every immediate subdirectory under `commands/` defines one public command. The directory name is the command name. The executable file `run` inside it is the entry point.

```
commands/greeting/run        →  greeting   (available on PATH)
commands/awesome-tools/run   →  awesome-tools
```

A command directory may contain any files it needs:

```
commands/greeting/
├── run              # entry point
├── banner.txt
└── system-info.sh
```

There is no separate manifest field for exposing commands. The directory name is the name. To rename a command, rename the directory.

Command directory names must match `[a-z0-9][a-z0-9._-]*`. A command directory with no executable `run` file is a preflight error. Command name collisions across modules are detected and rejected during preflight. Homeworld generates a launcher at `$HOMEWORLD_BIN/<name>` that executes `run` with enough context for `homeworld path self` to work.

Inside a command's `run`, use the CLI to reference co-located files:

```bash
#!/usr/bin/env bash
set -euo pipefail

cat "$(homeworld path self banner.txt)"
"$(homeworld path self system-info.sh)"
```

`homeworld path self` returns the deployed directory of the currently running command. `homeworld path self <relative>` returns a path within it. No module names, no runtime variables, no knowledge of generations required.

### Assets

Files under `assets/` are copied into the pending generation at install time, namespaced by module name:

```
assets/themes/default.zsh
    → $HOMEWORLD_TARGET_ASSETS/zsh/themes/default.zsh   (staged)
    → accessible via: homeworld path asset zsh/themes/default.zsh
```

To reference an asset from a command or config file:

```sh
homeworld path asset zsh/themes/default.zsh
```

Use assets for files shared across multiple commands, or for resources accessed from config files at runtime. Files private to a single command belong in that command's directory instead.

### System packages

Place package lists named after the provider in a `packages/` directory:

```
decompilation/
├── .homeworld-module
└── packages/
    ├── pacman.txt
    ├── apt.txt
    └── brew.txt
```

The presence and contents of `packages/` have precise meaning:

| Condition | Meaning |
|---|---|
| No `packages/` directory | Module has no system package requirements |
| `packages/<provider>.txt` exists (even if empty) | Module supports this provider |
| `packages/` exists but no file for the current provider | Module is not ported to this provider — treated as inapplicable |

Package files contain one package name per line. Blank lines and lines beginning with `#` are ignored. Provider flags and shell syntax are not permitted.

Homeworld infers the expected provider from the platform and distro, then checks that the provider binary is present before any installation begins. A module that is inapplicable due to a missing provider file is treated the same as a platform mismatch: skipped in broad installation, an error when explicitly requested.

Package requirements are collected and deduplicated across all modules before the provider is invoked once:

```
Planning packages through pacman:
  bat
  fd
  ripgrep
  zsh
```

### install.sh

Runs after commands, assets, and packages are handled. Before each module's `install.sh` runs, Homeworld prepends `$HOMEWORLD_TARGET_BIN` to `PATH`. Commands exposed by previously completed dependencies are therefore available inside `install.sh` — dependency ordering has practical meaning, not merely chronological meaning. Runtime configuration should still reference commands by name, not by path.

Receives:

| Variable | Description |
|---|---|
| `HOMEWORLD_MODULE_ROOT` | Absolute path to the module directory in the source |
| `HOMEWORLD_MODULE_NAME` | Module name from the manifest |
| `HOMEWORLD_PLATFORM` | `linux` or `macos` |
| `HOMEWORLD_DISTRO` | `arch`, `debian`, etc., or empty |
| `HOMEWORLD_ROOT` | Stable runtime root — always resolves to `current/` |
| `HOMEWORLD_ASSETS` | `$HOMEWORLD_ROOT/assets` |
| `HOMEWORLD_BIN` | `$HOMEWORLD_ROOT/bin` |
| `HOMEWORLD_TARGET` | Absolute path to the pending generation being built |
| `HOMEWORLD_TARGET_ASSETS` | `$HOMEWORLD_TARGET/assets` |
| `HOMEWORLD_TARGET_BIN` | `$HOMEWORLD_TARGET/bin` |

Use `HOMEWORLD_TARGET_*` only when `install.sh` needs to inspect or modify files being staged. Runtime configuration uses stable paths or the `homeworld path` CLI.

A typical install script:

```sh
#!/usr/bin/env bash
set -euo pipefail

homeworld config link .zshrc "$HOME/.zshrc"
homeworld config link nvim "$HOME/.config/nvim"
```

### Configuration linking

Relative source paths resolve from the module's `config/` directory. Both files and directories are supported. Absolute paths and paths containing `..` are rejected. A module can only manage configuration stored inside its own `config/` directory.

The source path is preserved in the generation under `config/<module>/`:

```
.zshrc      →  config/zsh/.zshrc
nvim/       →  config/zsh/nvim/
nested/foo  →  config/zsh/nested/foo
```

**Generation-safety.** `homeworld config link <src> <dest>` does not link to the source repository and does not immediately create external symlinks. It:

1. Validates the destination.
2. Stages the config file or directory into the pending generation.
3. Records the requested link in the generation's `managed-links` manifest.
4. Creates the external symlink pointing to `current/config/<module>/` only during activation.
5. Removes any newly created links if activation fails.

A failed `homeworld config link` operation cannot leave behind a broken symlink or modify the active configuration. Arbitrary side effects performed directly by `install.sh` remain outside Homeworld's transaction boundary.

**Destination policy:**

| Condition | Behavior |
|---|---|
| Destination missing | Create the managed link on activation |
| Destination managed by this module | Retain or update |
| Destination managed by another module | Fail |
| Destination exists but unmanaged | Fail — Homeworld will not overwrite unmanaged files |

Unmanaged files must be removed or relocated manually before Homeworld can take ownership.

**Link reconciliation.** Each generation records its external config links in `.homeworld/managed-links`. During activation, Homeworld compares the previous and pending link sets. Links no longer declared by the pending generation are removed — but only if they still point to their expected Homeworld-managed targets. If a link destination has been altered, Homeworld fails rather than deleting it silently.

**Transaction boundary.** Runtime generation switching is atomic — `current` is a single symlink swap. External config-link activation is journaled and rollback-safe; interrupted activation is detected and repaired on the next Homeworld invocation. System package changes and arbitrary side effects performed by `install.sh` are not automatically rolled back. `homeworld rollback` restores the previous generation; it does not undo package installations.

**Rollback reconciles config links.** `homeworld rollback` uses the same journaled activation and managed-link reconciliation process as installation. It restores links declared by the previous generation and removes links declared only by the generation being deactivated. The `current` and `previous` symlinks are swapped only as part of that activation transaction — rollback genuinely restores the generation, not merely its directory pointer.

---

## CLI reference

### Queries

```sh
homeworld path root                         # active runtime root (current/)
homeworld path asset <module>/<path>        # deployed asset path
homeworld path self [relative]              # current command's deployed directory (or a path within it)
```

`homeworld path self` is only meaningful inside a Homeworld-managed command. It returns the directory containing `run` for the currently executing command, giving co-located files a stable, generation-aware path without any knowledge of Homeworld's internal layout.

Relative paths passed to `homeworld path self`, `homeworld path asset`, and `homeworld config link` must remain within their designated root. Absolute paths and paths containing `..` are rejected:

```sh
homeworld path self banner.txt         # valid
homeworld path self ../other/run       # rejected

homeworld path asset zsh/theme.zsh     # valid
homeworld path asset ../../etc/passwd  # rejected
```

### Initialization

```sh
homeworld init <path>                       # local source — use a directory on disk
homeworld init <git-url>                    # managed source — clone and use
```

### Installation

```sh
homeworld install                           # install all auto-install modules
homeworld install <module>                  # install one module and its dependencies
homeworld install --source <path>           # install from a specific path (one-off)
homeworld install --dry-run                 # preflight only — no changes made
homeworld list                              # list all modules with status and reason
homeworld status                            # summarize the active generation
homeworld doctor                            # check for common environment issues
```

`--dry-run` performs a complete preflight: discovery, validation, platform filtering, dependency resolution, collision detection, and package planning. It reports exactly what would happen and in what order, without modifying the machine.

`homeworld install <module>` installs the named module and all of its transitive dependencies. It does not install modules that depend on it.

### Updates

```sh
homeworld update                            # fetch, confirm, and apply (managed only)
homeworld update --check                    # fetch and report, do not apply
homeworld update --check --async            # background fetch, no output
homeworld update --apply                    # apply a previously fetched revision
homeworld rollback                          # swap current and previous generations
homeworld generations                       # list installed generations
homeworld gc                                # remove generations not referenced by current or previous
```

### Module primitives (for use inside install.sh)

```sh
homeworld config link <src> <dest>          # stage config into generation, defer link to activation
```

---

## Repository layout

Category directories (`shells/`, `desktops/`, `workflows/`) have no behavioral meaning. They exist for human navigation. Homeworld discovers modules at any depth by their `.homeworld-module` sentinel. Reorganizing the repository does not change module identity — names are set by the manifest, not the path.

The root `.homeworld-module` is an ordinary module. Its `assets/`, `commands/`, and `config/` directories belong exclusively to it. Nested modules own only their immediate conventional subdirectories.

```
<source-repo>/
├── .homeworld-module                 # root module
├── install.sh
│
├── shells/
│   └── zsh/
│       ├── .homeworld-module
│       ├── install.sh
│       ├── packages/
│       │   ├── pacman.txt
│       │   └── brew.txt
│       ├── config/
│       │   └── .zshrc
│       ├── assets/
│       │   └── themes/
│       │       └── default.zsh
│       └── commands/
│           └── greeting/
│               ├── run
│               ├── banner.txt
│               └── system-info.sh
│
├── desktops/
│   └── awesomewm/
│       ├── .homeworld-module
│       ├── install.sh
│       ├── config/
│       │   └── rc.lua
│       └── commands/
│           ├── hw-stats/
│           │   └── run
│           └── pvol/
│               └── run
│
├── programs/
│   ├── .homeworld-module
│   └── commands/
│       ├── asciify/
│       │   └── run
│       └── system-info/
│           └── run
│
└── workflows/
    └── decompilation/
        ├── .homeworld-module
        └── packages/
            ├── pacman.txt
            └── brew.txt
```

---

## Runtime layout

```
~/.local/bin/
└── homeworld                               # independently installed CLI

~/.local/share/homeworld/
├── current  -> generations/20260711-a3f9c2/
├── previous -> generations/20260709-1b82ee/
└── generations/
    └── 20260711-a3f9c2/
        ├── assets/
        │   └── zsh/
        │       └── themes/
        │           └── default.zsh
        │
        ├── bin/                            # generated launchers — added to PATH
        │   ├── greeting
        │   ├── hw-stats
        │   ├── pvol
        │   ├── asciify
        │   └── system-info
        │
        ├── commands/                       # deployed command packages
        │   ├── zsh/
        │   │   └── greeting/
        │   │       ├── run
        │   │       ├── banner.txt
        │   │       └── system-info.sh
        │   ├── awesomewm/
        │   │   ├── hw-stats/
        │   │   │   └── run
        │   │   └── pvol/
        │   │       └── run
        │   └── programs/
        │       ├── asciify/
        │       │   └── run
        │       └── system-info/
        │           └── run
        │
        ├── config/
        │   ├── zsh/
        │   │   └── .zshrc
        │   └── awesomewm/
        │       └── rc.lua
        │
        └── .homeworld/
            ├── installed-modules
            ├── managed-links
            ├── source-revision
            ├── created-at
            ├── platform
            ├── distro
            └── package-provider

~/.local/state/homeworld/
├── source                              # path registered by homeworld init
├── source-mode                         # "local" or "managed"
├── update-state                        # timestamp and result of last fetch
├── locks/
└── logs/

~/.cache/homeworld/
└── repo/                               # managed clone (URL sources only)
```

`~/.local/bin/homeworld` is installed and updated independently of the provisioning source. A failed module installation or rollback never affects it.

`homeworld rollback` swaps `current` and `previous`. Rollback is always reversible by running it again.

`homeworld gc` removes generations not referenced by `current` or `previous`. It never removes the active installation.

Generation metadata travels with the generation inside `.homeworld/`. `homeworld rollback`, `homeworld status`, and `homeworld generations` always read from the actual generation, never from a global state file.

---

## Shell environment

Homeworld generates `~/.config/homeworld/env.sh` during installation. Shell modules source it once:

```sh
[ ! -r "$HOME/.config/homeworld/env.sh" ] ||
    . "$HOME/.config/homeworld/env.sh"
```

The generated file:

```sh
_hw_bin="${XDG_DATA_HOME:-$HOME/.local/share}/homeworld/current/bin"

case ":$PATH:" in
    *":$_hw_bin:"*) ;;
    *) export PATH="$_hw_bin:$PATH" ;;
esac

unset _hw_bin
```

This file is shell-compatible and idempotent. It puts Homeworld-managed commands on `PATH` and nothing else. Runtime paths are accessed through the `homeworld path` CLI when needed.

---

## Updates

At shell startup, `homeworld update --check --async` runs if more than 24 hours have passed since the last check. For managed sources, it acquires a lock to prevent concurrent runs, runs `git fetch` against the managed clone, records whether the remote is ahead, and exits silently. For local sources, it skips the check entirely. The active generation is never modified.

The next interactive shell prints one line if an update is available:

```
Homeworld update available. Run `homeworld update` to apply.
```

`homeworld update` shows the incoming commit range, prompts for confirmation, fast-forwards the managed clone to the fetched revision, runs `homeworld install`, and atomically activates the new generation on success.

To update the Homeworld CLI itself, rerun the bootstrap installer:

```sh
curl -fsSL <install-url> | sh
```