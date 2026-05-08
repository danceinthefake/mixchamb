<script setup lang="ts">
// Drum pad — five pieces (kick / snare / hi-hat / open hat / crash)
// arranged like a real kit from the drummer's perspective. Cymbals
// up top, snare in the middle, kick filling the bottom row. Tap the
// pads or press 1–5 on the keyboard.
//
// Local audio plays immediately on tap; the note + the player's
// chosen style are pushed to LiveView for broadcast. Remote players
// hear *the sender's* style — coherent kit sound for everyone in
// the jam.

import { onMounted, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import { ensureStarted, play, stopAll, type DrumName } from "@/lib/audio"

const props = defineProps<{
  remoteHit: { instrument: string; note: string; t: number } | null
}>()

const live = useLiveVue()

type DrumStyle = "synth" | "808" | "acoustic"
// `pos` is a percentage box inside the kit container, painting each
// piece where it would sit on a real drum kit (drummer's POV).
type Pad = {
  name: DrumName
  label: string
  key: string
  pos: { left: string; top: string; width: string; height: string }
  shape: "round" | "square"
}
type StyleOption = { id: DrumStyle; label: string }

const styles: StyleOption[] = [
  { id: "synth", label: "Synth" },
  { id: "808", label: "808" },
  { id: "acoustic", label: "Acoustic" },
]

const style = ref<DrumStyle>("synth")

const pads: Pad[] = [
  // Cymbals top — hi-hat upper-left, open-hat next to it, crash upper-right.
  {
    name: "hihat",
    label: "Hi-hat",
    key: "3",
    pos: { left: "2%", top: "0%", width: "22%", height: "44%" },
    shape: "round",
  },
  {
    name: "open_hat",
    label: "Open Hat",
    key: "4",
    pos: { left: "26%", top: "4%", width: "22%", height: "44%" },
    shape: "round",
  },
  {
    name: "crash",
    label: "Crash",
    key: "5",
    pos: { left: "76%", top: "0%", width: "22%", height: "44%" },
    shape: "round",
  },
  // Snare center, drumhead-shaped.
  {
    name: "snare",
    label: "Snare",
    key: "2",
    pos: { left: "36%", top: "30%", width: "28%", height: "40%" },
    shape: "round",
  },
  // Kick wide across the bottom, the biggest piece of the kit.
  {
    name: "kick",
    label: "Kick",
    key: "1",
    pos: { left: "22%", top: "68%", width: "56%", height: "30%" },
    shape: "square",
  },
]

const flashing = ref<DrumName | null>(null)
const remoteFlashing = ref<DrumName | null>(null)
let flashTimer: number | null = null
let remoteFlashTimer: number | null = null

function flash(name: DrumName) {
  flashing.value = name
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  flashTimer = window.setTimeout(() => (flashing.value = null), 120)
}

function flashRemote(name: DrumName) {
  remoteFlashing.value = name
  if (remoteFlashTimer !== null) window.clearTimeout(remoteFlashTimer)
  // Slightly longer than local so it's visible even after a short network hop.
  remoteFlashTimer = window.setTimeout(() => (remoteFlashing.value = null), 200)
}

const drumNames = new Set<DrumName>(["kick", "snare", "hihat", "open_hat", "crash"])

watch(
  () => props.remoteHit,
  (hit) => {
    if (!hit || hit.instrument !== "drums") return
    if (drumNames.has(hit.note as DrumName)) flashRemote(hit.note as DrumName)
  },
)

async function hit(name: DrumName) {
  await ensureStarted()
  play("drums", style.value, name)
  flash(name)
  live.pushEvent("note", { instrument: "drums", style: style.value, note: name })
}

function selectStyle(id: DrumStyle) {
  if (id === style.value) return
  // Cut any tail still ringing on the previous flavor before switching.
  stopAll("drums", style.value)
  style.value = id
}

function onKey(event: KeyboardEvent) {
  if (event.repeat) return
  const pad = pads.find((p) => p.key === event.key)
  if (pad) {
    event.preventDefault()
    hit(pad.name)
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
  stopAll("drums", style.value)
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

    <!-- Kit canvas. Aspect-ratio keeps the layout proportional at any
         width; on narrow screens it just gets smaller, not crushed. -->
    <div
      class="relative w-full mx-auto"
      style="max-width: 640px; aspect-ratio: 5 / 3;"
    >
      <button
        v-for="p in pads"
        :key="p.name"
        @pointerdown.prevent="hit(p.name)"
        :style="{
          left: p.pos.left,
          top: p.pos.top,
          width: p.pos.width,
          height: p.pos.height,
        }"
        :class="[
          'absolute border bg-card flex flex-col items-center justify-center gap-1 select-none transition-all active:scale-95 hover:bg-accent',
          p.shape === 'round' ? 'rounded-full' : 'rounded-lg',
          flashing === p.name && 'ring-4 ring-primary scale-95',
          remoteFlashing === p.name && flashing !== p.name && 'ring-4 ring-orange-400'
        ]"
      >
        <div class="text-sm font-medium">{{ p.label }}</div>
        <kbd class="text-[10px] px-1.5 py-0.5 rounded bg-muted text-muted-foreground">{{ p.key }}</kbd>
      </button>
    </div>
  </div>
</template>
