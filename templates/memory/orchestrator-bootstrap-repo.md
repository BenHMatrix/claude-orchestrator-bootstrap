---
name: orchestrator-bootstrap-repo
description: "Canonical source of the orchestrator pattern is the git repo ~/Local/matrix/claude-orchestrator-bootstrap — edit templates there and run bin/install.sh --apply, never edit ~/.claude copies alone"
metadata:
  type: reference
---

The orchestrator pattern (global CLAUDE.md section, the five agents, the spec, these memories, the `model` default) is maintained in the git repo `~/Local/matrix/claude-orchestrator-bootstrap/`. It holds byte-identical templates, `bin/install.sh` (dry run by default, `--apply` to install or upgrade, backs up first), `bin/audit.sh` (project-override audit), `bin/diff.sh` (drift between templates and `~/.claude`), README, CHANGELOG and SPEC.

When changing the pattern: edit the templates in the repo, run `bin/diff.sh`, then `bin/install.sh --apply`, then commit. If a live file under `~/.claude` was edited directly, copy it back into the repo first. Related: [[orchestrator-non-interference]], [[orchestrator-project-overrides-audit]].
