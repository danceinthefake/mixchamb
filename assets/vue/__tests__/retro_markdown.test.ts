import { describe, it, expect } from "vitest"
import { retroToMarkdown } from "../activities/retro/markdown"
import type { RetroSession } from "../activities/retro/RetroBoard.vue"

const session: RetroSession = {
  id: "s1",
  title: "Sprint 23",
  status: "archived",
  voting_enabled: true,
  brainstorm_visible: false,
  team: { slug: "payments", name: "Payments" },
  columns: [
    { id: "c1", name: "Good", position: 0 },
    { id: "c2", name: "Bad", position: 1 },
  ],
  cards: [
    {
      id: "k1",
      retro_column_id: "c2",
      body: "CI is slow",
      author_user_id: "u1",
      author_alias: "ana",
      author_display_name: null,
      vote_count: 3,
      reactions: [],
      comments: [],
    },
    {
      id: "k2",
      retro_column_id: "c2",
      body: "Flaky test",
      author_user_id: "u2",
      author_alias: "bo",
      author_display_name: null,
      vote_count: 5,
      reactions: [],
      comments: [],
    },
  ],
  action_items: [
    {
      id: "a1",
      source_card_id: "k2",
      body: "Quarantine it",
      assignee_alias: "bo",
      due_date: "2026-10-01",
      completed: false,
    },
    {
      id: "a2",
      source_card_id: null,
      body: "Pair more",
      assignee_alias: null,
      due_date: null,
      completed: true,
    },
  ],
}

describe("retroToMarkdown", () => {
  it("renders columns (votes desc), nested + freeform actions, footer", () => {
    expect(retroToMarkdown(session, "https://x/archives/retros/s1")).toBe(
      [
        "# Sprint 23",
        "",
        "## Good",
        "_(no cards)_",
        "",
        "## Bad",
        "- Flaky test _(5 votes)_ — bo",
        "  - [ ] Quarantine it — @bo _(by 2026-10-01)_",
        "- CI is slow _(3 votes)_ — ana",
        "",
        "## Action items",
        "- [x] Pair more",
        "",
        "Team: Payments · https://x/archives/retros/s1",
        "",
      ].join("\n"),
    )
  })

  it("omits the footer without team or permalink", () => {
    const md = retroToMarkdown({ ...session, team: null, action_items: [] })
    expect(md.endsWith("- CI is slow _(3 votes)_ — ana\n")).toBe(true)
  })
})
