<script setup lang="ts">
// Collapsed list of finished rounds in this chamber. Renders only
// when the session has at least one completed round; the host
// pushes a round into history every time they click "Next round"
// (server side, in PokerSession.next_round/2). Re-vote does NOT
// push — the team is redoing the same round, so the previous
// attempt isn't worth remembering.
//
// Each row shows the round number, the story (or "Untitled"),
// the vote count, and a compact verdict derived from the same
// `computeVerdict` helper RevealPanel uses for the live round.
// Colour-codes match: green = consensus, neutral = close,
// primary = discuss, muted = empty / meta-only.

import { computed } from "vue"
import type { DeckId } from "./PokerBoard.vue"
import { computeVerdict, type Verdict } from "./verdict"

export type HistoryEntry = {
  round: number
  story: string | null
  deck: DeckId
  cards: string[]
  values: string[]
}

const props = defineProps<{
  history: HistoryEntry[]
}>()

// Map each entry's votes through the shared verdict logic, then
// derive a compact label. The full RevealPanel headlines are too
// long for a single-line row; we squash to one of:
//   "5"       (consensus value)
//   "5 / 8"   (close call range)
//   "discuss" (wide spread)
//   "?" / "☕" (everyone picked the meta card)
//   "—"       (no votes at all)
function compactLabel(v: Verdict): string {
  switch (v.kind) {
    case "consensus":
    case "single":
      return v.value
    case "close":
      return `${v.low} / ${v.high}`
    case "discuss":
      return "discuss"
    case "all_question":
      return "?"
    case "all_coffee":
      return "☕"
    case "none":
      return "—"
  }
}

function labelClass(v: Verdict): string {
  switch (v.kind) {
    case "consensus":
      return "text-success"
    case "discuss":
      return "text-primary"
    case "close":
    case "single":
      return "text-foreground"
    case "all_question":
    case "all_coffee":
    case "none":
      return "text-muted-foreground"
  }
}

// Pre-compute the per-row verdict so the template stays declarative.
const rows = computed(() =>
  props.history.map((entry) => {
    const v = computeVerdict(entry.values, entry.cards)
    return {
      round: entry.round,
      story: entry.story,
      voteCount: entry.values.length,
      label: compactLabel(v),
      cls: labelClass(v),
    }
  }),
)
</script>

<template>
  <details
    v-if="history.length > 0"
    class="rounded-xl border bg-card/60 backdrop-blur-sm group"
  >
    <summary
      class="cursor-pointer list-none px-4 py-3 flex items-center justify-between gap-3 hover:bg-accent/30 transition-colors rounded-xl group-open:rounded-b-none"
    >
      <span class="text-xs uppercase tracking-wider text-muted-foreground font-display">
        Past rounds
      </span>
      <span class="flex items-center gap-2 text-xs text-muted-foreground">
        <span class="tabular-nums">{{ history.length }}</span>
        <!-- Native disclosure caret. Rotates via group-open: utility. -->
        <span
          aria-hidden="true"
          class="transition-transform group-open:rotate-180 select-none"
        >
          ▾
        </span>
      </span>
    </summary>

    <ul class="divide-y border-t">
      <li
        v-for="row in rows"
        :key="row.round"
        class="px-4 py-2 flex items-center gap-3 text-sm"
      >
        <span class="text-xs text-muted-foreground tabular-nums w-10 shrink-0 font-mono">
          R{{ row.round }}
        </span>
        <span
          :class="[
            'flex-1 min-w-0 truncate',
            row.story ? 'text-foreground' : 'text-muted-foreground italic',
          ]"
        >
          {{ row.story || "Untitled" }}
        </span>
        <span
          v-if="row.voteCount > 0"
          class="text-[11px] text-muted-foreground tabular-nums shrink-0"
        >
          {{ row.voteCount }} vote{{ row.voteCount === 1 ? "" : "s" }}
        </span>
        <span :class="['shrink-0 font-mono font-bold tabular-nums', row.cls]">
          {{ row.label }}
        </span>
      </li>
    </ul>
  </details>
</template>
