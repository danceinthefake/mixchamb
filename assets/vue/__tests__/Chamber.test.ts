import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"

const { pushEvent, handlers, audio } = vi.hoisted(() => ({
  pushEvent: vi.fn(),
  handlers: new Map<string, ((p: any) => void | Promise<void>)[]>(),
  audio: {
    ensureStarted: vi.fn(async () => {}),
    play: vi.fn(),
    preload: vi.fn(),
    setMasterVolume: vi.fn(),
    setChamberKind: vi.fn(),
    startRecording: vi.fn(async () => {}),
    stopRecording: vi.fn(async () => new Blob(["abc"], { type: "audio/ogg" })),
    stopAll: vi.fn(),
    makeStrumState: vi.fn(() => ({ held: new Map(), sessions: new Map() })),
    applyStrumPhase: vi.fn(),
    transposeNotes: vi.fn((n: string[]) => n),
    getChamberBus: vi.fn(),
    register: vi.fn(),
    registerInternalFx: vi.fn(),
    CHORDS: { C: ["C4", "E4", "G4"] },
  },
}))
vi.mock("live_vue", () => ({
  useLiveVue: () => ({
    pushEvent,
    handleEvent: (n: string, fn: any) => handlers.set(n, [...(handlers.get(n) ?? []), fn]),
  }),
}))
vi.mock("@/lib/audio", () => audio)
vi.mock("tone", () => ({ context: { state: "suspended" } }))
// Pads pull the engine modules; keep them out of this test's blast radius.
vi.mock("@/lib/audio/drums", () => ({}))
vi.mock("@/lib/audio/keyboard", () => ({}))
vi.mock("@/lib/audio/guitar", () => ({}))
vi.mock("@/lib/audio/bass", () => ({}))
vi.mock("@/lib/audio/pad", () => ({}))
vi.mock("@/lib/audio/suling", () => ({}))
vi.mock("@/lib/audio/kendang", () => ({}))

import { mount, enableAutoUnmount, flushPromises } from "@vue/test-utils"
import Chamber from "../Chamber.vue"

enableAutoUnmount(afterEach)

const fire = async (name: string, payload?: any) => {
  for (const fn of handlers.get(name) ?? []) await fn(payload)
  await flushPromises()
}

const base = {
  current_instrument: "drums" as const,
  chamber_kind: "room" as const,
  chamber_title: "My Jam!",
  chamber_slug: "abc123",
  activity: "music",
  presence_count: 2,
  current_user_id: "u1",
  is_host: true,
}

beforeEach(() => {
  pushEvent.mockClear()
  handlers.clear()
  for (const f of Object.values(audio)) if (typeof f === "function") (f as any).mockClear?.()
  localStorage.clear()
  vi.useFakeTimers()
})
afterEach(() => vi.useRealTimers())

describe("Chamber island", () => {
  it("music: gate, volume, kind, remote notes, replay, recording", async () => {
    localStorage.setItem("mixchamb:volume", "40")
    const w = mount(Chamber, { props: base, attachTo: document.body })
    expect(audio.setChamberKind).toHaveBeenCalledWith("room")
    expect(audio.setMasterVolume).toHaveBeenCalledWith(0.4)
    expect(w.text()).toContain("Tap to start jamming")

    await w.get("div.fixed").trigger("click")
    await flushPromises()
    expect(audio.ensureStarted).toHaveBeenCalled()
    expect(w.find("div.fixed").exists()).toBe(false)

    await w.setProps({ chamber_kind: "hall" })
    expect(audio.setChamberKind).toHaveBeenLastCalledWith("hall")

    const slider = w.get('input[type="range"]')
    await slider.setValue("65")
    expect(audio.setMasterVolume).toHaveBeenLastCalledWith(0.65)
    expect(localStorage.getItem("mixchamb:volume")).toBe("65")

    // Remote notes in every payload shape.
    await fire("play_remote_note", { instrument: "drums", style: "808", note: "kick" })
    await fire("play_remote_note", {
      instrument: "guitar",
      style: "rock",
      chord: "C",
      octave_offset: 1,
      phase: "press",
      up_strum: true,
    })
    await fire("play_remote_note", { instrument: "guitar", chord: "C", phase: "release" })
    expect(audio.play).toHaveBeenCalledWith("drums", "808", "kick", 0, undefined)
    expect(audio.play).toHaveBeenCalledWith("guitar", "rock", "C", 1, {
      phase: "press",
      upStrum: true,
    })

    // Replay: request, then a burst schedules plays + ends.
    const replayBtn = w.findAll("button").find((b) => /replay/i.test(b.text()))!
    await replayBtn.trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("request_replay", {})
    await fire("replay_burst", { events: [] })
    await replayBtn.trigger("click")
    audio.play.mockImplementationOnce(() => {
      throw new Error("sampler not loaded")
    })
    await fire("replay_burst", {
      events: [
        { instrument: "keyboard", style: "piano", note: "C4", offset_ms: 0 },
        { instrument: "guitar", style: "synth", chord: "C", phase: "press", offset_ms: 100 },
        { instrument: "pad", note: undefined, offset_ms: 150 },
      ],
    })
    expect(audio.preload).toHaveBeenCalledWith("keyboard", "piano")
    vi.advanceTimersByTime(500)
    expect(audio.play).toHaveBeenCalledWith("guitar", "synth", "C", 0, {
      phase: "press",
      upStrum: undefined,
    })
    // Stop mid-replay path.
    await replayBtn.trigger("click")
    await fire("replay_burst", {
      events: [{ instrument: "drums", style: "synth", note: "kick", offset_ms: 50 }],
    })
    await replayBtn.trigger("click")

    // Recording lifecycle → download link.
    await fire("start_audio_capture")
    await fire("start_audio_capture")
    expect(audio.startRecording).toHaveBeenCalledTimes(1)
    expect(w.text()).toContain("Capturing")
    vi.advanceTimersByTime(65_000)
    await fire("stop_audio_capture")
    await fire("stop_audio_capture")
    expect(w.text()).toContain("Download audio")
    expect(w.text()).toContain("1:05")

    ;(URL as any).createObjectURL = vi.fn(() => "blob:x")
    ;(URL as any).revokeObjectURL = vi.fn()
    const click = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {})
    await w
      .findAll("button")
      .find((b) => /Download audio/.test(b.text()))!
      .trigger("click")
    expect(click).toHaveBeenCalled()
    expect(pushEvent).toHaveBeenCalledWith("audio_downloaded", {})
    vi.advanceTimersByTime(1_100)
    expect((URL as any).revokeObjectURL).toHaveBeenCalled()

    await fire("clear_audio_capture")
    expect(w.text()).not.toContain("Download audio")

    // startRecording failure is swallowed.
    audio.startRecording.mockRejectedValueOnce(new Error("no mic"))
    await fire("start_audio_capture")
    expect(w.text()).not.toContain("Capturing")

    // Every pad mounts.
    for (const inst of [
      "keyboard",
      "guitar",
      "bass",
      "pad",
      "suling",
      "kendang",
      "drums",
    ] as const) {
      await w.setProps({ current_instrument: inst })
    }
    await w.setProps({ presence_count: 1 })
    expect(w.text().toLowerCase()).toContain("quiet here")
  })

  it("poker / retro / minigame: no audio bootstrap, seat gate copy, boards mount", async () => {
    const w = mount(Chamber, {
      props: {
        ...base,
        activity: "poker",
        poker_session: {
          status: "voting",
          deck: "fibonacci",
          cards: ["1", "2"],
          story: null,
          round: 1,
          my_vote: null,
          voted_user_ids: [],
          votes: {},
          history: [],
          queue: [],
        },
        poker_participants: [],
      },
    })
    expect(audio.setChamberKind).not.toHaveBeenCalled()
    expect(w.text()).toContain("Tap to take a seat")
    await w.setProps({ chamber_kind: "echo" })
    expect(audio.setChamberKind).not.toHaveBeenCalled()

    await w.setProps({ activity: "retro", retro_session: null })
    expect(w.text()).toContain("Retrospective")
    await w.setProps({ activity: "minigame", minigame_state: null, minigame_participants: [] })
    expect(w.html()).toBeTruthy()
  })
})
