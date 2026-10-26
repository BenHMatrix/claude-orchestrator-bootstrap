# claude-orchestrator-bootstrap

Installs and maintains a tiered orchestrator setup for [Claude Code](https://claude.com/claude-code): the session model plans, delegates, reviews and integrates, while cheaper pinned subagents do the exploration, implementation and verification. A stronger model is brought in only at review gates. The repo contains the templates, an idempotent installer, an audit that catches configuration that silently defeats the setup, and a drift check between the templates and the live configuration.

## How it works

Claude Code resolves a subagent's model from its agent definition, so pinning `model:` in each agent file is deterministic. The behavioural rules live in the global `CLAUDE.md` and are advisory, which keeps mid-session judgment and conversational override intact. Together they give:

| Session model   | Behaviour                                                                                                      |
|-----------------|----------------------------------------------------------------------------------------------------------------|
| Opus            | Orchestrates. Delegates to `explorer`, `implementer`, `reviewer`. Uses `advisor` (Fable) at review gates.       |
| Fable           | Orchestrates the same way. Does its own acceptance and never spawns `advisor`.                                 |
| Sonnet, Haiku   | Uninstructed. Stock Claude Code behaviour.                                                                     |

The agents:

| Agent         | Model   | Role                                                                                     |
|---------------|---------|------------------------------------------------------------------------------------------|
| `explorer`    | Haiku   | Read-only search and summary. Never modifies anything.                                   |
| `implementer` | Sonnet  | Implements one briefed slice. Stays inside scope, reports conflicts instead of guessing. |
| `reviewer`    | Sonnet  | Verifies a slice against its brief. Runs tests, reports real output, never fixes.         |
| `advisor`     | Fable   | Plan critique, final acceptance, and escalation for Opus sessions. Read-only plus Bash.  |
| `orchestrator`| inherit | Reserve main-thread profile. Installed but not activated.                                |

The advisor is used at exactly three points: a plan gate before any implementation on multi-slice work, an acceptance gate on every delegated slice after the reviewer passes, and escalation when a decision is ambiguous, the brief conflicts with the code, or a slice has failed twice. Its verdicts are `APPROVE`, `AMEND` or `REJECT`, and the orchestrator may not silently drop a finding.

`/model` is the per-session mode switch. The installer sets `"model": "opus"` as the default in the global settings file and owns no other settings key.

Design rationale and the constraints that follow from it are in [SPEC.md](SPEC.md). Version history is in [CHANGELOG.md](CHANGELOG.md).

## Requirements

- macOS or Linux with `bash` and `python3`
- Claude Code with user-level agent definitions (`~/.claude/agents/`)
- A `/model` picker that offers Opus, Fable, Sonnet and Haiku

## Installation

```sh
git clone <repo-url> claude-orchestrator-bootstrap
cd claude-orchestrator-bootstrap
bin/install.sh            # dry run: prints unchanged / would create / would update
bin/install.sh --apply    # install
```

Open a new Claude Code session afterwards. Running sessions do not pick up the change.

The installer writes:

| Target                                              | Action                                                                 |
|-----------------------------------------------------|------------------------------------------------------------------------|
| `~/.claude/agents/*.md`                             | Five agent files, overwritten after backup                             |
| `~/.claude/CLAUDE.md`                               | `## Orchestrator Mode` section placed at the top; other content kept    |
| `~/.claude/orchestrator-setup-spec.md`              | Copy of `SPEC.md`                                                      |
| `~/.claude/settings.json`                           | `"model": "opus"`; no other key touched                                |
| `~/.claude/projects/<home>/memory/`                 | Memory notes and their `MEMORY.md` index lines                         |

Every file about to change is first copied to `~/.claude/backups/orchestrator-<timestamp>/`. A second `--apply` reports everything unchanged.

## Upgrading an existing setup

Run the same two commands. The installer replaces the agent files and the spec, and relocates or inserts the `## Orchestrator Mode` section at the top of `CLAUDE.md`. The old section is taken to run from its heading to the next `# ` or `## ` heading or the end of the file. All other `CLAUDE.md` content is preserved byte for byte, except that blank lines at the join are collapsed to one.

`settings.json` is validated as JSON before anything is written; an invalid file aborts the run with exit 1 and no changes. When `model` needs setting, the file is re-serialised with two-space indentation and its original key order, so formatting may change. `env` and `agent` are never modified. If `env.CLAUDE_CODE_SUBAGENT_MODEL` or a top-level `agent` key is present the installer prints a warning, leaves the key in place, and the audit fails so the decision is explicit.

## Auditing

```sh
bin/audit.sh
```

Checks, each reported as `PASS` or `FAIL` with evidence, exit 1 on any failure:

1. The global `settings.json` has no `agent` key and no `env.CLAUDE_CODE_SUBAGENT_MODEL`.
2. No `.claude/settings.json` or `.claude/settings.local.json` under `PROJECTS_ROOT` sets `model`, `agent` or `env.CLAUDE_CODE_SUBAGENT_MODEL`, and every such file is valid JSON.
3. No shell rc file in `$HOME` mentions `CLAUDE_CODE_SUBAGENT_MODEL`.
4. The five agent files exist with the expected `model:` values.
5. `CLAUDE.md` starts with the orchestrator section.

Project-level settings override global settings. A project file that sets `model` stops the tier-keyed rules engaging for that project, and `CLAUDE_CODE_SUBAGENT_MODEL` overrides every agent's `model:` pin, flattening the tiers and defeating the advisor gate. Both are silent, which is why the audit exists and why `install.sh` runs it at the end.

## Drift check

```sh
bin/diff.sh
```

Compares every template with its live counterpart, template on the left and live on the right, and exits 1 on any difference. If the templates are newer, run `bin/install.sh --apply`. If the live files are newer, copy the edits back into `templates/` and commit.

## Customising

1. Edit the files under `templates/`, and `SPEC.md` if the rationale changes.
2. Run `bin/diff.sh` to confirm what will change.
3. Run `bin/install.sh --apply`.
4. Commit and add a `CHANGELOG.md` entry.

Edits made directly under `~/.claude` are overwritten (after backup) by the next `--apply`, so sync them back first.

## Constraints

Full reasoning in [SPEC.md](SPEC.md).

- Do not set `CLAUDE_CODE_SUBAGENT_MODEL` anywhere. It overrides every agent's `model:` and flattens the tiers, including the advisor.
- Do not set `model` in any project settings file.
- Do not set the `agent` key in settings.
- Do not add hooks as part of this setup.
- Do not hard-block the orchestrator's Edit and Write tools. Enforcement is advisory and economic.
- Do not spawn `advisor` from a Fable session.

## Project layout

```
README.md
CHANGELOG.md
SPEC.md                            design rationale and constraints
templates/
  CLAUDE.orchestrator-section.md   the "## Orchestrator Mode" section
  agents/                          explorer, implementer, reviewer, advisor, orchestrator
  memory/                          memory notes and MEMORY.index-lines.md
bin/
  install.sh                       dry run by default; --apply to write
  audit.sh                         configuration audit
  diff.sh                          template vs live comparison
```

## Environment variables

| Variable         | Default      | Used by                | Purpose                                              |
|------------------|--------------|------------------------|------------------------------------------------------|
| `CLAUDE_HOME`    | `~/.claude`  | all scripts            | Claude Code config directory                         |
| `PROJECTS_ROOT`  | `~/Local`    | `audit.sh`, `install.sh` | Root searched for project settings files           |
| `PROJECTS_DEPTH` | `6`          | `audit.sh`             | `find -maxdepth` for the project settings search     |

Set `HOME` as well for a fully isolated sandbox run, since the shell rc check reads from it.
