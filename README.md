# Homeworld

<p align="center">
  <img src="docs/banner.png" alt="Homeworld — a personal provisioning runtime" style="border-radius: 16px; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12); max-width: 100%; height: auto;">
</p>



<p align="center" style="margin-bottom: 0">
  <a href="https://github.com/off-by-some/homeworld/actions/workflows/test.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/off-by-some/homeworld/test.yml?branch=main&label=CI&color=2E8B57" alt="CI">
  </a>
  <a href="https://github.com/off-by-some/homeworld/blob/main/docs/README.md">
    <img src="https://img.shields.io/badge/docs-reference-8A2BE2" alt="Reference docs">
  </a>
  <a href="https://pubs.opengroup.org/onlinepubs/9799919799/utilities/sh.html">
    <img src="https://img.shields.io/badge/shell-POSIX%20sh-1E90FF" alt="Shell: POSIX sh">
  </a>
  <a href="https://github.com/off-by-some/homeworld/actions/workflows/test.yml">
    <img src="https://img.shields.io/badge/tested%20shells-sh%20%7C%20dash%20%7C%20ash-4169E1" alt="Tested shells: sh, dash, and ash">
  </a>
  <a href="https://github.com/off-by-some/homeworld/actions/workflows/test.yml">
    <img src="https://img.shields.io/badge/tested%20OS-Linux%20%7C%20macOS-FF6B35" alt="OS: Linux and macOS">
  </a>
</p>

<p align="center"><i>A transactional runtime for your personal computing environment.</i></p>


**Homeworld** makes setting up a machine feel like restoring it rather than rebuilding it. Your shell configuration, the scripts living in `~/bin` on exactly one computer, the packages you always install, the tools you clone from GitHub — Homeworld gathers them into one Git repository and makes every machine you own match it. Change something on your desktop, push, run `homeworld update --install` on your laptop, and get back to work.

And because every change builds off to the side and activates as a transaction, a broken install can't take your working environment with it. If a build fails, nothing changed. If it succeeds and you regret it, one command puts the previous environment back.

**Describe your machine once. Every machine follows.**

## Quick Start

```sh
curl -fsSL https://raw.githubusercontent.com/off-by-some/homeworld/refs/heads/main/install.sh | sh
```

Add one line to your `.zshrc` or `.bashrc` so Homeworld-managed commands are on your `PATH`:

```sh
[ ! -r "${XDG_CONFIG_HOME:-$HOME/.config}/homeworld/env.sh" ] ||
    . "${XDG_CONFIG_HOME:-$HOME/.config}/homeworld/env.sh"
```


For a quick example, let's put a real file under management. Homeworld reads your setup from a **setup repository** — an ordinary Git repository (or just a directory, to start) containing **modules**. A module is a folder that owns one piece of your setup: your shell, your editor, your scripts. Here's a repository with one module in it, managing the `.zshrc` you already have:

```text
~/dotfiles/
└── zsh/
    ├── .homeworld-module        # marks this folder as a module
    ├── config/
    │   └── .zshrc               # your actual zshrc, moved here
    └── install.sh               # what this module declares
```

```sh
# zsh/.homeworld-module
HOMEWORLD_MODULE_NAME="zsh"
```

```sh
# zsh/install.sh
homeworld config add config/.zshrc zshrc
homeworld config link zshrc "$HOME/.zshrc"
```

Point Homeworld at the repository. `init` records the source and runs the first install:

```sh
homeworld init ~/dotfiles
```

Homeworld prints a module plan, builds a generation, and activates it only after the build succeeds.

Your `~/.zshrc` is now a managed link into Homeworld's environment. Edit the copy in `~/dotfiles`, run `homeworld install`, and the change is live — on *this* machine. For every other machine:

```sh
git push                                          # on your desktop

homeworld init git@github.com:you/dotfiles.git    # on your laptop, once
```

That first laptop command clones the setup repository, records it, and installs the same zshrc. From then on, `homeworld update --dependencies --install` on any machine fetches your latest setup and rebuilds. That's the loop. Everything else in this README is about what you can put inside a module, and what Homeworld guarantees when it builds one.


## Where Homeworld Applies

<img
  src="docs/homeworld-pre-v1.svg"
  width="100%"
  alt="Homeworld is under construction and has not reached version 1. It is being tested on real machines, so concepts and interfaces may change suddenly. The documentation describes how it works today, but those promises may still evolve before version 1."
/>

Homeworld is built for the gap between "a dotfiles repo" and "adopting Nix." It earns its keep when:

* **You own several machines** — a work laptop, a personal desktop, a home server — and they've drifted
* **You cross operating systems** — macOS and Linux, or Arch and Debian and Fedora, with one setup describing all of them
* **Your setup is more than dotfiles** — scripts, cloned tools like pyenv, themes, packages, and caches that all need to arrive together
* **You want each OS's own package manager in charge** — brew, apt, dnf, and pacman keep doing their jobs; Homeworld hands them the list
* **You want rollback** — the ability to try a change and cleanly step back — without learning a new language to describe your computer
* **You've been burned** — by a setup script that died halfway through and left the machine half-configured

The common thread: your environment is an accumulation of small decisions, and you want it written down somewhere — versioned, shared between machines, and safe to rebuild. If you have fifteen dotfiles and one laptop, Homeworld is probably more than you need; see the [comparison table](#where-another-tool-fits-better) below for lighter options.

## The Resources

Everything a module can declare fits into a small set of resource kinds. This table is the whole list, and the rest of this README walks through the common ones:

| Resource | Declared with | What it is | Example |
|----------|--------------|------------|---------|
| **Config** | `homeworld config` | Files you maintain and want identical everywhere | `.zshrc`, `init.lua` |
| **Commands** | `homeworld command` | Your scripts, exposed on `PATH` | that deploy script you always lose |
| **Packages** | `packages/*.txt` | System packages, installed by your OS's manager | `ripgrep`, `tmux` |
| **Repos** | `homeworld repo` | Git dependencies, pinned to exact commits | pyenv, zsh plugins, themes |
| **Assets** | `homeworld asset` | Immutable generated, downloaded, patched, or bundled files | patched requirements, themes, tool bundles |
| **State** | `homeworld state` | Mutable machine-local data Homeworld points at but never touches | pyenv's built Pythons, caches |

Two verbs recur across the primitive resources, and they always mean the same thing:

* **`add`** — build the resource into the environment
* **`link`** — expose that resource at a Homeworld-owned destination

Declarations live in a module's `install.sh`, which is plain shell — no template language, no DSL. Conventional directories like `config/` and `commands/` are shorthand that feeds these same primitives; the primitives are the real API, and the layout is just a tidy place to keep their inputs.


## Config — files you maintain

The Quick Start already showed the concept:

```sh
homeworld config add config/.zshrc zshrc
homeworld config link zshrc "$HOME/.zshrc"
```

`config add` copies your file into the environment being built, and `config link` keeps `~/.zshrc` pointing at the named snapshot. Two properties are worth knowing:

* **The link survives updates without being rewritten.** `~/.zshrc` points through a stable `current/` symlink, so when a new environment activates, every config link follows automatically.
* **Homeworld won't clobber your files.** If `~/.zshrc` already exists as a real file — or as a symlink Homeworld didn't create — installation stops and tells you, rather than overwriting it.

## Commands — your scripts, everywhere

Every long-lived machine grows a `~/bin`. Homeworld makes it portable:

```text
zsh/commands/
└── greeting/
    └── run          # any executable
```

```sh
# in install.sh
homeworld command add commands/greeting greeting
```

```sh
$ greeting
Hello from every machine you own.
```

`greeting` is now on `PATH` wherever this module installs. A command can be a single executable file or a directory with a `run` entrypoint plus whatever helper files it needs. Names are checked for collisions across all modules at build time — two modules can't silently fight over `deploy`.

## Packages — one list per package manager

A module lists the system packages it needs, one file per package manager:

```text
zsh/packages/
├── brew.txt         # macOS
├── pacman.txt       # Arch
├── apt.txt          # Debian / Ubuntu
└── dnf.txt          # Fedora
```

```text
# pacman.txt
zsh
ripgrep
fzf
```

Homeworld detects the platform and hands the right list to the right manager. Packages here are still just package names; `brew`, `apt`, `dnf`, or `pacman` decide which versions they mean. If you need an exact version, use something Homeworld can pin, like a repo at a commit, or write the pinning yourself in `install.sh`. Homeworld will run that shell, but it won't make those side effects part of rollback. (Details in [Guarantees](#guarantees--and-their-limits).)

| Platform | Package provider | Status |
|---|---|---|
| Arch Linux | pacman | Supported |
| macOS | brew | Supported |
| Debian / Ubuntu | apt | Supported |
| Fedora | dnf | Supported |
| Other Linux | — | Modules without `packages/` install; others are skipped with a warning |

## Repos — Git dependencies, pinned

Plenty of good software isn't in any package manager — it's a Git repository you're told to clone. pyenv, zsh plugin managers, themes. The problem with `git clone` in a setup script is that it grabs *whatever the branch points at today*, so two machines provisioned a week apart quietly end up with different software.

Homeworld pins instead:

```sh
# in install.sh
homeworld repo add https://github.com/pyenv/pyenv pyenv
homeworld repo link pyenv "$HOME/.pyenv"
```

`repo add` resolves the repository to an **exact commit** and records it. `repo link` points `~/.pyenv` at that pinned checkout. Every machine that installs this module gets the same commit — not "whatever main was that day." When you *want* to move forward, `homeworld update --dependencies` fetches, and the next install pins the new commit while every previous environment keeps the old one, byte for byte.

Remove the declaration and the checkout is garbage-collected once nothing references it. There's no separate uninstall ritual — you stop declaring it, and it goes away.

## Assets — immutable generated or patched files

Assets are files or directories that Homeworld owns as part of a generation, but that are not configuration you edit directly. Use them for generated files, downloaded bundles, compiled tools, extracted archives, or small patches to a repository view.

```sh
# in install.sh
homeworld asset add generated/theme theme
homeworld asset link theme "$HOME/.local/share/theme"
```

`asset add` snapshots the source. After that, changing or deleting the original file does not change the generation. Rollback restores the older asset; garbage collection removes assets that no retained generation references.

Assets can also appear inside a managed repository without modifying the checkout:

```sh
homeworld repo add https://github.com/kohya-ss/sd-scripts.git sd-scripts
repo=$(homeworld repo path sd-scripts)

homeworld asset add generated/requirements.txt requirements
homeworld asset link requirements "$repo/requirements.txt"
```

Homeworld presents a composed repository view: the original checkout plus the immutable asset replacement. That is the right shape for generated files or tiny patches. Mutable data still belongs in state.

## State — the data that's yours, not Homeworld's

Homeworld rebuilds its environments freely — that's what makes updates and rollback safe — but pyenv itself expects parts of `~/.pyenv` to be writable. The checkout is code. Installed Python versions, regenerated shims, download caches, and the global `version` file are local data.

**State** is how a module draws that line. The pyenv code is pinned as a repo; the writable paths live somewhere stable outside the generation and are linked back into the pyenv root:

```sh
# in install.sh
homeworld repo add https://github.com/pyenv/pyenv pyenv
homeworld repo link pyenv "$HOME/.pyenv"

state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
pyenv_state_root=${PYENV_STATE_ROOT:-"$state_home/pyenv"}

mkdir -p \
    "$pyenv_state_root/versions" \
    "$pyenv_state_root/shims" \
    "$pyenv_state_root/cache"

[ -e "$pyenv_state_root/version" ] || : > "$pyenv_state_root/version"

homeworld state link "$pyenv_state_root/versions" "$HOME/.pyenv/versions"
homeworld state link "$pyenv_state_root/shims" "$HOME/.pyenv/shims"
homeworld state link "$pyenv_state_root/cache" "$HOME/.pyenv/cache"
homeworld state link "$pyenv_state_root/version" "$HOME/.pyenv/version"
```

Homeworld owns the links, not the data. It never copies, deletes, rolls back, or garbage-collects a state target. If one machine needs its pyenv state on a larger disk, bind that path to a portable name with `homeworld state bind` and link the name instead.

Plugins need the same decision. If every machine should have the same plugin code, pin each plugin as a repo and link it under `$HOME/.pyenv/plugins/<name>`. If a plugin manager owns that directory, make it state instead; it will work, but plugin contents become machine-local rather than something Homeworld keeps identical.

That split shows up everywhere in Homeworld: repos and assets are things it can rebuild, while state is data it only points at. Homeworld can throw away old environments because your data was never inside them.

## The Generation Guarantee

Every `homeworld install` builds a **generation** — an idea borrowed from NixOS: a complete, self-contained snapshot of your environment (config, commands, pinned repos) in a fresh directory. Your active environment isn't touched while it builds.

```text
generations/
├── 1/        ← previous — rollback target
├── 2/        ← current  — what your links resolve to
└── 3/        ← building — invisible until it succeeds
```

Only when the entire build succeeds does Homeworld **activate** the new generation, in a single journaled transaction that swaps what `current/` means. Because your `~/.zshrc` and friends point *through* `current/` rather than at any generation directly, activation flips your whole environment at once — and so does undoing it:

```sh
homeworld generation rollback     # the previous environment, back, atomically
```

The practical result:

* **A failed build changes nothing.** The generation you were using stays active; the broken one is discarded. There is no "died halfway through the setup script" state.
* **Interruption is recoverable.** Activation writes a journal before it mutates anything. Kill the process mid-swap — `Ctrl-C`, `kill`, a dropped SSH session — and the next Homeworld command finds the journal and finishes or reverses the transaction automatically. No repair command exists because none is needed.
* **Rollback is real.** The previous generation is a complete environment, kept on disk, one command away. Old generations beyond that are garbage-collected only after a successful activation — never before.

The runtime handles the fussy part. Modules stay folders, manifests stay shell variables, package lists stay text files — so a setup repository remains readable to anyone who can read a directory tree, including you in two years.

## Everyday Commands

```sh
homeworld install                          # build a generation and activate it
homeworld install --dry-run                # preview the module and package plan
homeworld install --reinstall              # rebuild from scratch — old generation stays active until the new one succeeds
homeworld update                           # fast-forward a managed setup repository
homeworld update --check                   # report whether the setup repository is behind
homeworld update --dependencies            # also fetch pinned repos
homeworld update --dependencies --install  # fetch everything and build a new generation
homeworld generation rollback              # activate the previous generation
homeworld generation gc                    # collect unreachable generations and checkouts
homeworld status                           # what's active right now
homeworld doctor                           # check for common problems
```

## Where Another Tool Fits Better

Homeworld sits between symlink managers and full declarative systems. Depending on what you need, a different starting point may serve you better:

| Need | Better starting point |
|---|---|
| A few dotfiles and symlinks | GNU Stow |
| Git-native dotfile tracking | YADM |
| Built-in templating, secrets, per-host content, Windows | Chezmoi |
| **Personal machine generations without Nix** | **Homeworld** |
| Exact declarative packages and dependency closures | Nix Home Manager |
| Project-level language runtimes and tasks | mise |
| Remote hosts, servers, fleets | Ansible |

This table is mostly about what each tool gives you out of the box. Chezmoi has templating and secret-manager integrations; in Homeworld, `install.sh` is plain shell, so per-host logic and secret fetching are code you write. Nix Home Manager pins package closures; Homeworld pins what it owns directly, like repos at exact commits or commands you build yourself, while leaving OS packages to `brew`, `apt`, `dnf`, or `pacman`. The tradeoff is that your existing dotfiles are already most of a setup repository, and there is no new language to learn.

## Guarantees — and Their Limits

Here is the line Homeworld tries not to cross.

**What Homeworld promises:**

* **Failed builds never replace a working environment.** Reinstall also builds first and cleans up only after successful activation. A failed reinstall leaves everything — `current`, `previous`, links, rollback, state — untouched.
* **Activation is recoverable after interruption.** Shell failure, signals, killed processes: the journal lets the next invocation restore consistency automatically.
* **Ownership is conservative.** Homeworld refuses to overwrite unmanaged files, and won't remove a managed link that something else has changed out from under it.
* **Pinned repos stay pinned.** Checkouts are detached at a recorded commit and isolated from the fetch cache (`--no-hardlinks`), so later fetches can't alter what an existing generation resolves to.
* **State is never rolled back or garbage-collected.** Homeworld manages the symlink; you own everything behind it.

**What it doesn't:**

* **Package versions aren't pinned by Homeworld.** Rollback restores Homeworld's files and checkouts; it cannot undo a `brew upgrade` or restore an apt dependency closure. A module can pin versions itself, but that runs outside the transaction.
* **Arbitrary side effects are outside the transaction.** Whatever your `install.sh` does beyond Homeworld's resources is yours to make idempotent.
* **Power-loss durability isn't claimed.** Portable POSIX shell has no reliable cross-platform `fsync`. Homeworld uses temp files and atomic renames, but makes no promises about kernel panics or storage-controller reordering.
* **Setup repositories are trusted code.** Manifests and `install.sh` run with your privileges. Pin repos you trust; read modules you didn't write.

The [full reference](docs/README.md) has the narrower details, including how symlink replacement works on each platform.

## Documentation & Support

* [**Full Reference**](docs/README.md) — every manifest field, resource verb, command, and the storage and transaction model
* [**Issues**](https://github.com/off-by-some/homeworld/issues) — bug reports and questions

<p align="center">
  <strong>Homeworld</strong> — a personal provisioning runtime
</p>

<p align="center">
  <em>Crafted with ❤️ by <a href="https://github.com/off-by-some">Cassidy Bridges</a></em>
</p>

<p align="center">
  © 2026 Cassidy Bridges • MIT Licensed
</p>

<br>

***
