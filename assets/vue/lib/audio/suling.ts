// Suling engine — Indonesian bamboo flute, three flavors (Synth /
// Bamboo sampled / Sweet). Side-effect module: importing from
// SulingPad.vue registers all three into audio.ts's registry.

import { Chorus, MonoSynth, PolySynth, Sampler, Synth, now as toneNow } from "tone"
import { getChamberBus, register, registerInternalFx, type InstrumentEngine } from "../audio"

// ── Suling (Indonesian bamboo flute) ───────────────────────────────
// Single-note melodic instrument — monophonic (one note rings at a
// time), each note triggers triggerAttackRelease for a short
// melodic phrase. Three flavors:
//
//   - Synth: pure sine + slow vibrato. Cleanest.
//   - Bamboo: sampled flute from the tonejs-instruments CDN. Closest
//     to a real bamboo flute, including the breath texture.
//   - Sweet: triangle PolySynth + chorus + slow attack. Soft + airy.

function makeSulingSynth(): InstrumentEngine {
  let synth: MonoSynth | null = null

  function ensure() {
    if (synth) return
    synth = new MonoSynth({
      oscillator: { type: "sine" },
      envelope: { attack: 0.06, decay: 0.2, sustain: 0.7, release: 0.4 },
      filter: { type: "lowpass", frequency: 2500, Q: 1 },
      filterEnvelope: {
        attack: 0.06,
        decay: 0.2,
        sustain: 0.5,
        release: 0.4,
        baseFrequency: 800,
        octaves: 2,
      },
    }).connect(getChamberBus())
    synth.volume.value = -10
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

register("suling", "synth", makeSulingSynth())

function makeSulingBamboo(): InstrumentEngine {
  let sampler: Sampler | null = null

  function ensure() {
    if (sampler) return
    sampler = new Sampler({
      urls: {
        A4: "A4.mp3",
        A5: "A5.mp3",
        A6: "A6.mp3",
      },
      release: 0.5,
      baseUrl: "https://nbrosowsky.github.io/tonejs-instruments/samples/flute/",
    }).connect(getChamberBus())
    sampler.volume.value = -6
  }

  return {
    play(note) {
      ensure()
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

register("suling", "bamboo", makeSulingBamboo())

function makeSulingSweet(): InstrumentEngine {
  let poly: PolySynth | null = null
  let chorus: Chorus | null = null

  function ensure() {
    if (poly) return
    chorus = new Chorus({
      frequency: 1.2,
      delayTime: 4,
      depth: 0.5,
      wet: 0.4,
    }).start()
    poly = new PolySynth(Synth, {
      oscillator: { type: "triangle" },
      envelope: { attack: 0.15, decay: 0.3, sustain: 0.6, release: 1.0 },
    })
    poly.chain(chorus, getChamberBus())
    poly.volume.value = -10
    registerInternalFx(chorus.wet)
  }

  return {
    play(note) {
      ensure()
      poly!.triggerAttackRelease(note, "2n", toneNow())
    },
    stopAll() {
      poly?.releaseAll()
    },
  }
}

register("suling", "sweet", makeSulingSweet())
