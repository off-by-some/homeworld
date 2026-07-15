# Homeworld

<p align="center">
  <img src="docs/banner.png" alt="Homeworld — a personal provisioning runtime" style="border-radius: 16px; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12); max-width: 100%; height: auto;">
</p>

<p align="center"><i>A personal provisioning runtime.</i></p>

**Homeworld** makes setting up a machine feel like restoring it rather than rebuilding it. Your shell configuration, the scripts living in `~/bin` on exactly one computer, the packages you always install, the tools you clone from GitHub — Homeworld gathers them into one Git repository and makes every machine you own match it. Change something on your desktop, push, run `homeworld update` on your laptop. Keeping machines in sync stops being a discipline you maintain and becomes a property of the system.

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
homeworld config link config/.zshrc "$HOME/.zshrc"
```

Point Homeworld at the repository and install:

```sh
homeworld init ~/dotfiles
homeworld install
```

```text
✓ zsh — config/.zshrc → ~/.zshrc
✓ Generation 1 built
✓ Activated
```

Your `~/.zshrc` is now a managed link into Homeworld's environment. Edit the copy in `~/dotfiles`, run `homeworld install`, and the change is live — on *this* machine. For every other machine:

```sh
git push                                          # on your desktop

homeworld init git@github.com:you/dotfiles.git    # on your laptop, once
homeworld install                                 # same zshrc, same everything
```

From now on, `homeworld update --dependencies --install` on any machine pulls your latest setup and rebuilds. That's the loop. Everything else in this README is about what you can put inside a module, and what Homeworld guarantees when it builds one.

## Where Homeworld Applies

Homeworld is built for the gap between "a dotfiles repo" and "adopting Nix." It earns its keep when:

* **You own several machines** — a work laptop, a personal desktop, a home server — and they've drifted
* **You cross operating systems** — macOS and Linux, or Arch and Debian and Fedora, with one setup describing all of them
* **Your setup is more than dotfiles** — scripts, cloned tools like pyenv, themes, packages, and caches that all need to arrive together
* **You want each OS's own package manager in charge** — brew, apt, dnf, and pacman keep doing their jobs; Homeworld hands them the list
* **You want rollback** — the ability to try a change and cleanly step back — without learning a new language to describe your computer
* **You've been burned** — by a setup script that died halfway through and left the machine half-configured

The common thread: your environment is an accumulation of small decisions, and you want it to be a *document* instead — one you can version, share between machines, and safely regenerate. If you have fifteen dotfiles and one laptop, Homeworld is more machinery than you need; see the [comparison table](#where-another-tool-fits-better) below for lighter options.

## The Five Resources

Everything a module can declare is one of five resource kinds. This table is the whole list — the rest of this README walks through it one row at a time:

| Resource | Declared with | What it is | Example |
|----------|--------------|------------|---------|
| **Config** | `homeworld config` | Files you maintain and want identical everywhere | `.zshrc`, `init.lua` |
| **Commands** | `homeworld command` | Your scripts, exposed on `PATH` | that deploy script you always lose |
| **Packages** | `packages/*.txt` | System packages, installed by your OS's manager | `ripgrep`, `tmux` |
| **Repos** | `homeworld repo` | Git dependencies, pinned to exact commits | pyenv, zsh plugins, themes |
| **State** | `homeworld state` | Mutable machine-local data Homeworld points at but never touches | pyenv's built Pythons, caches |

Two verbs recur across all of them, and they always mean the same thing:

* **`add`** — build the resource into the environment
* **`link`** — `add`, plus maintain a symlink somewhere in your home directory pointing at it

Declarations live in a module's `install.sh`, which is plain shell — no template language, no DSL. Conventional directories like `config/` and `commands/` are shorthand that feeds these same five resources; the primitives are the real API, and the layout is just a tidy place to keep their inputs.

## Config — files you maintain

The Quick Start already showed the essential move:

```sh
homeworld config link config/.zshrc "$HOME/.zshrc"
```

This copies your file into the environment being built and keeps `~/.zshrc` pointing at it. Two properties are worth knowing:

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

Homeworld detects the platform and hands the right list to the right manager. Note what this feature is and isn't: packages here are *names*, resolved by your OS's package manager, and Homeworld ships no machinery for pinning their versions. If you need a tool at an exact version, the usual move is to reach for a resource that *is* exact — declare it as a repo pinned to a commit and build it, or wrap it in a command that runs a specific container image. And since `install.sh` is plain shell, nothing stops a module from pinning package versions itself; Homeworld just doesn't manage that for you, and it stays outside rollback either way. (Details in [Guarantees](#guarantees--and-their-limits).)

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

## State — the data that's yours, not Homeworld's

Here's where the pyenv module gets interesting. Homeworld rebuilds its environments freely — that's what makes updates and rollback safe. But `~/.pyenv/versions` holds the Python interpreters pyenv *built*: gigabytes, twenty minutes each. That data must never be rebuilt, rolled back, or cleaned up. It isn't Homeworld's.

**State** is how a module says so:

```sh
# in install.sh
homeworld state bind pyenv-versions "$HOME/.pyenv/versions"
```

Homeworld now knows this path by name — and knows to keep its hands off. It never copies, deletes, rolls back, or garbage-collects a state target. It manages the pointer; you own the data.

The name is what makes state portable. Your setup repository says `pyenv-versions`; each machine binds that name wherever its data actually lives — `/mnt/big-disk/pyenv` on the desktop, `~/.pyenv/versions` on the laptop. The same repository provisions both without a single `if` statement.

So the complete pyenv module — pinned tool, linked into place, with its mutable data protected — is two files:

```text
pyenv/
├── .homeworld-module
└── install.sh
```

```sh
# install.sh
homeworld repo add https://github.com/pyenv/pyenv pyenv
homeworld repo link pyenv "$HOME/.pyenv"
homeworld state bind pyenv-versions "$HOME/.pyenv/versions"
```

This split — immutable resources Homeworld can rebuild at will, mutable state it only points at — runs through the whole system. It's also what makes the next section's guarantees safe to give: Homeworld can swap and discard environments freely because your data was never inside them.

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

This buys you three promises:

* **A failed build changes nothing.** The generation you were using stays active; the broken one is discarded. There is no "died halfway through the setup script" state.
* **Interruption is recoverable.** Activation writes a journal before it mutates anything. Kill the process mid-swap — `Ctrl-C`, `kill`, a dropped SSH session — and the next Homeworld command finds the journal and finishes or reverses the transaction automatically. No repair command exists because none is needed.
* **Rollback is real.** The previous generation is a complete environment, kept on disk, one command away. Old generations beyond that are garbage-collected only after a successful activation — never before.

All of this careful machinery lives in the runtime, not in your files. Modules stay folders, manifests stay shell variables, package lists stay text files — so a setup repository remains readable to anyone who can read a directory tree, including you in two years.

## Everyday Commands

```sh
homeworld install                          # build a generation and activate it
homeworld install --dry-run                # preview the module and package plan
homeworld install --reinstall              # rebuild from scratch — old generation stays active until the new one succeeds
homeworld update                           # pull the latest setup repository
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

A useful way to read this table: it's mostly about *built-in machinery*, not hard limits. Chezmoi ships a template engine and secret-manager integrations; in Homeworld, `install.sh` is plain shell, so per-host logic or fetching secrets from your password manager are things you write, not things you configure. Nix Home Manager makes exact package closures the default; in Homeworld you get exactness where you build from pinned sources — repos at exact commits, tools compiled in `install.sh`, commands backed by specific container images — while anything delegated to `brew` or `apt` resolves to whatever your OS ships today. Homeworld's bet is that for a personal machine, that division of labor is the right default: exactness where it's cheap, your OS's package manager where it isn't, and a much lower cost of entry — your existing dotfiles are most of a setup repository already, and there's no new language to learn.

## Guarantees — and Their Limits

A provisioning tool earns trust by stating its boundary precisely.

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

The [full reference](docs/README.md) states each boundary in exact terms, down to symlink-replacement semantics per platform.

## Documentation & Support

* [**Full Reference**](docs/README.md) — every manifest field, resource verb, command, and the storage and transaction model in depth
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