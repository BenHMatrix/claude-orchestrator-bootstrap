---
name: orchestrator-non-interference
description: "The orchestrator setup instructs Opus and Fable sessions only — never prescribe behavior for Sonnet or Haiku sessions"
metadata:
  type: feedback
---

The orchestrator system (`~/.claude/agents/` + orchestrator section in `~/.claude/CLAUDE.md`, spec at `~/.claude/orchestrator-setup-spec.md`) instructs Opus and Fable sessions to delegate. Sonnet and Haiku sessions must be left entirely uninstructed — not even told to "work hands-on as normal".

**Why:** The user's stated intent (2026-08-20): "We shouldn't be telling sub-Fable agents to work one way or another, we shouldn't be interfering." On 2026-10-17 the user widened the orchestrator tier to include Opus 5.5 as his new default, with Fable acting as `advisor` (plan gate, acceptance gate, escalation) for Opus sessions. Stock Claude Code behavior on Sonnet/Haiku is the baseline; a Sonnet session delegating exploration to the Haiku-pinned `explorer` on its own is fine (built-in behavior), not drift.

**How to apply:** When editing the orchestrator CLAUDE.md section or the setup spec, keep the scope condition pure ("applies on Opus or Fable; otherwise skip") and never add behavioral guidance for Sonnet/Haiku. Never spawn `advisor` from a Fable session. The only drift signal worth acting on is a Sonnet/Haiku session following orchestrator *policy* (e.g. writing briefs and delegating implementation to `implementer`). See [[orchestrator-project-overrides-audit]] for the project-settings trap.
