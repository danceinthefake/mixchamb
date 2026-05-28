import { test, expect } from "@playwright/test"
import { openRoom, bodyText } from "./helpers"

// Music chamber: presence fan-out, the cross-client note broadcast,
// instrument switching, the creator-only chamber-kind ripple, and the
// REC toggle. (Audio playback itself isn't asserted — headless has no
// real AudioContext; the unit/component tests cover the engine.)
test("music: presence, note broadcast, instrument + kind + REC", async ({ browser }) => {
  const room = await openRoom(browser, "music", 3)
  const [p1, p2, p3] = room.pages

  try {
    // 3 people present on every client.
    await expect(p1.getByText(/3 jamming/i)).toBeVisible()
    await expect(p3.getByText(/3 jamming/i)).toBeVisible()

    // u1 (drums) hits a pad → the broadcast path runs cleanly on all
    // three (the remote-play handler fires without error).
    await p1.locator('button[aria-label*="Crash 1"]').first().click()
    await p1.waitForTimeout(300)

    // u2 switches instrument → reflected as the pressed tab.
    await p2.waitForTimeout(1100) // instrument-switch cooldown
    await p2.locator('button[phx-value-to="keyboard"]').click()
    await expect(p2.locator('button[phx-value-to="keyboard"][aria-pressed="true"]')).toBeVisible()

    // u1 (creator) flips the chamber kind → non-creators see the label.
    await p1.locator('button[phx-click="set_kind"][phx-value-kind="anechoic"]').click()
    await expect(p2.getByText(/Anechoic/i).first()).toBeVisible()

    // REC toggle round-trips to every client.
    await p1.getByRole("button", { name: /Start recording/i }).click()
    await expect(p2.getByText(/REC/).first()).toBeVisible()

    expect(room.errors, room.errors.join("\n")).toEqual([])
  } finally {
    await room.close()
  }
})
