# Retrospective — feature spec

Planned as the third activity in a mixchamb chamber (after music
and planning poker). This doc is the per-section reference for
what retro is, how it behaves, and which decisions are locked.
The architectural framing — why activity is a column on
`chambers`, the same-shell-different-component pattern, the
ephemeral-state-in-Chambers.Server convention — lives in
`../BRAINSTORM-v4.md` §§3 + 5 + 6 and was proven by planning
poker (`./planning-poker.md`).

Code map (planned):
`lib/mixchamb/retro/retro_session.ex`,
`lib/mixchamb/retro/retro_column.ex`,
`lib/mixchamb/retro/retro_card.ex`,
`lib/mixchamb/retro/retro_action_item.ex`,
`lib/mixchamb/chambers/server.ex` (retro_* casts for ephemeral
vote state),
`lib/mixchamb_web/live/chamber_live.ex` (retro_* events +
broadcasts),
`assets/vue/activities/retro/` (component split per §10).

All sections below are **Locked** unless noted otherwise.

---

## 1. Session phase machine — _Locked_

**Decision:** Five or six phases depending on whether voting is
enabled (§5 — opt-in, off by default). Host-advanced linearly,
no skipping forward, no jumping back. Each transition is a
single host action.

**Default flow (voting disabled):**
```
:setup → :brainstorm → :reveal → :discuss → :archived
        Start brainstorm  Reveal cards  Start discussion  Archive
```

**With voting enabled:**
```
:setup → :brainstorm → :reveal → :voting → :discuss → :archived
        Start brainstorm  Reveal cards  Start voting  Start discussion  Archive
```

The Reveal button advances to `:voting` if `voting_enabled` is
true, otherwise straight to `:discuss`. Same button label
either way; the post-reveal phase is implicit in the session
setting.

| Phase | What's happening | Who can do what |
|---|---|---|
| `:setup` | Host customises session title + 4 column names. No cards yet. | Host edits title + column names. Participants can join + edit their alias but otherwise wait. |
| `:brainstorm` | Cards are being written. Each participant sees their own cards but **not** others' (per §4). | Everyone adds / edits / deletes their own cards. Host can also write. Host can't rename columns once brainstorm starts (cards already belong to a column id; rename would be cosmetic-only and confusing). |
| `:reveal` | All cards visible. Read-and-discuss time, no voting yet. | Everyone reads. No card edits (own or others'). Host advances when discussion lulls. |
| `:voting` | Dot voting active. | Each participant has 3 votes (§5) to spend across any cards. Vote / unvote freely until host advances. Cards still read-only. |
| `:discuss` | Cards sorted by vote count desc. Action items being added. | Anyone adds action items, optionally tied to a card. Host can mark a card as "currently discussing" (highlights it for everyone). |
| `:archived` | Session frozen. Visible in chamber history. | Everyone read-only. Action items remain editable for `completed`/assignee/due-date for a configurable grace window (out of scope for v1; treat as fully read-only on archive). |

**Why no grouping phase:** card grouping / merging is the highest-
risk UI work in retro tools (drag-to-cluster, "merge duplicates"
modals, ownership rules). EasyRetro and Reetro both ship without
it as standard; vote count alone is enough to surface themes.
Defer to v2 if teams ask.

**Why no separate wrapup phase:** action items get added during
`:discuss` as themes emerge. The transition into `:archived` is
the wrapup — host reviews actions one last time, exports markdown,
clicks Archive. Folding wrapup into discuss avoids a phase where
the only action is "click Archive."

## 2. Columns — _Locked_

**Decision:** **4 columns**, custom names per session. Default
seed at session creation: **Good / Bad / Start / Thanks**.
Host can rename each column inline during `:setup` only.

| Column position | Default name | Rename window |
|---|---|---|
| 1 | Good | `:setup` only |
| 2 | Bad | `:setup` only |
| 3 | Start | `:setup` only |
| 4 | Thanks | `:setup` only |

**Why the user's team's default rather than Start/Stop/Continue:**
the repo owner's team uses Good/Bad/Start/Thanks. It's also a
strong default for general teams — "Good" + "Bad" are immediately
understood, "Start" matches the common "Continue/Stop/Start"
slot, and "Thanks" is the only column that explicitly invites
appreciation (an often-missed retro pattern). Teams that prefer
SSC / MSG / 4Ls can rename to those.

**Why 4 fixed columns:** keeps the layout predictable on mobile
(4 columns of card width × N rows works in a vertical scroll;
variable counts break this). 4 is also the practical maximum
EasyRetro and Reetro ship — past 4, columns become too narrow on
laptop and unusable on mobile.

**Why rename only during `:setup`:** once a card belongs to a
column id, renaming the column changes the displayed bucket
under the card without moving the card. Cards added under "Bad"
shouldn't suddenly be under "Things to fix" — the author wrote
them with the original frame in mind. Rename-then-rebrainstorm
is a v2 conversation; for v1, lock at the brainstorm threshold.

**Presets (v2 later):** §1's decision matrix listed
Start/Stop/Continue, Mad/Sad/Glad, 4Ls. After custom-rename
ships, add a preset dropdown in `:setup` that prefills the four
name inputs — no schema change needed.

## 3. Card lifecycle — _Locked_

**Decision:** Cards are author-owned, alias-tagged, 280-char limit.
Edit/delete by author only during writable phases.

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `retro_session_id` | uuid fk | |
| `retro_column_id` | uuid fk | Determines which column the card lives in. Card-move (drag to different column) is out of scope for v1. |
| `body` | text, 1–280 chars | Validated server-side. Empty / whitespace-only rejected. |
| `author_user_id` | uuid fk, nullable | `nil` for anonymous-user cards — same pattern as anon poker votes. |
| `author_alias` | string | Snapshot of the author's display alias at card-create time. Stays even if author changes alias mid-session (the card represents what they said as that person at that moment). |
| `vote_count` | int, default 0 | Materialised when `:voting` → `:discuss` (see §5). `0` during writable phases. |
| `inserted_at`, `updated_at` | timestamps | |

**Editability gate:**

| Phase | Author can edit own | Author can delete own | Host can edit/delete others' |
|---|---|---|---|
| `:setup` | n/a (no cards yet) | n/a | n/a |
| `:brainstorm` | yes | yes | **no** — host has no special card privilege, parallel to poker's "host can't see others' votes pre-reveal" |
| `:reveal` | no | no | no |
| `:voting` | no | no | no |
| `:discuss` | no | no | no |
| `:archived` | no | no | no |

Editing past `:brainstorm` is disabled because cards become the
shared substrate for voting + discussion. If you typo'd, that's
your typo — same constraint as a sticky note in an in-person
retro.

**Authorship display:** alias-tagged (e.g. `Brave Otter 12 ·
alex`), same component pattern as poker reveal. Cards never go
fully anonymous in v1 — the social contract of "I said this,
this is what I think" matters more than the small reduction in
candor that anonymity would buy. Teams that need anonymity have
EasyRetro's anon mode; mixchamb's positioning is "team that
trusts each other enough to say things in their own name."

## 4. Brainstorm visibility — _Locked_

**Decision:** Cards are **hidden from non-authors** during
`:brainstorm`. You see only the cards you wrote. Card count per
column is visible to everyone ("Bad — 3 cards so far") so the
room can gauge brainstorm pace without seeing content.

Reveal transition flips every card to visible simultaneously
across all clients via `{:retro, :revealed}` broadcast. Cards
written after `:reveal` aren't possible (writing is gated to
`:brainstorm` phase) — but if late `:brainstorm` writes race the
reveal broadcast, the server enforces phase at message receipt,
so a card committed after reveal is rejected with an error
(client surfaces it as "Brainstorm ended — that one didn't
land").

**Why hidden by default:** matches EasyRetro / Parabol / Reetro
default. Reduces groupthink ("oh, X already wrote that, I won't
bother"), reduces piggybacking ("X said something, so I'll just
+1"), and produces a more honest distribution of perspectives.
The cost — people can't build on each other's ideas — is what
`:reveal` is for.

**Why no host toggle for "always visible" mode:** an extra
setting buys little (teams that prefer it can have everyone
write into a shared Miro instead; mixchamb's retro is opinionated
about the hidden-until-reveal flow). Revisit only if multiple
teams ask.

## 5. Voting model — _Locked_

**Decision:** Voting is **opt-in, default off**. Host toggles
`voting_enabled` any time before `:discuss` (i.e. during
`:setup`, `:brainstorm`, `:reveal`, or `:voting`). Locked once
`:discuss` begins — by then the flow is committed. When
enabled: **3 dot votes per participant**, spread across any
cards in any columns. Vote / unvote freely during `:voting`. No
per-user vote history persisted — only materialised counts.

**Why off by default:** most teams run retros as
talk-it-through, not vote-and-prioritise. Voting matters when
the team has too many cards to handle linearly in discussion
time. A 4-person team with 8 cards doesn't need dots; a
12-person team with 40 cards does. Default-off matches the
common case; opt-in covers the larger case.

**Why toggleable mid-session (until `:discuss`):** the host
often can't gauge card volume until brainstorm wraps. Common
patterns:
- Toggle **on** during `:reveal`: "There are way more cards
  than I expected — let's vote to prioritise."
- Toggle **off** during `:voting`: "This vote isn't going
  anywhere, let's just talk through them." → ephemeral vote
  map is discarded, no `vote_count` materialisation, phase
  auto-advances to `:discuss`.
- Toggle **off** during `:setup`/`:brainstorm`/`:reveal`
  (after being initially on): just flips the flag, next host
  advance from `:reveal` goes straight to `:discuss`.
- Toggle **on** during `:voting`: not possible — you're
  already in voting.

**Why locked at `:discuss`:** toggling on during discuss would
require jumping backward to a phase whose cards-have-been-
discussed-already state is messy. Toggling off during discuss
is a no-op (voting is already done). Either way, no value.

When voting is disabled, the phase machine skips `:voting`
entirely (see §1). Card display in `:discuss` falls back to
column-then-insertion-order rather than vote-count desc.

**When voting is enabled:**

| Property | Value |
|---|---|
| Votes per participant | 3, fixed |
| Multiple votes on same card by same person | Allowed (up to total of 3 spent). One card can take all 3. |
| Vote / unvote during `:voting` | Both allowed, freely. |
| Vote visibility during `:voting` | Vote counts per card are **visible to everyone** (live updating). |
| Vote attribution during `:voting` | Hidden — you see "5 votes" but not who voted. |
| Vote count after `:voting` | Materialised into `retro_cards.vote_count`. Per-user vote map discarded. |
| Per-user vote history after archive | None — no `retro_votes` table. By design. |

**Why 3 votes:** the standard dot-voting allocation. Fewer (1)
forces single-pick and loses nuance for cards that genuinely
need attention but aren't anyone's #1. More (5+) dilutes signal
— with 5 votes per person you're voting for everything, which
means voting for nothing.

**Why vote counts visible live, attribution hidden:** counts
let the room watch themes emerge in real time ("oh, this one's
spiking — interesting"). Hiding who voted what keeps the
psychological safety of "I voted for a critical card without
my manager seeing." The compromise mirrors how political dot-vote
boards work in physical spaces (everyone sees the dots, no one
sees who placed which).

**Why no vote history persisted:** vote tallies are useful for
the discussion that follows; per-user vote attribution is mostly
not (and could create awkward "I see Bob voted for this complaint
about Bob's process" dynamics if exposed). The materialised
`vote_count` column gives you "this card mattered most" forever,
which is the historically-useful signal.

**Server enforcement of the 3-vote cap:** `Chambers.Server`'s
ephemeral vote state is `%{user_id => MapSet.new([card_id, ...])}`
during `:voting`. Casts `{:retro_vote, user_id, card_id}` are
rejected if `MapSet.size(votes[user_id]) >= 3` and `card_id`
isn't already in the set. Client UI greys out unvoted cards once
the user hits 3.

## 6. Action items — _Locked_

**Decision:** Persisted in `retro_action_items`. Created during
`:discuss` (or `:archived` grace window — v2). Optionally tied
to a source card.

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `retro_session_id` | uuid fk | |
| `source_card_id` | uuid fk, nullable | If set, the action item shows under that card in the discuss view. If `nil`, it's a freeform action. |
| `body` | text, 1–280 chars | |
| `assignee_alias` | string, nullable | Free-text alias. Autocomplete in v1 pulls from current chamber Presence. Not enforced to be a real participant — teams sometimes assign to people not in the chamber. |
| `due_date` | date, nullable | Optional. If set, surfaces on the archived session view. |
| `completed` | bool, default false | Toggleable in `:discuss`. Out-of-band completion (after archive) is v2. |
| `created_by_user_id` | uuid fk, nullable | Audit. Not displayed in v1. |
| `inserted_at`, `updated_at` | timestamps | |

**Why both per-card and freeform action items:** during
discussion, an action usually emerges from a specific card
("this complaint → Alex investigates the deploy script") and
benefits from being visually anchored to that card. Other
actions are session-wide ("we should pair more next sprint") and
don't have a single source card. Supporting both via a nullable
FK is one schema field for two patterns.

**Why no separate "owner" / "creator" UI in v1:**
`created_by_user_id` is captured for audit but not displayed.
The `assignee_alias` is what matters for follow-through; surfacing
"created by" too crowds the row without obvious benefit.

**Why per-card display anchored to vote count:** in `:discuss`,
cards sort by `vote_count` desc. Action items render
underneath their `source_card` when set. Freeform actions render
in a separate panel below all cards. This makes "the top-voted
issue's action items" naturally most-prominent.

## 7. Persistence model — _Locked_

**Decision:** 4 new tables + extending `chambers.activity` enum
to include `"retro"`. Vote state stays ephemeral in
`Chambers.Server`. Materialised on phase transition out of
`:voting`.

**Tables:**

```
retro_sessions
  id, chamber_id (fk), title (string, nullable),
  status (enum: setup / brainstorm / reveal / voting / discuss / archived),
  voting_enabled (bool, default false),
  revealed_at (timestamp, nullable), archived_at (timestamp, nullable),
  inserted_at, updated_at

retro_columns
  id, retro_session_id (fk), name (string), position (int),
  inserted_at, updated_at

retro_cards
  id, retro_session_id (fk), retro_column_id (fk),
  body (text), author_user_id (fk, nullable), author_alias (string),
  vote_count (int, default 0),
  inserted_at, updated_at

retro_action_items
  id, retro_session_id (fk), source_card_id (fk, nullable),
  body (text), assignee_alias (string, nullable), due_date (date, nullable),
  completed (bool, default false), created_by_user_id (fk, nullable),
  inserted_at, updated_at
```

**Why session-as-row** (vs. one chamber = one retro): a chamber
hosts many retros over its lifetime — the team holds a retro
each sprint, all in the same chamber URL. Session-as-row keeps
history browsable per chamber.

**Why `vote_count` denormalised on `retro_cards`** rather than a
`retro_votes` table summed at read time: §5's "no per-user vote
history" decision means there's nothing else a votes table would
hold. Materialising the count on the card is the simplest path
that matches the persistence boundary.

**Migration order** (4 migrations, all small):
1. Add `"retro"` to `chambers.activity` enum's allowed values
   (no DB constraint change, just code-side validation).
2. Create `retro_sessions` + `retro_columns`.
3. Create `retro_cards`.
4. Create `retro_action_items`.

Migrations 2–4 are split for cleaner per-table review — they
could be one migration but the team prefers atomic-per-table.

## 8. Server-side state shape — _Locked_

**Decision:** The struct below carries every per-session
ephemeral artefact. Lives inside `Chambers.Server`'s state
alongside the existing music event buffer + `PokerSession`.
`nil` when `chamber.activity != "retro"`. Cleared when activity
flips away from retro.

```elixir
defmodule Mixchamb.Retro.EphemeralState do
  defstruct session_id: nil,        # current RetroSession id (UUID)
            phase: :setup,          # mirror of RetroSession.status, kept here
                                    # for fast access without DB hit per broadcast
            votes: %{},             # %{user_id => MapSet.new([card_id, ...])}
                                    # during :voting only; cleared on phase exit
            discussing_card_id: nil # host can highlight a card during :discuss;
                                    # nil = no current focus
end
```

The struct lives inside `Chambers.Server`'s state alongside the
existing music event buffer + `PokerSession`. Same null/cleared
semantics as poker: §5 of `../BRAINSTORM-v4.md` already requires
music FX bus to unmount under activity flip — retro follows the
same pattern.

**Persistence boundary:** *cards, columns, action items, session
metadata* live in Postgres. *vote map, discussing-card focus*
live in `Chambers.Server` and die with the chamber's
liveness. A chamber that gets unloaded mid-`:voting` loses the
in-flight vote map — when it reloads, vote state restarts at
zero (`vote_count` on cards is still `0` since we haven't
materialised yet). Host can re-enter `:voting` if needed.

PubSub broadcasts on the existing `chamber:<slug>` topic:

| Event | Payload | Trigger |
|---|---|---|
| `{:retro, :session_started, session_id}` | new session id | host clicks "Start retro" on a fresh chamber or after previous archive |
| `{:retro, :title_changed, title}` | new title string | host edits title during `:setup` |
| `{:retro, :column_renamed, column_id, name}` | column id + new name | host renames a column during `:setup` |
| `{:retro, :phase_changed, phase}` | new phase atom | host advances the phase machine |
| `{:retro, :voting_enabled_changed, bool}` | new value | host toggles voting before `:discuss` (see §5) |
| `{:retro, :card_added, card}` | full card map (id, column_id, body, author_alias, author_user_id) | participant adds a card during `:brainstorm` |
| `{:retro, :card_edited, card_id, body}` | id + new body | author edits during `:brainstorm` |
| `{:retro, :card_deleted, card_id}` | id | author deletes during `:brainstorm` |
| `{:retro, :revealed, cards_by_column}` | full cards-keyed-by-column-id map | phase change `:brainstorm` → `:reveal`; payload lets late joiners hydrate instantly |
| `{:retro, :vote_cast, user_id, card_id}` | both ids | participant votes during `:voting` |
| `{:retro, :vote_withdrawn, user_id, card_id}` | both ids | participant unvotes during `:voting` |
| `{:retro, :voting_closed, vote_counts}` | `%{card_id => count}` map | phase change `:voting` → `:discuss`; counts materialised into DB before this fires |
| `{:retro, :discussing, card_id_or_nil}` | card id or nil | host highlights a card during `:discuss` |
| `{:retro, :action_added, action_item}` | full action item map | anyone adds an action item during `:discuss` |
| `{:retro, :action_updated, action_item}` | full action item map | anyone toggles `completed`, edits body/assignee/due_date |
| `{:retro, :archived}` | nothing | host clicks Archive; session frozen |

**Why vote events carry user_id over the wire but UI hides it:**
the server broadcasts user_id for completeness (and for §11's
"vote_cast nudge" to know whose silhouette to flip in the
participants strip). The Vue board strips it before rendering
attribution — counts only. Same pattern as poker's vote events:
the wire carries enough for participant-list UI hints, the
display layer filters.

## 9. Edge cases — _Locked_

| Case | Handling |
|---|---|
| **Late joiner during `:setup`** | They see the empty board + current column names. Can edit alias, can't write cards yet. |
| **Late joiner during `:brainstorm`** | They see column card counts (others') but not contents. Can add their own cards immediately. |
| **Late joiner during `:reveal` / `:voting` / `:discuss`** | They get the full revealed board on mount. In `:voting` they have their full 3 votes regardless of when they arrived. |
| **Late joiner during `:archived`** | Read-only view, same as everyone else. |
| **Leaver mid-`:brainstorm`** | Their cards stay (they own them; deletion is opt-in). When they rejoin they still see them. |
| **Leaver mid-`:voting`** | Their votes stay in the ephemeral map until phase exit. If they rejoin, they can adjust. |
| **Leaver before archive, never returns** | Their cards + votes + action items persist (cards by author_user_id which may now be a stale fk; alias snapshot keeps the display sane). |
| **Host leaves** | The chamber stays running; any co-host the creator promoted (poker's multi-host pattern, see `./planning-poker.md` polish iterations) can drive. With no co-hosts, the phase machine freezes until creator returns. |
| **Switch activity mid-retro (retro → music)** | Ephemeral retro state (vote map, discussing focus) is cleared. **Persisted state (session, columns, cards, actions, voting_enabled flag) stays in DB** — switching back resumes the same session at its persisted phase. This is a meaningful divergence from poker, where activity-switch fully resets. |
| **Host toggles `voting_enabled` off during `:voting`** | Ephemeral vote map is discarded (no materialisation into `vote_count`). Session auto-advances to `:discuss`. Cards display in column-then-insertion order rather than vote-count desc. Broadcast `{:retro, :voting_enabled_changed, false}` + `{:retro, :phase_changed, :discuss}`. |
| **Host toggles `voting_enabled` on during `:reveal`** | Next host advance from `:reveal` goes to `:voting` instead of `:discuss`. Broadcast `{:retro, :voting_enabled_changed, true}`. |
| **Host tries to toggle `voting_enabled` during `:discuss` or `:archived`** | Server rejects with `{:error, :voting_locked}`. Client UI hides the toggle from `:discuss` onward. |
| **Switch activity mid-retro back to retro after going to music** | Resume the session at its persisted phase. Vote map starts empty if phase happened to be `:voting` (lost on switch); host can re-enter voting if needed. |
| **Create a second retro in the same chamber** | Old retro must be `:archived` first. New retro = new `retro_sessions` row with same `chamber_id`. Past retros visible in a history panel (§10). |
| **Vote on a card that gets deleted** | Not possible — cards become read-only at `:reveal`, before voting starts. |
| **Empty session archived** (no cards) | Allowed but pointless. UI nudges "No cards captured — are you sure?" on the archive button. |
| **Card body whitespace-only or > 280 chars** | Server rejects, client shows inline validation. |
| **Same user votes 4 times somehow** | Server rejects 4th vote with `{:error, :vote_limit_reached}`. Client cap is fast-path. |

## 10. Vue component split — _Locked_

**Decision:** Seven-file split under `assets/vue/activities/retro/`.

```
assets/vue/activities/retro/
├── RetroBoard.vue           # top-level mounted when chamber.activity = "retro"
├── RetroSetup.vue           # title + column-name editing (rendered when phase = :setup)
├── RetroColumn.vue          # one column (name + card list + add-card input)
├── RetroCard.vue            # one card (body + author alias + vote count + vote button)
├── RetroVotingPanel.vue     # bottom bar during :voting — "N/3 votes spent" + cards-remaining hint
├── RetroDiscussPanel.vue    # bottom panel during :discuss — sorted card highlight + action item list
└── RetroHostControls.vue    # phase-advance buttons (Start brainstorm / Reveal / Start voting / Start discussion / Archive)
```

The folder convention mirrors `assets/vue/activities/poker/` for
the six-file poker split + `assets/vue/instruments/` for the
seven-file instrument split. When standup / icebreaker /
mini-game land, each gets its own `activities/<name>/` sub-folder.

**Why split vs. one big file:** keeps each region under ~150
lines, testable in isolation via vitest, parallels the
established pattern. RetroCard is rendered in 4 contexts
(brainstorm column, reveal column, voting column, discuss
sorted list) — one component with mode props rather than four
similar components.

**Voting toggle UI:** lives inside `RetroHostControls.vue` (not
`RetroSetup.vue`), since the toggle is reachable from `:setup`
through `:voting` per §5. Renders as a small `[ ] Enable
voting` checkbox/switch next to the phase-advance button.
Hidden from `:discuss` and `:archived`. Non-hosts don't see
the toggle at all.

**Past-retros browsing** lives in `chamber_live.ex`'s presence
aside (a `<details>` disclosure: "Past retros (3)") rather than
inside the Vue board — it's a chamber-level surface, not a
session-level surface, so it doesn't need Vue.

## 11. Polish + nice-to-haves (not blocking v1 ship)

These are sized and considered but explicitly deferred until
after the locked v1 ships. Tracked here so they don't get
re-debated on each pass.

- **Card grouping / merging during `:reveal`.** Drag to cluster,
  vote on the cluster instead of individual cards. EasyRetro
  ships this; high UI complexity. Add when teams ask.
- **"Currently discussing" highlight animation.** During
  `:discuss`, the host's clicked card gets a soft pulse / border
  glow so latecomers' eyes go to the focused card. Polish, not
  blocker.
- **Action item carry-over from previous retro.** "Unfinished
  from last time: 2 items" surfaced at the top of `:setup`.
  Requires loading previous session's actions where `completed
  = false`. Schema already supports it; just a query + UI.
- **Card character counter** in the brainstorm input, 280-char
  cap. Same pattern as twitter compose box.
- **Anonymous mode.** Toggle on `:setup` to suppress author
  attribution on cards. Doesn't remove from DB (audit), just
  hides from UI. Add only if a team asks — see §3 for why
  default is non-anonymous.
- **Preset column templates** (Start/Stop/Continue, Mad/Sad/Glad,
  4Ls) as a dropdown on `:setup` that prefills the four name
  inputs. No schema change needed.
- **Markdown export from `:archived` view.** Same pattern as
  poker's round-history export — clipboard helper that builds
  a markdown snapshot of session title + cards by column +
  action items. ~25 lines.
- **Keyboard shortcuts.** Following poker's pattern:
  - `1`–`4` add card to column N during `:brainstorm`
  - `Enter` submits current card
  - `V` during `:voting` votes the focused/hovered card
  - `R` / `S` for host's "Reveal" / "Start voting" advances
  Worth it but not blocking.

## Ready-to-build checklist

Implementation order I'd recommend, sized in working-day units:

1. ✅ **Migration** — added `"retro"` to `chambers.activity`
   allowed values + created 3 retro tables (sessions+columns,
   cards, action_items) split for atomic-per-table review.
2. ✅ **Retro context + schemas** — `Mixchamb.Retro` module with
   `start_session/2`, `add_card/3`, `update_card/4`,
   `delete_card/3`, `rename_column/3`, `set_voting_enabled/2`,
   `advance_phase/1`, `set_phase/2`, `add_action_item/2`,
   `update_action_item/3`, `materialize_vote_counts/2`. Ecto
   schemas (RetroSession, RetroColumn, RetroCard,
   RetroActionItem) + EphemeralState struct + changesets.
   45 unit tests green.
3. ✅ **`Chambers.Server` integration** — added `retro_state`
   field, 14 new public API functions, 14 cast handlers + the
   set_activity rehydration path, broadcast helper. 14
   integration tests green.
4. ✅ **Create-chamber form** — Retrospective card added to
   landing alongside Music + Poker; activity picker passes
   through unchanged.
5. ✅ **`Chamber.vue` activity-branching** — `<RetroBoard>`
   branch alongside music / poker; new props `retro_session`,
   `retro_tallies`, `retro_my_votes`, `current_user_alias`.
6. ✅ **RetroBoard.vue + 6 sub-components** — 7 files
   (RetroBoard, RetroSetup, RetroColumn, RetroCard,
   RetroVotingPanel, RetroDiscussPanel, RetroHostControls).
   25 vitest tests across 3 suites green.
7. ✅ **Past-retros disclosure in chamber_live.ex presence aside**
   — `<details>` block in `presence_panel_body/1` lists
   archived sessions newest-first. v1 is list-only (title +
   archived date); click-to-view a past retro is a polish
   iteration in §11.
8. ✅ **Smoke test** — 3-browser Playwright at
   `~/danceinthefake/tmp/mixchamb_retro_smoke.mjs`. Walks: setup
   → rename column → brainstorm (verify hidden) → reveal →
   enable voting → voting (verify 3-cap + withdraw toggle) →
   discuss (verify materialisation + sort) → add action item →
   archive (verify past-retros disclosure). **25/25 assertions
   pass, zero page errors.**

Total: **~1 day actual.** (Estimate was ~6 working days; the
fact-finding round on the existing poker pattern compressed
most of the design phase.)

---

## Notes for the implementing pass

- **Card layout on narrow viewports.** 4 columns wide-side-by-side
  works at lg+; below lg, the columns should stack vertically.
  Reetro / EasyRetro both do this. Use Tailwind's `lg:grid-cols-4`
  with `grid-cols-1` default + `gap-4`. Add-card input sticks to
  bottom of each column on lg; on mobile it sticks to the top of
  the column (Twitter-compose pattern) so you don't scroll past
  N cards to add one.
- **Card author display** mirrors poker reveal: `{{ author_alias }}`
  with `<span class="text-muted-foreground">{{ noun_adj_name }}</span>`
  if both present. Same Tailwind classes for consistency.
- **Vote button on cards during `:voting`** is a thumb-up icon
  that flips to a filled state when the user has voted on it
  (`current_user_votes.includes(card.id)`). Tap to vote, tap
  again to unvote. Greyed + disabled if user has spent 3 votes
  and this card isn't already voted.
- **Action items panel** during `:discuss` is a single
  vertical list below the sorted cards. Each item is one row:
  checkbox (completed) + body + assignee chip + due-date chip.
  "+Add action item" sticky bottom button opens an inline
  compose row.
- **Archive button** is destructive-styled (red border, "Are you
  sure?" confirmation) — once archived, no edits.
