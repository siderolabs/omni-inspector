<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, Ref, ref, watch } from 'vue'
import type { Node, Edge } from '@vue-flow/core'
import { VueFlow, useVueFlow, MarkerType } from '@vue-flow/core'
import { Background } from '@vue-flow/background'
import { useLayout } from '../layout'
import { DependencyGraphRequest, DependencyGraphResponseNodeType, ResourceService } from '../api/resources/resources.pb'
import ResourceNode from '../components/ResourceNode.vue'
import ControllerNode from '../components/ControllerNode.vue'
import { ArrowDownIcon, ArrowRightIcon, TagIcon } from '@heroicons/vue/24/outline'
import IconButton from '../components/IconButton.vue'
import TextInput from '../components/Input.vue'
import fuzzysearch from 'fuzzysearch-ts'
import Checkbox from '../components/Checkbox.vue'
import { RequestOptions } from '@/api/fetch.pb'
import { TabsContent, TabsIndicator, TabsList, TabsRoot, TabsTrigger } from 'reka-ui'

const addMetadata = (req: RequestInit, headers: Record<string, string>) => {
  if (!req.headers) {
    req.headers = new Headers()
  }

  const h = req.headers as Headers

  for (const id in headers) {
    h.append(`Grpc-Metadata-${id}`, headers[id].toString())
  }
}

const withRuntime = (runtime: string) => {
  return (req: RequestOptions) => {
    addMetadata(req, { runtime: runtime })
  }
}

enum EdgeType {
  OutputExclusive = 0,
  OutputShared,
	InputStrong,
	InputWeak,
	InputDestroyReady,
	InputQPrimary,
	InputQMapped,
	InputQMappedDestroyReady,
}

const { layout } = useLayout()

const nodes = ref<Node[]>([]);
const edges = ref<Edge[]>([]);
const controllers = ref<string[]>([])
const resources = ref<string[]>([])

const sidebarWidth: Ref<number | undefined> = ref() // default width in px
const minWidth = 160
const maxWidth = 480
const showEdgeLabels = ref(localStorage.getItem("edge_labels") === "true")

let isResizing = false

const startResize = () => {
  isResizing = true
  document.addEventListener('mousemove', resize)
  document.addEventListener('mouseup', stopResize)
}

const resize = (e: MouseEvent) => {
  if (!isResizing) return
  const newWidth = e.clientX
  sidebarWidth.value = Math.min(Math.max(newWidth, minWidth), maxWidth)
}

const stopResize = () => {
  isResizing = false
  document.removeEventListener('mousemove', resize)
  document.removeEventListener('mouseup', stopResize)
}

onBeforeUnmount(() => {
  document.removeEventListener('mousemove', resize)
  document.removeEventListener('mouseup', stopResize)
})

onMounted(async () => {
  isLoading.value = true
  try {
    const resp = await ResourceService.Controllers({})

    controllers.value = resp.controllers ?? [];

    const defs = await ResourceService.List({
      namespace: "meta",
      type: "ResourceDefinitions.meta.cosi.dev",
    }, withRuntime("Omni"))

    resources.value = defs.items?.map(item => JSON.parse(item).spec.type as string) ?? []
  } finally {
    isLoading.value = false
  }
})

const shownControllers = ref<Record<string, boolean>>({})
const shownResources = ref<Record<string, boolean>>({})
const isLoading = ref(false)

const labels:Record<EdgeType, string> = {
  [EdgeType.OutputExclusive]: "EXCLUSIVE",
  [EdgeType.OutputShared]: "SHARED",
  [EdgeType.InputDestroyReady]: "DESTROY_READY",
  [EdgeType.InputQMappedDestroyReady]: "DESTROY_READY",
  [EdgeType.InputQMapped]: "SECONDARY",
  [EdgeType.InputWeak]: "SECONDARY",
  [EdgeType.InputQPrimary]: "PRIMARY",
  [EdgeType.InputStrong]: "STRONG"
}

watch([shownControllers.value, shownResources.value], async () => {
  const controllers = Object.keys(shownControllers.value).sort()
  const resources = Object.keys(shownResources.value).sort()

  nodes.value = []
  edges.value = []

  if (controllers.length === 0 && resources.length === 0) {
    return
  }

  isLoading.value = true

  const req: DependencyGraphRequest = {}

  if (controllers.length > 0) {
    req.controllers = controllers
  }

  if (resources.length > 0) {
    req.resources = resources
  }

  try {
    const resp = await ResourceService.DependencyGraph(req)

    nextTick(() => {
      nodes.value = resp.nodes?.map(item => {
        return {
          id: item.id!,
          position: { x: 0, y: 0 },
          data: {
            label: item.label?.split(".")[0],
            labels: item.labels,
            fields: item.fields,
          },
          width: 300,
          type: item.type === DependencyGraphResponseNodeType.RESOURCE ? 'resource' : 'controller',
          style: item.type === DependencyGraphResponseNodeType.RESOURCE ? {
            'border-radius': '4px',
          } : undefined
        }
      }) ?? [];

      edges.value = resp.edges?.map(item => {
        let edgeStyle = {}
        let animated = true
        let label: string = labels[item.edge_type ?? 0]

        switch (item.edge_type ?? 0) {
        case EdgeType.InputQMappedDestroyReady:
        case EdgeType.InputDestroyReady:
          edgeStyle['stroke'] = "#f2674b"
          break
        case EdgeType.InputStrong:
        case EdgeType.InputQPrimary:
          edgeStyle['stroke'] = "#88f24b"
          animated = false
          break
        case EdgeType.OutputShared:
          animated = false
          edgeStyle['stroke'] = "#3b90ff"
          break
        case EdgeType.OutputExclusive:
          animated = false
          break
        }

        return {
          id: item.id!,
          source: item.source!,
          target: item.target!,
          markerEnd: MarkerType.ArrowClosed,
          animated,
          style: edgeStyle,
          label,
        }
      }) ?? [];

      isLoading.value = false
    })
  } catch {
    isLoading.value = false
  }
})

const { onPaneReady, fitView } = useVueFlow()

const savedLayout = ref<'LR' | 'TB'>('TB')

const layoutGraph = async (direction: 'LR' | 'TB') => {
  isLoading.value = true

  savedLayout.value = direction

  try {
    nodes.value = await layout(nodes.value, edges.value, direction)
  } finally {
    isLoading.value = false
  }

  nextTick(() => {
    fitView()
  })
}

// event handler
onPaneReady(() => {
  layoutGraph(savedLayout.value)
})

const toggleControllerView = (name: string) => {
  if (isLoading.value) {
    return
  }

  if (shownControllers.value[name]) {
    delete shownControllers.value[name]
  } else {
    shownControllers.value[name] = true
  }
}

const toggleResourceView = (name: string) => {
  if (isLoading.value) {
    return
  }

  if (shownResources.value[name]) {
    delete shownResources.value[name]
  } else {
    shownResources.value[name] = true
  }
}

const filterControllers = ref('');

const filteredControllers = computed(() => {
  if (filterControllers.value === '') {
    return controllers.value;
  }

  return controllers.value.filter(item => fuzzysearch(filterControllers.value.toLowerCase(), item.toLowerCase()))
})

const filterResources = ref('');

const filteredResources = computed(() => {
  if (filterResources.value === '') {
    return resources.value;
  }

  return resources.value.filter(item => fuzzysearch(filterResources.value.toLowerCase(), item.toLowerCase()))
})

const toggleEdgeLabels = () => {
  showEdgeLabels.value = !showEdgeLabels.value

  localStorage.setItem("edge_labels", showEdgeLabels.value.toString())
}
</script>

<template>
  <div class="flex h-screen">
    <div class="h-full flex flex-col gap-2 bg-naturals-N3 text-naturals-N14 border-r border-naturals-N6">
      <div>
        <div class="flex items-center gap-2 px-4 py-2 border-b border-naturals-N5">
          <IconButton @click="() => layoutGraph('TB')" :toggle="savedLayout == 'TB'">
            <ArrowDownIcon class="w-3 h-3"/>
          </IconButton>
          <IconButton @click="() => layoutGraph('LR')" :toggle="savedLayout == 'LR'">
            <ArrowRightIcon class="w-3 h-3"/>
          </IconButton>
          <IconButton @click="() => toggleEdgeLabels()" :toggle="showEdgeLabels">
            <TagIcon class="w-3 h-3"/>
          </IconButton>
        </div>
      </div>

      <TabsRoot class="flex-1 flex flex-col gap-1 overflow-y-auto overflow-x-hidden h-full"
        default-value="controllers"
        :style="{ width: sidebarWidth ? `${sidebarWidth}px` : 'auto' }">
        <TabsList
          class="relative shrink-0 flex border-b border-naturals-N6"
        >
          <TabsIndicator class="absolute px-8 left-0 h-[2px] bottom-0 w-[--reka-tabs-indicator-size] translate-x-[--reka-tabs-indicator-position] translate-y-[1px] rounded-full transition-[width,transform] duration-300">
            <div class="bg-primary-P2 w-full h-full"/>
          </TabsIndicator>
          <TabsTrigger
            class="tab-button"
            value="controllers"
          >
            Controllers
          </TabsTrigger>
          <TabsTrigger
            class="tab-button"
            value="resources"
          >
            Resources
          </TabsTrigger>
        </TabsList>
        <TabsContent
          value="controllers"
        >
          <div class="flex items-center gap-2 px-4 py-2 border-b border-naturals-N5">
            <TextInput v-model="filterControllers" class="w-full"/>
          </div>
          <Checkbox v-for="controller in filteredControllers" :key="controller"
            class="px-4 py-2 hover:bg-naturals-N4 transition-colors duration-200 cursor-pointer text-xs select-none"
            :checked="shownControllers[controller]" @click="() => toggleControllerView(controller)"
            :label="controller"
            />
        </TabsContent>
        <TabsContent
          value="resources"
        >
          <div class="flex items-center gap-2 px-4 py-2 border-b border-naturals-N5">
            <TextInput v-model="filterResources" class="w-full"/>
          </div>
          <Checkbox v-for="resource in filteredResources" :key="resource"
            class="px-4 py-2 hover:bg-naturals-N4 transition-colors duration-200 cursor-pointer text-xs select-none"
            :checked="shownResources[resource]" @click="() => toggleResourceView(resource)"
            :label="resource"
            />
        </TabsContent>
      </TabsRoot>
    </div>
    <div style="width: 4px" class="bg-naturals-N3 hover:bg-primary-P2 transition-colors cursor-col-resize"
      @mousedown="startResize"
      />
    <div class="flex-1">
      <VueFlow :nodes="nodes" :edges="edges" class="cosi-flow dark" :default-viewport="{ zoom: 1.5 }" :min-zoom="0.2"
        @nodes-initialized="layoutGraph(savedLayout)" :max-zoom="4"
        :class="{'hide-edge-labels': !showEdgeLabels}"
        >
        <Background pattern-color="#aaa" :gap="16" />

        <template #node-resource="props">
          <ResourceNode :id="props.id" :data="props.data" />
        </template>

        <template #node-controller="props">
          <ControllerNode :id="props.id" :data="props.data" />
        </template>
      </VueFlow>
    </div>
  </div>
</template>

<style scoped>
button {
  @apply flex items-center justify-center gap-1 text-sm transition-colors duration-200 border rounded px-4 py-1.5 hover:bg-naturals-N3;
}
</style>

<style>
/* import the necessary styles for Vue Flow to work */
@import '@vue-flow/core/dist/style.css';

/* import the default theme, this is optional but generally recommended */
@import '@vue-flow/core/dist/theme-default.css';

.cosi-flow.dark {
  @apply bg-naturals-N3;
  color: #fffffb
}

.cosi-flow.dark .vue-flow__node {
  @apply bg-naturals-N0 truncate;
}

.cosi-flow.dark .vue-flow__node:hover {
  @apply transition-all duration-200;
  box-shadow: 0 0 0 2px #7D7D85;
}

.cosi-flow.dark .vue-flow__node.selected {
  @apply transition-colors duration-200;
  box-shadow: 0 0 0 2px #FE9E74
}

.cosi-flow .vue-flow__controls {
  display: flex;
  flex-wrap: wrap;
  justify-content: center
}

.cosi-flow.dark .vue-flow__controls {
  border: 1px solid #FFFFFB
}

.cosi-flow .vue-flow__controls .vue-flow__controls-button {
  border: none;
  border-right: 1px solid #eee
}

.cosi-flow .vue-flow__controls .vue-flow__controls-button svg {
  height: 100%;
  width: 100%
}

.cosi-flow.dark .vue-flow__controls .vue-flow__controls-button {
  background: #333;
  fill: #fffffb;
  border: none
}

.cosi-flow.dark .vue-flow__controls .vue-flow__controls-button:hover {
  background: #4d4d4d
}

.cosi-flow.dark .vue-flow__edge-textbg {
  @apply fill-naturals-N3 transition-opacity duration-200
}

.cosi-flow.dark .vue-flow__edge-text {
  fill: #fffffb;
  @apply transition-opacity duration-200
}

.cosi-flow.hide-edge-labels .vue-flow__edge-textbg {
  @apply opacity-0;
}

.cosi-flow.hide-edge-labels .vue-flow__edge-text {
  @apply opacity-0;
}

.tab-button {
  @apply px-3 py-2 flex-1 flex items-center justify-center text-sm leading-none select-none data-[state=active]:text-naturals-N14 outline-none cursor-pointer text-naturals-N11 border-none;
}
</style>
