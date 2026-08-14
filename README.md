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

Clone once, then link into whichever hosts you use:

```bash
git clone https://github.com/cwy433-png/agent-skills.git ~/agent-skills

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
ask codex "review the diff on stdin" < change.diff
ask claude --resume <session-id> "follow up on your earlier point"
ask --list
```

When a vendor renames a flag, fix it in `bin/ask` and every host picks up the
change. Exit codes: `2` bad usage, `3` CLI not installed, `4` CLI not
authenticated; anything else is the child's own exit code.

`ask deepseek` expects a `deepseek` command on PATH, provided separately by
[delegate-to-deepseek](https://github.com/cwy433-png/delegate-to-deepseek).

Each vendor needs its own credentials on the machine. A valid subscription is
not the same as a logged-in CLI — check with `ask --list` and the vendor's own
login command before building anything on top.

## Adding a skill

Drop a directory under `skills/` containing a `SKILL.md`. Keep it host-neutral:
refer to `ask` rather than a specific vendor's flags, and prefer plain Git and
shell over any one host's built-in tooling, so the same text works everywhere.

The rule of thumb for what belongs in a skill: **encode what fails silently, not
what `--help` will tell you.** Flag names are cheap to look up and rot fast.
Behaviours you only discover by a run dying are expensive to rediscover and
worth writing down.

## Licence

MIT
