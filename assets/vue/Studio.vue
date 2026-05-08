<script setup lang="ts">
// The single Vue island for the studio. Owns:
//   - cross-instrument audio receiver (remote players' notes)
//   - the active instrument pad (rendered via v-if from a prop)
//
// Why one island instead of three?
// live_vue 1.2's destroyed() hook *defers* `app.unmount()` until the
// next `phx:page-loading-stop` event — see hooks.ts:78. That event
// only fires on full-page navigation, not on WebSocket-driven LV
// re-renders. So if we have <.DrumPad /> swapping to <.GuitarPad />
// at the HEEX level, each swap leaves the previous Vue app alive
// forever, with its keydown listeners still attached to window.
// After a few switches every keystroke fires multiple instruments
// at once.
//
// Wrapping the pads in a single Vue island fixes it: v-if is pure
// Vue, so the inner pad's onUnmounted properly fires on switch and
// AbortController + stopAllX run as designed.

import { useLiveVue } from "live_vue"
import DrumPad from "@/instruments/DrumPad.vue"
import KeyboardPad from "@/instruments/KeyboardPad.vue"
import GuitarPad from "@/instruments/GuitarPad.vue"
import {
  ensureStarted,
  playDrum,
  playKey,
  playChord,
  type DrumName,
  type ChordName,
} from "@/lib/audio"

defineProps<{
  current_instrument: "drums" | "keyboard" | "guitar"
}>()

const live = useLiveVue()

type RemoteNote =
  | { instrument: "drums"; note: DrumName }
  | { instrument: "keyboard"; note: string }
  | { instrument: "guitar"; chord: ChordName }

// Cross-instrument audio: every user hears every other user, no
// matter which pad *they* have on screen.
live.handleEvent("play_remote_note", async (payload: RemoteNote) => {
  await ensureStarted()
  switch (payload.instrument) {
    case "drums":
      playDrum(payload.note)
      break
    case "keyboard":
      playKey(payload.note)
      break
    case "guitar":
      playChord(payload.chord)
      break
  }
})
</script>

<template>
  <DrumPad v-if="current_instrument === 'drums'" />
  <KeyboardPad v-else-if="current_instrument === 'keyboard'" />
  <GuitarPad v-else-if="current_instrument === 'guitar'" />
</template>
