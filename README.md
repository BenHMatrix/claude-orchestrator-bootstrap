# claude-orchestrator-bootstrap

The reinstallable source for my Claude Code "orchestrator pattern". It installs the global rules, agent profiles, memory notes and one settings key on a fresh machine, upgrades a machine still on the v1 pattern, and audits a machine for drift or for anything that silently undoes the pattern.

## The pattern

- Opus or Fable sessions act as orchestrator: plan, delegate, review, integrate. Legwork goes to pinned subagents: `explorer` on Haiku, `implementer` on Sonnet, `reviewer` on Sonnet.
- On Opus sessions only, the `advisor` agent (pinned to Fable) is used at three gates: plan gate (multi-slice work, before implementation), acceptance gate (each delegated slice, after the reviewer passes), and escalation (ambiguity, brief-versus-code conflict, a slice that failed twice). Fable sessions do their own acceptance and never spawn the advisor.
- Sonnet and Haiku sessions are left uninstructed. The rules say nothing about them.
- `/model` is the mode switch. `settings.json` sets `"model": "opus"` as the default; `/model fable` switches a session to Fable-as-orchestrator.
- `orchestrator.md` is a reserve main-thread profile (`model: inherit`). It is installed but not activated.

The installer owns exactly one settings key (`model`). It never copies your `settings.json`, which holds permissions and tokens.

## Repo layout

```
README.md  CHANGELOG.md
SPEC.md                          design rationale and constraints
templates/
  CLAUDE.orchestrator-section.md   the "## Orchestrator Mode" section only
  agents/                          explorer implementer reviewer advisor orchestrator
  memory/                          two memory notes + MEMORY.index-lines.md
bin/
  install.sh                       dry run by default, --apply to change things
  audit.sh                         checks for anything that undermines the pattern
  diff.sh                          template vs live comparison
```

All three scripts honour `CLAUDE_HOME` (default `~/.claude`) and `PROJECTS_ROOT` (default `~/Local`), so you can point them at a sandbox. `audit.sh` also honours `PROJECTS_DEPTH` (the `find -maxdepth` for project settings files, default 6). The shell rc check reads from `$HOME`, so a fully isolated sandbox run should set `HOME` too.

## Fresh machine install

```
git clone <this repo> ~/Local/matrix/claude-orchestrator-bootstrap
cd ~/Local/matrix/claude-orchestrator-bootstrap
bin/install.sh            # preview: unchanged / would create / would update
bin/install.sh --apply    # do it
```

Then open a new Claude Code session. Existing sessions do not pick up the changes.

## Upgrading a machine with v1

Same commands. The installer:

- Replaces the five agent files and the spec.
- Moves the `## Orchestrator Mode` section of `~/.claude/CLAUDE.md` to the top of the file, because the rules are meant to be front-loaded. The old section runs from its heading to the next `# ` or `## ` heading (or the end of the file); it is cut out wherever it was and the template section is put first, followed by one blank line. If there was no such section, the template is simply prepended.
- Preserves all other `CLAUDE.md` content byte for byte, except that blank lines at the cut are collapsed to at most one.
- Sets `"model": "opus"` in `settings.json` after backing it up. The file is re-serialised with 2-space indentation and the original key order, so formatting may change even though only `model` is edited (if `model` is already `opus` the file is left alone). It never touches `env` or `agent`; if it finds `CLAUDE_CODE_SUBAGENT_MODEL` or an `agent` key it prints a warning and leaves it for you to decide.
- Before writing anything, it checks that an existing `settings.json` is valid JSON and stops with an error (exit 1) if not.
- Adds the two memory notes and appends missing lines to `MEMORY.md`. Existing lines are left alone.

Every file it is about to change is first copied to `~/.claude/backups/orchestrator-<timestamp>/`. Running `--apply` twice is safe: the second run reports everything unchanged.

## Auditing

```
bin/audit.sh
```

It checks that global settings have no `agent` key or `CLAUDE_CODE_SUBAGENT_MODEL`; that no project `.claude/settings.json` or `settings.local.json` under `PROJECTS_ROOT` sets `model`, `agent` or `CLAUDE_CODE_SUBAGENT_MODEL`; that no shell rc file mentions `CLAUDE_CODE_SUBAGENT_MODEL`; that the five agents have the right `model:` values; and that `CLAUDE.md` starts with the orchestrator section. Exit 1 on any failure. The project check prints its root and depth (`PROJECTS_ROOT`, `PROJECTS_DEPTH`). `install.sh` runs it at the end.

Project overrides matter because project settings beat global ones. ContentiQ was silently excluded from the pattern from June to October 2026 by a pre-existing project settings file that forced Opus and flattened every subagent to Haiku.

`bin/diff.sh` is the drift check between this repo and `~/.claude`. It shows template on the left and live on the right. If the templates are newer, run `bin/install.sh --apply`. If the live files are newer, copy the edits back into `templates/` and commit.

## Changing the pattern

1. Edit the files in `templates/` (and `SPEC.md` if the rationale changes).
2. Run `bin/diff.sh` to see what differs from the live setup.
3. Run `bin/install.sh --apply`.
4. Commit, and add a `CHANGELOG.md` entry.

Never edit the copies in `~/.claude` directly without syncing the change back here. The next `--apply` would overwrite it (after a backup).

## Constraints

Full reasoning is in `SPEC.md`. In short:

- No `CLAUDE_CODE_SUBAGENT_MODEL` anywhere: it overrides every agent's `model:` and flattens the tiers, including the Fable advisor.
- No `model` override in any project settings file.
- No `agent` key in settings.
- No hooks as part of this setup.
- Never hard-block the orchestrator's Edit/Write; enforcement is advisory and economic.
- Never spawn `advisor` from a Fable session.
