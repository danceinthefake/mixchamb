<script setup lang="ts">
// Open action items from the team's previous retros (spec §13).
// Shown on :setup (plan the retro around what's still open) and
// :discuss (where actions get handled). Each row: carry it into
// this retro as a freeform item, or mark it done out-of-band.

import { useLiveVue } from "live_vue"

export type PreviousAction = {
  id: string
  body: string
  assignee_alias: string | null
  due_date: string | null
  from_title: string | null
  from_archived_at: string | null
}

defineProps<{ items: PreviousAction[] }>()

const live = useLiveVue()

function carryOver(id: string) {
  live.pushEvent("retro_carry_over_action", { action_id: id })
}

function markDone(id: string) {
  live.pushEvent("retro_complete_previous_action", { action_id: id })
}
</script>

<template>
  <section
    v-if="items.length > 0"
    id="retro-carry-over"
    class="rounded-xl border border-accent-bass/40 bg-accent-bass/10 p-4 space-y-3"
  >
    <header class="space-y-0.5">
      <h2 class="text-sm uppercase tracking-wider text-muted-foreground font-display">
        Still open from last time · {{ items.length }}
      </h2>
      <p class="text-xs text-muted-foreground">
        Action items nobody closed. Carry one into this retro, or mark it done.
      </p>
    </header>

    <ul class="space-y-2">
      <li
        v-for="a in items"
        :key="a.id"
        class="rounded-md border bg-card px-3 py-2 flex flex-wrap items-center gap-x-3 gap-y-1"
      >
        <div class="flex-1 min-w-0 text-sm">
          <p class="break-words">{{ a.body }}</p>
          <p class="text-xs text-muted-foreground">
            <span v-if="a.assignee_alias">{{ a.assignee_alias }} · </span>
            <span v-if="a.due_date">due {{ a.due_date }} · </span>
            from {{ a.from_title || "Untitled retro" }}
          </p>
        </div>
        <div class="flex gap-1.5 shrink-0">
          <button
            type="button"
            @click="carryOver(a.id)"
            class="rounded-md bg-accent-bass text-background px-2.5 py-1 text-xs font-medium hover:bg-accent-bass/90"
          >
            Carry over
          </button>
          <button
            type="button"
            @click="markDone(a.id)"
            class="rounded-md border px-2.5 py-1 text-xs font-medium hover:bg-accent"
          >
            Mark done
          </button>
        </div>
      </li>
    </ul>
  </section>
</template>
