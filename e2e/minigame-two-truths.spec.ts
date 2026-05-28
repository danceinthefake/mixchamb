import { test, expect } from "@playwright/test"
import type { Page } from "@playwright/test"
import { openRoom, bodyText } from "./helpers"

async function writeStatements(p: Page, tag: string) {
  const inputs = p.locator('input[placeholder^="Statement"]')
  for (let i = 0; i < 3; i++) await inputs.nth(i).fill(`${tag}-${i}`)
  await p.getByRole("button", { name: "Submit" }).click()
  await p.waitForTimeout(120)
}

// Each non-author taps a statement (the author's buttons are disabled).
async function guessRound(pages: Page[]) {
  for (const p of pages) {
    const first = p.locator("ul button").first()
    if (await first.isEnabled().catch(() => false)) {
      await first.click().catch(() => {})
      await p.waitForTimeout(100)
    }
  }
}

test("two truths: write → guess the lie → reveal → game over", async ({ browser }) => {
  const room = await openRoom(browser, "minigame", 3)
  const all = room.pages
  const [host] = all

  try {
    await host.getByRole("button", { name: "Two Truths" }).click()
    await host.waitForTimeout(400)
    await host.getByRole("button", { name: "Start game" }).click()
    await host.locator('input[placeholder^="Statement"]').first().waitFor({ timeout: 8000 })
    expect((await bodyText(host)).toLowerCase()).toContain("two truths and a lie")

    // Everyone writes their three statements.
    for (let i = 0; i < all.length; i++) await writeStatements(all[i], `u${i}`)
    await host.waitForTimeout(700)

    // Three authors: guessers pick, host advances each reveal.
    for (let round = 0; round < 3; round++) {
      await guessRound(all)
      await host.waitForTimeout(600)
      const next = host.getByRole("button", { name: "Next →" })
      if (await next.isVisible().catch(() => false)) {
        await next.click()
        await host.waitForTimeout(400)
      } else {
        const skip = host.getByRole("button", { name: /Skip the wait/ })
        if (await skip.isVisible().catch(() => false)) {
          await skip.click()
          await host.waitForTimeout(400)
          const n2 = host.getByRole("button", { name: "Next →" })
          if (await n2.isVisible().catch(() => false)) {
            await n2.click()
            await host.waitForTimeout(400)
          }
        }
      }
    }

    await expect(host.getByText(/final scores/i)).toBeVisible({ timeout: 8000 })
    await host.getByRole("button", { name: "Play again" }).click()
    await expect(host.getByText("Choose a game")).toBeVisible()

    expect(room.errors, room.errors.join("\n")).toEqual([])
  } finally {
    await room.close()
  }
})
