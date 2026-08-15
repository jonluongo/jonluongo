# Specs

Live specs, in the order they apply. Superseded specs are moved to
`superseded/` so a reader can tell at a glance which documents are
authoritative.

**Read `2026-08-15-mcp-coaching-architecture-design.md` first.** It is the
current architecture and it revises every document below it. The app makes no
training decisions; Claude does, over MCP.

| Spec | Covers | Status |
|---|---|---|
| `2026-08-15-mcp-coaching-architecture-design.md` | Claude as the single decision-maker, the app as blocks + record + interface, snapshot-out/proposal-in, and the full list of what was deleted on 2026-08-15. **Read this first.** | Live — authoritative |
| `2026-08-14-foundation-architecture-design.md` | Layer boundaries, the exercise catalog as bundled reference data, units, and the CloudKit constraints on every model. | Live |
| `2026-08-14-catalog-enrichment-and-lifter-data.md` | Secondary muscles, difficulty, and the lifter data needed to prescribe starting loads. | Live |
| `2026-08-14-workout-programming-design.md` | Movement patterns over muscle groups, push/pull balance, sticky exercise selection. | **Reference only.** The training reasoning is sound and `assembly-rules.json` encodes it for Claude to read. But its "What this means for the existing code" section is dead: the app no longer assembles weeks, enforces balance, or rewrites `TemplatePlanBuilder` — that type is deleted. Treat it as material for the coach, not instructions for the app. |
| `2026-08-14-app-structure-revision.md` | The plan → week → day → exercise → set hierarchy. | **Partly superseded.** The hierarchy is live and correct. Its interface thesis — chat as the app shell, each plan as a Claude project inside the app — is not being built; the conversation happens in Claude. See "Recorded departure" in the MCP spec. |
| `superseded/2026-08-14-modern-minimal-design-system.md` | The pre-chat visual direction. | Superseded |
| `superseded/2026-08-14-retro-8bit-theme-design.md` | An abandoned art direction. | Superseded |

One rule survives every revision and every art direction: **the styling is a
skin, not a mechanic.** No points, streaks, badges, levels, or celebratory UI.
This is a training tool, not a game.

A second rule now joins it: **the app does not decide how anyone should train.**
If you are adding code that chooses exercises, sets, reps, rest, or load — or
that clamps, caps, or substitutes a prescribed value — you are working against
the architecture. See the MCP spec.
