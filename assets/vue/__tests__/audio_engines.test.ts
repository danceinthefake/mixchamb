// Smoke tests for the per-instrument audio engine modules. Each
// engine is a side-effect module: importing it runs `register()`
// calls that put a playback function in audio.ts's engine map.
// We don't invoke the registered functions here because Tone.js
// can't render real audio under happy-dom (Web Audio nodes are
// stubs). Importing alone covers the top-level + factory paths,
// which is what coverage cares about for these heavy files.

import { describe, it, expect } from "vitest"
// No vi.resetModules() — each `import()` call hits the module
// cache on the second-and-later visit, but the first import in
// the suite still runs every top-level `register()` line, which
// is what coverage measures. Re-running them would only double-
// register, not improve coverage.

describe("audio.ts utilities", () => {
  it("ensureStarted resolves once Tone.start completes", async () => {
    const { ensureStarted } = await import("../lib/audio")
    await expect(ensureStarted()).resolves.toBeUndefined()
  })

  it("setMasterVolume is a callable function (Tone Destination is mocked in tests)", async () => {
    const { setMasterVolume } = await import("../lib/audio")
    // We can't actually mutate Destination.volume in happy-dom —
    // assert the export shape instead, which is what the rest of
    // the code depends on.
    expect(typeof setMasterVolume).toBe("function")
  })

  it("register + play round-trip via the engine map", async () => {
    const { register, play } = await import("../lib/audio")
    const calls: string[] = []
    register("drums", "test-style", {
      play: (note: string) => {
        calls.push(note)
      },
      stopAll: () => {},
    })

    play("drums", "test-style", "kick")
    expect(calls).toEqual(["kick"])
  })

  it("play with an unknown (instrument, style) is a silent no-op", async () => {
    const { play } = await import("../lib/audio")
    expect(() => play("drums", "no-such-style", "kick")).not.toThrow()
  })

  it("stopAll on an unknown engine is a silent no-op", async () => {
    const { stopAll } = await import("../lib/audio")
    expect(() => stopAll("drums", "no-such-style")).not.toThrow()
  })
})

describe("engine module imports run their register calls without throwing", () => {
  it("drums.ts", async () => {
    await expect(import("../lib/audio/drums")).resolves.toBeDefined()
  })

  it("keyboard.ts", async () => {
    await expect(import("../lib/audio/keyboard")).resolves.toBeDefined()
  })

  it("guitar.ts", async () => {
    await expect(import("../lib/audio/guitar")).resolves.toBeDefined()
  })

  it("bass.ts", async () => {
    await expect(import("../lib/audio/bass")).resolves.toBeDefined()
  })

  it("pad.ts", async () => {
    await expect(import("../lib/audio/pad")).resolves.toBeDefined()
  })

  it("suling.ts", async () => {
    await expect(import("../lib/audio/suling")).resolves.toBeDefined()
  })

  it("kendang.ts", async () => {
    await expect(import("../lib/audio/kendang")).resolves.toBeDefined()
  })
})

describe("playReveal (poker chime)", () => {
  it("exists as an importable function", async () => {
    const { playReveal } = await import("../lib/audio")
    expect(typeof playReveal).toBe("function")
    // Don't actually invoke — Tone synth wiring throws in happy-dom.
  })
})

describe("playVoteBlip (retro vote cue)", () => {
  it("exists as an importable function", async () => {
    const { playVoteBlip } = await import("../lib/audio")
    expect(typeof playVoteBlip).toBe("function")
    // Don't actually invoke — Tone synth wiring throws in happy-dom.
  })
})
