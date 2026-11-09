import type { EngineInterface, Register } from 'claude-code'

// statusbar — fields follow .local/statusline.ps1 (the terminal status line):
// model, folder + git branch (* when dirty), context %, 5h / 7d plan usage with reset
// time, token totals and session cost. Usage turns yellow from 50% and red from 80%.
//
// Desktop: one rounded capsule per field, Apple-style, with a ring gauge for each
// percentage and light/dark colours picked inside the SVG. Terminal: one text line.

type Window = 'five_hour' | 'seven_day'
type Limit = { window: Window; percent: number; resetsAt?: string }
type Usage = {
  model?: string
  ctxPercent?: number
  ctxTokens?: number
  ctxWindow?: number
  limits: Limit[]
  usd?: number
}
type Repo = { name: string; branch?: string; dirty: boolean }
type Place = { folder: string; branch?: string; dirty: boolean; repos?: Repo[] }
const REPOS_SHOWN = 6
type Tally = { sent: number; received: number; cached: number }

const WINDOW_LABEL: Record<Window, string> = { five_hour: '5h', seven_day: '7d' }
const WINDOW_NAME: Record<Window, string> = { five_hour: '5 小時額度', seven_day: '7 天額度' }
// Shortcut buttons on the second row. Pressing one puts the command in the prompt box.
const COMMANDS = [
  { cmd: '/compact' },
  { cmd: '/grilling' },
]
const GIT_EVERY_MS = 30_000
const REDRAW_EVERY_MS = 60_000

// ---------------- formatting ----------------

export type Level = 'ok' | 'warn' | 'high'

// Below 50% ok, from 50% warn, from 80% high.
export function levelOf(percent: number): Level {
  return percent >= 80 ? 'high' : percent >= 50 ? 'warn' : 'ok'
}

export function shortCount(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`
  return String(Math.round(n))
}

const two = (n: number) => String(n).padStart(2, '0')

// A reset later today shows its time, another day its date.
export function resetLabel(iso: string | undefined, now: number): string | undefined {
  if (!iso) return undefined
  const at = new Date(iso)
  if (Number.isNaN(at.getTime())) return undefined
  const today = new Date(now)
  const sameDay = at.toDateString() === today.toDateString()
  return sameDay ? `${two(at.getHours())}:${two(at.getMinutes())}` : `${two(at.getMonth() + 1)}/${two(at.getDate())}`
}

export function folderOf(path: string): string {
  const clean = path.replace(/[\\/]+$/, '')
  const at = Math.max(clean.lastIndexOf('\\'), clean.lastIndexOf('/'))
  return clean.slice(at + 1) || path
}

// "claude-opus-5-5[1m]" -> "Opus 5.5"
export function modelLabel(id: string): string {
  const m = /^claude-([a-z]+)-(\d+)(?:-(\d+))?/i.exec(id)
  if (!m) return id
  const family = m[1].charAt(0).toUpperCase() + m[1].slice(1)
  return m[3] ? `${family} ${m[2]}.${m[3]}` : `${family} ${m[2]}`
}

// ---------------- desktop capsules ----------------

const CAPSULE_H = 24
const FONT_SIZE = 12

// Approximate advance of system-ui at 12px: wide for CJK, narrow for punctuation.
function measure(text: string, bold = false): number {
  let w = 0
  for (const ch of text) {
    const code = ch.codePointAt(0) ?? 0
    if (code > 0x2e7f) w += 12
    else if ('.,:;|!il '.includes(ch)) w += 3.6
    else if (ch >= 'A' && ch <= 'Z') w += 7.6
    else w += 7
  }
  return bold ? w * 1.1 : w
}

const xml = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

// Theme classes resolved inside the SVG, so the capsule follows the app's light/dark mode.
const STYLE =
  '<style>' +
  ':root{color-scheme:light dark}' +
  // Slate card + per-capsule tint (same idea as letswritetw/claude-mod-token-usage):
  // a dark base reads on both light and dark app themes, so colours are fixed.
  '.t{fill:#F8FAFC}.s{fill:#94A3B8}.ln{stroke:#94A3B8}.trk{stroke:#334155}' +
  '.ok{fill:#4ADE80;stroke:#4ADE80}.warn{fill:#FBBF24;stroke:#FBBF24}.high{fill:#EF4444;stroke:#EF4444}' +
  '.blue{stroke:#60A5FA}.purple{stroke:#A78BFA}.amber{fill:#FBBF24}' +
  'g.c{cursor:default}.tint{transition:fill-opacity .12s}g.c:hover .tint{fill-opacity:.26}' +
  '</style>'
const CARD = '#1B2336'

// Glyphs drawn on a 14px grid; `cls` picks a stroke colour class.
const GLYPHS = {
  model: (x: number, cls: string) =>
    `<g transform="translate(${x} 5)" class="${cls}" fill="none" stroke-width="1.3" stroke-linejoin="round">` +
    `<path d="M7 1.5 8.4 5.6 12.5 7 8.4 8.4 7 12.5 5.6 8.4 1.5 7 5.6 5.6Z"/></g>`,
  folder: (x: number, cls: string) =>
    `<g transform="translate(${x} 5)" class="${cls}" fill="none" stroke-width="1.3" stroke-linejoin="round">` +
    `<path d="M1.5 4V11a1 1 0 0 0 1 1h9a1 1 0 0 0 1-1V5.5a1 1 0 0 0-1-1H7L5.6 2.8H2.5a1 1 0 0 0-1 1.2Z"/></g>`,
  branch: (x: number, cls: string) =>
    `<g transform="translate(${x} 5)" class="${cls}" fill="none" stroke-width="1.3" stroke-linecap="round">` +
    `<circle cx="3.5" cy="11" r="1.6"/><circle cx="10.5" cy="3" r="1.6"/><circle cx="3.5" cy="3" r="1.6"/>` +
    `<path d="M3.5 4.6v4.8M10.5 4.6C10.5 7.5 3.5 6.5 3.5 9.4"/></g>`,
  tokens: (x: number, cls: string) =>
    `<g transform="translate(${x} 5)" class="${cls}" fill="none" stroke-width="1.3" stroke-linecap="round">` +
    `<path d="M4 11.5V2.5M1.8 4.7 4 2.5l2.2 2.2M10 2.5v9M7.8 9.3 10 11.5l2.2-2.2"/></g>`,
  cost: (x: number, cls: string) =>
    `<g transform="translate(${x} 5)" class="${cls}" fill="none" stroke-width="1.3" stroke-linecap="round">` +
    `<circle cx="7" cy="7" r="5.6"/><path d="M8.9 5.2C8.5 4.6 7.8 4.3 7 4.3 6 4.3 5.2 4.8 5.2 5.6c0 1.8 3.6.9 3.6 2.7 0 .8-.8 1.3-1.8 1.3-.9 0-1.6-.4-2-1M7 3v1.3M7 9.7V11"/></g>`,
}

// Activity-ring style gauge, 14px across, starting at 12 o'clock.
function ring(x: number, percent: number, level: Level): string {
  const r = 5.5
  const c = 2 * Math.PI * r
  const p = Math.max(0, Math.min(100, percent))
  const arc = (p / 100) * c
  return (
    `<g transform="translate(${x + 7} 12) rotate(-90)" fill="none" stroke-width="2.4" stroke-linecap="round">` +
    `<circle r="${r}" class="trk"/>` +
    (arc > 0.01 ? `<circle r="${r}" class="${level}" style="fill:none" stroke-dasharray="${arc.toFixed(2)} ${c.toFixed(2)}"/>` : '') +
    `</g>`
  )
}

// A capsule is a list of runs laid out left to right.
type Run =
  | { kind: 'glyph'; draw: (x: number) => string }
  | { kind: 'ring'; percent: number; level: Level }
  | { kind: 'text'; text: string; cls: string; bold?: boolean }
  | { kind: 'space'; width: number }

export type Capsule = { svg: string; width: number; alt: string }

function capsule(runs: Run[], tip: string, alt: string, tint = '#64748B'): Capsule {
  let x = 9
  let body = ''
  for (const run of runs) {
    if (run.kind === 'glyph') {
      body += run.draw(x)
      x += 14 + 5
    } else if (run.kind === 'ring') {
      body += ring(x, run.percent, run.level)
      x += 14 + 5
    } else if (run.kind === 'text') {
      body +=
        `<text x="${x.toFixed(1)}" y="16" xml:space="preserve" font-family="system-ui,-apple-system,'Segoe UI','Microsoft JhengHei',sans-serif" ` +
        `font-size="${FONT_SIZE}"${run.bold ? ' font-weight="600"' : ''} class="${run.cls}">${xml(run.text)}</text>`
      x += measure(run.text, run.bold)
    } else {
      x += run.width
    }
  }
  const width = Math.ceil(x + 10)
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${CAPSULE_H}" viewBox="0 0 ${width} ${CAPSULE_H}">` +
    STYLE +
    `<g class="c"><title>${xml(tip)}</title>` +
    `<rect width="${width}" height="${CAPSULE_H}" rx="${CAPSULE_H / 2}" fill="${CARD}"/>` +
    `<rect class="tint" x=".5" y=".5" width="${width - 1}" height="${CAPSULE_H - 1}" rx="${CAPSULE_H / 2 - 0.5}" ` +
    `fill="${tint}" fill-opacity=".14" stroke="${tint}" stroke-opacity=".38"/>` +
    body +
    `</g></svg>`
  return { svg, width, alt }
}

const gap = (width: number): Run => ({ kind: 'space', width })

export function capsules(u: Usage | null, place: Place | null, tally: Tally, now: number): Capsule[] {
  const out: Capsule[] = []

  if (u?.model) {
    const name = modelLabel(u.model)
    out.push(capsule(
      [{ kind: 'glyph', draw: x => GLYPHS.model(x, 'purple') }, { kind: 'text', text: name, cls: 't', bold: true }],
      `模型：${u.model}`,
      name,
      '#8B5CF6',
    ))
  }

  if (place) {
    const runs: Run[] = [
      { kind: 'glyph', draw: x => GLYPHS.folder(x, 'blue') },
      { kind: 'text', text: place.folder, cls: 't' },
    ]
    if (place.branch) {
      runs.push(gap(10), { kind: 'glyph', draw: x => GLYPHS.branch(x, 'ln') }, { kind: 'text', text: place.branch, cls: 's' })
      if (place.dirty) runs.push({ kind: 'text', text: '*', cls: 'amber', bold: true })
    }
    const tip = place.branch
      ? `資料夾 ${place.folder} · 分支 ${place.branch}${place.dirty ? ' · 有未 commit 的改動' : ''}`
      : `資料夾 ${place.folder}（不是 git repo）`
    out.push(capsule(runs, tip, `${place.folder}${place.branch ? ` ${place.branch}${place.dirty ? '*' : ''}` : ''}`, '#3B82F6'))
  }

  if (u?.ctxPercent !== undefined) {
    const pct = Math.round(u.ctxPercent)
    const level = levelOf(u.ctxPercent)
    let tip = `上下文已用 ${pct}%`
    if (u.ctxWindow) {
      const used = u.ctxTokens ?? (u.ctxWindow * u.ctxPercent) / 100
      tip += `（${shortCount(used)} / ${shortCount(u.ctxWindow)}）`
    }
    out.push(capsule(
      [{ kind: 'ring', percent: u.ctxPercent, level }, { kind: 'text', text: 'ctx', cls: 's' }, gap(5), { kind: 'text', text: `${pct}%`, cls: level === 'ok' ? 't' : level, bold: true }],
      tip,
      `ctx ${pct}%`,
      '#06B6D4',
    ))
  }

  for (const l of u?.limits ?? []) {
    const pct = Math.round(l.percent)
    const level = levelOf(l.percent)
    const when = resetLabel(l.resetsAt, now)
    const runs: Run[] = [
      { kind: 'ring', percent: l.percent, level },
      { kind: 'text', text: WINDOW_LABEL[l.window], cls: 's' },
      gap(5),
      { kind: 'text', text: `${pct}%`, cls: level === 'ok' ? 't' : level, bold: true },
    ]
    if (when) runs.push(gap(6), { kind: 'text', text: '·', cls: 's' }, gap(6), { kind: 'text', text: when, cls: 's' })
    out.push(capsule(
      runs,
      `${WINDOW_NAME[l.window]}已用 ${pct}%${when ? `，${when} 重置` : ''}`,
      `${WINDOW_LABEL[l.window]} ${pct}%`,
      l.window === 'five_hour' ? '#22C55E' : '#8B5CF6',
    ))
  }

  if (tally.sent + tally.received + tally.cached > 0) {
    const text = `${shortCount(tally.sent)} / ${shortCount(tally.received)} / ${shortCount(tally.cached)}`
    out.push(capsule(
      [{ kind: 'glyph', draw: x => GLYPHS.tokens(x, 'ln') }, { kind: 'text', text, cls: 's' }],
      `token（mod 載入後累計）\n送出 ${shortCount(tally.sent)} · 收到 ${shortCount(tally.received)} · 快取讀取 ${shortCount(tally.cached)}`,
      `token ${text}`,
      '#F43F5E',
    ))
  }

  if (u?.usd !== undefined) {
    const usd = `$${u.usd.toFixed(2)}`
    out.push(capsule(
      [{ kind: 'glyph', draw: x => GLYPHS.cost(x, 'ln') }, { kind: 'text', text: usd, cls: 's' }],
      `本次 session 花費約 ${usd}`,
      usd,
      '#F59E0B',
    ))
  }

  // Folder is not a repo but holds some: one capsule per repo, name + branch.
  const repos = place?.repos ?? []
  for (const r of repos.slice(0, REPOS_SHOWN)) {
    const runs: Run[] = [
      { kind: 'glyph', draw: x => GLYPHS.branch(x, 'ln') },
      { kind: 'text', text: r.name, cls: 't' },
      gap(6),
      { kind: 'text', text: r.branch ?? '(detached)', cls: 's' },
    ]
    if (r.dirty) runs.push({ kind: 'text', text: '*', cls: 'amber', bold: true })
    out.push(capsule(
      runs,
      `${r.name} · 分支 ${r.branch ?? '(detached)'}${r.dirty ? ' · 有未 commit 的改動' : ''}`,
      `${r.name} ${r.branch ?? ''}${r.dirty ? '*' : ''}`,
      '#14B8A6',
    ))
  }
  if (repos.length > REPOS_SHOWN) {
    const n = repos.length - REPOS_SHOWN
    out.push(capsule([{ kind: 'text', text: `+${n} repo`, cls: 's' }], repos.slice(REPOS_SHOWN).map(r => r.name).join('、'), `+${n} repo`))
  }

  return out
}

// ---------------- terminal line ----------------

export function plainParts(u: Usage | null, place: Place | null, tally: Tally, now: number): string[] {
  const parts: string[] = []
  if (u?.model) parts.push(modelLabel(u.model))
  if (place) parts.push(place.branch ? `${place.folder} (${place.branch}${place.dirty ? '*' : ''})` : place.folder)
  for (const r of place?.repos ?? []) parts.push(`${r.name} (${r.branch ?? 'detached'}${r.dirty ? '*' : ''})`)
  if (u?.ctxPercent !== undefined) parts.push(`ctx ${Math.round(u.ctxPercent)}%`)
  for (const l of u?.limits ?? []) {
    const when = resetLabel(l.resetsAt, now)
    parts.push(`${WINDOW_LABEL[l.window]} ${Math.round(l.percent)}%${when ? ` @${when}` : ''}`)
  }
  if (tally.sent + tally.received + tally.cached > 0) {
    parts.push(`tok ${shortCount(tally.sent)}/${shortCount(tally.received)}/${shortCount(tally.cached)}`)
  }
  if (u?.usd !== undefined) parts.push(`$${u.usd.toFixed(2)}`)
  return parts
}

// ---------------- data ----------------

async function readUsage($: EngineInterface): Promise<Usage> {
  const [model, usage] = await Promise.all([
    $.session.model().catch(() => undefined),
    $.session.usage().catch(() => undefined),
  ])
  const limits: Limit[] = []
  for (const window of ['five_hour', 'seven_day'] as const) {
    const hit = usage?.rateLimits.find(r => r.kind === window)
    if (hit) limits.push({ window, percent: hit.percentUsed, resetsAt: hit.resetsAt })
  }
  return {
    model,
    ctxPercent: usage?.context.percent,
    ctxTokens: usage?.context.tokens,
    ctxWindow: usage?.context.window,
    limits,
    usd: usage?.cost?.usd,
  }
}

async function readPlace($: EngineInterface): Promise<Place> {
  const cwd = await $.session.cwd()
  const folder = folderOf(cwd)

  // Branch and dirty mark of the repo at `dir`, or null when it is not one.
  const inspect = async (dir: string): Promise<{ branch?: string; dirty: boolean } | null> => {
    const git = (...args: string[]) =>
      $.process.run(['git', ...args], { cwd: dir, timeoutMs: 5000 }).catch(() => ({ exitCode: 1, stdout: '' }))
    const head = await git('branch', '--show-current')
    if (head.exitCode !== 0) return null
    const branch = head.stdout.trim() || (await git('rev-parse', '--short', 'HEAD')).stdout.trim()
    // -uno: tracked files only, so large repos stay fast
    const status = await git('status', '--porcelain', '-uno')
    return { branch: branch || undefined, dirty: status.stdout.trim() !== '' }
  }

  const here = await inspect(cwd)
  if (here) return { folder, branch: here.branch, dirty: here.dirty }

  // Not a repo itself (e.g. a TFS workspace root): list the repos one level down.
  const base = cwd.replace(/[\\/]+$/, '')
  const kids = await $.fs.list(cwd).catch(() => [])
  const found = await Promise.all(
    kids
      .filter(k => k.kind === 'dir' && !k.name.startsWith('.'))
      .map(async k => {
        // .git is a folder, or a file in a worktree: exists() covers both
        if (!(await $.fs.exists(`${base}/${k.name}/.git`).catch(() => false))) return null
        const r = await inspect(`${base}/${k.name}`)
        return r ? { name: k.name, branch: r.branch, dirty: r.dirty } : null
      }),
  )
  const repos = found.filter((r): r is Repo => r !== null).sort((a, b) => a.name.localeCompare(b.name))
  return { folder, dirty: false, repos: repos.length > 0 ? repos : undefined }
}

// ---------------- hooks ----------------

export const register: Register = on => {
  // Kept in the module: a reload clears them and session.start reads them again.
  let usage: Usage | null = null
  let place: Place | null = null
  const tally: Tally = { sent: 0, received: 0, cached: 0 }

  on('session.start', async ($, e, next) => {
    const result = await next(e)
    ;[usage, place] = await Promise.all([readUsage($), readPlace($)])
    $.ui.invalidate('ui.render')
    $.clock.every(GIT_EVERY_MS, async () => {
      const fresh = await readPlace($)
      if (JSON.stringify(fresh) !== JSON.stringify(place)) {
        place = fresh
        $.ui.invalidate('ui.render')
      }
    })
    $.clock.every(REDRAW_EVERY_MS, () => $.ui.invalidate('ui.render'))
    return result
  })

  on('session.measure', async ($, e, next) => {
    usage = await readUsage($)
    $.ui.invalidate('ui.render')
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (e.usage) {
      tally.sent += e.usage.input_tokens + e.usage.cache_creation_input_tokens
      tally.received += e.usage.output_tokens
      tally.cached += e.usage.cache_read_input_tokens
    }
    const result = await next(e)
    ;[usage, place] = await Promise.all([readUsage($), readPlace($)])
    $.ui.invalidate('ui.render')
    return result
  })

  // A tool that may write files or run git: look at the branch and dirty mark again.
  on('tool.call', async ($, e, next) => {
    const result = await next(e)
    if (!['Read', 'Grep', 'Glob'].includes(e.tool)) {
      const fresh = await readPlace($)
      if (JSON.stringify(fresh) !== JSON.stringify(place)) {
        place = fresh
        $.ui.invalidate('ui.render')
      }
    }
    return result
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey || (!usage && !place)) return next(e)
    const ui = $.ui.resolve(e)
    const { Box, Text, Button } = ui
    const now = await $.clock.now()

    if (e.surface === 'desktop' && 'Svg' in ui) {
      const { Svg } = ui
      const list = capsules(usage, place, tally, now)
      if (list.length === 0) return next(e)
      // Capsules wrap whole onto a second row when the column is narrow.
      // Two fixed rows: first four capsules (model, folder, ctx, 5h) on top; the rest
      // (7d, tokens, cost) share row two with the shortcut buttons, so buttons never
      // drop to a third row. A press only fills the prompt box; Enter sends it.
      const cap = (c: Capsule) => (
        <Svg key={c.alt} source={c.svg} alt={c.alt} width={c.width} height={CAPSULE_H} isInteractive />
      )
      // Repo capsules (TFS-style workspace root) are the tail of the list; give them their own rows.
      const nRepos = place?.repos ? Math.min(place.repos.length, REPOS_SHOWN) + (place.repos.length > REPOS_SHOWN ? 1 : 0) : 0
      const main = list.slice(0, list.length - nRepos)
      const repoCaps = list.slice(list.length - nRepos)
      return (
        <Box flexDirection="column" rowGap={1}>
          <Box flexDirection="row" flexWrap="wrap" columnGap={1}>
            {main.slice(0, 4).map(cap)}
          </Box>
          <Box flexDirection="row" flexWrap="wrap" columnGap={1}>
            {main.slice(4).map(cap)}
            {COMMANDS.map(c => (
              <Button key={c.cmd} label={c.cmd} dimColor onPress={() => { void $.prompt.fill({ text: c.cmd }) }} />
            ))}
          </Box>
          {repoCaps.length > 0 ? (
            <Box flexDirection="row" flexWrap="wrap" columnGap={1} rowGap={1}>
              {repoCaps.map(cap)}
            </Box>
          ) : null}
        </Box>
      )
    }

    const parts = plainParts(usage, place, tally, now)
    if (parts.length === 0) return next(e)
    return <Text wrap="truncate-end">{parts.join(' · ')}</Text>
  })
}
