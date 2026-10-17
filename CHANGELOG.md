# Changelog

## v2 - 2026-10-17

- Opus added as an orchestrator tier and made the default model.
- New `advisor` agent (pinned to Fable) with three gates: plan, acceptance, escalation.
- `orchestrator` reserve profile switched from `model: fable` to `model: inherit`.
- Project-override audit added, after ContentiQ was found excluded from the pattern by a pre-existing project settings file.
- Spec rewritten (`SPEC.md`).

## v1 - 2026-08-20

- Fable-only orchestrator.
- `explorer`, `implementer`, `reviewer` worker agents.
- Reserve `orchestrator` profile pinned to `fable`.
