import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { mount } from "@vue/test-utils"
import RetroTimer from "../activities/retro/RetroTimer.vue"

const pushEvent = vi.fn()
vi.mock("live_vue", () => ({ useLiveVue: () => ({ pushEvent }) }))
const playTimeUp = vi.fn(() => Promise.resolve())
vi.mock("../lib/audio", () => ({ playTimeUp: () => playTimeUp() }))

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(new Date("2026-09-17T00:00:00Z"))
  pushEvent.mockClear()
  playTimeUp.mockClear()
})
afterEach(() => vi.useRealTimers())

describe("RetroTimer", () => {
  it("hidden for non-hosts with no deadline", () => {
    const w = mount(RetroTimer, { props: { deadline: null, auto_advance: false, is_host: false } })
    expect(w.find("#retro-timer").exists()).toBe(false)
  })

  it("host presets push seconds; clear pushes null", async () => {
    const w = mount(RetroTimer, {
      props: { deadline: Date.now() + 1000, auto_advance: false, is_host: true },
    })
    await w.get("button:nth-of-type(2)").trigger("click") // 5 min
    expect(pushEvent).toHaveBeenCalledWith("retro_set_timer", { seconds: 300, auto_advance: false })
    await w.get("#retro-timer-auto").setValue(true)
    await w.get("button:nth-of-type(1)").trigger("click") // 3 min
    expect(pushEvent).toHaveBeenLastCalledWith("retro_set_timer", {
      seconds: 180,
      auto_advance: true,
    })
    await w.findAll("button").at(-1)!.trigger("click") // Clear
    expect(pushEvent).toHaveBeenCalledWith("retro_set_timer", { seconds: null })
  })

  it("counts down from the absolute deadline and buzzes at zero", async () => {
    const w = mount(RetroTimer, {
      props: { deadline: Date.now() + 65_000, auto_advance: true, is_host: false },
    })
    expect(w.text()).toContain("1:05")
    expect(w.text()).toContain("auto")

    await vi.advanceTimersByTimeAsync(64_000)
    expect(w.text()).toContain("0:01")
    expect(playTimeUp).not.toHaveBeenCalled()

    await vi.advanceTimersByTimeAsync(1_500)
    expect(w.text()).toContain("Time's up")
    expect(playTimeUp).toHaveBeenCalledTimes(1)
  })
})
