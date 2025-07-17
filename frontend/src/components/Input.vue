<template>
  <div class="flex flex-col gap-1">
    <input
      :id="inputId"
      type="text"
      :value="modelValue"
      @input="onInput"
      :placeholder="placeholder"
      class="px-2 py-1 text-xs bg-naturals-N3 text-naturals-N11 rounded border border-naturals-N6 shadow-sm focus:outline-none focus:border-primary-P2 transition"
    />
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'

defineProps<{
  modelValue: string
  label?: string
  placeholder?: string
}>()

// Define emits
const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void
}>()

// Generate a unique ID for input
const inputId = computed(() => `input-${Math.random().toString(36).slice(2, 9)}`)

// Input handler
function onInput(event: Event) {
  const target = event.target as HTMLInputElement
  emit('update:modelValue', target.value)
}
</script>
