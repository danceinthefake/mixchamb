import { test, expect } from "@playwright/test"
import type { Page } from "@playwright/test"
import { openRoom, dismissGate } from "./helpers"

// Advance the retro phase machine one step (the button label changes
// per phase: Start brainstorm → Reveal cards → Start discussion…).
async function advance(p: Page) {
  const btn = p.getByRole("button", {
    name: /Start brainstorm|Reveal cards|Start voting|Start discussion|Archive/,
  })
  await btn.first().click()
  await p.waitForTimeout(400)
}

// Retrospective: host starts a session, the room brainstorms, the host
// reveals, and a card written in private becomes visible to everyone.
test("retro: start → brainstorm → reveal a card to the room", async ({ browser }) => {
  const room = await openRoom(browser, "retro", 2)
  const [host, guest] = room.pages

  try {
    // Host starts the session (null → :setup). Retry the click: a
    // phx-click landing before the socket is up is dropped silently.
    await expect(async () => {
      await host.getByRole("button", { name: /Start retro/i }).click({ timeout: 2000 })
      await expect(guest.getByText(/host is setting up/i)).toBeVisible({ timeout: 3000 })
    }).toPass({ timeout: 15_000 })

    // Tag a team on setup; the slug hint updates from the broadcast.
    const team = `e2e ${Date.now()}`
    await host.locator("#retro-team").fill(team)
    await host.locator("#retro-team").press("Enter")
    await expect(host.getByText(`/t/${team.replace(" ", "-")}`)).toBeVisible({ timeout: 8000 })

    // Setup → brainstorm.
    await advance(host)

    // Host writes a card into the first column.
    const col = host
      .locator("section")
      .filter({ has: host.locator("h2") })
      .first()
    await col.locator("textarea").first().fill("Slow CI is painful")
    await col.locator('button[type="submit"]').first().click()
    await host.waitForTimeout(300)

    // Brainstorm → reveal. The card is now visible to the other person.
    await advance(host)
    await expect(guest.getByText("Slow CI is painful")).toBeVisible({ timeout: 8000 })

    // Reveal → (voting is off by default) → discuss. Leave an open
    // action item, then archive.
    await advance(host)
    await host.getByPlaceholder("Add an action item…").fill("Fix the flaky CI job")
    await host.getByRole("button", { name: "Add action" }).click()
    await expect(host.getByText("Fix the flaky CI job")).toBeVisible()

    // Retro → poker handoff: the open item becomes the poker story
    // for the whole room; then the host flips back to finish the retro.
    host.once("dialog", (d) => d.accept())
    await host.locator("#retro-estimate-in-poker").click()
    await expect(guest.getByText(/Host switched the chamber to Poker/i)).toBeVisible()
    await expect(guest.getByText("Fix the flaky CI job")).toBeVisible({ timeout: 8000 })
    await host.locator('button[phx-value-activity="retro"]').click()
    await expect(host.getByRole("button", { name: /Archive retro/ })).toBeVisible({
      timeout: 8000,
    })

    host.once("dialog", (d) => d.accept())
    await host.getByRole("button", { name: /Archive retro/ }).click()
    await expect(host.getByText(/Retro archived/i)).toBeVisible({ timeout: 8000 })

    // The team page lists the retro and the open item.
    const slug = team.replace(" ", "-")
    await host.goto(`/t/${slug}`)
    await expect(host.locator("#team-retros a")).toHaveCount(1)
    await expect(host.locator("#team-open-actions")).toContainText("Fix the flaky CI job")
    await expect(host.locator("#team-summary")).toContainText("Retros")

    // The visit is remembered: the landing page offers the team back.
    await host.goto("/", { waitUntil: "networkidle" })
    await expect(host.locator("#your-teams a", { hasText: team })).toBeVisible()

    // Next retro in the same chamber inherits the team and offers
    // the open item for carry-over on :setup.
    await host.goto(room.url, { waitUntil: "networkidle" })
    await dismissGate(host)
    await host.getByRole("button", { name: /Start new retro/i }).click()
    await expect(host.locator("#retro-team")).toHaveValue(team, { timeout: 8000 })
    await expect(host.locator("#retro-carry-over")).toContainText("Fix the flaky CI job")
    await host.getByRole("button", { name: "Carry over" }).click()
    await expect(host.locator("#retro-carry-over")).toHaveCount(0, { timeout: 8000 })

    expect(room.errors, room.errors.join("\n")).toEqual([])
  } finally {
    await room.close()
  }
})
