// Kendang engine — Indonesian two-headed hand drum, two flavors
// (Synth / Wood). Six tones: dang / tut / dut / tak / tung / pak.
// Side-effect module: importing from KendangPad.vue registers both
// flavors into audio.ts's registry.

import { Filter, MembraneSynth, NoiseSynth, now as toneNow } from "tone"
import { getChamberBus, register, type InstrumentEngine } from "../audio"

// ── Kendang (Indonesian two-headed hand drum) ──────────────────────
// Six distinct tones — the percussive backbone of dangdut. The two
// most iconic are Dang (low boom from the larger head) and Dut (high
// sharp from the smaller head); together with the slap variants
// they cover the rhythmic vocabulary.
//
//   dang  open hit on the larger head     low boom, A1
//   tut   open hit on smaller head        mid-low, A2
//   dut   sharp hit on smaller head       high, E4
//   tak   slap (open palm, both heads)    bright noise burst
//   tung  open hit, big head, looser      mid-high, E2
//   pak   closed slap                     dampened high noise

export type KendangName = "dang" | "tut" | "dut" | "tak" | "tung" | "pak"

function makeKendang(opts: {
  dang: { pitch: string; pitchDecay: number; decay: number }
  tut: { pitch: string; pitchDecay: number; decay: number }
  dut: { pitch: string; decay: number }
  tung: { pitch: string; decay: number }
  // Centre frequency (Hz) of the bandpass we run the slap noise
  // through. Lower = more "skin", higher = more "snap".
  takBand: number
  pakBand: number
  takVolume: number
  pakVolume: number
}): InstrumentEngine {
  let dang: MembraneSynth | null = null
  let tut: MembraneSynth | null = null
  let dut: MembraneSynth | null = null
  let tung: MembraneSynth | null = null
  let tak: NoiseSynth | null = null
  let pak: NoiseSynth | null = null
  let takFilter: Filter | null = null
  let pakFilter: Filter | null = null

  const lastScheduled: Record<KendangName, number> = {
    dang: 0,
    tut: 0,
    dut: 0,
    tak: 0,
    tung: 0,
    pak: 0,
  }

  function ensure() {
    if (dang) return

    // Membrane voices: original octaves restored — the user
    // preferred the boomier kick-style swoop over the dampened
    // "talking-drum" reshape (which felt too polite).
    dang = new MembraneSynth({
      pitchDecay: opts.dang.pitchDecay,
      octaves: 5,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: opts.dang.decay, sustain: 0, release: 0.5 },
    }).connect(getChamberBus())

    tut = new MembraneSynth({
      pitchDecay: opts.tut.pitchDecay,
      octaves: 4,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: opts.tut.decay, sustain: 0, release: 0.4 },
    }).connect(getChamberBus())

    dut = new MembraneSynth({
      pitchDecay: 0.02,
      octaves: 3,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: opts.dut.decay, sustain: 0, release: 0.2 },
    }).connect(getChamberBus())

    tung = new MembraneSynth({
      pitchDecay: 0.04,
      octaves: 4,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: opts.tung.decay, sustain: 0, release: 0.4 },
    }).connect(getChamberBus())

    // Slap bandpass kept — pink-noise-through-bandpass landed the
    // palm-on-skin character the user confirmed worked on Wood.
    takFilter = new Filter({
      type: "bandpass",
      frequency: opts.takBand,
      Q: 1.6,
    }).connect(getChamberBus())
    tak = new NoiseSynth({
      noise: { type: "pink" },
      envelope: { attack: 0.001, decay: 0.08, sustain: 0 },
    }).connect(takFilter)
    tak.volume.value = opts.takVolume

    pakFilter = new Filter({
      type: "bandpass",
      frequency: opts.pakBand,
      Q: 2,
    }).connect(getChamberBus())
    pak = new NoiseSynth({
      noise: { type: "pink" },
      envelope: { attack: 0.001, decay: 0.04, sustain: 0 },
    }).connect(pakFilter)
    pak.volume.value = opts.pakVolume
  }

  function schedule(name: KendangName): number {
    const candidate = toneNow()
    const when = Math.max(candidate, lastScheduled[name] + 0.001)
    lastScheduled[name] = when
    return when
  }

  return {
    play(note) {
      const name = note as KendangName
      ensure()
      const when = schedule(name)
      switch (name) {
        case "dang":
          dang!.triggerAttackRelease(opts.dang.pitch, "8n", when)
          break
        case "tut":
          tut!.triggerAttackRelease(opts.tut.pitch, "8n", when)
          break
        case "dut":
          dut!.triggerAttackRelease(opts.dut.pitch, "16n", when)
          break
        case "tung":
          tung!.triggerAttackRelease(opts.tung.pitch, "8n", when)
          break
        case "tak":
          tak!.triggerAttackRelease("16n", when)
          break
        case "pak":
          pak!.triggerAttackRelease("32n", when)
          break
      }
    },
    stopAll() {},
  }
}

register(
  "kendang",
  "synth",
  makeKendang({
    dang: { pitch: "A1", pitchDecay: 0.05, decay: 0.5 },
    tut: { pitch: "A2", pitchDecay: 0.04, decay: 0.4 },
    dut: { pitch: "E4", decay: 0.15 },
    tung: { pitch: "E2", decay: 0.35 },
    takBand: 1100,
    pakBand: 900,
    takVolume: 18,
    pakVolume: 16,
  }),
)

// "Wood" preset: lower slap band so Tak/Pak read as palm-on-skin
// rather than fingertip-on-rim. Slap volumes pushed hard since the
// bandpass strips out a lot of the noise burst's broadband energy.
register(
  "kendang",
  "wood",
  makeKendang({
    dang: { pitch: "G1", pitchDecay: 0.07, decay: 0.65 },
    tut: { pitch: "G2", pitchDecay: 0.06, decay: 0.55 },
    dut: { pitch: "D4", decay: 0.2 },
    tung: { pitch: "D2", decay: 0.45 },
    takBand: 850,
    pakBand: 700,
    takVolume: 22,
    pakVolume: 20,
  }),
)
