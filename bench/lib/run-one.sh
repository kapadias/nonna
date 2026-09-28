#!/usr/bin/env bash
# usage: run-one.sh <suite> <task> <arm> <model> <rep>
# env (set by run.sh): WORK RESULTS CAP TIMEOUT MAX_TURNS RUN_BUDGET PROMPT_MODE LABEL RESCORE CLAUDE_BIN,
#   HARNESS_REPO HARNESS_REF INSTALLER (arm nonna), NONNA_SNAP NONNA_SHA PONYTAIL_SNAP PONYTAIL_SHA
#   (the plugin snapshots run.sh took)
# One run: build the project, run headless Claude Code in it, score it with the hidden check,
# append one row to $RESULTS/<suite>.tsv. RESCORE=1 skips setup and the agent and re-scores an
# existing run dir (no API calls).
#
# The run sees none of this machine's Claude Code or git setup. It starts under env -i with only the
# variables kept below, a fresh config dir ($d.cfg: its global git config and its transcripts too),
# no user settings and no MCP servers. lib/fingerprint.py launches it, and stops it as soon as its
# first events show it is not the arm it claims to be (exit 86), or at TIMEOUT (exit 124).
set -uo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
suite="$1"; t="$2"; arm="$3"; model="$4"; rep="$5"
# The run dir's name is the row's id, so a review-prompt run or a labelled rerun is a run of its own.
id="${t}-${arm}-${model}-${rep}"
[ "${PROMPT_MODE:-neutral}" = review ] && id="$id-review"
[ -n "${LABEL:-}" ] && id="$id-$LABEL"
d="$WORK/$suite/$id"
tsv="$RESULTS/$suite.tsv"

spent() { # total logged spend across every results TSV, by header name
  awk -F'\t' 'FNR==1{c=0; for(i=1;i<=NF;i++) if($i=="cost_usd") c=i; next} c && $c>0 {s+=$c} END{printf "%.2f", s+0}' \
    "$RESULTS"/*.tsv 2>/dev/null || echo 0
}

if [ "${RESCORE:-0}" != 1 ]; then
  s="$(spent)"
  if awk -v s="$s" -v c="$CAP" 'BEGIN{exit !(s>=c)}'; then
    echo "SKIP $id: logged spend \$$s has reached the cap \$$CAP" >&2
    exit 0
  fi
  bash "$B/lib/setup.sh" "$suite" "$t" "$arm" "$d" || { echo "SETUP FAILED $id" >&2; exit 1; }
  # A fresh config dir, with an empty global git config. A ponytail arm starts as a returning user:
  # its first session asks the agent to offer a statusline setup, which a real user sees once.
  cfg="$d.cfg"
  rm -rf "$cfg" "$d.xdg" "$d.transcripts" "$d.fingerprint"
  mkdir -p "$cfg" "$d.xdg" && : > "$cfg/gitconfig"
  case "$arm" in ponytail*) : > "$cfg/.ponytail-statusline-nudged" ;; esac
  plugins=()
  case "$arm" in
    plugin-lite | plugin-full) plugins=(--plugin-dir "$NONNA_SNAP") ;;
    ponytail) plugins=(--plugin-dir "$PONYTAIL_SNAP") ;;
    ponytail+lite) plugins=(--plugin-dir "$PONYTAIL_SNAP" --plugin-dir "$NONNA_SNAP") ;;
  esac
  sid="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  python3 - "$d.fpspec" "$arm" "$model" "$d" "$(cat "$B/tasks/$suite/TESTCMD" 2>/dev/null)" \
    "${NONNA_SNAP:-}" "${PONYTAIL_SNAP:-}" <<'PY'
import json, sys
out, arm, model, cwd, test_cmd, nonna, pony = sys.argv[1:]
with open(out, "w") as fh:
    json.dump({"arm": arm, "model": model, "cwd": cwd, "test_cmd": test_cmd,
               "plugins": {"nonna": nonna, "ponytail": pony}}, fh)
PY
  keep=()
  for v in PATH HOME USER LOGNAME SHELL LANG LC_ALL LC_CTYPE TZ TMPDIR \
    HTTPS_PROXY HTTP_PROXY NO_PROXY https_proxy http_proxy no_proxy \
    SSL_CERT_FILE SSL_CERT_DIR NODE_EXTRA_CA_CERTS REQUESTS_CA_BUNDLE ANTHROPIC_API_KEY; do
    [ -n "${!v:-}" ] && keep+=("$v=${!v}")
  done
  start=$(date +%s)
  # No user settings (--setting-sources) and no MCP servers (--strict-mcp-config, none given).
  # acceptEdits + an explicit tool allowlist: --dangerously-skip-permissions is refused as root.
  (
    cd "$d" && env -i ${keep[@]+"${keep[@]}"} DISABLE_AUTOUPDATER=1 CLAUDE_CONFIG_DIR="$cfg" \
      XDG_CONFIG_HOME="$d.xdg" GIT_CONFIG_GLOBAL="$cfg/gitconfig" GIT_CONFIG_NOSYSTEM=1 \
      python3 "$B/lib/fingerprint.py" run "$d.fpspec" "$d.stream.jsonl" "$d.err.txt" "$d.fingerprint" \
      "${TIMEOUT:-1500}" -- \
      "${CLAUDE_BIN:-claude}" -p "$(cat "$d.prompt")" --model "$model" ${plugins[@]+"${plugins[@]}"} \
      --setting-sources project,local --strict-mcp-config --max-budget-usd "${RUN_BUDGET:-3}" \
      --session-id "$sid" --output-format stream-json --verbose --include-hook-events \
      --permission-mode acceptEdits \
      --allowedTools "Bash,Edit,Write,MultiEdit,Read,Glob,Grep,Task,TodoWrite" \
      --max-turns "${MAX_TURNS:-80}"
  )
  rc=$?
  printf '%s\t%s\n' "$rc" "$(($(date +%s) - start))" > "$d.meta"
  # Keep the session transcripts (subagents included) next to the run: review-lanes output from a
  # subagent is only there.
  proj="$cfg/projects/$(python3 -c "import re,os,sys;print(re.sub(r'[^A-Za-z0-9]','-',os.path.realpath(sys.argv[1])))" "$d")"
  mkdir -p "$d.transcripts"
  cp "$proj/$sid.jsonl" "$d.transcripts/" 2>/dev/null
  [ -d "$proj/$sid" ] && cp -r "$proj/$sid" "$d.transcripts/"
fi

[ -f "$d.meta" ] || { echo "NO RUN $id" >&2; exit 1; }
IFS=$'\t' read -r rc wall < "$d.meta"
# The agent's last word: the final result event's text (a background subagent can add a later one).
python3 -c "import json,sys
t=''
for l in open(sys.argv[1], errors='replace'):
    try: j=json.loads(l)
    except ValueError: continue
    if j.get('type')=='result' and (j.get('result') or '').strip(): t=j['result']
open(sys.argv[2],'w').write(t)" "$d.stream.jsonl" "$d.final.txt" 2>/dev/null || : > "$d.final.txt"

verdict="$(bash "$B/lib/score.sh" "$suite" "$t" "$d")"
harness="$(cat "$d.harness" 2>/dev/null || echo -)"
row="$(python3 "$B/lib/metrics.py" "$suite" "$t" "$arm" "$model" "$rep" "$d" "$verdict" "$rc" "$wall" "${harness:--}" \
  "${PROMPT_MODE:-neutral}" "${LABEL:--}")"
mkdir -p "$RESULTS"
(
  flock 9
  [ -s "$tsv" ] || python3 "$B/lib/metrics.py" --header > "$tsv"
  printf '%s\n' "$row" >> "$tsv"
) 9> "$RESULTS/.lock"
printf '%s\n' "$row"
