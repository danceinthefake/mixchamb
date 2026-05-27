<script setup lang="ts">
// Top-level Vue island for a mini-game chamber. Mounted by
// Chamber.vue when `chamber.activity === "minigame"`. The mini-game
// is a *framework* (features/mini-game.md §1): this board owns the
// lobby / scoreboard / host-control shell and phase-routes the
// middle to the chosen game's stage component (v1: Pictionary).
//
// State flows in from the LiveView (source of truth); user actions
// push back as Phoenix events. The chamber GenServer broadcasts on
// every change, so every player's board re-renders within ~50ms.

import { computed, watch } from "vue"
import { useLiveVue } from "live_vue"
import { playGameOver } from "../../lib/audio"
import MiniGameLobby from "./MiniGameLobby.vue"
import MiniGameScoreboard from "./MiniGameScoreboard.vue"
import MiniGameHostControls from "./MiniGameHostControls.vue"
import PictionaryStage from "./pictionary/PictionaryStage.vue"

export type MiniGamePhase = "lobby" | "turn" | "turn_reveal" | "gameover"

export type MiniGameConfig = {
  word_pack: string
  turn_seconds: number
  round_count: number
  // Number of host-pasted custom words (the words themselves never
  // reach the client). 0 unless the "custom" pack has entries.
  custom_word_count: number
}

export type Stroke = {
  seq?: number
  points: [number, number][]
  color: string
  width: number
}

// The per-user view shaped by the game's `view/2` on the server.
// `word` is present only for the drawer (their turn) or once a turn
// is revealed; guessers get `blanks` (per-token lengths) instead.
export type MiniGameView = {
  game: string
  phase: MiniGamePhase
  config: MiniGameConfig
  round: number
  round_count: number
  players: string[]
  drawer_id: string | null
  is_drawer: boolean
  is_choosing: boolean
  word: string | null
  blanks: number[]
  word_choices: string[]
  guessed: string[]
  scores: Record<string, number>
  deadline: number | null
  strokes: Stroke[]
  turn_token: number
}

export type Participant = {
  user_id: string
  display_name: string
  alias: string | null
}

const props = defineProps<{
  state: MiniGameView | null
  participants: Participant[]
  current_user_id: string
  is_host: boolean
}>()

const live = useLiveVue()

// A minigame chamber's GenServer always allocates a lobby at boot;
// `null` only happens if mounted for a non-minigame chamber by
// mistake. Render a calm empty state rather than crash children.
const state = computed(() => props.state)

const phase = computed<MiniGamePhase | null>(() => state.value?.phase ?? null)
const inGame = computed(() => phase.value === "turn" || phase.value === "turn_reveal")

// alias_or_name lookup for rendering players/drawer/scoreboard
// without leaking raw ids. Falls back to a short id for a player
// who's left (still on the scoreboard per spec §7).
const nameOf = computed(() => {
  const map = new Map(props.participants.map((p) => [p.user_id, p.alias || p.display_name]))
  return (id: string | null): string => {
    if (!id) return "—"
    return map.get(id) ?? `${id.slice(0, 4)}…`
  }
})

const drawerName = computed(() => nameOf.value(state.value?.drawer_id ?? null))

// Celebratory fanfare the moment the game ends.
watch(phase, (next, prev) => {
  if (next === "gameover" && prev && prev !== "gameover") void playGameOver()
})
</script>

<template>
  <section
    v-if="state"
    class="minigame-scope w-full max-w-3xl mx-auto space-y-4"
    aria-label="Mini-game board"
  >
    <!-- Header: game name + round/turn status -->
    <header class="flex items-center justify-between gap-3 flex-wrap">
      <div class="flex items-center gap-2">
        <span class="size-2.5 rounded-full bg-accent-minigame"></span>
        <h2 class="text-lg font-bold font-display tracking-tight">Mini-game</h2>
        <span
          v-if="inGame"
          class="text-xs uppercase tracking-wider text-muted-foreground tabular-nums"
        >
          Round {{ state.round }} / {{ state.round_count }}
        </span>
      </div>
      <MiniGameHostControls
        v-if="is_host"
        :phase="state.phase"
        :player_count="participants.length"
        @start="live.pushEvent('minigame_start', {})"
        @skip="live.pushEvent('minigame_skip', {})"
        @next="live.pushEvent('minigame_next', {})"
        @play-again="live.pushEvent('minigame_play_again', {})"
        @end="live.pushEvent('minigame_end', {})"
      />
    </header>

    <!-- Lobby: game picker + roster + config -->
    <MiniGameLobby
      v-if="phase === 'lobby'"
      :game="state.game"
      :config="state.config"
      :player_count="participants.length"
      :is_host="is_host"
      @select-game="(g) => live.pushEvent('minigame_select_game', { game: g })"
      @set-config="(c) => live.pushEvent('minigame_set_config', { config: c })"
    />

    <!-- Active game: scoreboard strip on top, Pictionary stage below.
         Single centered column so nothing lands under the floating
         presence panel. -->
    <div v-else-if="inGame" class="space-y-4">
      <MiniGameScoreboard
        :scores="state.scores"
        :players="state.players"
        :drawer_id="state.drawer_id"
        :guessed="state.guessed"
        :name-of="nameOf"
      />
      <PictionaryStage
        :state="state"
        :current_user_id="current_user_id"
        :drawer-name="drawerName"
        :name-of="nameOf"
      />
    </div>

    <!-- Game over: final scoreboard -->
    <div v-else-if="phase === 'gameover'" class="space-y-4">
      <div class="text-center space-y-1">
        <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">Game over</p>
        <h3 class="text-2xl font-bold font-display">Final scores</h3>
      </div>
      <MiniGameScoreboard
        :scores="state.scores"
        :players="state.players"
        :drawer_id="null"
        :guessed="[]"
        :name-of="nameOf"
        final
      />
      <p v-if="!is_host" class="text-center text-sm text-muted-foreground">
        Waiting for the host to play again or end the game.
      </p>
    </div>
  </section>

  <section v-else class="max-w-md mx-auto text-center py-16 text-muted-foreground">
    No game running.
  </section>
</template>
