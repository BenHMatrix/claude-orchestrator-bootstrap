---
name: orchestrator-project-overrides-audit
description: "Whenever the orchestrator system is touched, audit every project .claude/settings*.json for model or CLAUDE_CODE_SUBAGENT_MODEL overrides — ContentiQ was silently excluded for four months"
metadata:
  type: feedback
---

Project-level `.claude/settings.json` / `.claude/settings.local.json` override global settings. Any project file setting `"model"` or `env.CLAUDE_CODE_SUBAGENT_MODEL` silently removes that project from the orchestrator system: a model override stops the tier-keyed rules engaging, and the subagent env var overrides every agent's `model:` frontmatter, flattening the Haiku/Sonnet/Fable tiering and defeating the Fable `advisor` gate.

**Why:** ContentiQ (`~/Local/matrix/contentiq/contentiq/.claude/settings.json`, written 2026-06-27) carried `model: opus[1m]` and `CLAUDE_CODE_SUBAGENT_MODEL=haiku`. The 2026-08-20 orchestrator install was global-only and never looked at project files, so the flagship product ran outside the system until 2026-10-17, which the user considered a serious failure: it is the project that needs this approach the most. Fixed 2026-10-17 by removing both keys.

**How to apply:** Any time the orchestrator files are created, changed or audited, run the Step 4 find/grep from `~/.claude/orchestrator-setup-spec.md` across `~/Local` and the shell rc files, and expect zero hits. Never advise "leave that env var alone" for a project; remove it. Related: [[orchestrator-non-interference]].
