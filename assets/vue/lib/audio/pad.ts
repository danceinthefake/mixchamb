// Pad engines — Warm / Bell / Sweep, all chord-based with long
// envelopes. Side-effect module: importing from SynthPad.vue
// registers all three into audio.ts's registry.

import { FMSynth, MonoSynth, PolySynth, Synth, now as toneNow } from "tone"
import {
  getChamberBus,
  register,
  transposeNotes,
  type ChordName,
  CHORDS,
  type InstrumentEngine,
} from "../audio"

// ── Pad : Warm ─────────────────────────────────────────────────────
// Slow-attack analog-style pad. Triangle through a long envelope —
// the chord swells in over half a second and fades out for several
// seconds after release. Sits behind everything else as ambience.

function makePadWarm(): InstrumentEngine {
  let poly: PolySynth | null = null

  function ensure() {
    if (poly) return
    poly = new PolySynth(Synth, {
      oscillator: { type: "fattriangle" },
      envelope: { attack: 0.8, decay: 0.5, sustain: 0.6, release: 2.5 },
    }).connect(getChamberBus())
    poly.volume.value = -14
  }

  return {
    play(chord, octaveOffset = 0) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      const shifted = transposeNotes(notes, octaveOffset)
      poly!.triggerAttackRelease(shifted, "2n", toneNow())
    },
    stopAll() {
      poly?.releaseAll()
    },
  }
}

register("pad", "warm", makePadWarm())

// ── Pad : Bell ─────────────────────────────────────────────────────
// FMSynth-driven bell-pad. Bright, harmonic, glassy attack that
// settles into a sustained tone.

function makePadBell(): InstrumentEngine {
  let poly: PolySynth | null = null

  function ensure() {
    if (poly) return
    poly = new PolySynth(FMSynth, {
      harmonicity: 3,
      modulationIndex: 10,
      envelope: { attack: 1.0, decay: 0.4, sustain: 0.5, release: 3.0 },
      modulation: { type: "sine" },
      modulationEnvelope: { attack: 0.4, decay: 0, sustain: 1, release: 2.5 },
    }).connect(getChamberBus())
    poly.volume.value = -14
  }

  return {
    play(chord, octaveOffset = 0) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      const shifted = transposeNotes(notes, octaveOffset)
      poly!.triggerAttackRelease(shifted, "2n", toneNow())
    },
    stopAll() {
      poly?.releaseAll()
    },
  }
}

register("pad", "bell", makePadBell())

// ── Pad : Sweep ────────────────────────────────────────────────────
// Sawtooth pad with a wide filter envelope sweep — classic 80s pad
// vibe, low-to-bright over the attack phase.

function makePadSweep(): InstrumentEngine {
  let poly: PolySynth | null = null

  function ensure() {
    if (poly) return
    poly = new PolySynth(MonoSynth, {
      oscillator: { type: "sawtooth" },
      envelope: { attack: 0.6, decay: 0.4, sustain: 0.7, release: 2.5 },
      filter: { type: "lowpass", frequency: 600, Q: 5 },
      filterEnvelope: {
        attack: 1.2,
        decay: 0.6,
        sustain: 0.5,
        release: 2.5,
        baseFrequency: 100,
        octaves: 4,
      },
    }).connect(getChamberBus())
    poly.volume.value = -14
  }

  return {
    play(chord, octaveOffset = 0) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      const shifted = transposeNotes(notes, octaveOffset)
      poly!.triggerAttackRelease(shifted, "2n", toneNow())
    },
    stopAll() {
      poly?.releaseAll()
    },
  }
}

register("pad", "sweep", makePadSweep())
