// Keyboard engines — Synth / Lead / Piano (sampled). Side-effect
// module: importing it from KeyboardPad.vue registers all three
// engines into audio.ts's registry at module load. Lazy-chunked.

import { MonoSynth, PolySynth, Sampler, Synth, now as toneNow } from "tone"
import { getChamberBus, register, type InstrumentEngine } from "../audio"

// ── Keyboard : Synth ───────────────────────────────────────────────
// PolySynth over Synth — multiple notes can ring at once.

function makeKeyboardSynth(): InstrumentEngine {
  let poly: PolySynth | null = null

  function ensure() {
    if (poly) return
    poly = new PolySynth(Synth, {
      oscillator: { type: "triangle" },
      envelope: { attack: 0.005, decay: 0.1, sustain: 0.3, release: 0.8 },
    }).connect(getChamberBus())
    poly.volume.value = -10
  }

  return {
    play(note) {
      ensure()
      poly!.triggerAttackRelease(note, "8n", toneNow())
    },
    stopAll() {
      poly?.releaseAll()
    },
  }
}

register("keyboard", "synth", makeKeyboardSynth())

// ── Keyboard : Lead ────────────────────────────────────────────────
// Sawtooth + sweeping lowpass filter envelope, Moog-y solo voice.

function makeKeyboardLead(): InstrumentEngine {
  let poly: PolySynth | null = null

  function ensure() {
    if (poly) return
    poly = new PolySynth(MonoSynth, {
      oscillator: { type: "sawtooth" },
      envelope: { attack: 0.01, decay: 0.4, sustain: 0.4, release: 0.5 },
      filter: { type: "lowpass", frequency: 1500, Q: 6 },
      filterEnvelope: {
        attack: 0.04,
        decay: 0.4,
        sustain: 0.3,
        release: 0.5,
        baseFrequency: 300,
        octaves: 3,
      },
    }).connect(getChamberBus())
    poly.volume.value = -12
  }

  return {
    play(note) {
      ensure()
      poly!.triggerAttackRelease(note, "8n", toneNow())
    },
    stopAll() {
      poly?.releaseAll()
    },
  }
}

register("keyboard", "lead", makeKeyboardLead())

// ── Keyboard : Piano (Salamander Grand Piano, sampled) ────────────
// Real grand-piano samples — Salamander Grand Piano is a free
// open-source recording of a Yamaha C5 concert grand, streamed from
// the js community CDN. Three anchor samples (A3 / A4 / A5)
// cover the keyboard's full visible range — Sampler pitch-shifts
// between them. ~150 KB total download, only fetched when the user
// actually picks Piano (preload() hook).

function makeKeyboardPiano(): InstrumentEngine {
  let sampler: Sampler | null = null

  function ensure() {
    if (sampler) return
    sampler = new Sampler({
      urls: {
        A3: "A3.mp3",
        A4: "A4.mp3",
        A5: "A5.mp3",
      },
      release: 1,
      baseUrl: "https://tonejs.github.io/audio/salamander/",
    }).connect(getChamberBus())
    sampler.volume.value = -6
  }

  return {
    play(note) {
      ensure()
      // Sampler triggers are silent until samples finish loading.
      // After the user picks Piano, preload() fires the fetch; by the
      // time they hit a key, samples are usually ready.
      sampler!.triggerAttackRelease(note, "2n", toneNow())
    },
    stopAll() {
      sampler?.releaseAll()
    },
    preload() {
      ensure()
    },
  }
}

register("keyboard", "piano", makeKeyboardPiano())
