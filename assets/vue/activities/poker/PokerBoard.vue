<script setup lang="ts">
// Top-level Vue island for a planning-poker chamber, mounted by
// Chamber.vue when `chamber.activity === "poker"`. Step-4 stub —
// real story header / card deck / participants / reveal / host
// controls land in step 5 (see features/planning-poker.md).

defineProps<{
  chamber_slug: string
  chamber_title?: string | null
}>()
</script>

<template>
  <div class="rounded-2xl border bg-card/60 backdrop-blur-sm p-8 text-center space-y-3">
    <h2 class="text-xl font-bold tracking-tight font-display">Planning poker</h2>
    <p class="text-sm text-muted-foreground">
      The board lands next. For now you can share this chamber's link and the
      team will land here when poker is live.
    </p>
  </div>
</template>
