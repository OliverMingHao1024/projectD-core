import { expect, test } from 'claude-code/testing'

import { capsules, folderOf, levelOf, modelLabel, resetLabel } from './register'

const BAND = {
  plugin: 'statusbar',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 200 },
} as const

const NOW = new Date(2099, 10, 6, 9, 0).getTime() // local 2099-11-06 09:00
const TODAY_1120 = new Date(2099, 10, 6, 11, 20).toISOString()
const NOV_10 = new Date(2099, 10, 10, 8, 0).toISOString()

function engine(on: any, opts: { dirty: boolean; ctx: number; fiveHour: number; cwd?: string; git?: boolean }) {
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
  on('session.cwd', () => ({ value: opts.cwd ?? 'D:\\workspaces\\projectD-core' }))
  on('session.usage', () => ({
    value: {
      startedAt: 0,
      context: { tokens: opts.ctx * 2000, window: 200000, percent: opts.ctx },
      rateLimits: [
        { kind: 'seven_day', percentUsed: 12, resetsAt: NOV_10 },
        { kind: 'five_hour', percentUsed: opts.fiveHour, resetsAt: TODAY_1120 },
      ],
      cost: { usd: 0.4234 },
    },
  }))
  on('process.run', (_: any, e: any) => {
    if (opts.git === false) return { value: { exitCode: 128, stdout: '', stderr: 'not a git repo' } }
    const sub = e.argv[1]
    if (sub === 'branch') return { value: { exitCode: 0, stdout: 'main\n', stderr: '' } }
    if (sub === 'status') return { value: { exitCode: 0, stdout: opts.dirty ? ' M a.ts\n' : '', stderr: '' } }
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })
  on('clock.every', () => ({ value: {} }))
  on('clock.now', () => ({ value: NOW }))
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
}

test('terminal: one plain line with every field', async ($, on) => {
  engine(on, { dirty: true, ctx: 42, fiveHour: 85 })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe(
    'Opus 5.5 · projectD-core (main*) · ctx 42% · 5h 85% @11:20 · 7d 12% @11/10 · $0.42',
  )
  await ui.unmount()
})

test('desktop: one capsule per field, in order', async ($, on) => {
  engine(on, { dirty: true, ctx: 42, fiveHour: 85 })
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
  const alts = (await ui.findAll({ type: 'Svg' })).map(s => s.props.alt)
  expect(alts).toEqual(['Opus 5.5', 'projectD-core main*', 'ctx 42%', '5h 85%', '7d 12%', '$0.42'])
  await ui.unmount()
})

test('outside a git repo only the folder shows', async ($, on) => {
  engine(on, { dirty: false, ctx: 10, fiveHour: 10, cwd: 'C:\\Users\\me\\scratch-2026\\', git: false })
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
  const alts = (await ui.findAll({ type: 'Svg' })).map(s => s.props.alt)
  expect(alts[1]).toBe('scratch-2026')
  await ui.unmount()
})

test('levels, labels and escaping', () => {
  expect([levelOf(49), levelOf(50), levelOf(79.9), levelOf(80)]).toEqual(['ok', 'warn', 'warn', 'high'])
  expect(modelLabel('claude-sonnet-5-5')).toBe('Sonnet 5.5')
  expect(modelLabel('gpt-x')).toBe('gpt-x')
  expect(folderOf('D:/a/b/')).toBe('b')
  expect(resetLabel(TODAY_1120, NOW)).toBe('11:20')
  expect(resetLabel(NOV_10, NOW)).toBe('11/10')

  const [, folder, ctx] = capsules(
    { model: 'claude-opus-5-5', ctxPercent: 60, limits: [] },
    { folder: 'a&b<c>', dirty: false },
    { sent: 0, received: 0, cached: 0 },
    NOW,
  )
  expect(folder.svg).toContain('a&amp;b&lt;c&gt;')
  expect(ctx.svg).toContain('class="warn"')
})
