<script lang="ts">
	import Label from '../Label.svelte'
	import { DatabaseIcon, Info, Loader2, Trash2 } from 'lucide-svelte'
	import ToggleButton from '../common/toggleButton-v2/ToggleButton.svelte'
	import ToggleButtonGroup from '../common/toggleButton-v2/ToggleButtonGroup.svelte'
	import Button from '../common/button/Button.svelte'
	import CustomPopover from '../CustomPopover.svelte'
	import { Webhook, Route, Unplug, Mail, Play } from 'lucide-svelte'
	import KafkaIcon from '$lib/components/icons/KafkaIcon.svelte'
	import { createEventDispatcher, onDestroy, untrack } from 'svelte'
	import { type TriggerKind } from '../triggers'
	import { CaptureService } from '$lib/gen'
	import { workspaceStore } from '$lib/stores'
	import { type CaptureTriggerKind } from '$lib/gen'
	import CaptureButton from '$lib/components/triggers/CaptureButton.svelte'
	import InfiniteList from '../InfiniteList.svelte'
	import { isObject, sendUserToast } from '$lib/utils'
	import SchemaPickerRow from '$lib/components/schema/SchemaPickerRow.svelte'
	import type { Capture } from '$lib/gen'
	import { AwsIcon, MqttIcon } from '../icons'
	import GoogleCloudIcon from '../icons/GoogleCloudIcon.svelte'

	interface Props {
		path: string
		hasPreprocessor?: boolean
		canHavePreprocessor?: boolean
		isFlow?: boolean
		captureType?: CaptureTriggerKind | undefined
		headless?: boolean
		addButton?: boolean
		canEdit?: boolean
		fullHeight?: boolean
		limitPayloadSize?: boolean
		noBorder?: boolean
		captureActiveIndicator?: boolean | undefined
	}

	let {
		path,
		hasPreprocessor = false,
		canHavePreprocessor = false,
		isFlow = false,
		captureType = undefined,
		headless = false,
		addButton = false,
		canEdit = false,
		fullHeight = true,
		limitPayloadSize = false,
		noBorder = false,
		captureActiveIndicator = undefined
	}: Props = $props()

	let selected: number | undefined = $state(undefined)
	let testKind: 'preprocessor' | 'main' = $state('main')
	let isEmpty: boolean = $state(true)
	let infiniteList: InfiniteList | null = $state(null)
	let capturesLength = $state(0)
	let openStates: Record<string, boolean> = {}
	let viewerOpen = $state(false)

	$effect(() => {
		hasPreprocessor && (testKind = 'preprocessor')
	})

	const dispatch = createEventDispatcher<{
		openTriggers: {
			kind: TriggerKind
			config: Record<string, any>
		}
		applyArgs: {
			kind: 'main' | 'preprocessor'
			args: Record<string, any> | undefined
		}
		addPreprocessor: null
		updateSchema: {
			payloadData: any
			redirect: boolean
			args?: boolean
		}
		select: any
		testWithArgs: any
		selectCapture: Capture | undefined
	}>()

	interface CaptureWithPayload extends Capture {
		getFullCapture?: () => Promise<Capture>
		payloadData?: any
	}

	export async function loadCaptures(refresh: boolean = false) {
		await infiniteList?.loadData(refresh ? 'refresh' : 'loadMore')
	}

	function initLoadCaptures(kind: 'preprocessor' | 'main' = testKind) {
		const loadInputsPageFn = async (page: number, perPage: number) => {
			const captures = await CaptureService.listCaptures({
				workspace: $workspaceStore!,
				runnableKind: isFlow ? 'flow' : 'script',
				path: path ?? '',
				triggerKind: captureType,
				page,
				perPage
			})

			let capturesWithPayload: CaptureWithPayload[] = captures.map((capture) => {
				let newCapture: CaptureWithPayload = { ...capture }

				const isLarge =
					capture.main_args === 'WINDMILL_TOO_BIG' ||
					capture.preprocessor_args === 'WINDMILL_TOO_BIG'
				if (isLarge) {
					newCapture = {
						...capture,
						payloadData: 'Too big to display here, select to view',
						getFullCapture: () =>
							CaptureService.getCapture({
								workspace: $workspaceStore!,
								id: capture.id
							})
					}
					return newCapture
				}
				const preprocessor_args = isObject(capture.preprocessor_args)
					? capture.preprocessor_args
					: {}

				if ('wm_trigger' in preprocessor_args) {
					// v1
					newCapture.payloadData =
						kind === 'preprocessor'
							? typeof capture.main_args === 'object'
								? {
										...capture.main_args,
										...preprocessor_args
									}
								: preprocessor_args
							: capture.main_args
				} else {
					// v2
					newCapture.payloadData = kind === 'preprocessor' ? preprocessor_args : capture.main_args
				}

				return newCapture
			})
			return capturesWithPayload
		}
		infiniteList?.setLoader(loadInputsPageFn)

		const deleteInputFn = async (id: any) => {
			await CaptureService.deleteCapture({
				workspace: $workspaceStore!,
				id
			})
		}
		infiniteList?.setDeleteItemFn(deleteInputFn)
	}

	async function handleSelect(capture: Capture) {
		if (selected === capture.id) {
			resetSelected()
		} else {
			const payloadData = await getPayload(capture)
			selected = capture.id
			dispatch('select', structuredClone($state.snapshot(payloadData)))
			dispatch('selectCapture', capture)
		}
	}

	async function getPayload(capture: CaptureWithPayload) {
		let payloadData: any = {}
		if (capture.getFullCapture) {
			const fullCapture = await capture.getFullCapture()
			const preprocessor_args = isObject(fullCapture.preprocessor_args)
				? fullCapture.preprocessor_args
				: {}
			if ('wm_trigger' in preprocessor_args) {
				// v1
				payloadData =
					testKind === 'preprocessor'
						? {
								...(typeof fullCapture.main_args === 'object' ? fullCapture.main_args : {}),
								...preprocessor_args
							}
						: fullCapture.main_args
			} else {
				// v2
				payloadData =
					testKind === 'preprocessor' ? fullCapture.preprocessor_args : fullCapture.main_args
			}
		} else {
			payloadData = structuredClone($state.snapshot(capture.payloadData))
		}
		return payloadData
	}

	export function resetSelected(dispatchEvent: boolean = true) {
		selected = undefined
		if (dispatchEvent) {
			dispatch('select', undefined)
		}
	}

	onDestroy(() => {
		resetSelected()
	})

	const captureKindToIcon: Record<string, any> = {
		webhook: Webhook,
		http: Route,
		email: Mail,
		websocket: Unplug,
		kafka: KafkaIcon,
		mqtt: MqttIcon,
		sqs: AwsIcon,
		postgres: DatabaseIcon,
		gcp: GoogleCloudIcon
	}

	function handleKeydown(event: KeyboardEvent) {
		if (event.key === 'Escape' && selected) {
			resetSelected()
			event.stopPropagation()
			event.preventDefault()
		}
	}

	function handleError(error: { type: string; error: any }) {
		if (error.type === 'delete') {
			sendUserToast(`Failed to delete capture: ${error.error}`, true)
		} else if (error.type === 'load') {
			sendUserToast(`Failed to load captures: ${error.error}`, true)
		}
	}

	function updateViewerOpenState(itemId: string, isOpen: boolean) {
		openStates[itemId] = isOpen
		viewerOpen = Object.values(openStates).some((state) => state)
	}

	$effect(() => {
		path && infiniteList && untrack(() => initLoadCaptures())
	})
</script>

<svelte:window onkeydown={handleKeydown} />

<Label label="Trigger captures" {headless} class="h-full {headless ? '' : 'flex flex-col gap-1'}">
	{#snippet header()}
		{#if addButton}
			<div class="inline-block">
				<CaptureButton small={true} on:openTriggers />
			</div>
		{/if}
		{#if captureActiveIndicator}
			<Loader2 class="animate-spin" size={16} />
		{/if}
	{/snippet}
	{#snippet action()}
		{#if canHavePreprocessor && !isEmpty}
			<div>
				<ToggleButtonGroup
					bind:selected={testKind}
					class="h-full"
					on:selected={(e) => {
						initLoadCaptures(e.detail)
					}}
				>
					{#snippet children({ item })}
						<ToggleButton value="main" label={isFlow ? 'Flow' : 'Main'} small {item} />
						<ToggleButton
							value="preprocessor"
							label="Preprocessor"
							small
							tooltip="When the runnable has a preprocessor, it receives additional information about the request"
							{item}
						/>
					{/snippet}
				</ToggleButtonGroup>
			</div>
		{/if}
	{/snippet}

	<div
		class={fullHeight
			? headless
				? 'h-full'
				: 'min-h-0 grow'
			: capturesLength > 7
				? 'h-[300px]'
				: 'h-fit'}
	>
		<InfiniteList
			bind:this={infiniteList}
			selectedItemId={selected}
			bind:isEmpty
			on:error={(e) => handleError(e.detail)}
			on:select={(e) => handleSelect(e.detail)}
			bind:length={capturesLength}
			{noBorder}
			neverShowLoader={captureActiveIndicator !== undefined}
		>
			{#snippet columns()}
				<colgroup>
					<col class="w-8" />
					<col class="w-16" />
					<col />
				</colgroup>
			{/snippet}
			{#snippet children({ item, hover })}
				{@const captureIcon = captureKindToIcon[item.trigger_kind]}
				<SchemaPickerRow
					date={item.created_at}
					payloadData={item.payloadData}
					hovering={hover}
					on:openChange={({ detail }) => {
						updateViewerOpenState(item.id, detail)
					}}
					{viewerOpen}
					{limitPayloadSize}
				>
					{#snippet start()}
						{@const SvelteComponent = captureIcon}

						<div class="center-center">
							<SvelteComponent size={12} />
						</div>
					{/snippet}

					{#snippet extra({ isTooBig })}
						{#if canEdit}
							<div class="flex flex-row items-center gap-2 px-2">
								{#if testKind === 'preprocessor' && !hasPreprocessor}
									<CustomPopover noPadding>
										<Button
											size="xs2"
											color="dark"
											disabled
											endIcon={{
												icon: Info
											}}
											wrapperClasses="h-full"
										>
											Apply args
										</Button>
										{#snippet overlay()}
											<div class="text-sm p-2 flex flex-col gap-1 items-start">
												<p> You need to add a preprocessor to use preprocessor captures as args </p>
												<Button
													size="xs2"
													color="dark"
													on:click={() => {
														dispatch('addPreprocessor')
													}}
												>
													Add preprocessor
												</Button>
											</div>
										{/snippet}
									</CustomPopover>
								{:else}
									<Button
										size="xs2"
										color={hover || selected === item.id ? 'dark' : 'light'}
										dropdownItems={[
											{
												label: 'Use as input schema',
												onClick: async () => {
													const payloadData = await getPayload(item)
													dispatch('updateSchema', {
														payloadData,
														redirect: true,
														args: true
													})
												},
												disabled: isTooBig,
												hidden: !isFlow || testKind !== 'main'
											}
										].filter((item) => !item.hidden)}
										on:click={async () => {
											const payloadData = await getPayload(item)
											if (isFlow && testKind === 'main') {
												dispatch('testWithArgs', payloadData)
											} else {
												dispatch('applyArgs', {
													kind: testKind,
													args: payloadData
												})
											}
										}}
										disabled={testKind === 'preprocessor' && !hasPreprocessor}
										title={isFlow && testKind === 'main'
											? 'Test flow with args'
											: testKind === 'preprocessor'
												? 'Apply args to preprocessor'
												: 'Apply args to inputs'}
										startIcon={isFlow && testKind === 'main' ? { icon: Play } : {}}
									>
										{isFlow && testKind === 'main' ? 'Test' : 'Apply args'}
									</Button>
								{/if}
								<Button
									size="xs2"
									color="light"
									variant="contained"
									iconOnly
									startIcon={{ icon: Trash2 }}
									loading={item.isDeleting}
									on:click={() => {
										infiniteList?.deleteItem(item.id)
									}}
									btnClasses="hover:text-white hover:bg-red-500 text-red-500"
								/>
							</div>
						{/if}
					{/snippet}
				</SchemaPickerRow>
			{/snippet}
			{#snippet empty()}
				<div class="text-center text-xs text-tertiary py-2">No captures yet</div>
			{/snippet}
		</InfiniteList>
	</div>
</Label>
