<script setup lang="ts">
// Guess input + scrolling feed (features/mini-game.md §4). Wrong
// guesses render `alias: text` for everyone; a correct guess collapses
// to "✦ alias guessed it!" with the winning text withheld (the server
// never sends it). Feed entries arrive as transient `minigame_feed`
// push-events — not reloadable state — and reset each turn.

import { computed, nextTick, ref, watch } from "vue"
import { useLiveVue } from "live_vue"

const props = defineProps<{
  canGuess: boolean
  hasGuessed: boolean
  turnToken?: number
  current_user_id: string
  nameOf: (id: string | null) => string
}>()

const live = useLiveVue()

type FeedEntry = {
  id: number
  type: "wrong" | "correct"
  user_id: string
  alias: string
  text?: string
  isSelf: boolean
}

const feed = ref<FeedEntry[]>([])
const scroller = ref<HTMLElement | null>(null)
const draft = ref("")
let nextId = 1

// Reset the feed at the start of each turn.
watch(
  () => props.turnToken,
  () => {
    feed.value = []
  },
)

live.handleEvent(
  "minigame_feed",
  (payload: { type: "wrong" | "correct"; user_id: string; alias: string; text?: string }) => {
    feed.value.push({
      id: nextId++,
      type: payload.type,
      user_id: payload.user_id,
      alias: payload.alias,
      text: payload.text,
      isSelf: payload.user_id === props.current_user_id,
    })
    // Auto-scroll to bottom unless the user has scrolled up to read.
    void nextTick(() => {
      const el = scroller.value
      if (!el) return
      const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 60
      if (nearBottom) el.scrollTop = el.scrollHeight
    })
  },
)

function submit() {
  const text = draft.value.trim()
  if (!text || !props.canGuess) return
  live.pushEvent("minigame_guess", { text })
  draft.value = ""
}

const placeholder = computed(() => {
  if (props.hasGuessed) return "You guessed it! 🎉"
  if (!props.canGuess) return "Waiting…"
  return "Type your guess…"
})
</script>

<template>
  <div class="rounded-xl border bg-card/60 p-3 space-y-2">
    <div ref="scroller" class="h-32 overflow-y-auto space-y-1 text-sm pr-1" aria-live="polite">
      <p v-if="feed.length === 0" class="text-xs text-muted-foreground italic">
        Guesses appear here.
      </p>
      <p
        v-for="e in feed"
        :key="e.id"
        :class="e.type === 'correct' ? 'text-accent-minigame font-semibold' : ''"
      >
        <template v-if="e.type === 'correct'">
          ✦ {{ e.isSelf ? "You" : e.alias }} guessed it!
        </template>
        <template v-else>
          <span class="text-muted-foreground">{{ e.isSelf ? "You" : e.alias }}:</span>
          {{ e.text }}
        </template>
      </p>
    </div>

    <form @submit.prevent="submit" class="flex items-center gap-2">
      <input
        v-model="draft"
        :disabled="!canGuess"
        :placeholder="placeholder"
        type="text"
        autocomplete="off"
        class="flex-1 bg-background border border-input rounded-md px-2 py-1.5 text-sm outline-none focus:border-accent-minigame/60 disabled:opacity-60"
      />
      <button
        type="submit"
        :disabled="!canGuess || !draft.trim()"
        class="px-3 py-1.5 text-sm rounded-md bg-accent-minigame/90 text-white hover:bg-accent-minigame transition-colors cursor-pointer font-medium disabled:opacity-50 disabled:cursor-not-allowed"
      >
        Guess
      </button>
    </form>
  </div>
</template>
