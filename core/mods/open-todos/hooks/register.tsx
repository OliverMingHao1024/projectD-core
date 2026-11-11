import type { EngineInterface, Register } from 'claude-code'

// open-todos — a side pane listing, across every Claude Code session on this machine,
// the todos still open and the sessions active right now, grouped by project.
// hooks/collect.js reads the session logs (node); this module groups and draws.

type Todo = { text: string; state: 'pending' | 'in_progress' }
export type Session = {
  id: string
  cwd: string
  title: string
  updatedAt: number
  todos: Todo[]
  done: number
  total: number
  lastPrompt: string
  lastTool: string
}
export type Group = { name: string; sessions: Session[]; active: number; latest: number }

const PANE = 'open-todos'
const ACTIVE_MS = 5 * 60_000
const QUIET_DAYS = 14
const RESCAN_MS = 20_000
const TODOS_SHOWN = 5
const SESSIONS_SHOWN = 4

// Soft dark-theme palette from letswritetw/claude-mod-open-todos: cool hues name a project,
// warm / green accents are reserved for status. The terminal maps them to its nearest.
const HUES = ['#7FD6CB', '#9DB0FF', '#BFA9FF', '#8EDDB0', '#85CBF0', '#DDAEEB']
const GREEN = '#86DDAE' // running now
const ORANGE = '#F3CB82' // in progress
const GRAY = '#8E96AD' // waiting

function hueOf(name: string): string {
  let h = 0
  for (const c of name) h = (h * 31 + c.charCodeAt(0)) >>> 0
  return HUES[h % HUES.length]
}

// ---------------- grouping ----------------

const isActive = (s: Session, now: number) => now - s.updatedAt <= ACTIVE_MS

export function projectName(cwd: string): string {
  if (/scratch-workspaces/i.test(cwd)) return '無資料夾'
  const clean = cwd.replace(/[\\/]+$/, '')
  return clean.slice(Math.max(clean.lastIndexOf('\\'), clean.lastIndexOf('/')) + 1) || '未知專案'
}

export function group(sessions: Session[], now: number): Group[] {
  const byName = new Map<string, Session[]>()
  for (const s of sessions) {
    const name = projectName(s.cwd)
    byName.set(name, [...(byName.get(name) ?? []), s])
  }
  const groups = [...byName].map(([name, list]) => {
    const sorted = [...list].sort(
      (a, b) => Number(isActive(b, now)) - Number(isActive(a, now)) || b.updatedAt - a.updatedAt,
    )
    return {
      name,
      sessions: sorted,
      active: sorted.filter(s => isActive(s, now)).length,
      latest: Math.max(...sorted.map(s => s.updatedAt)),
    }
  })
  // Projects with an active session first, then the most recently touched.
  return groups.sort((a, b) => Number(b.active > 0) - Number(a.active > 0) || b.latest - a.latest)
}

export function since(updatedAt: number, now: number): string {
  const minutes = Math.floor((now - updatedAt) / 60_000)
  if (minutes < 60) return `${Math.max(1, minutes)} 分鐘前`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours} 小時前`
  const days = Math.floor(hours / 24)
  if (days === 1) return '昨天'
  if (days < 60) return `${days} 天前`
  return `${Math.floor(days / 30)} 個月前`
}

// ---------------- collecting ----------------

// Module state: a reload clears it and session.start collects again.
let sessions: Session[] = []
let failure = ''
let loaded = false
let running = false
let queued = false
let lastJson = ''

async function collect($: EngineInterface): Promise<void> {
  if (running) {
    queued = true
    return
  }
  running = true
  try {
    const out = await $.process.run(['node', `${$.plugin.root}/hooks/collect.js`], { timeoutMs: 60_000 })
    if (out.exitCode !== 0) throw new Error(out.stderr.trim().slice(0, 200) || `node 結束代碼 ${out.exitCode}`)
    const changed = out.stdout !== lastJson || failure !== '' || !loaded
    if (out.stdout !== lastJson) {
      sessions = JSON.parse(out.stdout) as Session[]
      lastJson = out.stdout
    }
    failure = ''
    loaded = true
    if (changed) $.ui.invalidate('ui.render')
  } catch (error) {
    failure = error instanceof Error ? error.message : String(error)
    loaded = true
    $.ui.invalidate('ui.render')
  } finally {
    running = false
    if (queued) {
      queued = false
      void collect($)
    }
  }
}

// The terminal's todo tools, and the desktop Code tab's step list (update_plan, wrap_up).
const isTodoTool = (tool: string) =>
  ['TodoWrite', 'TaskCreate', 'TaskUpdate'].includes(tool) || /(^|__)(update_plan|wrap_up)$/.test(tool)

// Marks a todo (or, without a text, every open todo of the session) done by hand, then
// collects again. collect.js keeps the mark until the session is prompted again.
async function markDone($: EngineInterface, id: string, text?: string): Promise<void> {
  const argv = ['node', `${$.plugin.root}/hooks/collect.js`, '--done', id]
  if (text !== undefined) argv.push(text)
  const out = await $.process.run(argv, { timeoutMs: 20_000 })
  if (out.exitCode !== 0) {
    failure = out.stderr.trim().slice(0, 200) || `node 結束代碼 ${out.exitCode}`
    $.ui.invalidate('ui.render')
    return
  }
  await collect($)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    await $.command.register({ name: 'todos', description: '開啟或重新整理所有 session 的待辦面板' })
    void $.ui.open({ id: PANE, title: '待辦' })
    void collect($)
    // other sessions change too; collect.js only re-reads logs that changed
    $.clock.every(RESCAN_MS, () => void collect($))
    return result
  })

  on('tool.call', async ($, e, next) => {
    const result = await next(e)
    if (isTodoTool(e.tool)) void collect($)
    return result
  })

  on('turn.complete', async ($, e, next) => {
    void collect($)
    return next(e)
  })

  on('command.run', { command: 'todos' }, async $ => {
    await $.ui.open({ id: PANE, title: '待辦' })
    await collect($)
    return { text: '待辦面板已重新整理。' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const now = Date.now()

    if (!loaded) {
      return (
        <Box paddingX={1}>
          <Text dimColor>正在讀取各 session 的待辦…</Text>
        </Box>
      )
    }
    if (failure !== '') {
      return (
        <Box flexDirection="column" paddingX={1}>
          <Text bold>讀不到待辦資料</Text>
          <Text dimColor wrap="truncate-end">{failure}</Text>
          <Text dimColor>需要電腦上有 node。確認後輸入 /todos 再試一次。</Text>
        </Box>
      )
    }

    const groups = group(sessions, now)
    if (groups.length === 0) {
      return (
        <Box flexDirection="column" paddingX={1}>
          <Text bold>都做完了</Text>
          <Text dimColor>沒有未完成的待辦，也沒有正在執行的 session。</Text>
        </Box>
      )
    }

    const all = groups.flatMap(g => g.sessions)
    const doing = all.reduce((n, s) => n + s.todos.filter(t => t.state === 'in_progress').length, 0)
    const waiting = all.reduce((n, s) => n + s.todos.filter(t => t.state === 'pending').length, 0)
    const activeCount = all.filter(s => isActive(s, now)).length

    const count = (color: string, n: number, label: string) => (
      <Text>
        <Text color={n > 0 ? color : GRAY}>● </Text>
        <Text bold={n > 0} dimColor={n === 0}>{`${n} ${label}`}</Text>
      </Text>
    )
    // Text that may run long sits in a box that grows, so labels beside it keep their width.
    const grow = (child: any) => (
      <Box width={1} flexGrow={1} flexShrink={1}>
        {child}
      </Box>
    )

    return (
      <Box flexDirection="column" paddingX={1}>
        <Box gap={2}>
          {count(GREEN, activeCount, '執行中')}
          {count(ORANGE, doing, '進行中')}
          {count(GRAY, waiting, '待辦')}
        </Box>

        {groups.map(g => {
          const open = g.sessions.reduce((n, s) => n + s.todos.length, 0)
          const shown = g.sessions.slice(0, SESSIONS_SHOWN)
          const more = g.sessions.length - shown.length
          return (
            <Box flexDirection="column" marginTop={1}>
              <Box>
                {grow(<Text bold color={hueOf(g.name)} wrap="truncate-end">{g.name}</Text>)}
                <Box flexShrink={0} marginLeft={1}>
                  <Text dimColor>{open > 0 ? `${open} 項` : ''}</Text>
                </Box>
              </Box>

              <Box>
              <Box width={1} flexShrink={0} backgroundColor={hueOf(g.name)} />
              <Box width={1} flexGrow={1} flexShrink={1} flexDirection="column">
              {shown.map(s => {
                const live = isActive(s, now)
                const quiet = !live && now - s.updatedAt > QUIET_DAYS * 86_400_000
                const name = s.title || s.lastPrompt || `未命名 ${s.id.slice(0, 8)}`
                const todos = [...s.todos].sort(
                  (a, b) => Number(b.state === 'in_progress') - Number(a.state === 'in_progress'),
                )
                const rows = todos.slice(0, TODOS_SHOWN)
                return (
                  <Box flexDirection="column" marginTop={1} paddingLeft={1}>
                    <Box>
                      {grow(<Text dimColor={quiet} wrap="truncate-end">{name}</Text>)}
                      <Box flexShrink={0} marginLeft={1}>
                        {live ? (
                          <Text color={GREEN} bold>● 執行中</Text>
                        ) : (
                          <Text dimColor>{since(s.updatedAt, now)}</Text>
                        )}
                      </Box>
                    </Box>
                    {live && s.title && s.lastPrompt ? (
                      <Text dimColor wrap="truncate-end">{`› ${s.lastPrompt}`}</Text>
                    ) : null}
                    {live && s.lastTool ? <Text dimColor wrap="truncate-end">{`工具：${s.lastTool}`}</Text> : null}
                    {s.total > 1 || s.todos.length > 1 ? (
                      <Box>
                        {grow(<Text dimColor>{s.total > 1 ? `完成 ${s.done}/${s.total}` : ''}</Text>)}
                        {s.todos.length > 1 ? (
                          <Box flexShrink={0} marginLeft={1}>
                            <Button
                              key={`done-all-${s.id}`}
                              label="全部完成"
                              dimColor
                              onPress={() => { void markDone($, s.id) }}
                            />
                          </Box>
                        ) : null}
                      </Box>
                    ) : null}
                    {rows.map(t => (
                      <Box>
                        <Text color={t.state === 'in_progress' ? ORANGE : GRAY}>
                          {t.state === 'in_progress' ? ' ◉ ' : ' ○ '}
                        </Text>
                        {grow(
                          <Text bold={t.state === 'in_progress'} dimColor={quiet} wrap="truncate-end">
                            {t.text}
                          </Text>,
                        )}
                        {/* Done: hide it until the session is prompted again. */}
                        <Box flexShrink={0} marginLeft={1}>
                          <Button
                            key={`done-${s.id}-${t.text}`}
                            label="完成"
                            dimColor
                            onPress={() => { void markDone($, s.id, t.text) }}
                          />
                        </Box>
                        {/* Chat: put the todo in the prompt box to talk it through (Enter sends). */}
                        <Box flexShrink={0} marginLeft={1}>
                          <Button
                            key={`chat-${s.id}-${t.text}`}
                            label="Chat"
                            dimColor
                            onPress={() => { void $.prompt.fill({ text: `Re: ${t.text}\n` }) }}
                          />
                        </Box>
                      </Box>
                    ))}
                    {todos.length > rows.length ? (
                      <Text dimColor>{`   還有 ${todos.length - rows.length} 項`}</Text>
                    ) : null}
                  </Box>
                )
              })}
              {more > 0 ? <Text dimColor>{` 另有 ${more} 個 session`}</Text> : null}
              </Box>
              </Box>
            </Box>
          )
        })}
      </Box>
    )
  })
}
