<script setup lang="ts">
// Bass pad — eight notes from C2 up to C3 plus a Style selector.
// Click a note or press 1–8.
//
//   - Synth: punchy sawtooth MonoSynth with a sweeping filter
//   - Sub: pure sine sub-bass for deep low-end
//   - Slap: bandpass-filtered square for funky slap-bass feel
//
// Bass is monophonic; one note at a time. Local play + push;
// remote audio goes through Studio.vue's receiver.

import { onMounted, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import { ensureStarted, play, stopAll } from "@/lib/audio"

const props = defineProps<{
  remoteHit: { instrument: string; note: string; t: number } | null
}>()

const live = useLiveVue()

type BassStyle = "synth" | "sub" | "slap"
type StyleOption = { id: BassStyle; label: string }

const styles: StyleOption[] = [
  { id: "synth", label: "Synth" },
  { id: "sub", label: "Sub" },
  { id: "slap", label: "Slap" },
]

const style = ref<BassStyle>("synth")

type BassNote = { note: string; label: string; key: string }

// C major scale, one octave starting at C2. Comfortable bass-line range.
const notes: BassNote[] = [
  { note: "C2", label: "C", key: "1" },
  { note: "D2", label: "D", key: "2" },
  { note: "E2", label: "E", key: "3" },
  { note: "F2", label: "F", key: "4" },
  { note: "G2", label: "G", key: "5" },
  { note: "A2", label: "A", key: "6" },
  { note: "B2", label: "B", key: "7" },
  { note: "C3", label: "C", key: "8" },
]

const flashing = ref<string | null>(null)
const remoteFlashing = ref<string | null>(null)
let flashTimer: number | null = null
let remoteFlashTimer: number | null = null

function flash(note: string) {
  flashing.value = note
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  flashTimer = window.setTimeout(() => (flashing.value = null), 150)
}

function flashRemote(note: string) {
  remoteFlashing.value = note
  if (remoteFlashTimer !== null) window.clearTimeout(remoteFlashTimer)
  remoteFlashTimer = window.setTimeout(() => (remoteFlashing.value = null), 220)
}

watch(
  () => props.remoteHit,
  (hit) => {
    if (!hit || hit.instrument !== "bass") return
    flashRemote(hit.note)
  },
)

async function hit(note: string) {
  await ensureStarted()
  play("bass", style.value, note)
  flash(note)
  live.pushEvent("note", { instrument: "bass", style: style.value, note })
}

function selectStyle(id: BassStyle) {
  if (id === style.value) return
  stopAll("bass", style.value)
  style.value = id
}

function onKey(event: KeyboardEvent) {
  if (event.repeat) return
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
  stopAll("bass", style.value)
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
            ? 'bg-primary text-primary-foreground border-primary'
            : 'bg-card hover:bg-accent text-muted-foreground border-input'
        ]"
      >
        {{ s.label }}
      </button>
    </div>

    <!-- Notes -->
    <div class="grid grid-cols-4 sm:grid-cols-8 gap-3">
      <button
        v-for="n in notes"
        :key="n.note"
        @pointerdown.prevent="hit(n.note)"
        :class="[
          'rounded-md border bg-card flex flex-col items-center justify-center gap-2 py-6 select-none transition-all active:scale-95 hover:bg-accent',
          flashing === n.note && 'ring-2 ring-primary scale-95',
          remoteFlashing === n.note && flashing !== n.note && 'ring-2 ring-orange-400'
        ]"
      >
        <div class="text-xl font-bold">{{ n.label }}</div>
        <kbd class="text-xs px-1.5 py-0.5 rounded bg-muted text-muted-foreground">{{ n.key }}</kbd>
      </button>
    </div>
  </div>
</template>
