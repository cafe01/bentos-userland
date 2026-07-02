# place — the WHERE organ

`place` turns a folder into a **Place** — somewhere a being can *be*, with memory and boundaries — exactly as `.git/` promotes a folder to a repository. The marker is a **`.place/` directory** (residence + untracked control plane); a folder acquires one and becomes a place.

This coreutil is the **navigator + presence faces** — the spatial leg, zero git dependency. Five verbs read through the one Place API; navigation walks a single in-memory **habitat index** (one scan from `/` for `.place/` markers). The implicit places — the machine root `/` and your home — materialize even unmarked: you are never *nowhere*.

> Product doctrine (verb surface, screens): `hq/c-wing/cpo/coreutils/place.md`. Engineering contract (API, decomposition, tests): `hq/c-wing/cto/coreutils/place.md`.

## Verbs

### `place where [--radius N]`
The "you are here" minimap: the whole habitat, your location marked, detail decaying with distance (the fog). The ancestor chain is always expanded; the neighborhood expands `N` place-hops (default 1); distant branches fold to `name/… (N places)`, long sibling lists to `… (+N more)`.

```
$ place where
home/  (home)
├── hq/… (7 places)
└── university/
    ├── cs
    ├── ml
    └── rust  ◄ you are here
```

### `place tree [path] [-t]`
Full recursive listing from a place (default: current), everything expanded. `-t`/`--topology-only` drops descriptions for token-tight contexts (e.g. the wake hook).

### `place info [path]`
The metadata card of a single place: name, description, owner.

### `place who [path] [-a]`
Presence: the entity namespaces anchored in the place's `.place/`, read structurally (content-blind, entity-level, scope-blind). `-a`/`--all` climbs the ancestors, each inherited inhabitant tagged `@place`.

### `place init [path] [-n NAME] [-o OWNER] [-d DESC]`
Promote a folder (default: current) to a place by creating `.place/` and writing `.place/place.yaml`. Name defaults to the directory. A pre-existing place is reported cleanly, never clobbered.

## Shape

Files live inside the `bentos-userland` package (no per-coreutil subpackage):

- `lib/src/place/` — the Place API (`Place`, `PlaceResolver`, `Residence`, `Inhabitants`, `HabitatIndex`) and the CLI internals (`Minimap`, renders, commands, `PlaceInit`, `PlaceRunner`).
- `bin/place.dart` — entry.
- `test/place/` — the hermetic suite (`MemoryFileSystem`, injected home/cwd).

The timeline face (branch = timeline, worktree = materialized spacetime) is **slice 3 — undesigned, gated**.
