# agent-skills

Portable skills for agent CLIs, kept in one place and symlinked into every host
so there is exactly one copy to edit.

Claude Code, Codex, Grok, and WorkBuddy all read skills from a per-host
directory using the same `SKILL.md` shape — YAML frontmatter with `name` and
`description`, then Markdown. That means a skill written once can serve all of
them. What usually goes wrong is not the format but the copies: install the same
skill four times and you now maintain four versions that drift apart. Symlinks
fix that.

## Contents

| Path | What it is |
|---|---|
| `skills/local-multi-agent/` | How to make several agents collaborate on one machine without standing up a relay |
| `bin/ask` | Vendor-neutral wrapper: `ask <vendor> "<prompt>"` |

## Install

Clone this repo once, then link into whichever hosts you use:

```bash
git clone <this-repo> ~/agent-skills

for host in ~/.claude ~/.codex ~/.grok ~/.workbuddy; do
  [ -d "$host" ] || continue
  mkdir -p "$host/skills"
  ln -sfn ~/agent-skills/skills/local-multi-agent "$host/skills/local-multi-agent"
done
```

Put `ask` on your PATH so skills can call it without knowing where it lives:

```bash
ln -sfn ~/agent-skills/bin/ask /usr/local/bin/ask
```

Verify:

```bash
ask --list
```

Some hosts only rescan their skills directory on restart. If a newly linked
skill does not show up, restart that app.

## The `ask` wrapper

Every vendor spells the same three ideas differently — headless prompt,
auto-approve, resume-by-id. Encoding those spellings in each agent's
instructions means N copies that rot independently, so `ask` holds them instead:

```bash
ask grok "attack the weakest part of this argument: ..."
ask codex --model <id> "review this design"   # see: ask --list
ask codex "review the diff on stdin" < change.diff
ask claude --resume <session-id> "follow up on your earlier point"
ask --list
```

When a vendor renames a flag, fix it in `bin/ask` and every host picks up the
change. Exit codes: `2` bad usage, `3` CLI not installed, `4` CLI not
authenticated; anything else is the child's own exit code.

### Pin the model when the answer matters

Omit `--model` and each CLI quietly uses whatever its own config says. That is
fine for throwaway questions and wrong for anything you will act on: the reason
to ask a second vendor is to get a *different model*, so an unpinned comparison
does not tell you what you actually compared — and it silently changes meaning
the next time one of those configs is edited.

`ask --list` prints each vendor's current default, so you can see what you would
get before deciding whether to pin. Naming a model that does not exist fails
loudly rather than falling back to the default, which is what you want.

`ask deepseek` expects a `deepseek` command on PATH. DeepSeek ships no first-
party CLI, so this slot is filled by whatever wrapper you use — typically a
second CLI pointed at DeepSeek's Anthropic-compatible endpoint. Drop one on
PATH under that name and it works like the rest; leave it out and `ask --list`
simply reports it missing.

Each vendor needs its own credentials on the machine. A valid subscription is
not the same as a logged-in CLI — check with `ask --list` and the vendor's own
login command before building anything on top.

## Adding a skill

Drop a directory under `skills/` containing a `SKILL.md`. Keep it host-neutral:
refer to `ask` rather than a specific vendor's flags, and prefer plain Git and
shell over any one host's built-in tooling, so the same text works everywhere.

### What belongs in prose

**Anything reachable by one command should not be written down; what gets
written down should be the judgement you cannot query.**

A document that repeats a queryable fact has two failure modes and no upside: it
goes stale silently, and while stale it is *more* convincing than no
documentation at all, because it reads like knowledge. `ask --list` cannot go
stale — it stores the method, not the answer.

This sorts naturally into three layers that decay at very different rates, and
the whole trick is not to let a fast layer leak into a slow one:

| Layer | Example | Goes stale in | Lives in |
|---|---|---|---|
| Judgement | which topology fits, when infrastructure is justified, how to force real disagreement | years | `SKILL.md` |
| Flag spelling | `--always-approve`, the escape hatch for Git-repo checks, opening the sandbox to the network | months | `bin/ask`, one file |
| Model ids, versions, paths | whatever `ask --list` prints today | weeks | nowhere — queried |

The middle layer still rots, but it rots *loudly*: a wrong flag makes a run fail
immediately, while a wrong sentence in a document quietly misleads for months.
That is the argument for putting volatile mechanics in code and keeping prose
for the parts that stay true.

The corollary for the top layer: **encode what fails silently.** A behaviour you
only discover by watching a run die — a sandboxed child with no network, a CLI
that refuses to start outside a repository — costs a run to rediscover every
time it is forgotten. That is exactly what is worth a paragraph.

## Licence

MIT
