# Setup Spec: Orchestrator System for Claude Code (v2, October 2026)

**Audience:** a Claude Code session on a fresh machine, or a session asked to repair or audit the orchestrator setup on this one. Follow this spec exactly. The *Constraints* section explains why several tempting alternatives are known to be wrong. Supersedes the August 2026 v1 spec (Fable-only orchestrator).

## Objective

Every Claude Code session on this machine follows one rule, keyed to model tier:

- **Opus and Fable sessions act as orchestrator** — plan, delegate, review, integrate. Legwork goes to cheaper pinned subagents (`explorer` on Haiku, `implementer` and `reviewer` on Sonnet).
- **Opus sessions additionally use Fable as advisor** via the `advisor` agent (pinned to Fable) at three points: plan gate, acceptance gate, escalation. Fable sessions do not spawn the advisor; they do the acceptance themselves.
- **Sonnet and Haiku sessions are left uninstructed.** The orchestrator rules do not apply to them and the setup prescribes nothing for them. Choosing a model per session (`/model`) is the mode switch.
- The orchestrator is **never hard-blocked** from Edit/Write. Enforcement is advisory + economic, not tool removal.
- **No project may silently opt out.** Project-level `.claude/settings.json` files must not set a `model` override or `CLAUDE_CODE_SUBAGENT_MODEL`; either one breaks the design for that project (see Step 4 and Constraints).

## Step 1 — Create the worker agents

Create `~/.claude/agents/` if it does not exist. If any of these files already exists, STOP and show the user the existing content instead of overwriting. The live copies on this machine are the source of truth; a fresh machine gets them from here.

`~/.claude/agents/explorer.md`:

```markdown
---
name: explorer
description: Fast, cheap codebase and documentation exploration — searching files, mapping structure, reading and summarizing code, looking up docs. Use for any read-only investigation before planning or implementing.
tools: Read, Grep, Glob, WebFetch, WebSearch
model: haiku
---

You are a codebase scout. You find and summarize; you never modify anything.

- Answer the specific question asked; do not expand scope.
- Prefer targeted searches (Grep, Glob) over reading files end to end.
- Return findings as compact, structured summaries with exact file paths and line numbers — never dump whole files back.
- State clearly when something was NOT found; absence is a finding, not a failure.
- If the question is ambiguous, answer the most likely interpretation and note the ambiguity in one line.
```

`~/.claude/agents/implementer.md`:

```markdown
---
name: implementer
description: Implements a well-defined slice of work — writing and editing code to a written brief. Use once a plan exists; give it settled decisions, scope boundaries, and acceptance criteria.
tools: Read, Grep, Glob, Edit, Write, Bash
model: sonnet
---

You are an implementer. You receive a brief and deliver that slice, nothing more.

- Treat the brief's settled decisions as fixed; do not relitigate them.
- Stay inside scope: if the brief marks something out of scope or deferred, leave it alone even if you see an improvement — note it in your report instead.
- Before writing, read any project conventions files the brief names (e.g. CLAUDE.md, TEMPLATING.md, MDS-AI-REFERENCE.md in Craft projects) and match the surrounding code's style, naming, and comment density.
- If the brief is ambiguous or contradicts the code you find, stop and report the conflict instead of guessing.
- Report back: what changed (files with line references), what you verified and how, and anything you noticed but deliberately left alone.
```

`~/.claude/agents/reviewer.md`:

```markdown
---
name: reviewer
description: Verifies a completed slice of work against its brief — runs builds/tests, checks the diff for correctness, scope creep, and regressions. Use before reporting any slice complete.
tools: Read, Grep, Glob, Bash
model: sonnet
---

You are a verifier. You check work against its brief; you never fix anything yourself.

- Run the project's build/tests where available and report actual output, never assumptions.
- Check the changes for: correctness against the brief, unintended edits outside scope, and regressions in adjacent code.
- Return a verdict: pass, or a concrete list of defects with file:line references and what the brief required. Never soften a failure.
- If you could not verify something (no test coverage, build unavailable), say so explicitly rather than passing it silently.
```

`~/.claude/agents/advisor.md` — copy verbatim from the live file on this machine. Its frontmatter is `tools: Read, Grep, Glob, Bash` and `model: fable`. Its body defines the three review modes (plan, acceptance, escalation) and the mandatory closing line `VERDICT: APPROVE | AMEND | REJECT`.

`~/.claude/agents/orchestrator.md` — RESERVE profile, `model: inherit`, `tools: Agent(explorer, implementer, reviewer, advisor), Read, Grep, Glob, Edit, Write, Bash, TodoWrite`. Create it from the live file but do NOT activate it in any settings file (see Constraints).

## Step 2 — Add the orchestrator rules to the global CLAUDE.md

Edit `~/.claude/CLAUDE.md`. The "Orchestrator Mode — keyed to model tier" section must be at the very TOP of the file. Copy it verbatim from the live file on this machine. Its load-bearing properties:

- Scope line: applies on Opus or Fable; prescribes nothing for Sonnet or Haiku.
- Delegation defaults to `explorer`/`implementer`/`reviewer`; pin a cheaper model on any other agent type.
- Direct edits only for corrections smaller than a delegation round-trip; never open an implementation slice yourself.
- Never trust a subagent's self-report; verify by diff or reviewer output.
- Subsection "Fable as advisor — Opus sessions only": plan gate (multi-slice work, before implementation), acceptance gate (every delegated slice, after reviewer passes, before reporting to Ben), escalation (ambiguity, brief-vs-code conflict, twice-failed slice). Never spawn advisor from a Fable session. Never silently drop an advisor finding.
- Ben's explicit instruction to do something directly overrides delegation.

## Step 3 — Set the default model

In `~/.claude/settings.json`, set `"model": "opus"`. Opus is the default orchestrator tier; `/model fable` switches a session to the Fable-as-orchestrator mode.

## Step 4 — Audit project-level overrides (mandatory, every time this system is touched)

Project settings override global settings. A project `.claude/settings.json` or `.claude/settings.local.json` that sets `model` or `env.CLAUDE_CODE_SUBAGENT_MODEL` silently removes that project from this system. This is exactly what happened to ContentiQ between June and October 2026: a pre-existing project file forced Opus and flattened every subagent to Haiku, and the August install did not look.

Run:

```
find ~/Local -maxdepth 5 -path '*/.claude/settings*.json' -not -path '*/node_modules/*' -not -path '*/vendor/*' \
  | xargs grep -lE '"model"|CLAUDE_CODE_SUBAGENT_MODEL|"agent"'
```

Expected result: no hits. Any hit must be removed (or explicitly justified to Ben). Also check `~/.zshrc`, `~/.zprofile`, `~/.zshenv` for `CLAUDE_CODE_SUBAGENT_MODEL`.

## Step 5 — Verify

1. Confirm the five agent files exist and the CLAUDE.md section is at the top.
2. Confirm Step 4 returns no hits.
3. Tell the user to open a **new** session (existing sessions do not pick up changes). On Opus, a small multi-slice task should: reach for `explorer` first, send the plan to `advisor`, delegate to `implementer`, verify with `reviewer`, then send the slice to `advisor` for acceptance before reporting. On Fable: the same without the advisor. On Sonnet: stock Claude Code behavior; it picking the Haiku-pinned `explorer` on its own is fine, only routinely following orchestrator *policy* (writing briefs for `implementer`) would be drift.
4. Report completion with the list of files created/modified. Do not run paid test sessions yourself.

## Constraints — do NOT deviate

1. **Do NOT set `CLAUDE_CODE_SUBAGENT_MODEL`** anywhere (global settings `env`, project settings, shell rc). Its position in model resolution (env var → per-call → frontmatter → inherit) means it overrides per-agent `model:` frontmatter, flattening the Haiku/Sonnet/Fable tiering this design depends on. It would also force the Fable-pinned `advisor` down to whatever the env var says, silently defeating the advisor gate.
2. **Do NOT set `model` in any project settings file.** The session tier is a per-user, per-session choice (`/model`), not a per-project constant. A project override hides a project from the orchestrator rules.
3. **Do NOT remove Edit/Write/Bash from the orchestrator.** Ben has explicitly rejected hard-blocking.
4. **Do NOT add PreToolUse/UserPromptSubmit hooks** as part of this setup. Held in reserve for observed drift. If ever added: settings-file hooks also fire inside subagents (payload carries `agent_id`/`agent_type`), and exit-2 block messages are not fed back to Claude; prefer non-blocking `additionalContext` nudges.
5. **Do NOT set the `agent` key in any settings file** as part of this setup. It replaces the default system prompt for the main thread; held in reserve per project.
6. **Do NOT spawn `advisor` from a Fable session.** Same tier reviewing itself is pure cost.
7. Subagent `model:` values known valid: `haiku`, `sonnet`, `opus`, `fable`, `inherit`. The `tools: Agent(name, name)` allowlist syntax restricts which subagent types can be spawned.

## Background

Subagents default to inheriting the parent model, so unpinned delegation bills at the session tier; pinning `model:` in frontmatter is the deterministic half of this design. The CLAUDE.md rules are the advisory half: context, not enforcement, which preserves mid-session judgment and conversational override. The advisor pattern puts the strongest model at the points of highest leverage per token (design critique and final acceptance) rather than on legwork, which is the standard cost-efficient shape for a mixed-tier agent team. Keying the rules to model tier makes `/model` the per-session mode switch.

## Files that make up this system (update all of them together)

- `~/.claude/CLAUDE.md` — live policy
- `~/.claude/agents/{explorer,implementer,reviewer,advisor,orchestrator}.md`
- `~/.claude/orchestrator-setup-spec.md` — this file
- `~/.claude/settings.json` — `model` key
- `~/.claude/projects/-Users-ben/memory/orchestrator-non-interference.md`, `orchestrator-project-overrides-audit.md`, `orchestrator-bootstrap-repo.md`
- Any project `.claude/settings*.json` found by Step 4

**Canonical source:** the git repo `~/Local/matrix/claude-orchestrator-bootstrap/` holds templates of every file above plus `bin/install.sh`, `bin/audit.sh` and `bin/diff.sh`. Edit there, run `bin/install.sh --apply`, commit. Do not hand-edit the `~/.claude` copies without syncing back.
