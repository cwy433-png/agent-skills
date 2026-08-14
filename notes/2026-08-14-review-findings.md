# Review findings — 2026-08-14

Two independent adversarial reviews of the repo at commit `e443a03`, run as a
redundancy fan-out: the same prompt to two reviewers that never saw each other,
reconciled here. Reviewers: Claude Fable, Codex (gpt-5.6-sol).

Kept as a log, not as guidance. Guidance goes in `SKILL.md`; this file records
what was actually wrong and how it was found, so the same ground is not
re-walked.

## How to read the attribution

Convergence between independent reviewers is weak evidence — they can share a
blind spot. The interesting columns are the ones where only one reviewer saw
something, and the one place they contradicted each other.

Status: `verified` = reproduced locally. `reported` = claimed, not yet
reproduced.

---

## Tier 1 — the script is actually broken

### 1.1 `--list` dies silently when any probe fails · verified
`bin/ask` runs under `set -euo pipefail`. `default_model()` pipes `grok models`
into `sed`; when grok is not signed in the pipeline returns non-zero, the
command substitution inherits it, and `set -e` aborts the whole script.

Reproduced with a stub grok that exits 1: **`ask --list` printed nothing at all
and exited 1.** Not a missing row — no output. The diagnostic command fails
exactly in the situation it exists to diagnose.

Found by Codex only. Fable missed it.

### 1.2 Extra positional arguments are silently dropped · reported
Only `$1` becomes the prompt. `ask codex first second` sends `first` and
discards the rest with no warning.

### 1.3 An option missing its value swallows the next option · reported
`ask grok --model --resume abc` parses `--resume` as the model id.

### 1.4 A prompt starting with `-` becomes child flags · reported
No `--` guard before the positional prompt, so the child parses it as options.
Both reviewers, independently.

### 1.5 Exit code 4 does not exist · verified
`bin/ask:14` and `README.md:65` document `4 = CLI not authenticated`. The script
contains only `exit 2` and `exit 3`; there is no auth probe anywhere. The
comment block at `ask:43–46` describes separating not-authenticated from
not-installed — an intent that was never implemented.

Found independently by both reviewers and by the author.

### 1.6 `--resume` is accepted then discarded for deepseek · reported
The parser stores it; the deepseek argv never includes it. Round two silently
becomes a fresh conversation — the exact failure `peer-debate.md` warns about.

---

## Tier 2 — the documents state things that are false

### 2.1 "Run the tests before merging, not after" is wrong
`SKILL.md`, worktree section. Per-worker tests before integration cannot catch
interactions between patches that only exist once merged. Should be both: before
integration to reject bad patches, and on the merged state to catch interaction.

Found by Codex only. This one is about content, not the script.

### 2.2 "Uncorrelated mistakes" contradicts the paragraph it sits in
The redundancy section sells independent workers as buying uncorrelated errors,
then immediately says agreement is weak evidence *because they can share a blind
spot*. Both cannot hold. Workers on the same base model correlate.

### 2.3 The stdin example does not work as written
`ask codex "..." < change.diff` — `ask` reads stdin only when the prompt argument
is absent, so the redirect goes to the child instead of being combined.

**Reviewers disagreed here, and the disagreement was the useful part.** Fable
claimed codex ignores piped stdin when given a positional prompt. Codex quoted
its own `--help`: *"If stdin is piped and a prompt is also provided, stdin is
appended as a `<stdin>` block"* — so Fable is wrong about codex specifically.
The real defect is Codex's framing: routing stdin through a shell variable is
lossy (trailing newlines stripped, NULs impossible, `ARG_MAX` for large diffs).

Resolving this needed a third source. Neither reviewer alone was right.

### 2.4 "auto-approve is normalized" is false for claude
grok gets `--always-approve`, codex gets a widened sandbox, claude gets nothing.
Three different capability levels presented as one normalized behaviour.

### 2.5 `--list` "cannot go stale" contradicts the three-layer thesis
`README.md` puts `ask --list` in the layer that "cannot go stale" while the
implementation parses `grok models` output format and the codex config path and
schema — both middle-layer material that rots quietly. The essay's own example
violates the essay.

### 2.6 `/usr/local/bin` install line
Not writable without sudo, and not the Apple Silicon convention. The author hit
this during install, used `~/.local/bin`, and did not update the README.

### 2.7 Cost framing is noise for subscription users
"Six figures of tokens" reads as a warning aimed at metered API billing. On a
subscription it is not a decision input, and it sits awkwardly beside the
~200-word cap that claims to keep rounds affordable. Cut it down.

---

## Tier 3 — needs a design decision, not a patch

- **Session ids cannot be obtained through `ask`.** `peer-debate.md` depends on
  resuming a thread, but plain output does not reliably print an id and `ask`
  neither captures nor returns one. The documented escape hatch cannot recover
  the id of the session just created.
- **No timeout anywhere.** `SKILL.md` discusses a peer that "times out", but
  nothing sets one, and `exec` means `ask` cannot enforce one after handoff.
- **Permission level is per-vendor and unprincipled.** A read-only review and a
  file-mutating task get the same capabilities. Whether `ask` should default to
  least privilege and require opt-in for writes is a design question.
- **Adding a vendor means editing three places.** `vendor_cmd`, `list_vendors`,
  and the dispatch `case` each hardcode the list. Supporting another CLI should
  be one table entry.

---

## Method note

The most severe finding (1.1) came from one reviewer, not both. The one place
the reviewers contradicted each other (2.3) was also the one place a third
source had to be consulted. Both outcomes argue for running more than one
reviewer, and for treating disagreement as the signal rather than averaging it.
