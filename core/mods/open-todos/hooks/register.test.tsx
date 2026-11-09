import { expect, test } from 'claude-code/testing'

import { group, projectName, since } from './register'

const PANE = {
  plugin: 'open-todos',
  component: 'Pane',
  requestId: 'open-todos',
  props: {
    title: '待辦',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

const NOW = Date.now()
const MIN = 60_000

const SESSIONS = [
  {
    id: 'aaaa1111-0000',
    cwd: 'D:\\workspaces\\projectD-core',
    title: '狀態列 mod',
    updatedAt: NOW - 3 * 86_400_000,
    todos: [
      { text: '寫測試', state: 'in_progress' },
      { text: '發布', state: 'pending' },
    ],
    done: 1,
    total: 3,
    lastPrompt: '',
    lastTool: '',
  },
  {
    id: 'bbbb2222-0000',
    cwd: 'C:\\Users\\me\\scratch-workspaces\\x\\y',
    title: '',
    updatedAt: NOW - 1 * MIN,
    todos: [],
    done: 0,
    total: 0,
    lastPrompt: '幫我看這個 repo',
    lastTool: 'Bash',
  },
]

function engine(on: any, out: { exitCode: number; stdout: string; stderr?: string }) {
  on('command.register', () => ({ value: { command: 'todos' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('clock.every', () => ({ value: {} }))
  on('process.run', () => ({ value: { stderr: '', ...out } }))
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`groups open todos and active sessions on ${surface}`, async ($, on) => {
    engine(on, { exitCode: 0, stdout: JSON.stringify(SESSIONS) })
    await $.session.start({ cwd: '/', surface, isInteractive: true })
    await $.command.run({ command: 'todos', args: '' } as any)
    const ui = await $.ui.mount({ ...PANE, surface })
    const text = async (re: RegExp) => (await ui.find({ type: 'Text', text: re }))?.text

    expect(await text(/執行中$/)).toBe('● 1 執行中')
    expect(await text(/^無資料夾$/)).toBe('無資料夾')
    expect(await text(/^幫我看/)).toBe('幫我看這個 repo')
    expect(await text(/^projectD-core$/)).toBe('projectD-core')
    expect(await text(/寫測試/)).toBe('寫測試')
    expect(await text(/^完成/)).toBe('完成 1/3')
    expect(await text(/天前$/)).toBe('3 天前')
    await ui.unmount()
  })
}

test('a failed collect says why', async ($, on) => {
  engine(on, { exitCode: 1, stdout: '', stderr: 'node: not found' })
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run({ command: 'todos', args: '' } as any)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /讀不到/ }))?.text).toBe('讀不到待辦資料')
  await ui.unmount()
})

test('grouping and labels', () => {
  expect(projectName('D:\\a\\b\\')).toBe('b')
  expect(projectName('C:/x/scratch-workspaces/1/2')).toBe('無資料夾')
  const groups = group(SESSIONS as any, NOW)
  expect(groups.map(g => g.name)).toEqual(['無資料夾', 'projectD-core']) // active first
  expect(since(NOW - 90 * MIN, NOW)).toBe('1 小時前')
  expect(since(NOW - 86_400_000, NOW)).toBe('昨天')
})
