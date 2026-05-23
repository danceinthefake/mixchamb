<script setup lang="ts">
// Reveal panel: visible only when status === 'revealed'. Shows a
// per-value distribution plus stats. Numeric decks (fibonacci,
// modified_fibonacci, pow2) get average + median; the t-shirt
// deck gets mode only (per features/planning-poker.md §3).

import { computed } from "vue"
import type { DeckId, Participant } from "./PokerBoard.vue"

const props = defineProps<{
  deck: DeckId
  cards: string[]
  votes: Record<string, string>
  participants: Participant[]
}>()

const QUESTION_CARD = "?"
const COFFEE_CARD = "☕"

// Top-of-panel verdict — the one-glance answer to "what did the
// team land on?" before the eye has to parse the distribution
// bars. `?` and `☕` are stripped from the spread check because
// they're meta-votes (I don't know / I need a break), not grades;
// we still surface them in the labels for the "everyone …" cases.
type Verdict =
  | { kind: "none" }
  | { kind: "single"; value: string }
  | { kind: "consensus"; value: string }
  | { kind: "close"; low: string; high: string }
  | { kind: "discuss" }
  | { kind: "all_question" }
  | { kind: "all_coffee" }

const verdict = computed<Verdict>(() => {
  const values = Object.values(props.votes)
  if (values.length === 0) return { kind: "none" }
  if (values.length === 1) return { kind: "single", value: values[0] }

  if (values.every((v) => v === values[0])) {
    if (values[0] === QUESTION_CARD) return { kind: "all_question" }
    if (values[0] === COFFEE_CARD) return { kind: "all_coffee" }
    return { kind: "consensus", value: values[0] }
  }

  const grading = values.filter((v) => v !== QUESTION_CARD && v !== COFFEE_CARD)
  if (grading.length === 0) return { kind: "discuss" }

  const uniq = [...new Set(grading)]
  if (uniq.length === 1) return { kind: "consensus", value: uniq[0] }

  const indices = uniq
    .map((v) => props.cards.indexOf(v))
    .filter((i) => i >= 0)
    .sort((a, b) => a - b)
  if (indices.length >= 2 && indices[indices.length - 1] - indices[0] <= 1) {
    return {
      kind: "close",
      low: props.cards[indices[0]],
      high: props.cards[indices[indices.length - 1]],
    }
  }
  return { kind: "discuss" }
})

const numericDecks: DeckId[] = ["fibonacci", "modified_fibonacci", "pow2"]

// Distribution: each unique vote value -> count of voters.
const distribution = computed(() => {
  const counts = new Map<string, number>()
  for (const v of Object.values(props.votes)) {
    counts.set(v, (counts.get(v) ?? 0) + 1)
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1])
})

// Numeric votes only — `?` and `☕` skipped. "½" → 0.5.
const numericValues = computed(() => {
  if (!numericDecks.includes(props.deck)) return []
  const out: number[] = []
  for (const v of Object.values(props.votes)) {
    if (v === "½") out.push(0.5)
    else {
      const n = Number(v)
      if (Number.isFinite(n)) out.push(n)
    }
  }
  return out
})

const average = computed(() => {
  if (numericValues.value.length === 0) return null
  const sum = numericValues.value.reduce((a, b) => a + b, 0)
  return sum / numericValues.value.length
})

const median = computed(() => {
  const xs = [...numericValues.value].sort((a, b) => a - b)
  if (xs.length === 0) return null
  const mid = Math.floor(xs.length / 2)
  return xs.length % 2 ? xs[mid] : (xs[mid - 1] + xs[mid]) / 2
})

const mode = computed(() => {
  if (distribution.value.length === 0) return null
  return distribution.value[0][0]
})

function format(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(1)
}

const isNumericDeck = computed(() => numericDecks.includes(props.deck))
const totalVotes = computed(() => Object.keys(props.votes).length)
</script>

<template>
  <div class="space-y-3">
    <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
      Reveal
    </p>

    <div v-if="totalVotes === 0" class="text-sm text-muted-foreground italic">
      No votes were cast in this round.
    </div>

    <div v-else class="space-y-4">
      <!-- Verdict headline. Cheap one-liner that turns the
           distribution bars into an actionable read: did we agree,
           are we close enough, or do we need to talk about it.
           Colour-codes by outcome (success / foreground / primary)
           so the eye latches before parsing the numbers. -->
      <p
        v-if="verdict.kind === 'consensus'"
        class="text-center text-2xl font-bold font-display text-success"
      >
        Consensus: {{ verdict.value }}
      </p>
      <p
        v-else-if="verdict.kind === 'close'"
        class="text-center text-2xl font-bold font-display text-foreground"
      >
        Close call — {{ verdict.low }} or {{ verdict.high }}
      </p>
      <p
        v-else-if="verdict.kind === 'discuss'"
        class="text-center text-2xl font-bold font-display text-primary"
      >
        Wide range — discuss
      </p>
      <p
        v-else-if="verdict.kind === 'single'"
        class="text-center text-base font-bold font-display text-foreground"
      >
        One vote in: {{ verdict.value }}
      </p>
      <p
        v-else-if="verdict.kind === 'all_question'"
        class="text-center text-base font-bold font-display text-muted-foreground"
      >
        Everyone wants clarification
      </p>
      <p
        v-else-if="verdict.kind === 'all_coffee'"
        class="text-center text-base font-bold font-display text-muted-foreground"
      >
        Time for a break ☕
      </p>

      <!-- Distribution: each value with a bar showing its share. -->
      <ul class="space-y-1.5">
        <li
          v-for="[value, count] in distribution"
          :key="value"
          class="flex items-center gap-3"
        >
          <span class="w-10 font-mono font-bold text-base tabular-nums text-right">
            {{ value }}
          </span>
          <div class="flex-1 h-5 rounded-md bg-muted overflow-hidden">
            <div
              class="h-full bg-accent-poker/70"
              :style="{ width: (count / totalVotes) * 100 + '%' }"
            ></div>
          </div>
          <span class="text-xs text-muted-foreground tabular-nums w-8">
            {{ count }}
          </span>
        </li>
      </ul>

      <!-- Stats: numeric decks get avg + median, t-shirt gets mode.
           Values picked up the brand green token (--success) so the
           outcome numbers read as "the result you walked away with"
           rather than just more body text. -->
      <dl class="flex flex-wrap gap-x-6 gap-y-1 text-sm">
        <template v-if="isNumericDeck">
          <div v-if="average !== null" class="flex gap-1.5">
            <dt class="text-muted-foreground">Average:</dt>
            <dd class="font-bold font-mono text-success">{{ format(average) }}</dd>
          </div>
          <div v-if="median !== null" class="flex gap-1.5">
            <dt class="text-muted-foreground">Median:</dt>
            <dd class="font-bold font-mono text-success">{{ format(median) }}</dd>
          </div>
        </template>
        <div v-if="mode !== null" class="flex gap-1.5">
          <dt class="text-muted-foreground">Mode:</dt>
          <dd class="font-bold font-mono text-success">{{ mode }}</dd>
        </div>
      </dl>
    </div>
  </div>
</template>
