import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"

// One fake LiveVue for the whole file: records pushes and keeps the
// server→client handlers so tests can fire relay / feed events.
const { pushEvent, handlers } = vi.hoisted(() => ({
  pushEvent: vi.fn(),
  handlers: new Map<string, (p: any) => void>(),
}))
vi.mock("live_vue", () => ({
  useLiveVue: () => ({
    pushEvent,
    handleEvent: (name: string, fn: (p: any) => void) => handlers.set(name, fn),
  }),
}))
vi.mock("../lib/audio", () => ({
  playGameOver: vi.fn(() => Promise.resolve()),
  playGuessCorrect: vi.fn(() => Promise.resolve()),
  playTimeUp: vi.fn(() => Promise.resolve()),
}))

import { mount, enableAutoUnmount } from "@vue/test-utils"
import { nextTick } from "vue"
import MiniGameBoard from "../activities/minigame/MiniGameBoard.vue"
import MiniGameLobby from "../activities/minigame/MiniGameLobby.vue"
import MiniGameHostControls from "../activities/minigame/MiniGameHostControls.vue"
import MiniGameScoreboard from "../activities/minigame/MiniGameScoreboard.vue"
import HowToPlay from "../activities/minigame/HowToPlay.vue"
import PlayerIdenticon from "../activities/minigame/PlayerIdenticon.vue"
import DrawingCanvas from "../activities/minigame/pictionary/DrawingCanvas.vue"
import GuessFeed from "../activities/minigame/pictionary/GuessFeed.vue"
import { identicon } from "../lib/identicon"

enableAutoUnmount(afterEach)

// happy-dom has no 2D canvas; stub the bits DrawingCanvas touches.
const ctx = {
  fillRect: vi.fn(),
  beginPath: vi.fn(),
  arc: vi.fn(),
  fill: vi.fn(),
  moveTo: vi.fn(),
  lineTo: vi.fn(),
  stroke: vi.fn(),
}
beforeEach(() => {
  pushEvent.mockClear()
  handlers.clear()
  ;(HTMLCanvasElement.prototype as any).getContext = () => ctx
  ;(HTMLCanvasElement.prototype as any).setPointerCapture = () => {}
  HTMLCanvasElement.prototype.getBoundingClientRect = () =>
    ({ left: 0, top: 0, width: 100, height: 60, right: 100, bottom: 60 }) as DOMRect
  ;(globalThis as any).ResizeObserver = class {
    observe() {}
    disconnect() {}
  }
})

const participants = [
  { user_id: "u1", display_name: "ana-01", alias: null },
  { user_id: "u2", display_name: "bo-02", alias: "Bo" },
  { user_id: "u3", display_name: "cy-03", alias: null },
]
const nameOf = (id: string | null) =>
  participants.find((p) => p.user_id === id)?.alias ??
  participants.find((p) => p.user_id === id)?.display_name ??
  "—"

const pictConfig = { word_pack: "general", turn_seconds: 80, round_count: 2, custom_word_count: 0 }
const pictTurn = {
  game: "pictionary" as const,
  phase: "turn" as const,
  config: pictConfig,
  round: 1,
  round_count: 2,
  players: ["u1", "u2", "u3"],
  drawer_id: "u1",
  is_drawer: true,
  is_choosing: true,
  word: null,
  masked: "_ _ _",
  drawer_away: false,
  word_choices: ["cat", "dog", "owl"],
  guessed: [],
  scores: { u1: 0, u2: 5, u3: 0 },
  deadline: Date.now() + 60_000,
  strokes: [],
  turn_token: 1,
}

describe("MiniGameBoard", () => {
  it("renders nothing without state, the lobby in :lobby", () => {
    const empty = mount(MiniGameBoard, {
      props: { state: null, participants, current_user_id: "u1", is_host: true },
    })
    expect(empty.find("section[aria-label]").exists()).toBe(false)

    const w = mount(MiniGameBoard, {
      props: {
        state: { ...pictTurn, phase: "lobby" },
        participants,
        current_user_id: "u1",
        is_host: true,
      },
    })
    expect(w.text()).toContain("Mini-game")
    expect(w.findComponent(MiniGameLobby).exists()).toBe(true)
  })

  it("routes each game + phase to its stage and wires host controls", async () => {
    const w = mount(MiniGameBoard, {
      props: { state: pictTurn, participants, current_user_id: "u1", is_host: true },
    })
    expect(w.text()).toContain("Round 1 / 2")
    await w.get("button[title], button").trigger("click") // host Skip
    expect(pushEvent).toHaveBeenCalledWith("minigame_skip", {})

    await w.setProps({ state: { ...pictTurn, phase: "gameover" } })
    expect(w.text()).toContain("Final scores")

    await w.setProps({
      state: {
        game: "gartic_phone",
        phase: "play",
        step: 0,
        total_steps: 3,
        player_count: 3,
        submitted_count: 0,
        deadline: Date.now() + 30_000,
        turn_token: 1,
        is_player: true,
        my_kind: "text",
        prompt: null,
        submitted: false,
      },
    })
    expect(w.text()).toContain("Gartic")

    await w.setProps({
      state: {
        game: "two_truths",
        phase: "writing",
        is_player: true,
        submitted: false,
        submitted_count: 0,
        player_count: 3,
        deadline: null,
        turn_token: 1,
      },
    })
    expect(w.text().toLowerCase()).toContain("truths")
  })
})

describe("MiniGameLobby", () => {
  const base = {
    game: "pictionary",
    config: pictConfig,
    player_count: 3,
    min_players: 2,
    is_host: true,
  }

  it("host picks a game and edits config; guests see read-only copy", async () => {
    const w = mount(MiniGameLobby, { props: base })
    await w.get("button").trigger("click")
    expect(w.emitted("select-game")?.length).toBeGreaterThan(0)

    const selects = w.findAll("select")
    await selects[0].setValue("animals")
    expect(w.emitted("set-config")?.[0]).toEqual([{ word_pack: "animals" }])
    await selects[1].setValue("60")
    expect(w.emitted("set-config")?.[1]).toEqual([{ turn_seconds: 60 }])

    await w.setProps({ config: { ...pictConfig, word_pack: "custom", custom_word_count: 2 } })
    await w.get("textarea").setValue("rubber duck\n\nmerge conflict\n")
    await w
      .findAll("button")
      .find((b) => b.text() === "Save words")!
      .trigger("click")
    const custom = w.emitted("set-config")?.find((e: any) => e[0].custom_words)
    expect(custom?.[0]).toEqual({ custom_words: ["rubber duck", "merge conflict"] })

    const guest = mount(MiniGameLobby, { props: { ...base, is_host: false } })
    expect(guest.findAll("select")).toHaveLength(0)
  })

  it("shows the other games' lobby copy", () => {
    expect(mount(MiniGameLobby, { props: { ...base, game: "gartic_phone" } }).text()).toContain(
      "Gartic",
    )
    expect(mount(MiniGameLobby, { props: { ...base, game: "two_truths" } }).text()).toContain(
      "Two Truths",
    )
  })
})

describe("MiniGameHostControls", () => {
  it("emits the right action per phase, gates start on min players", async () => {
    const w = mount(MiniGameHostControls, {
      props: { phase: "lobby", player_count: 1, min_players: 2 },
    })
    expect(w.get("button").attributes("disabled")).toBeDefined()
    await w.setProps({ player_count: 3 })
    await w.get("button").trigger("click")
    expect(w.emitted("start")).toBeTruthy()

    await w.setProps({ phase: "turn" })
    await w.get("button").trigger("click")
    expect(w.emitted("skip")).toBeTruthy()

    await w.setProps({ phase: "turn_reveal" })
    await w.get("button").trigger("click")
    expect(w.emitted("next")).toBeTruthy()

    await w.setProps({ phase: "gameover" })
    const [again, end] = w.findAll("button")
    await again.trigger("click")
    await end.trigger("click")
    expect(w.emitted("play-again")).toBeTruthy()
    expect(w.emitted("end")).toBeTruthy()
  })
})

describe("MiniGameScoreboard / HowToPlay / PlayerIdenticon", () => {
  it("scoreboard sorts by score and marks drawer + guessed", () => {
    const w = mount(MiniGameScoreboard, {
      props: {
        scores: { u1: 0, u2: 5, u3: 3 },
        players: ["u1", "u2", "u3"],
        drawer_id: "u1",
        guessed: ["u3"],
        nameOf,
      },
    })
    const names = w.findAll("li").map((li) => li.text())
    expect(names[0]).toContain("Bo")
    const final = mount(MiniGameScoreboard, {
      props: {
        scores: { u1: 1 },
        players: ["u1"],
        drawer_id: null,
        guessed: [],
        nameOf,
        final: true,
      },
    })
    expect(final.text()).toContain("ana-01")
  })

  it("how-to-play has copy per game", () => {
    for (const game of ["pictionary", "gartic_phone", "two_truths", "other"]) {
      expect(mount(HowToPlay, { props: { game } }).text().length).toBeGreaterThan(10)
    }
  })

  it("identicon is deterministic and symmetric", () => {
    const a = identicon("abc")
    expect(identicon("abc")).toEqual(a)
    expect(a.hue).toBeGreaterThanOrEqual(0)
    for (const [x, y] of a.cells) if (x < 2) expect(a.cells).toContainEqual([4 - x, y])
    const w = mount(PlayerIdenticon, { props: { seed: "abc" } })
    expect(w.findAll("rect").length).toBe(a.cells.length + 1) // + background
  })
})

describe("DrawingCanvas", () => {
  const base = { strokes: [], isDrawer: true, frozen: false, turnToken: 1, current_user_id: "u1" }

  function pointer(w: any, type: string, x: number, y: number) {
    const ev = new Event(type, { bubbles: true }) as any
    ev.clientX = x
    ev.clientY = y
    ev.pointerId = 1
    ev.preventDefault = () => {}
    w.get("canvas").element.dispatchEvent(ev)
  }

  it("drawer strokes are batched to the server and a stroke_end follows", async () => {
    const w = mount(DrawingCanvas, { props: base, attachTo: document.body })
    pointer(w, "pointerdown", 10, 10)
    pointer(w, "pointermove", 20, 20)
    pointer(w, "pointerup", 20, 20)
    const end = pushEvent.mock.calls.find((c) => c[0] === "minigame_stroke_end")
    expect(end?.[1].points).toEqual([
      [0.1, 1 / 6],
      [0.2, 1 / 3],
    ])
    expect(pushEvent).toHaveBeenCalledWith("minigame_stroke", expect.objectContaining({ seq: 1 }))

    // Toolbar: undo + clear relay; keyboard picks colour / size / eraser.
    const buttons = w.findAll("button")
    await buttons.at(-2)!.trigger("click")
    await buttons.at(-1)!.trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("minigame_undo", {})
    expect(pushEvent).toHaveBeenCalledWith("minigame_clear", {})
    for (const key of ["3", "[", "]", "e", "z", "x"]) {
      window.dispatchEvent(new KeyboardEvent("keydown", { key }))
    }
    expect(pushEvent.mock.calls.filter((c) => c[0] === "minigame_undo").length).toBe(2)
  })

  it("non-drawers can't draw; relay events update the model; local mode exposes strokes", async () => {
    const w = mount(DrawingCanvas, { props: { ...base, isDrawer: false } })
    pointer(w, "pointerdown", 10, 10)
    pointer(w, "pointerup", 10, 10)
    expect(pushEvent).not.toHaveBeenCalled()

    const relay = handlers.get("minigame_relay")!
    relay({
      kind: "stroke",
      payload: { from: "u2", seq: 9, points: [[0.1, 0.1]], color: "#000", width: 0.01 },
    })
    relay({ kind: "stroke", payload: { from: "u2", seq: 9, points: [[0.2, 0.2]] } })
    relay({
      kind: "stroke_end",
      payload: {
        from: "u2",
        seq: 9,
        points: [
          [0.1, 0.1],
          [0.2, 0.2],
        ],
        color: "#000",
        width: 0.01,
      },
    })
    relay({ kind: "undo", payload: { from: "u2" } })
    relay({ kind: "clear", payload: { from: "u2" } })
    relay({ kind: "stroke", payload: { from: "u1", seq: 1, points: [] } }) // own echo skipped
    await nextTick()

    const local = mount(DrawingCanvas, {
      props: { ...base, local: true, strokes: [{ points: [[0, 0]], color: "#000", width: 0.01 }] },
      attachTo: document.body,
    })
    pointer(local, "pointerdown", 10, 10)
    pointer(local, "pointerup", 10, 10)
    expect(pushEvent).not.toHaveBeenCalled()
    expect((local.vm as any).getStrokes()).toHaveLength(2)
    await local.setProps({ turnToken: 2, strokes: [] })
    expect((local.vm as any).getStrokes()).toHaveLength(0)
  })
})

describe("GuessFeed", () => {
  it("submits guesses and renders feed lines from the server", async () => {
    const w = mount(GuessFeed, {
      props: { canGuess: true, hasGuessed: false, turnToken: 1, current_user_id: "u1", nameOf },
    })
    await w.get("input").setValue("  cat ")
    await w.get("form").trigger("submit")
    expect(pushEvent).toHaveBeenCalledWith("minigame_guess", { text: "cat" })

    const feed = handlers.get("minigame_feed")!
    feed({ type: "wrong", user_id: "u2", alias: "Bo", text: "dog" })
    feed({ type: "close", user_id: "u1", alias: "me" })
    feed({ type: "correct", user_id: "u3", alias: "cy" })
    await nextTick()
    expect(w.text()).toContain("dog")
    expect(w.text().toLowerCase()).toContain("close")

    await w.setProps({ hasGuessed: true })
    expect(w.get("input").attributes("placeholder")).toContain("guessed")
    await w.setProps({ hasGuessed: false, canGuess: false })
    expect(w.get("input").attributes("placeholder")).toContain("Waiting")
    await w.setProps({ turnToken: 2 })
  })
})
