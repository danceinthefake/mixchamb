import type { Browser, BrowserContext, Page } from "@playwright/test"

// Tap through the "Enter chamber" audio gate if it's showing. Retries
// because in headless the AudioContext sometimes isn't running yet, so
// the gate persists for a beat.
export async function dismissGate(p: Page) {
  for (let i = 0; i < 6; i++) {
    const gate = p.getByRole("button", { name: "Enter chamber" })
    if (!(await gate.isVisible().catch(() => false))) break
    await gate.click({ timeout: 2000 }).catch(() => {})
    await p.waitForTimeout(300)
  }
  await p.waitForTimeout(150)
}

// Create a chamber for `activity` from the landing page; returns its
// URL. The button is a LiveView phx-click — if tapped before the
// socket connects the event is dropped and the page just re-renders
// "/", so retry until the navigation to /chamber/ takes.
export async function createChamber(p: Page, activity: string): Promise<string> {
  await p.goto("/", { waitUntil: "networkidle" })
  const btn = p.locator(`button[phx-value-activity="${activity}"]`)
  await btn.waitFor({ state: "visible" })

  for (let i = 0; i < 3; i++) {
    await btn.click()
    try {
      await p.waitForURL(/\/chamber\//, { timeout: 8000 })
      return p.url()
    } catch {
      await p.waitForTimeout(500)
    }
  }
  throw new Error(`createChamber: never navigated to a ${activity} chamber`)
}

export type Room = {
  ctxs: BrowserContext[]
  pages: Page[]
  url: string
  errors: string[]
  close: () => Promise<void>
}

// Open one chamber with `n` player contexts (pages[0] is the
// creator/host). Everyone joins + clears the gate. Collects page
// errors (minus headless AudioContext noise) for an end-of-test assert.
export async function openRoom(browser: Browser, activity: string, n: number): Promise<Room> {
  const ctxs = await Promise.all(Array.from({ length: n }, () => browser.newContext()))
  const pages = await Promise.all(ctxs.map((c) => c.newPage()))
  const errors: string[] = []
  pages.forEach((p, i) =>
    p.on("pageerror", (e) => {
      if (e.message === "AbortError") return
      errors.push(`[u${i + 1}] ${e.message}`)
    }),
  )

  const url = await createChamber(pages[0], activity)
  for (let i = 1; i < n; i++) await pages[i].goto(url, { waitUntil: "networkidle" })
  await Promise.all(pages.map(dismissGate))
  await pages[0].waitForTimeout(400)

  return {
    ctxs,
    pages,
    url,
    errors,
    close: async () => {
      for (const c of ctxs) await c.close().catch(() => {})
    },
  }
}

export const bodyText = (p: Page) => p.evaluate(() => document.body.innerText)
