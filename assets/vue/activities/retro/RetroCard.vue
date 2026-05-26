<script setup lang="ts">
// One card. Phase-aware: brainstorm shows owner edit/delete on
// own cards; voting shows vote/unvote button + live tally;
// discuss + archived show static count + (host-only) discussing
// focus toggle.

import { computed, ref } from "vue"
import { useLiveVue } from "live_vue"
import RetroActionRow from "./RetroActionRow.vue"
import RetroComments from "./RetroComments.vue"
import type {
  RetroCard as RetroCardT,
  RetroActionItem,
  RetroPhase,
} from "./RetroBoard.vue"

// The same 6-emoji set RetroCardReaction validates on the
// server. Order matches the schema's @emojis attribute so
// counts always render in the same order across all clients.
const REACTION_EMOJIS = ["👍", "❤️", "🎉", "😄", "😢", "🤔"] as const

const props = defineProps<{
  card: RetroCardT
  phase: RetroPhase
  // Host's "show all cards live" toggle from :setup. When true,
  // reactions + comments unlock during :brainstorm too (same
  // logic as the server-side Mixchamb.Retro.interactive?/1).
  brainstorm_visible: boolean
  is_mine: boolean
  // Used for "did I react / is this my comment" checks. Empty
  // string in archived-permalink mode (RetroLive) — the
  // reaction strip + comments thread still render read-only.
  current_user_id: string
  tally: number
  is_my_vote: boolean
  votes_remaining: number
  is_host: boolean
  // Visually highlight this card if it's the currently-focused
  // discussion card (host-driven, broadcast to everyone).
  is_discussing: boolean
  // Action items whose source_card_id is this card. Rendered
  // nested below the card body during :discuss / :archived
  // (spec §6). Empty list outside those phases.
  tied_actions: RetroActionItem[]
}>()

// Reactions + comments are available from :reveal onward, plus
// during :brainstorm when the host opted into always-visible
// mode. Mirrors Mixchamb.Retro.interactive?/1 on the server.
const reactableNow = computed(() => {
  if (["reveal", "voting", "discuss", "archived"].includes(props.phase)) return true
  if (props.phase === "brainstorm" && props.brainstorm_visible) return true
  return false
})

// Group reactions by emoji and check if current user has each.
// Only emojis with at least one reaction render in the strip;
// the "+" picker exposes the full set so users can add
// emojis nobody's used yet.
type ReactionSummary = {
  emoji: string
  count: number
  mine: boolean
}
const reactionSummaries = computed<ReactionSummary[]>(() => {
  const byEmoji: Record<string, ReactionSummary> = {}
  for (const r of props.card.reactions) {
    const summary = byEmoji[r.emoji] || { emoji: r.emoji, count: 0, mine: false }
    summary.count++
    if (r.user_id && r.user_id === props.current_user_id) summary.mine = true
    byEmoji[r.emoji] = summary
  }
  // Sort by REACTION_EMOJIS order so chips stay in a stable
  // left-to-right order across clients.
  return REACTION_EMOJIS.filter((e) => byEmoji[e]).map((e) => byEmoji[e])
})

const pickerOpen = ref(false)
function togglePicker() {
  pickerOpen.value = !pickerOpen.value
}
function pickEmoji(emoji: string) {
  toggleReaction(emoji)
  pickerOpen.value = false
}

const commentsReadOnly = computed(() => props.phase === "archived")

function toggleReaction(emoji: string) {
  if (!reactableNow.value) return
  if (props.phase === "archived") return
  live.pushEvent("retro_toggle_reaction", { card_id: props.card.id, emoji })
}

const showTiedActions = computed(
  () =>
    (props.phase === "discuss" || props.phase === "archived") &&
    props.tied_actions.length > 0,
)
const readOnlyActions = computed(() => props.phase === "archived")

const live = useLiveVue()

const editing = ref(false)
const editDraft = ref(props.card.body)

const canVote = computed(() => props.is_my_vote || props.votes_remaining > 0)
const showVoteButton = computed(() => props.phase === "voting")
const showCount = computed(
  () => props.phase === "voting" || props.phase === "discuss" || props.phase === "archived",
)
const showEditDeleteAffordances = computed(() => props.phase === "brainstorm" && props.is_mine)

function startEdit() {
  editDraft.value = props.card.body
  editing.value = true
}

function commitEdit() {
  const body = editDraft.value.trim()
  if (!body) {
    editing.value = false
    return
  }
  if (body !== props.card.body) {
    live.pushEvent("retro_update_card", { card_id: props.card.id, body })
  }
  editing.value = false
}

function cancelEdit() {
  editDraft.value = props.card.body
  editing.value = false
}

function deleteCard() {
  if (!confirm("Delete this card?")) return
  live.pushEvent("retro_delete_card", { card_id: props.card.id })
}

function toggleVote() {
  if (props.is_my_vote) {
    live.pushEvent("retro_withdraw_vote", { card_id: props.card.id })
  } else if (props.votes_remaining > 0) {
    live.pushEvent("retro_vote", { card_id: props.card.id })
  }
}

function focusForDiscussion() {
  if (!props.is_host) return
  live.pushEvent("retro_set_discussing", { card_id: props.card.id })
}
</script>

<template>
  <article
    class="rounded-lg border bg-card p-2.5 space-y-2 group transition-all"
    :class="{
      'border-accent-bass/40': is_mine && phase === 'brainstorm',
      'cursor-pointer hover:border-accent-bass/40': is_host && phase === 'discuss',
      'ring-2 ring-accent-bass ring-offset-1 ring-offset-background border-accent-bass':
        is_discussing,
    }"
    @click="phase === 'discuss' ? focusForDiscussion() : undefined"
  >
    <div v-if="!editing" class="text-sm leading-snug whitespace-pre-wrap break-words">
      {{ card.body }}
    </div>

    <textarea
      v-else
      v-model="editDraft"
      maxlength="280"
      rows="3"
      class="w-full rounded-md border bg-background px-2 py-1.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
      @keydown.enter.exact.prevent="commitEdit"
      @keydown.escape="cancelEdit"
    ></textarea>

    <div class="flex items-center justify-between gap-2 text-[10px] text-muted-foreground">
      <span class="truncate">
        {{ card.author_alias
        }}<span
          v-if="card.author_display_name && card.author_display_name !== card.author_alias"
          class="text-muted-foreground/70"
        >
          · {{ card.author_display_name }}</span>
      </span>

      <div class="flex items-center gap-1.5">
        <!-- Edit/delete (brainstorm + own card) -->
        <template v-if="showEditDeleteAffordances && !editing">
          <button
            type="button"
            class="opacity-0 group-hover:opacity-100 transition-opacity hover:text-foreground"
            aria-label="Edit card"
            @click.stop="startEdit"
          >
            edit
          </button>
          <button
            type="button"
            class="opacity-0 group-hover:opacity-100 transition-opacity hover:text-destructive"
            aria-label="Delete card"
            @click.stop="deleteCard"
          >
            delete
          </button>
        </template>

        <template v-if="editing">
          <button
            type="button"
            class="hover:text-foreground"
            @click.stop="commitEdit"
          >
            save
          </button>
          <button
            type="button"
            class="hover:text-foreground"
            @click.stop="cancelEdit"
          >
            cancel
          </button>
        </template>

        <!-- Vote button -->
        <button
          v-if="showVoteButton"
          type="button"
          :disabled="!canVote"
          :aria-pressed="is_my_vote"
          :aria-label="is_my_vote ? 'Withdraw vote' : 'Vote for this card'"
          class="inline-flex items-center gap-1 rounded-md border px-1.5 py-0.5 text-[10px] font-medium transition-colors"
          :class="
            is_my_vote
              ? 'bg-accent-bass text-background border-accent-bass'
              : canVote
                ? 'hover:bg-accent border-input text-foreground'
                : 'opacity-40 cursor-not-allowed border-input'
          "
          @click.stop="toggleVote"
        >
          <span aria-hidden="true">●</span>
          <span class="tabular-nums">{{ tally }}</span>
        </button>

        <!-- Static count chip (discuss / archived) -->
        <span
          v-else-if="showCount && tally > 0"
          class="inline-flex items-center gap-1 rounded-md border border-input bg-card px-1.5 py-0.5 text-[10px] tabular-nums"
        >
          <span aria-hidden="true">●</span>
          {{ tally }}
        </span>
      </div>
    </div>

    <!-- Emoji reactions strip. Only emojis that have been used
         render as chips (with counts). The "+" button opens a
         picker showing the full allow-list so users can add
         emojis nobody's reacted with yet. Read-only on :archived
         (no +/toggle), but used chips still display. -->
    <div
      v-if="reactableNow"
      class="pt-2 mt-2 border-t border-input/40 flex flex-wrap items-center gap-1 relative"
      :aria-label="`Reactions on: ${card.body}`"
      @click.stop
    >
      <button
        v-for="r in reactionSummaries"
        :key="r.emoji"
        type="button"
        :aria-pressed="r.mine"
        :aria-label="`${r.mine ? 'Remove' : 'Add'} ${r.emoji} reaction`"
        :disabled="phase === 'archived'"
        class="inline-flex items-center gap-1 rounded-md border px-1.5 py-0.5 text-xs transition-colors"
        :class="
          r.mine
            ? 'bg-accent-bass/20 border-accent-bass text-foreground'
            : 'border-input hover:bg-accent text-muted-foreground hover:text-foreground'
        "
        @click="toggleReaction(r.emoji)"
      >
        <span aria-hidden="true">{{ r.emoji }}</span>
        <span class="tabular-nums text-[10px]">{{ r.count }}</span>
      </button>

      <button
        v-if="phase !== 'archived'"
        type="button"
        :aria-label="pickerOpen ? 'Close reaction picker' : 'Add reaction'"
        :aria-expanded="pickerOpen"
        class="inline-flex items-center justify-center rounded-md border border-dashed border-input px-1.5 py-0.5 text-[11px] text-muted-foreground hover:text-foreground hover:bg-accent"
        @click="togglePicker"
      >
        + 😊
      </button>

      <!-- Picker popover — six emojis to pick from. Clicking
           an emoji here toggles its reaction and closes. -->
      <div
        v-if="pickerOpen"
        class="absolute z-10 top-full mt-1 left-0 rounded-md border bg-card shadow-lg p-1 flex gap-0.5"
        role="menu"
      >
        <button
          v-for="emoji in REACTION_EMOJIS"
          :key="`picker-${emoji}`"
          type="button"
          role="menuitem"
          :aria-label="`Add ${emoji} reaction`"
          class="rounded hover:bg-accent px-1.5 py-1 text-base"
          @click="pickEmoji(emoji)"
        >
          {{ emoji }}
        </button>
      </div>
    </div>

    <!-- Comments thread. Collapsed by default; click to expand. -->
    <RetroComments
      v-if="reactableNow"
      :card_id="card.id"
      :comments="card.comments"
      :current_user_id="current_user_id"
      :read_only="commentsReadOnly"
    />

    <!-- Tied action items, nested below the card body during
         :discuss / :archived. Source-card context is implicit
         (the actions sit under their card), so the row hides
         the "re: …" tail. -->
    <div
      v-if="showTiedActions"
      class="pt-2 mt-2 border-t border-input/40 space-y-1.5"
      :aria-label="`Action items for: ${card.body}`"
    >
      <RetroActionRow
        v-for="action in tied_actions"
        :key="action.id"
        :action="action"
        :read_only="readOnlyActions"
        :hide_source_ref="true"
      />
    </div>
  </article>
</template>
