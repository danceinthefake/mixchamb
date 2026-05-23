// Verdict computation for a set of planning-poker votes. Shared
// between RevealPanel (the live round) and RoundHistory (past
// rounds in the session timeline).
//
// `?` and `☕` are stripped from the spread check — they're
// meta-votes (need info / need a break), not grades. Each verdict
// kind carries enough info for the consumer to render its own
// label + colour scheme; we deliberately don't bake the visual
// styling in here.

const QUESTION_CARD = "?"
const COFFEE_CARD = "☕"

export type Verdict =
  | { kind: "none" }
  | { kind: "single"; value: string }
  | { kind: "consensus"; value: string }
  | { kind: "close"; low: string; high: string }
  | { kind: "discuss" }
  | { kind: "all_question" }
  | { kind: "all_coffee" }

export function computeVerdict(values: string[], cards: string[]): Verdict {
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
    .map((v) => cards.indexOf(v))
    .filter((i) => i >= 0)
    .sort((a, b) => a - b)
  if (indices.length >= 2 && indices[indices.length - 1] - indices[0] <= 1) {
    return {
      kind: "close",
      low: cards[indices[0]],
      high: cards[indices[indices.length - 1]],
    }
  }
  return { kind: "discuss" }
}
