<script lang="ts">
	import { goto } from '$lib/navigation'
	import { afterNavigate, replaceState } from '$app/navigation'
	import { page } from '$app/stores'

	import FlowBuilder from '$lib/components/FlowBuilder.svelte'
	import UnsavedConfirmationModal from '$lib/components/common/confirmationModal/UnsavedConfirmationModal.svelte'
	import type { FlowState } from '$lib/components/flows/flowState'
	import { importFlowStore, initFlow } from '$lib/components/flows/flowStore.svelte'
	import { FlowService, type Flow } from '$lib/gen'
	import { initialArgsStore, userStore, workspaceStore } from '$lib/stores'
	import { sendUserToast } from '$lib/toast'
	import { decodeState, emptySchema, type StateStore } from '$lib/utils'
	import { tick } from 'svelte'
	import { writable } from 'svelte/store'
	import { replaceScriptPlaceholderWithItsValues } from '$lib/hub'
	import type { Trigger } from '$lib/components/triggers/utils'

	let nodraft = $page.url.searchParams.get('nodraft')

	afterNavigate(() => {
		if (nodraft) {
			let url = new URL($page.url.href)
			url.search = ''
			replaceState(url.toString(), $page.state)
		}
	})

	const hubId = $page.url.searchParams.get('hub')
	const templatePath = $page.url.searchParams.get('template')
	const templateId = $page.url.searchParams.get('template_id')
	const initialState = hubId || templatePath || nodraft ? undefined : localStorage.getItem('flow')

	let selectedId: string = $state('settings-metadata')
	let loading = $state(false)

	let initialPath: string | undefined = $state(undefined)
	let pathStoreInit: string | undefined = $state(undefined)

	let initialArgs = $state({})
	if ($initialArgsStore) {
		initialArgs = $initialArgsStore
		$initialArgsStore = undefined
	}
	let flowBuilder: FlowBuilder | undefined = $state(undefined)

	const flowStore: StateStore<Flow> = $state({
		val: {
			summary: '',
			value: { modules: [] },
			path: '',
			edited_at: '',
			edited_by: '',
			archived: false,
			extra_perms: {},
			schema: emptySchema()
		}
	})
	const flowStateStore = writable<FlowState>({})

	let draftTriggersFromUrl: Trigger[] | undefined = $state(undefined)
	let selectedTriggerIndexFromUrl: number | undefined = $state(undefined)
	async function loadFlow() {
		loading = true
		let flow: Flow = {
			path: '',
			summary: '',
			value: { modules: [] },
			edited_by: '',
			edited_at: '',
			archived: false,
			extra_perms: {},
			schema: emptySchema()
		}

		let state = initialState ? decodeState(initialState) : undefined
		const initialStateQuery = $page.url.hash != '' ? $page.url.hash.slice(1) : undefined

		if (initialStateQuery) {
			state = decodeState(initialStateQuery)
		}
		if ($importFlowStore) {
			flow = $importFlowStore
			$importFlowStore = undefined
			sendUserToast('Flow loaded from YAML/JSON')
		} else if (!templatePath && !hubId && state) {
			sendUserToast('Flow restored from draft', false, [
				{
					label: 'Start from blank instead',
					callback: () => {
						flowStore.val = {
							summary: '',
							value: { modules: [] },
							path: '',
							edited_at: '',
							edited_by: '',
							archived: false,
							extra_perms: {},
							schema: emptySchema()
						}
					}
				}
			])

			flow = state.flow
			pathStoreInit = state.path
			draftTriggersFromUrl = state.draft_triggers
			selectedTriggerIndexFromUrl = state.selected_trigger
			flowBuilder?.setDraftTriggers(draftTriggersFromUrl)
			flowBuilder?.setSelectedTriggerIndex(selectedTriggerIndexFromUrl)
			state?.selectedId && (selectedId = state?.selectedId)
		} else {
			if (templatePath) {
				let template: Flow
				if (templateId) {
					template = await FlowService.getFlowVersion({
						workspace: $workspaceStore!,
						path: templatePath,
						version: parseInt(templateId)
					})
				} else {
					template = await FlowService.getFlowByPath({
						workspace: $workspaceStore!,
						path: templatePath
					})
				}
				Object.assign(flow, template)
				const oldPath = templatePath.split('/')
				initialPath = `u/${$userStore?.username.split('@')[0].replace(/[^a-zA-Z0-9_]/g, '')}/${
					oldPath[oldPath.length - 1]
				}_fork`
				flow = flow
				goto('?', { replaceState: true })
				selectedId = 'settings-metadata'
			} else if (hubId) {
				const hub = await FlowService.getHubFlowById({ id: Number(hubId) })
				delete hub['comments']
				initialPath = `u/${$userStore?.username}/flow_${hubId}`
				Object.assign(flow, hub.flow)
				if (flow.value.preprocessor_module?.value.type === 'rawscript') {
					flow.value.preprocessor_module.value.content = replaceScriptPlaceholderWithItsValues(
						hubId,
						flow.value.preprocessor_module.value.content
					)
				}
				flow = flow
				goto('?', { replaceState: true })
				selectedId = 'constants'
			} else {
				tick().then(() => {
					flowBuilder?.triggerTutorial()
				})
			}
		}
		await initFlow(flow, flowStore, flowStateStore)
		flowBuilder?.loadFlowState()
		loading = false
	}

	loadFlow()
</script>

<!-- <div id="monaco-widgets-root" class="monaco-editor" style="z-index: 1200;" /> -->

<FlowBuilder
	on:saveInitial={(e) => {
		goto(`/flows/edit/${e.detail}?selected=${flowBuilder?.getSelectedId?.()}`)
	}}
	on:deploy={(e) => {
		goto(`/flows/get/${e.detail}?workspace=${$workspaceStore}`)
	}}
	on:details={(e) => {
		goto(`/flows/get/${e.detail}?workspace=${$workspaceStore}`)
	}}
	{initialPath}
	{pathStoreInit}
	bind:this={flowBuilder}
	newFlow
	{initialArgs}
	{flowStore}
	{flowStateStore}
	{selectedId}
	{loading}
	{draftTriggersFromUrl}
	{selectedTriggerIndexFromUrl}
	noInitial
>
	<UnsavedConfirmationModal
		getInitialAndModifiedValues={flowBuilder?.getInitialAndModifiedValues}
	/>
</FlowBuilder>
