<script lang="ts">
	import { VariableService } from '$lib/gen'
	import Path from './Path.svelte'
	import { createEventDispatcher } from 'svelte'
	import { userStore, workspaceStore } from '$lib/stores'
	import Tooltip from './Tooltip.svelte'
	import { Button } from './common'
	import Drawer from './common/drawer/Drawer.svelte'
	import DrawerContent from './common/drawer/DrawerContent.svelte'
	import Alert from './common/alert/Alert.svelte'
	import Toggle from './Toggle.svelte'
	import type SimpleEditor from './SimpleEditor.svelte'
	import { sendUserToast } from '$lib/toast'
	import { canWrite, isOwner } from '$lib/utils'
	import ToggleButtonGroup from './common/toggleButton-v2/ToggleButtonGroup.svelte'
	import ToggleButton from './common/toggleButton-v2/ToggleButton.svelte'
	import Section from './Section.svelte'
	import { Loader2, Save } from 'lucide-svelte'
	import autosize from '$lib/autosize'

	const dispatch = createEventDispatcher()

	let path: string = $state('')

	let variable: {
		value: string
		is_secret: boolean
		description: string
	} = $state({
		value: '',
		is_secret: true,
		description: ''
	})
	let valid = $state(true)

	let drawer: Drawer | undefined = $state()
	let edit = $state(false)
	let initialPath: string = $state('')
	let pathError = $state('')
	let can_write = $state(true)

	export function initNew(): void {
		variable = {
			value: '',
			is_secret: true,
			description: ''
		}
		edit = false
		initialPath = ''
		path = ''
		can_write = true
		drawer?.openDrawer()
	}

	export async function editVariable(edit_path: string): Promise<void> {
		edit = true
		const getV = await VariableService.getVariable({
			workspace: $workspaceStore ?? '',
			path: edit_path,
			decryptSecret: false
		})
		can_write =
			getV.workspace_id == $workspaceStore &&
			canWrite(edit_path, getV.extra_perms ?? {}, $userStore)

		variable = {
			value: getV.value ?? '',
			is_secret: getV.is_secret,
			description: getV.description ?? ''
		}
		initialPath = edit_path
		path = edit_path
		drawer?.openDrawer()
	}

	export async function loadVariable(path: string): Promise<void> {
		const getV = await VariableService.getVariable({
			workspace: $workspaceStore ?? '',
			path,
			decryptSecret: true
		})
		variable.value = getV.value ?? ''
		editor?.setCode(variable.value)
	}

	const MAX_VARIABLE_LENGTH = 10000

	$effect(() => {
		valid = variable.value.length <= MAX_VARIABLE_LENGTH
	})

	async function createVariable(): Promise<void> {
		await VariableService.createVariable({
			workspace: $workspaceStore!,
			requestBody: {
				path,
				value: variable.value,
				is_secret: variable.is_secret,
				description: variable.description
			}
		})
		sendUserToast(`Created variable ${path}`)
		dispatch('create')
		drawer?.closeDrawer()
	}

	async function updateVariable(): Promise<void> {
		try {
			const getV = await VariableService.getVariable({
				workspace: $workspaceStore ?? '',
				path: initialPath,
				decryptSecret: false
			})

			await VariableService.updateVariable({
				workspace: $workspaceStore!,
				path: initialPath,
				requestBody: {
					path: getV.path != path ? path : undefined,
					value: variable.value == '' ? undefined : variable.value,
					is_secret: getV.is_secret != variable.is_secret ? variable.is_secret : undefined,
					description: getV.description != variable.description ? variable.description : undefined
				}
			})
			sendUserToast(`Updated variable ${initialPath}`)
			dispatch('create')
			drawer?.closeDrawer()
		} catch (err) {
			sendUserToast(`Could not update variable: ${err.body}`, true)
		}
	}
	let editorKind: 'plain' | 'json' | 'yaml' = $state('plain')
	let editor: SimpleEditor | undefined = $state(undefined)
</script>

<Drawer bind:this={drawer} size="900px">
	<DrawerContent
		title={edit ? `Update variable at ${initialPath}` : 'Add a variable'}
		on:close={drawer?.closeDrawer}
	>
		<div class="flex flex-col gap-8">
			{#if !can_write}
				<Alert type="warning" title="Only read access">
					You only have read access to this resource and cannot edit it
				</Alert>
			{/if}
			<Section label="Path">
				<div class="flex flex-col gap-4">
					<Path
						disabled={initialPath != '' && !isOwner(initialPath, $userStore, $workspaceStore)}
						bind:error={pathError}
						bind:path
						{initialPath}
						namePlaceholder="variable"
						kind="variable"
					/>
					<Toggle
						on:change={() => edit && loadVariable(initialPath)}
						bind:checked={variable.is_secret}
						disabled={edit && $userStore?.operator}
						options={{ right: 'Secret' }}
					/>
					{#if variable.is_secret}
						<Alert type="warning" title="Audit log for each access">
							Every secret is encrypted at rest and in transit with a key specific to this
							workspace. In addition, any read of a secret variable generates an audit log whose
							operation name is: variables.decrypt_secret
						</Alert>
					{/if}
				</div>
			</Section>
			<Section label="Variable value">
				{#snippet header()}
					<span class="text-sm text-tertiary mr-4 font-normal">
						({variable.value.length}/{MAX_VARIABLE_LENGTH} characters)
					</span>
				{/snippet}
				<div>
					<div class="mb-1">
						{#if edit && variable.is_secret}{#if $userStore?.operator}
								<div class="p-2 border">Operators cannot load secret value</div>
							{:else}
								<Button variant="border" size="xs" on:click={() => loadVariable(initialPath)}
									>Load secret value<Tooltip>Will generate an audit log</Tooltip></Button
								>{/if}{/if}
					</div>
					<div class="flex flex-col gap-2">
						<ToggleButtonGroup bind:selected={editorKind}>
							{#snippet children({ item })}
								<ToggleButton value="plain" label="Plain" {item} />
								<ToggleButton value="json" label="Json" {item} />
								<ToggleButton value="yaml" label="YAML" {item} />
							{/snippet}
						</ToggleButtonGroup>
						{#if editorKind == 'plain'}
							<textarea
								disabled={!can_write}
								rows="4"
								use:autosize
								bind:value={variable.value}
								placeholder="Update variable value"
							></textarea>
						{:else if editorKind == 'json'}
							<div class="border rounded mb-4 w-full">
								{#await import('$lib/components/SimpleEditor.svelte')}
									<Loader2 class="animate-spin" />
								{:then Module}
									<Module.default
										bind:this={editor}
										autoHeight
										lang="json"
										bind:code={variable.value}
										fixedOverflowWidgets={false}
									/>
								{/await}
							</div>
						{:else if editorKind == 'yaml'}
							<div class="border rounded mb-4 w-full">
								{#await import('$lib/components/SimpleEditor.svelte')}
									<Loader2 class="animate-spin" />
								{:then Module}
									<Module.default
										bind:this={editor}
										autoHeight
										lang="yaml"
										bind:code={variable.value}
										fixedOverflowWidgets={false}
									/>
								{/await}
							</div>
						{/if}
					</div>
				</div>
			</Section>
			<Section label="Description">
				<textarea rows="4" use:autosize bind:value={variable.description} placeholder="Used for X"
				></textarea>
			</Section>
		</div>
		{#snippet actions()}
			<Button
				on:click={() => (edit ? updateVariable() : createVariable())}
				disabled={!can_write || !valid || pathError != ''}
				startIcon={{ icon: Save }}
				color="dark"
				size="sm"
			>
				{edit ? 'Update' : 'Save'}
			</Button>
		{/snippet}
	</DrawerContent>
</Drawer>
