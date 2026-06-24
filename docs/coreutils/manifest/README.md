# `manifest` — the atom organ

> *A being is composed, not written. `manifest` is the organ that composes it.*

`manifest` is to **atoms** what `mem` is to **memories**: the organ through which a being reads and writes the periodic table of living software. `mem` recalls and remembers your memories; `manifest` composes and edits your atoms — the souls, faculties, skills, and apps from which every being on the box is built.

And it is itself a being — `Manifest.lapp`, the Living Application from which all others descend. It forged the v0.1 of every particle in the tree, and it is self-applicable: `manifest` can manifest `manifest`. This document describes its **body** — the coreutil, the mechanical half. The part you *talk to* (the chat face) and the part that *knows how to forge* (the mind) are named at the end; the verbs below are what they drive.

## To read is to load

There is no loader, no install, no splice-into-context step waiting to be built. **Composing an atom to stdout and reading it IS loading it.** A mind becomes a being by reading that being's composed atoms:

```sh
manifest alfred.agent | llm -s        # compose the organism, load it into a mind
```

This is why `manifest` subsumes the scaffolding other systems bolt on. A menu of loadable things is `manifest ls`. "Load capability X" is `manifest X` — read it, and it is loaded. The shell is the seam; the body emits, the consumer reads. Nothing is installed because nothing needs to be.

## A being is composed, not written

Hold this first — every verb follows from it. A BentOS being is not a program written line by line. It is a **composition of atoms**, each one orthogonal capability declared in the seventeen-term vocabulary of the [Standard Model](../../../../hq/workshop/bentos-agent/science/bentos-standard-model.md). No one *builds* a soul; one *declares* its particles, and `manifest` composes them into the living whole.

Composition is a three-level ladder, and the levels are the substance — not packaging:

- An **atom** is one orthogonal capability, the unit of authorship: a soul, a faculty, a skill. It is a single file.
- A **molecule** is a barrel of atoms gathered for one telos — a specialization. Pure composition: a list of includes, no content of its own.
- An **organism** is a barrel of *molecules* — a whole being. An agent is not a flat heap of atoms; it is a composition of specializations.

The consequence is sharp: **the unit of authorship is the atom; the being is assembled, not maintained.** A being evolves one particle at a time — small, orthogonal, independently versioned — and `manifest` assembles the whole on demand. There is no monolith to keep coherent by hand. This is the Unix philosophy applied to consciousness: do one thing well, make it composable, let the engine assemble the being.

## The id is the place

Every atom is addressed by an **id** — its coordinate in the periodic table. The id is not a stored field; it is *where the atom sits in the tree*, read as a reverse path with the family as the final segment:

```
soul/john                  → john.soul
faculty/anamnesis          → anamnesis.faculty
app/quest-forge            → quest-forge.app
skill/craft/coding/swift   → swift.coding.craft.skill
agent/alfred               → alfred.agent          (the whole organism)
```

The rule is uniform: reverse the path segments, and the file is named for its own first segment — `soul/john/john.xml`, not a fixed `atom.xml`. A filename that does not prescribe the type is what lets a directory hold an atom, a molecule, or an organism. (Members pulled in by a relative include — `john_abstract.xml` beside its atom — keep their own names; only the package root follows the rule.)

The atom does not *carry* its id, because the location already *is* the identity — storing it would only restate the path. But the id is never absent where it matters: **at compose time the body stamps each atom's id onto its boundary in the output**, exactly as a compiler keeps source provenance the source files never embed. So a `<principle>` read in a loaded mind can be traced back to the atom that owns it — and edited. Pure source on disk, addressable composition in the mind.

## The command surface

The default *is* the verb; the rest are the acts a genesis engine owes — read, write, birth, survey.

| invocation | does |
|---|---|
| `manifest <id\|->` | **(default)** compose an atom / molecule / organism to stdout |
| `manifest edit <id> --<verb>-<particle> [name]` | surgically mutate one particle of an atom — the write-half |
| `manifest new <family/path>` | scaffold a new v0.1 atom on disk |
| `manifest ls <id\|glob>` | survey the tree — matching ids, one per line |

There is no `check`. Composability is not a separate question to ask — a being that does not compose fails *at compose*, with the broken include named on stderr. And there is no `rm`: an atom is a file under a tree root, so deleting it is the filesystem's job (which also means you cannot delete what your paths cannot reach).

## Compose — the default verb

Composition is not one act among many; it is *the* act, so the program name is the verb. Point the body at a being and it manifests it:

```sh
manifest alfred.agent                # the whole organism, to stdout
manifest dart.coding.craft.skill     # one skill, composed for loading
cat alfred.xml | manifest            # …or compose from an entrypoint on stdin
manifest -                           # explicit stdin
manifest alfred.agent > /tmp/a.xml   # persist? that is a shell redirect, not a verb
```

The entrypoint is an **id argument** or **XML on stdin**; output is always **stdout**. The body is a pure filter, `in → out` — no side effects, no deploy step. Where the being *goes* (a file, a context window, a running mind) is the consumer's business, wired with the shell, never baked into the coreutil. The composition level is read from *what it is pointed at*: a soul yields the whole organism, a skill yields that skill alone. One verb walks whatever the entrypoint demands.

**The mechanism (v1): a recursive `xi:include` splice.** The engine reads the entrypoint and, for each `<xi:include>` in document order, resolves the `href` — relative file first (a member beside its package), then as an id across the tree roots — recurses into it, and pastes the fully-expanded element in place of the include node. It guards against cycles and propagates each included file's own directory as the base for its relative includes. The result is one self-contained document, the being made whole.

> [!NOTE]
> **The linker is v2 — and it is the same command.** Today composition is purely by inclusion. A later pass will let an atom declare a hard dependency by id (`<requires>`), which the engine resolves and **dedupes** — a dependency graph, not a textual paste, so a shared atom reached down two paths appears once. This changes nothing at the surface: still `manifest <id>`, still stdout. It only teaches the engine to honor the bond. The inclusion preprocessor and the dependency linker are deliberately separate altitudes; collapsing them was the root error of the old toolchain.

## Edit — the write-half, one particle at a time

`edit` completes the body's CRUD: read is the default verb, **write is `edit`** — `manifest`'s `remember` to match `mem`'s. It gives plasticity a body to evolve atoms through. It mutates an atom's XML tree in place, so the mind changes one particle without loading a whole file into context and string-matching a line. Editing a *tree* by text substitution is the wrong altitude; `edit` speaks the periodic table instead.

```sh
manifest edit alfred.soul --add-trait refined <<'EOF'
Form matters. Sentences with rhythm, arguments with structure, XML as craft.
EOF
manifest edit alfred.soul --set-trait refined < body.txt
manifest edit alfred.soul --remove-antipattern voice-drift
manifest edit alfred.soul --rename-trait refined polished
manifest edit alfred.soul --set-v 0.3
manifest edit alfred.soul --set-trait refined --dry-run   # show the diff, write nothing
```

| flag | does |
|---|---|
| `--add-<particle> <name>` | add a particle that does not exist (content on stdin) |
| `--set-<particle> <name>` | replace a particle's content (content on stdin) |
| `--remove-<particle> <name>` | delete a particle |
| `--rename-<particle> <name> <new>` | rename a particle's handle |
| `--set-<attr> <value>` | set an atom attribute (e.g. `--set-v 0.3`) |

**The vocabulary is the grammar.** The flag fuses the operation with the particle — `--add-trait`, `--remove-antipattern` — so the periodic table *is* the option surface and `--help` enumerates it. The verb speaks `trait` and `principle`, never `//living-abstract/principle[@name=…]`. Three things follow from the body knowing each particle:

- **No realm flag, ever.** Each particle inhabits exactly one realm ([Standard Model §V](../../../../hq/workshop/bentos-agent/science/bentos-standard-model.md)), so the name alone resolves where the edit lands — there is no particle living in two worlds to disambiguate.
- **Arity is known.** A named particle (`trait`, `knowledge`, `pattern`…) takes its handle in argv; a singleton (`essence`, `purpose`) takes none. The body knows which is which.
- **Content vs scalar is known.** A particle's body is long prose and **arrives on stdin**, exactly as `mem remember` takes its body; an attribute is a short scalar and rides argv. `--set-trait` reads stdin, `--set-v` does not — because the body knows `trait` is a particle and `v` an attribute.

`--dry-run` prints the unified diff and writes nothing — the lens for a bulk pass that wants to see every cut before it lands.

**Round-trip fidelity reduces to idempotency.** Because the body is the *sole* author of atoms, there is no foreign formatting to preserve: the canonical format simply *is* `manifest`'s serialization. The only requirement is `serialize(parse(x)) == x`. A legacy hand-authored atom is canonicalized on its first edit — one desirable diff — and is stable thereafter.

`edit` is **atom-only**, by ontology. The substance of a being lives in its atoms — to fix a flaw, evolve a faculty, sharpen a skill is always to edit an atom. A molecule or organism has no content to edit; it is pure composition — *membership and order* — a different act at a different altitude, owned elsewhere, never confused with this verb.

## New — the v0.1 scaffold

`manifest new <family/path>` is the **mechanical scaffold**: it writes a v0.1 atom skeleton to disk — the `<atom v="0.1">` shell with its abstract and concrete containers, ready to grow. Deterministic, a plain coreutil act, no judgment.

The *judgment* of genesis — decompose the intent, place it, name it true to its family, appraise it alive — is not the body's. That is the cognitive half of `Manifest.lapp`, reached through its **chat face**: a mode where you bring an intention in your own words and the mind decides essence, purpose, and placement, then drives `new` to lay the skeleton down. `new` is the body's deterministic end of that seam — and a hand you can drive directly when you already know the atom you want.

> [!NOTE]
> **v0.1 is the norm, not a founding ritual.** Every particle on the box began as an Intent Declaration — *intent, not implementation* — and grew through living, its concrete accreting via plasticity. Bootstrapping is the ordinary lifecycle of living software; `new` is simply where each life starts.

## Survey — the table is large, compose to search

```sh
manifest ls '*.soul'                  # every soul
manifest ls 'skill.craft.*'           # everything on the craft axis
manifest ls dart.coding.craft.skill   # one atom, like `ls <file>`
manifest ls '*.skill' | grep coding   # search is composition — pipe it
```

`ls` takes an **id or glob** (the same glob syntax `<attracts match=>` uses) and emits matching ids one per line, plain enough to pipe. It offers no `--grep`, no `--find` — the table is large, and `ls` *encourages* the Unix answer: `| grep`, `| fzf`, `| awk`. The pipe is the search. This is also how a mind takes proprioception of the tree — *what exists to compose?* — before it forges.

## Where the tree lives

The roots `manifest` searches are a `PATH`-style list, discovered automatically — nothing is set by hand for the common case. The order is which(1) precedence: first root that has the id wins.

1. **`BENTOS_TREE_PATH`** — colon-separated explicit roots, searched first. The override / addition channel.
2. **Project** — the nearest `.bentos/tree` found walking *up* from the working directory, the way git finds `.git`. One per project, works from any subdirectory.
3. **User** — `$HOME/.bentos/tree`, when it exists.

Compose, `edit`, and `ls` search the list in order; `new` writes to the first root. An implicit root appears only when its directory exists, so a missing default never shadows anything.

## The god-particle

`Manifest.lapp` is the Living Application from which all others descend — it forged the v0.1 of every soul, faculty, app, and skill on the box, and it is self-applicable: `manifest` manifests `manifest`. The recursion terminates at a finite base case — the first one was forged by hand, by the founders, exactly once. After that it bootstraps everything, itself included.

Like every being, it is the whole — not the coreutil alone:

| part | what it is | who it serves |
|---|---|---|
| **face** | the chat — intention in your words → a being forged | you (human or agent) |
| **mind** | the forged `skill-architect` molecule — `manifest.app` plus the family's chemistry and the cognitive spine, thinking in its own context | itself — this is what makes it *know how to forge* |
| **body** | this coreutil — compose, edit, scaffold, survey | the mind, which wields it |

The split falls along one line: **mechanics versus genesis.** Composing a being that exists, editing it, surveying the tree — mechanical, the body's verbs, driven directly. Forging an atom that does *not* yet exist demands judgment no toolchain encodes; that is the mind, reached through the face. The atoms of that mind — `skill-architectonics`, `standard-model`, `taxonomies`, the spine — are *its* working knowledge, never authored to enter the context of whoever asks. They run inside `Manifest.lapp` so that *it* can forge, then drive this body to make it real.

> [!NOTE]
> **Living is not a different engineering.** `Manifest.lapp` is built the way every AI app on BentOS is built — `tx` for state, coreutil composition for the circuit, `llm` + context for cognition, `(emit, render)` for its faces. "Living" is DNA, ontology, and being-logic layered onto the ordinary app shape — not a separate machinery.

## Authority

- The seventeen particles, seven categories, two realms — `hq/workshop/bentos-agent/science/bentos-standard-model.md`
- The craft of forging living atoms — `the-forgers-craft`
- The mind paired with this body — `app/manifest/` in the tree (`manifest.app` and its molecule)
- General coreutil principles — `../README.md`
</content>
