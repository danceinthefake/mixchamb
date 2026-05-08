<script setup lang="ts">
// Persistent footer player. Mounted once in root.html.heex, outside
// any LiveView, so it survives LV navigation. Talks to LV via window
// CustomEvents:
//
//   window.addEventListener("mixwave:play",  …)  // start a track
//   window.addEventListener("mixwave:stop",  …)  // explicit stop
//
// SongLive dispatches "mixwave:play" with { id, title, url, by } via
// JS.dispatch("mixwave:play", detail: ...). The player owns its own
// reactive state — howler instance, position, duration — so LV
// re-renders don't perturb playback.

import { computed, onMounted, onUnmounted, ref } from "vue"
import { Howl } from "howler"
import { Button } from "@/components/ui/button"

type CurrentSong = {
  id: string
  title: string
  url: string
  by: string
}

const current = ref<CurrentSong | null>(null)
const isPlaying = ref(false)
const position = ref(0)      // seconds
const duration = ref(0)      // seconds

let howl: Howl | null = null
let positionTimer: number | null = null

const formatTime = (s: number) => {
  if (!Number.isFinite(s) || s < 0) return "0:00"
  const m = Math.floor(s / 60)
  const ss = Math.floor(s % 60).toString().padStart(2, "0")
  return `${m}:${ss}`
}

const positionLabel = computed(() => formatTime(position.value))
const durationLabel = computed(() => formatTime(duration.value))
const progressPct = computed(() =>
  duration.value > 0 ? (position.value / duration.value) * 100 : 0
)

function teardown() {
  if (howl) {
    howl.unload()
    howl = null
  }
  if (positionTimer !== null) {
    window.clearInterval(positionTimer)
    positionTimer = null
  }
  isPlaying.value = false
  position.value = 0
  duration.value = 0
}

function play(song: CurrentSong) {
  // If we're already playing this exact song, toggle instead of restart.
  if (current.value?.id === song.id && howl) {
    if (isPlaying.value) {
      howl.pause()
      isPlaying.value = false
    } else {
      howl.play()
      isPlaying.value = true
    }
    return
  }

  teardown()
  current.value = song

  howl = new Howl({
    src: [song.url],
    html5: true, // streaming, no full-buffer download for big files
    onload: () => {
      duration.value = howl?.duration() ?? 0
    },
    onplay: () => {
      isPlaying.value = true
      // Howler doesn't push position events; poll while playing.
      if (positionTimer === null) {
        positionTimer = window.setInterval(() => {
          if (howl && isPlaying.value) {
            position.value = (howl.seek() as number) || 0
          }
        }, 250)
      }
    },
    onpause: () => {
      isPlaying.value = false
    },
    onend: () => {
      isPlaying.value = false
      position.value = duration.value
    },
    onloaderror: (_id, err) => {
      console.error("Player load error", err)
      teardown()
    },
  })
  howl.play()
}

function togglePlay() {
  if (!howl) return
  if (isPlaying.value) howl.pause()
  else howl.play()
}

function onSeek(event: Event) {
  if (!howl || duration.value <= 0) return
  const target = event.target as HTMLInputElement
  const pct = Number.parseFloat(target.value)
  const newPos = (pct / 100) * duration.value
  howl.seek(newPos)
  position.value = newPos
}

function stop() {
  teardown()
  current.value = null
}

const onPlayEvent = (event: Event) => {
  const detail = (event as CustomEvent<CurrentSong>).detail
  if (detail?.url && detail?.id) play(detail)
}

const onStopEvent = () => stop()

onMounted(() => {
  window.addEventListener("mixwave:play", onPlayEvent as EventListener)
  window.addEventListener("mixwave:stop", onStopEvent)
})

onUnmounted(() => {
  window.removeEventListener("mixwave:play", onPlayEvent as EventListener)
  window.removeEventListener("mixwave:stop", onStopEvent)
  teardown()
})
</script>

<template>
  <Transition
    enter-active-class="transition-transform duration-200"
    enter-from-class="translate-y-full"
    enter-to-class="translate-y-0"
    leave-active-class="transition-transform duration-200"
    leave-from-class="translate-y-0"
    leave-to-class="translate-y-full"
  >
    <div
      v-if="current"
      class="fixed bottom-0 left-0 right-0 border-t bg-card/95 backdrop-blur supports-[backdrop-filter]:bg-card/80 z-40"
    >
      <div class="mx-auto max-w-5xl flex items-center gap-4 px-4 py-3">
        <Button
          variant="outline"
          size="sm"
          @click="togglePlay"
          :aria-label="isPlaying ? 'Pause' : 'Play'"
          class="shrink-0"
        >
          <span v-if="!isPlaying">▶</span>
          <span v-else>❚❚</span>
        </Button>

        <div class="min-w-0 flex-1">
          <div class="flex items-baseline gap-2 text-sm">
            <span class="font-medium truncate">{{ current.title }}</span>
            <span class="truncate text-muted-foreground">by {{ current.by }}</span>
          </div>
          <div class="flex items-center gap-2 mt-1">
            <span class="text-xs tabular-nums text-muted-foreground">{{ positionLabel }}</span>
            <input
              type="range"
              min="0"
              max="100"
              step="0.1"
              :value="progressPct"
              @input="onSeek"
              class="flex-1 h-1 cursor-pointer accent-primary"
            />
            <span class="text-xs tabular-nums text-muted-foreground">{{ durationLabel }}</span>
          </div>
        </div>

        <Button variant="ghost" size="sm" @click="stop" aria-label="Close player" class="shrink-0">
          ✕
        </Button>
      </div>
    </div>
  </Transition>
</template>
