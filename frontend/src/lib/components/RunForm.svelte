<script lang="ts">
	import {
		computeSharableHash as computeSharableHash,
		defaultIfEmptyString,
		emptyString,
		truncateHash
	} from '$lib/utils'

	import type { Schema } from '$lib/common'
	import { Badge, Button } from './common'
	import SchemaForm from './SchemaForm.svelte'
	import SharedBadge from './SharedBadge.svelte'

	import TimeAgo from './TimeAgo.svelte'
	import Popover from './meltComponents/Popover.svelte'
	import { Calendar, Check, CornerDownLeft } from 'lucide-svelte'
	import RunFormAdvancedPopup from './RunFormAdvancedPopup.svelte'
	import { page } from '$app/stores'
	import { replaceState } from '$app/navigation'
	import JsonInputs from '$lib/components/JsonInputs.svelte'
	import { triggerableByAI } from '$lib/actions/triggerableByAI'
	import InputSelectedBadge from './schema/InputSelectedBadge.svelte'
	import { untrack } from 'svelte'

	let reloadArgs = $state(0)
	let jsonEditor: JsonInputs | undefined = $state(undefined)
	let schemaHeight = $state(0)
	let showInputSelectedBadge = $state(false)
	let savedPreviousArgs: Record<string, any> | undefined = $state(undefined)

	export async function setArgs(nargs: Record<string, any>) {
		args = nargs
		reloadArgs++
	}

	export function run() {
		runAction(scheduledForStr, args ?? {}, invisible_to_owner, overrideTag)
	}

	interface Props {
		runnable:
			| {
					summary?: string
					schema?: Schema | any
					description?: string
					path?: string
					is_template?: boolean
					hash?: string
					kind?: string
					can_write?: boolean
					created_at?: string
					created_by?: string
					extra_perms?: Record<string, boolean>
			  }
			| undefined
		runAction: (
			scheduledForStr: string | undefined,
			args: Record<string, any>,
			invisible_to_owner: boolean | undefined,
			overrideTag: string | undefined
		) => void
		buttonText?: string
		schedulable?: boolean
		detailed?: boolean
		autofocus?: boolean
		topButton?: boolean
		loading?: boolean
		noVariablePicker?: boolean
		viewKeybinding?: boolean
		scheduledForStr: string | undefined
		invisible_to_owner: boolean | undefined
		overrideTag: string | undefined
		args?: Record<string, any>
		jsonView?: boolean
		isValid?: boolean
	}

	let {
		runnable = $bindable(),
		runAction,
		buttonText = 'Run',
		schedulable = true,
		detailed = true,
		autofocus = false,
		topButton = false,
		loading = false,
		noVariablePicker = false,
		viewKeybinding = false,
		scheduledForStr = $bindable(),
		invisible_to_owner = $bindable(),
		overrideTag = $bindable(),
		args = $bindable(),
		jsonView = false,
		isValid = $bindable(true)
	}: Props = $props()

	$effect.pre(() => {
		if (args == undefined) {
			args = {}
		}
	})

	let debounced: NodeJS.Timeout | undefined = undefined

	function onArgsChange(args: any) {
		try {
			debounced && clearTimeout(debounced)
			debounced = setTimeout(() => {
				const nurl = new URL(window.location.href)
				nurl.hash = computeSharableHash(args)

				try {
					replaceState(nurl.toString(), $page.state)
				} catch (e) {
					console.error(e)
				}
			}, 200)
		} catch (e) {
			console.error('Impossible to set hash in args', e)
		}
	}

	export function setCode(code: string) {
		jsonEditor?.setCode(code)
	}
	$effect(() => {
		Object.keys(args ?? {}).forEach((key) => {
			args?.[key]
		})
		untrack(() => onArgsChange(args))
	})
</script>

<!-- Standalone triggerable registration for the run form -->
<div
	style="display: none"
	use:triggerableByAI={{
		id: `run-form-${runnable?.path ?? ''}`,
		description: `Form to fill the inputs to run ${runnable?.summary && runnable?.summary.length > 0 ? runnable?.summary : runnable?.path}.
	## Script description: ${runnable?.description ?? ''}.
	## Schema used: ${JSON.stringify(runnable?.schema)}.
	## Current args: ${JSON.stringify(args)}}`,
		callback: (value) => {
			savedPreviousArgs = args
			setArgs(JSON.parse(value ?? '{}'))
			showInputSelectedBadge = true
		},
		showAnimation: false
	}}
></div>

{#snippet acceptButton()}
	<Button
		startIcon={{
			icon: Check
		}}
		size="xs2"
		btnClasses="border border-gray-200 dark:border-gray-600 !bg-surface text-primary"
		on:click={() => {
			showInputSelectedBadge = false
			savedPreviousArgs = undefined
		}}
	>
		Accept
	</Button>
{/snippet}

{#if showInputSelectedBadge}
	<InputSelectedBadge
		inputSelected="ai"
		labelColor="text-violet-800 dark:text-primary"
		className="dark:!bg-violet-800 !bg-violet-200 !border-violet-200 dark:!border-violet-800"
		{acceptButton}
		onReject={() => {
			setArgs(savedPreviousArgs ?? {})
			savedPreviousArgs = undefined
			showInputSelectedBadge = false
		}}
	/>
{/if}
<div class="max-w-3xl">
	{#if detailed}
		{#if runnable}
			<div class="flex flex-row flex-wrap justify-between gap-4">
				<div>
					<div class="flex flex-col mb-2">
						<h1 class="break-words py-2 mr-2">
							{defaultIfEmptyString(runnable.summary, runnable.path ?? '')}
						</h1>
						{#if !emptyString(runnable.summary)}
							<h2 class="font-bold pb-4">{runnable.path}</h2>
						{/if}

						<div class="flex items-center gap-2">
							<span class="text-sm text-tertiary">
								{#if runnable}
									Edited <TimeAgo agoOnlyIfRecent date={runnable.created_at || ''} /> by {runnable.created_by ||
										'unknown'}
								{/if}
							</span>
							<Badge color="dark-gray">
								{truncateHash(runnable?.hash ?? '')}
							</Badge>
							{#if runnable?.is_template}
								<Badge color="blue">Template</Badge>
							{/if}
							{#if runnable && runnable.kind !== 'runnable'}
								<Badge color="blue">
									{runnable?.kind}
								</Badge>
							{/if}
							<SharedBadge
								canWrite={runnable.can_write ?? true}
								extraPerms={runnable?.extra_perms ?? {}}
							/>
						</div>
					</div>
				</div>
			</div>
		{:else}
			<h1
				use:triggerableByAI={{
					id: 'run-form-loading',
					description: 'Run form is loading, should scan the page until this is gone'
				}}>Loading...</h1
			>
		{/if}
	{/if}
	{#if topButton}
		<Button
			btnClasses="!px-6 !py-1 w-full"
			disabled={!isValid || jsonView}
			on:click={() => runAction(undefined, args ?? {}, invisible_to_owner, overrideTag)}
		>
			{buttonText}
		</Button>
	{/if}
	{#if runnable?.schema}
		<div class="my-2"></div>
		{#if !runnable.schema.properties || Object.keys(runnable.schema.properties).length === 0}
			<div class="text-sm py-4 italic">No arguments</div>
		{:else if jsonView}
			<div class="py-2" style="height: {schemaHeight}px" data-schema-picker>
				<JsonInputs
					bind:this={jsonEditor}
					on:select={(e) => {
						if (e.detail) {
							args = e.detail
						}
					}}
					updateOnBlur={false}
					placeholder={`Write args as JSON.<br/><br/>Example:<br/><br/>{<br/>&nbsp;&nbsp;"foo": "12"<br/>}`}
				/>
			</div>
		{:else}
			{#key reloadArgs}
				<div bind:clientHeight={schemaHeight}>
					<SchemaForm
						helperScript={runnable.hash
							? {
									type: 'hash',
									hash: runnable.hash
								}
							: undefined}
						prettifyHeader
						{noVariablePicker}
						{autofocus}
						schema={runnable.schema}
						bind:isValid
						bind:args
					/>
				</div>
			{/key}
		{/if}
	{:else}
		<div class="text-xs text-tertiary">No arguments</div>
	{/if}
	{#if schedulable}
		<div class="mt-10"></div>
		<div class="flex gap-2 items-start flex-wrap justify-between mt-2 md:mt-6 mb-6">
			<div class="flex-row-reverse flex-wrap flex w-full gap-4">
				<Button
					{loading}
					color="dark"
					btnClasses="!px-6 !py-1 !h-8 inline-flex gap-2"
					disabled={!isValid || jsonView}
					on:click={() => runAction(scheduledForStr, args ?? {}, invisible_to_owner, overrideTag)}
					shortCut={{ Icon: CornerDownLeft, hide: !viewKeybinding }}
				>
					{scheduledForStr ? 'Schedule to run later' : buttonText}
				</Button>
				<div>
					<Popover placement="bottom" closeButton usePointerDownOutside>
						{#snippet trigger()}
							<Button nonCaptureEvent startIcon={{ icon: Calendar }} size="xs" color="light">
								Advanced
							</Button>
						{/snippet}
						{#snippet content()}
							<RunFormAdvancedPopup
								bind:scheduledForStr
								bind:invisible_to_owner
								bind:overrideTag
								bind:runnable
							/>
						{/snippet}
					</Popover>
				</div>
			</div>
			{#if overrideTag}
				<div class="flex-row-reverse flex w-full text-primary text-sm">
					tag override: {overrideTag}
				</div>
			{/if}
			{#if invisible_to_owner}
				<div class="flex-row-reverse flex w-full text-primary text-sm">
					Job will be invisible to owner
				</div>
			{/if}
		</div>
	{:else if !topButton}
		<Button
			btnClasses="!px-6 !py-1 w-full"
			disabled={!isValid || jsonView}
			on:click={() => runAction(undefined, args ?? {}, invisible_to_owner, overrideTag)}
			shortCut={{ Icon: CornerDownLeft, hide: !viewKeybinding }}
		>
			{buttonText}
		</Button>
	{/if}
</div>
