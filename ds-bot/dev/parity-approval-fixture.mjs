// Loaded explicitly by an isolated bench overlay; excluded from the published plugin.
// The tool does no work beyond asking the public approval service for one decision.
import { basename } from 'node:path'
import { defineTool } from '@deepseek-ai/dsh-tools'

export const name = 'ds-bot-parity-approval-fixture'
export const inject = ['tools', 'approval']

export function apply(ctx, config = {}) {
  if (!/^[a-z0-9-]+$/.test(config.bench ?? '') || basename(process.env.DSH_HOME ?? '') !== `.dsh-test-${config.bench}`) {
    throw new Error('The approval fixture requires an explicitly named isolated mock bench')
  }
  ctx.tools.register(defineTool({
    name: 'ds_bot_test_approval',
    description: 'Mock-only parity test: ask for one harmless approval without executing a command or changing a file.',
    parameters: {},
    output: { schema: { type: 'string' }, render: (_args, value) => [{ type: 'text', text: value }] },
    async execute(_args, exec) {
      if (!exec.agent) throw new Error('This fixture requires a live test conversation')
      const decision = await ctx.approval.request({
        agent: exec.agent,
        toolName: 'ds_bot_test_approval',
        callId: exec.callId,
        reason: 'Allow the harmless approval test? No command will run and no file will change.',
        signal: exec.signal,
      })
      return `Mock approval outcome: ${decision}`
    },
  }))
}
