<script setup lang="ts">
import { Handle, useNode } from '@vue-flow/core'

const node = useNode()

defineProps<{id: string, data: {
  label: string,
}}>()
</script>

<template>
  <div class="resource-node flex flex-col items-center gap-2 px-4 py-6 text-xs box color-yellow font-bold">
    <div class="w-full text-center truncate">{{ data.label }}</div>
  </div>

  <Handle :id="`${id}-source`" type="source" :position="node.node.sourcePosition" />
  <Handle :id="`${id}-target`" type="target" :position="node.node.targetPosition" />
</template>
