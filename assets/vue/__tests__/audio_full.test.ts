// Drives every registered instrument engine + the chamber FX bus
// through a universal Tone.js stub. Nothing here proves a sound is
// right — it proves the wiring doesn't throw for any (instrument,
// style, note) combination the pads can send, which is what a bad
// import or a renamed Tone option would break.
import { describe, it, expect, vi } from "vitest"

function stub(): any {
  const t: any = function () {}
  return new Proxy(t, {
    get(target, p) {
      if (p === "then") return undefined
      if (p === Symbol.toPrimitive) return () => 0
      if (!(p in target)) target[p] = stub()
      return target[p]
    },
    set(target, p, v) {
      target[p] = v
      return true
    },
    apply: () => stub(),
    construct: () => stub(),
  })
}

vi.mock("tone", () => {
  const Recorder: any = function () {
    return {
      start: async () => {},
      stop: async () => new Blob(["x"]),
      dispose: () => {},
      state: "started",
      mimeType: "audio/webm",
    }
  }
  Recorder.supported = true
  const klass = function () {
    return stub()
  }
  const classes = Object.fromEntries(
    [
      "Chorus",
      "Distortion",
      "FMSynth",
      "FeedbackDelay",
      "Filter",
      "Freeverb",
      "Gain",
      "MembraneSynth",
      "MetalSynth",
      "MonoSynth",
      "NoiseSynth",
      "PolySynth",
      "Reverb",
      "Sampler",
      "Synth",
    ].map((n) => [n, klass]),
  )
  return {
    ...classes,
    start: async () => {},
    now: () => 0,
    gainToDb: (g: number) => Math.log10(Math.max(g, 1e-6)) * 20,
    getDestination: () => stub(),
    Frequency: () => ({
      transpose: () => ({ toNote: () => "C4" }),
      toFrequency: () => 440,
      toNote: () => "C4",
    }),
    Recorder,
    context: { state: "running", currentTime: 0 },
  }
})

const { engines } = vi.hoisted(() => ({ engines: new Map<string, any>() }))
vi.mock("../lib/audio", async (orig) => {
  const real: any = await orig()
  return {
    ...real,
    register: (i: string, s: string, e: any) => {
      engines.set(`${i}:${s}`, e)
      real.register(i, s, e)
    },
  }
})

import * as audio from "../lib/audio"
import "../lib/audio/drums"
import "../lib/audio/keyboard"
import "../lib/audio/guitar"
import "../lib/audio/bass"
import "../lib/audio/pad"
import "../lib/audio/suling"
import "../lib/audio/kendang"

const DRUMS = [
  "kick",
  "snare",
  "hihat",
  "open_hat",
  "hihat_pedal",
  "crash",
  "ride",
  "tom_high",
  "tom_mid",
  "tom_floor",
]
const NOTES = ["C4", "D#3", "A2", "G5", "nope"]
const CHORDS = Object.keys(audio.CHORDS)

describe("every engine plays every note shape without throwing", () => {
  it("registered all seven instruments", () => {
    const instruments = new Set([...engines.keys()].map((k) => k.split(":")[0]))
    expect([...instruments].sort()).toEqual([
      "bass",
      "drums",
      "guitar",
      "kendang",
      "keyboard",
      "pad",
      "suling",
    ])
  })

  for (const [key, engine] of engines) {
    it(key, () => {
      const [instrument] = key.split(":")
      const notes =
        instrument === "drums"
          ? DRUMS
          : instrument === "guitar" || instrument === "pad"
            ? [...CHORDS, ...NOTES]
            : NOTES
      engine.preload?.()
      for (const note of notes) {
        for (const oct of [0, 1, -1]) {
          engine.play(note, oct, { phase: "press" })
          engine.play(note, oct, { phase: "press", upStrum: true })
          engine.play(note, oct, { phase: "release" })
        }
      }
      engine.play("kendang-tak", 0)
      engine.stopAll()
      engine.stopAll()
      // Through the public registry too.
      audio.play(instrument, key.split(":")[1], notes[0])
      audio.preload(instrument, key.split(":")[1])
      audio.stopAll(instrument, key.split(":")[1])
    })
  }
})

describe("audio.ts bus + helpers", () => {
  it("chamber kinds, volume, recording, cues, strum helpers", async () => {
    await audio.ensureStarted()
    await audio.ensureStarted()
    for (const kind of [
      "vacuum",
      "anechoic",
      "room",
      "live",
      "hall",
      "cathedral",
      "plate",
      "spring",
      "echo",
    ] as const) {
      audio.setChamberKind(kind)
    }
    audio.registerInternalFx({ value: 0.4, rampTo: vi.fn() } as any)
    audio.setChamberKind("vacuum")
    audio.registerInternalFx({ value: 0.2, rampTo: vi.fn() } as any)
    audio.setChamberKind("hall")

    audio.setMasterVolume(0)
    audio.setMasterVolume(0.5)
    audio.setMasterVolume(2)

    expect(await audio.stopRecording()).toBeNull()
    await audio.startRecording()
    await audio.startRecording()
    expect(await audio.stopRecording()).toBeInstanceOf(Blob)

    expect(audio.transposeNotes(["C4"], 0)).toEqual(["C4"])
    expect(audio.transposeNotes(["C4", "E4"], 1)).toHaveLength(2)

    vi.useFakeTimers()
    const state = audio.makeStrumState()
    const v = { triggerAttack: vi.fn(), triggerRelease: vi.fn(), triggerAttackRelease: vi.fn() }
    const notes = ["C4", "E4", "G4"]
    audio.applyStrumPhase(v, notes, "C", "press", false, false, state, "8n", "4n")
    vi.runAllTimers()
    audio.applyStrumPhase(v, notes, "C", "release", false, false, state, "8n", "4n")
    audio.applyStrumPhase(v, notes, "C", "press", true, false, state, "8n", "4n")
    audio.applyStrumPhase(v, notes, "C", "release", true, false, state, "8n", "4n")
    audio.applyStrumPhase(v, notes, "C", "press", false, true, state, "8n", "4n")
    vi.runAllTimers()
    audio.applyStrumPhase(v, notes, "C", undefined, false, false, state, "8n", "4n")
    vi.runAllTimers()
    expect(v.triggerAttack).toHaveBeenCalled()
    vi.useRealTimers()

    await audio.playReveal()
    await audio.playVoteBlip()
    await audio.playGuessCorrect()
    await audio.playTimeUp()
    await audio.playGameOver()
    audio.play("nope", "nope", "x")
    audio.stopAll("nope", "nope")
    audio.preload("nope", "nope")
  })
})
