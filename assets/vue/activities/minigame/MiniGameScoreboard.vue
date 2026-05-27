<script setup lang="ts">
// Shared scoreboard across all registry games (features/mini-game.md
// §8). Sorts by points desc, highlights the current drawer, marks
// who's already guessed this turn. Reused unchanged by future games.

import { computed } from "vue"

const props = defineProps<{
  scores: Record<string, number>
  players: string[]
  drawer_id: string | null
  guessed: string[]
  nameOf: (id: string | null) => string
  final?: boolean
}>()

// Everyone with a score plus everyone still in the rotation, even at
// zero — so the board reads as a roster, not just "who's scored".
const rows = computed(() => {
  const ids = new Set<string>([...Object.keys(props.scores), ...props.players])
  const guessedSet = new Set(props.guessed)
  return [...ids]
    .map((id) => ({
      id,
      name: props.nameOf(id),
      points: props.scores[id] ?? 0,
      isDrawer: id === props.drawer_id,
      hasGuessed: guessedSet.has(id),
    }))
    .sort((a, b) => b.points - a.points || a.name.localeCompare(b.name))
})

const leaderId = computed(() => (rows.value.length ? rows.value[0].id : null))
</script>

<template>
  <div class="rounded-xl border bg-card/60 p-4 space-y-2">
    <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
      {{ final ? "Final" : "Scores" }}
    </p>
    <ol class="space-y-1">
      <li
        v-for="(r, i) in rows"
        :key="r.id"
        class="flex items-center gap-2 text-sm rounded-md px-2 py-1 transition-colors"
        :class="r.isDrawer ? 'bg-accent-minigame/10' : ''"
      >
        <span class="w-4 text-xs text-muted-foreground tabular-nums">{{ i + 1 }}</span>
        <span class="truncate flex items-center gap-1.5">
          <span v-if="final && r.id === leaderId" aria-hidden="true" title="Winner"> 👑 </span>
          <span
            v-else-if="r.isDrawer"
            class="text-[10px] uppercase tracking-wider text-accent-minigame font-semibold"
            title="Drawing now"
          >
            ✎
          </span>
          <span class="truncate">{{ r.name }}</span>
          <span v-if="r.hasGuessed" aria-hidden="true" title="Guessed it">✓</span>
        </span>
        <span class="ml-auto tabular-nums font-semibold">{{ r.points }}</span>
      </li>
    </ol>
    <p v-if="rows.length === 0" class="text-xs text-muted-foreground italic">No players yet.</p>
  </div>
</template>
