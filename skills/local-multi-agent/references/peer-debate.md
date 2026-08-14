# Running a peer exchange between two CLIs

Read this when you have decided on peer conversation — two agents engaging each
other's arguments directly — rather than fan-out. For choosing between the two,
and for the fan-out playbook, see `SKILL.md`.

The mechanism is simple once stated: you do not relay messages. You hand agent A
a task that includes *the command for reaching agent B*, and A calls B itself.
A's own context carries its side of the conversation; B's session carries B's.

```
you → A ──ask <vendor> ...──→ B
          ←── raw stdout ────┘
```

## The driving prompt

What follows is a template that has worked in practice. The parts that look
fussy are load-bearing — each one is there because leaving it out produced a
worse exchange.

```
You have the `ask` command available. Hold a real two-round exchange with
<peer>, agent to agent, with no human relaying messages.

TOPIC
  <the question, stated concretely enough to disagree about>

HOW TO REACH <peer>
  ask <peer> "<your message>"

  Its reply prints to stdout. For round 2, continue the SAME thread:

  ask <peer> --resume <session-id> "<your message>"

  If no session id was printed, check the peer CLI's own --help for how it
  continues a conversation. Starting a fresh session in round 2 means the peer
  has forgotten round 1 and will answer as if seeing the topic for the
  first time.

WHAT TO DO
  1. Form your own position first, and write it down.
  2. Send your position and ask for the strongest DISAGREEMENT. Say explicitly
     that you want the weakest part of your argument attacked, and that you do
     not want agreement.
  3. Read the raw reply. In round 2, respond to the objection actually made —
     concede what is right, push back on what is not.
  4. Get the round-2 reply.

Keep each message under ~200 words.

OUTPUT
  Append to ./discussion.md as you go, with the peer's replies QUOTED VERBATIM —
  do not paraphrase or summarize them:

    ## Round 1 — <caller>
    ## Round 1 — <peer> (verbatim)
    ## Round 2 — <caller>
    ## Round 2 — <peer> (verbatim)
    ## Where we ended up
    - Agreed on: ...
    - Still disagree on: ...

If <peer> cannot be reached, say so and leave the transcript incomplete. Do not
write what it "would have said".
```

## Why each constraint is there

**"Attack the weakest part, do not be agreeable."** Without this you get a
courteous restatement of the position you sent, and the exchange tells you
nothing you did not already believe.

**Verbatim quoting.** A caller left to summarize will drop precisely the
objection it found least convincing — which is often the one worth reading. It
also makes the transcript checkable afterwards.

**Word cap.** Uncapped, both sides write essays that restate context instead of
leading with the claim. It also keeps two rounds affordable.

**Resume the same thread in round 2.** This is the step most easily missed. A
fresh session means the peer never saw its own round-1 argument, so round 2
becomes two disconnected first drafts rather than an exchange.

**Explicit "agreed / still disagree" ending.** The residual disagreement is the
part worth your attention: it names the decision that is still yours. Without
asking for it, both sides tend to close on a polite synthesis that hides where
they actually part.

## Reading the result

Two rounds is usually where the real crux appears; beyond that the exchange
circles. Judge it by whether either side *moved* — a concession, a narrowed
claim, an abandoned overreach. An exchange where both sides restate their
opening position twice means the topic was posed too vaguely to disagree about,
not that they genuinely disagree.

Then read the residual disagreement as your own to-do, not as a failure of the
exchange.

## Cost

Every round bills the peer's account. A substantive two-round exchange can run
well into six figures of tokens on that side. Say so before starting, and pin
the model with `--model` if the comparison is one you will act on — otherwise
you cannot report what you actually compared.
