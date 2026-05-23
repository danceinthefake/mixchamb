<script setup lang="ts">
// Vote picker. Renders the deck's card values as buttons; clicking
// one fires `pick(card)`. The currently-selected card is
// highlighted so the user can see what they voted at a glance —
// PokerBoard.vue treats a click on the selected card as a withdraw
// (toggle off).

defineProps<{
  cards: string[]
  selected: string | null
}>()

defineEmits<{ pick: [card: string] }>()
</script>

<template>
  <div class="space-y-2">
    <p class="text-xs uppercase tracking-wider text-muted-foreground font-display text-center">
      Pick a card
    </p>
    <!-- Cards take 5:7 playing-card proportions at 56x80 — half
         the scale of the ParticipantsRow silhouette. Same object
         type, two scales: deck pick is the same kind of card the
         player flips to reveal. Centered to match the section's
         label + the silhouettes row above. -->
    <div class="flex flex-wrap gap-2 justify-center">
      <button
        v-for="(card, i) in cards"
        :key="card"
        type="button"
        @click="$emit('pick', card)"
        :aria-pressed="card === selected"
        :class="[
          'pad-touch touch-manipulation relative w-14 h-20 rounded-md text-xl font-bold font-display border flex items-center justify-center transition-all cursor-pointer',
          card === selected
            ? 'bg-primary text-primary-foreground border-primary shadow-md scale-105 -translate-y-0.5'
            : 'bg-card hover:bg-accent text-foreground border-border',
        ]"
      >
        {{ card }}
        <!-- Keybind chip: number keys 1-9 vote the card at that
             index (PokerBoard.vue owns the listener). Hidden past
             index 8 since we only bind nine keys; rare cards stay
             mouse-only. Hidden on small viewports — the chip is
             ~10px tall and we don't want it stealing space on a
             56x80 card on mobile. -->
        <kbd
          v-if="i < 9"
          aria-hidden="true"
          class="hidden sm:inline-block absolute bottom-1 right-1 text-[9px] px-1 rounded bg-background/70 text-muted-foreground font-mono font-normal leading-tight"
        >
          {{ i + 1 }}
        </kbd>
      </button>
    </div>
    <p v-if="selected" class="text-xs text-muted-foreground text-center">
      Voted <span class="font-mono font-bold text-foreground">{{ selected }}</span> ·
      tap again to withdraw.
    </p>
  </div>
</template>
