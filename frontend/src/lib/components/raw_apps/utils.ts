export type RawApp = {
	files: string[]
}

export const wmillTs = `
let reqs = {}

function doRequest(type: string, o: object) {
	return new Promise((resolve, reject) => {
		const reqId = Math.random().toString(36)
		reqs[reqId] = { resolve, reject }
		parent.postMessage({ ...o, type, reqId }, '*')
	})
}

export const runBg = new Proxy(
{},
{
	get(_, runnable_id: string) {
		return (v: any) => {
			return doRequest('runBg', { runnable_id, v })
	}}
})

export const runBgAsync = new Proxy(
{},
{
	get(_, runnable_id: string) {
		return (v: any) => {
			return doRequest('runBgAsync', { runnable_id, v })
	}}
})

export function waitJob(jobId: string) {
	return doRequest('waitJob', { jobId })
}

export function getJob(jobId: string) {
	return doRequest('getJob', { jobId })
}


window.addEventListener('message', (e) => {
	if (e.data.type == 'runBg' || e.data.type == 'runBgAsync') {
		console.log('Message from parent runBg', e.data)
		let job = reqs[e.data.reqId]
		if (job) {
			const result = e.data.result
			if (e.data.error) {
				job.reject(new Error(result.stack ?? result.message))
			} else {
				job.resolve(result)
			}
		} else {
			console.error('No job found for', e.data.reqId)
		}
	}
})`

export function htmlContent(workspace: string, version: number) {
	return `
        <!DOCTYPE html>
        <html>
            <head>
                <meta charset="UTF-8" />
                <title>App Preview</title>
                <link rel="stylesheet" href="/api/w/${workspace}/apps/get_data/v/${version}/index.css" />
            </head>
            <body>
                <div id="root"></div>
                <script src="/api/w/${workspace}/apps/get_data/v/${version}/index.js"></script>
            </body>
        </html>
    `
}
