<script setup lang="ts">
// Freeform action items panel — visible during :discuss + read-
// only during :archived. Per-card actions are rendered nested
// inside RetroCard (spec §6); this panel handles only those
// actions whose source_card_id is null, plus the global
// "+Add action" form (which can still tie an action to a card
// via the source-card dropdown).

import { computed, inject, ref, type ComputedRef } from "vue"
import { useLiveVue } from "live_vue"
import RetroActionRow from "./RetroActionRow.vue"
import type { RetroSession, RetroActionItem } from "./RetroBoard.vue"

const participantAliases = inject<ComputedRef<string[]>>(
  "retro_participant_aliases",
  computed(() => []),
)

const props = defineProps<{
  session: RetroSession
  freeform_actions: RetroActionItem[]
  is_host: boolean
}>()

const live = useLiveVue()

const readOnly = computed(() => props.session.status === "archived")

// Retro → poker handoff: open action items become the poker queue
// (first one is the current story). Host-only; the chamber flips
// activity underneath everyone.
const openActionCount = computed(
  () => props.session.action_items.filter((a) => !a.completed).length,
)
function estimateInPoker() {
  if (
    !confirm(
      `Switch this chamber to planning poker with ${openActionCount.value} action item(s) queued as stories?`,
    )
  )
    return
  live.pushEvent("retro_estimate_in_poker", {})
}

const draft = ref({
  body: "",
  source_card_id: "",
  assignee_alias: "",
  due_date: "",
})

function submit() {
  const body = draft.value.body.trim()
  if (!body) return
  live.pushEvent("retro_add_action_item", {
    body,
    source_card_id: draft.value.source_card_id || null,
    assignee_alias: draft.value.assignee_alias.trim() || null,
    due_date: draft.value.due_date || null,
  })
  draft.value.body = ""
  draft.value.source_card_id = ""
  draft.value.assignee_alias = ""
  draft.value.due_date = ""
}
</script>

<template>
  <section class="rounded-xl border bg-card/40 p-4 space-y-4">
    <header class="flex items-baseline justify-between gap-3">
      <h2 class="text-sm uppercase tracking-wider text-muted-foreground font-display">
        Freeform action items
      </h2>
      <button
        v-if="is_host && openActionCount > 0"
        id="retro-estimate-in-poker"
        type="button"
        @click="estimateInPoker"
        class="text-xs font-medium rounded-md border px-3 py-1 hover:bg-accent"
        title="Flip the chamber to planning poker with the open action items queued as stories"
      >
        Estimate in poker · {{ openActionCount }}
      </button>
    </header>

    <div v-if="freeform_actions.length > 0" class="space-y-2">
      <RetroActionRow
        v-for="action in freeform_actions"
        :key="action.id"
        :action="action"
        :read_only="readOnly"
        :hide_source_ref="true"
      />
    </div>

    <p v-else class="text-xs text-muted-foreground italic">
      No freeform action items yet. Per-card actions are nested under their cards above.
    </p>

    <!-- Add form -->
    <form v-if="!readOnly" @submit.prevent="submit" class="space-y-2 pt-2 border-t">
      <textarea
        v-model="draft.body"
        maxlength="280"
        rows="2"
        placeholder="Add an action item…"
        aria-label="New action item body"
        class="w-full rounded-md border bg-card px-2.5 py-1.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
      ></textarea>
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
        <input
          v-model="draft.assignee_alias"
          type="text"
          maxlength="80"
          placeholder="Assignee (optional)"
          aria-label="Assignee alias"
          list="retro-add-assignees"
          class="rounded-md border bg-card px-2.5 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
        />
        <datalist id="retro-add-assignees">
          <option v-for="name in participantAliases" :key="name" :value="name" />
        </datalist>
        <input
          v-model="draft.due_date"
          type="date"
          aria-label="Due date"
          class="rounded-md border bg-card px-2.5 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
        />
        <select
          v-model="draft.source_card_id"
          aria-label="Tie to a card (optional)"
          class="rounded-md border bg-card px-2.5 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
        >
          <option value="">No source card (freeform)</option>
          <option v-for="c in session.cards" :key="c.id" :value="c.id">
            {{ c.body.slice(0, 50) }}{{ c.body.length > 50 ? "…" : "" }}
          </option>
        </select>
      </div>
      <div class="flex justify-end">
        <button
          type="submit"
          :disabled="!draft.body.trim()"
          class="text-xs font-medium rounded-md bg-accent-bass text-background px-3 py-1.5 hover:bg-accent-bass/90 disabled:opacity-40 disabled:cursor-not-allowed"
        >
          Add action
        </button>
      </div>
    </form>
  </section>
</template>
