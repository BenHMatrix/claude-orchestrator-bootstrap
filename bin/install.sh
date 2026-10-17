#!/usr/bin/env bash
# install.sh - install or upgrade the Claude Code orchestrator pattern.
#
# Default is a DRY RUN: reports what would change and writes nothing.
# With --apply, the steps run in this order:
#   1. Back up every file about to be changed into
#      $CLAUDE_HOME/backups/orchestrator-<YYYYmmdd-HHMMSS>/ (relative paths kept).
#   2. Agents: copy the five agent templates into $CLAUDE_HOME/agents/.
#   3. CLAUDE.md: create it, or move the "## Orchestrator Mode" section (wherever it
#      is) to the TOP with the template content. Other content is kept byte-identical.
#   4. Spec: copy SPEC.md to $CLAUDE_HOME/orchestrator-setup-spec.md.
#   5. settings.json: set top-level "model" to "opus", keeping every other key.
#      Warn (never remove) if env.CLAUDE_CODE_SUBAGENT_MODEL or an "agent" key exists.
#   6. Memory: copy every note in templates/memory/ and add missing lines to MEMORY.md.
#   7. Run bin/audit.sh; exit non-zero if it fails.
#   8. Remind that changes apply to NEW sessions only.
# Before any of this, a preflight check exits 1 if settings.json is invalid JSON.
# A dry run does steps 2-6 in report-only mode and still runs the audit.
#
# Env: CLAUDE_HOME (default ~/.claude), PROJECTS_ROOT (default ~/Local)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
PROJECTS_ROOT="${PROJECTS_ROOT:-$HOME/Local}"
export CLAUDE_HOME PROJECTS_ROOT

MEMORY_DIR="$CLAUDE_HOME/projects/${HOME//\//-}/memory"
BACKUP_DIR="$CLAUDE_HOME/backups/orchestrator-$(date +%Y%m%d-%H%M%S)"
APPLY=0
BACKED_UP=0
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

usage() {
  cat <<USAGE
Usage: install.sh [--apply] [--help]

  (no flags)  Dry run: show what would change, write nothing.
  --apply     Back up, then install or upgrade the orchestrator pattern.
  --help      Show this help.

Env: CLAUDE_HOME (default ~/.claude), PROJECTS_ROOT (default ~/Local)
USAGE
}

# Copies one live file into the backup dir, keeping its path relative to CLAUDE_HOME.
back_up_file() {
  local live="$1"
  local relative="${live#"$CLAUDE_HOME"/}"
  mkdir -p "$(dirname "$BACKUP_DIR/$relative")"
  cp -p "$live" "$BACKUP_DIR/$relative"
  BACKED_UP=1
}

# Makes the live file at $2 match the source file at $1 (or reports that it would).
# Arg 3 is a label for the report.
sync_file() {
  local source="$1" live="$2" label="$3"
  if [ ! -f "$live" ]; then
    if [ "$APPLY" -eq 1 ]; then
      mkdir -p "$(dirname "$live")"
      cp "$source" "$live"
      echo "  created      $label"
    else
      echo "  would create $label"
    fi
    return
  fi
  if cmp -s "$source" "$live"; then
    echo "  unchanged    $label"
    return
  fi
  if [ "$APPLY" -eq 1 ]; then
    back_up_file "$live"
    cp "$source" "$live"
    echo "  updated      $label"
  else
    echo "  would update $label"
  fi
}

# Writes the desired CLAUDE.md to the file named by $1.
# Rule: the template section goes first, then one blank line, then the existing
# content. If the file already has a "## Orchestrator Mode" section (it ends at the
# next line starting "# " or "## ", or EOF) it is cut out of its old place first,
# and at most one blank line is left at the join.
build_claude_md() {
  local output="$1"
  python3 -I - "$CLAUDE_HOME/CLAUDE.md" "$REPO_DIR/templates/CLAUDE.orchestrator-section.md" "$output" <<'PY'
import os, sys
live_path, template_path, output_path = sys.argv[1:4]
with open(template_path, encoding="utf-8") as f:
    template = f.read()
if not template.endswith("\n"):
    template += "\n"
lines = []
if os.path.exists(live_path):
    with open(live_path, encoding="utf-8") as f:
        lines = f.read().splitlines(keepends=True)
start = None
for i, line in enumerate(lines):
    if line.startswith("## Orchestrator Mode"):
        start = i
        break
if start is None:
    before, after = [], lines
    rest = "".join(lines)
else:
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("## ") or lines[j].startswith("# "):
            end = j
            break
    before = lines[:start]
    after = lines[end:]
    while before and before[-1].strip() == "":
        before.pop()
    while after and after[0].strip() == "":
        after.pop(0)
    rest = "".join(before)
    if before and after:
        rest += "\n"
    rest += "".join(after)
result = template + ("\n" + rest if rest else "")
with open(output_path, "w", encoding="utf-8") as f:
    f.write(result)
PY
}

# Preflight: stop before any write if settings.json exists but is not valid JSON.
preflight_settings() {
  local file="$CLAUDE_HOME/settings.json"
  [ -f "$file" ] || return 0
  if ! python3 -I - "$file" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        json.load(f)
except Exception as exc:
    sys.stderr.write("ERROR: %s is not valid JSON (%s)\n" % (sys.argv[1], exc))
    sys.exit(1)
PY
  then
    echo "Nothing was changed. Fix the file above and re-run." >&2
    exit 1
  fi
}

# Writes the desired settings.json to the file named by $1 and prints warnings.
build_settings() {
  local output="$1"
  python3 -I - "$CLAUDE_HOME/settings.json" "$output" <<'PY'
import json, os, sys
live_path, output_path = sys.argv[1:3]
if not os.path.exists(live_path):
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(json.dumps({"model": "opus"}, indent=2) + "\n")
    sys.exit(0)
with open(live_path, encoding="utf-8") as f:
    original = f.read()
try:
    data = json.loads(original)
except Exception as exc:
    sys.stderr.write("ERROR: %s is not valid JSON (%s); fix it and re-run.\n" % (live_path, exc))
    sys.exit(2)
if not isinstance(data, dict):
    sys.stderr.write("ERROR: %s is not a JSON object.\n" % live_path)
    sys.exit(2)
env = data.get("env")
if isinstance(env, dict) and "CLAUDE_CODE_SUBAGENT_MODEL" in env:
    print("  WARNING: env.CLAUDE_CODE_SUBAGENT_MODEL is set in settings.json. It overrides every agent's model: and breaks the pattern. NOT removed; decide and remove it yourself.")
if "agent" in data:
    print("  WARNING: top-level 'agent' key is set in settings.json. It replaces the main-thread system prompt and is not part of this pattern. NOT removed; decide yourself.")
if data.get("model") == "opus":
    result = original
else:
    data["model"] = "opus"
    result = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
with open(output_path, "w", encoding="utf-8") as f:
    f.write(result)
PY
}

# Writes the desired MEMORY.md to the file named by $1: the existing file plus any
# index line whose target filename (text in parentheses) is not already mentioned.
build_memory_index() {
  local output="$1"
  python3 -I - "$MEMORY_DIR/MEMORY.md" "$REPO_DIR/templates/memory/MEMORY.index-lines.md" "$output" <<'PY'
import os, re, sys
live_path, lines_path, output_path = sys.argv[1:4]
existing = ""
if os.path.exists(live_path):
    with open(live_path, encoding="utf-8") as f:
        existing = f.read()
with open(lines_path, encoding="utf-8") as f:
    index_lines = [l for l in f.read().splitlines() if l.strip()]
result = existing
for line in index_lines:
    match = re.search(r"\(([^)]+)\)", line)
    target = match.group(1) if match else line
    if target in result:
        continue
    if result and not result.endswith("\n"):
        result += "\n"
    result += line + "\n"
with open(output_path, "w", encoding="utf-8") as f:
    f.write(result)
PY
}

install_agents() {
  echo "Agents ($CLAUDE_HOME/agents):"
  local name
  for name in explorer implementer reviewer advisor orchestrator; do
    sync_file "$REPO_DIR/templates/agents/$name.md" "$CLAUDE_HOME/agents/$name.md" "agents/$name.md"
  done
}

install_claude_md() {
  echo "CLAUDE.md:"
  build_claude_md "$SCRATCH/CLAUDE.md"
  sync_file "$SCRATCH/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md" "CLAUDE.md"
}

install_spec() {
  echo "Spec:"
  sync_file "$REPO_DIR/SPEC.md" "$CLAUDE_HOME/orchestrator-setup-spec.md" "orchestrator-setup-spec.md"
}

install_settings() {
  echo "settings.json:"
  build_settings "$SCRATCH/settings.json"
  sync_file "$SCRATCH/settings.json" "$CLAUDE_HOME/settings.json" "settings.json (model: opus)"
}

install_memory() {
  echo "Memory ($MEMORY_DIR):"
  local path note
  for path in "$REPO_DIR"/templates/memory/*.md; do
    note="$(basename "$path")"
    [ "$note" = "MEMORY.index-lines.md" ] && continue
    sync_file "$path" "$MEMORY_DIR/$note" "memory/$note"
  done
  build_memory_index "$SCRATCH/MEMORY.md"
  sync_file "$SCRATCH/MEMORY.md" "$MEMORY_DIR/MEMORY.md" "memory/MEMORY.md"
}

# Step 7: run the audit; returns non-zero if it fails.
run_audit() {
  echo
  echo "Audit:"
  if "$REPO_DIR/bin/audit.sh"; then
    return 0
  fi
  return 1
}

# ---- main ----

case "${1:-}" in
  "") ;;
  --apply) APPLY=1 ;;
  --help|-h) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac

preflight_settings

if [ "$APPLY" -eq 1 ]; then
  echo "APPLY mode. Files that get replaced are backed up to: $BACKUP_DIR"
else
  echo "DRY RUN (nothing will be written). Use --apply to make changes."
fi
echo "CLAUDE_HOME=$CLAUDE_HOME"
echo

install_agents
install_claude_md
install_spec
install_settings
install_memory

if [ "$APPLY" -eq 1 ]; then
  echo
  if [ "$BACKED_UP" -eq 1 ]; then
    echo "Backup written to: $BACKUP_DIR"
  else
    echo "No existing files were replaced, so no backup was needed."
  fi
fi

AUDIT_OK=0
run_audit || AUDIT_OK=1

echo
if [ "$APPLY" -eq 1 ]; then
  echo "Reminder: changes apply to NEW Claude Code sessions only. Open a fresh session."
fi
exit "$AUDIT_OK"
