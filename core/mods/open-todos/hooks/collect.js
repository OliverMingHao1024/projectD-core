// open-todos collector: reads the Claude Code session logs under ~/.claude/projects and
// prints, as JSON on stdout, every session that still has open todos or was active
// recently. Read-only on the logs; keeps a small cache file so unchanged logs are skipped.
// Plain CommonJS without newer syntax, so an older node (12+) on PATH can run it.
//
// Output: [{ id, cwd, title, updatedAt, todos: [{ text, state }], done, total, lastPrompt, lastTool }]
//
// `node collect.js --done <session id> [todo text]` marks one todo (or, without a text,
// every open todo of that session) as done by hand. The mark lives in its own file, never
// in the session log, and lapses once the person sends that session a new prompt.

'use strict'
const { existsSync, readFileSync, readdirSync, statSync, writeFileSync } = require('fs')
const { homedir } = require('os')
const { basename, join } = require('path')

const HOME = join(homedir(), '.claude')
const LOGS = join(HOME, 'projects')
const CACHE = join(HOME, 'open-todos.cache.json')
const IGNORE = join(HOME, 'open-todos-ignore.txt')
const DONE = join(HOME, 'open-todos-done.json')
const CACHE_FORMAT = 'open-todos/3' // bump whenever readLog changes, so old results are dropped
const DONE_FORMAT = 'open-todos-done/1'
const ACTIVE_MS = 10 * 60_000
// TodoWrite / TaskCreate / TaskUpdate in the terminal; the desktop app's Code tab keeps
// its step list with update_plan and checks it off with wrap_up.
const TODO_TOOLS = ['"TodoWrite"', '"TaskCreate"', '"TaskUpdate"', '__update_plan"']
const isPlan = name => name === 'update_plan' || /__update_plan$/.test(name)
const isWrapUp = name => name === 'wrap_up' || /__wrap_up$/.test(name)

const now = Date.now()

function loadCache() {
  try {
    const data = JSON.parse(readFileSync(CACHE, 'utf8'))
    return data.format === CACHE_FORMAT ? data.files : {}
  } catch (_) {
    return {}
  }
}

// One line per entry: a project name, a folder path, or the start of a session id. '#' comments.
function loadIgnore() {
  try {
    return readFileSync(IGNORE, 'utf8')
      .split(/\r?\n/)
      .map(line => line.trim())
      .filter(line => line && !line.startsWith('#'))
      .map(line => line.replace(/\\/g, '/').toLowerCase())
  } catch (_) {
    return []
  }
}

const readable = text => typeof text === 'string' && text !== '' && !text.includes('�')

function promptText(content) {
  if (typeof content === 'string') return content
  if (Array.isArray(content)) {
    const block = content.find(b => b && b.type === 'text' && typeof b.text === 'string')
    return block ? block.text : ''
  }
  return ''
}

// update_plan: `items` replaces the list; `done` (1-based) completes steps, `advance`
// completes the step in progress and starts the next pending one, `start` starts a step.
function applyPlan(list, input) {
  if (Array.isArray(input.items)) {
    return input.items.map((t, i) => ({ key: `p${i}`, text: t && t.content, state: (t && t.status) || 'pending' }))
  }
  if (Array.isArray(input.done)) {
    for (const n of input.done) if (list[n - 1]) list[n - 1].state = 'completed'
  }
  if (input.advance === true) {
    const doing = list.find(t => t.state === 'in_progress')
    if (doing) doing.state = 'completed'
    const nextUp = list.find(t => t.state === 'pending')
    if (nextUp) nextUp.state = 'in_progress'
  }
  if (typeof input.start === 'number' && list[input.start - 1]) list[input.start - 1].state = 'in_progress'
  return list
}

// Replays the todo tools of one log, in order, and keeps the facts the pane shows.
function readLog(file, wantTail) {
  const text = readFileSync(file, 'utf8')
  const info = { cwd: '', title: '', todos: [], lastPrompt: '', lastTool: '', lastPromptAt: 0 }
  const hasTodos = TODO_TOOLS.some(name => text.includes(name))
  if (!hasTodos && !wantTail) {
    const m = /"cwd":"((?:[^"\\]|\\.)*)"/.exec(text)
    if (m) info.cwd = JSON.parse(`"${m[1]}"`)
    return info
  }

  let list = [] // { key, text, state }
  let created = 0
  const seen = new Set() // a tool call can be logged more than once; replay it once
  for (const line of text.split('\n')) {
    if (line === '') continue
    let entry
    try {
      entry = JSON.parse(line)
    } catch (_) {
      continue
    }
    if (!info.cwd && typeof entry.cwd === 'string') info.cwd = entry.cwd
    if (entry.type === 'custom-title' && readable(entry.customTitle)) info.title = entry.customTitle

    const content = entry.message && entry.message.content
    if (entry.type === 'user' && !entry.isMeta) {
      const said = promptText(content).trim()
      if (said && !said.startsWith('<') && !said.startsWith('[') && !said.startsWith('Base directory')) {
        info.lastPrompt = said.replace(/\s+/g, ' ').slice(0, 80)
        const at = Date.parse(entry.timestamp)
        if (at > info.lastPromptAt) info.lastPromptAt = at
      }
    }
    if (entry.type !== 'assistant' || !Array.isArray(content)) continue

    for (const block of content) {
      if (!block || block.type !== 'tool_use') continue
      if (block.id) {
        if (seen.has(block.id)) continue
        seen.add(block.id)
      }
      info.lastTool = block.name
      const input = block.input || {}
      if (isPlan(block.name)) {
        list = applyPlan(list, input)
      } else if (isWrapUp(block.name)) {
        // wrap_up closes the turn and checks off what is left of its list
        for (const t of list) if (t.state === 'pending' || t.state === 'in_progress') t.state = 'completed'
      } else if (block.name === 'TodoWrite' && Array.isArray(input.todos)) {
        list = input.todos.map((t, i) => ({ key: `w${i}`, text: t.content, state: t.status }))
      } else if (block.name === 'TaskCreate') {
        // one task ({ subject }) or a batch ({ tasks }: an array, or that array as a JSON string)
        let batch = input.tasks
        if (typeof batch === 'string') {
          try {
            batch = JSON.parse(batch)
          } catch (_) {
            batch = null
          }
        }
        const made = Array.isArray(batch) ? batch : [input]
        for (const task of made) {
          if (!task || typeof task !== 'object') continue
          created += 1
          list.push({ key: String(created), text: task.subject || task.description, state: task.status || 'pending' })
        }
      } else if (block.name === 'TaskUpdate') {
        const item = list.find(t => t.key === String(input.taskId))
        if (!item) continue
        if (input.subject) item.text = input.subject
        if (input.status) item.state = input.status
      }
    }
  }

  const kept = list.filter(t => t.state !== 'deleted' && readable(t.text))
  info.todos = kept.filter(t => t.state === 'pending' || t.state === 'in_progress').map(t => ({ text: t.text, state: t.state }))
  info.done = kept.filter(t => t.state === 'completed').length
  info.total = kept.length
  return info
}

// { [session id]: { at: ms, all: bool, todos: [text] } }: todos marked done by hand.
function loadDone() {
  try {
    const data = JSON.parse(readFileSync(DONE, 'utf8'))
    return data.format === DONE_FORMAT && data.sessions && typeof data.sessions === 'object' ? data.sessions : {}
  } catch (_) {
    return {}
  }
}

function saveDone(marks) {
  writeFileSync(DONE, JSON.stringify({ format: DONE_FORMAT, sessions: marks }, null, 2))
}

function markDone(id, text) {
  if (!/^[0-9a-f-]{8,64}$/i.test(id || '')) throw new Error('--done needs a session id')
  const marks = loadDone()
  const mark = marks[id] || { at: 0, all: false, todos: [] }
  mark.at = Date.now()
  if (text) {
    if (mark.todos.indexOf(text) < 0) mark.todos.push(text)
  } else {
    mark.all = true
  }
  marks[id] = mark
  saveDone(marks)
}

// Hides the todos marked done, unless the session was prompted again after the mark.
// Returns the info to show, or null when the mark has lapsed and should be dropped.
function applyDone(info, mark) {
  if (!mark || info.lastPromptAt > mark.at) return null
  const open = info.todos.filter(t => !mark.all && mark.todos.indexOf(t.text) < 0)
  const hidden = info.todos.length - open.length
  return Object.assign({}, info, { todos: open, done: (info.done || 0) + hidden })
}

function main() {
  const cache = loadCache()
  const nextCache = {}
  const ignore = loadIgnore()
  const marks = loadDone()
  let marksChanged = false
  const sessions = []

  let folders = []
  try {
    folders = readdirSync(LOGS, { withFileTypes: true }).filter(d => d.isDirectory())
  } catch (_) {
    process.stdout.write('[]')
    return
  }

  for (const folder of folders) {
    const dir = join(LOGS, folder.name)
    let names = []
    try {
      names = readdirSync(dir).filter(n => n.endsWith('.jsonl'))
    } catch (_) {
      continue
    }
    for (const name of names) {
      const file = join(dir, name)
      let st
      try {
        st = statSync(file)
      } catch (_) {
        continue
      }
      const active = now - st.mtimeMs <= ACTIVE_MS
      const prior = cache[file]
      let info = prior && prior.size === st.size && prior.mtimeMs === st.mtimeMs && (!active || prior.tail) ? prior.info : null
      if (!info) {
        try {
          info = readLog(file, active)
        } catch (_) {
          continue
        }
      }
      nextCache[file] = { size: st.size, mtimeMs: st.mtimeMs, tail: active, info }

      const id = name.replace(/\.jsonl$/, '')
      if (marks[id]) {
        const shown = applyDone(info, marks[id])
        if (shown) {
          info = shown
        } else {
          delete marks[id] // reopened: its todos count again
          marksChanged = true
        }
      }

      if (info.todos.length === 0 && !active) continue
      if (info.cwd && !existsSync(info.cwd)) continue // the project folder is gone

      const keys = [info.cwd, basename(info.cwd || ''), id.slice(0, 8)].map(k => (k || '').replace(/\\/g, '/').toLowerCase())
      if (keys.some(k => k && ignore.includes(k))) continue
      if (/[\\/]observer-sessions$/.test(info.cwd)) continue // background sessions of the claude-mem plugin

      sessions.push({
        id,
        cwd: info.cwd,
        title: info.title,
        updatedAt: st.mtimeMs,
        todos: info.todos,
        done: info.done || 0,
        total: info.total || 0,
        lastPrompt: active ? info.lastPrompt : '',
        lastTool: active ? info.lastTool : '',
      })
    }
  }

  try {
    writeFileSync(CACHE, JSON.stringify({ format: CACHE_FORMAT, files: nextCache }))
  } catch (_) {
    // a cache that cannot be written only makes the next run slower
  }
  if (marksChanged) {
    try {
      saveDone(marks)
    } catch (_) {
      // a lapsed mark that stays on disk lapses again next run
    }
  }
  process.stdout.write(JSON.stringify(sessions))
}

if (process.argv[2] === '--done') {
  markDone(process.argv[3], process.argv[4])
} else {
  main()
}
