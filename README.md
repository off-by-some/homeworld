# Homeworld

<p align="center">
  <img src="docs/banner.png" alt="Homeworld — a personal provisioning runtime" style="border-radius: 16px; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12); max-width: 100%; height: auto;">
</p>

<p align="center"><i>A personal provisioning runtime.</i></p>

**Homeworld** makes setting up a machine feel like restoring it rather than rebuilding it. Your shell configuration, those handy one-off scripts you've written over the years, the packages you always need — keep it in one Git repository, and Homeworld makes each machine match it. Keeping machines in sync stops being a discipline you maintain and becomes a property of the system: change something on one machine, push, run `homeworld update` on the others. **Declare what your machine should have. Homeworld builds it, activates it atomically, and can roll it back.**

Every install lands in a fresh *generation* and activates as a transaction: Homeworld rolls back its generated environment and managed links, though not package-manager changes or arbitrary module scripts. The precise boundary is spelled out in [Guarantees](#guarantees--and-their-limits).


## Install

Install the CLI:

```sh
curl -fsSL https://raw.githubusercontent.com/off-by-some/homeworld/refs/heads/main/install.sh | sh
```

Add one line to your shell's RC file (`.zshrc`, `.bashrc`, etc.) so Homeworld-managed commands are on `PATH` in every session:

```sh
[[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/homeworld/env.sh" ]] &&
    source "${XDG_CONFIG_HOME:-$HOME/.config}/homeworld/env.sh"
```



## Quick Start


Point Homeworld at a provisioning source — a directory or Git repository of modules, marked by a `.homeworld-module` file at its root — and install:

```sh
homeworld init ~/dotfiles         # use a directory on disk (or: homeworld init <git-url>)
homeworld install                 # build and activate your environment
```

Confirm everything is active:

```sh
homeworld status                  # summarize the active generation
homeworld doctor                  # check for common environment issues
```


## Creating a Module

Most setups accumulate: a dotfiles repo here, a `brew install` you'll never remember there, a `~/bin` full of scripts that exist on exactly one computer. Homeworld replaces the pile with a **module graph**. A module is a directory that owns one concern of your setup — your shell, your editor, your window manager — and everything that concern needs to exist.

The smallest useful module is three files:

```
zsh/
├── .homeworld-module        # manifest
├── config/
│   └── .zshrc               # the file you already have
└── install.sh               # what to do with it
```

```bash
# .homeworld-module
HOMEWORLD_MODULE_NAME="zsh"
```

```bash
# install.sh
homeworld config link .zshrc "$HOME/.zshrc"
```

That's a complete module that keeps zshrc in sync across machines. Commit it, and it exists on every machine you provision with homeworld. As a module grows, each new responsibility has one conventional home:

```
shells/zsh/
├── .homeworld-module        # manifest — name, platforms, dependencies
├── config/                  # managed configuration files
│   └── .zshrc
├── packages/                # system packages, one file per package manager
│   ├── pacman.txt
│   └── brew.txt
├── commands/                # your scripts, exposed on PATH by directory name
│   └── greeting/run
├── assets/                  # shared static files — themes, templates
│   └── themes/default.zsh
└── install.sh               # optional setup logic
```

Every piece is optional, and Homeworld handles the rest: discovery, platform filtering, dependency ordering, and atomic activation with rollback. No Nix, no templating language, no rewrite of your existing setup — manifests are small bash-sourceable files, and category directories like `shells/` are purely organizational. If you have dotfiles today, you're most of the way there.

The [full reference](docs/README.md) covers every field, convention, and command in depth.

## Requirements

* A POSIX-compatible `sh` (bootstrap installer only)
* Bash 3.2 or newer — no GNU-specific behavior, so it runs on the Bash shipped with macOS
* Git, only for URL initialization and managed updates

| Platform | Package provider | Status |
|---|---|---|
| Arch Linux | pacman | Supported |
| macOS | brew | Supported |
| Debian / Ubuntu | apt | Supported |
| Fedora | dnf | Supported |
| Other Linux | — | Modules without `packages/` install; others are skipped with a warning |


## Everyday Commands

```sh
homeworld install                # install all auto-install modules
homeworld install zsh            # install one module and its dependencies
homeworld install --dry-run      # preview the complete plan without changing the machine
homeworld list                   # all modules, with platform and status
homeworld update                 # pull and apply the latest changes (Git sources)
homeworld rollback               # swap back to the previous generation
homeworld doctor                 # check for common environment issues
```

For Git-managed sources, Homeworld checks for updates at shell startup, at most once per day, and prints a single line in your next shell when one is available. No daemon and no telemetry — the check is a `git fetch` against your own repository, nothing else, and it never modifies the active generation. Local directories are never touched at all: Homeworld reads them as-is and leaves Git to you.


## Design Philosophy

Reproducibility shouldn't require a research project. Homeworld's bet is that most people don't need an immutable closure of the universe — they need their *own* environment to follow them between machines, with honest guarantees about what happens when something fails. So the primitives stay boring on purpose: modules are directories, manifests are Bash variables, package lists are text files. Convention carries the meaning, and a provisioning source stays legible to anyone who can read a directory tree. The sophistication lives in the runtime — dependency resolution, collision detection, journaled activation, generational rollback — where you benefit from it without learning a new language to describe your machine.


## How It Works

Homeworld walks the source to discover every module (any directory containing a `.homeworld-module` file), filters them by platform and distro, sorts them in dependency order, and installs them into a new **pending generation** — a complete, self-contained snapshot of your environment. The `current` symlink is updated atomically only after every module in the plan succeeds. If installation fails, Homeworld leaves the active generation unchanged, and `homeworld rollback` swaps you back to the previous generation at any time.

Filtering is visible, not silent — inapplicable modules are reported with a reason, and explicitly requesting one is an error rather than a no-op:

```
INSTALL  programs          Generic utilities
INSTALL  zsh               Zsh configuration and interactive tools
SKIP     awesomewm         unsupported on macos
SKIP     decompilation     no package provider for this distro
```

The same repo provisions your Arch desktop and your work Mac. Modules declare where they apply; Homeworld installs what fits and tells you what didn't.


## Guarantees — and Their Limits

A provisioning tool earns trust by being precise about what it promises. Homeworld is deliberately explicit about what is and is not transactional:

* **Generation switching is atomic.** `current` is a single symlink swap. External config-link activation is journaled and rollback-safe; interrupted activation is detected and repaired on the next invocation.
* **Ownership is never taken silently.** If `~/.zshrc` exists and Homeworld doesn't manage it, installation fails and asks you to resolve the conflict. Modules also cannot take over paths owned by other modules.
* **Rollback restores the user environment, not the whole machine.** `homeworld rollback` restores the previous generation's commands, assets, and managed links. It does not undo system package installations or arbitrary side effects performed by `install.sh` — those are outside the transaction boundary.
* **Package lists are names, not pinned versions.** Installing the same source months later may pull newer packages. Generations preserve Homeworld's deployed files, not an immutable closure of every program and library. If you need bit-for-bit reproducibility down to the final shared library, use [Nix](https://nixos.org) — Homeworld trades that guarantee for working with the package manager you already have.
* **Manifests and `install.sh` are trusted code.** Both execute as Bash with your privileges. Treat a provisioning source as repository code, not inert data, and only install sources you trust.

## Documentation & Support

* [**Full Reference**](docs/README.md) — modules, manifests, commands, assets, packages, `install.sh`, configuration linking, CLI reference, repository and runtime layout, updates
* [**Issues**](https://github.com/off-by-some/homeworld/issues) — bug reports and questions

<br>

## 🌟 Love Homeworld?

Support the project by [**starring the repository**](https://github.com/off-by-some/homeworld) ⭐

***

<br>

<p align="center">
  <strong>Homeworld</strong> — a personal provisioning runtime
</p>

<p align="center">
  <a href="https://github.com/off-by-some/homeworld/blob/main/LICENSE">License</a> •
  <a href="https://github.com/off-by-some/homeworld/blob/main/CONTRIBUTING.md">Contributing</a> •
  <a href="https://github.com/off-by-some/homeworld/blob/main/CODE_OF_CONDUCT.md">Code of Conduct</a>
</p>

<p align="center">
  <em>Crafted with ❤️ by <a href="https://github.com/off-by-some">Cassidy Bridges</a></em>
</p>

<p align="center">
  © 2026 Cassidy Bridges • MIT Licensed
</p>

<br>

***