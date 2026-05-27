<script setup lang="ts">
// The one genuinely new primitive (features/mini-game.md §3): a live
// shared canvas where only the current drawer emits strokes and the
// server relays them to everyone else, with a buffered snapshot for
// late joiners.
//
// Coordinates are normalized to 0..1 of the canvas box (never pixels)
// so every client renders at its own size and the canvas stays
// responsive — line widths are fractions of the canvas width too.
// The drawer's pointer input is batched (~50ms) rather than one event
// per move, mirroring how the music activity rate-limits notes.
//
// Render strategy: one <canvas>, a requestAnimationFrame loop that
// redraws when `dirty`, repainting the full stroke list only on
// change/resize. The white "paper" background is theme-independent so
// the eraser (= draw in the background colour) works in light + dark.

import { onMounted, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import { isTypingInForm } from "../../../lib/utils"
import type { Stroke } from "../MiniGameBoard.vue"

const props = defineProps<{
  strokes: Stroke[] // late-joiner snapshot (authoritative completed strokes)
  isDrawer: boolean
  frozen: boolean // :turn_reveal — canvas locked
  turnToken: number
  current_user_id: string
  // Local mode (Gartic Phone): draw on a private surface — no live
  // relay over PubSub; the parent grabs the strokes on submit via the
  // exposed getStrokes(). Default false = Pictionary's shared canvas.
  local?: boolean
}>()

const live = useLiveVue()

const PAPER = "#ffffff"
const PALETTE = [
  "#1a1a1a",
  "#e23b3b",
  "#f08c2e",
  "#f4c430",
  "#3aa655",
  "#2e7dd1",
  "#7b4fc4",
  "#d94f9e",
]
// Brush sizes + eraser, as fractions of canvas width (scale-stable).
const SIZES = [0.006, 0.013, 0.026]
const ERASER_WIDTH = 0.06

const wrapper = ref<HTMLDivElement | null>(null)
const canvas = ref<HTMLCanvasElement | null>(null)
let ctx: CanvasRenderingContext2D | null = null

// Tool state (drawer only).
const color = ref(PALETTE[0])
const sizeIdx = ref(1)
const erasing = ref(false)

// Rendered model. `completed` is the authoritative stroke list;
// `inProgress` holds remote strokes being assembled from live batches,
// keyed by seq.
let completed: Stroke[] = []
const inProgress = new Map<number, Stroke>()
let dirty = true
let raf = 0

// --- Drawer's in-flight stroke ---
let drawing = false
let curSeq = 0
let curStroke: Stroke | null = null
let sentUpTo = 0 // index of points already flushed
let lastFlush = 0
let seqCounter = 0

function activeWidth(): number {
  return erasing.value ? ERASER_WIDTH : SIZES[sizeIdx.value]
}
function activeColor(): string {
  return erasing.value ? PAPER : color.value
}

// Re-seed from the server snapshot at the start of each turn (and on
// first mount). During a turn the snapshot is stale — live relay
// drives — so we only re-init on turn change, never clobbering live
// strokes with an empty mid-turn snapshot.
watch(
  () => props.turnToken,
  () => {
    completed = (props.strokes ?? []).map(cloneStroke)
    inProgress.clear()
    dirty = true
  },
  { immediate: true },
)

function cloneStroke(s: Stroke): Stroke {
  return {
    points: s.points.map((p) => [p[0], p[1]] as [number, number]),
    color: s.color,
    width: s.width,
  }
}

// Expose the current strokes so a local-mode parent (Gartic) can grab
// them on submit.
defineExpose({ getStrokes: () => completed.map(cloneStroke) })

// --- Live relay from the server (other clients' strokes). The drawer
// skips its own echo — it already rendered locally. Skipped entirely
// in local mode (private surface, no relay). ---
live.handleEvent("minigame_relay", ({ kind, payload }: { kind: string; payload: any }) => {
  if (props.local || payload?.from === props.current_user_id) return

  switch (kind) {
    case "stroke": {
      const seq = payload.seq as number
      let s = inProgress.get(seq)
      if (!s) {
        s = { points: [], color: payload.color, width: payload.width }
        inProgress.set(seq, s)
      }
      for (const p of payload.points ?? []) s.points.push([p[0], p[1]])
      break
    }
    case "stroke_end": {
      const seq = payload.seq as number
      inProgress.delete(seq)
      // Authoritative full stroke heals any dropped batches.
      completed.push({
        points: (payload.points ?? []).map((p: number[]) => [p[0], p[1]]),
        color: payload.color,
        width: payload.width,
      })
      break
    }
    case "undo":
      completed.pop()
      break
    case "clear":
      completed = []
      inProgress.clear()
      break
  }
  dirty = true
})

// --- Rendering ---
function resize() {
  const el = canvas.value
  const box = wrapper.value
  if (!el || !box) return
  const dpr = window.devicePixelRatio || 1
  const w = box.clientWidth
  const h = Math.round(w * 0.6) // 5:3 paper
  el.style.height = h + "px"
  el.width = Math.round(w * dpr)
  el.height = Math.round(h * dpr)
  ctx = el.getContext("2d")
  dirty = true
}

function drawStroke(s: Stroke, W: number, H: number) {
  if (!ctx || s.points.length === 0) return
  ctx.strokeStyle = s.color
  ctx.fillStyle = s.color
  ctx.lineWidth = Math.max(1, s.width * W)
  ctx.lineJoin = "round"
  ctx.lineCap = "round"

  if (s.points.length === 1) {
    const [x, y] = s.points[0]
    ctx.beginPath()
    ctx.arc(x * W, y * H, ctx.lineWidth / 2, 0, Math.PI * 2)
    ctx.fill()
    return
  }
  ctx.beginPath()
  ctx.moveTo(s.points[0][0] * W, s.points[0][1] * H)
  for (let i = 1; i < s.points.length; i++) ctx.lineTo(s.points[i][0] * W, s.points[i][1] * H)
  ctx.stroke()
}

function render() {
  if (dirty && ctx && canvas.value) {
    const W = canvas.value.width
    const H = canvas.value.height
    ctx.fillStyle = PAPER
    ctx.fillRect(0, 0, W, H)
    for (const s of completed) drawStroke(s, W, H)
    for (const s of inProgress.values()) drawStroke(s, W, H)
    if (drawing && curStroke) drawStroke(curStroke, W, H)
    dirty = false
  }
  raf = requestAnimationFrame(render)
}

// --- Drawer pointer handling ---
function pointFromEvent(e: PointerEvent): [number, number] {
  const rect = canvas.value!.getBoundingClientRect()
  const x = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width))
  const y = Math.min(1, Math.max(0, (e.clientY - rect.top) / rect.height))
  return [x, y]
}

function onPointerDown(e: PointerEvent) {
  if (!props.isDrawer || props.frozen) return
  e.preventDefault()
  // Capture so a drag that leaves the canvas still tracks. Guarded —
  // some pointers (synthetic, already-released) reject capture, and a
  // throw here would abort the stroke.
  try {
    canvas.value!.setPointerCapture(e.pointerId)
  } catch {
    /* capture optional */
  }
  drawing = true
  curSeq = ++seqCounter
  curStroke = {
    seq: curSeq,
    points: [pointFromEvent(e)],
    color: activeColor(),
    width: activeWidth(),
  }
  sentUpTo = 0
  lastFlush = performance.now()
  dirty = true
}

function onPointerMove(e: PointerEvent) {
  if (!drawing || !curStroke) return
  curStroke.points.push(pointFromEvent(e))
  dirty = true
  const now = performance.now()
  if (now - lastFlush >= 50) flushBatch()
}

function flushBatch() {
  if (props.local || !curStroke) return
  const fresh = curStroke.points.slice(sentUpTo)
  if (fresh.length === 0) return
  live.pushEvent("minigame_stroke", {
    seq: curSeq,
    points: fresh,
    color: curStroke.color,
    width: curStroke.width,
  })
  sentUpTo = curStroke.points.length
  lastFlush = performance.now()
}

function onPointerUp() {
  if (!drawing || !curStroke) return
  drawing = false
  flushBatch()
  // Authoritative full stroke for the snapshot buffer + self-heal.
  // Local mode keeps the stroke private (no relay) — submitted later.
  if (!props.local) {
    live.pushEvent("minigame_stroke_end", {
      seq: curSeq,
      points: curStroke.points,
      color: curStroke.color,
      width: curStroke.width,
    })
  }
  completed.push({ points: curStroke.points, color: curStroke.color, width: curStroke.width })
  curStroke = null
  dirty = true
}

function undo() {
  if (!props.isDrawer) return
  completed.pop()
  dirty = true
  if (!props.local) live.pushEvent("minigame_undo", {})
}
function clearCanvas() {
  if (!props.isDrawer) return
  completed = []
  inProgress.clear()
  dirty = true
  if (!props.local) live.pushEvent("minigame_clear", {})
}

// Drawer keyboard shortcuts: 1-8 pick a colour, [ / ] shrink/grow the
// brush, E toggle eraser, Z undo. Ignored when typing in a field or
// when this client isn't the active drawer.
function onKeydown(e: KeyboardEvent) {
  if (!props.isDrawer || props.frozen || isTypingInForm(e)) return
  const k = e.key
  if (k >= "1" && k <= "8" && Number(k) <= PALETTE.length) {
    color.value = PALETTE[Number(k) - 1]
    erasing.value = false
  } else if (k === "[") {
    sizeIdx.value = Math.max(0, sizeIdx.value - 1)
    erasing.value = false
  } else if (k === "]") {
    sizeIdx.value = Math.min(SIZES.length - 1, sizeIdx.value + 1)
    erasing.value = false
  } else if (k === "e" || k === "E") {
    erasing.value = !erasing.value
  } else if (k === "z" || k === "Z") {
    undo()
  } else {
    return
  }
  e.preventDefault()
}

let ro: ResizeObserver | undefined
let keyAbort: AbortController | undefined
onMounted(() => {
  resize()
  ro = new ResizeObserver(resize)
  if (wrapper.value) ro.observe(wrapper.value)
  raf = requestAnimationFrame(render)
  keyAbort = new AbortController()
  window.addEventListener("keydown", onKeydown, { signal: keyAbort.signal })
})
onUnmounted(() => {
  cancelAnimationFrame(raf)
  ro?.disconnect()
  keyAbort?.abort()
})
</script>

<template>
  <div class="space-y-2">
    <div ref="wrapper" class="rounded-xl border overflow-hidden bg-white shadow-sm">
      <canvas
        ref="canvas"
        class="block w-full touch-none select-none"
        :class="isDrawer && !frozen ? 'cursor-crosshair' : 'cursor-default'"
        @pointerdown="onPointerDown"
        @pointermove="onPointerMove"
        @pointerup="onPointerUp"
        @pointercancel="onPointerUp"
      ></canvas>
    </div>

    <!-- Drawer tools -->
    <div v-if="isDrawer && !frozen" class="flex items-center gap-3 flex-wrap">
      <div class="flex items-center gap-1">
        <button
          v-for="c in PALETTE"
          :key="c"
          type="button"
          @click="((color = c), (erasing = false))"
          :aria-label="`Colour ${c}`"
          class="size-6 rounded-full border-2 transition-transform hover:scale-110 cursor-pointer"
          :style="{ backgroundColor: c }"
          :class="!erasing && color === c ? 'border-foreground' : 'border-transparent'"
        ></button>
      </div>

      <div class="flex items-center gap-1">
        <button
          v-for="(s, i) in SIZES"
          :key="i"
          type="button"
          @click="((sizeIdx = i), (erasing = false))"
          :aria-label="`Brush size ${i + 1}`"
          class="size-7 rounded-md border flex items-center justify-center cursor-pointer hover:bg-accent transition-colors"
          :class="
            !erasing && sizeIdx === i
              ? 'border-accent-minigame bg-accent-minigame/10'
              : 'border-border'
          "
        >
          <span
            class="rounded-full bg-foreground"
            :style="{ width: (i + 1) * 3 + 'px', height: (i + 1) * 3 + 'px' }"
          ></span>
        </button>
      </div>

      <button
        type="button"
        @click="erasing = !erasing"
        title="Eraser (E)"
        class="px-2 py-1 text-xs rounded-md border cursor-pointer hover:bg-accent transition-colors"
        :class="erasing ? 'border-accent-minigame bg-accent-minigame/10' : 'border-border'"
      >
        Eraser
      </button>

      <div class="ml-auto flex items-center gap-1">
        <button
          type="button"
          @click="undo"
          title="Undo last stroke (Z)"
          class="px-2 py-1 text-xs rounded-md border border-border hover:bg-accent cursor-pointer transition-colors"
        >
          Undo
        </button>
        <button
          type="button"
          @click="clearCanvas"
          class="px-2 py-1 text-xs rounded-md border border-border hover:bg-accent cursor-pointer transition-colors"
        >
          Clear
        </button>
      </div>
    </div>

    <!-- Inline shortcut hint (keys are shown inline, never in a
         separate cheatsheet). Hidden on touch where there's no
         keyboard. -->
    <p
      v-if="isDrawer && !frozen"
      class="hidden sm:block text-[10px] text-muted-foreground font-mono"
    >
      1–8 colour · [ ] size · E eraser · Z undo
    </p>
  </div>
</template>
