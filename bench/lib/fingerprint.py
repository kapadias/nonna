#!/usr/bin/env python3
"""Is this run the arm it claims to be? Decided from the start of its stream-json transcript.

usage: fingerprint.py check <stream.jsonl> <spec.json>
         -> prints ok:<hash8> or mismatch:<why> (a finished run: still undecided is a mismatch)
       fingerprint.py run <spec.json> <stream.jsonl> <err.txt> <verdict-file> <timeout-s> -- <cmd...>
         -> runs cmd in its own process group, stdout to the stream; writes the verdict as soon as
            it is known and stops the whole group on a mismatch. Exits with cmd's status, 124 on
            timeout (as timeout(1) does), 86 when stopped on a mismatch, 128+N when itself stopped
            by signal N.

spec.json: {"arm", "model" (the --model alias), "cwd" (the run dir), "test_cmd", "plugins":
{name: snapshot dir}}.

Claude Code writes every SessionStart hook's response before its init event, and init before the
first model call, so a mismatch costs at most one call, and none when init alone decides it. A run
is stopped when:
  * its plugins (built-ins aside) are not its arm's, or one was not loaded inline (--plugin-dir)
    from its snapshot, or there are plugin errors or any MCP server;
  * it does not bill ANTHROPIC_API_KEY in acceptEdits mode, on the alias's model family, in its
    run dir;
  * its SessionStart output is not exactly its arm's: Nonna on in the arm's mode with the task's
    test gate and no warning (any version, for the copy-in arm), ponytail on without its statusline
    nudge, and no other SessionStart hook.
ok:<hash8> names the configuration (plugin versions, model, CLI version, tools, agents, skills), so
a group of runs that mixes two of them can be flagged.
"""

import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time

# arm -> (plugins it loads, Nonna's expected mode: None | "lite" | "full" | "copy-in", ponytail on)
ARMS = {
    "none": (frozenset(), None, False),
    "nonna": (frozenset(), "copy-in", False),
    "plugin-lite": (frozenset({"nonna"}), "lite", False),
    "plugin-full": (frozenset({"nonna"}), "full", False),
    "ponytail": (frozenset({"ponytail"}), None, True),
    "ponytail+lite": (frozenset({"nonna", "ponytail"}), "lite", True),
}
NONNA_ON = re.compile(r"Nonna (?:is on \((\w+)\)|harness active)")
PONYTAIL_ON = "PONYTAIL MODE ACTIVE — level: "
PONYTAIL_NUDGE = "STATUSLINE SETUP NEEDED"
FAMILIES = ("fable", "opus", "sonnet", "haiku")
ABORTED = 86


def _family(model):
    m = (model or "").lower()
    return next((f for f in FAMILIES if f in m), None)


def _text(ev):
    """What a SessionStart hook said: its additionalContext and systemMessage, else its raw stdout."""
    out = ev.get("stdout") or ev.get("output") or ""
    try:
        j = json.loads(out)
    except ValueError:
        return out
    if not isinstance(j, dict):
        return out
    hso = j.get("hookSpecificOutput") or {}
    return "\n".join(
        s
        for s in (hso.get("additionalContext"), j.get("systemMessage"))
        if isinstance(s, str)
    )


def _real(p):
    return os.path.realpath(p) if p else ""


def _hash(init):
    key = {
        "plugins": sorted(
            (p.get("name", ""), p.get("version", ""), p.get("source", ""))
            for p in init.get("plugins") or []
        ),
        "model": init.get("model"),
        "cli": init.get("claude_code_version"),
        "permissionMode": init.get("permissionMode"),
        "apiKeySource": init.get("apiKeySource"),
        "output_style": init.get("output_style"),
        "tools": sorted(init.get("tools") or []),
        "agents": sorted(init.get("agents") or []),
        "skills": sorted(init.get("skills") or []),
    }
    return hashlib.sha256(json.dumps(key, sort_keys=True).encode()).hexdigest()[:8]


def _check_init(init, spec):
    want, _, _ = ARMS[spec["arm"]]
    loaded = [
        p
        for p in init.get("plugins") or []
        if not str(p.get("source", "")).endswith("@builtin")
    ]
    names = {p.get("name") for p in loaded}
    if names != set(want):
        return f"plugins {sorted(names)} are not the arm's {sorted(want)}"
    for p in loaded:
        name = p.get("name")
        if p.get("source") != f"{name}@inline":
            return f"plugin {name} came from {p.get('source')}, not --plugin-dir"
        if _real(p.get("path")) != _real(spec["plugins"].get(name)):
            return f"plugin {name} at {p.get('path')} is not the snapshot {spec['plugins'].get(name)}"
    if init.get("plugin_errors"):
        e = init["plugin_errors"][0]
        return f"plugin errors: {e.get('plugin')}: {e.get('message')}"
    if init.get("mcp_servers") or init.get("mcp_server_errors"):
        return f"MCP servers: {[m.get('name') for m in init.get('mcp_servers') or []]}"
    if init.get("apiKeySource") != "ANTHROPIC_API_KEY":
        return f"apiKeySource is {init.get('apiKeySource')}, not ANTHROPIC_API_KEY"
    if init.get("permissionMode") != "acceptEdits":
        return f"permissionMode is {init.get('permissionMode')}, not acceptEdits"
    fam = _family(spec["model"])
    if (fam and _family(init.get("model")) != fam) or (
        not fam and init.get("model") != spec["model"]
    ):
        return f"model {init.get('model')} is not {spec['model']}"
    if _real(init.get("cwd")) != _real(spec["cwd"]):
        return f"cwd {init.get('cwd')} is not the run dir {spec['cwd']}"
    return ""


def _check_session_start(responses, spec):
    """-> (mismatch reason, what is still missing)."""
    _, mode, pony = ARMS[spec["arm"]]
    nonna_texts, pony_texts = [], []
    for ev in responses:
        if ev.get("exit_code") not in (0, None):
            return (
                f"a SessionStart hook failed (exit {ev.get('exit_code')}): {ev.get('hook_name')}",
                [],
            )
        t = _text(ev)
        if NONNA_ON.search(t):
            nonna_texts.append(t)
        elif PONYTAIL_ON in t:
            pony_texts.append(t)
        else:
            return f"unexpected SessionStart output: {t[:80]!r}", []
    if nonna_texts and mode is None:
        return "Nonna's SessionStart ran in an arm without her", []
    if pony_texts and not pony:
        return "ponytail's SessionStart ran in an arm without it", []
    missing = []
    if mode is not None:
        if not nonna_texts:
            missing.append("no SessionStart from Nonna")
        for t in nonna_texts:
            got = NONNA_ON.search(t).group(1)
            if mode != "copy-in":
                if got != mode:
                    return f"Nonna is on ({got}), not {mode}", []
                if f"Test gate: {spec['test_cmd']} runs" not in t:
                    return f"Nonna's test gate is not `{spec['test_cmd']}`", []
            if "WARNING:" in t:
                return (
                    f"Nonna's SessionStart warns: {t[t.index('WARNING:') :][:120]}",
                    [],
                )
    if pony:
        if not pony_texts:
            missing.append("no SessionStart from ponytail")
        if any(PONYTAIL_NUDGE in t for t in pony_texts):
            return (
                "ponytail's statusline nudge is on (its flag was not set in the config dir)",
                [],
            )
    return "", missing


def check(events, spec, final=False):
    """-> ("ok", hash8) | ("mismatch", why) | ("pending", "")."""
    if spec.get("arm") not in ARMS:
        raise ValueError(f"unknown arm {spec.get('arm')!r} (known: {', '.join(ARMS)})")
    init, called, responses = None, False, []
    for ev in events:
        if ev.get("type") == "system" and ev.get("subtype") == "init" and init is None:
            init = ev
        elif (
            ev.get("type") == "system"
            and ev.get("subtype") == "hook_response"
            and ev.get("hook_event") == "SessionStart"
        ):
            responses.append(ev)
        elif ev.get("type") in ("assistant", "result"):
            called = True
            break
    if init is None:
        if called or final:
            return "mismatch", "no init event: the run did not start as Claude Code"
        return "pending", ""
    why = _check_init(init, spec)
    if not why:
        why, missing = _check_session_start(responses, spec)
        if not why and missing:
            if not (called or final):
                return "pending", ""
            why = "; ".join(missing)
    return ("mismatch", why) if why else ("ok", _hash(init))


def _kill_group(p):
    """TERM the run's process group, then KILL whatever is left of it."""
    for sig, grace in ((signal.SIGTERM, 5), (signal.SIGKILL, 5)):
        try:
            os.killpg(p.pid, sig)
        except (ProcessLookupError, PermissionError):
            return
        try:
            p.wait(grace)
            break
        except subprocess.TimeoutExpired:
            continue
    try:
        os.killpg(
            p.pid, signal.SIGKILL
        )  # stragglers: hook or tool processes the run left behind
    except (ProcessLookupError, PermissionError):
        pass


def run(spec_path, stream, err, verdict_path, timeout, cmd):
    with open(spec_path, encoding="utf-8") as fh:
        spec = json.load(fh)
    ARMS[spec["arm"]]  # an unknown arm fails before anything runs

    def decide(v):
        with open(verdict_path, "w", encoding="utf-8") as fh:
            fh.write(f"{v[0]}:{v[1]}\n")
        return v

    with open(stream, "wb") as out, open(err, "wb") as er:
        p = subprocess.Popen(
            cmd, stdin=subprocess.DEVNULL, stdout=out, stderr=er, start_new_session=True
        )

    def stop(signum, _frame):
        _kill_group(p)
        if not os.path.exists(verdict_path):
            decide(("interrupted", f"signal {signum}"))
        sys.exit(128 + signum)

    for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(s, stop)

    deadline = time.monotonic() + timeout
    events, buf, verdict = [], b"", None
    with open(stream, "rb") as rd:
        while True:
            rc = p.poll()
            chunk = rd.read()
            if verdict is None and chunk:
                buf += chunk
                *lines, buf = buf.split(b"\n")
                for line in lines:
                    try:
                        events.append(json.loads(line))
                    except ValueError:
                        pass
                v = check(events, spec)
                if v[0] != "pending":
                    verdict = decide(v)
                    if v[0] == "mismatch":
                        _kill_group(p)
                        return ABORTED
            if rc is not None:
                if verdict is None:
                    try:
                        events.append(json.loads(buf))
                    except ValueError:
                        pass
                    decide(check(events, spec, final=True))
                _kill_group(p)
                return rc if rc >= 0 else 128 - rc
            if time.monotonic() >= deadline:
                _kill_group(p)
                if verdict is None:
                    decide(check(events, spec, final=True))
                return 124
            time.sleep(0.05)


def main(argv):
    if argv[:1] == ["check"] and len(argv) == 3:
        with open(argv[2], encoding="utf-8") as fh:
            spec = json.load(fh)
        events = []
        try:
            with open(argv[1], encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    try:
                        events.append(json.loads(line))
                    except ValueError:
                        pass
        except FileNotFoundError:
            pass
        v = check(events, spec, final=True)
        print(f"{v[0]}:{v[1]}")
        return 0
    if argv[:1] == ["run"] and len(argv) >= 8 and argv[6] == "--":
        return run(argv[1], argv[2], argv[3], argv[4], float(argv[5]), argv[7:])
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
