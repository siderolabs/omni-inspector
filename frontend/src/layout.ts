import { Position, useVueFlow } from '@vue-flow/core'
import { Ref, ref } from 'vue'
import type { Node, Edge } from '@vue-flow/core'
import ELK, { ElkNode } from 'elkjs/lib/elk.bundled.js'

export const useLayout = () => {
  const { findNode } = useVueFlow()

  const graph = ref(new ELK())

  const previousDirection: Ref<'LR' | 'TB'> = ref('LR')

  const layout = async (nodes: Node[], edges: Edge[], direction: 'LR' | 'TB') => {
    // we create a new graph instance, in case some nodes/edges were removed, otherwise dagre would act as if they were still there
    const isHorizontal = direction === 'LR'

    const elkNode: ElkNode = {
      id: "root",
      layoutOptions: { 'elk.algorithm': 'layered', 'elk.direction': isHorizontal ? 'RIGHT' : 'DOWN', 'spacing.nodeNodeBetweenLayers': '100' },
      children: [],
      edges: []
    }

    for (const node of nodes) {
      // if you need width+height of nodes for your layout, you can use the dimensions property of the internal node (`GraphNode` type)
      const graphNode = findNode(node.id)

      if (!graphNode) {
        continue
      }

      elkNode.children?.push({
        id: node.id,
        width: graphNode.dimensions.width,
        height: graphNode.dimensions.height,
      })
    }

    for (const edge of edges) {
      elkNode.edges?.push({
        id: edge.id,
        sources: [edge.source],
        targets: [edge.target]
      })
    }

    await graph.value.layout(elkNode)

    const elkNodes: Record<string, ElkNode> = {};

    for (const node of elkNode.children!) {
      elkNodes[node.id] = node
    }

    // set nodes with updated positions
    return nodes.map((node) => {
      const nodeWithPosition = elkNodes[node.id]

      if (!nodeWithPosition) {
        return node
      }

      return {
        ...node,
        targetPosition: isHorizontal ? Position.Left : Position.Top,
        sourcePosition: isHorizontal ? Position.Right : Position.Bottom,
        position: { x: nodeWithPosition.x ?? 0, y: nodeWithPosition.y ?? 0 },
      }
    })
  }

  return { graph, layout, previousDirection }
}
