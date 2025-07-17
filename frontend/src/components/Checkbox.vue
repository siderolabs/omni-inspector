<template>
  <div class="checkbox-wrapper" :class="{ 'cursor-not-allowed': disabled, 'cursor-pointer': !disabled }"
    @click="(e) => disabled ? e.stopImmediatePropagation() : null">
    <div class="checkbox" :class="{ checked: checked, disabled: disabled }">
      <input type="checkbox" value="" class="sr-only peer" disabled :checked="checked as boolean">
      <div
        class="relative w-9 h-5 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-P3 rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-primary-P3">
      </div>
      <input type="checkbox" hidden :value="checked" />
    </div>
    <span v-if="!!label" class="checkbox-label">{{ label }}</span>
  </div>
</template>

<script setup lang="ts">
type Props = {
  checked?: boolean | number;
  label?: string;
  disabled?: boolean;
};

defineProps<Props>()
</script>

<style scoped>
.checkbox {
  @apply flex items-center justify-center rounded h-full transition-transform;

}
.checkbox-wrapper {
  @apply flex items-center gap-2;
}
.checkbox-label {
  @apply text-xs text-naturals-N13 block select-none truncate flex-1;
}
.checkbox-icon {
  @apply bg-naturals-N3 text-primary-P3 w-2 h-2;
}
</style>
