# Homeworld Reference

This is the complete command surface, storage model, and set of guarantees. It assumes you've read the [main README](../README.md) and know the shape of a module.

## Contents

- [CLI reference](#cli-reference)
- [Command-line output](#command-line-output)
- [Modules](#modules) — discovery, the manifest, and the hook environment
- [The resource model](#the-resource-model) — the verbs, and what they always mean
- [Writing good modules](#writing-good-modules) — practices that keep the guarantees intact
- [Config](#config) · [Assets](#assets) · [Commands](#commands) · [Repositories](#repositories) · [State](#state)
- [Generations and activation](#generations-and-activation) — the transaction
- [Updates and reinstall](#updates-and-reinstall)
- [Locking and garbage collection](#locking-and-garbage-collection)
- [Metadata and compatibility](#metadata-and-compatibility)
- [Guarantees and their limits](#guarantees-and-their-limits)
- [Runtime layout](#runtime-layout)

---

## CLI reference

```text
homeworld init <path|url>

homeworld install [module] [--dry-run] [--reinstall] [--yes]
homeworld list
homeworld status
homeworld doctor

homeworld update [--dependencies] [--install]

homeworld repo add <source> <namespace> [--ref <ref>]
homeworld repo link <namespace> <destination>
homeworld repo path <namespace>
homeworld repo update <namespace|--all>

homeworld asset add <source> <name>
homeworld asset link <name> <destination>
homeworld asset path <module/name>

homeworld config add <source> <name>
homeworld config link <name> <destination>
homeworld config path <module/name>

homeworld command add <source> <name>
homeworld command path <name|self>

homeworld state bind <name> <path>
homeworld state link <name-or-absolute-path> <destination>

homeworld generation path [self]
homeworld generation list
homeworld generation rollback
homeworld generation gc

homeworld module path
```

Resource-creation commands require module installation context. They are called from an install hook. `state bind`, `repo update`, path queries, and generation operations are ordinary runtime commands you can run at any time.

The old top-level `rollback`, `generations`, `gc`, and `path` forms fail with migration guidance.

---

## Command-line output

Human-facing output uses stable uppercase labels so it is easy to scan and easy to grep. Status words stay in the first column of tables, and color, when enabled, decorates only the status word.

The install plan is a table. Nested modules are indented in the `MODULE` column, while `INSTALL` and `SKIP` remain fixed in the `STATUS` column:

```text
Module plan:
  STATUS   MODULE                DETAILS
  -------  ------                -------
  INSTALL  ai-tools              AI and machine learning tools
  INSTALL  docker                Docker utilities and GPU acceleration detection
  INSTALL    docker-linux        Docker on Linux with NVIDIA GPU support
  SKIP       docker-macos        unsupported on linux
  INSTALL  node                  Node.js runtime via nvm
```

Errors and hints use the same shape:

```text
homeworld: ERROR  unknown command: wat
homeworld: HINT   Run 'homeworld --help' for usage.
```

Warnings use `homeworld: WARN`. Test output and doctor checks use the same short status-token style.

---

## Modules

A module is any directory inside your setup repository containing a `.homeworld-module` file. That file is the only thing Homeworld looks for — how you arrange the directories around it is entirely up to you.

So this layout:

```text
~/dotfiles/
├── zsh/
│   └── .homeworld-module
├── neovim/
│   └── .homeworld-module
└── pyenv/
    └── .homeworld-module
```

is identical, as far as Homeworld is concerned, to this one:

```text
~/dotfiles/
├── shells/
│   └── zsh/
│       └── .homeworld-module
├── editors/
│   └── neovim/
│       └── .homeworld-module
└── languages/
    └── pyenv/
        └── .homeworld-module
```

and you can mix the two freely:

```text
~/dotfiles/
├── shells/
│   └── zsh/
│       └── .homeworld-module
├── neovim/
│   └── .homeworld-module
└── pyenv/
    └── .homeworld-module
```

Directories like `shells/` and `editors/` are for your benefit, not Homeworld's. Modules are found by their manifest, addressed by their `HOMEWORLD_MODULE_NAME`, and ordered by their declared dependencies — never by their path.

### The manifest

The manifest is POSIX shell. It may set:

```sh
HOMEWORLD_MODULE_NAME="zsh"
HOMEWORLD_DESCRIPTION="Zsh configuration"
HOMEWORLD_PLATFORMS="linux macos"
HOMEWORLD_DISTROS=""
HOMEWORLD_DEPENDS=""
HOMEWORLD_AUTO_INSTALL="true"
```

Only `HOMEWORLD_MODULE_NAME` is required. The root module may additionally set `HOMEWORLD_REQUIRES`.

Manifests and `install.sh` are **trusted code**. They run with your privileges. Homeworld doesn't sandbox them, and doesn't pretend to.

### The install hook

A module's `install.sh` is its **install hook**: the script Homeworld runs during a build, where all resource declarations live. While it runs, Homeworld exports:

| Variable | What it points at |
|---|---|
| `HOMEWORLD_MODULE_ROOT` | This module's directory |
| `HOMEWORLD_MODULE_NAME` | This module's name |
| `HOMEWORLD_PLATFORM` | `linux` or `macos` |
| `HOMEWORLD_DISTRO` | `arch`, `debian`, `fedora`, … |
| `HOMEWORLD_ROOT` | The **active** generation, via `current/` |
| `HOMEWORLD_BIN` | The active generation's `bin/` |
| `HOMEWORLD_TARGET` | The **new generation being built** |
| `HOMEWORLD_TARGET_BIN` | The new generation's `bin/` |

The `ROOT`/`TARGET` split matters: `ROOT` is the environment you're using right now, `TARGET` is the one under construction. A hook that needs to write a file into the environment it's building writes to `TARGET`.

---

## The resource model

Resource types and verbs. The verbs mean the same thing everywhere when a resource supports them:

| Verb | Meaning |
|---|---|
| `add` | Put the resource into the generation being built |
| `link` | Expose an already-named resource or state binding at a managed destination |
| `path` | Ask where a resource lives, generation-aware |
| `update` | Fetch new source data without touching the active environment |
| `bind` | Map a portable state name to machine-local storage |

The compact form:

```text
add  = manage it inside the generation
link = expose it at a Homeworld-owned destination
```

For config, assets, repos, and state, `link` exposes an existing named resource or binding. It does not secretly stage a source file.

One asymmetry is worth memorizing: **config, asset, and repo links point through `current/`; state links point straight at the real data.** That's the immutable/mutable line, drawn in symlinks. Activation swaps what `current/` resolves to, so every immutable link follows along for free. State doesn't follow — because state isn't Homeworld's to move.

(`current/` lives in Homeworld's data directory, `~/.local/share/homeworld/` by default — see [Runtime layout](#runtime-layout).)

---

## Writing good modules

Homeworld's guarantees cover what its primitives do. A hook is plain shell, so it *can* do anything — and everything it does outside the primitives runs outside the transaction: no rollback, no ownership checks, no cleanup. These practices keep your modules inside the part of the system that keeps promises.

**No live mutation in module hooks.** A hook should only calculate values, generate files under a temporary build location, and invoke resource declarations. It should not edit files in `$HOME`, restart services, or otherwise modify the environment you're currently using — that's what `link` and activation are for, and they do it transactionally. Any unavoidable side effect (running `pyenv install`, initializing a database) should be isolated in its own clearly named function, documented, and idempotent — so the deliberate exceptions are easy to find and safe to re-run.

**Write to `HOMEWORLD_TARGET`, never `HOMEWORLD_ROOT`.** `ROOT` is the environment you're using right now; a hook that writes into it has mutated live state behind the transaction's back. Generated files belong in the build. Write them under `TARGET` or a temp dir, declare them with `asset add`, and link the resulting asset where it belongs.

**Make hooks idempotent.** Hooks run on *every* build — install, reinstall, update. Anything expensive or side-effectful must be safe to run twice: check whether the Python version already exists before building it, whether the database is already initialized before seeding it. The primitives are already idempotent; your additions need to match.

**Assume the generation is disposable.** A generation should be rebuildable from the setup repository alone, on any machine. Generate assets in the hook rather than committing build artifacts; pin tools as repos rather than `curl | sh` from a moving URL; build from pinned sources when a version matters. If a repository needs a generated or patched file, declare that file as an asset and link it inside the repo view instead of editing the checkout. If deleting every generation and reinstalling wouldn't reproduce your environment, something is hiding outside the declarations.

**Pin downloaded artifacts explicitly.** Git sources get exact commits for free; anything a hook downloads by other means (release tarballs, prebuilt binaries) needs the same discipline by hand. Pin the release version — never "latest" — verify a checksum, and keep the architecture and platform selection visible in the hook rather than deferring to whatever a download page decides. Download to a temporary path and move into place only after verification, so a network failure leaves no partial artifact behind.

**Put anything a tool writes behind `state`.** Interpreter versions, caches, databases, history files — if it's written at runtime and would hurt to lose, bind it as state. Never let a tool write into a generation path: generations are rebuilt and garbage-collected, and data stored inside one will be rebuilt and garbage-collected with it. The pyenv pattern is the template — the tool is a pinned repo, its `versions/` directory is state.

**Keep state physically separate.** Prefer a home of its own for mutable data — `~/.local/share/<state-name>` — over nesting it beneath a managed repository tree. Homeworld handles nested state correctly (see [State](#state)), but a separate directory keeps the immutable/mutable boundary visible on disk: nothing under a checkout is ever a surprise, and nothing precious lives where everything around it is disposable.

**Absorb machine differences with names, not conditionals.** A state name binds to a different path on each machine; `HOMEWORLD_PLATFORM` and `HOMEWORLD_DISTRO` handle the OS-level splits; `HOMEWORLD_PLATFORMS` in the manifest excludes a module entirely. Reaching for these keeps `if` trees out of your configs and hooks — if a hook is accumulating per-machine branches, some of those branches probably want to be bindings or separate modules.

**Declare dependencies; don't rely on order.** If a module needs another's commands or config, say so with `HOMEWORLD_DEPENDS`. Discovery order is not a contract.

---

## Config

Files you maintain and want identical everywhere.

```sh
homeworld config add config/zshrc zshrc
homeworld config link zshrc "$HOME/.zshrc"
homeworld config path zsh/zshrc
```

Sources are relative to `HOMEWORLD_MODULE_ROOT`. Absolute paths, `..` traversal, and symlink sources are rejected.

**Naming.** The second argument to `config add` is the stable Homeworld name for this config inside the module. It uses the same name rules as assets: lowercase letters, numbers, dots, underscores, and hyphens. The source path is just where the bytes come from; the name is how other commands refer to the snapshot.

```text
homeworld config add config/zshrc zshrc
    → generation/config/zsh/zshrc

homeworld config add generated/app.conf app-conf
    → generation/config/zsh/app-conf
```

**Staging.** Files are copied to a temporary sibling path, then renamed into place once complete. A generation never contains a half-written config.

**The link.** `config link <name> <destination>` exposes an already-added config. An external config link resolves through `current/`:

```text
~/.zshrc  →  ~/.local/share/homeworld/current/config/zsh/zshrc
```

Homeworld will not overwrite an unmanaged file, directory, or foreign symlink at the destination. It stops and tells you.

If a config link targets a path inside a managed repository view, Homeworld composes it into that generation-local view, just like an asset overlay. The checkout is not modified.

---

## Assets

Immutable files or directories owned by a generation: themes, templates, generated data, downloaded tools, patched files, and other build results that Homeworld may safely recreate.

```sh
homeworld asset add generated/theme theme
homeworld asset link theme "$HOME/.local/share/theme"
homeworld asset path zsh/theme
```
An asset source can be a file or a directory, sourced from an absolute generated path or a module-relative one. Symlink sources are rejected. `asset add` snapshots the source into the pending generation. After that, changing or deleting the source path does not change the asset.

Assets are **recreated on every build**, never copied forward from the previous generation. If your hook generates a theme, it generates it fresh each time, so an asset in a generation always reflects the code that built it, not a fossil from three installs ago. Rollback restores whatever the selected generation had. GC removes an asset along with its generation.

### Asset links

`asset link <name> <destination>` exposes an already-added asset. If the destination is outside Homeworld-managed content, Homeworld creates a symlink that points through `current/`, just like config and repo links:

```text
~/.local/share/theme  ->  ~/.local/share/homeworld/current/assets/zsh/theme
```

If the destination is inside a managed directory resource, such as the path returned by `homeworld repo path`, Homeworld does not modify that directory. It builds a generation-local composed view instead.

```sh
homeworld repo add https://github.com/kohya-ss/sd-scripts.git sd-scripts
repo=$(homeworld repo path sd-scripts)

# requirements.txt was generated earlier by this hook.
homeworld asset add requirements.txt requirements
homeworld asset link requirements "$repo/requirements.txt"
```

The checked-out repository stays immutable. The active repository path becomes a view made from the checkout plus the asset replacement:

```text
sd-scripts checkout
+ requirements asset
= generation-local sd-scripts view
```

After activation, `homeworld repo path sd-scripts` returns that composed view. Rollback returns the view for the selected generation, including the matching asset contents.

### Asset overlay rules

Asset overlays are immutable and generation-owned, so they may intentionally replace existing repository files or directories. This is the supported way to model small patches or generated files inside a repository without editing the checkout.

Conflicts fail before activation. Homeworld rejects unsafe nested paths, duplicate incompatible destinations, ancestor/descendant overlay ambiguity, and attempts to cross a file as though it were a directory. Exact duplicate declarations that resolve to the same target are deduplicated.

Use state, not assets, for data that a tool should keep mutating after activation.

---

## Commands

Your scripts, on your `PATH`.

```sh
homeworld command add scripts/greet greet
homeworld command path greet
homeworld command path self
```

A command source is either a directory containing an executable `run`, or a plain executable file. Homeworld deploys it to `generation/commands/<module>/<name>/` and writes a launcher at `generation/bin/<name>`.

The launcher exports `HOMEWORLD_COMMAND_DIR` and `exec`s your command — so a command directory can carry helper files and find them at runtime.

Command names are globally unique within a generation. Two modules claiming `greet` is a build-time error, not a race.

---

## Repositories

Much of a working environment isn't in any package manager — it's a Git repository you're told to clone: pyenv, zsh plugins, themes, tools you build from source. A bare `git clone` in a setup script takes whatever the branch points at *that day*, so machines provisioned a week apart quietly diverge. Homeworld instead resolves every repository declaration to an exact commit at build time, and each generation permanently keeps the exact copy it was built with.

```sh
homeworld repo add <source> <namespace> [--ref <ref>]
homeworld repo link <namespace> <destination>
homeworld repo path <namespace>
homeworld repo update <namespace>
homeworld repo update --all
```

`repo add` and `repo link` are install-time declarations, called from a hook. `repo update` is a runtime cache operation and never changes the active environment.

### Two layers

On disk, a repository is split into a cache and its realizations:

```text
git/mirrors/<source-id>.git/             # mutable bare cache
git/checkouts/<source-id>/<commit>/      # immutable local clone, detached
```

The mirror is where fetched objects land; it changes every time you fetch. A checkout is an ordinary clone detached at one exact commit; it never changes after creation. **Generations reference checkouts, never mirrors** — which is why fetching new objects tomorrow can't change what a generation from today resolves to.

This split answers most practical questions about the `git/` directory: mirrors are disposable caches (deleting one costs you a refetch), checkouts are the actual contents of your generations (GC deletes them only when no generation needs them), and a `git fetch` gone wrong can at worst damage a mirror, never a checkout.

The isolation between the layers is deliberate. Checkouts are created with `git clone --local --no-hardlinks`, so their object files share no inodes with the mirror — without that flag, the two layers would share physical files, and marking a checkout read-only would silently alter the mirror's permission metadata. Each checkout is built at a temporary path, detached at its commit, renamed to its final commit-keyed location, and made read-only.

Read-only is an **accident guard, not a security boundary** — a process running as you can `chmod` it back. Homeworld's guarantee is behavioral: it treats published checkouts as immutable and never mutates them.

### Per-generation manifest

Each generation records what it declared:

```text
.homeworld/repo-manifest/<namespace>/
├── schema-version
├── source
├── source-id
├── ref-mode
├── ref
└── sha
```

Everything downstream reads these manifests directly: `repo update --all` uses them to decide what to fetch, and garbage collection uses them to decide which checkouts and mirrors are still referenced. There's no separate index of "known repositories" that could drift out of sync with what generations actually declare — so a stale index can never cause a wrong fetch or, worse, a wrong deletion.

A namespace can use a new URL or ref in a later generation. Homeworld notices the changed declaration, realizes it independently, and leaves the active generation alone until activation succeeds. Older generations keep their original source and commit. Two conflicting declarations for one namespace inside a single build is an error.

### Composed repository views

A repository checkout is immutable. When a config, asset, or state declaration targets a path beneath `homeworld repo path <namespace>`, Homeworld builds a generation-local view instead of changing the checkout. Unchanged entries are symlinks into the checkout. Config and asset entries point at immutable generation snapshots. State entries point through the state resolver.

The same public command resolves the right location:

```sh
repo=$(homeworld repo path sd-scripts)
```

If no nested resources exist, this is the checkout itself. If nested config, asset, or state entries exist, this is the composed view for the active or pending generation. Callers do not need a separate command.

Immutable config and asset overlays deliberately have different conflict rules from state. Configs and assets may replace repository content because they are immutable and generation-owned. State may only occupy absent paths because it remains mutable across rollbacks.

### Ref resolution

An explicit `--ref` must resolve to a commit. Homeworld peels to a commit rather than accepting whatever Git object it lands on.

Rejected: names ambiguously naming both a branch and a tag, option-shaped refs, reflog expressions, ambiguous abbreviated object IDs, and non-commit objects.

When `--ref` is omitted:

- remote sources use the remote symbolic `HEAD`
- local sources use symbolic `HEAD`
- detached local sources require an explicit ref

Default-branch changes are detected on later installs.

### Source identity

Homeworld deliberately avoids guessing that two URLs mean the same thing.

- Local paths → physical absolute paths; local symlinks resolve to their target
- `file://` → classified as local
- Remote URL spelling → preserved as written
- SCP-style SSH and `ssh://` → may produce separate cache identities
- Trailing `.git`, host case, default ports, percent encoding → **not** normalized
- Query strings and fragments → rejected
- Embedded HTTP credentials and password-style SSH credentials → rejected

This can produce duplicate caches for spellings you'd consider equivalent. That's the accepted cost: clever normalization occasionally merges two identities that only *look* the same, and that failure is far worse than a duplicate cache. Credential rejection exists so secrets never land in a manifest, a log, or an error message.

### Updates

`repo update` fetches mirror objects. That's all — no checkout is created, and the active environment doesn't change.

`repo update --all` reads the current generation's manifest, so a repo that disappears from your declarations stops updating automatically. No removal ritual exists because none is needed.

On network or auth failure, a healthy mirror is left alone. If Git reports the mirror corrupt, Homeworld quarantines it, rebuilds it once, and touches no existing checkout during the repair.

---

## State

State is mutable, persistent, and deliberately outside generations: caches, databases, built interpreters — data that would be absurd to rebuild and catastrophic to roll back.

```sh
homeworld state bind pyenv-versions "$HOME/.pyenv/versions"
homeworld state link pyenv-versions "$HOME/.local/share/pyenv-versions"
```

A module can also link a direct absolute path, skipping the name:

```sh
homeworld state link "/mnt/data/app" "$HOME/.local/share/app"
```

**Homeworld owns the destination symlink, not the target data.** It never copies, deletes, rolls back, garbage-collects, or changes permissions on a state target.

### Why bindings have names

A generation records the *name*, not the resolved path. That indirection is the point: `pyenv-versions` lives on `/mnt/big-disk` on your desktop and in `~/.pyenv/versions` on your laptop, and the same setup repository works on both, with zero conditional logic.

Names resolve through a single stable resolver in machine-local state (under `~/.local/state/homeworld/`), shared by every retained generation. That shared resolver is what makes rollback and state compose cleanly: old and new generations both look a name up in the same place, so rolling back changes which code and config you're running without rolling back your data.

Bindings are machine-local and versioned independently from generations. Rebind a name and every active consumer updates transactionally and automatically — no reinstall, no relink command.

Targets must already exist. Homeworld records whether each is a file or a directory, validates the type, and fails **before switching generations** if a target is missing or wrong — a half-bound environment never activates.

### Nested state

State can sit beneath a managed tree — the canonical case is `~/.pyenv/versions` living inside the pyenv repo link. Homeworld supports this without compromising either side of the immutable/mutable line.

The read-only checkout is never modified. Instead, each generation gets its own composed view of the managed directory: unchanged entries are symlinks into the checkout, and the state entry points through the resolver. Nothing named `versions` is inserted into the checkout itself. It exists only in that generation-local view. The view is built and fully validated before the activation journal opens and before `current` moves, so nested state obeys the same rule as everything else: no live change until the whole build has succeeded.

Conflicts fail loudly rather than quietly. If upstream later adds a real `versions` path to the repository, activation fails before `current` changes. Homeworld does not silently hide or replace upstream content with your state. When a destination could nest under more than one managed directory, Homeworld chooses the nearest declared managed ancestor; conflicting targets, unsafe path components, duplicate incompatible declarations, and attempts to store state *beneath a managed root* are all rejected. Multiple modules may declare the same nested destination as long as they resolve to the same target, and the declarations are deduplicated.

Nested state shares the same composed-view machinery as nested config and asset overlays, but the policy is different: immutable overlays may replace repository content, state may not.

(All of this said: physically separate state directories remain the tidier habit — see [Writing good modules](#writing-good-modules).)

---

## Generations and activation

Every install builds a fresh generation in its own directory. Until that build is complete and validated, it's invisible: **no active file or binding changes while it runs.** A failed build is an error message, not a broken shell.

**Activation** is the moment the finished generation becomes your environment, and it runs as a journaled transaction. The journal lives at `~/.local/state/homeworld/activation-journal/` and records:

- schema version
- target generation
- old `current` and `previous` pointers
- every binding creation, replacement, and removal
- the previous and new target for each affected destination
- transaction phase

Activation then:

1. acquires the global generation lock
2. repairs an unfinished prior transaction, if one exists
3. validates every desired destination
4. writes the complete journal
5. replaces `previous`
6. replaces `current`
7. creates or updates desired bindings
8. removes dropped bindings — but only where they still match Homeworld's expected target
9. clears the journal

Step 8 is conservative ownership at work: if something else changed a link Homeworld thought it owned, Homeworld leaves it alone rather than deleting a stranger's work.

**Every Homeworld invocation checks for an unfinished journal before doing anything else.** Recovery is automatic. No repair command exists because nothing needs repairing by hand.

Rollback is not a special code path — it invokes the same activation transaction with the previous generation as its target.

---

## Updates and reinstall

```sh
homeworld update                           # setup repository only
homeworld update --dependencies            # + fetch repos the current generation declares
homeworld update --dependencies --install  # + build and activate the result
```

Each flag adds one step. `update` alone changes nothing about your environment — it pulls a newer setup repository. Nothing builds or activates until `--install`.

```sh
homeworld install --reinstall
homeworld install --reinstall --yes
```

Reinstall never destroys a working environment to make room for its replacement. It builds normally while the old generation and its checkouts stay active; only after activation succeeds does GC remove what's now unreachable.

A failed reinstall leaves `current`, `previous`, bindings, rollback, and state untouched.

---

## Locking and garbage collection

The lock order is fixed, always:

```text
global generation/transaction lock
  → repository source lock
```

Install, activation, rollback, generation GC, reinstall cleanup, and state rebinding take the global lock. Repository fetch and checkout creation take source-specific locks. GC takes the global lock *before* any source lock.

That ordering is what stops GC from deleting a checkout out from under an in-progress build: a generation still being built counts as in use, exactly like `current` and `previous`, even though nothing points at it yet.

After activation or an explicit `generation gc`:

- generations other than `current` and `previous` are removed
- checkouts referenced by no retained or in-progress generation are removed
- mirrors referenced by no retained generation are marked orphaned
- orphan mirrors expire after a grace period
- a source that reappears clears its orphan marker

The grace period exists because deleting a mirror is cheap and refetching one is not.

Directory locks contain a PID and a process-start fingerprint, so a dead owner — or a rapidly reused PID — can't hold a stale lock forever.

---

## Metadata and compatibility

Generation metadata, repository manifests, managed links, state bindings, and journals all carry a `schema-version`.

Readers accept supported legacy metadata where they can. Missing mandatory metadata, or an unknown *newer* schema, fails clearly. Homeworld does not guess at a partially upgraded structure — a wrong guess about a generation's layout is a corrupted environment, and a clear error isn't.

The Homeworld binary is installed independently, so it can be newer than the generations you've retained. Rollback therefore reads metadata from the selected generation and validates its schema at use time, not install time.

---

## Guarantees and their limits

### What the transaction covers

The journaled activation is designed for:

- normal shell failure
- command failure
- process termination
- `HUP`, `INT`, `TERM`
- automatic recovery on the next invocation after an interrupted process

### What it doesn't promise

Portable shell has no cross-platform `fsync`. Homeworld writes to temporary sibling paths and renames before mutating, but claims no durability across:

- sudden power loss
- kernel panic
- storage-controller write reordering
- filesystem or hardware corruption

This applies equally to metadata replacement, orphan timestamps, journal phases, and generation-pointer updates. It's a real limit of portable shell programs in general, and Homeworld doesn't claim to escape it.

### Portability

The implementation and all module hooks use POSIX `sh`; no GNU-only syntax. The test matrix runs under the system `sh`, `dash`, and BusyBox `ash`.

Pointer replacement uses `mv -T` on GNU and BusyBox, `mv -h` on BSD/macOS. A minimal POSIX fallback avoids following the destination but can have a small visibility gap.

### Paths

Spaces, tabs, glob characters, leading hyphens, and Unicode all work wherever the filesystem supports them. Line breaks in metadata-bearing names and paths are rejected explicitly — they'd make the metadata format ambiguous.

Homeworld claims no adversarial protection against another same-user process changing a path between validation and replacement. Same-user processes are trusted, by construction.


## Runtime layout

```text
~/.local/share/homeworld/          # generations and git caches
├── current -> generations/<id>/
├── previous -> generations/<id>/
├── generations/
│   └── <id>/
│       ├── assets/
│       ├── bin/
│       ├── commands/
│       ├── config/
│       ├── repos/
│       └── .homeworld/
│           ├── managed-links/
│           ├── projections/
│           ├── projection-roots/
│           ├── resource-projections/
│           ├── repo-manifest/
│           ├── installed-modules
│           ├── source-revision
│           ├── status
│           └── schema-version
└── git/
    ├── mirrors/                   # disposable caches
    ├── checkouts/                 # generation contents — GC-managed
    └── orphaned/

~/.local/state/homeworld/          # machine-local, never inside a generation
├── source
├── source-mode
├── state-bindings/
├── activation-journal/
├── locks/
└── logs/

~/.cache/homeworld/                # safe to delete
└── repo/
```

XDG environment variables override the default roots.