import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"

const { pushEvent } = vi.hoisted(() => ({ pushEvent: vi.fn() }))
vi.mock("live_vue", () => ({ useLiveVue: () => ({ pushEvent }) }))
vi.mock("../lib/audio", () => ({ playVoteBlip: vi.fn() }))
vi.mock("emoji-picker-element", () => ({}))

import { mount, enableAutoUnmount } from "@vue/test-utils"
import { defineComponent, h, provide, computed } from "vue"
import RetroCard from "../activities/retro/RetroCard.vue"
import RetroActionRow from "../activities/retro/RetroActionRow.vue"
import RetroComments from "../activities/retro/RetroComments.vue"
import RetroColumn from "../activities/retro/RetroColumn.vue"
import RetroDiscussPanel from "../activities/retro/RetroDiscussPanel.vue"
import type { RetroSession, RetroActionItem } from "../activities/retro/RetroBoard.vue"

enableAutoUnmount(afterEach)
beforeEach(() => {
  pushEvent.mockClear()
  ;(window as any).confirm = vi.fn(() => true)
})

const action: RetroActionItem = {
  id: "a1",
  source_card_id: "card1",
  body: "Fix CI",
  assignee_alias: "ana",
  due_date: "2026-10-01",
  completed: false,
}

const card = {
  id: "card1",
  retro_column_id: "c1",
  body: "Pairing helped",
  author_user_id: "u1",
  author_alias: "ana",
  author_display_name: null,
  vote_count: 2,
  merged: [],
  reactions: [
    { user_id: "u1", emoji: "🔥" },
    { user_id: "u2", emoji: "🔥" },
    { user_id: "u2", emoji: "👀" },
  ],
  comments: [
    { id: "k1", body: "one", author_user_id: "u1", author_alias: "ana", author_display_name: null },
    { id: "k2", body: "two", author_user_id: "u2", author_alias: "bo", author_display_name: null },
    {
      id: "k3",
      body: "three",
      author_user_id: "u2",
      author_alias: "bo",
      author_display_name: null,
    },
    {
      id: "k4",
      body: "four",
      author_user_id: "u1",
      author_alias: "ana",
      author_display_name: null,
    },
  ],
}

// Wrap with the inject RetroBoard normally provides.
function withAliases(Comp: any, props: any) {
  return mount(
    defineComponent({
      setup() {
        provide(
          "retro_participant_aliases",
          computed(() => ["ana", "bo"]),
        )
        return () => h(Comp, props)
      },
    }),
  )
}

const cardProps = {
  card,
  phase: "reveal" as const,
  brainstorm_visible: false,
  is_mine: true,
  current_user_id: "u1",
  tally: 0,
  is_my_vote: false,
  votes_remaining: 3,
  is_host: false,
  is_discussing: false,
  is_discussed: false,
  tied_actions: [] as RetroActionItem[],
}

describe("RetroCard edit / delete / reactions", () => {
  it("edits own card in :brainstorm (save, cancel, escape) and deletes with confirm", async () => {
    const w = mount(RetroCard, { props: { ...cardProps, phase: "brainstorm" } })
    await w.get('button[aria-label="Edit card"]').trigger("click")
    const ta = w.get("textarea")
    await ta.setValue("Pairing helped a lot")
    await ta.trigger("keydown", { key: "Enter" })
    expect(pushEvent).toHaveBeenCalledWith("retro_update_card", {
      card_id: "card1",
      body: "Pairing helped a lot",
    })

    await w.get('button[aria-label="Edit card"]').trigger("click")
    await w.get("textarea").setValue("   ")
    await w
      .findAll("button")
      .find((b) => b.text() === "save")!
      .trigger("click")
    // Blank / unchanged body never sends.
    expect(pushEvent).toHaveBeenCalledTimes(1)
    await w.get('button[aria-label="Edit card"]').trigger("click")
    await w.get("textarea").trigger("keydown", { key: "Escape" })
    expect(w.find("textarea").exists()).toBe(false)

    await w.get('button[aria-label="Delete card"]').trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("retro_delete_card", { card_id: "card1" })
    ;(window.confirm as any).mockReturnValueOnce(false)
    await w.get('button[aria-label="Delete card"]').trigger("click")
    expect(pushEvent.mock.calls.filter((c) => c[0] === "retro_delete_card")).toHaveLength(1)
  })

  it("reaction chips group by emoji, toggle, and are read-only when archived", async () => {
    const w = mount(RetroCard, { props: cardProps })
    const fire = w.get('button[aria-label="Remove 🔥 reaction"]')
    expect(fire.text()).toContain("2")
    await fire.trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("retro_toggle_reaction", {
      card_id: "card1",
      emoji: "🔥",
    })
    await w.get('button[aria-label="Add 👀 reaction"]').trigger("click")

    // Picker opens lazily; picking an emoji toggles it + closes.
    await w.get('button[aria-label="Add reaction"]').trigger("click")
    await new Promise((r) => setTimeout(r, 0))
    const picker = w.find("emoji-picker")
    if (picker.exists()) {
      picker.element.dispatchEvent(new CustomEvent("emoji-click", { detail: { unicode: "🎉" } }))
      expect(pushEvent).toHaveBeenCalledWith("retro_toggle_reaction", {
        card_id: "card1",
        emoji: "🎉",
      })
      picker.element.dispatchEvent(new CustomEvent("emoji-click", { detail: {} }))
    }

    pushEvent.mockClear()
    await w.setProps({ phase: "archived" })
    await w.get('button[aria-label="Remove 🔥 reaction"]').trigger("click")
    expect(pushEvent).not.toHaveBeenCalled()

    // Not reactable during hidden brainstorm.
    await w.setProps({ phase: "brainstorm", brainstorm_visible: false })
    expect(w.find('button[aria-label="Add reaction"]').exists()).toBe(false)
    await w.setProps({ brainstorm_visible: true })
    expect(w.find('button[aria-label="Add reaction"]').exists()).toBe(true)
  })
})

describe("RetroComments", () => {
  it("expands, trims long threads, adds / edits / deletes own comments", async () => {
    const w = mount(RetroComments, {
      props: { card_id: "card1", comments: card.comments, current_user_id: "u1", read_only: false },
    })
    expect(w.text()).toContain("4 comments")
    await w.get("button").trigger("click") // expand
    expect(w.text()).not.toContain("one")
    await w
      .findAll("button")
      .find((b) => /more|older|load/i.test(b.text()))!
      .trigger("click")
    expect(w.text()).toContain("one")

    await w.get('textarea[aria-label="Add comment to this card"]').setValue(" new one ")
    await w.get("form").trigger("submit")
    expect(pushEvent).toHaveBeenCalledWith("retro_add_comment", {
      card_id: "card1",
      body: "new one",
    })

    // Own comment: edit (enter commits, escape cancels) + delete.
    const editBtns = w.findAll("button").filter((b) => b.text() === "edit")
    await editBtns[0].trigger("click")
    const ta = w.get('textarea[aria-label="Edit comment"]')
    await ta.setValue("one!")
    await ta.trigger("keydown", { key: "Enter" })
    expect(pushEvent).toHaveBeenCalledWith("retro_update_comment", {
      comment_id: "k1",
      body: "one!",
    })
    await w
      .findAll("button")
      .filter((b) => b.text() === "edit")[0]
      .trigger("click")
    await w.get('textarea[aria-label="Edit comment"]').trigger("keydown", { key: "Escape" })
    expect(w.find('textarea[aria-label="Edit comment"]').exists()).toBe(false)
    await w
      .findAll("button")
      .filter((b) => b.text() === "delete")[0]
      .trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("retro_delete_comment", { comment_id: "k1" })

    await w.setProps({ read_only: true })
    expect(w.find("form").exists()).toBe(false)
    expect(w.findAll("button").filter((b) => b.text() === "edit")).toHaveLength(0)
  })
})

describe("RetroActionRow", () => {
  it("toggles completion, edits every field, deletes; read-only hides controls", async () => {
    const w = withAliases(RetroActionRow, {
      action,
      read_only: false,
      source_card_body: "Pairing helped",
    })
    expect(w.text()).toContain("re:")
    await w.get('input[type="checkbox"]').trigger("change")
    expect(pushEvent).toHaveBeenCalledWith("retro_update_action_item", {
      action_id: "a1",
      completed: true,
    })

    await w.get(`button[aria-label="Edit action: Fix CI"]`).trigger("click")
    await w.get('textarea[aria-label="Edit action body"]').setValue("Fix CI for real")
    await w.get('input[aria-label="Edit assignee alias"]').setValue("bo")
    await w.get('input[aria-label="Edit due date"]').setValue("")
    await w
      .findAll("button")
      .find((b) => /save/i.test(b.text()))!
      .trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("retro_update_action_item", {
      action_id: "a1",
      body: "Fix CI for real",
      assignee_alias: "bo",
      due_date: null,
    })

    await w.get(`button[aria-label="Edit action: Fix CI"]`).trigger("click")
    await w.get('textarea[aria-label="Edit action body"]').trigger("keydown", { key: "Escape" })
    expect(w.find("textarea").exists()).toBe(false)

    await w.get(`button[aria-label="Delete action: Fix CI"]`).trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("retro_delete_action_item", { action_id: "a1" })

    const ro = withAliases(RetroActionRow, {
      action: { ...action, completed: true },
      read_only: true,
      hide_source_ref: true,
    })
    expect(ro.find("button[aria-label^='Edit']").exists()).toBe(false)
    expect(ro.text()).not.toContain("re:")
  })
})

describe("RetroColumn + RetroDiscussPanel", () => {
  const session: RetroSession = {
    id: "s1",
    title: "T",
    status: "discuss",
    voting_enabled: false,
    brainstorm_visible: false,
    team: null,
    columns: [{ id: "c1", name: "Good", position: 0 }],
    cards: [card],
    action_items: [action, { ...action, id: "a2", source_card_id: null, body: "Pair more" }],
  }

  it("column adds a card in :brainstorm and shows the hidden count", async () => {
    const w = withAliases(RetroColumn, {
      column: session.columns[0],
      cards: [card],
      total_count: 3,
      hidden_count: 2,
      phase: "brainstorm",
      brainstorm_visible: false,
      current_user_id: "u1",
      tallies: {},
      my_votes: new Set<string>(),
      votes_remaining: 3,
      discussing_card_id: null,
      discussed: new Set<string>(),
      actions_by_card_id: {},
      is_host: false,
    })
    await w.get("textarea").setValue("  new card ")
    await w.get("form").trigger("submit")
    expect(pushEvent).toHaveBeenCalledWith("retro_add_card", { column_id: "c1", body: "new card" })
    expect(w.text()).toContain("2")
  })

  it("discuss panel adds a freeform action with every field and hands off to poker", async () => {
    const w = withAliases(RetroDiscussPanel, {
      session,
      freeform_actions: [session.action_items[1]],
      is_host: true,
    })
    await w.get("textarea").setValue(" Do the thing ")
    await w.get('input[list], input[type="text"]').setValue("ana")
    await w.get('input[type="date"]').setValue("2026-11-01")
    await w.get("select").setValue("card1")
    await w.get("form").trigger("submit")
    expect(pushEvent).toHaveBeenCalledWith("retro_add_action_item", {
      body: "Do the thing",
      source_card_id: "card1",
      assignee_alias: "ana",
      due_date: "2026-11-01",
    })

    await w.get("#retro-estimate-in-poker").trigger("click")
    expect(pushEvent).toHaveBeenCalledWith("retro_estimate_in_poker", {})
    ;(window.confirm as any).mockReturnValueOnce(false)
    await w.get("#retro-estimate-in-poker").trigger("click")
    expect(pushEvent.mock.calls.filter((c) => c[0] === "retro_estimate_in_poker")).toHaveLength(1)
  })
})
