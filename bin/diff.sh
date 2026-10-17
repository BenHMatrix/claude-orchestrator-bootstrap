#!/usr/bin/env bash
# diff.sh - compare the templates in this repo with the live files in CLAUDE_HOME.
#
# Steps:
#   1. For each template, find its live counterpart.
#      (CLAUDE.md: only the orchestrator section is compared, found with the same
#      heading rule install.sh uses. MEMORY.md: each index line must be present.)
#   2. Print "in sync" or a unified diff, template on the LEFT, live on the RIGHT.
#   3. Exit 1 if anything differs.
#
# Reading the result:
#   - Templates are newer  -> run bin/install.sh --apply.
#   - Live files are newer -> copy the live edits back into templates/, then commit.
#
# Env: CLAUDE_HOME (default ~/.claude)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
MEMORY_DIR="$CLAUDE_HOME/projects/${HOME//\//-}/memory"

DRIFT=0
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# Writes the orchestrator section of a CLAUDE.md to stdout. The section runs from the
# "## Orchestrator Mode" line to the next line starting "# " or "## " (or EOF),
# minus trailing blank lines. Prints nothing if there is no such heading.
extract_section() {
  python3 -I - "$1" <<'PY'
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    lines = f.read().splitlines(keepends=True)
start = None
for i, line in enumerate(lines):
    if line.startswith("## Orchestrator Mode"):
        start = i
        break
if start is None:
    sys.exit(0)
end = len(lines)
for j in range(start + 1, len(lines)):
    if lines[j].startswith("## ") or lines[j].startswith("# "):
        end = j
        break
section = lines[start:end]
while section and section[-1].strip() == "":
    section.pop()
sys.stdout.write("".join(section))
PY
}

# Arg 1: label. Arg 2: template path. Arg 3: live path.
compare_files() {
  local label="$1" template="$2" live="$3"
  if [ ! -f "$live" ]; then
    echo "DRIFT  $label: live file missing ($live)"
    DRIFT=1
    return
  fi
  if diff -u --label "template/$label" --label "live/$label" "$template" "$live" > "$SCRATCH/out.diff"; then
    echo "in sync  $label"
  else
    echo "DRIFT  $label"
    cat "$SCRATCH/out.diff"
    DRIFT=1
  fi
}

compare_claude_md() {
  local live="$CLAUDE_HOME/CLAUDE.md"
  if [ ! -f "$live" ]; then
    echo "DRIFT  CLAUDE.md: live file missing ($live)"
    DRIFT=1
    return
  fi
  extract_section "$live" > "$SCRATCH/live-section.md"
  compare_files "CLAUDE.md (orchestrator section)" \
    "$REPO_DIR/templates/CLAUDE.orchestrator-section.md" "$SCRATCH/live-section.md"
}

compare_memory_index() {
  local live="$MEMORY_DIR/MEMORY.md" missing=0 line
  if [ ! -f "$live" ]; then
    echo "DRIFT  memory/MEMORY.md: live file missing ($live)"
    DRIFT=1
    return
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if ! grep -qxF -- "$line" "$live"; then
      echo "DRIFT  memory/MEMORY.md: index line not in live file: $line"
      missing=1
    fi
  done < "$REPO_DIR/templates/memory/MEMORY.index-lines.md"
  if [ "$missing" -eq 0 ]; then
    echo "in sync  memory/MEMORY.md (index lines)"
  else
    DRIFT=1
  fi
}

echo "Diff: template (left) vs live in $CLAUDE_HOME (right)"
echo "Templates newer -> run bin/install.sh --apply. Live newer -> copy live edits back into templates/."
echo

compare_claude_md
for agent in explorer implementer reviewer advisor orchestrator; do
  compare_files "agents/$agent.md" "$REPO_DIR/templates/agents/$agent.md" "$CLAUDE_HOME/agents/$agent.md"
done
compare_files "SPEC.md" "$REPO_DIR/SPEC.md" "$CLAUDE_HOME/orchestrator-setup-spec.md"
for path in "$REPO_DIR"/templates/memory/*.md; do
  note="$(basename "$path")"
  [ "$note" = "MEMORY.index-lines.md" ] && continue
  compare_files "memory/$note" "$path" "$MEMORY_DIR/$note"
done
compare_memory_index

echo
if [ "$DRIFT" -eq 0 ]; then
  echo "Result: everything in sync"
  exit 0
fi
echo "Result: drift found"
exit 1
