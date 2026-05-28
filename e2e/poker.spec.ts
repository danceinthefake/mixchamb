import { test, expect } from "@playwright/test"
import { openRoom } from "./helpers"

// Planning poker: vote in private, host reveals, the verdict reflects
// the spread, then a re-vote returns everyone to voting.
test("poker: vote → reveal → verdict → re-vote", async ({ browser }) => {
  const room = await openRoom(browser, "poker", 3)
  const [p1, p2, p3] = room.pages

  try {
    // Everyone votes (consensus on 5).
    for (const p of [p1, p2, p3]) {
      await p.locator('button:has-text("5")').first().click()
      await p.waitForTimeout(100)
    }

    // Host reveals. After the ~800ms suspense the cards flip + the
    // verdict headline lands.
    await p1.getByRole("button", { name: /^Reveal/ }).click()
    await expect(p1.getByText(/Consensus: 5/)).toBeVisible({ timeout: 5000 })
    // The other players see the same revealed verdict.
    await expect(p2.getByText(/Consensus: 5/)).toBeVisible({ timeout: 5000 })

    // Re-vote clears back to voting (the deck is interactive again).
    await p1.getByRole("button", { name: /Re-vote/i }).click()
    await expect(p1.getByText(/Consensus: 5/)).toHaveCount(0)
    await expect(p1.locator('button:has-text("8")').first()).toBeVisible()

    expect(room.errors, room.errors.join("\n")).toEqual([])
  } finally {
    await room.close()
  }
})
