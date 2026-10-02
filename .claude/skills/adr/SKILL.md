---
name: adr
disable-model-invocation: true
description: Write a numbered Architecture Decision Record in docs/adr/NNNN-<slug>.md capturing the context, the options considered, the decision, and its consequences.
argument-hint: "[the decision to record]"
model: opus
allowed-tools: Read, Glob, Edit(docs/adr/**)
---

!ls docs/adr 2>/dev/null || echo "(no docs/adr directory yet — NNNN starts at 0001)"

Record the decision: **$ARGUMENTS**

## Steps

1. **Find the next number.** The `ls docs/adr` output above shows existing ADRs; use the next zero-padded `NNNN`. Slugify the title.
2. **Write `docs/adr/NNNN-<slug>.md`** using the template below. Be concrete: the value of an ADR is the
   _alternatives you rejected and why_, not the choice alone.
3. **Link it** from the ADR index (`docs/adr/README.md`) and from the tracked issue.

## Template

Write the ADR from [`templates/adr.md`](templates/adr.md) — read it when you need it.

## Output

The path to the new ADR and a one-line summary of the decision. If this changed scope or the harness,
run `/sync`.
