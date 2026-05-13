<script setup lang="ts">
// Suling — Indonesian bamboo flute. Monophonic, one note at a time.
// Single-octave row of buttons (chromatic C5–B5), played either by
// click or via the keyboard cluster — same vbn-area mapping as the
// other pads so two-handed play stays on home position.
//
// Three flavors:
//   - Synth: clean sine MonoSynth with envelope shape mimicking
//     a soft flute attack.
//   - Bamboo: real flute samples streamed from the tonejs-
//     instruments CDN.
//   - Sweet: triangle PolySynth + chorus, soft and airy.

import { onMounted, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import { ensureStarted, play, stopAll, preload } from "@/lib/audio"
import { FLASH_MS, REMOTE_FLASH_DELTA_MS } from "@/lib/motion"
import { isTypingInForm } from "@/lib/utils"

const props = defineProps<{
  remoteHit: { instrument: string; note: string; t: number } | null
}>()

const live = useLiveVue()

type SulingStyle = "synth" | "bamboo" | "sweet"
type StyleOption = { id: SulingStyle; label: string }

const styles: StyleOption[] = [
  { id: "synth", label: "Synth" },
  { id: "bamboo", label: "Bamboo" },
  { id: "sweet", label: "Sweet" },
]

const style = ref<SulingStyle>("synth")

// Twelve chromatic notes, one octave. Suling is melodic / soloistic
// in dangdut; one octave covers most lines without overwhelming the
// user with a giant keyboard.
type Note = { note: string; label: string; key: string }

const notes: Note[] = [
  { note: "C5", label: "C", key: "r" },
  { note: "C#5", label: "C#", key: "5" },
  { note: "D5", label: "D", key: "t" },
  { note: "D#5", label: "D#", key: "6" },
  { note: "E5", label: "E", key: "y" },
  { note: "F5", label: "F", key: "u" },
  { note: "F#5", label: "F#", key: "8" },
  { note: "G5", label: "G", key: "i" },
  { note: "G#5", label: "G#", key: "9" },
  { note: "A5", label: "A", key: "f" },
  { note: "A#5", label: "A#", key: "g" },
  { note: "B5", label: "B", key: "h" },
]

const flashing = ref<string | null>(null)
const remoteFlashing = ref<string | null>(null)
let flashTimer: number | null = null
let remoteFlashTimer: number | null = null

function flash(note: string) {
  flashing.value = note
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  flashTimer = window.setTimeout(() => (flashing.value = null), FLASH_MS.medium)
}

function flashRemote(note: string) {
  remoteFlashing.value = note
  if (remoteFlashTimer !== null) window.clearTimeout(remoteFlashTimer)
  remoteFlashTimer = window.setTimeout(
    () => (remoteFlashing.value = null),
    FLASH_MS.medium + REMOTE_FLASH_DELTA_MS,
  )
}

const noteSet = new Set(notes.map((n) => n.note))

watch(
  () => props.remoteHit,
  (hit) => {
    if (!hit || hit.instrument !== "suling") return
    if (noteSet.has(hit.note)) flashRemote(hit.note)
  },
)

async function hit(note: string) {
  await ensureStarted()
  play("suling", style.value, note)
  flash(note)
  live.pushEvent("note", { instrument: "suling", style: style.value, note })
}

function selectStyle(id: SulingStyle) {
  if (id === style.value) return
  stopAll("suling", style.value)
  style.value = id
  preload("suling", id)
}

function onKey(event: KeyboardEvent) {
  if (event.repeat) return
  if (isTypingInForm(event)) return
  const n = notes.find((x) => x.key === event.key)
  if (n) {
    event.preventDefault()
    hit(n.note)
  }
}

let controller: AbortController | null = null

onMounted(() => {
  controller = new AbortController()
  window.addEventListener("keydown", onKey, { signal: controller.signal })
})

onUnmounted(() => {
  controller?.abort()
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  if (remoteFlashTimer !== null) window.clearTimeout(remoteFlashTimer)
  stopAll("suling", style.value)
})
</script>

<template>
  <div class="space-y-4">
    <!-- Style selector -->
    <div class="flex items-center gap-1">
      <span class="text-xs uppercase tracking-wider text-muted-foreground mr-2">Style</span>
      <button
        v-for="s in styles"
        :key="s.id"
        @click="selectStyle(s.id)"
        :class="[
          'px-3 py-1 text-xs rounded-md border transition-colors',
          style === s.id
            ? 'bg-accent-suling text-background border-accent-suling'
            : 'bg-card hover:bg-accent text-muted-foreground border-input',
        ]"
      >
        {{ s.label }}
      </button>
    </div>

    <!-- Notes row. Black keys (C# / D# / F# / G# / A#) styled darker to
         visually distinguish from naturals, like a flute fingering chart.
         Wrapped in a horizontal scroller with min-width so each note
         button stays large enough to thumb on mobile (≥50 px). -->
    <div class="relative -mx-2">
      <!-- Scroll edge fades on small screens, like KeyboardPad. -->
      <div
        class="pointer-events-none absolute inset-y-0 left-0 w-6 z-10 bg-gradient-to-r from-background to-transparent sm:hidden"
      ></div>
      <div
        class="pointer-events-none absolute inset-y-0 right-0 w-6 z-10 bg-gradient-to-l from-background to-transparent sm:hidden"
      ></div>

      <div class="overflow-x-auto px-2">
        <div class="grid grid-cols-12 gap-1.5 sm:gap-2" style="min-width: 720px">
          <button
            v-for="n in notes"
            :key="n.note"
            @pointerdown.prevent="hit(n.note)"
            :class="[
              'rounded-md border bg-card flex flex-col items-center justify-center gap-1 py-6 select-none transition-all active:scale-95 hover:bg-accent touch-manipulation',
              n.label.includes('#') && 'bg-muted',
              flashing === n.note && 'ring-2 ring-accent-suling scale-95 glow-suling',
              remoteFlashing === n.note && flashing !== n.note && 'ring-2 ring-orange-400',
            ]"
          >
            <div class="text-sm font-semibold">{{ n.label }}</div>
            <kbd
              class="hidden sm:inline-block text-[10px] px-1 py-0.5 rounded bg-muted text-muted-foreground font-mono"
            >
              {{ n.key }}
            </kbd>
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
