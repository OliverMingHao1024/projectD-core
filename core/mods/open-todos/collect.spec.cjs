// Fixture check for hooks/collect.js: `node core/mods/open-todos/collect.spec.cjs`.
// Runs the collector against a throwaway ~/.claude and checks the desktop step list
// (update_plan / wrap_up) and the done marks. Not a `claude plugin test` file: that
// runner has no fs or process.
'use strict'
const assert = require('assert')
const { execFileSync } = require('child_process')
const { mkdirSync, mkdtempSync, readFileSync, rmdirSync, writeFileSync } = require('fs')
const { tmpdir } = require('os')
const { join } = require('path')

const COLLECT = join(__dirname, 'hooks', 'collect.js')
const home = mkdtempSync(join(tmpdir(), 'open-todos-spec-'))
const env = Object.assign({}, process.env, { HOME: home, USERPROFILE: home })
const logs = join(home, '.claude', 'projects', 'p')
mkdirSync(logs, { recursive: true })

const OLD = '2020-01-01T00:00:00.000Z'
const LATER = '2099-01-01T00:00:00.000Z'
const prompt = (text, at) => ({ type: 'user', cwd: home, timestamp: at, message: { role: 'user', content: text } })
const call = (id, name, input) => ({
  type: 'assistant',
  cwd: home,
  message: { role: 'assistant', content: [{ type: 'tool_use', id, name, input }] },
})
const plan = 'mcp__ccd_turn__update_plan'
const items = [
  { content: 'one', status: 'in_progress' },
  { content: 'two', status: 'pending' },
  { content: 'three', status: 'pending' },
]

function write(id, entries) {
  writeFileSync(join(logs, `${id}.jsonl`), entries.map(e => JSON.stringify(e)).join('\n') + '\n')
}
const run = args => execFileSync(process.execPath, [COLLECT].concat(args || []), { env, encoding: 'utf8' })
const sessions = () => JSON.parse(run())
const todosOf = id => {
  const s = sessions().find(x => x.id === id)
  return s ? s.todos.map(t => `${t.text}:${t.state}`) : null
}

try {
  // advance, logged twice (the same tool_use id), moves exactly one step
  const advance = call('t2', plan, { advance: true })
  write('aaaaaaaa-0001', [prompt('go', OLD), call('t1', plan, { items }), advance, advance])
  assert.deepStrictEqual(todosOf('aaaaaaaa-0001'), ['two:in_progress', 'three:pending'])

  // done + start
  write('aaaaaaaa-0002', [prompt('go', OLD), call('t1', plan, { items }), call('t2', plan, { done: [1, 3], start: 2 })])
  assert.deepStrictEqual(todosOf('aaaaaaaa-0002'), ['two:in_progress'])

  // wrap_up checks off what is left (the fresh log still lists the session as active)
  write('aaaaaaaa-0003', [prompt('go', OLD), call('t1', plan, { items }), call('t2', 'mcp__ccd_turn__wrap_up', { recap: 'x' })])
  assert.deepStrictEqual(todosOf('aaaaaaaa-0003'), [])

  // a done mark hides one todo, then the whole session
  write('aaaaaaaa-0004', [prompt('go', OLD), call('t1', plan, { items })])
  run(['--done', 'aaaaaaaa-0004', 'two'])
  assert.deepStrictEqual(todosOf('aaaaaaaa-0004'), ['one:in_progress', 'three:pending'])
  run(['--done', 'aaaaaaaa-0004'])
  assert.deepStrictEqual(todosOf('aaaaaaaa-0004'), [])

  // a new prompt after the mark reopens the session and drops the mark
  write('aaaaaaaa-0004', [prompt('go', OLD), call('t1', plan, { items }), prompt('back again', LATER)])
  assert.deepStrictEqual(todosOf('aaaaaaaa-0004'), ['one:in_progress', 'two:pending', 'three:pending'])
  const marks = JSON.parse(readFileSync(join(home, '.claude', 'open-todos-done.json'), 'utf8'))
  assert.strictEqual(marks.sessions['aaaaaaaa-0004'], undefined)

  // the terminal's TodoWrite still works
  write('aaaaaaaa-0005', [prompt('go', OLD), call('t1', 'TodoWrite', { todos: [{ content: 'x', status: 'pending' }] })])
  assert.deepStrictEqual(todosOf('aaaaaaaa-0005'), ['x:pending'])

  // a bad session id is refused
  assert.throws(() => execFileSync(process.execPath, [COLLECT, '--done', '../x'], { env, stdio: 'pipe' }))

  process.stdout.write('OPEN_TODOS_COLLECT_SPEC_OK\n')
} finally {
  rmdirSync(home, { recursive: true }) // rmSync needs node 14.14; the collector supports 12
}
