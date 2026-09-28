#!/usr/bin/env python3
"""Nonna harness linter — the harness validated against its own rules.

Every check below fails the build (boundaries.md: deterministic gates decide):
  - agents: valid frontmatter (name/description/model/tools); model in the
    allowed set; read-only agents grant no mutating tools.
  - skills (commands are skills too): description present; model/effort valid;
    side-effecting workflows set disable-model-invocation.
  - settings.json: every wired hook script exists on disk.
  - cross-links: every intra-repo markdown link resolves to a real file.
  - slash refs: every `/name` named in the harness resolves to a command or skill.
  - domain leak: no domain-specific vocabulary in a domain-agnostic harness.
  - external names: a project whose ideas Nonna adapted is credited in README.md
    and named nowhere else.
  - the ladder: the seven rung keywords appear in both 00-core.md (always-on)
    and skills/lean/SKILL.md (depth), so the two copies cannot drift (ADR-0008).
  - debt gate wiring: /review and /sync invoke check-debt.sh (ADR-0008).
  - review inflation: dev-process §4 and the severity rubric keep the rule that a
    review ask which adds code must name a failing input (ADR-0008).

NONNA_LINT_ROOT points the linter at a different tree. It exists so tests/run.sh
can golden-test the linter itself against mutated copies of this repo — a linter
with no failing-case test is an unverified gate. CI never sets it.
"""

from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import sys

ROOT = os.environ.get("NONNA_LINT_ROOT") or os.path.dirname(
    os.path.dirname(os.path.abspath(__file__))
)
offenders: list[str] = []


def bad(msg: str) -> None:
    offenders.append(msg)


ALLOWED_MODELS = {"opus", "sonnet", "haiku", "fable", "inherit"}
ALLOWED_EFFORT = {"low", "medium", "high", "xhigh", "max"}
READ_ONLY_AGENTS = {
    "orchestrator",
    "planner",
    "explorer",
    "code-reviewer",
    "security-reviewer",
}
MUTATING_TOOLS = {"Write", "Edit", "MultiEdit"}


def frontmatter(path: str) -> list[str] | None:
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return lines[1:i]
    return None


def fm_value(block: list[str], key: str) -> str | None:
    for line in block:
        s = line.lstrip()
        if s.startswith(f"{key}:"):
            return s[len(key) + 1 :].strip()
    return None


# --- agents ---
for path in sorted(glob.glob(f"{ROOT}/.claude/agents/*.md")):
    name = os.path.basename(path)[:-3]
    block = frontmatter(path)
    if block is None:
        bad(f"{path}: missing/unterminated frontmatter")
        continue
    for key in ("name", "description", "model", "tools"):
        if fm_value(block, key) is None:
            bad(f"{path}: frontmatter missing '{key}:'")
    model = fm_value(block, "model")
    if model and model not in ALLOWED_MODELS:
        bad(f"{path}: model '{model}' not in {sorted(ALLOWED_MODELS)}")
    tools = fm_value(block, "tools") or ""
    granted = {t.strip() for t in tools.split(",") if t.strip()}
    leaked = granted & MUTATING_TOOLS
    if name in READ_ONLY_AGENTS and leaked:
        bad(f"{path}: read-only agent grants mutating tools {sorted(leaked)}")
    # `skills:` preloads FULL skill content at startup, turning a probabilistic
    # description-trigger into a deterministic one. That guarantee is why depth
    # may live in the skill instead of an always-on rule — so a name that does
    # not resolve silently removes the depth it was trusted to carry.
    for skill in (s.strip() for s in (fm_value(block, "skills") or "").split(",")):
        if skill and not os.path.isfile(f"{ROOT}/.claude/skills/{skill}/SKILL.md"):
            bad(f"{path}: preloads skill '{skill}' which has no SKILL.md")
    effort = fm_value(block, "effort")
    if effort and effort not in ALLOWED_EFFORT:
        bad(f"{path}: effort '{effort}' not in {sorted(ALLOWED_EFFORT)}")

# --- skills (commands are skills too: Claude Code merged the two) ---
# A side-effecting workflow must be user-invocable ONLY. safety.md requires a
# human to approve first promotion to production; disable-model-invocation is
# what makes that a mechanism instead of a request, and it also drops the
# description from every turn's context.
USER_ONLY_SKILLS = {"ship", "release", "rollback", "adr", "sync", "intake", "nonna"}
for path in sorted(glob.glob(f"{ROOT}/.claude/skills/*/SKILL.md")):
    name = os.path.basename(os.path.dirname(path))
    block = frontmatter(path)
    if block is None:
        bad(f"{path}: missing/unterminated frontmatter")
        continue
    if fm_value(block, "description") is None:
        bad(f"{path}: frontmatter missing 'description:'")
    model = fm_value(block, "model")
    if model and model not in ALLOWED_MODELS:
        bad(f"{path}: model '{model}' not in {sorted(ALLOWED_MODELS)}")
    effort = fm_value(block, "effort")
    if effort and effort not in ALLOWED_EFFORT:
        bad(f"{path}: effort '{effort}' not in {sorted(ALLOWED_EFFORT)}")
    if (
        name in USER_ONLY_SKILLS
        and fm_value(block, "disable-model-invocation") != "true"
    ):
        bad(
            f"{path}: '{name}' has side effects and must set "
            f"disable-model-invocation: true — a human approves outward-facing "
            f"actions (rules/safety.md), and the model must not self-invoke it"
        )

# --- review gate wiring: the machine-checkable verdict must be reachable ---
# ADR-0005's parser is only a gate if the live pipeline invokes it. /review and
# /ship must reference check-review.sh; a harness where the script exists but
# nothing calls it re-creates the unwired-gate defect this pins against.
for cmd in ("review", "ship"):
    cmd_path = f"{ROOT}/.claude/skills/{cmd}/SKILL.md"
    try:
        with open(cmd_path, encoding="utf-8") as fh:
            if "check-review.sh" not in fh.read():
                bad(f"{cmd_path}: does not wire check-review.sh (ADR-0005)")
    except FileNotFoundError:
        bad(f"review gate wiring: missing {os.path.relpath(cmd_path, ROOT)}")

# --- test-count drift: no doc may hardcode a stale gate-test count ---
# The suite size is derived from run.sh (its `check`/`contains` helper calls);
# any "N-gate" / "N golden" number in the living docs must equal it. Historical
# entries under STATUS.md's "Recently changed" are records, not claims — skipped.
with open(f"{ROOT}/tests/run.sh", encoding="utf-8") as fh:
    ACTUAL_GATES = len(
        re.findall(r'\b(?:check|contains|sv_blocks|sv_allows) "', fh.read())
    )
COUNT = re.compile(r"\b(\d+)[- ](?:gate|golden)\b", re.IGNORECASE)
for rel in (
    "CLAUDE.md",
    "README.md",
    "tests/README.md",
    ".claude/README.md",
    "docs/STATUS.md",
):
    path = os.path.join(ROOT, rel)
    if not os.path.isfile(path):
        continue
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if rel == "docs/STATUS.md":
        text = text.split("## Recently changed")[0]
    for n, line in enumerate(text.splitlines(), 1):
        for m in COUNT.finditer(line):
            if int(m.group(1)) != ACTUAL_GATES:
                bad(
                    f"{rel}:{n}: stale gate-test count {m.group(1)} (run.sh has {ACTUAL_GATES})"
                )

# --- verdict format: no harness surface may teach the unparseable text verdict ---
# The pre-ADR-0005 security skill printed "SECURITY VERDICT: ..." — a format
# check-review.sh cannot parse. Every reviewer surface must use the JSON contract.
for md in glob.glob(f"{ROOT}/.claude/**/*.md", recursive=True):
    with open(md, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            if "SECURITY VERDICT:" in line:
                bad(f"{md}:{n}: text verdict format — use the ADR-0005 JSON contract")

# --- A/C/V/R reporting convention: pinned in the PR template and dev-process ---
# Every completed unit reports Assumptions / Changed / Verified / Remaining risk
# (dev-process.md §6). The PR template is the artifact form of the convention.
pr_template = f"{ROOT}/.github/PULL_REQUEST_TEMPLATE.md"
if not os.path.isfile(pr_template):
    bad("missing .github/PULL_REQUEST_TEMPLATE.md (A/C/V/R reporting convention)")
else:
    with open(pr_template, encoding="utf-8") as fh:
        tpl = fh.read()
    for heading in ("Assumptions", "Changed", "Verified", "Remaining risk"):
        if heading not in tpl:
            bad(f"PULL_REQUEST_TEMPLATE.md: missing '{heading}' section (A/C/V/R)")
with open(f"{ROOT}/.claude/rules/dev-process.md", encoding="utf-8") as fh:
    if "Assumptions" not in fh.read():
        bad(".claude/rules/dev-process.md: A/C/V/R reporting convention missing")

# --- hook commands: one exact form each, and the wired script exists ---
# A hook command is its quoted root, the script, and nothing else. The root is quoted because Claude
# Code puts the path into a shell command, and an unquoted path with a space ("Application Support")
# splits: the script is never found and the gate silently never runs. Nothing may follow the script,
# because a tail changes what the gate does: `|| true` turns a block (exit 2) into a pass. SessionStart
# alone may pass the plugin data dir, and only in hooks.json. `claude plugin validate` checks the
# quoting in hooks.json only; settings.json has no validator, so the lint holds both.
HOOK_FORMS = {
    ".claude/hooks/hooks.json": (
        re.compile(
            r'^"\$\{CLAUDE_PLUGIN_ROOT\}"/(hooks/[A-Za-z0-9_.-]+\.sh)(?P<data> "\$\{CLAUDE_PLUGIN_DATA\}")?$'
        ),
        '"${CLAUDE_PLUGIN_ROOT}"/hooks/<script>.sh',
    ),
    ".claude/settings.json": (
        re.compile(r'^"\$CLAUDE_PROJECT_DIR"/\.claude/(hooks/[A-Za-z0-9_.-]+\.sh)$'),
        '"$CLAUDE_PROJECT_DIR"/.claude/hooks/<script>.sh',
    ),
}


def hook_script(rel: str, event: str, cmd: str):
    """The script a hook command runs (relative to .claude/), or None if the command is not in its one form."""
    m = HOOK_FORMS[rel][0].fullmatch(cmd)
    if not m or (m.groupdict().get("data") and event != "SessionStart"):
        return None
    return m.group(1)


# The other keys decide whether a hook can block at all, so they are pinned too: an async hook
# cannot block, a timeout counts as a non-blocking error (a tiny one fails the gate open), and any
# type but "command" hands the decision to a model. statusMessage only sets the spinner text.
HOOK_KEYS = {"type", "command", "timeout", "statusMessage"}
MIN_HOOK_TIMEOUT = 10  # seconds


def check_hook_forms(rel: str, cfg: dict) -> None:
    for event, entries in (cfg.get("hooks") or {}).items():
        for entry in entries:
            for hook in entry.get("hooks", []):
                cmd = hook.get("command", "")
                script = hook_script(rel, event, cmd)
                if script is None:
                    bad(
                        f"{rel}: {event} hook '{cmd}' must be exactly {HOOK_FORMS[rel][1]} "
                        f"(quoted root, then the script, then nothing: a tail like '|| true' turns a block into a pass)"
                    )
                elif not os.path.isfile(os.path.join(ROOT, ".claude", script)):
                    shown = (
                        script if rel.endswith("hooks.json") else f".claude/{script}"
                    )
                    bad(f"{os.path.basename(rel)}: wired hook missing on disk: {shown}")
                if hook.get("type") != "command":
                    bad(
                        f"{rel}: {event} hook '{cmd}' must be type \"command\" (a gate is a script, not a model's judgment)"
                    )
                extra = sorted(set(hook) - HOOK_KEYS)
                if extra:
                    bad(
                        f"{rel}: {event} hook '{cmd}' has keys {extra} (allowed: {sorted(HOOK_KEYS)}; an async hook cannot block)"
                    )
                t = hook.get("timeout")
                if "timeout" in hook and (
                    isinstance(t, bool)
                    or not isinstance(t, (int, float))
                    or t < MIN_HOOK_TIMEOUT
                ):
                    bad(
                        f"{rel}: {event} hook '{cmd}' timeout {t!r} is under {MIN_HOOK_TIMEOUT}s (a timeout lets the action through)"
                    )


with open(f"{ROOT}/.claude/settings.json", encoding="utf-8") as fh:
    settings = json.load(fh)
check_hook_forms(".claude/settings.json", settings)
# One settings key turns every hook off at once; pinning each gate means nothing if it is set.
if settings.get("disableAllHooks"):
    bad(
        ".claude/settings.json: disableAllHooks is set, which turns every Nonna gate off"
    )

# --- cross-links: intra-repo markdown links must resolve ---
LINK = re.compile(r"\]\(([^)]+)\)")
FILE_EXT = re.compile(r"\.(md|sh|json|py|ts|go|ya?ml|txt)$")


def check_links(md: str) -> None:
    base = os.path.dirname(md)
    in_fence = False
    with open(md, encoding="utf-8") as fh:
        for line in fh:
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for target in LINK.findall(line):
                t = target.strip().split()[0]
                if not t or t.startswith(("http://", "https://", "mailto:", "#")):
                    continue
                t = t.split("#")[0]
                if not t or not FILE_EXT.search(t):
                    continue
                if not os.path.exists(os.path.normpath(os.path.join(base, t))):
                    bad(f"{md}: dead link -> {target}")


md_files: list[str] = []
for patt in (
    "CLAUDE.md",
    "README.md",
    "CONTRIBUTING.md",
    ".claude/**/*.md",
    "docs/**/*.md",
    "stacks/**/*.md",
    "tests/**/*.md",
):
    md_files += glob.glob(f"{ROOT}/{patt}", recursive=True)
for md in sorted(set(md_files)):
    check_links(md)

# --- backticked docs/ references must exist (the link lint only sees []()) ---
# ADR-0006 cited `docs/INSTALL.md` in backticks for months while the file did
# not exist; prose references to docs/ are promises and must resolve.
TICK = re.compile(r"`(docs/[A-Za-z0-9._/-]+\.md)`")
for md in sorted(set(md_files)):
    with open(md, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            for t in TICK.findall(line):
                if not os.path.isfile(os.path.join(ROOT, t)):
                    bad(f"{md}:{n}: backtick-referenced {t} does not exist")

# --- allowed-tools completeness: a command must be able to run its own steps ---
# `allowed-tools` is a PRE-APPROVAL grant, not a restriction: a missing entry
# falls through to the permission system, so the command halts for approval
# interactively and is denied outright in dontAsk / non-interactive runs — it
# degrades exactly where unattended operation matters. /release shipped with
# `git tag` but no `git push` while its own step 4 said "Push the tag".
# Only the mechanically provable case is checked: a backticked `git <verb>` in
# the body of a command that declares allowed-tools but does not grant that verb.
FRONT = re.compile(r"^---\n(.*?)\n---\n", re.S)
GIT_IN_SPAN = re.compile(r"`[^`]*\bgit\s+([a-z-]+)")
NEGATED = re.compile(r"\b(do not|don't|never|instead of)\b", re.I)
for path in sorted(glob.glob(f"{ROOT}/.claude/skills/*/SKILL.md")):
    raw = open(path, encoding="utf-8").read()
    m = FRONT.match(raw)
    if not m:
        continue
    at = re.search(r"^allowed-tools:\s*(.+)$", m.group(1), re.M)
    if not at:
        continue  # unrestricted by design — nothing can be under-granted
    granted = set(re.findall(r"Bash\(git\s+([a-z-]+)", at.group(1)))
    used: set[str] = set()
    for line in raw[m.end() :].splitlines():
        if not NEGATED.search(line):
            used |= set(GIT_IN_SPAN.findall(line))
    for verb in sorted(used - granted):
        bad(
            f"{os.path.relpath(path, ROOT)}: body runs `git {verb}` but "
            f"allowed-tools does not grant Bash(git {verb}:*)"
        )

# --- a skill's ! line runs only as its allowed-tools pre-approve it ---
# Claude Code runs a skill's !`command` line before the model sees the skill,
# through the permission check alone: no PreToolUse hook sees it. A line the
# rules do not pre-approve is not run as written (auto mode hands it to the
# model, where the branch guard refuses her own scripts), and a rule wider than
# the line pre-approves more than the line. So each ! line needs a rule that is
# exactly it: Bash(<line>), or Bash(<line without its $ARGUMENTS>:*). Claude Code
# runs two forms, an inline !`…` and a fenced ```! block; both are held to it.
BANG = re.compile(r"(?:^|\s)!`([^`]+)`|```!\s*\n?([\s\S]*?)\n?```", re.M)
for path in sorted(glob.glob(f"{ROOT}/.claude/skills/*/SKILL.md")):
    raw = open(path, encoding="utf-8").read()
    m = FRONT.match(raw)
    if not m:
        continue
    at = re.search(r"^allowed-tools:\s*(.+)$", m.group(1), re.M)
    rules = (
        set(re.findall(r"Bash\(([^()]*(?:\([^()]*\)[^()]*)*)\)", at.group(1)))
        if at
        else set()
    )
    for inline, fenced in BANG.findall(raw[m.end() :]):
        line = (inline or fenced).strip()
        prefix = re.sub(r"\s+\$ARGUMENTS$", "", line)
        if line not in rules and f"{prefix}:*" not in rules:
            bad(
                f"{os.path.relpath(path, ROOT)}: the ! line `{line}` is not pre-approved exactly "
                f"by allowed-tools; grant Bash({prefix}:*) and nothing wider"
            )

# --- slash references: every `/name` the harness advertises must be invocable ---
# Descriptions and rules route the agent by naming commands. A `/name` that no
# longer exists is a routing dead end the agent cannot detect at runtime, so it
# silently does nothing. Skills are invocable as `/name` too, so both count.
SLASH = re.compile(r"`(/[a-z][a-z0-9-]*)`")
invocable = {
    os.path.basename(os.path.dirname(p))
    for p in glob.glob(f"{ROOT}/.claude/skills/*/SKILL.md")
}
for md in sorted(glob.glob(f"{ROOT}/.claude/**/*.md", recursive=True)):
    with open(md, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            for ref in SLASH.findall(line):
                if ref[1:] not in invocable:
                    bad(
                        f"{os.path.relpath(md, ROOT)}:{n}: `{ref}` is not a command or skill"
                    )

# --- domain leak: a domain-agnostic harness names no single domain ---
DENY = re.compile(r"\b(trading|brokerage)\b", re.IGNORECASE)
for md in glob.glob(f"{ROOT}/.claude/**/*.md", recursive=True):
    with open(md, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            if DENY.search(line):
                bad(f"{md}:{n}: domain-specific term in a domain-agnostic harness")

# --- review inflation: the review loop must not un-size what the ladder sized ---
# The first WS7 eval's outlier: a six-line check became 25 lines because every MEDIUM
# was built. dev-process §4 and the rubric carry the rule; pin the load-bearing phrases.
for rel, phrase in (
    (".claude/rules/dev-process.md", "names a failing case"),
    (
        ".claude/skills/code-review/references/severity-rubric.md",
        "Does the fix add code?",
    ),
):
    path = os.path.join(ROOT, rel)
    try:
        with open(path, encoding="utf-8") as fh:
            if phrase not in fh.read():
                bad(
                    f"{rel}: missing '{phrase}' — a review ask that adds code must name a failing input (ADR-0008)"
                )
    except FileNotFoundError:
        bad(f"review-inflation rule: missing {rel}")

# --- external names: credit lives in README.md and nowhere else ---
# Nonna adapts ideas from other projects; the credit line in the root README is the
# one place their names appear. Everything the harness ships stays brand-free. The
# term is assembled at runtime so this file cannot trip its own check.
EXTERNAL_NAMES = ("pony" + "tail",)
# The credit line, and the one helper that must name the plugin to detect it (lib/ladder.sh).
EXTERNAL_ALLOWED = {"README.md", ".claude/hooks/lib/ladder.sh"}
EXTERNAL = re.compile("|".join(re.escape(t) for t in EXTERNAL_NAMES), re.IGNORECASE)
SCAN_EXT = re.compile(r"\.(md|sh|py|json|ya?ml|txt)$")
# os.walk, not glob: glob("**") skips dot-directories, and .claude/ is one.
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules")]
    for name in filenames:
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, ROOT)
        if rel in EXTERNAL_ALLOWED or not SCAN_EXT.search(name):
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            for n, line in enumerate(fh, 1):
                if EXTERNAL.search(line):
                    bad(
                        f"{rel}:{n}: external project name — credit belongs in README.md only"
                    )

# --- the ladder: one ruleset, two copies (always-on rungs; on-demand depth) ---
# The seven rungs are pinned by keyword because the copies differ in depth by design.
LADDER = (
    "YAGNI",
    "codebase",
    "stdlib",
    "native",
    "installed",
    "one line",
    "minimum code",
)
for rel in (".claude/rules/00-core.md", ".claude/skills/lean/SKILL.md"):
    path = os.path.join(ROOT, rel)
    if not os.path.isfile(path):
        bad(f"ladder: missing {rel} (ADR-0008)")
        continue
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    for rung in LADDER:
        if rung not in text:
            bad(
                f"{rel}: ladder rung '{rung}' missing — 00-core.md and the lean skill must agree (ADR-0008)"
            )

# --- lite.md: the house rules every lite session and subagent carries ---
# It rides additionalContext on every lite SessionStart and SubagentStart, so it has a budget, and
# it must keep a line for each never-list item lite mode inherits: without one, lite would stop
# saying what its own gates enforce.
MAX_LITE_WORDS = 150
LITE_COVERS = (  # (never-list wording in 00-core.md, phrase lite.md must keep)
    ("Commit or push to", "Never commit or push to main"),
    ("force-push", "never force-push"),
    ("Put a secret", "Never put a secret"),
    ("with failing tests", "whole test suite passes"),
    ("no test that would have failed before it", "fails before the fix"),
    ("Override a gate", "do not work around it"),
)
lite_path = os.path.join(ROOT, ".claude/hooks/lib/lite.md")
if not os.path.isfile(lite_path):
    bad("lite mode: missing .claude/hooks/lib/lite.md")
else:
    with open(lite_path, encoding="utf-8") as fh:
        lite = " ".join(fh.read().split())
    if len(lite.split()) > MAX_LITE_WORDS:
        bad(
            f".claude/hooks/lib/lite.md is {len(lite.split())} words, over its {MAX_LITE_WORDS}-word budget (it rides every lite session and subagent)"
        )
    with open(os.path.join(ROOT, ".claude/rules/00-core.md"), encoding="utf-8") as fh:
        core_text = fh.read()
    never = " ".join(core_text.split("## Never", 1)[-1].split("\n## ", 1)[0].split())
    for item, phrase in LITE_COVERS:
        if item not in never:
            # A reworded never-list would otherwise switch this check off without a word.
            bad(
                f".claude/rules/00-core.md: the never-list no longer says '{item}' — update LITE_COVERS in tests/harness_lint.py"
            )
        elif phrase not in lite:
            bad(
                f".claude/hooks/lib/lite.md: no line for the never-list item '{item}' (keep '{phrase}')"
            )

# --- debt gate wiring: /review gates the delta, /sync prints the ledger (ADR-0008) ---
for cmd in ("review", "sync"):
    cmd_path = f"{ROOT}/.claude/skills/{cmd}/SKILL.md"
    try:
        with open(cmd_path, encoding="utf-8") as fh:
            if "check-debt.sh" not in fh.read():
                bad(f"{cmd_path}: does not wire check-debt.sh (ADR-0008)")
    except FileNotFoundError:
        bad(f"debt gate wiring: missing {os.path.relpath(cmd_path, ROOT)}")

# --- host rule files: generated from 00-core.md, never hand-edited (hosts/build.py) ---
_hb = os.path.join(ROOT, "hosts", "build.py")
if os.path.exists(_hb):
    import subprocess

    _r = subprocess.run(
        [sys.executable, _hb, "--check"],
        capture_output=True,
        text=True,
        env={**os.environ, "NONNA_LINT_ROOT": ROOT},
    )
    for _line in _r.stderr.splitlines():
        bad(_line)
else:
    bad("hosts/build.py is missing — every agent host's rules file is generated by it")

# --- review lanes: /review sizes itself by script, never by the model's judgement (ADR-0009) ---
review_path = f"{ROOT}/.claude/skills/review/SKILL.md"
try:
    with open(review_path, encoding="utf-8") as fh:
        if "review-lanes.sh" not in fh.read():
            bad(f"{review_path}: does not wire review-lanes.sh (ADR-0009)")
except FileNotFoundError:
    bad("review lanes wiring: missing .claude/skills/review/SKILL.md")

# --- token budget: the always-on surface is gated, not aspirational ---
# CLAUDE.md + rules/*.md are paid on every turn (token-economy.md). Budgets are
# words (whitespace-split — deterministic, no tokenizer dependency). Raising a
# budget is an explicit, reviewable act — that is the point.
# Calibrated 2026-09-23: CLAUDE.md 236, largest rule 517 (00-core.md), total
# 3,690 by this metric (str.split() counts slightly above `wc -w`).
MAX_CLAUDE_MD_WORDS = 300
MAX_RULE_WORDS = 520
MAX_ALWAYS_ON_WORDS = 3700
# 00-core.md is also what a plugin install receives through SessionStart
# additionalContext (ADR-0007), which Claude Code caps at 10,000 characters.
# Overrun does not error — it truncates, silently dropping the tail of the
# constitution for exactly the install mode that has nothing else. Budget under.
MAX_CORE_CHARS = 9000


def word_count(path: str) -> int:
    with open(path, encoding="utf-8") as fh:
        return len(fh.read().split())


always_on = word_count(f"{ROOT}/CLAUDE.md")
if always_on > MAX_CLAUDE_MD_WORDS:
    bad(f"CLAUDE.md: {always_on} words exceeds the {MAX_CLAUDE_MD_WORDS}-word budget")
for path in sorted(glob.glob(f"{ROOT}/.claude/rules/*.md")):
    w = word_count(path)
    always_on += w
    if w > MAX_RULE_WORDS:
        bad(f"{path}: {w} words exceeds the {MAX_RULE_WORDS}-word rule budget")
if always_on > MAX_ALWAYS_ON_WORDS:
    bad(
        f"always-on surface (CLAUDE.md + rules/) is {always_on} words — "
        f"exceeds the {MAX_ALWAYS_ON_WORDS}-word budget (token-economy.md)"
    )
# Descriptions are always-on too: Claude Code injects every skill, agent and
# command description into every turn so it can decide what to load. That made
# them the one part of the surface with no budget at all, and they had grown to
# ~7,000 chars. A description exists to support a load/route DECISION; prose
# past that decision is paid every turn and buys nothing. A skill only the user
# can invoke (disable-model-invocation) is not offered to the model, so its
# description is not paid and not counted.
MAX_DESCRIPTION_CHARS = 5600
desc_chars = 0
for patt in ("skills/*/SKILL.md", "agents/*.md"):
    for p in glob.glob(f"{ROOT}/.claude/{patt}"):
        if fm_value(frontmatter(p) or [], "disable-model-invocation") == "true":
            continue
        m = re.search(r"^description:\s*(.+)$", open(p, encoding="utf-8").read(), re.M)
        if m:
            desc_chars += len(m.group(1))
if desc_chars > MAX_DESCRIPTION_CHARS:
    bad(
        f"skill+agent+command descriptions total {desc_chars} chars — exceeds the "
        f"{MAX_DESCRIPTION_CHARS}-char budget; these load on every turn"
    )

core = f"{ROOT}/.claude/rules/00-core.md"
if not os.path.isfile(core):
    bad(
        "missing .claude/rules/00-core.md — the constitution and the plugin carrier (ADR-0007)"
    )
else:
    core_chars = len(open(core, encoding="utf-8").read())
    if core_chars > MAX_CORE_CHARS:
        bad(
            f"00-core.md is {core_chars} chars — exceeds the {MAX_CORE_CHARS}-char budget; "
            f"SessionStart additionalContext truncates at 10,000 and a plugin install "
            f"would silently lose the tail (ADR-0007)"
        )

# --- plugin packaging: manifests are valid JSON and wired scripts exist ---
plugin_manifest = f"{ROOT}/.claude/.claude-plugin/plugin.json"
marketplace = f"{ROOT}/.claude-plugin/marketplace.json"
plugin_hooks = f"{ROOT}/.claude/hooks/hooks.json"
for jf in (plugin_manifest, marketplace, plugin_hooks):
    if not os.path.isfile(jf):
        bad(f"plugin packaging: missing {os.path.relpath(jf, ROOT)}")
        continue
    try:
        with open(jf, encoding="utf-8") as fh:
            json.load(fh)
    except json.JSONDecodeError as exc:
        bad(f"plugin packaging: invalid JSON in {os.path.relpath(jf, ROOT)}: {exc}")


# --- hook wiring equivalence: two files declare the same gates, with no shared source ---
# settings.json (standalone, $CLAUDE_PROJECT_DIR/.claude/...) and hooks.json
# (plugin, ${CLAUDE_PLUGIN_ROOT}/...) register the SAME gates against the same
# events. Nothing links them, so a gate added to one and forgotten in the other
# is live in one install mode and absent in the other — the exact asymmetry
# ADR-0007 was written about. Generating one from the other would need a build
# step ADR-0006 rejected, so assert equivalence instead.
def hook_shape(rel: str, cfg: dict) -> dict:
    """Event -> matcher -> ordered scripts. A command outside its one form stays whole, so it differs."""
    shape: dict[str, dict[str, list[str]]] = {}
    for event, entries in (cfg.get("hooks") or {}).items():
        by_matcher: dict[str, list[str]] = {}
        for entry in entries:
            scripts = []
            for hook in entry.get("hooks", []):
                cmd = hook.get("command", "")
                # The whole hook, with the command reduced to its script: a timeout or type set in
                # one mode only changes what the gate does in that mode, so it must differ here too.
                rest = {
                    k: v
                    for k, v in hook.items()
                    if k not in ("command", "statusMessage")
                }
                scripts.append(
                    json.dumps(
                        {**rest, "script": hook_script(rel, event, cmd) or cmd},
                        sort_keys=True,
                    )
                )
            by_matcher.setdefault(entry.get("matcher", "*"), []).extend(scripts)
        shape[event] = by_matcher
    return shape


if os.path.isfile(plugin_hooks):
    with open(plugin_hooks, encoding="utf-8") as fh:
        ph = json.load(fh)
    a, b = (
        hook_shape(".claude/settings.json", settings),
        hook_shape(".claude/hooks/hooks.json", ph),
    )
    for event in sorted(set(a) | set(b)):
        if event not in a:
            bad(f"hook wiring: '{event}' is in hooks.json but not settings.json")
        elif event not in b:
            bad(f"hook wiring: '{event}' is in settings.json but not hooks.json")
        elif a[event] != b[event]:
            bad(
                f"hook wiring: '{event}' differs between settings.json and hooks.json "
                f"(settings={a[event]}, plugin={b[event]}) — a gate wired in one "
                f"install mode and not the other"
            )
    # The nonna plugin's root is .claude/ (marketplace source "./.claude").
    check_hook_forms(".claude/hooks/hooks.json", ph)

# --- the core gates are wired, in both install modes ---
# Equivalence alone passes a gate deleted from both files. These are the gates the README promises.
REQUIRED_GATES = {
    ("PreToolUse", "Bash"): ("hooks/guard-branch.sh", "hooks/secret-scan.sh"),
    ("PreToolUse", "Edit|Write|MultiEdit"): (
        "hooks/guard-branch.sh",
        "hooks/secret-scan.sh",
    ),
    ("PreToolUse", "Read|Grep"): ("hooks/secret-scan.sh",),
    ("Stop", "*"): ("hooks/stop-dod.sh",),
    ("SessionStart", "*"): ("hooks/session-start.sh",),
}
for rel, wiring in (
    (".claude/settings.json", settings),
    (".claude/hooks/hooks.json", ph if os.path.isfile(plugin_hooks) else {}),
):
    for (event, matcher), scripts in REQUIRED_GATES.items():
        wired = set()
        for entry in (wiring.get("hooks") or {}).get(event, []):
            if entry.get("matcher", "*") == matcher:
                wired |= {
                    hook_script(rel, event, h.get("command", ""))
                    for h in entry.get("hooks", [])
                }
        for script in scripts:
            if script not in wired:
                bad(f"{rel}: {event} '{matcher}' must run {script} (a core gate)")

# --- every Read settings.json denies, the Read hook refuses too, for Read and for Grep ---
# A plugin install cannot carry permissions.deny: the hook is all it has. Each deny glob becomes a
# sample path, and secret-scan.sh must refuse to Read it, and to Grep it (Claude Code applies Read
# denies to Grep).
for rule in (settings.get("permissions") or {}).get("deny", []):
    m = re.fullmatch(r"Read\((.+)\)", rule)
    if not m:
        continue
    sample = m.group(1).replace("**", "x").replace("*", "a")
    for tool, tool_input in (
        ("Read", {"file_path": sample}),
        ("Grep", {"pattern": ".", "path": sample}),
    ):
        payload = json.dumps({"tool_name": tool, "tool_input": tool_input})
        rc = subprocess.run(
            ["bash", os.path.join(ROOT, ".claude/hooks/secret-scan.sh")],
            input=payload,
            capture_output=True,
            text=True,
            env={**os.environ, "NONNA_MODE": "full", "CLAUDE_PROJECT_DIR": ROOT},
        ).returncode
        if rc != 2:
            bad(
                f".claude/hooks/secret-scan.sh lets the agent {tool} {sample}, which settings.json denies ({rule}); a plugin install has only the hook"
            )

if offenders:
    print("Harness lint FAILED:")
    for o in offenders:
        print(f"  - {o}")
    sys.exit(1)
print("Harness lint OK.")
