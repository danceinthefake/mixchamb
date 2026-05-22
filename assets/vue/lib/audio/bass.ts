// Bass engines — Synth / Sub / Slap. Side-effect module: importing
// from BassPad.vue registers all three into audio.ts's registry.

import { MonoSynth, PolySynth, Synth, now as toneNow } from "tone"
import { getChamberBus, register, type InstrumentEngine } from "../audio"

// ── Bass : Synth ───────────────────────────────────────────────────
// Punchy MonoSynth bass — sawtooth through a moving lowpass filter.
// Bass is monophonic by tradition (and by physical bass-guitar
// constraint), so we use a single MonoSynth instead of PolySynth.

function makeBassSynth(): InstrumentEngine {
  let synth: MonoSynth | null = null

  function ensure() {
    if (synth) return
    synth = new MonoSynth({
      oscillator: { type: "sawtooth" },
      envelope: { attack: 0.005, decay: 0.4, sustain: 0.3, release: 0.4 },
      filter: { type: "lowpass", frequency: 1200, Q: 4 },
      filterEnvelope: {
        attack: 0.005,
        decay: 0.3,
        sustain: 0.2,
        release: 0.4,
        baseFrequency: 100,
        octaves: 3,
      },
    }).connect(getChamberBus())
    synth.volume.value = -6
  }

  return {
    play(note) {
      ensure()
      synth!.triggerAttackRelease(note, "8n", toneNow())
    },
    stopAll() {
      synth?.triggerRelease(toneNow())
    },
  }
}

register("bass", "synth", makeBassSynth())

// ── Bass : Sub ─────────────────────────────────────────────────────
// Pure sine sub-bass. Slow attack, long sustain, deep low-frequency
// emphasis. Sits underneath everything else in the mix.

function makeBassSub(): InstrumentEngine {
  let synth: MonoSynth | null = null

  function ensure() {
    if (synth) return
    synth = new MonoSynth({
      oscillator: { type: "sine" },
      envelope: { attack: 0.04, decay: 0.3, sustain: 0.7, release: 0.8 },
      filter: { type: "lowpass", frequency: 200, Q: 1 },
      filterEnvelope: {
        attack: 0.04,
        decay: 0.3,
        sustain: 0.5,
        release: 0.8,
        baseFrequency: 80,
        octaves: 1,
      },
    }).connect(getChamberBus())
    synth.volume.value = -3
  }

  return {
    play(note) {
      ensure()
      synth!.triggerAttackRelease(note, "4n", toneNow())
    },
    stopAll() {
      synth?.triggerRelease(toneNow())
    },
  }
}

register("bass", "sub", makeBassSub())

// ── Bass : Slap ────────────────────────────────────────────────────
// Funky slap-bass character — square through a bandpass that
// sweeps for the popped attack feel.

function makeBassSlap(): InstrumentEngine {
  let synth: MonoSynth | null = null

  function ensure() {
    if (synth) return
    synth = new MonoSynth({
      oscillator: { type: "square" },
      envelope: { attack: 0.001, decay: 0.18, sustain: 0, release: 0.15 },
      filter: { type: "bandpass", frequency: 800, Q: 8 },
      filterEnvelope: {
        attack: 0.001,
        decay: 0.3,
        sustain: 0,
        release: 0.2,
        baseFrequency: 200,
        octaves: 4,
      },
    }).connect(getChamberBus())
    // Bandpass + short envelope makes Slap quieter than the other
    // bass flavors at matched settings. -2 dB lifts it close to
    // Synth/Sub so users don't need to chase the volume slider when
    // switching styles.
    synth.volume.value = -2
  }

  return {
    play(note) {
      ensure()
      synth!.triggerAttackRelease(note, "16n", toneNow())
    },
    stopAll() {
      synth?.triggerRelease(toneNow())
    },
  }
}

register("bass", "slap", makeBassSlap())
