<script setup lang="ts">
// Lobby (features/mini-game.md §1): host picks a game from the
// registry, sets per-game config, and sees the roster. Everyone
// present at Start becomes a player. Non-hosts see a read-only view
// and a "waiting for the host" line.

import type { MiniGameConfig, Participant } from "./MiniGameBoard.vue"

const props = defineProps<{
  game: string
  config: MiniGameConfig
  participants: Participant[]
  is_host: boolean
  nameOf: (id: string | null) => string
}>()

const emit = defineEmits<{
  "select-game": [game: string]
  "set-config": [config: Record<string, string | number>]
}>()

// v1 registry: one game. Listed as cards so a second game (Gartic
// Phone, trivia…) is a new entry, not a re-layout.
const GAMES = [
  {
    key: "pictionary",
    label: "Pictionary",
    blurb: "Draw a secret word; everyone else races the clock to guess it.",
  },
]

const WORD_PACKS = [
  { id: "general", label: "General" },
  { id: "animals", label: "Animals" },
  { id: "movies", label: "Movies" },
  { id: "office", label: "Office" },
]
const TURN_SECONDS = [60, 80, 120]
const ROUND_COUNTS = [1, 2, 3, 4, 5]

function setConfig(key: string, value: string | number) {
  if (!props.is_host) return
  emit("set-config", { [key]: value })
}
</script>

<template>
  <div class="grid sm:grid-cols-[1fr_260px] gap-4 items-start">
    <!-- Game picker -->
    <div class="space-y-3">
      <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
        Choose a game
      </p>
      <div class="grid gap-2">
        <button
          v-for="g in GAMES"
          :key="g.key"
          type="button"
          :disabled="!is_host"
          :aria-pressed="game === g.key"
          @click="emit('select-game', g.key)"
          class="text-left rounded-xl border p-4 transition-all"
          :class="[
            game === g.key
              ? 'border-accent-minigame/60 bg-accent-minigame/10 ring-1 ring-accent-minigame/40'
              : 'bg-card hover:bg-accent border-border',
            is_host ? 'cursor-pointer' : 'cursor-default',
          ]"
        >
          <div class="font-semibold font-display">{{ g.label }}</div>
          <div class="text-sm text-muted-foreground">{{ g.blurb }}</div>
        </button>
      </div>

      <!-- Per-game config (Pictionary) -->
      <div v-if="game === 'pictionary'" class="rounded-xl border bg-card/60 p-4 space-y-3">
        <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">Setup</p>

        <label class="flex items-center justify-between gap-3 text-sm">
          <span class="text-muted-foreground">Word pack</span>
          <select
            :value="config.word_pack"
            :disabled="!is_host"
            @change="(e) => setConfig('word_pack', (e.target as HTMLSelectElement).value)"
            class="px-2 py-1 text-sm rounded-md border bg-card disabled:opacity-60 cursor-pointer"
          >
            <option v-for="p in WORD_PACKS" :key="p.id" :value="p.id">{{ p.label }}</option>
          </select>
        </label>

        <label class="flex items-center justify-between gap-3 text-sm">
          <span class="text-muted-foreground">Turn timer</span>
          <select
            :value="config.turn_seconds"
            :disabled="!is_host"
            @change="
              (e) => setConfig('turn_seconds', Number((e.target as HTMLSelectElement).value))
            "
            class="px-2 py-1 text-sm rounded-md border bg-card disabled:opacity-60 cursor-pointer"
          >
            <option v-for="s in TURN_SECONDS" :key="s" :value="s">{{ s }}s</option>
          </select>
        </label>

        <label class="flex items-center justify-between gap-3 text-sm">
          <span class="text-muted-foreground">Rounds</span>
          <select
            :value="config.round_count"
            :disabled="!is_host"
            @change="(e) => setConfig('round_count', Number((e.target as HTMLSelectElement).value))"
            class="px-2 py-1 text-sm rounded-md border bg-card disabled:opacity-60 cursor-pointer"
          >
            <option v-for="r in ROUND_COUNTS" :key="r" :value="r">{{ r }}</option>
          </select>
        </label>
      </div>
    </div>

    <!-- Roster -->
    <div class="rounded-xl border bg-card/60 p-4 space-y-2">
      <div class="flex items-center justify-between">
        <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">Players</p>
        <span class="text-xs text-muted-foreground tabular-nums">{{ participants.length }}</span>
      </div>
      <ul class="space-y-1">
        <li
          v-for="p in participants"
          :key="p.user_id"
          class="flex items-center gap-2 text-sm py-0.5"
        >
          <span class="size-1.5 rounded-full bg-accent-minigame shrink-0"></span>
          <span class="truncate">{{ p.alias || p.display_name }}</span>
        </li>
      </ul>
      <p
        v-if="participants.length < 2"
        class="text-[11px] text-muted-foreground italic pt-1 border-t border-border/60"
      >
        Need at least 2 players to start. Share the chamber link to invite more.
      </p>
      <p v-else-if="!is_host" class="text-[11px] text-muted-foreground italic pt-1">
        Waiting for the host to start the game.
      </p>
    </div>
  </div>
</template>
