import { describe, it, expect, vi, beforeEach } from "vitest"
import { mount } from "@vue/test-utils"
import RetroSetup from "../activities/retro/RetroSetup.vue"
import { COLUMN_PRESETS } from "../activities/retro/presets"
import type { RetroSession } from "../activities/retro/RetroBoard.vue"

const pushEvent = vi.fn()
vi.mock("live_vue", () => ({ useLiveVue: () => ({ pushEvent }) }))

const session: RetroSession = {
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
}

beforeEach(() => pushEvent.mockClear())

describe("RetroSetup", () => {
  it("every preset has exactly four names", () => {
    for (const names of Object.values(COLUMN_PRESETS)) expect(names).toHaveLength(4)
  })

  it("applying a preset renames only the columns that differ", async () => {
    const w = mount(RetroSetup, { props: { session, is_host: true } })
    await w.get("#retro-column-preset").setValue("Start / Stop / Continue / Kudos")

    expect(pushEvent).toHaveBeenCalledTimes(4)
    expect(pushEvent).toHaveBeenCalledWith("retro_rename_column", {
      column_id: "c1",
      name: "Start",
    })
    expect(pushEvent).toHaveBeenCalledWith("retro_rename_column", {
      column_id: "c4",
      name: "Kudos",
    })

    pushEvent.mockClear()
    await w.get("#retro-column-preset").setValue("Good / Bad / Start / Thanks")
    // Compared against the server's names (still the defaults until
    // the broadcast lands), so nothing to send.
    expect(pushEvent).toHaveBeenCalledTimes(0)
  })

  it("team input pushes retro_set_team on enter", async () => {
    const w = mount(RetroSetup, { props: { session, is_host: true } })
    await w.get("#retro-team").setValue("Payments")
    await w.get("#retro-team").trigger("keydown.enter")
    expect(pushEvent).toHaveBeenCalledWith("retro_set_team", { team: "Payments" })
  })

  it("title + column edits commit only real changes; blank column restores", async () => {
    const w = mount(RetroSetup, { props: { session, is_host: true } })
    const title = w.get("#retro-title")
    await title.setValue("Sprint 5")
    await title.trigger("blur")
    expect(pushEvent).toHaveBeenCalledWith("retro_set_title", { title: "Sprint 5" })
    pushEvent.mockClear()
    await title.setValue("  ")
    await title.trigger("blur")
    expect(pushEvent).not.toHaveBeenCalled()

    const cols = w.findAll('input[aria-label^="Rename column"]')
    await cols[0].setValue("Wins")
    await cols[0].trigger("keydown.enter")
    expect(pushEvent).toHaveBeenCalledWith("retro_rename_column", { column_id: "c1", name: "Wins" })
    pushEvent.mockClear()
    await cols[1].setValue("   ")
    await cols[1].trigger("blur")
    expect(pushEvent).not.toHaveBeenCalled()
    expect((cols[1].element as HTMLInputElement).value).toBe("Bad")
    await cols[2].setValue("Start")
    await cols[2].trigger("blur")
    expect(pushEvent).not.toHaveBeenCalled()

    // Same team name → no event; toggle brainstorm visibility.
    await w.get("#retro-team").setValue("")
    await w.get("#retro-team").trigger("blur")
    expect(pushEvent).not.toHaveBeenCalled()
    await w.get('input[type="checkbox"]').trigger("change")
    expect(pushEvent).toHaveBeenCalledWith("retro_set_brainstorm_visible", { visible: true })

    // Broadcast updates re-seed the drafts.
    await w.setProps({
      session: {
        ...session,
        title: "From server",
        team: { slug: "ops", name: "Ops" },
        columns: [{ id: "c1", name: "Renamed", position: 0 }, ...session.columns.slice(1)],
      },
    })
    expect((w.get("#retro-title").element as HTMLInputElement).value).toBe("From server")
    expect((w.get("#retro-team").element as HTMLInputElement).value).toBe("Ops")
    expect(w.text()).toContain("/t/ops")

    const guest = mount(RetroSetup, { props: { session, is_host: false } })
    expect(guest.text()).toContain("host is setting up")
  })
})
