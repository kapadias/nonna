---
name: nonna
description: See or change what Nonna enforces in this repository — status, setup, lite, full, off, test, uninstall.
argument-hint: "[setup | lite | full | off | test <command> | uninstall]"
disable-model-invocation: true
model: haiku
allowed-tools: Bash(bash "${CLAUDE_SKILL_DIR}/scripts/nonna.sh":*)
---

!`bash "${CLAUDE_SKILL_DIR}/scripts/nonna.sh" $ARGUMENTS`

Show the output above to the user as it is, in a code block. Do not summarize it, and do not run
Nonna's scripts yourself: the line above already ran, and it made any change it reports. If a
placeholder stands where the output should be, Claude Code did not run the line, because its
disableSkillShellExecution setting is on: say so, and that nothing of hers changed.

If the output has `OFFER:` lines, ask the user yes or no for each one. On yes, make exactly that
change and nothing more; on no, leave it.
