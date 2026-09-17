// Column presets — four names each (the column count is fixed in
// v1). Applying one is just four rename events through the
// existing :setup-only pipeline; no schema, no new server path.
export const COLUMN_PRESETS: Record<string, string[]> = {
  "Good / Bad / Start / Thanks": ["Good", "Bad", "Start", "Thanks"],
  "Start / Stop / Continue / Kudos": ["Start", "Stop", "Continue", "Kudos"],
  "Mad / Sad / Glad / Ideas": ["Mad", "Sad", "Glad", "Ideas"],
  "4Ls: Liked / Learned / Lacked / Longed for": ["Liked", "Learned", "Lacked", "Longed for"],
  "Sailboat: Wind / Anchor / Rocks / Island": ["Wind", "Anchor", "Rocks", "Island"],
}
