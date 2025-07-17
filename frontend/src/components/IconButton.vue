<script setup lang="ts">
defineProps<{
  toggle?: boolean
}>()
</script>

<template>
  <div
    class="button"
    :class="{ toggle }"
    >
    <slot/>
  </div>
</template>

<style scoped>
.button {
  @apply rounded border border-naturals-N12 transition-colors duration-200 p-1 cursor-pointer
}

.button:not(.toggle) {
  @apply hover:bg-naturals-N8
}

.button.toggle {
  @apply bg-naturals-N12 text-naturals-N3 hover:bg-naturals-N14
}
</style>
