import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

// Utility used by shadcn-vue components to merge Tailwind classes
// while resolving conflicts (e.g., a later px-4 wins over an earlier px-2).
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

// True when the keyboard event originated from a form control or a
// contenteditable element — i.e. the user is typing into the alias
// box / a chamber title input, not jamming. Every pad's window-level
// keydown handler checks this first so QWERTY keys don't double as
// note triggers while typing.
export function isTypingInForm(event: KeyboardEvent): boolean {
  const target = event.target as HTMLElement | null
  if (!target) return false
  const tag = target.tagName
  if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return true
  return target.isContentEditable === true
}
