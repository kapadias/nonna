"""lib/setup.sh: the project each arm starts from. Plugin arms get the same bare tree as `none`,
plus the git config her SessionStart would record; the prompt mode decides what the small tasks
ask for."""

import os
import subprocess

import pytest

V = os.path.dirname(os.path.abspath(__file__))
B = os.path.dirname(V)
ROOT = os.path.dirname(B)
SETUP = os.path.join(B, "lib", "setup.sh")
REVIEW = "Run /review before you finish."
NEUTRAL = "Review your change before you finish."


def setup(tmp_path, arm, suite="small", task="d3", prompt=None, **env):
    d = tmp_path / "run" / f"{task}-{arm}"
    e = dict(
        os.environ,
        NONNA_SHA="abc1234",
        PONYTAIL_SHA="def5678",
        HARNESS_REPO=ROOT,
        HARNESS_REF="HEAD",
    )
    e.pop("PROMPT_MODE", None)
    if prompt:
        e["PROMPT_MODE"] = prompt
    e.update(env)
    r = subprocess.run(
        ["bash", SETUP, suite, task, arm, str(d)], env=e, capture_output=True, text=True
    )
    return d, r


def cfg(d, key):
    r = subprocess.run(
        ["git", "-C", str(d), "config", "--local", "--get", key],
        capture_output=True,
        text=True,
    )
    return r.stdout.strip() if r.returncode == 0 else None


def side(d, ext):
    p = str(d) + ext
    return open(p).read().strip() if os.path.exists(p) else None


TESTCMD = (
    open(os.path.join(B, "tasks", "small", "TESTCMD")).read().strip()
    if os.path.exists(os.path.join(B, "tasks", "small", "TESTCMD"))
    else None
)


@pytest.mark.parametrize(
    "arm,mode,harness",
    [
        ("plugin-lite", "lite", "nonna@abc1234"),
        ("plugin-full", "full", "nonna@abc1234"),
        ("ponytail", None, "ponytail@def5678"),
        ("ponytail+lite", "lite", "nonna@abc1234+ponytail@def5678"),
        ("none", None, None),
    ],
)
def test_plugin_arms_get_a_bare_tree_and_her_config(tmp_path, arm, mode, harness):
    d, r = setup(tmp_path, arm)
    assert r.returncode == 0, r.stderr
    assert cfg(d, "nonna.mode") == mode
    assert cfg(d, "nonna.testCmd") == (TESTCMD if mode else None)
    assert TESTCMD == "python3 -m pytest -q"
    assert side(d, ".harness") == harness
    assert not (d / ".claude").exists() and not (d / "CLAUDE.md").exists()
    status = subprocess.run(
        ["git", "-C", str(d), "status", "--porcelain"], capture_output=True, text=True
    ).stdout
    assert status == ""
    branch = subprocess.run(
        ["git", "-C", str(d), "branch", "--show-current"],
        capture_output=True,
        text=True,
    ).stdout
    assert branch.strip() == "feature/work"


def test_the_installer_arm_installs_the_whole_harness(tmp_path):
    """install.sh defaults to lite; the `nonna` arm is rounds 1-2's copy-in, the whole harness."""
    d, r = setup(tmp_path, "nonna", INSTALLER=ROOT)
    assert r.returncode == 0, r.stderr
    assert (d / ".claude" / "rules" / "00-core.md").is_file()
    assert cfg(d, "nonna.defaultMode") == "full"


def test_an_installer_without_modes_is_not_given_one(tmp_path):
    """Rounds 1-2's install.sh knew no --mode (the whole harness was its only shape) and refuses
    an argument it does not know, so a rerun at their harness ref must not pass one."""
    old = tmp_path / "old"
    old.mkdir()
    (old / "install.sh").write_text(
        "#!/usr/bin/env bash\n"
        '[ "$#" -eq 0 ] || { echo "install.sh: unknown argument \'$1\'" >&2; exit 2; }\n'
        "mkdir -p .claude/rules && echo core > .claude/rules/00-core.md\n"
    )
    git = ["git", "-C", str(old), "-c", "user.name=t", "-c", "user.email=t@example.com"]
    subprocess.run(git[:3] + ["init", "-q"], check=True)
    subprocess.run(git + ["add", "-A"], check=True)
    subprocess.run(git + ["commit", "-q", "-m", "old"], check=True)
    d, r = setup(tmp_path, "nonna", INSTALLER=str(old))
    assert r.returncode == 0, r.stderr
    assert (d / ".claude" / "rules" / "00-core.md").is_file()


@pytest.mark.parametrize("suite", ["traps", "small"])
def test_every_suite_names_its_test_command(suite):
    with open(os.path.join(B, "tasks", suite, "TESTCMD")) as fh:
        assert fh.read().strip() == "python3 -m pytest -q"


@pytest.mark.parametrize(
    "arm,prompt,want",
    [
        ("none", None, NEUTRAL),
        ("plugin-lite", None, NEUTRAL),
        ("plugin-full", "neutral", NEUTRAL),
        ("ponytail", "neutral", NEUTRAL),
        ("ponytail+lite", "neutral", NEUTRAL),
        ("nonna", "neutral", NEUTRAL),
        ("none", "review", NEUTRAL),
        ("ponytail", "review", NEUTRAL),
        ("nonna", "review", REVIEW),
        ("plugin-lite", "review", "Run /nonna:review before you finish."),
        ("plugin-full", "review", "Run /nonna:review before you finish."),
        ("ponytail+lite", "review", "Run /nonna:review before you finish."),
    ],
)
def test_the_prompt_mode(tmp_path, arm, prompt, want):
    d, r = setup(tmp_path, arm, prompt=prompt)
    assert r.returncode == 0, r.stderr
    text = side(d, ".prompt")
    assert text.endswith(want + " Do not commit; do not push.")


def test_a_trap_prompt_is_the_same_in_every_arm(tmp_path):
    texts = set()
    for arm in ("none", "plugin-lite", "ponytail+lite"):
        d, r = setup(tmp_path, arm, suite="traps", task="no-test", prompt="review")
        assert r.returncode == 0, r.stderr
        texts.add(side(d, ".prompt"))
    assert len(texts) == 1


@pytest.mark.parametrize(
    "arm,env,msg",
    [
        ("nonna-lite", {}, "unknown arm"),
        ("plugin-lite", {"PROMPT_MODE": "polite"}, "prompt mode"),
        ("plugin-lite", {"NONNA_SHA": ""}, "NONNA_SHA"),
        ("ponytail", {"PONYTAIL_SHA": ""}, "PONYTAIL_SHA"),
    ],
)
def test_refusals(tmp_path, arm, env, msg):
    d, r = setup(tmp_path, arm, **env)
    assert r.returncode == 2
    assert msg in r.stderr


def test_the_users_git_config_stays_out_of_the_project(tmp_path):
    """A global init template (a hook manager, say) would plant hooks in every run's .git."""
    home = tmp_path / "home"
    (home / "tpl" / "hooks").mkdir(parents=True)
    hook = home / "tpl" / "hooks" / "pre-commit"
    hook.write_text("#!/bin/sh\nexit 1\n")
    hook.chmod(0o755)
    (home / ".gitconfig").write_text(
        f"[init]\n\ttemplateDir = {home / 'tpl'}\n[nonna]\n\tmode = off\n"
    )
    d, r = setup(tmp_path, "none", HOME=str(home), XDG_CONFIG_HOME=str(home / "xdg"))
    assert r.returncode == 0, r.stderr
    assert not (d / ".git" / "hooks" / "pre-commit").exists()
