import { describe, it, expect, vi } from "vitest"
import { mount } from "@vue/test-utils"
import RetroCarryOver from "../activities/retro/RetroCarryOver.vue"

const pushEvent = vi.fn()
vi.mock("live_vue", () => ({ useLiveVue: () => ({ pushEvent }) }))

const item = {
  id: "a1",
  body: "fix CI",
  assignee_alias: "ana",
  due_date: null,
  from_title: "Sprint 1",
  from_archived_at: null,
}

describe("RetroCarryOver", () => {
  it("renders nothing without items", () => {
    const w = mount(RetroCarryOver, { props: { items: [] } })
    expect(w.find("#retro-carry-over").exists()).toBe(false)
  })

  it("pushes carry-over and mark-done events for a row", async () => {
    const w = mount(RetroCarryOver, { props: { items: [item] } })
    expect(w.text()).toContain("fix CI")
    expect(w.text()).toContain("from Sprint 1")

    await w.get("button:nth-of-type(1)").trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("retro_carry_over_action", { action_id: "a1" })

    await w.get("button:nth-of-type(2)").trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("retro_complete_previous_action", {
      action_id: "a1",
    })
  })
})
