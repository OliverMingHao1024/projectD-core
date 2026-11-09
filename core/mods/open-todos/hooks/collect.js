// open-todos collector: reads the Claude Code session logs under ~/.claude/projects and
// prints, as JSON on stdout, every session that still has open todos or was active
// recently. Read-only on the logs; keeps a small cache file so unchanged logs are skipped.
// Plain CommonJS without newer syntax, so an older node (12+) on PATH can run it.
//
// Output: [{ id, cwd, title, updatedAt, todos: [{ text, state }], done, total, lastPrompt, lastTool }]

'use strict'
const { existsSync, readFileSync, readdirSync, statSync, writeFileSync } = require('fs')
const { homedir } = require('os')
const { basename, join } = require('path')

const HOME = join(homedir(), '.claude')
const LOGS = join(HOME, 'projects')
const CACHE = join(HOME, 'open-todos.cache.json')
const IGNORE = join(HOME, 'open-todos-ignore.txt')
const CACHE_FORMAT = 'open-todos/2' // bump whenever readLog changes, so old results are dropped
const ACTIVE_MS = 10 * 60_000
const TODO_TOOLS = ['"TodoWrite"', '"TaskCreate"', '"TaskUpdate"']

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

// Replays the todo tools of one log, in order, and keeps the facts the pane shows.
function readLog(file, wantTail) {
  const text = readFileSync(file, 'utf8')
  const info = { cwd: '', title: '', todos: [], lastPrompt: '', lastTool: '' }
  const hasTodos = TODO_TOOLS.some(name => text.includes(name))
  if (!hasTodos && !wantTail) {
    const m = /"cwd":"((?:[^"\\]|\\.)*)"/.exec(text)
    if (m) info.cwd = JSON.parse(`"${m[1]}"`)
    return info
  }

  let list = [] // { key, text, state }
  let created = 0
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
      }
    }
    if (entry.type !== 'assistant' || !Array.isArray(content)) continue

    for (const block of content) {
      if (!block || block.type !== 'tool_use') continue
      info.lastTool = block.name
      const input = block.input || {}
      if (block.name === 'TodoWrite' && Array.isArray(input.todos)) {
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

function main() {
  const cache = loadCache()
  const nextCache = {}
  const ignore = loadIgnore()
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

      if (info.todos.length === 0 && !active) continue
      if (info.cwd && !existsSync(info.cwd)) continue // the project folder is gone

      const id = name.replace(/\.jsonl$/, '')
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
  process.stdout.write(JSON.stringify(sessions))
}

main()
