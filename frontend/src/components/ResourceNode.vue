<script setup lang="ts">
import { Handle, useNode } from '@vue-flow/core'
defineProps<{id: string, data: {
  label: string,
  labels: string[],
  fields: string[],
}}>()

const node = useNode()
</script>

<template>
  <div class="resource-node rounded flex flex-col items-center gap-2 p-2 text-xs box color-light6">
    <div class="w-full text-center truncate">{{ data.label }}</div>
    <div class="box rounded color-green p-1 w-full" v-if="data.labels?.length">
      <div v-for="label in data.labels" :key="label">{{ label }}</div>
    </div>
    <div class="box rounded color-light2 p-1 w-full" v-if="data.fields?.length">
      <div v-for="field in data.fields" :key="field">{{ field }}</div>
    </div>
  </div>

  <Handle :id="`${id}-source`" type="source" :position="node.node.sourcePosition" />
  <Handle :id="`${id}-target`" type="target" :position="node.node.targetPosition" />
</template>

<style>
.resource-node .vue-flow__handle {
  border: none;
  height: unset;
  width: unset;
  background: transparent;
  font-size: 12px;
}
</style>
