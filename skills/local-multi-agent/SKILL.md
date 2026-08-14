---
name: local-multi-agent
description: >-
  How to make several AI agents collaborate on one machine for one developer:
  pick a topology, have the agent CLIs invoke each other over the shell, and
  avoid standing up a shared relay or message bus. Use this whenever the user
  wants a second opinion from another model, wants two models to debate or
  cross-review, wants several agents working the same repo at once, asks to
  orchestrate or fan out across vendors, or asks whether they should install a
  shared event log / relay / message bus for agent collaboration. Also use
  before recommending any agent-collaboration infrastructure — on a single
  machine the answer is almost always "no infrastructure", and the real failure
  mode is concurrent edits, not message delivery.
---

# Local multi-agent collaboration

For one developer on one machine, the default is **no infrastructure**. Agent
CLIs already have shell access, so they can invoke each other directly. A shared
relay with a signed event log solves problems that only appear once you have
multiple machines, multiple humans, or agents that must outlive the process that
started them.

The two mistakes are opposite in shape: standing up a relay nobody needed, and
assuming that because you skipped the relay you have no coordination problem.
The coordination problem is real — it just lives in the filesystem, not in
message delivery.

## Calling another agent

Use the `ask` wrapper that ships alongside this skill:

```
ask grok "attack the weakest part of this argument: ..."
ask codex "review the diff on stdin" < change.diff
ask claude --resume <session-id> "follow up on your earlier point"
ask --list          # which vendors are installed
```

It normalizes the per-vendor spellings of "headless prompt", "auto-approve",
and "resume by id". Prefer it over hand-writing vendor flags: those change
between releases, and hardcoding them in prose means every copy of that prose
rots independently.

If `ask` is not on PATH, check `--help` on the vendor's own CLI rather than
trusting a remembered flag name.

## Pick the topology first

Most disagreement about "how should agents collaborate" is really disagreement
about which of these two you are in. They need different things.

**Supervisor DAG** — isolated workers, no sibling communication, one integrator.
Each agent gets a bounded task and returns a patch, an analysis, or a review;
one supervisor owns integration. This is the right default for code work.
Workers staying deaf to each other is a feature: it keeps their context small,
makes each output independently reviewable, and means a bad run contaminates
nothing. Peer messaging, broadcast, and rejoin are all unnecessary here.

**Peer conversation** — agents talk to each other directly and the orchestrator
stays out of the content. This is the right shape when the goal is judgment
rather than production: debate, cross-examination, a second opinion that has to
actually engage with the first. Here, routing every message through yourself is
the failure mode — each hop costs a paraphrase, and paraphrases diverge until
the two agents hold different pictures of the same discussion without knowing
it. Have the calling agent invoke its peer itself and quote the raw stdout.

Choosing peer conversation for production work buys context bloat and cross-
contamination for nothing. Choosing supervisor DAG for a debate gets you your
own opinion echoed back through a summarizer.

## Concurrent edits are a filesystem problem

When several agents touch the same repo, what breaks is not message delivery —
it is two agents editing from stale state and the loser's work vanishing
silently. A message log does not prevent that, and neither does a signed
identity log when every participant is the same person on one machine.

The fixes are ordinary version control:

- Give each agent its own worktree, so their edits cannot collide in place
- Have agents return **patches** rather than mutating shared files
- Record the base commit a patch was built against, and refuse to apply it if
  the base has moved
- Run the tests before merging, not after
- Keep a single writer for integration — one authority applies patches in order

This is the most load-bearing section here. Reach for it before reaching for any
messaging idea, because it addresses the failure that actually happens.

## When infrastructure becomes justified

Add durable shared machinery only when at least one of these holds. Until then
direct invocation is a *smaller* architecture, not a defective one.

- Agents must survive the parent process, or rejoin after a crash
- Multiple humans need to watch or audit the same conversation
- Work spans machines
- Participants are mutually untrusted, so authorship must be tamper-evident
- Several autonomous writers commit to the same state without an integrator

Apply this self-check honestly: **if what you are building has a durable shared
log, cursors, and rejoin semantics, it is a relay** — calling it "just some
append-only files" changes nothing except that you now maintain a relay with no
schema. Either accept that you need one, or keep the design genuinely smaller.

One threshold arrives earlier than people expect. An LLM supervisor is not
`make -j`: it forgets, re-plans, and cannot reliably distinguish "I dispatched
this" from "I considered dispatching this." Process handles are not facts. So
for work that must survive a restart or span sessions, keep a durable record of
**dispatch → result** — task id, who got it, where the output landed. That is a
job log, not a channel, and it is far smaller than a relay.

Whether it is worth having from the very first run is a genuine open question.
It clearly pays once anything is resumable — and it becomes mandatory under a
scheduler, where each run starts with no memory of the last by construction, so
the supervisor's amnesia stops being a risk and becomes a certainty.

## Getting a second opinion that is worth having

Models default to agreeableness, which is exactly what makes a second opinion
worthless. Three things fix it:

**Demand the disagreement.** Ask the peer to attack the weakest part of the
argument and say plainly that you do not want agreement. Without this you get a
polite restatement of your own position.

**Require verbatim quoting.** Have the calling agent record the peer's raw
stdout unedited. Summaries drop the parts that would have changed your mind.

**Bound the length.** A word cap per message keeps rounds fast and forces both
sides to lead with the actual claim.

Two rounds is usually where real disagreement surfaces; beyond that it circles.
Ask for an explicit "agreed on / still disagree on" ending — the residual
disagreement is the useful part, because it names the decision still left to the
human.

## When the peer cannot be reached

If the other CLI errors, is unauthenticated, or times out, report the block and
leave the transcript incomplete. Never synthesize what the peer "would have
said" — a fabricated second opinion is worse than none, because it launders your
own reasoning as independent corroboration. Retry once if the failure looks
mechanical, then stop and say what is missing.

## Things that fail silently

`--help` will not warn you about these, and each one costs a run to discover:

- **A sandboxed child usually cannot reach the network.** If one agent is going
  to call another vendor's API, the sandbox must allow it explicitly. The
  failure surfaces as an authentication or API error from the child, which
  sends you debugging the wrong layer. Prefer narrowing the sandbox to a
  workspace with network enabled over disabling confinement entirely.
- **Some CLIs refuse to start outside a Git repository.** The escape flag
  exists, but you will not know to search for it until a run dies. Scratch
  directories are where this bites.
- **A valid subscription is not a logged-in CLI.** Check before building a
  workflow on top of it. When a CLI is not signed in, hand the login command to
  the human and let them complete the browser step — do not attempt to
  authenticate on their behalf.

Cross-vendor rounds bill the other vendor's account, and a substantive
multi-round exchange can run well into six figures of tokens. Say so before
starting anything long.
