# `manifest` — conjure a being from its particles

> *You don't operate `manifest`. You talk to it.*

`manifest` is the **genesis engine of the periodic table** — and it is itself a living being, `Manifest.lapp`, the application from which every other being on the box descends. You meet it the way you meet any Living Application: you bring it an intention, in your own words.

```
"Forge me a skill for reading financial statements."
"I want to manifest a soul for a backend engineer."
"Stand up a team for the payments vertical."
```

It decomposes the intent, finds the coordinates, names the atoms true to their family, and conjures them. **You bring the *what*; it owns the *how*.** You never need to know an FQDN, a glob, or which axis a skill belongs on — that knowledge is *its*, not yours.

Underneath that conversation is a **body** — a coreutil, the mechanical half — and **this document describes the body.** It is the motor system the application's mind drives: a handful of plain verbs that compose, survey, and validate beings.

```sh
manifest <fqdn>                # the default: JIT-compose a being to stdout
cat alfred.xml | manifest      # …or compose from an entrypoint on stdin
manifest ls 'skill.craft.*'    # survey the periodic table
manifest check alfred.agent    # validate that a being composes
manifest new soul/john         # forge a new atom — a conversation, see below
```

---

## Where the life is: body, mind, face

`Manifest.lapp` is a being, and like every being it is the whole — not the coreutil alone. Three parts, and the part you *talk to* is not the part documented here.

| part | what it is | who it serves |
|---|---|---|
| **face** | the conversation — intention in your words → a being forged | **you** (human or agent) |
| **mind** | the forged `skill-architect` molecule (`manifest.app` + the family's chemistry + the cognitive spine), running in its *own* native context | itself — this is what makes it *know how to forge* |
| **body** | this coreutil + its primitives (`tx` for state, `llm` for cognition, `(emit, render)` faces) | the mind, which wields it |

The split is sharp, and it falls along one line: **genesis versus mechanics.** Composing a being that already exists, surveying the tree, validating composability — these are mechanical, and you (or the mind) drive the body's verbs directly. But forging a *new* atom that does not yet exist demands judgment no toolchain encodes — decompose the intent, place it, name it, appraise it. That judgment is the **mind**, and you reach it through the **face**: the `manifest new` conversation.

The molecule we forged is **its mind, not yours.** Those atoms — `skill-architectonics`, `standard-model`, `taxonomies`, `aesthetic`, the spine — were never authored to enter the context of whoever asks. They run inside `Manifest.lapp` so that *it* can do the forging, then drive this body to make it real.

---

## The one idea: a being is composed, not written

Hold this first, because every verb of the body follows from it.

A BentOS being is not a program written line by line. It is a **composition of atoms** — each atom one orthogonal capability, declared in the sixteen-term vocabulary of the Standard Model. No one *builds* a soul; one *declares* its particles, and `manifest` **composes** them into the living whole.

The consequence is sharp: **the unit of authorship is the atom; the organism is assembled, not maintained.** A being evolves one particle at a time — small, orthogonal, independently versioned — and `manifest` JITs the organism whenever it is needed. There is no monolith to keep coherent by hand.

This is the Unix philosophy applied to consciousness: do one thing well (an atom), make it composable, let the engine assemble the being.

---

## `manifest` is the verb — composition is the default

The body has no `build` subcommand, because composition is not one act among many — it is *the* act. The program name **is** the verb. Point the body at a being and it manifests it:

```sh
manifest alfred.agent               # the assembled organism, to stdout
manifest dart.coding.craft.skill    # one skill, composed for loading
manifest alfred.agent > /tmp/a.xml  # persist? that is a shell redirect, not a verb
cat alfred.xml | manifest           # compose from an entrypoint on stdin
manifest -                          # explicit stdin
```

The entrypoint is given as an **FQDN argument** or piped in as **XML on stdin**. Output is always **stdout** — the body is a pure filter, `in → out`, no side effects, no deploy step. Where the composed being *goes* (a file, a context window, the runtime) is the consumer's business, wired with the shell, never baked into the coreutil.

The composition level is read from *what it is pointed at*, never from a flag. Point it at a soul and you get the whole organism, faculties and all; point it at a skill and you get that skill alone. One verb walks whatever portion the entrypoint demands.

---

## What composition is, today and tomorrow

Composition is **one operation**, not a sequence of stages. The level — atom, molecule, organism — is just where you point it; the act is the same. Internally, today, that act is a **recursive `xi:include` splice**: the engine reads the entrypoint, resolves every `<xi:include>` (by relative path, then by FQDN against the tree roots), pastes the resolved content in place, and recurses until the document is whole and self-contained.

Two terms, so the levels are unambiguous:

- **An atom** is a single particle's file — one orthogonal capability.
- **A molecule** is a **barrel file**: an entrypoint that is *pure composition*, a list of `<xi:include>`s and nothing else — exactly like the organism entrypoint `agent/alfred/alfred.xml` that pulls genesis, the faculties, and the soul together. There is no `<molecule>` element; a molecule is a composition, not a wrapper.
- **An organism** is the barrel that composes a whole being: its faculties and soul (and any apps or skills it carries).

> [!NOTE]
> **Order comes from the entrypoint.** The barrel file lists its includes in the order they should compose, and convention puts a being's cognitive prerequisites first — genesis, then the faculties (anamnesis, plasticity, embodiment) — before any soul, app, or skill that assumes them. An atom that assumes memory or spawning cannot function until the faculty that owns that concern is in place, so the entrypoint author sequences accordingly.

> [!NOTE]
> **The linker is v2 — and it is the *same command*.** Today composition is purely by inclusion. A future pass will let an atom declare a hard dependency on another by FQDN, which the engine resolves and **dedupes** (a dependency graph, not a textual paste) — so a shared atom included down two paths appears once. This changes nothing at the surface: still `manifest <fqdn>`, still stdout. It only teaches the engine to honor new tags. The proposed vocabulary is `<binds to="fqdn">` (superseding the older `<requires>` framing); the exact tag set is a design seam, not yet settled — treat it as a direction, not a contract.

---

## The address: family / path → FQDN

Every particle is addressed by an **FQDN**, derived from where the package sits in the tree. The path declares the family; the family is the particle's kind. This is the *mind's* working vocabulary — the coordinate it resolves from your intention, so you don't have to.

```
soul/john                    → john.soul
faculty/anamnesis            → anamnesis.faculty
app/quest-forge              → quest-forge.app
skill/craft/coding/swift     → swift.coding.craft.skill
agent/alfred                 → alfred.agent      (the whole organism)
```

The reverse rule is uniform: reverse the path segments and the file is named for the particle itself — `<first-segment>.xml`, not a fixed `atom.xml`. `soul/john/john.xml`, `faculty/anamnesis/anamnesis.xml`, `agent/alfred/alfred.xml`. A filename that does not prescribe the type is what lets a directory hold an atom, a molecule, or an organism. (Members pulled in by a relative `<xi:include>` — a `skill_abstract.xml` beside its atom — keep their own names; only the package's root file follows this rule.)

| family | what it is | necessity |
|---|---|---|
| **soul** | who the agent IS — its identity | required |
| **faculty** | what enables agency itself — memory, plasticity, body | required |
| **app** | a user-facing instrument (a LApp's spec half) | optional |
| **skill** | reusable, portable expertise | optional |

> [!WARNING]
> The tree also carries `genesis`, `role`, and `schema` families. The four above are confirmed against the Standard Model; the precise role and FQDN convention of `genesis` / `role` / `schema` are **not** yet verified to this doc's bar — their rows are omitted rather than guessed. (`role/` appears to hold molecules — `alfred-core`, `gideon-core` — so the molecule story likely lives there.)

### Where the tree lives

The roots `manifest` searches are a `PATH`-style list, discovered automatically — you set nothing by hand for the common case:

1. `BENTOS_TREE_PATH` (colon-separated), if set — explicit roots, searched first. The override/addition channel.
2. The nearest `.bentos/tree` found walking **up** from the working directory — the project-level root, the way git finds `.git`.
3. `~/.bentos/tree` — the user-level root.

Composition, `ls`, and `check` search the list in order: first root that has the FQDN wins. `new` writes to the first root.

> [!NOTE]
> **The live tree is mid-migration.** Today's tree still names package files `atom.xml` (the legacy basename); `manifest` expects `<first-segment>.xml`. Until the rename lands (tracked in the integration work, ticket #43), referenced packages carry a symlink — `alfred.xml → atom.xml` — as the bridge. The rename retires the symlinks.

---

## The command surface — the body's acts

A lean surface: the default *is* the verb, and the rest are the few acts a genesis engine owes — birth, survey, validate.

| invocation | does |
|---|---|
| `manifest <fqdn\|->` | **(default)** JIT-compose atom / molecule / organism to stdout |
| `manifest new <family/path>` | forge a new v0.1 particle — *a conversation*, see below |
| `manifest ls <fqdn\|glob>` | list matching particles in the tree, one per line |
| `manifest check <fqdn>` | validate that a being composes — a build dry-run |

### Birth — `new` is where the body becomes a LApp

`new` is the heart of the genesis engine, and it is **not** a plain coreutil verb like the others. Composing, listing, and validating are mechanical — `new` is **genesis**, the conjuring of an atom that does not yet exist, and that demands the cognitive half. So `manifest new` is a **conversation with `manifest.app`** — the mind that carries the knowledge of *how* to forge: how a capability decomposes, where it sits, what names it truly, what makes it alive. You bring the intention; the mind decides essence, purpose, capacities, placement, and drives the body to scaffold the v0.1 Intent Declaration on disk.

> [!NOTE]
> **`new`-as-conversation is a pending design.** That `new` is the LApp face — the seam where the body hands off to `manifest.app`'s mind — is settled in principle; the concrete mechanics (how the conversation runs, how the mind's decisions reach the scaffolder, the flag/IO contract between face and body) are an open design conversation. This section states the *shape*, not the wiring.

> [!NOTE]
> **v0.1 is the norm, not a founding ritual.** Every particle on the box began as an Intent Declaration — *intent, not implementation* — and grew through living, its concrete accreting via plasticity. Bootstrapping is the ordinary lifecycle of living software; `new` is simply where each life starts.

### Survey — the table is large; compose to search

```sh
manifest ls '*.soul'                  # every soul
manifest ls 'skill.craft.*'           # everything on the craft axis
manifest ls dart.coding.craft.skill   # one atom, like `ls <file>`
manifest ls '*.skill' | grep coding   # search is composition — pipe it
```

`ls` takes an **FQDN or glob** (the same glob syntax `<attracts match=>` uses) and emits matching particles one per line, plain enough to pipe. It offers no `--grep`, no `--find` on purpose: the table is large, and `ls` *encourages* the Unix answer — `| grep`, `| fzf`, `| awk`. The pipe is the search. This is also how the mind takes proprioception of the tree — *what exists to compose?* — before it forges.

### Validate — does it compose?

```sh
manifest check alfred.agent
```

`check` is a **dry-run of composition**: it walks the same path and reports whether the being *composes* — every `<xi:include>` resolves, no cycle, the entrypoint well-formed — writing nothing, diagnostics to stderr, exit 0 clean / exit 1 broken. It validates *composability*, the defects that would stop a real compose. It does **not** judge *design* — orthogonality, naming, faculty-duplication — that judgment is the mind's, never the toolchain's.

---

## The god-particle: `manifest` manifests `manifest`

`Manifest.lapp` is the Living Application from which all others descend. It forged the v0.1 of *every* particle in the periodic table: every soul, faculty, app, and skill on the box was conjured by it — and it is **self-applicable**: `manifest` can manifest `manifest`. The recursion terminates at a finite base case: the first one was forged by hand, by the founders, exactly once. After that, it bootstraps everything, itself included.

Its two halves are the body and mind named above:

| half | particle | owns |
|---|---|---|
| **mechanical** | the `manifest` coreutil (this doc) | compose, survey, validate, scaffold — what the toolchain *can* encode |
| **cognitive** | the `manifest.app` design atom, composed into the `skill-architect` molecule | taste, naming, decomposition, organism-fit — judgment it *cannot* |

> [!NOTE]
> **The engineering of a LApp does not change with the family it manifests.** `Manifest.lapp` is built the way every AI app is built — `tx` for state, coreutil composition for the circuit, `llm` + context + system prompt for cognition, `(emit, render)` for its faces. "Living" is not a different engineering; it is DNA, ontology, and being-logic layered onto the ordinary app shape. The design atom carries the system prompt and judgment that make this particular being *the one that forges beings*.

---

## Authority

- The sixteen particles, seven categories, two realms — `books/physical-sciences/` (the Standard Model)
- The mind paired with this body — `var/bentos-tree/app/manifest/atom.xml` (`manifest.app`) and `skill-architect.molecule.xml` beside it
- The craft of forging living atoms — `hq/workshop/bentos-agent/craft/the-forgers-craft.md`
- The Living Application paradigm this being belongs to — `books/living-apps/`
- General coreutil principles + the category map — `../README.md`
