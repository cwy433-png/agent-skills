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
ask codex --model <id> "review this design"   # see: ask --list
ask codex "review the diff" < change.diff        # a file is folded in
printf "%s" "$d" | ask codex "review the diff" -   # a pipe needs a final -
ask claude --resume <session-id> "follow up on your earlier point"
ask --list          # which vendors are installed, and their default model
```

It normalizes the per-vendor spellings of "headless prompt", "auto-approve",
"resume by id", and "pin the model". Prefer it over hand-writing vendor flags:
those change between releases, and hardcoding them in prose means every copy of
that prose rots independently.

**Name the model whenever the answer matters.** Left unpinned, each CLI uses
whatever its own config happens to say. The whole reason to ask a second vendor
is to reach a different model, so an unpinned comparison cannot tell you what
you compared, and it changes meaning silently the next time someone edits a
config. `ask --list` shows the current defaults; a bad model id fails loudly
instead of falling back.

If `ask` is not on PATH, check `--help` on the vendor's own CLI rather than
trusting a remembered flag name.

Some CLIs also expose themselves as an MCP server, which a host that speaks MCP
can connect to instead of shelling out. That buys structured multi-turn session
handling at the cost of a per-host connector; `ask` stays the portable option,
because every host can run a command.

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

## Running a supervisor DAG

Many hosts only offer this shape — fan work out to independent agents, collect
what comes back, summarize. That is not a limitation to work around; it is the
topology you want most of the time. Peer messaging is needed for one narrow
purpose (below), and everything else is served by fan-out and integration.

Two fan-out patterns do different jobs, and it is worth knowing which one you
are running:

**Division of labour** — a different bounded task per worker, integrated at the
end. You are buying throughput and context isolation.

**Redundancy** — the *same* task to several workers, then compared. You are
buying uncorrelated mistakes. Note which direction the evidence runs: agreement
between independent workers is weak evidence of correctness (they can share a
blind spot), while **disagreement is strong evidence that something needs a
human**. Treat a split verdict as the finding, not as noise to average away.

### Independent disagreement vs engaged disagreement

Redundancy gives you *independent* disagreement: N opinions that never saw each
other. It is cheap, fully parallel, and its errors do not correlate — but no
worker ever addresses another's actual argument, so you learn **that** they
differ, not **why**.

Peer conversation gives you *engaged* disagreement: each side attacks the other's
weakest point until the real crux surfaces. That is more informative and costs
round trips, sequencing, and a host that can pass messages between agents.

So escalate rather than choosing upfront: run redundancy first, and if the
outputs disagree in a way the artifacts alone cannot settle, take that one
disagreement to an engaged round. Most disagreements resolve at the first step,
which is why a host that cannot do peer messaging is rarely blocked in practice.

### What the supervisor owes the work

- **Write self-contained worker prompts.** An isolated worker shares none of
  your context, so "as we discussed" and "the file we looked at" resolve to
  nothing. State the task, the inputs, and the expected output shape.
- **Keep raw outputs addressable.** The summary is a view over the artifacts,
  not a replacement for them. Once the originals are gone, nobody can check
  whether the summary dropped the part that mattered.
- **Reconcile, do not average.** When two workers conflict, pick one with a
  stated reason or escalate it. Blending two incompatible answers produces a
  third answer that neither worker would defend and no evidence supports.
- **Record dispatch and result.** Which task went where, and where the output
  landed. Not bookkeeping for its own sake: an LLM supervisor cannot reliably
  tell "I dispatched this" from "I considered dispatching this", so the record
  is the only thing that knows whether a worker is still owed.

## Accepting what comes back

Judge a worker by the state of the tree, not by what it says about the tree.
These tools are trained to sound finished, so a confident closing summary is
evidence of fluency and nothing else. Its report is a claim; the diff, the test
run, and the acceptance condition are the evidence.

So before integrating anything, look:

- `git status` and `git diff` — were the files it named actually changed, and
  only those?
- Run the tests and the build yourself. A worker reporting "tests pass" has
  told you what it believes.
- Check the acceptance condition you wrote into the assignment. If you did not
  write one, that gap is upstream in the brief, not in the worker.

When the evidence contradicts the claim, the useful move is to re-brief with the
failure attached — the actual command and its actual output — rather than to ask
again more firmly. A worker that cannot see the failure cannot fix it.

This is the single highest-yield habit in the whole document. Everything else
here reduces the chance of a bad outcome; this is what catches one.

## Bounding the wait

Give every dispatch a deadline. A child CLI can hang on a network call, sit
waiting for an interactive confirmation that no one will type, or loop. None of
those announce themselves — from the outside a hung child and a thinking child
look identical, and a run left unbounded stalls until someone notices.

Three habits cover it:

- Set an explicit timeout on every call, sized to the task rather than to
  patience — `ask --timeout <seconds>` if you are using the wrapper. A tight
  bound that occasionally fires is more useful than a generous one that never
  does, because the fired bound tells you something.
- Use each CLI's non-interactive mode, so a prompt for confirmation becomes an
  error instead of a silent wait.
- Bound the retries. One retry is worth it when the failure looks mechanical;
  after that, stop and report the task incomplete.

When the bound is reached, remember there is always a fallback executor: you.
Doing the task directly is a legitimate outcome, and often faster than a third
attempt at delegating it.

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

For the mechanics — the prompt that actually drives a two-round exchange, and
the session-continuity step that is easiest to miss — read
`references/peer-debate.md` when you are about to run one.

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
- **A vendor can change what a flag means while keeping its spelling.** The call
  still exits zero and still returns plausible output; only the behaviour moved
  — a pinned model quietly ignored, a resume that starts a fresh session. Since
  nothing breaks, nothing prompts you to look. A version string is the cheap
  cue: `ask --check` reports drift, and a change is the signal to re-verify the
  affected calls against the real CLI before trusting them again.

Cross-vendor rounds bill the other vendor's account, and a substantive
multi-round exchange can run well into six figures of tokens. Say so before
starting anything long.
