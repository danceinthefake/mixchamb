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
})
