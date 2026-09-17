import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"

const { pushEvent, handlers, playGuessCorrect, playTimeUp } = vi.hoisted(() => ({
  pushEvent: vi.fn(),
  handlers: new Map<string, ((p: any) => void)[]>(),
  playGuessCorrect: vi.fn(() => Promise.resolve()),
  playTimeUp: vi.fn(() => Promise.resolve()),
}))
vi.mock("live_vue", () => ({
  useLiveVue: () => ({
    pushEvent,
    handleEvent: (name: string, fn: (p: any) => void) =>
      handlers.set(name, [...(handlers.get(name) ?? []), fn]),
  }),
}))
vi.mock("../lib/audio", () => ({
  playGameOver: vi.fn(() => Promise.resolve()),
  playGuessCorrect,
  playTimeUp,
}))

import { mount, enableAutoUnmount } from "@vue/test-utils"
import PictionaryStage from "../activities/minigame/pictionary/PictionaryStage.vue"
import GarticStage from "../activities/minigame/gartic_phone/GarticStage.vue"
import TwoTruthsStage from "../activities/minigame/two_truths/TwoTruthsStage.vue"

enableAutoUnmount(afterEach)

const nameOf = (id: string | null) => (id ? `name-${id}` : "—")
const ctx = new Proxy({}, { get: () => vi.fn() })
beforeEach(() => {
  pushEvent.mockClear()
  handlers.clear()
  vi.useFakeTimers()
  vi.setSystemTime(new Date("2026-09-17T00:00:00Z"))
  ;(HTMLCanvasElement.prototype as any).getContext = () => ctx
  ;(globalThis as any).ResizeObserver = class {
    observe() {}
    disconnect() {}
  }
})
afterEach(() => vi.useRealTimers())

const pict = {
  game: "pictionary" as const,
  phase: "turn" as const,
  config: { word_pack: "general", turn_seconds: 80, round_count: 2, custom_word_count: 0 },
  round: 1,
  round_count: 2,
  players: ["u1", "u2"],
  drawer_id: "u1",
  is_drawer: true,
  is_choosing: true,
  word: null as string | null,
  masked: "_ _ _",
  drawer_away: false,
  word_choices: ["cat", "dog"],
  guessed: [] as string[],
  scores: { u1: 0, u2: 0 },
  deadline: Date.now() + 5_000,
  strokes: [],
  turn_token: 1,
}

describe("PictionaryStage", () => {
  it("drawer picks a word; guesser sees blanks; reveal shows the word; timer buzzes", async () => {
    pict.deadline = Date.now() + 5_000
    const w = mount(PictionaryStage, {
      props: { state: pict, current_user_id: "u1", drawerName: "Ana", nameOf },
    })
    expect(w.text()).toContain("Pick a word")
    await w
      .findAll("button")
      .find((b) => b.text() === "dog")!
      .trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("minigame_choose_word", { word: "dog" })

    await w.setProps({ state: { ...pict, is_choosing: false, word: "dog" } })
    expect(w.text()).toContain("dog")

    await w.setProps({
      state: { ...pict, is_drawer: false, is_choosing: false, drawer_id: "u2", word: null },
      current_user_id: "u1",
    })
    expect(w.text()).toContain("_ _ _")
    expect(w.text()).toContain("Ana is drawing")

    // Feed cue: a correct guess plays the blip.
    for (const fn of handlers.get("minigame_feed")!) fn({ type: "correct" })
    expect(playGuessCorrect).toHaveBeenCalled()

    // Clock runs out while the turn is live → buzzer once.
    await vi.advanceTimersByTimeAsync(6_000)
    expect(playTimeUp).toHaveBeenCalledTimes(1)

    await w.setProps({ state: { ...pict, phase: "turn_reveal", word: "dog", is_choosing: false } })
    expect(w.text()).toContain("Round result")
    expect(w.text()).toContain("dog")

    await w.setProps({
      state: { ...pict, is_drawer: false, drawer_id: "u2", drawer_away: true, is_choosing: true },
    })
    expect(w.text()).toContain("choosing")
  })
})

const gartic = {
  game: "gartic_phone" as const,
  phase: "play" as const,
  config: { step_seconds: 60 },
  step: 0,
  total_steps: 3,
  player_count: 3,
  submitted_count: 1,
  deadline: Date.now() + 10_000,
  turn_token: 1,
  is_player: true,
  my_kind: "text" as "text" | "drawing" | null,
  prompt: null as any,
  submitted: false,
}

describe("GarticStage", () => {
  it("text step submits trimmed text; drawing step submits strokes; host can skip", async () => {
    const w = mount(GarticStage, {
      props: { state: gartic, current_user_id: "u1", is_host: true, nameOf },
    })
    await w.get("input").setValue("  a fish  ")
    await w
      .findAll("button")
      .find((b) => b.text().includes("Submit"))!
      .trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("minigame_submit", { text: "a fish" })

    await w.setProps({
      state: {
        ...gartic,
        step: 1,
        my_kind: "drawing",
        prompt: { kind: "text", by: "u2", text: "a fish" },
      },
    })
    expect(w.text()).toContain("a fish")
    await w
      .findAll("button")
      .find((b) => b.text().includes("Submit"))!
      .trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("minigame_submit", { strokes: [] })

    await w.setProps({
      state: {
        ...gartic,
        step: 2,
        my_kind: "text",
        prompt: {
          kind: "drawing",
          by: "u2",
          strokes: [{ points: [[0, 0]], color: "#000", width: 0.01 }],
        },
      },
    })
    expect(w.find("canvas").exists()).toBe(true)

    await w
      .findAll("button")
      .find((b) => /skip|force/i.test(b.text()))!
      .trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("minigame_skip", {})

    await w.setProps({ state: { ...gartic, submitted: true } })
    expect(w.text().toLowerCase()).toContain("waiting")
    await w.setProps({ state: { ...gartic, is_player: false } })
    expect(w.text().toLowerCase()).toContain("watching")
  })

  it("album pages through books; game over lists them all", async () => {
    const pages = [
      { kind: "text", by: "u1", text: "a fish" },
      { kind: "drawing", by: "u2", strokes: [] },
    ]
    const w = mount(GarticStage, {
      props: {
        state: {
          game: "gartic_phone",
          phase: "album",
          total_books: 3,
          album_book: 0,
          album_page: 1,
          book_owner: "u1",
          pages,
        },
        current_user_id: "u1",
        is_host: false,
        nameOf,
      },
    })
    expect(w.text()).toContain("name-u1")
    expect(w.text()).toContain("Host is presenting")
    await w.setProps({ is_host: true })
    await w
      .findAll("button")
      .find((b) => b.text().includes("Next"))!
      .trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("minigame_album_next", {})

    await w.setProps({
      state: {
        game: "gartic_phone",
        phase: "gameover",
        books: [{ owner: "u1", pages }],
      },
      is_host: false,
    })
    expect(w.text()).toContain("a fish")
    expect(w.text()).toContain("Waiting for the host")
  })
})

const tt = {
  game: "two_truths" as const,
  phase: "writing" as const,
  config: { write_seconds: 90, guess_seconds: 30 },
  is_player: true,
  submitted: false,
  submitted_count: 0,
  player_count: 3,
  deadline: Date.now() + 5_000,
  turn_token: 1,
}

describe("TwoTruthsStage", () => {
  it("writing: three statements + lie index; host skip", async () => {
    const w = mount(TwoTruthsStage, {
      props: { state: tt, current_user_id: "u1", is_host: true, nameOf },
    })
    const submit = () => w.findAll("button").find((b) => b.text().includes("Submit"))!
    await submit().trigger("click")
    expect(pushEvent).not.toHaveBeenCalled()

    const texts = w.findAll("input[type=text]")
    await texts[0].setValue("I ski")
    await texts[1].setValue("I fly")
    await texts[2].setValue("I sing")
    await w.findAll("input[type=radio]")[2].setValue()
    await submit().trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("minigame_submit", {
      items: ["I ski", "I fly", "I sing"],
      lie: 2,
    })

    await w
      .findAll("button")
      .find((b) => /skip|force|start/i.test(b.text()))!
      .trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("minigame_skip", {})

    await w.setProps({ state: { ...tt, submitted: true } })
    expect(w.text().toLowerCase()).toContain("waiting")
    await w.setProps({ state: { ...tt, is_player: false } })
    expect(w.text().toLowerCase()).toContain("watching")
  })

  it("guessing: pick the lie; author + locked-in copy; reveal marks the lie", async () => {
    const guessing = {
      game: "two_truths" as const,
      phase: "guessing" as const,
      author: "u2",
      author_index: 0,
      total_authors: 3,
      guessed_count: 0,
      guesser_count: 2,
      players: ["u1", "u2", "u3"],
      scores: { u1: 0, u2: 0, u3: 0 },
      statements: ["a", "b", "c"],
      is_author: false,
      my_guess: null as number | null,
      guessed: [] as string[],
      deadline: Date.now() + 5_000,
      turn_token: 2,
    }
    const w = mount(TwoTruthsStage, {
      props: { state: guessing, current_user_id: "u1", is_host: true, nameOf },
    })
    expect(w.text()).toContain("name-u2")
    await w
      .findAll("button")
      .find((b) => b.text().includes("b"))!
      .trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("minigame_submit", { lie_guess: 1 })

    await w.setProps({ state: { ...guessing, my_guess: 1 } })
    expect(w.text()).toContain("Locked in")
    await w.setProps({ state: { ...guessing, is_author: true } })
    pushEvent.mockClear()
    await w
      .findAll("button")
      .find((b) => b.text().includes("a"))!
      .trigger("click")
    expect(pushEvent).not.toHaveBeenCalledWith("minigame_submit", expect.anything())

    await vi.advanceTimersByTimeAsync(6_000)

    await w.setProps({
      state: {
        ...guessing,
        phase: "reveal",
        is_author: false,
        my_guess: 1,
        lie_index: 2,
        picks: { u1: 1, u3: 2 },
        deadline: null,
      },
    })
    expect(w.text().toLowerCase()).toContain("lie")
    await w
      .findAll("button")
      .find((b) => /next|continue|skip/i.test(b.text()))!
      .trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("minigame_skip", {})

    await w.setProps({
      state: { game: "two_truths", phase: "gameover", scores: { u1: 10 }, players: ["u1"] },
    })
    expect(w.text().toLowerCase()).toContain("final")
  })
})
