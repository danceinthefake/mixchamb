import { describe, it, expect, vi, afterEach } from "vitest"

const { pushEventMock } = vi.hoisted(() => ({
  pushEventMock: vi.fn(),
}))

vi.mock("live_vue", () => ({
  useLiveVue: () => ({ pushEvent: pushEventMock }),
}))

import { mount, enableAutoUnmount } from "@vue/test-utils"
import RetroBoard from "../activities/retro/RetroBoard.vue"

const flush = async () => {
  for (let i = 0; i < 4; i++) await Promise.resolve()
}
import type { RetroSession } from "../activities/retro/RetroBoard.vue"

enableAutoUnmount(afterEach)

function makeSession(overrides: Partial<RetroSession> = {}): RetroSession {
  return {
    id: "s1",
    title: null,
    status: "setup",
    voting_enabled: false,
    brainstorm_visible: false,
    team: null,
    columns: [
      { id: "c1", name: "Good", position: 0 },
      { id: "c2", name: "Bad", position: 1 },
      { id: "c3", name: "Start", position: 2 },
      { id: "c4", name: "Thanks", position: 3 },
    ],
    cards: [],
    action_items: [],
    ...overrides,
  }
}

const baseProps = {
  chamber_slug: "abc",
  session: null as RetroSession | null,
  tallies: {},
  my_votes: [],
  discussing_card_id: null,
  timer_deadline: null,
  discussed: [],
  participant_aliases: [],
  last_archived: null,
  previous_actions: [],
  current_user_id: "u1",
  current_user_alias: "host-alias",
  is_host: true,
}

describe("RetroBoard", () => {
  afterEach(() => {
    pushEventMock.mockReset()
  })

  it("shows 'Start retro' button for host with no session", () => {
    const w = mount(RetroBoard, { props: { ...baseProps, session: null } })
    const btn = w.get("button")
    expect(btn.text()).toBe("Start retro")
    btn.trigger("click")
    expect(pushEventMock).toHaveBeenCalledWith("retro_start_session", {})
  })

  it("shows 'Waiting for the host' message for non-host with no session", () => {
    const w = mount(RetroBoard, { props: { ...baseProps, session: null, is_host: false } })
    expect(w.text()).toContain("Waiting for the host")
  })

  it("renders RetroSetup during :setup phase", () => {
    const w = mount(RetroBoard, { props: { ...baseProps, session: makeSession() } })
    expect(w.text()).toContain("Column names")
  })

  it("renders 4 columns during :brainstorm", () => {
    const session = makeSession({ status: "brainstorm" })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    const columnHeaders = w.findAll("h2")
    // 1 header in main h1 + 4 column headers = 5; filter to column headers only
    const columnNames = columnHeaders.filter((h) =>
      ["Good", "Bad", "Start", "Thanks"].includes(h.text()),
    )
    expect(columnNames.length).toBe(4)
  })

  it("renders face-down placeholders for hidden cards during :brainstorm", () => {
    const session = makeSession({
      status: "brainstorm",
      cards: [
        {
          id: "card-mine",
          retro_column_id: "c1",
          body: "my card",
          author_user_id: "u1",
          author_alias: "me",
          vote_count: 0,
          reactions: [],
          comments: [],
        },
        {
          id: "card-theirs-1",
          retro_column_id: "c1",
          body: "their card 1",
          author_user_id: "u2",
          author_alias: "them",
          vote_count: 0,
          reactions: [],
          comments: [],
        },
        {
          id: "card-theirs-2",
          retro_column_id: "c1",
          body: "their card 2",
          author_user_id: "u3",
          author_alias: "other",
          vote_count: 0,
          reactions: [],
          comments: [],
        },
      ],
    })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    // 1 real card (mine) + 2 face-down silhouettes (theirs)
    const placeholders = w.findAll(
      "[aria-label='Hidden card from another participant — reveals together']",
    )
    expect(placeholders.length).toBe(2)
    expect(w.text()).toContain("my card")
    expect(w.text()).not.toContain("their card 1")
  })

  it("brainstorm_visible mode shows all cards live, no placeholders", () => {
    const session = makeSession({
      status: "brainstorm",
      brainstorm_visible: true,
      team: null,
      cards: [
        {
          id: "mine",
          retro_column_id: "c1",
          body: "my card",
          author_user_id: "u1",
          author_alias: "me",
          vote_count: 0,
          reactions: [],
          comments: [],
        },
        {
          id: "theirs",
          retro_column_id: "c1",
          body: "their card",
          author_user_id: "u2",
          author_alias: "them",
          vote_count: 0,
          reactions: [],
          comments: [],
        },
      ],
    })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    // Both cards visible (no per-author filter)
    expect(w.text()).toContain("my card")
    expect(w.text()).toContain("their card")
    // No face-down placeholders
    const placeholders = w.findAll(
      "[aria-label='Hidden card from another participant — reveals together']",
    )
    expect(placeholders.length).toBe(0)
  })

  it("no placeholders outside :brainstorm even when others have cards", () => {
    const session = makeSession({
      status: "reveal",
      cards: [
        {
          id: "card-theirs",
          retro_column_id: "c1",
          body: "their card",
          author_user_id: "u2",
          author_alias: "them",
          vote_count: 0,
          reactions: [],
          comments: [],
        },
      ],
    })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    const placeholders = w.findAll(
      "[aria-label='Hidden card from another participant — reveals together']",
    )
    expect(placeholders.length).toBe(0)
    // their card is now visible
    expect(w.text()).toContain("their card")
  })

  it("hides others' cards during :brainstorm but counts them", () => {
    const session = makeSession({
      status: "brainstorm",
      cards: [
        {
          id: "card-mine",
          retro_column_id: "c1",
          body: "my card",
          author_user_id: "u1",
          author_alias: "me",
          vote_count: 0,
          reactions: [],
          comments: [],
        },
        {
          id: "card-theirs",
          retro_column_id: "c1",
          body: "their card",
          author_user_id: "u2",
          author_alias: "them",
          vote_count: 0,
          reactions: [],
          comments: [],
        },
      ],
    })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    expect(w.text()).toContain("my card")
    expect(w.text()).not.toContain("their card")
    // Total count badge shows 2
    expect(w.html()).toContain(">2<")
  })

  it("shows all cards during :reveal", () => {
    const session = makeSession({
      status: "reveal",
      cards: [
        {
          id: "card-mine",
          retro_column_id: "c1",
          body: "my card",
          author_user_id: "u1",
          author_alias: "me",
          vote_count: 0,
          reactions: [],
          comments: [],
        },
        {
          id: "card-theirs",
          retro_column_id: "c1",
          body: "their card",
          author_user_id: "u2",
          author_alias: "them",
          vote_count: 0,
          reactions: [],
          comments: [],
        },
      ],
    })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    expect(w.text()).toContain("my card")
    expect(w.text()).toContain("their card")
  })

  it("renders RetroVotingPanel during :voting", () => {
    const session = makeSession({ status: "voting", voting_enabled: true })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    expect(w.text()).toContain("0/3 votes spent")
  })

  it("renders RetroDiscussPanel during :discuss", () => {
    const session = makeSession({ status: "discuss" })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    // Header is now "Freeform action items" — actions tied to a
    // card render nested under the card itself (spec §6).
    expect(w.text().toLowerCase()).toContain("freeform action items")
  })

  it("provides participant_aliases as a datalist source during :discuss", () => {
    const session = makeSession({ status: "discuss" })
    const w = mount(RetroBoard, {
      props: {
        ...baseProps,
        session,
        participant_aliases: ["alex", "Brave Otter 12", "kim"],
      },
    })
    // The freeform assignee input + the datalist with options
    const datalist = w.find("datalist#retro-add-assignees")
    expect(datalist.exists()).toBe(true)
    const options = datalist.findAll("option").map((o) => o.attributes("value"))
    expect(options).toEqual(["alex", "Brave Otter 12", "kim"])
  })

  it("stepper highlights the current phase + checks past ones", () => {
    const session = makeSession({ status: "voting", voting_enabled: true })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    // All six step labels appear
    for (const label of ["Setup", "Brainstorm", "Reveal", "Voting", "Discuss", "Archived"]) {
      expect(w.text()).toContain(label)
    }
    // Done steps before voting render the checkmark
    expect(w.text()).toContain("✓")
  })

  it("stepper de-emphasises voting step when voting disabled", () => {
    const session = makeSession({ status: "discuss", voting_enabled: false })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    const html = w.html()
    // Voting step should still appear but with the line-through opacity class
    expect(html).toContain("Voting")
    expect(html).toContain("line-through")
  })

  it("Copy share link appears in empty state when last_archived is present", () => {
    const w = mount(RetroBoard, {
      props: {
        ...baseProps,
        session: null,
        last_archived: { id: "past-1", title: "Sprint 23", archived_at: null },
      },
    })
    expect(w.text()).toContain("Last retro archived: Sprint 23")
    expect(w.text()).toContain("Copy share link")
  })

  it("no Copy share link when nothing has been archived", () => {
    const w = mount(RetroBoard, {
      props: { ...baseProps, session: null, last_archived: null },
    })
    expect(w.text()).not.toContain("Copy share link")
  })

  it("sorts cards by vote_count desc in :discuss", () => {
    const session = makeSession({
      status: "discuss",
      cards: [
        {
          id: "low",
          retro_column_id: "c1",
          body: "low priority",
          author_user_id: "u1",
          author_alias: "me",
          vote_count: 1,
          reactions: [],
          comments: [],
        },
        {
          id: "high",
          retro_column_id: "c1",
          body: "high priority",
          author_user_id: "u1",
          author_alias: "me",
          vote_count: 5,
          reactions: [],
          comments: [],
        },
      ],
    })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    const html = w.html()
    expect(html.indexOf("high priority")).toBeLessThan(html.indexOf("low priority"))
  })

  describe("archived banner + clipboard", () => {
    const card = (id: string, col: string, body: string, vote_count: number) => ({
      id,
      retro_column_id: col,
      body,
      author_user_id: "u1",
      author_alias: "ana",
      author_display_name: null,
      vote_count,
      reactions: [],
      comments: [],
    })
    const archived = makeSession({
      status: "archived",
      team: { slug: "core", name: "Core" },
      cards: [
        card("k1", "c1", "low", 1),
        card("k2", "c1", "high", 4),
        card("k3", "ghost", "orphan", 0),
      ],
      action_items: [
        {
          id: "a1",
          source_card_id: "k2",
          body: "tied",
          assignee_alias: null,
          due_date: null,
          completed: false,
        },
        {
          id: "a2",
          source_card_id: null,
          body: "free",
          assignee_alias: null,
          due_date: null,
          completed: true,
        },
      ],
    })

    it("copies the permalink and the markdown snapshot, with separate flashes", async () => {
      vi.useFakeTimers()
      const writeText = vi.fn().mockResolvedValue(undefined)
      Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText } })
      const w = mount(RetroBoard, { props: { ...baseProps, session: archived } })
      expect(w.text()).toContain("Filed under")

      const btn = (re: RegExp) => w.findAll("button").find((b) => re.test(b.text()))!
      await btn(/Copy share link/).trigger("click")
      await flush()
      expect(writeText).toHaveBeenCalledWith(expect.stringContaining("/archives/retros/s1"))
      expect(btn(/Copied!/).exists()).toBe(true)

      await btn(/Copy as markdown/).trigger("click")
      await flush()
      expect(writeText.mock.calls[1][0]).toContain("# ")
      expect(writeText.mock.calls[1][0]).toContain("Team: Core")
      vi.advanceTimersByTime(1600)
      await w.vm.$nextTick()
      expect(w.findAll("button").filter((b) => /Copied!/.test(b.text()))).toHaveLength(0)

      // Clipboard blocked → silent, no flash.
      writeText.mockRejectedValueOnce(new Error("blocked"))
      await btn(/Copy share link/).trigger("click")
      await flush()
      expect(w.findAll("button").filter((b) => /Copied!/.test(b.text()))).toHaveLength(0)
      writeText.mockRejectedValueOnce(new Error("blocked"))
      await btn(/Copy as markdown/).trigger("click")
      await flush()
      vi.useRealTimers()
    })

    it("empty-state share link copies the last archived permalink", async () => {
      const writeText = vi.fn().mockResolvedValue(undefined)
      Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText } })
      const w = mount(RetroBoard, {
        props: {
          ...baseProps,
          session: null,
          last_archived: { id: "past-9", title: null, archived_at: null },
        },
      })
      await w
        .findAll("button")
        .find((b) => /Copy share link/.test(b.text()))!
        .trigger("click")
      await flush()
      expect(writeText).toHaveBeenCalledWith(expect.stringContaining("/archives/retros/past-9"))
    })

    it("sorts cards by votes in :archived and tolerates cards in unknown columns", () => {
      const w = mount(RetroBoard, { props: { ...baseProps, session: archived } })
      const bodies = w.findAll("[data-card-body], .break-words").map((n) => n.text())
      expect(bodies.indexOf("high")).toBeLessThan(bodies.indexOf("low"))
    })
  })
})
