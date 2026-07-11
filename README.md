# Homeworld

<p align="center">
  <img src="docs/banner.png" alt="Homeworld — a personal provisioning runtime" style="border-radius: 16px; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12); max-width: 100%; height: auto;">
</p>

<p align="center"><i>A personal provisioning runtime.</i></p>

**Homeworld** helps you set up and maintain personal machines by treating your configuration as a **module graph** rather than a pile of dotfiles. Each module owns its config, assets, commands, package requirements, and install logic. Homeworld handles the rest: discovery, platform filtering, dependency ordering, and atomic activation with rollback — without requiring Nix, templates, or a rewrite of your existing setup.

Homeworld is the executor of the module graph, not a node within it. The provisioning source describes the machine; Homeworld interprets that description.

**Declare what your machine should have. Homeworld builds it, activates it atomically, and can roll it back.**


## Install

```sh
curl -fsSL https://raw.githubusercontent.com/off-by-some/homeworld/refs/heads/main/install.sh | sh
```

This installs `~/.local/bin/homeworld` independently. It is not part of any provisioning source and is never replaced by a module installation.


## Requirements

- A POSIX-compatible `sh` (bootstrap installer only)
- Bash 3.2 or newer — no GNU-specific behavior, so it runs on the Bash shipped with macOS
- Git, only for URL initialization and managed updates

| Platform | Package provider | Status |
|---|---|---|
| Arch Linux | pacman | Supported |
| macOS | brew | Supported |
| Debian / Ubuntu | apt | Supported |
| Fedora | dnf | Supported |
| Other Linux | — | Modules without `packages/` install; others are skipped with a warning |

## Quick start

Point Homeworld at a provisioning source — a directory (or Git repo) with a `.homeworld-module` file at its root:

```sh
homeworld init .                  # local source — use the current directory
homeworld init ~/dotfiles         # local source — use any directory on disk
homeworld init <git-url>          # managed source — clone a remote repo and use that
```

Then provision:

```sh
homeworld install                # install all auto-install modules
homeworld install zsh            # install one module and its dependencies
homeworld list                   # show all modules with platform and status
homeworld update                 # pull and apply the latest changes (managed sources only)
```

Not sure what an install would do? `homeworld install --dry-run` runs the complete preflight — discovery, validation, platform filtering, dependency resolution, collision detection, and package planning — and reports exactly what would happen, in order, without touching the machine.

## How it works

Homeworld walks the source directory to discover every module (any directory containing a `.homeworld-module` file), filters them by platform and distro, sorts them in dependency order, and installs them into a new **pending generation**. The `current` symlink is updated atomically only after every module in the plan succeeds. A failed install leaves the previous generation untouched, and `homeworld rollback` swaps you back to the previous generation at any time.

Filtering is visible, not silent — inapplicable modules are reported with a reason, and explicitly requesting one is an error rather than a no-op:

```
INSTALL  programs          Generic utilities
INSTALL  zsh               Zsh configuration and interactive tools
SKIP     awesomewm         unsupported on macos
SKIP     decompilation     no package provider for this distro
```

## What a module looks like

A module is any directory with a `.homeworld-module` manifest. Its conventional subdirectories each mean one thing:

```
shells/zsh/
├── .homeworld-module        # manifest — name, platforms, dependencies
├── install.sh               # optional post-install logic
├── packages/                # system package lists, one file per provider
│   ├── pacman.txt
│   └── brew.txt
├── config/                  # managed configuration files and directories
│   └── .zshrc
├── assets/                  # shared static files
│   └── themes/default.zsh
└── commands/                # public commands exposed to PATH
    └── greeting/
        └── run              # entry point — the directory name is the command name
```

The manifest is a small, bash-sourceable file:

```bash
HOMEWORLD_MODULE_NAME="zsh"
HOMEWORLD_DESCRIPTION="Zsh configuration and interactive tools"
HOMEWORLD_PLATFORMS="linux macos"
HOMEWORLD_DEPENDS=""
```

Category directories like `shells/` or `desktops/` are purely organizational — module identity comes from the manifest, not the path. Reorganizing the repository changes nothing.

See the [full documentation](docs/README.md) for the manifest reference, command and asset conventions, package handling, `install.sh` environment, CLI reference, and runtime layout.

## Guarantees — and their limits

Homeworld is deliberately explicit about what is and is not transactional:

- **Generation switching is atomic.** `current` is a single symlink swap. External config-link activation is journaled and rollback-safe; interrupted activation is detected and repaired on the next invocation.
- **Ownership is never taken silently.** If `~/.zshrc` exists and Homeworld doesn't manage it, installation fails and asks you to resolve the conflict. Modules also cannot take over paths owned by other modules.
- **Rollback restores the user environment, not the whole machine.** `homeworld rollback` restores the previous generation's commands, assets, and managed links. It does not undo system package installations or arbitrary side effects performed by `install.sh` — those are outside the transaction boundary.
- **Package lists are names, not pinned versions.** Installing the same source months later may pull newer packages. Generations preserve Homeworld's deployed files, not an immutable closure of every program and library.
- **Manifests and `install.sh` are trusted code.** Both execute as Bash with your privileges. Treat a provisioning source as repository code, not inert data, and only install sources you trust.

## Documentation

- [Full reference](docs/README.md) — modules, manifests, commands, assets, packages, `install.sh`, config linking, CLI reference, repository and runtime layout, updates