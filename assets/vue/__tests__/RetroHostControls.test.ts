import { describe, it, expect, vi, afterEach } from "vitest"

const { pushEventMock, confirmMock } = vi.hoisted(() => ({
  pushEventMock: vi.fn(),
  confirmMock: vi.fn(() => true),
}))

vi.mock("live_vue", () => ({
  useLiveVue: () => ({ pushEvent: pushEventMock }),
}))

vi.stubGlobal("confirm", confirmMock)

import { mount, enableAutoUnmount } from "@vue/test-utils"
import RetroHostControls from "../activities/retro/RetroHostControls.vue"
import type { RetroSession } from "../activities/retro/RetroBoard.vue"

enableAutoUnmount(afterEach)

function session(
  status: RetroSession["status"],
  voting_enabled = false,
  cardCount = 0,
): RetroSession {
  return {
    id: "s1",
    title: null,
    status,
    voting_enabled,
    columns: [],
    cards: Array.from({ length: cardCount }, (_, i) => ({
      id: `c${i}`,
      retro_column_id: "col1",
      body: `card ${i}`,
      author_user_id: "u1",
      author_alias: "a",
      vote_count: 0,
    })),
    action_items: [],
  }
}

describe("RetroHostControls", () => {
  afterEach(() => {
    pushEventMock.mockReset()
    confirmMock.mockReset()
    confirmMock.mockImplementation(() => true)
  })

  it("renders nothing if not host", () => {
    const w = mount(RetroHostControls, {
      props: { session: session("setup"), is_host: false },
    })
    expect(w.find("footer").exists()).toBe(false)
  })

  it("advance label per phase", () => {
    const cases: Array<[RetroSession["status"], boolean, string]> = [
      ["setup", false, "Start brainstorm"],
      ["brainstorm", false, "Reveal cards"],
      ["reveal", false, "Start discussion"],
      ["reveal", true, "Start voting"],
      ["voting", true, "Start discussion"],
      ["discuss", false, "Archive retro"],
    ]
    for (const [status, voting, label] of cases) {
      const w = mount(RetroHostControls, {
        props: { session: session(status, voting), is_host: true },
      })
      expect(w.text()).toContain(label)
    }
  })

  it("no advance button when :archived", () => {
    const w = mount(RetroHostControls, {
      props: { session: session("archived"), is_host: true },
    })
    expect(w.findAll("button").length).toBe(0)
  })

  it("archive transition asks for confirmation", async () => {
    const w = mount(RetroHostControls, {
      props: { session: session("discuss"), is_host: true },
    })
    await w.get("button").trigger("click")
    expect(confirmMock).toHaveBeenCalled()
    expect(pushEventMock).toHaveBeenCalledWith("retro_advance_phase", {})
  })

  it("declined confirm does not advance", async () => {
    confirmMock.mockImplementation(() => false)
    const w = mount(RetroHostControls, {
      props: { session: session("discuss"), is_host: true },
    })
    await w.get("button").trigger("click")
    expect(pushEventMock).not.toHaveBeenCalled()
  })

  it("voting toggle visible :setup through :voting, hidden after", () => {
    for (const phase of ["setup", "brainstorm", "reveal", "voting"] as const) {
      const w = mount(RetroHostControls, {
        props: { session: session(phase), is_host: true },
      })
      expect(w.find("input[type='checkbox']").exists()).toBe(true)
    }
    for (const phase of ["discuss", "archived"] as const) {
      const w = mount(RetroHostControls, {
        props: { session: session(phase), is_host: true },
      })
      expect(w.find("input[type='checkbox']").exists()).toBe(false)
    }
  })

  it("toggling voting pushes retro_set_voting_enabled with negation", async () => {
    const w = mount(RetroHostControls, {
      props: { session: session("setup", false), is_host: true },
    })
    await w.get("input[type='checkbox']").trigger("change")
    expect(pushEventMock).toHaveBeenCalledWith("retro_set_voting_enabled", { enabled: true })
  })

  describe("voting threshold hint", () => {
    it("hidden below the threshold", () => {
      const w = mount(RetroHostControls, {
        props: { session: session("brainstorm", false, 14), is_host: true },
      })
      expect(w.text()).not.toContain("voting helps")
    })

    it("shown at or above the threshold when voting is off", () => {
      const w = mount(RetroHostControls, {
        props: { session: session("brainstorm", false, 15), is_host: true },
      })
      expect(w.text()).toContain("15 cards")
      expect(w.text()).toContain("voting helps")
    })

    it("hidden once voting is already enabled", () => {
      const w = mount(RetroHostControls, {
        props: { session: session("brainstorm", true, 20), is_host: true },
      })
      expect(w.text()).not.toContain("voting helps")
    })

    it("hidden once past :voting (no longer toggleable)", () => {
      const w = mount(RetroHostControls, {
        props: { session: session("discuss", false, 20), is_host: true },
      })
      expect(w.text()).not.toContain("voting helps")
    })
  })
})
