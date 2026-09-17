// Markdown snapshot of a retro — title, cards by column (votes desc,
// per-card actions nested), freeform actions, team + permalink
// footer. Pure so it's unit-testable; the board copies it to the
// clipboard from the archived banner.

import type { RetroSession, RetroActionItem } from "./RetroBoard.vue"

function actionLine(a: RetroActionItem, indent = ""): string {
  const assignee = a.assignee_alias ? ` — @${a.assignee_alias}` : ""
  const due = a.due_date ? ` _(by ${a.due_date})_` : ""
  const done = a.completed ? "[x] " : "[ ] "
  return `${indent}- ${done}${a.body}${assignee}${due}`
}

export function retroToMarkdown(session: RetroSession, permalink?: string): string {
  const lines: string[] = [`# ${session.title || "Retro"}`, ""]

  for (const col of session.columns) {
    lines.push(`## ${col.name}`)
    const cards = session.cards
      .filter((c) => c.retro_column_id === col.id)
      .sort((a, b) => b.vote_count - a.vote_count)
    if (cards.length === 0) lines.push("_(no cards)_")
    for (const c of cards) {
      const votes = c.vote_count > 0 ? ` _(${c.vote_count} votes)_` : ""
      lines.push(`- ${c.body}${votes} — ${c.author_alias}`)
      for (const a of session.action_items.filter((a) => a.source_card_id === c.id))
        lines.push(actionLine(a, "  "))
    }
    lines.push("")
  }

  const freeform = session.action_items.filter((a) => !a.source_card_id)
  if (freeform.length > 0) {
    lines.push("## Action items")
    for (const a of freeform) lines.push(actionLine(a))
    lines.push("")
  }

  const footer: string[] = []
  if (session.team) footer.push(`Team: ${session.team.name}`)
  if (permalink) footer.push(permalink)
  if (footer.length > 0) lines.push(footer.join(" · "))

  return lines.join("\n").trimEnd() + "\n"
}
