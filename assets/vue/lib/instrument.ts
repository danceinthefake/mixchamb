import { onMounted, onUnmounted, ref, watch, type Ref } from "vue"
import { FLASH_MS, REMOTE_FLASH_DELTA_MS } from "./motion"
import { isTypingInForm } from "./utils"

// Wire-level shape of a remote-hit prop. Every instrument component
// declares the same prop, so the type lives here once.
export type RemoteHit = { instrument: string; note: string; t: number } | null

// Flash state for an instrument: a `local` ref that lights up the
// pad the *local* user tapped, and a `remote` ref that lights up
// when another player taps the same thing. Generic over the local-
// flash key type (L) and the remote-flash key type (R). They're
// the same string in most instruments; DrumPad is the outlier —
// it uses pad ids locally (so two crash-pads don't flash each
// other on a local tap) and drum names for remote hits (because
// the wire format only carries the drum, not the pad id).
//
// Remote flash auto-fires from a `watch` on `remoteHit`; the
// `extractRemote` callback decides which remote hits count for
// this instrument (return null to skip — used by DrumPad to
// filter out non-drum names that arrive via the same prop).
export function useInstrumentFlash<L, R = L>(opts: {
  remoteHit: Ref<RemoteHit>
  instrument: string
  extractRemote?: (hit: NonNullable<RemoteHit>) => R | null
  /** Visual flash duration token; matches the sound's tail. */
  duration?: keyof typeof FLASH_MS
}) {
  const local = ref<L | null>(null) as Ref<L | null>
  const remote = ref<R | null>(null) as Ref<R | null>
  let localTimer: number | null = null
  let remoteTimer: number | null = null

  const localMs = FLASH_MS[opts.duration ?? "tight"]
  const remoteMs = localMs + REMOTE_FLASH_DELTA_MS

  function flash(key: L) {
    local.value = key
    if (localTimer !== null) window.clearTimeout(localTimer)
    localTimer = window.setTimeout(() => {
      local.value = null
    }, localMs)
  }

  function flashRemote(key: R) {
    remote.value = key
    if (remoteTimer !== null) window.clearTimeout(remoteTimer)
    remoteTimer = window.setTimeout(() => {
      remote.value = null
    }, remoteMs)
  }

  watch(
    () => opts.remoteHit.value,
    (hit) => {
      if (!hit || hit.instrument !== opts.instrument) return
      const key = opts.extractRemote ? opts.extractRemote(hit) : (hit.note as unknown as R)
      if (key !== null) flashRemote(key)
    },
  )

  onUnmounted(() => {
    if (localTimer !== null) window.clearTimeout(localTimer)
    if (remoteTimer !== null) window.clearTimeout(remoteTimer)
  })

  return { local, remote, flash, flashRemote }
}

// Window-level QWERTY → pad mapping. Every instrument wires up the
// same shape: ignore key-repeat (so holding a key isn't a tremolo),
// ignore typing-in-form (so the alias editor and chamber-title
// inputs don't double as a piano), find the item that owns the
// pressed key, fire the trigger. GuitarPad needs both keydown and
// keyup because chords are held-and-released; everyone else only
// uses keydown.
export function useInstrumentKeyboard<T>(opts: {
  findByKey: (key: string) => T | undefined
  onDown: (item: T) => void
  onUp?: (item: T) => void
}) {
  let controller: AbortController | null = null

  onMounted(() => {
    controller = new AbortController()
    const signal = controller.signal

    window.addEventListener(
      "keydown",
      (event) => {
        if (event.repeat) return
        if (isTypingInForm(event)) return
        const item = opts.findByKey(event.key)
        if (item !== undefined) {
          event.preventDefault()
          opts.onDown(item)
        }
      },
      { signal },
    )

    if (opts.onUp) {
      const onUp = opts.onUp
      window.addEventListener(
        "keyup",
        (event) => {
          if (isTypingInForm(event)) return
          const item = opts.findByKey(event.key)
          if (item !== undefined) {
            event.preventDefault()
            onUp(item)
          }
        },
        { signal },
      )
    }
  })

  onUnmounted(() => {
    controller?.abort()
  })
}
