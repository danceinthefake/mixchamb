import { test, expect } from "@playwright/test"
import type { Page } from "@playwright/test"
import { openRoom } from "./helpers"

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
    // Host starts the session (null → :setup).
    await host.getByRole("button", { name: /Start retro/i }).click()
    await expect(guest.getByText(/host is setting up/i)).toBeVisible()

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

    // Reveal → (voting is off by default) → discuss → archive, then
    // the team page lists it.
    await advance(host)
    host.once("dialog", (d) => d.accept())
    await host.getByRole("button", { name: /Archive retro/ }).click()
    await expect(host.getByText(/Retro archived/i)).toBeVisible({ timeout: 8000 })
    await host.goto(`/t/${team.replace(" ", "-")}`)
    await expect(host.locator("#team-retros a")).toHaveCount(1)

    expect(room.errors, room.errors.join("\n")).toEqual([])
  } finally {
    await room.close()
  }
})
