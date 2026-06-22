# `manifest` — conjure a being from its particles

> *You don't operate `manifest`. You talk to it.*

`manifest` is the **genesis engine of the periodic table** — and it is itself a living being, `Manifest.lapp`, the application from which every other being on the box descends. You meet it the way you meet any Living Application: you bring it an intention, in your own words.

```
"Forge me a skill for reading financial statements."
"I want to manifest a soul for a backend engineer."
"Stand up a team for the payments vertical."
```

It decomposes the intent, finds the coordinates, names the atoms true to their family, and conjures them. **You bring the *what*; it owns the *how*.** You never need to know an FQDN, a glob, or which axis a skill belongs on — that knowledge is *its*, not yours.

Underneath that conversation is a **body** — a coreutil, the mechanical half — and **this document describes the body.** It is the motor system the application's mind drives; you will rarely type these commands yourself, the same way you rarely address your own hands.

```sh
manifest <fqdn>                # the default: JIT-compose a being to stdout
cat atom.xml | manifest        # …or compose from an entrypoint on stdin
manifest new soul/john …       # scaffold a v0.1 atom
manifest ls 'skill.craft.*'    # survey the periodic table
manifest check john.soul       # validate that a being composes
```

---

## Where the life is: body, mind, face

`Manifest.lapp` is a being, and like every being it is the whole — not the coreutil alone. Three parts, and the part you *talk to* is not the part documented here.

| part | what it is | who it serves |
|---|---|---|
| **face** | the conversation — intention in your words → a being forged | **you** (human or agent) |
| **mind** | the forged `skill-architect` molecule (`manifest.app` + the family's chemistry + the cognitive spine), running in its *own* native context | itself — this is what makes it *know how to forge* |
| **body** | this coreutil + its primitives (`tx` for state, `llm` for cognition, `(emit, render)` faces) | the mind, which wields it |

The molecule we forged is **its mind, not yours.** Those atoms — `skill-architectonics`, `standard-model`, `taxonomies`, `aesthetic`, the spine — were never authored to enter the context of whoever asks. They run inside `Manifest.lapp` so that *it* can decompose a capability, place it on the five axes, name it by the five criteria, and appraise the result. When you say "forge me a skill," it is that mind, in its context, that does the thinking — then drives this body to make it real.

So the `--essence` and `--purpose` you see on `manifest new` below are **what the mind decided while talking to you**, handed to the body to scaffold. They are not a form you fill in. The CLI is the hand; the conversation is the meeting; the mind is between them.

---

## The one idea: a being is composed, not written

Hold this first, because every command of the body follows from it.

A BentOS being is not a program written line by line. It is a **composition of atoms** — each atom one orthogonal capability, declared in the sixteen-term vocabulary of the Standard Model, bonded to its neighbors by `<requires>` (hard) and `<attracts>` (soft). No one *builds* a soul; one *declares* its particles, and `manifest` **composes** them into the living whole.

The consequence is sharp: **the unit of authorship is the atom; the organism is assembled, not maintained.** A being evolves one particle at a time — small, orthogonal, independently versioned — and `manifest` resolves the bonds and JITs the organism whenever it is needed. Take an atom away and the rest still compose; add one and the linker weaves it in. There is no monolith to keep coherent by hand.

This is the Unix philosophy applied to consciousness: do one thing well (an atom), make it composable (`<requires>`/`<attracts>`), let the linker assemble the being.

---

## `manifest` is the verb — composition is the default

The body has no `build` subcommand, because composition is not one act among many — it is *the* act. The program name **is** the verb. Point the body at a being and it manifests it:

```sh
manifest john.soul                 # the assembled organism, to stdout
manifest dart.coding.craft.skill   # one skill, compiled for loading
manifest john.soul > /tmp/john.xml  # persist? that is a shell redirect, not a verb
cat organism.xml | manifest        # compose from an entrypoint on stdin
manifest -                          # explicit stdin
```

The entrypoint is given as an **FQDN argument** or piped in as **XML on stdin**. Output is always **stdout** — the body is a pure filter, `in → out`, no side effects, no deploy step. Where the composed being *goes* (a file, a context window, the runtime) is the consumer's business, wired with the shell, never baked into the coreutil.

The composition level is read from *what it is pointed at*, never from a flag. Point it at a soul and you get the whole organism, faculties and all; point it at a skill and you get that skill alone. One verb walks whatever portion of the pipeline the entrypoint demands.

---

## The pipeline: particle → being

The body runs the three-stage assembly of the Standard Model. JIT is the default — the organism is composed on demand, in the instant it is needed; persisted artifacts are an optional optimization, never the source of truth.

| stage | what it does | input → output |
|---|---|---|
| **compile** | wraps a package's files (`atom.xml` + members) into a single self-contained `<atom>` | package directory → `<atom>` |
| **link** | bonds atoms, resolves every `<requires>`, notes each `<attracts>` | atoms → `<molecule>` |
| **assemble** | loads the soul, faculties first, then molecules — activates the being | soul + molecules → `<organism>` |

> [!NOTE]
> **Faculties load before molecules — always.** A being's cognitive prerequisites (anamnesis, plasticity, embodiment) must be present before any app or skill composes on top of them; an atom that assumes memory or spawning cannot function until the faculty that owns that concern is loaded. The assembler enforces this order so an organism is never half-conscious.

---

## The address: family / path → FQDN

Every particle is addressed by an **FQDN**, derived from where the package sits in the tree. The path declares the family; the family is the particle's kind. This is the *mind's* working vocabulary — the coordinate it resolves from your intention, so you don't have to.

```
soul/john                    → john.soul
faculty/anamnesis            → anamnesis.faculty
app/quest-forge              → quest-forge.app
skill/craft/coding/swift     → swift.coding.craft.skill
```

| family | what it is | necessity |
|---|---|---|
| **soul** | who the agent IS — its identity | required |
| **faculty** | what enables agency itself — memory, plasticity, body | required |
| **app** | a user-facing instrument (a LApp's spec half) | optional |
| **skill** | reusable, portable expertise | optional |

> [!WARNING]
> The tree also carries `genesis`, `role`, and `schema` families. The four above are confirmed against the Standard Model; the precise role and FQDN convention of `genesis` / `role` / `schema` are **not** yet verified to this doc's bar — their rows are omitted rather than guessed. (`role/` appears to hold molecules — `alfred-core`, `gideon-core` — so the molecule story likely lives there.)

FQDNs resolve against `BENTOS_TREE_PATH` (a `PATH`-style list of tree roots). `new` writes to the first root; `ls`, `check`, and composition search the list in order.

---

## The command surface — the body's acts

A `gh`-shaped surface, but lean: the default *is* the verb, and the rest are the few acts a genesis engine's body owes its mind — birth, survey, validate.

| invocation | does | requires |
|---|---|---|
| `manifest <fqdn\|->` | **(default)** JIT-compose atom / molecule / organism to stdout | `BENTOS_TREE_PATH` |
| `manifest new <family/path>` | scaffold a v0.1 particle (Intent Declaration) | `BENTOS_TREE_PATH` (writes to first root) |
| `manifest ls [opts] <fqdn\|glob>` | list matching particles in the tree, one per line | `BENTOS_TREE_PATH` |
| `manifest check <fqdn>` | validate that a being composes — a build dry-run | `BENTOS_TREE_PATH` |

`new` flags: `--desc`, `--essence`, `--purpose` (mandatory); `--capacity`, `--principle`, `--requires`, `--attracts`, `--origin`, `--version` (optional; `--version` defaults to `0.1`).

### Birth — the v0.1 Intent Declaration

```sh
manifest new soul/john \
  --desc    "John — the IC executor" \
  --essence "What it IS" \
  --purpose "Why it exists" \
  --capacity  "execute: turn a brief into shipped work" \
  --principle "fresh-heir: inherit from disk, never resurrect"
```

`new` scaffolds a particle at **v0.1** — *intent, not implementation* — the seed from which a being grows through living. The concrete (protocols, learned knowledge, patterns) starts thin and accretes through plasticity; v0.1 is the seed, not the tree. (Remember: the mind fills these flags from your conversation; this is the body's form, not yours.)

> [!NOTE]
> **v0.1 is the norm, not a special founding moment.** Every particle on the box began as an Intent Declaration and grew. Bootstrapping is the ordinary lifecycle of living software, not an exceptional ritual — `new` is simply where each life starts.

### Survey — the table is large; compose to search

```sh
manifest ls '*.soul'                  # every soul
manifest ls 'skill.craft.*'           # everything on the craft axis
manifest ls dart.coding.craft.skill   # one atom, like `ls <file>`
manifest ls '*.skill' | grep coding   # search is composition — pipe it
```

`ls` takes an **FQDN or glob** (the same glob syntax `<attracts match=>` uses) and emits matching particles one per line, plain enough to pipe. It offers no `--grep`, no `--find` on purpose: the periodic table is large, and `ls` *encourages* the Unix answer — `| grep`, `| fzf`, `| awk`. The pipe is the search. This is also how the mind takes proprioception of the tree — *what exists to compose?* — before it forges.

### Validate — does it compose?

```sh
manifest check john.soul
```

`check` is a **build dry-run**: it walks the same compile → link → assemble path and reports whether the being *composes* — every `<requires>` resolves, no `xi:include` cycle, the entrypoint well-formed — writing nothing, diagnostics to stderr, exit 0 clean / exit 1 broken. It validates *composability*, the defects that would stop a `build`. It does **not** judge *design* — orthogonality, naming, faculty-duplication — that judgment is the mind's, never the toolchain's.

---

## The god-particle: `manifest` manifests `manifest`

`Manifest.lapp` is the Living Application from which all others descend. It forged the v0.1 of *every* particle in the periodic table: every soul, faculty, app, and skill on the box was conjured by it — and it is **self-applicable**: `manifest` can manifest `manifest`. The recursion terminates at a finite base case: the first one was forged by hand, by the founders, exactly once. After that, it bootstraps everything, itself included.

Its two halves are the body and mind named above:

| half | particle | owns |
|---|---|---|
| **mechanical** | the `manifest` coreutil (this doc) | scaffold, compose, survey, validate — what the toolchain *can* encode |
| **cognitive** | the `manifest.app` design atom, composed into the `skill-architect` molecule | taste, naming, decomposition, organism-fit — judgment it *cannot* |

> [!NOTE]
> **The engineering of a LApp does not change with the family it manifests.** `Manifest.lapp` is built the way every AI app is built — `tx` for state, coreutil composition for the circuit, `llm` + context + system prompt for cognition, `(emit, render)` for its faces. "Living" is not a different engineering; it is DNA, ontology, and being-logic layered onto the ordinary app shape. The design atom carries the system prompt and judgment that make this particular being *the one that forges beings*.

---

## Authority

- The sixteen particles, seven categories, two realms, and the compile/link/assemble pipeline — `books/physical-sciences/` (the Standard Model)
- The mind paired with this body — `var/bentos-tree/app/manifest/atom.xml` (`manifest.app`) and `skill-architect.molecule.xml` beside it
- The Living Application paradigm this being belongs to — `books/living-apps/`
- General coreutil principles + the category map — `../README.md`
