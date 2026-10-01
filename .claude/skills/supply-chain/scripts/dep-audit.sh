#!/usr/bin/env bash
# dep-audit.sh — detect the project's ecosystem(s) from lockfiles and run the
# matching known-vulnerability scanner, failing the build on findings.
#
# Part of the Nonna `supply-chain` skill. Fails CLOSED: if a lockfile is present
# but its scanner is not installed, that is an ERROR (a skipped scan is an
# un-run gate), not a silent pass. See .claude/rules/safety.md.
#
# Usage:   dep-audit.sh [project-root]   (defaults to the current directory)
# Exit:    0 = all detected scanners clean
#          1 = at least one scanner reported a vulnerability
#          2 = a scanner is required (lockfile present) but unavailable / errored
#          3 = no recognized lockfile found (nothing to audit)
set -euo pipefail

root="${1:-$(pwd)}"
cd "$root"

# --- outcome tracking -------------------------------------------------------
found_lockfile=0   # did we recognize any ecosystem?
vuln_found=0        # did any scanner report a vulnerability?
gate_error=0        # was a scan required but unrunnable?

log()  { printf '%s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# Record that an ecosystem was detected but its scanner is missing. Fail closed:
# we cannot assert "no vulns" without running the scan.
missing_scanner() {
  local eco="$1" tool="$2" hint="$3"
  log "✗ ${eco}: '${tool}' not installed — cannot verify dependencies."
  log "  install it (${hint}) or run the scan in CI; refusing to pass un-audited."
  gate_error=1
}

# Run a scanner; classify its exit code. Convention for all four tools used
# here: 0 = clean, non-zero = vulnerabilities (or tool error). We treat any
# non-zero as "do not pass" and surface it.
run_scan() {
  local eco="$1"; shift
  log "→ ${eco}: running: $*"
  local rc=0
  "$@" || rc=$?
  if [ "$rc" -eq 0 ]; then
    log "✓ ${eco}: no known vulnerabilities."
  else
    log "✗ ${eco}: scanner exited ${rc} — vulnerabilities or scan error."
    vuln_found=1
  fi
}

# --- Node.js (npm / pnpm / yarn) -------------------------------------------
# npm audit exits non-zero when vulnerabilities are found at/above the level.
if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
  found_lockfile=1
  if have npm; then
    run_scan "npm" npm audit --audit-level=low
  else
    missing_scanner "npm" "npm" "Node.js toolchain"
  fi
fi
if [ -f pnpm-lock.yaml ]; then
  found_lockfile=1
  if have pnpm; then
    run_scan "pnpm" pnpm audit --audit-level=low
  else
    missing_scanner "pnpm" "pnpm" "https://pnpm.io/installation"
  fi
fi
if [ -f yarn.lock ]; then
  found_lockfile=1
  if have yarn; then
    run_scan "yarn" yarn npm audit
  else
    missing_scanner "yarn" "yarn" "https://yarnpkg.com/getting-started/install"
  fi
fi

# --- Python (pip / poetry / pipenv) ----------------------------------------
# pip-audit scans the resolved environment / lock and exits non-zero on vulns.
if [ -f poetry.lock ] || [ -f Pipfile.lock ] || [ -f requirements.txt ] \
  || compgen -G "requirements*.txt" >/dev/null 2>&1; then
  found_lockfile=1
  if have pip-audit; then
    if [ -f poetry.lock ]; then
      run_scan "python (poetry)" pip-audit
    elif [ -f requirements.txt ]; then
      run_scan "python (pip)" pip-audit -r requirements.txt
    else
      run_scan "python" pip-audit
    fi
  else
    missing_scanner "python" "pip-audit" "https://pypi.org/project/pip-audit/"
  fi
fi

# --- Go --------------------------------------------------------------------
# govulncheck reports only vulns reachable from your code; non-zero on findings.
if [ -f go.sum ] || [ -f go.mod ]; then
  found_lockfile=1
  if have govulncheck; then
    run_scan "go" govulncheck ./...
  else
    missing_scanner "go" "govulncheck" "https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck"
  fi
fi

# --- Rust ------------------------------------------------------------------
# cargo audit checks Cargo.lock against the RustSec advisory DB.
if [ -f Cargo.lock ]; then
  found_lockfile=1
  if have cargo-audit || cargo audit --version >/dev/null 2>&1; then
    run_scan "rust" cargo audit
  else
    missing_scanner "rust" "cargo-audit" "https://crates.io/crates/cargo-audit"
  fi
fi

# --- verdict ---------------------------------------------------------------
if [ "$found_lockfile" -eq 0 ]; then
  log "• no recognized lockfile found under ${root} — nothing to audit."
  exit 3
fi
if [ "$gate_error" -eq 1 ]; then
  log "RESULT: BLOCKED — a required scanner was unavailable (fail closed)."
  exit 2
fi
if [ "$vuln_found" -eq 1 ]; then
  log "RESULT: FAIL — known vulnerabilities found. Triage and upgrade before merge."
  exit 1
fi
log "RESULT: PASS — all detected ecosystems clean."
exit 0
