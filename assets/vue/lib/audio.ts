// Named imports so Vite/Rollup can tree-shake unused Tone modules
// (Analyser, FFT, Players, etc.) out of the lazy `instrument` chunk.
// `import * as Tone from "tone"` pulled the whole namespace and
// defeated tree-shaking. `now` and `start` get aliased so the bare
// names don't shadow other identifiers.
import {
  AmplitudeEnvelope,
  Chorus,
  Delay,
  Destination,
  Distortion,
  FeedbackDelay,
  Filter,
  FMSynth,
  Frequency,
  Gain,
  gainToDb,
  getDestination,
  MembraneSynth,
  MonoSynth,
  Noise,
  NoiseSynth,
  now as toneNow,
  PluckSynth,
  PolySynth,
  Recorder,
  Reverb,
  Sampler,
  start as toneStart,
  Synth,
  type Param,
} from "tone"

// ── Audio context lifecycle ────────────────────────────────────────
// Tone's audio context is created suspended; browsers require a
// user gesture to resume it.

let started = false

export async function ensureStarted(): Promise<void> {
  if (started) return
  await toneStart()
  started = true
}

// Master output volume. Sets `Destination`'s volume in dB —
// every synth in the registry routes through it, so this is a
// single point of control for both local hits and incoming remote
// notes.
//
//   linearGain: 0..1   (0 = silent, 1 = full)
export function setMasterVolume(linearGain: number) {
  const clamped = Math.max(0, Math.min(1, linearGain))
  getDestination().volume.value = clamped === 0 ? -Infinity : gainToDb(clamped)
}

// ── Audio recording ────────────────────────────────────────────────
// Recorder wraps MediaRecorder, so the output MIME type is
// browser-dependent: audio/webm on Chrome/Firefox, audio/mp4 on
// Safari. We don't re-encode — the caller gets whatever the
// browser produced and we pick the filename extension from the
// Blob's `type`.

let recorder: Recorder | null = null

export async function startRecording(): Promise<void> {
  if (recorder) return
  if (!Recorder.supported) {
    console.warn("[mixchamb] Recorder not supported in this browser")
    return
  }
  recorder = new Recorder()
  // The destination is what the speakers hear, so connecting the
  // recorder there captures every instrument routed through the
  // chamber FX bus without us tapping individual synths.
  getDestination().connect(recorder)
  await recorder.start()
  console.info("[mixchamb] recorder started, state:", recorder.state, "mime:", recorder.mimeType)
}

export async function stopRecording(): Promise<Blob | null> {
  if (!recorder) {
    console.warn("[mixchamb] stopRecording called with no active recorder")
    return null
  }
  console.info("[mixchamb] stopping recorder, state before stop:", recorder.state)
  const blob = await recorder.stop()
  console.info("[mixchamb] recorder stopped, blob:", blob?.size, "bytes, type:", blob?.type)
  recorder.dispose()
  recorder = null
  return blob
}

// ── Chamber FX bus ─────────────────────────────────────────────────
// Every instrument routes through this single shared bus before
// hitting the speakers, so chamber-wide effects (reverb / delay /
// the type-of-room character) can be applied uniformly. The chain:
//
//   each instrument → chamberBus → chamberReverb → chamberDelay → destination
//
// Reverb and Delay are both always in the chain; their `wet` values
// switch the actual character on or off per chamber kind (anechoic
// = both wet 0, hall = high reverb wet, echo = high delay wet,
// etc.). This avoids re-routing the graph every time the kind
// changes.

let chamberBus: Gain | null = null
let chamberReverb: Reverb | null = null
let chamberDelay: FeedbackDelay | null = null

// Engine-internal — only `lib/audio/<instrument>.ts` modules call
// this, to route their voices through the shared chamber FX bus.
// Don't reach for it from Vue components.
export function getChamberBus(): Gain {
  if (chamberBus) return chamberBus
  chamberBus = new Gain()
  chamberReverb = new Reverb({ decay: 1, wet: 0 })
  chamberDelay = new FeedbackDelay({
    delayTime: "8n",
    feedback: 0.4,
    wet: 0,
  })
  chamberBus.chain(chamberReverb, chamberDelay, getDestination())
  // Pre-generate the convolution so the first reverb hit isn't a
  // synchronous block at trigger time.
  chamberReverb.generate()
  return chamberBus
}

export type ChamberKind =
  | "vacuum"
  | "anechoic"
  | "room"
  | "live"
  | "hall"
  | "cathedral"
  | "plate"
  | "spring"
  | "echo"

type ChamberPreset = {
  decay: number
  wet: number
  preDelay?: number
  delayWet: number
  delayTime?: string
  feedback?: number
}

// Tuned to evoke each room's archetypal sound. `decay` is the
// reverb's RT60-ish length; `wet` is how loud the reverberant tail
// sits relative to the dry signal. `delayWet` only goes above 0
// for kinds that need an audible discrete echo (`echo`, `spring`).
const CHAMBER_PRESETS: Record<ChamberKind, ChamberPreset> = {
  // Physically impossible — vacuums don't transmit sound — but
  // useful as a "raw signal, no coloration anywhere" mode for
  // hearing instrument voices in their bare form. Sets every
  // chamber-level wet to 0 *and* triggers the instrument-FX
  // bypass below.
  vacuum: { decay: 0.5, wet: 0, delayWet: 0 },
  // Real anechoic chamber: room reflections gone, but the
  // instrument's own signal chain (amp reverb, chorus pedal,
  // cymbal bloom) stays untouched. That matches what an actual
  // anechoic chamber does — it doesn't reach into the
  // instrument's circuit.
  anechoic: { decay: 0.5, wet: 0, delayWet: 0 },
  room: { decay: 0.7, wet: 0.22, delayWet: 0 },
  live: { decay: 1.5, wet: 0.32, delayWet: 0 },
  hall: { decay: 3.0, wet: 0.42, delayWet: 0 },
  cathedral: { decay: 6.0, wet: 0.52, delayWet: 0 },
  plate: { decay: 1.2, wet: 0.4, preDelay: 0.005, delayWet: 0 },
  spring: {
    decay: 0.8,
    wet: 0.32,
    preDelay: 0.015,
    delayWet: 0.12,
    delayTime: "16n",
    feedback: 0.5,
  },
  echo: { decay: 0.3, wet: 0.05, delayWet: 0.4, delayTime: "8n", feedback: 0.5 },
}

// Tracks the chamber kind currently in effect. Engines that create
// internal FX after the kind has been set check this so a node born
// during anechoic mode comes up muted, not at its constructor wet.
let currentChamberKind: ChamberKind = "room"

// Registry of every "internal" FX node — instrument-baked effects
// like the Electric guitar's chorus + reverb or the drums' cymbal
// reverb. Anechoic chambers bypass them all (truly dry); other
// kinds restore each node's original wet level.
type InternalFx = {
  wet: Param<"normalRange">
  originalValue: number
}
const internalFxNodes: InternalFx[] = []

/**
 * Engines call this for every "always-on" effect they ship with —
 * the chorus baked into Electric, the cymbal reverb under drums,
 * etc. The current value of `node.wet` is captured as the
 * original; when the chamber kind is non-anechoic we ramp back to
 * that. Anechoic mode mutes all of them.
 */
// Engine-internal — instrument-specific FX nodes (e.g. drums'
// cymbal reverb) call this so their `wet` param is muted along
// with the rest of the chamber when the user picks "anechoic".
export function registerInternalFx(wetParam: Param<"normalRange">): void {
  const originalValue = wetParam.value
  internalFxNodes.push({ wet: wetParam, originalValue })
  if (currentChamberKind === "vacuum") {
    wetParam.value = 0
  }
}

/**
 * Switches the master chamber FX to the chosen kind. Setting
 * `decay` or `preDelay` regenerates the convolution impulse —
 * happens in-place and is fast enough to be unnoticeable on
 * deliberate switches.
 *
 * Anechoic mode also mutes every registered instrument-internal
 * FX node (Electric guitar's chorus + reverb, drums' cymbal
 * reverb, etc.) so the signal path is genuinely dry. Switching
 * back to any other kind ramps those nodes' wet levels to their
 * originals.
 */
export function setChamberKind(kind: ChamberKind) {
  getChamberBus()
  currentChamberKind = kind
  const preset = CHAMBER_PRESETS[kind]

  if (chamberReverb) {
    if (chamberReverb.decay !== preset.decay) {
      chamberReverb.decay = preset.decay
    }
    if (preset.preDelay !== undefined && chamberReverb.preDelay !== preset.preDelay) {
      chamberReverb.preDelay = preset.preDelay
    }
    chamberReverb.wet.rampTo(preset.wet, 0.1)
  }

  if (chamberDelay) {
    if (preset.delayTime !== undefined) {
      chamberDelay.delayTime.value = preset.delayTime
    }
    if (preset.feedback !== undefined) {
      chamberDelay.feedback.value = preset.feedback
    }
    chamberDelay.wet.rampTo(preset.delayWet, 0.1)
  }

  // Bypass instrument-internal FX in vacuum mode for a truly
  // raw signal. Anechoic *doesn't* trigger this — a real
  // anechoic chamber removes room reflections but leaves the
  // instrument's signal chain (chorus pedal, amp reverb, etc.)
  // alone. Vacuum is the synthetic "no coloration anywhere"
  // mode users can pick for hearing the bare instrument voice.
  const vacuum = kind === "vacuum"
  for (const { wet, originalValue } of internalFxNodes) {
    wet.rampTo(vacuum ? 0 : originalValue, 0.1)
  }
}

// ── Engine registry ────────────────────────────────────────────────
// Each (instrument, style) pair gets its own engine. Engines own
// their Tone synths internally — lazy-init on first play so we
// don't allocate audio nodes for flavors no one picks.
//
// Pads call:    play("drums", "synth", "kick")
// Receive side: play(payload.instrument, payload.style, payload.note)

export interface PlayOptions {
  /**
   * Strum from high string to low string instead of the default
   * low-to-high. Only chord-based engines (guitar) honor this; the
   * rest ignore the field. For real-guitar feel: down = thumb /
   * downstroke, up = fingernail / upstroke.
   */
  reverse?: boolean
  /**
   * Lifecycle phase, used by guitar engines for natural strumming:
   *   - "press":   downstroke + chord rings until released
   *   - "release": stops the held ring + up-stroke re-strike
   *   - undefined: legacy one-shot strum (used by old replay events
   *                and by non-strumming engines)
   */
  phase?: "press" | "release"
  /**
   * Whether the release phase should re-strike the chord in reverse
   * (the up-stroke). Defaults to true. The caller sets this to false
   * for short taps where firing an up-stroke would just sound like
   * a doubled chord — only sustained holds earn the second strum.
   */
  upStrum?: boolean
}

export interface InstrumentEngine {
  /**
   * `octaveOffset` is in octaves, relative to the engine's default
   * voicing. Drums and instruments that already encode the octave
   * in `note` (keyboard, bass) ignore it; chord-based instruments
   * (guitar, pad) use it to transpose all notes in the chord.
   *
   * `opts` is engine-specific behaviour like strum direction. Most
   * engines ignore it; only chord-strumming engines read it.
   */
  play(note: string, octaveOffset?: number, opts?: PlayOptions): void
  stopAll(): void
  /**
   * Optional. Called when a user *selects* this flavor (not every
   * play). Sampled engines override this to start downloading their
   * samples ahead of the first hit so there's no awkward silence.
   */
  preload?(): void
}

const engines = new Map<string, InstrumentEngine>()

// Engine-internal — the per-instrument modules under `lib/audio/`
// call this at module load to wire their factory into the registry.
// `play()` / `stopAll()` / `preload()` then look up the engine by
// `instrument:style` key.
export function register(instrument: string, style: string, engine: InstrumentEngine) {
  engines.set(`${instrument}:${style}`, engine)
}

function getEngine(instrument: string, style: string): InstrumentEngine | undefined {
  return engines.get(`${instrument}:${style}`)
}

export function play(
  instrument: string,
  style: string,
  note: string,
  octaveOffset: number = 0,
  opts?: PlayOptions,
) {
  getEngine(instrument, style)?.play(note, octaveOffset, opts)
}

export function stopAll(instrument: string, style: string) {
  getEngine(instrument, style)?.stopAll()
}

export function preload(instrument: string, style: string) {
  getEngine(instrument, style)?.preload?.()
}

// Engine-internal — chord-based engine modules (guitar, pad) use
// this. Shifts every note in a list by `octaveOffset` octaves.
// Frequency does the math in semitones.
export function transposeNotes(notes: readonly string[], octaveOffset: number): string[] {
  if (octaveOffset === 0) return notes as string[]
  const semitones = octaveOffset * 12
  return notes.map((n) => Frequency(n).transpose(semitones).toNote())
}

// Time between successive strings in a guitar strum, in seconds.
// 0.03s × ~6 notes per chord ≈ 180ms total strum, which reads as a
// real strum (the listener can almost hear individual strings)
// rather than a one-shot chord stab. Real acoustic strums sit in
// the 50-200ms range; we're at the slow end deliberately.
const GUITAR_STRUM_STAGGER = 0.03

// Returns the chord notes ordered for the requested strum direction.
// Down (default) = low to high (thumb/down-stroke); reverse = high
// to low (fingernail/up-stroke).
function strumOrder(notes: readonly string[], reverse: boolean): readonly string[] {
  return reverse ? [...notes].reverse() : notes
}

// Common interface every Tone polyphonic source we use exposes —
// PolySynth and Sampler both speak this. The helper below uses it
// to drive any of the five guitar engines through the same press /
// release / legacy code path.
export type StrumTriggerable = {
  triggerAttack(note: string, time: number): unknown
  triggerRelease(note: string, time: number): unknown
  triggerAttackRelease(note: string, duration: string, time: number): unknown
}

// Per-engine strum state. `held` records the notes that have already
// attacked for each chord; `sessions` holds a session id per chord
// that the press's deferred attacks check before firing — if the
// release runs first, the session is gone and the pending attacks
// no-op. That's how quick taps avoid the "ringing forever" + double-
// attack bugs the previous Tone-scheduled stagger had.
export type StrumState = {
  held: Map<string, string[]>
  sessions: Map<string, number>
}

export function makeStrumState(): StrumState {
  return { held: new Map(), sessions: new Map() }
}

let nextStrumSession = 0

// Engine-internal — guitar/pad engine modules call this. Renders a
// strum at the given lifecycle phase.
//   - press: schedules a low→high down-stroke via setTimeout (so we
//     can cancel via session id), records each attacked note in
//     `state.held` as it fires.
//   - release: invalidates the press session (cancels any pending
//     attacks), releases whatever notes did fire, and optionally
//     plays the up-stroke re-strike if `upStrum` is true.
//   - undefined: a legacy one-shot strum, kept so old replay events
//     keep working.
export function applyStrumPhase(
  voice: StrumTriggerable,
  shifted: readonly string[],
  chordKey: string,
  phase: "press" | "release" | undefined,
  reverse: boolean,
  upStrum: boolean,
  state: StrumState,
  upStrumDuration: string,
  legacyDuration: string,
): void {
  if (phase === "press") {
    const id = ++nextStrumSession
    state.sessions.set(chordKey, id)
    const attackedNotes: string[] = []
    state.held.set(chordKey, attackedNotes)

    const ordered = strumOrder(shifted, false)
    ordered.forEach((note, i) => {
      const fire = () => {
        // If the release ran before this attack got to fire, the
        // session id is stale — bail without attacking.
        if (state.sessions.get(chordKey) !== id) return
        voice.triggerAttack(note, toneNow())
        attackedNotes.push(note)
      }
      if (i === 0) {
        fire()
      } else {
        window.setTimeout(fire, i * GUITAR_STRUM_STAGGER * 1000)
      }
    })
    return
  }
  if (phase === "release") {
    // Invalidate the press session so any pending setTimeouts no-op.
    state.sessions.delete(chordKey)
    // Release the notes that actually attacked. Pending notes never
    // ran, so no voices to release for them.
    const attackedNotes = state.held.get(chordKey)
    if (attackedNotes) {
      const now = toneNow()
      for (const note of attackedNotes) voice.triggerRelease(note, now)
      state.held.delete(chordKey)
    }
    // Up-stroke re-strike (only if the caller asked for it — quick
    // taps skip this so we don't get a "double chord" effect).
    if (upStrum) {
      const upOrder = strumOrder(shifted, true)
      const now = toneNow()
      upOrder.forEach((note, i) => {
        voice.triggerAttackRelease(note, upStrumDuration, now + i * GUITAR_STRUM_STAGGER)
      })
    }
    return
  }
  // Legacy: a single one-shot strum, used by older replay events
  // and by callers that don't track press/release pairs.
  const ordered = strumOrder(shifted, reverse)
  const now = toneNow()
  ordered.forEach((note, i) => {
    voice.triggerAttackRelease(note, legacyDuration, now + i * GUITAR_STRUM_STAGGER)
  })
}

// ── Planning-poker reveal cue ──────────────────────────────────────
// Short ascending arpeggio (C5 E5 G5 C6) timed to land its last
// note around the card-flip moment in PokerBoard.vue. Standalone
// from the per-instrument engines because poker has no instrument
// to register against. The AudioContext is gated by the same gesture
// requirement as music — fail silently if a remote-broadcast reveal
// arrives at a client that hasn't started anything yet (the visual
// suspense still reads as a moment without the chime).
export async function playReveal(): Promise<void> {
  try {
    await ensureStarted()
  } catch {
    return
  }
  const voice = new Synth({
    oscillator: { type: "sine" },
    envelope: { attack: 0.005, decay: 0.12, sustain: 0.2, release: 0.5 },
    volume: -14,
  }).toDestination()
  const start = toneNow()
  voice.triggerAttackRelease("C5", "16n", start)
  voice.triggerAttackRelease("E5", "16n", start + 0.15)
  voice.triggerAttackRelease("G5", "16n", start + 0.3)
  voice.triggerAttackRelease("C6", "8n", start + 0.45)
  // Hang around long enough for the release tail to ring out, then
  // free the voice. setTimeout (not Tone's transport) since this is
  // a one-shot independent of any musical clock.
  setTimeout(() => voice.dispose(), 2500)
}

// ── Retro vote-cast cue ────────────────────────────────────────────
// A single soft "blip" the local voter hears when they cast a vote
// (silent on withdraw — the cue marks the positive action). Quieter
// and shorter than the poker reveal arpeggio so rapid voting doesn't
// turn into a melody. Like playReveal, it's standalone (retro has no
// instrument to register) and gated by the same gesture requirement —
// fails silently if the AudioContext hasn't been unlocked yet.
export async function playVoteBlip(): Promise<void> {
  try {
    await ensureStarted()
  } catch {
    return
  }
  const voice = new Synth({
    oscillator: { type: "triangle" },
    envelope: { attack: 0.004, decay: 0.08, sustain: 0, release: 0.12 },
    volume: -18,
  }).toDestination()
  voice.triggerAttackRelease("A5", "32n", toneNow())
  setTimeout(() => voice.dispose(), 600)
}

// ── Mini-game (Pictionary) cues ────────────────────────────────────
// Standalone one-shots like playReveal / playVoteBlip — no instrument
// to register against, gated by the same gesture requirement, fail
// silently if the AudioContext hasn't been unlocked.

// Bright two-note rise the room hears on any correct guess.
export async function playGuessCorrect(): Promise<void> {
  try {
    await ensureStarted()
  } catch {
    return
  }
  const voice = new Synth({
    oscillator: { type: "triangle" },
    envelope: { attack: 0.004, decay: 0.09, sustain: 0, release: 0.14 },
    volume: -15,
  }).toDestination()
  const start = toneNow()
  voice.triggerAttackRelease("E5", "32n", start)
  voice.triggerAttackRelease("B5", "16n", start + 0.09)
  setTimeout(() => voice.dispose(), 900)
}

// Low descending buzzer when a turn runs out of time.
export async function playTimeUp(): Promise<void> {
  try {
    await ensureStarted()
  } catch {
    return
  }
  const voice = new Synth({
    oscillator: { type: "sawtooth" },
    envelope: { attack: 0.006, decay: 0.2, sustain: 0.1, release: 0.2 },
    volume: -20,
  }).toDestination()
  const start = toneNow()
  voice.triggerAttackRelease("A3", "16n", start)
  voice.triggerAttackRelease("E3", "8n", start + 0.16)
  setTimeout(() => voice.dispose(), 1200)
}

// Celebratory rising arpeggio at game over.
export async function playGameOver(): Promise<void> {
  try {
    await ensureStarted()
  } catch {
    return
  }
  const voice = new Synth({
    oscillator: { type: "sine" },
    envelope: { attack: 0.005, decay: 0.14, sustain: 0.25, release: 0.6 },
    volume: -13,
  }).toDestination()
  const start = toneNow()
  voice.triggerAttackRelease("C5", "16n", start)
  voice.triggerAttackRelease("E5", "16n", start + 0.12)
  voice.triggerAttackRelease("G5", "16n", start + 0.24)
  voice.triggerAttackRelease("C6", "16n", start + 0.36)
  voice.triggerAttackRelease("G5", "16n", start + 0.5)
  voice.triggerAttackRelease("C6", "4n", start + 0.62)
  setTimeout(() => voice.dispose(), 2800)
}

// Drum-kit voicing: the wire format only carries these strings,
// shared between the engine in `lib/audio/drums.ts` and the
// UI pad definitions in `assets/vue/instruments/DrumPad.vue`.
export type DrumName =
  | "kick"
  | "snare"
  | "hihat"
  | "open_hat"
  | "hihat_pedal"
  | "crash"
  | "ride"
  | "tom_high"
  | "tom_mid"
  | "tom_floor"

// The drum engines themselves live in `lib/audio/drums.ts`; they
// register with the engine map there as a side effect of being
// imported by DrumPad.vue. Vite emits a separate chunk for the
// drums module so users who never open DrumPad never download
// MembraneSynth / NoiseSynth / MetalSynth setup code.

export type ChordName = "C" | "D" | "E" | "F" | "G" | "A" | "Am" | "Dm" | "Em" | "B7" | "A7" | "D7"

export const CHORDS: Record<ChordName, string[]> = {
  C: ["C3", "E3", "G3", "C4", "E4"],
  D: ["D3", "A3", "D4", "F#4"],
  E: ["E2", "B2", "E3", "G#3", "B3", "E4"],
  F: ["F2", "C3", "F3", "A3", "C4", "F4"],
  G: ["G2", "B2", "D3", "G3", "B3", "G4"],
  A: ["A2", "E3", "A3", "C#4", "E4"],
  Am: ["A2", "E3", "A3", "C4", "E4"],
  Dm: ["D3", "A3", "D4", "F4"],
  Em: ["E2", "B2", "E3", "G3", "B3", "E4"],
  B7: ["B2", "D#3", "A3", "B3", "D#4", "F#4"],
  A7: ["A2", "E3", "G3", "C#4", "E4"],
  D7: ["D3", "A3", "C4", "F#4"],
}
