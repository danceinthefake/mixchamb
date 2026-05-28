import { test, expect } from "@playwright/test"
import { openRoom } from "./helpers"

// When the host switches the chamber's activity, the board swaps under
// everyone — a flash explains why, on every connected client.
test("activity switch flashes the whole room", async ({ browser }) => {
  const room = await openRoom(browser, "music", 2)
  const [host, guest] = room.pages

  try {
    await host.locator('button[phx-value-activity="minigame"]').click()

    await expect(host.getByText(/Host switched the chamber to Mini-game/i)).toBeVisible()
    await expect(guest.getByText(/Host switched the chamber to Mini-game/i)).toBeVisible()
    // And the board actually swapped to the mini-game lobby.
    await expect(host.getByText("Choose a game")).toBeVisible()

    expect(room.errors, room.errors.join("\n")).toEqual([])
  } finally {
    await room.close()
  }
})
