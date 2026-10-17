#!/usr/bin/env bash
# audit.sh - check that nothing on this machine undermines the orchestrator pattern.
#
# Steps:
#   a. Global settings.json has no top-level "agent" key and no env.CLAUDE_CODE_SUBAGENT_MODEL.
#   b. No project .claude/settings*.json under PROJECTS_ROOT sets "model", "agent",
#      or env.CLAUDE_CODE_SUBAGENT_MODEL (and every one of them parses as JSON).
#   c. No shell rc file mentions CLAUDE_CODE_SUBAGENT_MODEL.
#   d. The five agent files exist with the expected "model:" frontmatter.
#   e. Global CLAUDE.md starts with the orchestrator section heading.
#
# Prints PASS/FAIL per check with evidence. Exits 1 if any check fails.
#
# Env: CLAUDE_HOME (default ~/.claude), PROJECTS_ROOT (default ~/Local),
#      PROJECTS_DEPTH (find -maxdepth for check b, default 6).
#      Check c reads rc files from $HOME; set HOME too to isolate a sandbox run.

set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
PROJECTS_ROOT="${PROJECTS_ROOT:-$HOME/Local}"
PROJECTS_DEPTH="${PROJECTS_DEPTH:-6}"
HEADING="## Orchestrator Mode — keyed to model tier"

FAILURES=0
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# Evidence lines are queued in a file and printed right after the next PASS/FAIL line.
EVIDENCE_FILE="$SCRATCH/evidence.txt"
: > "$EVIDENCE_FILE"

evidence() {
  echo "      $1" >> "$EVIDENCE_FILE"
}

flush_evidence() {
  cat "$EVIDENCE_FILE"
  : > "$EVIDENCE_FILE"
}

pass() {
  echo "PASS  $1"
  flush_evidence
}

fail() {
  echo "FAIL  $1"
  FAILURES=$((FAILURES + 1))
  flush_evidence
}

# Prints one line per problem found in a settings file, e.g. "top-level model".
# Prints "INVALID JSON ..." if the file does not parse.
# Arg 1: path. Arg 2: "global" (only agent + env var matter) or "project" (model matters too).
problems_in_settings() {
  python3 -I - "$1" "$2" <<'PY'
import json, sys
path, scope = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except Exception as exc:
    print("INVALID JSON (%s)" % exc)
    sys.exit(0)
if not isinstance(data, dict):
    print("INVALID settings (top level is not an object)")
    sys.exit(0)
if scope == "project" and "model" in data:
    print("top-level model = %r" % (data["model"],))
if "agent" in data:
    print("top-level agent = %r" % (data["agent"],))
env = data.get("env")
if isinstance(env, dict) and "CLAUDE_CODE_SUBAGENT_MODEL" in env:
    print("env.CLAUDE_CODE_SUBAGENT_MODEL = %r" % (env["CLAUDE_CODE_SUBAGENT_MODEL"],))
PY
}

check_global_settings() {
  local file="$CLAUDE_HOME/settings.json"
  if [ ! -f "$file" ]; then
    pass "a. global settings.json (file missing, nothing to override)"
    return
  fi
  local found
  found="$(problems_in_settings "$file" global)"
  if [ -z "$found" ]; then
    pass "a. global settings.json has no agent key and no CLAUDE_CODE_SUBAGENT_MODEL"
  else
    while IFS= read -r line; do evidence "$line"; done <<< "$found"
    fail "a. global settings.json overrides the pattern: $file (details below)"
  fi
}

check_project_settings() {
  local list="$SCRATCH/project-files.txt"
  : > "$list"
  if [ -d "$PROJECTS_ROOT" ]; then
    find "$PROJECTS_ROOT" -maxdepth "$PROJECTS_DEPTH" -type f \
      \( -name settings.json -o -name settings.local.json \) \
      -path '*/.claude/*' \
      -not -path '*/node_modules/*' -not -path '*/vendor/*' \
      | sort > "$list"
  fi
  local count bad=0 file found
  count="$(wc -l < "$list" | tr -d ' ')"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    found="$(problems_in_settings "$file" project)"
    if [ -n "$found" ]; then
      bad=$((bad + 1))
      while IFS= read -r line; do evidence "$file: $line"; done <<< "$found"
    fi
  done < "$list"
  if [ "$bad" -eq 0 ]; then
    pass "b. $count project settings file(s) clean (root $PROJECTS_ROOT, depth $PROJECTS_DEPTH)"
  else
    fail "b. $bad project settings file(s) override the pattern, root $PROJECTS_ROOT, depth $PROJECTS_DEPTH (details below)"
  fi
}

check_shell_rc_files() {
  local rc hits=0 present=0
  for rc in .zshrc .zprofile .zshenv .bashrc .bash_profile; do
    [ -f "$HOME/$rc" ] || continue
    present=$((present + 1))
    if grep -n 'CLAUDE_CODE_SUBAGENT_MODEL' "$HOME/$rc" > "$SCRATCH/rc-hits.txt"; then
      hits=$((hits + 1))
      while IFS= read -r line; do evidence "~/$rc:$line"; done < "$SCRATCH/rc-hits.txt"
    fi
  done
  if [ "$hits" -eq 0 ]; then
    pass "c. $present shell rc file(s) checked, none mention CLAUDE_CODE_SUBAGENT_MODEL"
  else
    fail "c. $hits shell rc file(s) mention CLAUDE_CODE_SUBAGENT_MODEL (details below)"
  fi
}

# Prints the value of "model:" from the first frontmatter block of a file.
frontmatter_model() {
  awk '
    NR == 1 && $0 == "---" { infront = 1; next }
    infront && $0 == "---" { exit }
    infront && /^model:/ { sub(/^model:[ \t]*/, ""); print; exit }
  ' "$1"
}

check_agents() {
  local bad=0 pair name expected file actual
  for pair in explorer=haiku implementer=sonnet reviewer=sonnet advisor=fable orchestrator=inherit; do
    name="${pair%%=*}"
    expected="${pair##*=}"
    file="$CLAUDE_HOME/agents/$name.md"
    if [ ! -f "$file" ]; then
      bad=$((bad + 1))
      evidence "$name: missing ($file)"
      continue
    fi
    actual="$(frontmatter_model "$file")"
    if [ "$actual" != "$expected" ]; then
      bad=$((bad + 1))
      evidence "$name: model is '$actual', expected '$expected'"
    fi
  done
  if [ "$bad" -eq 0 ]; then
    pass "d. all five agents present with expected model values"
  else
    fail "d. $bad agent problem(s) in $CLAUDE_HOME/agents (details below)"
  fi
}

check_claude_md() {
  local file="$CLAUDE_HOME/CLAUDE.md"
  if [ ! -f "$file" ]; then
    fail "e. $file does not exist"
    return
  fi
  local first
  first="$(awk 'NF { print; exit }' "$file")"
  if [ "$first" = "$HEADING" ]; then
    pass "e. CLAUDE.md starts with the orchestrator section"
  else
    fail "e. CLAUDE.md first non-blank line is not the orchestrator heading"
    evidence "found: $first"
  fi
}

echo "Orchestrator audit (CLAUDE_HOME=$CLAUDE_HOME, PROJECTS_ROOT=$PROJECTS_ROOT)"
check_global_settings
check_project_settings
check_shell_rc_files
check_agents
check_claude_md

if [ "$FAILURES" -eq 0 ]; then
  echo "Audit result: PASS"
  exit 0
fi
echo "Audit result: FAIL ($FAILURES check(s) failed)"
exit 1
