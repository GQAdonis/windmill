<script lang="ts">
	import type { FlowModule } from '$lib/gen'
	import { getBezierPath, BaseEdge, type Position, EdgeLabel } from '@xyflow/svelte'
	import { getStraightLinePath } from '../utils'

	interface Props {
		sourceX: number
		sourceY: number
		sourcePosition: Position
		targetX: number
		targetY: number
		targetPosition: Position
		markerEnd?: string | undefined
		data: {
			modules: FlowModule[]
			sourceId: string
			targetId: string
		}
	}

	let {
		sourceX,
		sourceY,
		sourcePosition,
		targetX,
		targetY,
		targetPosition,
		markerEnd = undefined
	}: Props = $props()

	let [edgePath, labelX, labelY] = $derived(
		getBezierPath({
			sourceX,
			sourceY: targetY - sourceY > 100 ? targetY - 100 : sourceY,
			sourcePosition,
			targetX,
			targetY,
			targetPosition,
			curvature: 0.25
		})
	)
</script>

<EdgeLabel x={labelX} y={labelY}></EdgeLabel>

<BaseEdge
	path={targetY - sourceY > 100
		? `${edgePath} ${getStraightLinePath({ sourceX, sourceY, targetY })}`
		: edgePath}
	{markerEnd}
	style={`animation:dashdraw 0.5s linear infinite; stroke-dasharray: 5px;`}
/>
