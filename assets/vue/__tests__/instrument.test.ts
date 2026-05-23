import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { defineComponent, h, ref, type Ref } from "vue"
import { mount, enableAutoUnmount } from "@vue/test-utils"
import { useInstrumentFlash, useInstrumentKeyboard, type RemoteHit } from "../lib/instrument"

enableAutoUnmount(afterEach)

// Test composables by mounting a tiny ad-hoc component that just
// invokes them and exposes the returned bits.
function makeFlashHost(remoteHit: Ref<RemoteHit>) {
  return defineComponent({
    setup() {
      const flash = useInstrumentFlash<string>({
        remoteHit,
        instrument: "drums",
      })
      return { ...flash }
    },
    render: () => h("div"),
  })
}

describe("useInstrumentFlash", () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it("flash() sets local + clears after the duration", async () => {
    const remoteHit = ref<RemoteHit>(null)
    const wrapper = mount(makeFlashHost(remoteHit))
    const vm = wrapper.vm as unknown as {
      local: string | null
      remote: string | null
      flash: (k: string) => void
    }

    vm.flash("kick" as never)
    expect(vm.local).toBe("kick")

    // Tight flash is ~120 ms; advance well past.
    vi.advanceTimersByTime(500)
    expect(vm.local).toBeNull()
  })

  it("remoteHit prop triggers a remote flash on the matching instrument", async () => {
    const remoteHit = ref<RemoteHit>(null)
    const wrapper = mount(makeFlashHost(remoteHit))
    const vm = wrapper.vm as unknown as {
      local: string | null
      remote: string | null
      flash: (k: string) => void
    }

    remoteHit.value = { instrument: "drums", note: "snare", t: 1 }
    await wrapper.vm.$nextTick()
    expect(vm.remote).toBe("snare")
  })

  it("ignores remote hits from a different instrument", async () => {
    const remoteHit = ref<RemoteHit>(null)
    const wrapper = mount(makeFlashHost(remoteHit))
    const vm = wrapper.vm as unknown as {
      local: string | null
      remote: string | null
      flash: (k: string) => void
    }

    remoteHit.value = { instrument: "keyboard", note: "C4", t: 1 }
    await wrapper.vm.$nextTick()
    expect(vm.remote).toBeNull()
  })

  it("extractRemote can filter or remap incoming hits", async () => {
    const remoteHit = ref<RemoteHit>(null)
    const host = defineComponent({
      setup() {
        const flash = useInstrumentFlash<string, string>({
          remoteHit,
          instrument: "drums",
          extractRemote: (h) => (h.note === "kick" ? "kick" : null),
        })
        return { ...flash }
      },
      render: () => h("div"),
    })
    const wrapper = mount(host)
    const vm = wrapper.vm as unknown as {
      local: string | null
      remote: string | null
      flash: (k: string) => void
    }

    remoteHit.value = { instrument: "drums", note: "ride", t: 1 }
    await wrapper.vm.$nextTick()
    expect(vm.remote).toBeNull()

    remoteHit.value = { instrument: "drums", note: "kick", t: 2 }
    await wrapper.vm.$nextTick()
    expect(vm.remote).toBe("kick")
  })
})

describe("useInstrumentKeyboard", () => {
  it("triggers onDown when a tracked key is pressed", async () => {
    const onDown = vi.fn()
    const host = defineComponent({
      setup() {
        useInstrumentKeyboard({
          findByKey: (k) => (k === "a" ? "kick" : undefined),
          onDown,
        })
      },
      render: () => h("div"),
    })

    mount(host, { attachTo: document.body })
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "a" }))
    await new Promise((r) => setTimeout(r, 0))
    expect(onDown).toHaveBeenCalledWith("kick")
  })

  it("ignores untracked keys", async () => {
    const onDown = vi.fn()
    const host = defineComponent({
      setup() {
        useInstrumentKeyboard({
          findByKey: () => undefined,
          onDown,
        })
      },
      render: () => h("div"),
    })

    mount(host, { attachTo: document.body })
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "q" }))
    await new Promise((r) => setTimeout(r, 0))
    expect(onDown).not.toHaveBeenCalled()
  })

  it("skips when typing in a form input", async () => {
    const onDown = vi.fn()
    const host = defineComponent({
      setup() {
        useInstrumentKeyboard({
          findByKey: (k) => (k === "a" ? "kick" : undefined),
          onDown,
        })
      },
      render: () => h("div"),
    })

    mount(host, { attachTo: document.body })

    const input = document.createElement("input")
    document.body.appendChild(input)
    const evt = new KeyboardEvent("keydown", { key: "a" })
    Object.defineProperty(evt, "target", { value: input })
    window.dispatchEvent(evt)

    await new Promise((r) => setTimeout(r, 0))
    expect(onDown).not.toHaveBeenCalled()
  })

  it("ignores auto-repeat events", async () => {
    const onDown = vi.fn()
    const host = defineComponent({
      setup() {
        useInstrumentKeyboard({
          findByKey: (k) => (k === "a" ? "kick" : undefined),
          onDown,
        })
      },
      render: () => h("div"),
    })

    mount(host, { attachTo: document.body })
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "a", repeat: true }))
    await new Promise((r) => setTimeout(r, 0))
    expect(onDown).not.toHaveBeenCalled()
  })

  it("calls onUp on keyup when provided", async () => {
    const onDown = vi.fn()
    const onUp = vi.fn()
    const host = defineComponent({
      setup() {
        useInstrumentKeyboard({
          findByKey: (k) => (k === "a" ? "kick" : undefined),
          onDown,
          onUp,
        })
      },
      render: () => h("div"),
    })

    mount(host, { attachTo: document.body })
    window.dispatchEvent(new KeyboardEvent("keyup", { key: "a" }))
    await new Promise((r) => setTimeout(r, 0))
    expect(onUp).toHaveBeenCalledWith("kick")
  })
})
