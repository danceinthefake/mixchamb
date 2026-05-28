import { test, expect } from "@playwright/test"
import type { Page } from "@playwright/test"
import { openRoom, bodyText } from "./helpers"

// Submit the current step: a text phrase, or a drawing (mouse-drag on
// the input canvas — the last canvas; an earlier one may be the
// read-only prompt drawing).
async function submitStep(p: Page, tag: string) {
  const phrase = p.locator(
    'input[placeholder="Your phrase…"], input[placeholder="Describe the drawing…"]',
  )
  if (
    await phrase
      .first()
      .isVisible()
      .catch(() => false)
  ) {
    await phrase.first().fill(tag)
  } else {
    const c = p.locator("canvas").last()
    const box = (await c.boundingBox())!
    const y = box.y + box.height / 2
    await p.mouse.move(box.x + box.width * 0.25, y)
    await p.mouse.down()
    for (let i = 1; i <= 6; i++)
      await p.mouse.move(box.x + box.width * (0.25 + 0.08 * i), y + Math.sin(i) * 20)
    await p.mouse.up()
  }
  await p.getByRole("button", { name: "Submit" }).click()
  await p.waitForTimeout(150)
}

test("gartic phone: write→draw→describe chain → album → game over", async ({ browser }) => {
  const room = await openRoom(browser, "minigame", 3)
  const all = room.pages
  const [host] = all

  try {
    await host.getByRole("button", { name: "Gartic Phone" }).click()
    await host.waitForTimeout(400)
    await host.getByRole("button", { name: "Start game" }).click()
    await host.waitForTimeout(700)
    expect((await bodyText(host)).toLowerCase()).toContain("step 1 / 3")

    // 3 steps (n=3): everyone submits each.
    for (let step = 0; step < 3; step++) {
      for (const p of all) await submitStep(p, `m-${step}`)
      await host.waitForTimeout(700)
    }

    // Chain complete → album.
    await expect(host.getByText(/album/i).first()).toBeVisible({ timeout: 8000 })

    // Host flips the album through to the end.
    for (let i = 0; i < 14; i++) {
      const next = host.getByRole("button", { name: "Next →" })
      if (!(await next.isVisible().catch(() => false))) break
      await next.click()
      await host.waitForTimeout(250)
    }
    await expect(host.getByText(/all the books/i)).toBeVisible()

    // Play again → lobby.
    await host.getByRole("button", { name: "Play again" }).click()
    await expect(host.getByText("Choose a game")).toBeVisible()

    expect(room.errors, room.errors.join("\n")).toEqual([])
  } finally {
    await room.close()
  }
})
