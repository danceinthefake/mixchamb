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

import { onUnmounted, ref, toRef } from "vue"
import { useLiveVue } from "live_vue"
import "@/lib/audio/suling"
import { ensureStarted, play, stopAll, preload } from "@/lib/audio"
import { useInstrumentFlash, useInstrumentKeyboard } from "@/lib/instrument"

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

const noteSet = new Set(notes.map((n) => n.note))

const {
  local: flashing,
  remote: remoteFlashing,
  flash,
} = useInstrumentFlash<string>({
  remoteHit: toRef(props, "remoteHit"),
  instrument: "suling",
  duration: "medium",
  extractRemote: (hit) => (noteSet.has(hit.note) ? hit.note : null),
})

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

useInstrumentKeyboard({
  findByKey: (k) => notes.find((n) => n.key === k),
  onDown: (n) => hit(n.note),
})

onUnmounted(() => stopAll("suling", style.value))
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
        :aria-pressed="style === s.id"
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
        class="pointer-events-none absolute inset-y-0 left-0 w-6 z-10 bg-gradient-to-r from-background to-transparent md:hidden"
      ></div>
      <div
        class="pointer-events-none absolute inset-y-0 right-0 w-6 z-10 bg-gradient-to-l from-background to-transparent md:hidden"
      ></div>

      <div class="overflow-x-auto px-2">
        <div class="grid grid-cols-12 gap-1.5 sm:gap-2" style="min-width: 720px">
          <button
            v-for="n in notes"
            :key="n.note"
            @pointerdown.prevent="hit(n.note)"
            :aria-label="`${n.label}${n.key ? ' (press ' + n.key + ')' : ''}`"
            :class="[
              'pad-touch touch-manipulation rounded-lg border bg-card flex flex-col items-center justify-center gap-1 py-6 transition-all active:scale-95 hover:bg-accent',
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
