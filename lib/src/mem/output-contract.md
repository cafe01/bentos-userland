# The account: what `mem` says about what it did

Normative. A builder obeys this without re-deriving it.

`mem`'s interface quality is its product quality: the organ exists to keep an agent oriented, and an organ that acts without saying what it did leaves the caller less oriented than before. This contract governs the **output** of every verb — success and failure — across `walk`, `recall`, `survey`, `health`, `remember`, `refocus`, `forget`, `tag`, `gist`.

Out of scope, named because this design touches their seams: `mem search` (semantic; blocked on embeddings and a bentos-kernel dependency — when it lands it obeys this contract unchanged), renaming `survey` to `index`, and the empty-body and dirty-checkout guards.

## 1. The outcome record

**R1.1 — A verb computes an outcome, then renders it. It never prints as it goes.**

Every `run()` produces one `Outcome` value and hands it to a renderer. No `cli.out.add` or `cli.diagnostics.add` inside the body of a verb's logic. This is the spine: the frame is a renderer over the outcome, a hint is a predicate over the outcome, and `--shape` is a second renderer over the same outcome rather than a parallel code path.

**R1.2 — The outcome carries cost.** Pages, words, links followed. Cost is what a caller budgets against, and today it is reachable only through `--dry-run`.

`walk` already has this record: `Walked{reached, skipped, weight}` with `Weight{pages, words, links}` (`walk.dart`). Nothing in the core needs building for `walk` — `WalkCommand.run` simply discards it. The remaining verbs have no record and get one.

**R1.3 — The outcome is a data class with no I/O and no clock.** This is what makes hint predicates pure and testable.

**R1.4 — Seam, named and NOT built: `--json`.** With R1.3 held, a `--json` face is one more renderer over `Outcome`. Do not build it. Do not add a flag. Do not shape the record around a serializer.

## 2. Frame and hint

Two mechanisms, and confusing them is the defect this contract exists to prevent.

**R2.1 — Frame: always emitted, factual, no imperative.** One block, one to three lines, stating what was attempted and what it cost. It is a receipt. It never teaches and never contains a verb addressed to the caller.

**R2.2 — Hint: conditional, teaching, imperative.** Fires on a condition of the outcome, states a lesson, and names the next command. At most **two** hints per invocation.

**R2.3 — A rule that fires in ordinary use is frame, not a hint.** A hint that prints every time is wallpaper: unread within three sessions, then pure token cost forever. This is an authoring law enforced at review, not by the machine. Test: *does this fire on a healthy brain doing normal work?* If yes, it is either frame or it does not exist.

This rule kills the obvious candidate. "N links were not followed (filter: attention)" fires on every wake by construction — a band is filtration. It is **frame**.

**R2.4 — The frame is one contiguous block, emitted after the artifact.** No leading banner. Two reasons: stdout and stderr are independently buffered, so a frame split around the artifact scrambles on a piped terminal; and through MCP the streams arrive as separate labelled blocks, so a leading line buys nothing and costs a line on every call forever.

**R2.5 — Every frame and hint line is prefixed `mem: `.** stderr is shared; the speaker identifies itself.

## 3. Streams

**R3.1 — stdout is the artifact. stderr is the account.** The artifact is what the caller asked to obtain: the composition, the index block, the page bodies, the health table. The account is the frame and the hints.

Verified, not assumed:
- `bentos-agent spawn` composes a mind by `Process.run('mem', ['walk', …])` and returns **`result.stdout` only**, forwarding stderr to its own stderr (`spawn_command.dart:321-330`). The machine consumer already ignores the account. No change to `spawn`.
- An agent calling `mem` through MCP receives **both**: `program.dart:193-194` returns `stdout` and `stderr` as separate labelled `TextContent`, on the success path, the non-zero-exit path, and the timeout path. **The spine is confirmed.**
- One caveat, and it is the only one: on a **timeout**, drain is bounded by `_drainGrace`, so stderr can truncate there. Acceptable — a timed-out call has worse problems than a lost frame.

**R3.2 — The artifact is defined per verb by what the caller asked for, and `--shape` moves the boundary.** Under `--shape` the caller asked for the traversal itself, so the ring table *and the not-entered table* are artifact and go to stdout. In an ordinary walk the not-entered detail is account and is summarised in the frame. Same outcome record, two renderers, one boundary that moves once.

## 4. One law, one home

**R4.1 — Three homes, no overlap.**
- `--help` states **grammar**: what may be typed, and what each option selects. Nothing about outcomes.
- The **frame** states **what happened**.
- A **hint** states **what to do next, given what happened**.

A sentence living in two of the three is a defect.

**R4.2 — Delete the apologies from help.** `health --help` calls its own bare count "the naive number". Help knows the output misleads and says so where the caller cannot act on it. Delete that sentence; the frame now states orphans and dead links as counts, which is the fact the apology was standing in for.

## 5. The hint mechanism

A registry of rules, extended the way a lint rule is added.

```dart
final class HintRule {
  const HintRule({
    required this.id,          // stable, kebab-case; names the rule in tests
    required this.verbs,       // which verbs it may fire on
    required this.fires,       // bool Function(Outcome) — pure
    required this.render,      // String Function(Outcome) — one line
  });
}

const hintRules = <HintRule>[ /* §6, in priority order */ ];
```

**R5.1 — `fires` is a pure function of the outcome.** No file reads, no clock, no ambient state, no randomness.

**R5.2 — Evaluation: registry order, first two matches win.** Order in the list *is* priority.

**R5.3 — One line per hint.** A hint that needs a paragraph is documentation and belongs in `--help` or a page, not on the wire.

**R5.4 — Adding a rule is: one `const` in the registry, one test asserting it fires, one test asserting it stays silent on a healthy outcome.** The silence test is not optional — it is how R2.3 is enforced mechanically.

**R5.5 — The two good examples already shipped set the voice.** `remember` with no `--actor` refuses *and* states the law and why nothing else may answer. `NO TREE` says the bank stands but its tree does not, names the path where it would stand, and ends "Materialize it." One line, teaches on the failure path, no footer. Every hint sounds like these.

**R5.5.1 — A message that teaches is only as good as the law it teaches, and it is the harder one to catch.** This rule cited a second example for a day: the wrong-bank refusal, "names bank X, not the addressed bank Y — recall reaches one bank per call, use walk to cross banks." It sounded exactly right, which is why nobody questioned it — and it was false. An address names its bank; honouring it violates nothing about reaching one bank per call, and refusing it broke the first line of the `/sleep` and `/flush` skills. A fluent refusal is *harder* to report as a defect than a bare parse error, because the caller assumes the law and doubts itself. So: **when a refusal states a law, the law is the thing under review, not the sentence.** The address now elects the bank (`RecallCommand._electBank`), and that message survives only where it is true — two addresses naming two banks, which one `Index` over one `Bank` genuinely cannot serve.

## 6. The first cut: six rules

In registry order.

| id | verbs | fires when | line |
|---|---|---|---|
| `unresolved-topic` | recall, refocus, tag, gist, forget | named topic absent, bank resolved | `no page at <topic> in <bank>. Nearest by name: a, b, c. \`mem survey\` for the index.` |
| `unknown-option` | every verb | an option was typed that the verb does not declare | `no option --<typed> on <verb>. Did you mean --<nearest>?`, or `--<typed> is <other verb>'s flag.` |
| `no-match` | survey, recall, walk, refocus, tag, gist | 0 pages selected, bank resolved and non-empty | `no page matches. <bank> has N pages; \`mem survey\` lists them, hottest first.` |
| `dead-link` | walk | any skip with reason `dead` | `N links point at pages that do not exist: <from> → <target>, … \`mem health\` lists every one.` |
| `no-tree` | walk, and every verb reaching a bank | reason `noTree`, or `_reportIfNoTree` | the existing NO TREE message, unchanged — it already teaches and already names the act |
| `unreachable-hot` | walk | the filter admits attention 1.0, and the bank holds hot pages the walk did not reach | `K hot pages are unreachable from this entry: a, b, c. Heat is not passage — a hot page nobody links never stages.` |
| `unlinked-write` | remember | the written page has no inbound link in the bank | `nothing links <topic>. An unlinked page is in the index, not in the brain — link it from a page that reaches it.` |

Notes a builder needs:

- **`unresolved-topic` is the rule that does not get cut.** If scope has to shrink, it survives everything else in this table. A mistyped topic is the single most common failed call an agent makes against its own memory, and today it returns a dead end that reads like a missing page — which is how a typo becomes a false bug report. One line turns it into a resolved lookup. Build this one first.
- **`unknown-option` fires before the verb runs**, in the argument-parsing failure path, and replaces the bare `Could not find an option named --x`. It is the flag-level twin of `unresolved-topic` and shares its matching. It is what makes a retirement like `--dry-run` → `--shape` (§7) safe: the caller who types the retired flag is told the live one. Retired names are matched too — keep a small `const retired = {'dry-run': 'shape'}` map, consulted before the nearest-name search, so a retirement answers exactly rather than approximately. The map is the only place a dead flag name survives; there is no alias and no hidden flag.
- **`unknown-option`'s candidate pool is the failing call's own grammar** — the runner's globals plus the verb the parser was inside — and never every option of every verb. Ranked against the union, `mem survey --limit 200 --shape` answered *no option --shape. Did you mean --shape?*: `walk`'s real flag, scored against a call `walk` was no part of. The verb comes from `ArgParserException.commands`, intercepted in a `CommandRunner.parse` override before the args package discards it — **never from scanning argv for the first word that names a command**, because `mem -b survey recall a` is a legal call in which `survey` is a bank name. And when the typed name is a live flag of exactly one other verb, the line locates it (`--shape is walk's flag`) instead of searching: that is the whole of what the caller needs, and it is a fact rather than a guess.
- **Nearest by name** is Levenshtein distance, ascending, cap 3, **edit distance 2 or less**, no fuzzy-match dependency. One implementation serves topics and option names both. The ceiling is not a tuning knob: without it the nearest name is whatever came closest in a pool holding nothing close at all, and the line teaches a falsehood in a confident voice — `mem --version` answered *did you mean --attention?*, and a topic nobody ever wrote answered with three unrelated pages. Past the ceiling the honest answer is no answer, and the caller keeps the bare fact and the index.
- **`unreachable-hot`** is the highest-value rule in the set and the one most at risk of becoming wallpaper. It is silent on a well-wired brain; if it fires on every wake, the brain is telling the truth and the rule is doing its job. Review it after a week of real use.
- **A candidate that was designed and rejected:** `narrow-band` ("only N of M pages entered"). It fires on every `--hot` walk — every wake, forever. R2.3 kills it. The number it carried lives in the frame instead.

## 7. `--dry-run` becomes `--shape`

**R7.1 — Rename, no alias.** Once the real run frames itself, "dry run" describes nothing: the ordinary walk is not wet. The surviving job is *show the set, not the bodies*, and the flag is named for it.

**R7.2 — Seam, checked: nothing in the tree passes `--dry-run`.** `spawn_command.dart` calls `mem walk <entry> --hot` and nothing else. But **hands do** — every agent of this kind who has read the old help, and every operator with the flag in muscle memory. The rename is safe only because `unknown-option` (§6) answers a retired flag with its replacement by name. Ship the two together; the rename without the rule is a regression.

**R7.3 — Limbs to remove with the flag** (deletion is proven by falsification, not by a green suite): the `addFlag('dry-run')` declaration and its help text; the `final dry = …` branch in `WalkCommand.run`; every `--dry-run` string in tests; the flag's mentions in prose and in `walk --help`. `_renderDryWalk` survives, renamed `_renderShape`, minus the weight and not-entered blocks it duplicates from the frame — except under `--shape`, where the not-entered table is artifact (R3.2).

## 8. Rendered output

What a builder must reproduce.

### 8.1 A wake — **two invocations, two accounts**

`spawn` stages a mind with **two separate `mem walk` processes**, not one: the kind's book, then the specimen's (`spawn_command.dart:114,124`). There is no invocation that sees both, and none can name the other's entry point. A frame is therefore **per-walk**, its numbers are that walk's alone, and no line sums across the pair.

This is stated because the idealized single-frame version of this render is not producible, and a builder handed an unbuildable example fixes it in a direction nobody chose.

First process — `mem walk mem://agent.bentos.mem/you --hot`. stdout: the kind's fenced pages. stderr:

```
mem: walk mem://agent.bentos.mem/you --hot — 18 pages, 5680 words, 30 links followed
mem: 22 not entered — 19 filtered (attention), 3 cross-bank
```

Second process — `mem walk mem://alfred.mem/self/alfred --hot`. stdout: the specimen's fenced pages. stderr:

```
mem: walk mem://alfred.mem/self/alfred --hot — 2 pages, 782 words, 30 links followed
mem: 9 not entered — 3 filtered (attention), 5 cross-bank, 1 dead
mem: 1 link points at a page that does not exist: self/alfred → arcs/native-runtime. `mem health` lists every one.
```

**Four frame lines per wake**, plus a hint only while the brain is actually broken — against roughly thirty unframed `skipped` lines today. The trade stands; do not redesign the pair into one account to improve it.

### 8.2 `mem walk mem://alfred.mem/self/alfred --hot --shape`

stdout:

```
ring   words  page  ← via
   0    443  self/alfred  ← entry
   1    339  domain/bentos/people/cafe  ← self/alfred
   1    618  arcs/agent  ← self/alfred
   1    432  arcs/kernel  ← self/alfred
   1    420  arcs/humanos  ← self/alfred
   2    763  discipline/orchestration/fuel  ← self/alfred

not entered
       mem://alfred.mem/company/brain  ← self/alfred  — filtered
       mem://alfred.mem/meta/memory/the-band  ← self/alfred  — filtered
       mem://agent.bentos.mem/you  ← domain/bentos/people/cafe  — crossBank
       mem://alfred.mem/arcs/native-runtime  ← self/alfred  — dead
```

stderr:

```
mem: walk mem://alfred.mem/self/alfred --hot --shape — 6 pages, 3015 words, 17 links followed
mem: 4 not entered — 2 filtered (attention), 1 cross-bank, 1 dead
mem: 1 link points at a page that does not exist: self/alfred → arcs/native-runtime. `mem health` lists every one.
```

### 8.3 `mem survey`

stdout — unchanged, the legend and cue block.

stderr:

```
mem: survey alfred.mem — 30 of 241 shown, hottest first, 4102 words
```

One line. Today: one line of the same weight, unframed and not saying what was shown of what.

### 8.4 `mem survey --tag craft --cold`, matching nothing

stdout — the bank header only.

stderr:

```
mem: survey alfred.mem — 0 of 241 shown (filter: --tag craft --cold)
mem: no page matches. alfred.mem has 241 pages; `mem survey` lists them, hottest first.
```

### 8.5 Failure: `mem recall disciplne/proof`

stdout — empty.

stderr:

```
mem: recall alfred.mem/disciplne/proof — no page.
mem: no page at disciplne/proof in alfred.mem. Nearest by name: discipline/proof, discipline/proof/untouched-claim, discipline/proof/ask-the-mechanism. `mem survey` for the index.
```

Exit 1.

### 8.6 `mem health`

stdout — unchanged, the orphans and dead-links tables.

stderr:

```
mem: health alfred.mem — 241 pages, 3 orphans, 7 dead links, 2 external unjudged; resolved against agent.bentos.mem
```

One line replaces the bare count that `--help` apologises for. The apology is deleted from help (R4.2).
