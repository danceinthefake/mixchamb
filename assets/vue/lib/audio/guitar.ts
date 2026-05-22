// Guitar engines — Synth / Pluck (disabled) / Electric / Rock / Nylon
// / Acoustic / Mandolin. Strums via the shared `applyStrumPhase`
// helper in audio.ts. Side-effect module: importing from GuitarPad.vue
// registers every flavor into audio.ts's registry.

import {
  AmplitudeEnvelope,
  Chorus,
  Delay,
  Distortion,
  Filter,
  Frequency,
  Gain,
  MonoSynth,
  Noise,
  PolySynth,
  Reverb,
  Sampler,
  Synth,
  now as toneNow,
} from "tone"
import {
  applyStrumPhase,
  getChamberBus,
  makeStrumState,
  register,
  registerInternalFx,
  transposeNotes,
  type ChordName,
  CHORDS,
  type InstrumentEngine,
} from "../audio"

function makeGuitarSynth(): InstrumentEngine {
  let poly: PolySynth | null = null
  const state = makeStrumState()

  function ensure() {
    if (poly) return
    poly = new PolySynth(MonoSynth, {
      oscillator: { type: "sawtooth" },
      // Sustain != 0 so the chord can ring while the user holds.
      // Without this, voices fade as soon as the attack-decay finishes
      // and "hold to sustain" feels broken.
      envelope: { attack: 0.002, decay: 0.3, sustain: 0.4, release: 1.0 },
      filter: { type: "lowpass", frequency: 3000, Q: 2 },
      filterEnvelope: {
        attack: 0.001,
        decay: 0.4,
        sustain: 0.4,
        release: 1.0,
        baseFrequency: 200,
        octaves: 3,
      },
    }).connect(getChamberBus())
    poly.volume.value = -8
  }

  return {
    play(chord, octaveOffset = 0, opts) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      applyStrumPhase(
        poly!,
        transposeNotes(notes, octaveOffset),
        `${chord}@${octaveOffset}`,
        opts?.phase,
        opts?.reverse ?? false,
        opts?.upStrum !== false,
        state,
        "8n",
        "2n",
      )
    },
    stopAll() {
      poly?.releaseAll()
      state.held.clear()
      state.sessions.clear()
    },
  }
}

register("guitar", "synth", makeGuitarSynth())

// ── Guitar : Pluck (DISABLED) ──────────────────────────────────────
// Hand-rolled Karplus-Strong (delay + filter + feedback loop driven
// by a noise burst). It worked algorithmically but the resulting
// tone was always slightly fatiguing on headphones — the natural
// resonance peaks of the algorithm sit right at the ear and even
// after taming gain / cutoff / feedback, the character stayed
// uncomfortable at length. Replaced by Electric / Rock / Nylon
// below; the function is preserved (commented out) in case we
// want to revisit the algorithm later.
/*
function makeGuitarPluck(): InstrumentEngine {
  let output: Gain | null = null
  let activeStrings: { dispose: () => void }[] = []

  function ensure() {
    if (output) return
    output = new Gain(0.02).connect(getChamberBus())
  }

  function pluckNote(note: string, when: number) {
    ensure()
    const freq = Frequency(note).toFrequency()
    const delayTime = 1 / freq
    const delay = new Delay(delayTime, 0.05)
    const filter = new Filter(1800, "lowpass")
    const feedback = new Gain(0.97)
    delay.connect(filter)
    filter.connect(feedback)
    feedback.connect(delay)
    filter.connect(output!)
    const noise = new Noise("pink")
    const env = new AmplitudeEnvelope({
      attack: 0.004, decay: 0.005, sustain: 0, release: 0.001,
    })
    noise.connect(env)
    env.connect(delay)
    noise.start(when)
    env.triggerAttackRelease(0.005, when)
    noise.stop(when + 0.05)
    const nodes = [noise, env, delay, filter, feedback]
    const string = {
      dispose() {
        for (const n of nodes) { try { n.dispose() } catch {} }
      },
    }
    activeStrings.push(string)
    setTimeout(() => {
      string.dispose()
      activeStrings = activeStrings.filter((s) => s !== string)
    }, 2500)
  }

  return {
    play(chord, octaveOffset = 0) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      const now = toneNow()
      const shifted = transposeNotes(notes, octaveOffset)
      shifted.forEach((note, i) => {
        pluckNote(note, now + i * 0.012)
      })
    },
    stopAll() {
      const strings = activeStrings.slice()
      activeStrings = []
      for (const s of strings) s.dispose()
    },
  }
}
register("guitar", "pluck", makeGuitarPluck())
*/

// ── Guitar : Electric (clean) ──────────────────────────────────────
// Bright, sustained clean electric guitar — triangle PolySynth fed
// through a modest chorus + a touch of room reverb so the tone has
// the airy width of a clean amp without the harshness Karplus-Strong
// produced. Sits comfortably on headphones at length.

function makeGuitarElectric(): InstrumentEngine {
  let poly: PolySynth | null = null
  let chorus: Chorus | null = null
  let reverb: Reverb | null = null
  const state = makeStrumState()

  function ensure() {
    if (poly) return
    chorus = new Chorus({
      frequency: 1.4,
      delayTime: 3,
      depth: 0.6,
      wet: 0.45,
    }).start()
    reverb = new Reverb({ decay: 1.2, wet: 0.18 })
    poly = new PolySynth(Synth, {
      oscillator: { type: "triangle" },
      // Already had sustain 0.4; works well with hold-to-ring.
      envelope: { attack: 0.004, decay: 0.5, sustain: 0.4, release: 1.4 },
    })
    poly.chain(chorus, reverb, getChamberBus())
    // Both bypass when chamber is anechoic so Electric falls back
    // to a plain triangle synth in dry mode.
    registerInternalFx(chorus.wet)
    registerInternalFx(reverb.wet)
    poly.volume.value = -10
  }

  return {
    play(chord, octaveOffset = 0, opts) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      applyStrumPhase(
        poly!,
        transposeNotes(notes, octaveOffset),
        `${chord}@${octaveOffset}`,
        opts?.phase,
        opts?.reverse ?? false,
        opts?.upStrum !== false,
        state,
        "8n",
        "2n",
      )
    },
    stopAll() {
      poly?.releaseAll()
      state.held.clear()
      state.sessions.clear()
    },
  }
}

register("guitar", "electric", makeGuitarElectric())

// ── Guitar : Rock (overdriven) ─────────────────────────────────────
// Sawtooth PolySynth with two slightly-detuned voices through a
// soft Distortion. Reads as a crunchy electric for rock chord
// strumming. Distortion adds gain, so output sits ~6 dB lower than
// Electric to keep flavors level-matched.

function makeGuitarRock(): InstrumentEngine {
  let poly: PolySynth | null = null
  let distortion: Distortion | null = null
  const state = makeStrumState()

  function ensure() {
    if (poly) return
    distortion = new Distortion({ distortion: 0.35, wet: 0.7 }).connect(getChamberBus())
    poly = new PolySynth(MonoSynth, {
      oscillator: { type: "fatsawtooth" as const, count: 2, spread: 18 },
      envelope: { attack: 0.005, decay: 0.4, sustain: 0.5, release: 1.0 },
      filter: { type: "lowpass", frequency: 2400, Q: 1.5 },
      filterEnvelope: {
        attack: 0.001,
        decay: 0.4,
        sustain: 0.4,
        release: 1.0,
        baseFrequency: 200,
        octaves: 2,
      },
    })
    poly.connect(distortion)
    poly.volume.value = -16
  }

  return {
    play(chord, octaveOffset = 0, opts) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      applyStrumPhase(
        poly!,
        transposeNotes(notes, octaveOffset),
        `${chord}@${octaveOffset}`,
        opts?.phase,
        opts?.reverse ?? false,
        opts?.upStrum !== false,
        state,
        "8n",
        "2n",
      )
    },
    stopAll() {
      poly?.releaseAll()
      state.held.clear()
      state.sessions.clear()
    },
  }
}

register("guitar", "rock", makeGuitarRock())

// ── Guitar : Nylon (sampled, classical) ────────────────────────────
// Sampler with classical / nylon-string guitar samples. Same
// CDN pipeline as the Acoustic flavor; the nylon sample bank reads
// softer and warmer (gut-string body, no metallic snap) which makes
// it the calmest of the five flavors.

function makeGuitarNylon(): InstrumentEngine {
  let sampler: Sampler | null = null
  const state = makeStrumState()

  function ensure() {
    if (sampler) return
    sampler = new Sampler({
      urls: {
        A2: "A2.mp3",
        A3: "A3.mp3",
        A4: "A4.mp3",
      },
      release: 0.8,
      baseUrl: "https://nbrosowsky.github.io/tonejs-instruments/samples/guitar-nylon/",
    }).connect(getChamberBus())
    sampler.volume.value = -4
  }

  return {
    play(chord, octaveOffset = 0, opts) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      applyStrumPhase(
        sampler!,
        transposeNotes(notes, octaveOffset),
        `${chord}@${octaveOffset}`,
        opts?.phase,
        opts?.reverse ?? false,
        opts?.upStrum !== false,
        state,
        "4n",
        "2n",
      )
    },
    stopAll() {
      sampler?.releaseAll()
      state.held.clear()
      state.sessions.clear()
    },
    preload() {
      ensure()
    },
  }
}

register("guitar", "nylon", makeGuitarNylon())

// ── Guitar : Acoustic (sampled) ────────────────────────────────────
// Real acoustic-guitar samples streamed from the tonejs-instruments
// CDN. Three anchor samples (A2 / A3 / A4) cover our chord range
// from E2 up through G4; Sampler pitch-shifts between them.

function makeGuitarAcoustic(): InstrumentEngine {
  let sampler: Sampler | null = null
  const state = makeStrumState()

  function ensure() {
    if (sampler) return
    sampler = new Sampler({
      urls: {
        A2: "A2.mp3",
        A3: "A3.mp3",
        A4: "A4.mp3",
      },
      release: 0.5,
      baseUrl: "https://nbrosowsky.github.io/tonejs-instruments/samples/guitar-acoustic/",
    }).connect(getChamberBus())
    sampler.volume.value = -4
  }

  return {
    play(chord, octaveOffset = 0, opts) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      applyStrumPhase(
        sampler!,
        transposeNotes(notes, octaveOffset),
        `${chord}@${octaveOffset}`,
        opts?.phase,
        opts?.reverse ?? false,
        opts?.upStrum !== false,
        state,
        "4n",
        "2n",
      )
    },
    stopAll() {
      sampler?.releaseAll()
      state.held.clear()
      state.sessions.clear()
    },
    preload() {
      ensure()
    },
  }
}

register("guitar", "acoustic", makeGuitarAcoustic())

// ── Guitar : Mandolin ──────────────────────────────────────────────
// Bright plucky chord-strummer for the dangdut-flavored chamber.
// Synthesized rather than sampled: fatsawtooth PolySynth with a
// sharp short envelope (mandolin staccato), through a faster Chorus
// to emulate the shimmer of mandolin's paired (course) strings.
//
// Real mandolins sit about an octave above a guitar (tuning is
// GDAE, like a violin). Rather than make players hunt for the
// right octave_offset on the pad, we bake +1 octave into the
// engine — so picking a chord here lands in the mandolin range
// automatically while the user's octave control still adjusts
// from there.

function makeGuitarMandolin(): InstrumentEngine {
  let poly: PolySynth | null = null
  let chorus: Chorus | null = null
  const state = makeStrumState()

  function ensure() {
    if (poly) return
    chorus = new Chorus({
      frequency: 4.5,
      delayTime: 1.5,
      depth: 0.4,
      wet: 0.4,
    }).start()
    poly = new PolySynth(Synth, {
      oscillator: { type: "fatsawtooth" as const, count: 2, spread: 14 },
      envelope: { attack: 0.002, decay: 0.25, sustain: 0.05, release: 0.6 },
    })
    poly.chain(chorus, getChamberBus())
    registerInternalFx(chorus.wet)
    poly.volume.value = -12
  }

  return {
    play(chord, octaveOffset = 0, opts) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      applyStrumPhase(
        poly!,
        transposeNotes(notes, octaveOffset + 1),
        `${chord}@${octaveOffset}`,
        opts?.phase,
        opts?.reverse ?? false,
        opts?.upStrum !== false,
        state,
        "16n",
        "2n",
      )
    },
    stopAll() {
      poly?.releaseAll()
      state.held.clear()
      state.sessions.clear()
    },
  }
}

register("guitar", "mandolin", makeGuitarMandolin())
