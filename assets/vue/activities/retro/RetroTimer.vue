<script setup lang="ts">
// Phase timer. The host picks a length; everyone counts down from
// the same absolute server deadline (same trick as Pictionary), so
// latency doesn't skew who sees 0:00 first. Display-only — nothing
// auto-advances; a buzzer marks time-up and the host moves on.

import { computed, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import { playTimeUp } from "../../lib/audio"

const props = defineProps<{
  deadline: number | null
  is_host: boolean
}>()

const live = useLiveVue()

const PRESETS_MIN = [3, 5, 10]

function start(minutes: number) {
  live.pushEvent("retro_set_timer", { seconds: minutes * 60 })
}
function clear() {
  live.pushEvent("retro_set_timer", { seconds: null })
}

const now = ref(Date.now())
let ticker: number | undefined
watch(
  () => props.deadline,
  (deadline) => {
    if (typeof window === "undefined") return
    window.clearInterval(ticker)
    if (deadline) {
      now.value = Date.now()
      ticker = window.setInterval(() => (now.value = Date.now()), 250)
    }
  },
  { immediate: true },
)
onUnmounted(() => window.clearInterval(ticker))

const secondsLeft = computed(() => {
  if (!props.deadline) return null
  return Math.max(0, Math.ceil((props.deadline - now.value) / 1000))
})

const label = computed(() => {
  const s = secondsLeft.value
  if (s === null) return ""
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`
})

watch(secondsLeft, (cur, prev) => {
  if (cur === 0 && prev !== null && prev > 0) void playTimeUp()
})
</script>

<template>
  <div
    v-if="deadline || is_host"
    id="retro-timer"
    class="flex flex-wrap items-center gap-2 text-xs"
    role="timer"
    :aria-live="secondsLeft === 0 ? 'assertive' : 'off'"
  >
    <span
      v-if="deadline"
      class="font-mono tabular-nums text-base font-semibold px-2 py-0.5 rounded-md border"
      :class="secondsLeft === 0 ? 'text-destructive border-destructive/50' : 'bg-card'"
    >
      {{ secondsLeft === 0 ? "Time's up" : label }}
    </span>
    <template v-if="is_host">
      <span class="text-muted-foreground">Timer</span>
      <button
        v-for="m in PRESETS_MIN"
        :key="m"
        type="button"
        @click="start(m)"
        class="rounded-md border px-2 py-0.5 hover:bg-accent"
      >
        {{ m }} min
      </button>
      <button
        v-if="deadline"
        type="button"
        @click="clear"
        class="rounded-md px-2 py-0.5 text-muted-foreground hover:text-foreground"
      >
        Clear
      </button>
    </template>
  </div>
</template>
