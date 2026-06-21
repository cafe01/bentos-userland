# `manifest` — conjure a being from its particles

```sh
manifest new soul/john --desc "…" --essence "…" --purpose "…"   # birth a v0.1 atom
manifest check john.soul                                         # validate against the Standard Model
manifest build john.soul                                         # JIT the composed organism to stdout
manifest install john.soul                                       # deploy it into the runtime
```

`manifest` is the **genesis engine of the periodic table**. Everything that lives on the box — a soul, a faculty, an app, a skill — is composed from the fifteen XML particles of the Standard Model. `manifest` is the one program that takes those particles and **brings a being into existence**: it scaffolds a particle's v0.1, validates it against the ontology, and JIT-composes the final `<organism>` that the runtime assembles into a running agent.

The name is the act, twice over: it reads a **`manifest`** (the declarative `atom.xml` — the spec) and it **manifests** the particle (conjures it into being). Declaration and manifestation are the same verb here, because that is precisely the living-software arc: *from an intent declaration, a being is made real.*

> [!IMPORTANT]
> **`manifest` synthesizes; it does not author.** It is the *mechanical* half of bringing a particle into being — scaffold, validate, compose, deploy. The *cognitive* half — taste, naming, decomposition, organism-fit — is judgment no toolchain can encode; it lives in the paired design atom (`manifest.app`). Together, coreutil + design atom = **`Manifest.lapp`**, a Living Application like any other. This README documents the coreutil. (See *The god-particle*, below, for the pairing.)

---

## The one idea: a being is composed, not written

Hold this first, because every command follows from it.

A BentOS being is not a program you write line by line. It is a **composition of atoms** — each atom one orthogonal capability, declared in the fifteen-term vocabulary, bonded to its neighbors by `<requires>` (hard) and `<attracts>` (soft). You do not *build* a soul; you *declare* its particles and `manifest` **composes** them into the living whole.

The consequence is sharp: **the unit of authorship is the atom; the organism is assembled, not maintained.** You evolve one particle at a time — small, orthogonal, independently versioned — and `manifest` resolves the bonds and JITs the organism every time it is needed. Take an atom away and the rest still compose; add one and the linker weaves it in. There is no monolith to keep coherent by hand.

This is the Unix philosophy applied to consciousness: do one thing well (an atom), make it composable (`<requires>`/`<attracts>`), let the linker assemble the being.

---

## The pipeline: particle → being

`manifest` runs the three-stage assembly of the Standard Model. JIT is the default — the organism is composed on demand, in the instant it is needed; pre-built artifacts are an optional optimization, never the source of truth.

| stage | what it does | input → output |
|---|---|---|
| **compile** | wraps a package's files (`atom.xml` + members) into a single self-contained `<atom>` | package directory → `<atom>` |
| **link** | bonds atoms, resolves every `<requires>`, notes each `<attracts>` | atoms → `<molecule>` |
| **assemble** | loads the soul, faculties first, then molecules — activates the being | soul + molecules → `<organism>` |

A single `manifest build <fqdn>` walks whichever portion of this pipeline the entrypoint demands: build an atom and you get the compiled atom; build a soul and you get the fully assembled organism, faculties and all. The composition level is read from *what you point it at*, not from a flag.

> [!NOTE]
> **Faculties load before molecules — always.** A being's cognitive prerequisites (anamnesis, plasticity, embodiment) must be present before any app or skill composes on top of them; an atom that assumes memory or spawning cannot function until the faculty that owns that concern is loaded. The assembler enforces this order so an organism is never half-conscious.

---

## The address: family / path → FQDN

Every particle is addressed by an **FQDN**, and the FQDN is derived from where the package sits in the tree. The path declares the family; the family is the particle's kind.

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
> The tree also carries `genesis`, `role`, and `schema` families alongside the four canonical ones above. I am confident of the four families documented in the Standard Model (soul / faculty / app / skill); I have **not** verified the precise role and FQDN convention of `genesis` / `role` / `schema` to the bar this doc holds. Their rows are deliberately omitted rather than guessed — to be filled when confirmed.

FQDNs resolve against `BENTOS_TREE_PATH` (a `PATH`-style list of tree roots). `manifest new` writes to the first root; resolution for `check`/`build` searches the list in order.

---

## Walkthrough

### Birth a particle — the v0.1 Intent Declaration

```sh
manifest new soul/john \
  --desc    "John — the IC executor" \
  --essence "What it IS" \
  --purpose "Why it exists" \
  --capacity  "execute: turn a brief into shipped work" \
  --principle "fresh-heir: inherit from disk, never resurrect"
```

`manifest new` scaffolds a particle at **v0.1** — *intent, not implementation*. This is the genesis act: the minimal declaration from which the being grows through living. The concrete (protocols, learned knowledge, patterns) starts thin and accretes through plasticity; v0.1 is the seed, not the tree.

> [!NOTE]
> **v0.1 is the norm, not a special founding moment.** Every particle on the box began as an Intent Declaration and grew. Bootstrapping is the ordinary lifecycle of living software, not an exceptional ritual — `manifest new` is simply where each life starts.

### Validate against the ontology

```sh
manifest check john.soul
```

`check` validates three things, and writes nothing — diagnostics go to stderr, exit 0 = clean (warnings allowed), exit 1 = errors:

- **structural** — well-formed XML, `atom.xml` present;
- **schema** — Standard Model compliance (the fifteen terms, the seven categories);
- **includes** — `xi:include` resolution and cycle detection.

`check` validates *structure*. It cannot judge *design* — whether the decomposition is orthogonal, the name beautiful, the atom free of faculty duplication. That assessment is the design atom's job (*The god-particle*, below).

### Compose the being

```sh
manifest build john.soul                 # the assembled organism, to stdout
manifest build john.soul > /tmp/john.xml  # redirect to write anywhere
cat organism.xml | manifest build -       # compose from stdin
```

`build` is the JIT: it composes the entrypoint into its final XML and prints it. Point it at a soul and you get the whole organism; point it at a skill and you get that skill compiled for runtime loading. It reads `BENTOS_TREE_PATH` to resolve every FQDN it encounters while walking the bonds.

### Deploy into the runtime

```sh
manifest install john.soul
```

`install` places the composed artifact where the runtime loads it.

> [!WARNING]
> I am **not** confident of `install`'s exact contract. The design atom's `forge` protocol references an install step (deploy a built particle into the runtime — today, the prosthetic vessel's `.claude/skills/`), but the current body surface exposes only `new`/`check`/`build`. Whether `install` is a distinct verb, a flag on `build`, or a separate deploy path is **unresolved** and must be pinned during implementation. The antipattern it enforces is firm regardless: *never hand-edit the deployed artifact — evolve the source atom, then re-install.*

---

## The command surface

The `gh` shape: a verb per act, the entrypoint addressed by FQDN or family-path.

| command | does | requires |
|---|---|---|
| `manifest new <family/path>` | scaffold a v0.1 particle (Intent Declaration) | `BENTOS_TREE_PATH` (writes to first root) |
| `manifest check <fqdn>` | validate against the Standard Model | `BENTOS_TREE_PATH` |
| `manifest build <fqdn\|->` | JIT-compose atom / molecule / organism to stdout | `BENTOS_TREE_PATH` |
| `manifest install <fqdn>` | deploy the composed particle into the runtime | *(contract unresolved — see callout)* |

`new` flags: `--desc`, `--essence`, `--purpose` (mandatory); `--capacity`, `--principle`, `--requires`, `--attracts`, `--origin`, `--version` (optional; `--version` defaults to `0.1`).

> [!TIP]
> **The verbs name the mechanics; the meaning lives in the atoms.** `manifest` knows how to compile, bond, and assemble particles — it does not know what a soul *means* or what a faculty *does*. It imposes one opinion (the Standard Model vocabulary and the assembly order) and nothing more. The semantics live in the particles themselves.

---

## The god-particle: `manifest` manifests `manifest`

`manifest` is itself a **Living Application** — `Manifest.lapp` — and it is the one from which all others descend. It forges the v0.1 of *every* particle in the periodic table: every soul, faculty, app, and skill on the box was conjured by it. It is the genesis engine, and it is **self-applicable** — `manifest` can manifest `manifest`. The recursion terminates at a finite base case: the first `manifest` was forged by hand, by the founders, exactly once. After that, it bootstraps everything, itself included.

Like every LApp, it is a pairing — the same shape as `chat`, `teams`, and the rest:

| half | particle | owns |
|---|---|---|
| **mechanical** | the `manifest` coreutil (this doc) | scaffold, validate, compose, deploy — what the toolchain *can* encode |
| **cognitive** | the `manifest.app` design atom | taste, naming (the five criteria), decomposition, organism-fit — judgment it *cannot* |

> [!NOTE]
> **The engineering of a LApp does not change with the family it manifests.** `manifest` is built the way every AI app is built — `tx` for state, coreutil composition for the circuit, `llm` + context + system prompt for cognition, `(emit, render)` for its faces. "Living" is not a different engineering; it is DNA, ontology, and being-logic layered onto the ordinary app shape. The design atom carries the system prompt and judgment that make this particular app *the one that forges beings*.

---

## Authority

- The fifteen particles, seven categories, and the compile/link/assemble pipeline — `books/physical-sciences/` (the Standard Model)
- The design judgment paired with this coreutil — `var/bentos-tree/app/manifest/atom.xml` (`manifest.app`)
- The Living Application paradigm this engine serves — `books/living-apps/`
- General coreutil principles + the category map — `../README.md`
</content>
</invoke>
