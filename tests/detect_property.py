"""Property: for seeded random piles of marker files and installed runners, nonna_detect_test_cmd names what
the first matching row of TABLE says. Prints three lines for tests/run.sh: how many piles disagreed with the
table; which answers no pile reached (an answer nothing reaches is a row nothing tests); and how many piles
are gated less than the four rows develop had would gate them. If bash itself fails, most likely on the
source, the one line says its status and the first line of its stderr."""

import fnmatch
import os
import random
import shutil
import subprocess
import sys
import tempfile

hooks, log = sys.argv[1], sys.argv[2]
PILES = 312  # 13 rows, each the target of 24 piles: 6 at each of 4 noise densities

ONE_DOTNET = "exactly one *.sln, *.slnx or *.*proj file"
DOTNET = ("App.sln", "App.slnx", "App.csproj", "Lib.fsproj")
PYTEST = ("pytest.ini", "tox.ini", "conftest.py", "tests/test_app.py")
PHPXML = ("phpunit.xml", "phpunit.xml.dist", "phpunit.dist.xml")
# Each row: the answer; the files that must all be there (a tuple: any one of them); the runners that must be
# installed; and whether the files alone claim the repository (only pytest's do: without its runner the search
# ends with nothing). The first row that matches decides. No row matches: nothing.
TABLE = [
    ("python3 -m pytest -q", [PYTEST], ["python3"], True),
    (
        "bundle exec rspec",
        ["Gemfile", (".rspec", "spec/spec_helper.rb")],
        ["bundle"],
        False,
    ),
    ("bundle exec rake test", ["Gemfile", "Rakefile", "test/"], ["bundle"], False),
    ("vendor/bin/pest", [PHPXML, "vendor/bin/pest"], ["php"], False),
    ("vendor/bin/phpunit", [PHPXML, "vendor/bin/phpunit"], ["php"], False),
    ("./gradlew test", ["gradlew"], ["java"], False),
    ("./mvnw test", ["mvnw"], ["java"], False),
    ("mvn test", ["pom.xml"], ["mvn"], False),
    ("dotnet test", [ONE_DOTNET], ["dotnet"], False),
    ("mix test", ["mix.exs"], ["mix"], False),
    ("npm test --silent", ["package.json"], [], False),
    ("go test ./...", ["go.mod"], [], False),
    ("cargo test --quiet", ["Cargo.toml"], [], False),
]
# The four rows develop had. A pile they gate must still be gated here, by one of them or by a new row.
BEFORE = [r for r in TABLE if r[0] in ("python3 -m pytest -q", "npm test --silent", "go test ./...", "cargo test --quiet")]
EXEC = {"gradlew", "mvnw", "vendor/bin/pest", "vendor/bin/phpunit"}
# Noise may be any file the table names, and decoys that change nothing or only the .NET count: a Jasmine
# file in a bare spec/, more solution and project files.
NAMES = {
    n
    for _, needs, _, _ in TABLE
    for need in needs
    if need != ONE_DOTNET
    for n in (need if isinstance(need, tuple) else (need,))
}
FILES = sorted(NAMES) + ["spec/app.spec.js", "docker-compose.dcproj", *DOTNET]
RUNNERS = sorted({t for _, _, tools, _ in TABLE for t in tools})


def there(need, files):
    if need == ONE_DOTNET:
        globs = ("*.sln", "*.slnx", "*.*proj")  # MSBuild's own
        return (
            sum(
                1
                for f in files
                if "/" not in f and any(fnmatch.fnmatchcase(f, g) for g in globs)
            )
            == 1
        )
    return any(n in files for n in (need if isinstance(need, tuple) else (need,)))


def expected(files, runners, rows=TABLE):
    for answer, needs, tools, claims in rows:
        if all(there(n, files) for n in needs):
            if all(t in runners for t in tools):
                return answer
            if claims:
                return ""
    return ""


def pile(rng, row, density):
    """Noise at this density, plus one way for `row` to match; its runners are mostly, not always, there."""
    _, needs, tools, _ = row
    files = {f for f in FILES if rng.random() < density}
    for need in needs:
        files.add(
            rng.choice(DOTNET)
            if need == ONE_DOTNET
            else rng.choice(need)
            if isinstance(need, tuple)
            else need
        )
    return sorted(files), [
        r for r in RUNNERS if rng.random() < (0.9 if r in tools else 0.5)
    ]


def build(root, files):
    for name in files:
        path = os.path.join(root, name)
        if name.endswith("/"):
            os.makedirs(path, exist_ok=True)
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", newline="\n") as fh:  # LF: Windows writes CRLF in text mode
            if name in EXEC:
                fh.write('#!/bin/sh\necho %s >> "%s"\n' % (name, log))
            elif name == "package.json":
                fh.write('{"scripts":{"test":"node t.js"}}\n')
        if name in EXEC:
            os.chmod(path, 0o755)


# The bash on PATH, as the hooks run in: from Python on Windows a bare "bash" is System32's, WSL's.
BASH = shutil.which("bash") or "bash"
# grep, as that bash finds it: a private PATH holds a script that runs it, since Git Bash cannot start a
# link to one of its programs from another directory (it finds no msys-2.0.dll beside the link: exit 127).
GREP = subprocess.run(
    [BASH, "-c", "command -v grep"], stdout=subprocess.PIPE, universal_newlines=True
).stdout.strip()



def sh_path(p):
    """A path as Git Bash reads it: on Windows C:\\a\\b is /c/a/b, since a PATH splits at the drive's colon."""
    if os.name != "nt":
        return p
    drive, rest = os.path.splitdrive(p)
    return "/" + drive.rstrip(":").lower() + rest.replace("\\", "/")


base = tempfile.mkdtemp()
try:
    stubs = os.path.join(base, "stubs")
    os.makedirs(stubs)
    for r in RUNNERS:  # stand-ins: python3 is one that finds pytest, the rest log a run
        with open(os.path.join(stubs, r), "w", newline="\n") as fh:
            fh.write(
                "#!/bin/sh\nexit 0\n"
                if r == "python3"
                else '#!/bin/sh\necho %s >> "%s"\n' % (r, log)
            )
        os.chmod(os.path.join(stubs, r), 0o755)

    rng = random.Random(28)
    piles, lines = [], []
    for i in range(PILES):
        files, runners = pile(
            rng, TABLE[i % len(TABLE)], (0.0, 0.15, 0.3, 0.5)[i // len(TABLE) % 4]
        )
        repo, bindir = (
            os.path.join(base, "p%d" % i, "repo"),
            os.path.join(base, "p%d" % i, "bin"),
        )
        os.makedirs(repo)
        os.makedirs(bindir)
        build(repo, files)
        with open(os.path.join(bindir, "grep"), "w", newline="\n") as fh:
            fh.write("#!/bin/sh\nexec '%s' \"$@\"\n" % GREP.replace("'", "'\\''"))
        os.chmod(os.path.join(bindir, "grep"), 0o755)
        for r in runners:
            os.symlink(os.path.join(stubs, r), os.path.join(bindir, r))
        piles.append((files, runners))
        lines.append("%s|%s" % (sh_path(repo), sh_path(bindir)))

    # One bash, the library sourced once; each pile is detected in a subshell with PATH its own and nothing else.
    script = (
        '. "$1/lib/tests.sh" || exit $?; while IFS= read -r line; do repo="${line%%|*}"; bin="${line#*|}"; '
        '( cd "$repo" && PATH="$bin" nonna_detect_test_cmd ) </dev/null; printf "\\n"; done'
    )
    env = {k: v for k, v in os.environ.items() if k != "JAVA_HOME"}
    # Bytes both ways: in text mode, Windows would end each line bash reads with a CR, and every PATH too.
    run = subprocess.run(
        [BASH, "-c", script, "_", hooks],
        input=("\n".join(lines) + "\n").encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    err = run.stderr.decode(errors="replace")
    if run.returncode:
        print("bash rc=%d: %s" % (run.returncode, (err.splitlines() or [""])[0]))
        sys.exit(1)
    got = run.stdout.decode(errors="replace").split("\n")[:-1]

    seen, bad, less = set(), [], 0
    for n, (files, runners) in enumerate(piles):
        want = expected(files, runners)
        seen.add(want)
        if expected(files, runners, BEFORE) and not (got[n] if n < len(got) else ""):
            less += 1
        if n >= len(got) or got[n] != want:
            bad.append(
                "files=%s runners=%s want=%r got=%r"
                % (files, runners, want, got[n] if n < len(got) else None)
            )
    print(
        "piles=%d mismatches=%d%s"
        % (len(piles), len(bad), " first: " + bad[0] if bad else "")
    )
    print(
        "unreached="
        + ", ".join(
            [a for a, _, _, _ in TABLE if a not in seen]
            + ([] if "" in seen else ["(nothing)"])
        )
    )
    print("gated_less=%d" % less)
finally:
    shutil.rmtree(base, ignore_errors=True)
