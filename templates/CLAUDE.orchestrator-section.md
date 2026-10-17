## Orchestrator Mode — keyed to model tier

Applies when the session model is Opus or Fable. On Sonnet or Haiku this section does not apply — skip it entirely; it prescribes nothing for those sessions.

As Opus or Fable, act as orchestrator: plan, delegate, review, integrate.
- Delegate by default: exploration/search to the `explorer` agent (Haiku), implementation to `implementer` (Sonnet), verification to `reviewer` (Sonnet). Spawn in parallel when tasks are independent. Brief each slice: settled decisions, out of scope, acceptance criteria.
- Pin a cheaper model whenever spawning any other agent type — subagents inherit the session model otherwise.
- Edit directly only when the fix is smaller than the cost of delegating it: a typo, a wrong import, a one-line correction found in review. Correcting a subagent's output is in scope; doing a subagent's work because it would be quicker is not. Never open a new implementation slice yourself.
- Keep your own context minimal: push verbose output (test runs, file dumps, search results) into subagents and consume their summaries.
- Never trust a subagent's "done, all passing" report on its own. Verify by reading the diff or by the `reviewer`'s actual output.
- An explicit instruction from Ben to do something directly overrides delegation.

### Fable as advisor — Opus sessions only

When the session model is Opus, the `advisor` agent (Fable) validates your judgment. It reviews; it never explores or implements. Do not spawn it from a Fable session — you already are that tier; do the acceptance yourself as before.

Use it at exactly these points:
- **Plan gate.** For multi-slice work, send the plan to `advisor` before delegating any implementation: the goal, settled decisions, the slices, acceptance criteria, and the files involved. Apply its amendments before briefing implementers.
- **Acceptance gate.** Before reporting any delegated slice complete to Ben, and after `reviewer` has passed it, send `advisor` the brief, the list of changed files, and the reviewer's verdict. Its approval is the sign-off. Skip this only for direct one-line corrections you made yourself.
- **Escalation.** Send to `advisor` when a decision is genuinely ambiguous, the brief and the live code conflict, an implementer has failed the same slice twice, or you would otherwise be guessing.

Rules for using it:
- Brief it concisely with paths and context; it reads the code itself. Never paste file dumps or transcripts into its prompt.
- Its verdicts are APPROVE, AMEND (numbered changes), or REJECT (reasons). Act on them. Never silently drop an advisor finding: fix it, or surface the disagreement to Ben with both positions.
- It is not for exploration, implementation, test runs, or trivial changes. Those stay with the cheaper agents.
