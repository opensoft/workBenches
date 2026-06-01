export const meta = {
  name: 'deep-swarm-code-review',
  description: 'Swarm of expert subagents deep-reviews a PR / branch / uncommitted diff, adversarially verifies each finding, and (in PR mode) automatically posts all confirmed findings as inline comments on the PR',
  whenToUse: 'Deep multi-agent code review. Auto-targets: open PR for the current branch, else committed branch-vs-main, else uncommitted working-tree changes. In PR mode it ALWAYS posts all confirmed findings to the PR automatically (set args.post=false to suppress, args.dedupeAgainstExisting=true to skip findings already commented on the PR). Override with args {mode:"pr"|"branch"|"uncommitted", prNumber, base}.',
  phases: [
    { title: 'Scope',  detail: 'detect review target (PR / branch / uncommitted) + partition the diff' },
    { title: 'Review', detail: 'multi-pass swarm — each pass adds expert lenses, finer file units, deeper digging' },
    { title: 'Verify', detail: 'independent skeptic verifies each finding + validates the diff line' },
    { title: 'Post',   detail: 'auto-publish one consolidated GitHub review of all confirmed findings (PR mode)' },
  ],
}

// ============================================================================
// args (all optional — workflow auto-detects when omitted):
//   mode:      'pr' | 'branch' | 'uncommitted'
//   prNumber:  number (pr mode)
//   base:      base ref for committed diffs (default auto: origin/main || main)
//   post:      boolean — post results to GitHub (default true in pr mode)
//   repoRoot:  absolute path (default: current working dir of agents)
// ============================================================================
const cfg = args || {}
const REPO_ROOT = cfg.repoRoot || '.'
const POST = cfg.post !== false          // PR mode auto-posts unless explicitly disabled
const DEDUPE = cfg.dedupeAgainstExisting === true  // skip findings already commented on the PR

// ---- Phase 0: detect the review target -------------------------------------
phase('Scope')

const SCOPE_SCHEMA = {
  type: 'object',
  required: ['mode', 'base', 'summary'],
  properties: {
    mode: { type: 'string', enum: ['pr', 'branch', 'uncommitted'] },
    prNumber: { type: 'integer' },
    base: { type: 'string' },
    branch: { type: 'string' },
    summary: { type: 'string' },
  },
}

let scope
if (cfg.mode) {
  scope = { mode: cfg.mode, prNumber: cfg.prNumber, base: cfg.base || 'origin/main', summary: 'from args' }
} else {
  scope = await agent(
    `Determine what this code review should target. Repo root: ${REPO_ROOT}. Use Bash (git, gh).

Decide ONE mode, in this priority order:
1. 'pr'  — if 'gh pr view --json number,baseRefName,headRefName' shows an OPEN PR for the CURRENT branch. Capture prNumber and base (the PR's baseRefName, e.g. origin/main or main).
2. 'uncommitted' — else if 'git status --porcelain' shows tracked changes (the working tree is dirty). base = HEAD.
3. 'branch' — else review committed work on this branch vs its base. base = whichever of 'origin/main' or 'main' exists (prefer origin/main). If the current branch IS main/master with no PR and a clean tree, still pick 'branch' with base = the previous commit's parent (HEAD~1) and note it in summary.

Return the chosen mode, base ref string (usable in 'git diff <base>...HEAD' for pr/branch, or literally 'HEAD' for uncommitted), prNumber if pr, branch name, and a one-line summary of what will be reviewed.`,
    { label: 'scope:detect', phase: 'Scope', schema: SCOPE_SCHEMA },
  )
}

const MODE = scope.mode
const BASE = scope.base || 'origin/main'
const PRNUM = scope.prNumber || cfg.prNumber
log(`Target: ${MODE}${PRNUM ? ' #' + PRNUM : ''} (base=${BASE}) — ${scope.summary}`)

// How each reviewer obtains its slice of the diff, by mode.
function diffSpec(files) {
  const fileArgs = files.map(f => `'${f}'`).join(' ')
  if (MODE === 'uncommitted') {
    return `Review UNCOMMITTED changes only:\n  git -C ${REPO_ROOT} diff HEAD -- ${fileArgs}\n  (also 'git -C ${REPO_ROOT} status --porcelain -- ${fileArgs}' for new untracked files).`
  }
  return `BASE detection (run first):\n  BASE=$(git -C ${REPO_ROOT} merge-base HEAD ${BASE} 2>/dev/null || git -C ${REPO_ROOT} merge-base HEAD main || echo ${BASE})\nThen review the committed diff:\n  git -C ${REPO_ROOT} diff "$BASE"...HEAD -- ${fileArgs}`
}

// ---- Phase 1 setup: discover changed files and group them ------------------
// A reviewer agent reads the changed-file list and partitions it into coherent
// subsystem groups, so the workflow adapts to whatever diff it is pointed at.
const GROUPS_SCHEMA = {
  type: 'object',
  required: ['groups'],
  properties: {
    groups: {
      type: 'array',
      items: {
        type: 'object',
        required: ['name', 'persona', 'files'],
        properties: {
          name: { type: 'string' },
          persona: { type: 'string' },
          files: { type: 'array', items: { type: 'string' } },
        },
      },
    },
  },
}

const listCmd = MODE === 'uncommitted'
  ? `git -C ${REPO_ROOT} diff --name-only HEAD; git -C ${REPO_ROOT} ls-files --others --exclude-standard`
  : `BASE=$(git -C ${REPO_ROOT} merge-base HEAD ${BASE} 2>/dev/null || git -C ${REPO_ROOT} merge-base HEAD main || echo ${BASE}); git -C ${REPO_ROOT} diff --name-only "$BASE"...HEAD`

const partition = await agent(
  `List the changed files for this review and partition them into coherent review groups.

Run:
  ${listCmd}

Then group the changed files into 8–24 subsystem groups so each group is a coherent unit one expert can review well (group by directory / language / feature; keep related scripts together; isolate large/high-risk files into their own group). For each group give: a short kebab 'name', a 'persona' (the kind of expert best suited — e.g. "a defensive Bash engineer", "a Docker layered-build expert", "a senior Python engineer", "a PowerShell automation expert", "a config/JSON correctness reviewer", "a refactor-safety auditor for renamed/removed paths"), and the exact repo-relative 'files' (every changed file must appear in exactly one group). Aim to cover EVERY changed file.`,
  { label: 'scope:partition', phase: 'Scope', schema: GROUPS_SCHEMA },
)

const GROUPS = (partition.groups || []).filter(g => g.files && g.files.length)
if (!GROUPS.length) {
  log('No changed files found — nothing to review.')
  return { mode: MODE, base: BASE, confirmedCount: 0, confirmed: [] }
}
log(`Swarm: ${GROUPS.length} expert reviewers over ${GROUPS.reduce((n, g) => n + g.files.length, 0)} changed files`)

// ---- shared reviewer guidance ----------------------------------------------
const SHARED_RULES = `
You are reviewing a real change. Work from the actual diff and full file context — do NOT speculate.

SCOPE: Report only problems introduced or touched by THIS diff. Ignore pre-existing issues in unchanged lines.

LOOK FOR (weight by real impact):
- Correctness / logic bugs, wrong conditionals, off-by-one, bad expansion, unset-var use.
- Shell robustness: unquoted expansions, word-splitting, missing 'set -euo pipefail' where it matters, ignored exit codes, fragile parsing, non-portable bashisms in /bin/sh, eval misuse, unguarded cd, unsafe rm globs.
- Security: command injection, curl|bash of untrusted input, secret/token leakage, unsafe temp files, world-readable creds, permissions.
- Cross-platform / cross-shell parity (bash vs zsh vs PowerShell; macOS vs Linux: sed -i, mktemp, readlink).
- Dockerfile: cache busting, missing cleanup/--no-install-recommends, root vs user, version pinning where it matters, COPY/chmod correctness.
- Config/JSON/YAML: invalid syntax, wrong keys, broken references to renamed/removed paths.
- Dead code, broken cross-file refs, renames the diff didn't propagate everywhere.

PRECISION (critical for the next stage):
- "file" MUST be the repo-relative path exactly as in the diff.
- "line" MUST be a line number in the NEW (post-change) file — a line on the RIGHT side of the diff (an added '+' line, or a context line inside a changed hunk). Read the file to get the exact number. Prefer an added '+' line.
- "body" is GitHub-Markdown: state the concrete problem, why it matters, and a specific fix (a short \`\`\`suggestion\`\`\` block is ideal).
- Quality over quantity. Skip pure style nits with no functional impact. A finding you are not fairly confident is real does more harm than good downstream.

Return findings via the structured tool. An empty list is a valid answer.`

function reviewerPrompt(u) {
  const known = (u.known && u.known.length)
    ? `\nALREADY-REPORTED in this area by earlier reviewers — do NOT repeat these. Find DIFFERENT, deeper, or adjacent problems the others missed:\n${u.known.map(k => `  - ${k.file}:${k.line} — ${k.title}`).join('\n')}\n`
    : ''
  const deep = u.depth
    ? 'This is a DEEP pass: read each touched file in full, trace control/data flow into the sibling files it sources or calls (and that call it), and reason about non-obvious failure modes, edge cases, and cross-file interactions — not just surface-level bugs.\n'
    : ''
  return `You are ${u.persona}. Repo root: ${REPO_ROOT}.
Review lens for this pass: ${u.lensDesc}

Review these changed files:
${u.files.map(f => '  - ' + f).join('\n')}

${diffSpec(u.files)}

Use Bash (git diff / grep) and Read freely to get the diff and full surrounding context before judging.
${deep}${known}${SHARED_RULES}`
}

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'line', 'severity', 'category', 'title', 'body', 'confidence'],
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          category: { type: 'string' },
          title: { type: 'string' },
          body: { type: 'string' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['keep', 'reason'],
  properties: {
    keep: { type: 'boolean' },
    reason: { type: 'string' },
    adjustedLine: { type: 'integer' },
    adjustedSeverity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
    refinedBody: { type: 'string' },
    inDiff: { type: 'boolean' },
  },
}

function verifyPrompt(f) {
  return `You are an independent, skeptical senior reviewer. A prior reviewer raised the finding below. REFUTE it unless it clearly holds up. Default keep=false when uncertain, when it is style-only, or when it concerns unchanged/pre-existing code.

Repo root: ${REPO_ROOT}
Finding file: ${f.file}
Claimed NEW-file line: ${f.line}
Severity: ${f.severity} | Category: ${f.category}
Title: ${f.title}
Body:
${f.body}

Steps:
1. ${diffSpec([f.file]).split('\n').join('\n   ')}
   Confirm the cited line is part of this diff (an added '+' line or context line inside a changed hunk). Set inDiff. If the issue is real but the line is slightly off, put the correct NEW-file line (one that IS in the diff) in adjustedLine.
2. Read surrounding code to confirm the problem is REAL with practical impact, not a misreading.
3. Decide keep (true only if real, impactful, tied to changed lines). One-sentence reason. Optionally set adjustedSeverity and improve refinedBody (GitHub-Markdown).

Return via the structured tool.`
}

// ---- Multi-pass swarm — wider lenses + finer granularity + deeper digging each pass
// Each pass adds more expert lenses, splits the diff into finer units, and tells
// every reviewer what earlier passes already found so it hunts for NEW, deeper issues.
const PASSES = Math.max(1, cfg.passes || 3)
const MAX_UNITS = cfg.maxReviewersPerPass || 120   // per-pass reviewer cap (cost guard)

const LENS_SETS = [
  // Pass 1 — broad sweep, one generalist per subsystem
  [{ key: 'core', desc: 'overall correctness, logic bugs, and the highest-impact robustness problems' }],
  // Pass 2 — specialist quartet, applied per subsystem
  [
    { key: 'security', desc: 'security: command/regex injection, secret & token handling, file permissions, unsafe temp files, curl|bash of untrusted input' },
    { key: 'robustness', desc: 'shell robustness & portability: quoting/word-splitting, set -euo pipefail interactions, ignored exit codes, GNU-vs-BSD/macOS, bash-vs-zsh-vs-POSIX' },
    { key: 'consistency', desc: 'cross-file consistency: renamed/removed paths, parser parity between sibling scripts, docs/READMEs that contradict behavior, broken references' },
    { key: 'control-flow', desc: 'control-flow & tool/API semantics: wrong conditionals, early/no-op exits, broken orchestration, misused CLIs/builtins, idempotency on re-run' },
  ],
  // Pass 3+ — full battery, per-file granularity, deep flow tracing
  [
    { key: 'concurrency', desc: 'concurrency, races, locking, and idempotency under parallel or repeated invocation' },
    { key: 'error-handling', desc: 'error handling & failure modes: partial failures, missing guards, silent skips, cleanup/trap correctness' },
    { key: 'edge-cases', desc: 'edge cases & input validation: empty/whitespace/unicode/missing inputs, unusual paths, boundary conditions' },
    { key: 'perf-resource', desc: 'performance & resource use: redundant work, repeated network/subprocess calls, unbounded loops, leaks' },
    { key: 'docs-ux', desc: 'documentation/UX accuracy: help text, READMEs, comments, and error messages vs actual behavior' },
  ],
]

function chunk(arr, size) { const out = []; for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size)); return out }
const sevRank = { critical: 0, high: 1, medium: 2, low: 3 }

const confirmedAll = []
const seenByFile = {}
function titleKey(t) { return (t || '').toLowerCase().replace(/[^a-z0-9 ]/g, '').split(/\s+/).filter(Boolean).slice(0, 6).join(' ') }
// Dup only if same file AND within ±3 lines AND (identical line OR similar title).
// Different-angle findings (e.g. a security vs a perf issue) on nearby lines survive.
function isNew(f) {
  const tk = titleKey(f.title)
  for (const e of (seenByFile[f.file] || [])) {
    if (Math.abs(e.line - f.line) <= 3 && (e.line === f.line || e.tkey === tk)) return false
  }
  return true
}
function remember(f) { (seenByFile[f.file] = seenByFile[f.file] || []).push({ line: f.line, tkey: titleKey(f.title) }) }
function knownFor(files) { const s = new Set(files); return confirmedAll.filter(f => s.has(f.file)).map(f => ({ file: f.file, line: f.line, title: f.title })) }
function normalize(x) {
  return {
    file: x.file,
    line: (Number.isInteger(x.verdict.adjustedLine) ? x.verdict.adjustedLine : x.line),
    severity: x.verdict.adjustedSeverity || x.severity,
    category: x.category, title: x.title,
    body: x.verdict.refinedBody || x.body,
    confidence: x.confidence, group: x.group,
    inDiff: x.verdict.inDiff !== false, verifyReason: x.verdict.reason,
  }
}

let rawTotal = 0
for (let p = 1; p <= PASSES; p++) {
  // widen across passes: each pass applies a DISTINCT tier of lenses (it does NOT
  // re-run earlier tiers — re-running 'core' every pass just rediscovers pass-1
  // findings and wastes the budget). Reviewers still get earlier findings as context.
  const tier = Math.min(p - 1, LENS_SETS.length - 1)
  const lenses = LENS_SETS[tier]
  // deepen: finer file chunks + full-file deep reads on later passes
  const chunkSize = p <= 1 ? 999 : (p === 2 ? 3 : 2)
  const deep = p >= 3

  // Build per-lens unit lists, then interleave round-robin so that if the per-pass
  // cap trims, it trims EVENLY across lenses and subsystems (never starves a lens).
  const perLens = lenses.map(lens => {
    const arr = []
    for (const g of GROUPS) for (const fc of chunk(g.files, chunkSize)) {
      arr.push({
        name: `${g.name}/${lens.key}`,
        persona: lens.key === 'core' ? g.persona : `${g.persona}, reviewing specifically through a ${lens.key} lens`,
        lensDesc: lens.desc, files: fc, depth: deep, known: knownFor(fc),
      })
    }
    return arr
  })
  const totalUnits = perLens.reduce((n, a) => n + a.length, 0)
  let units = []
  for (let i = 0; units.length < totalUnits; i++) {
    for (const arr of perLens) if (i < arr.length) units.push(arr[i])
  }
  if (units.length > MAX_UNITS) { log(`Pass ${p}: ${totalUnits} reviewer units → capped to ${MAX_UNITS} (interleaved across lenses; raise args.maxReviewersPerPass for fuller coverage)`); units = units.slice(0, MAX_UNITS) }

  phase(`Pass ${p} · Review`)
  log(`Pass ${p}/${PASSES}: ${units.length} expert reviewers — lenses [${lenses.map(l => l.key).join(', ')}], chunk=${chunkSize}${deep ? ', deep' : ''}`)

  const reviewed = await pipeline(
    units,
    u => agent(reviewerPrompt(u), { label: `p${p}:${u.name}`, phase: `Pass ${p} · Review`, schema: FINDINGS_SCHEMA })
          .then(r => ({ u, findings: (r && r.findings) || [] }))
          .catch(() => ({ u, findings: [] })),
    (res) => parallel((res.findings).map(f => () =>
      agent(verifyPrompt(f), { label: `p${p}:verify:${(f.file || '').split('/').pop()}:${f.line}`, phase: `Pass ${p} · Verify`, schema: VERDICT_SCHEMA })
        .then(v => ({ ...f, group: res.u.name, verdict: v }))
        .catch(() => null)
    )),
  )

  const passRaw = reviewed.flat().filter(Boolean)
  rawTotal += passRaw.length
  const passConfirmed = passRaw.filter(x => x.verdict && x.verdict.keep).map(normalize)
  let added = 0
  for (const f of passConfirmed) { if (isNew(f)) { confirmedAll.push(f); remember(f); added++ } }
  log(`Pass ${p}: +${added} net-new confirmed (running total ${confirmedAll.length})`)

  if (budget.total && budget.remaining() < 80000) { log(`Budget low (${Math.round(budget.remaining() / 1000)}k left) — stopping after pass ${p}.`); break }
}

confirmedAll.sort((a, b) => (sevRank[a.severity] - sevRank[b.severity]) || a.file.localeCompare(b.file) || a.line - b.line)
const counts = confirmedAll.reduce((m, f) => (m[f.severity] = (m[f.severity] || 0) + 1, m), {})
log(`Total confirmed (deduped) across passes: ${confirmedAll.length} from ${rawTotal} raw — ${JSON.stringify(counts)}`)

// ---- Phase 3: auto-post ONE consolidated GitHub review (PR mode) -----------
// In PR mode the workflow ALWAYS posts every confirmed finding (unless post=false).
// The posting agent follows an exact, deterministic procedure so it is reliable
// unattended: it parses the diff with the embedded python script (no guessing
// about which lines are commentable) and submits one COMMENT review.
let posted = { attempted: false }
if (POST && MODE === 'pr' && PRNUM && confirmedAll.length) {
  phase('Post')
  const payload = JSON.stringify({ prNumber: PRNUM, counts, dedupe: DEDUPE, findings: confirmedAll })
  const postResult = await agent(
    `Publish the verified findings below as ONE consolidated GitHub pull-request review on PR #${PRNUM}, with each finding as an inline comment. Repo root: ${REPO_ROOT}. This DOES publish to GitHub — that is the intended behavior, post everything that maps. Use Bash (gh, git, python3).

FINDINGS JSON (write it to a temp file, e.g. /tmp/swarm_findings.json):
${payload}

Run EXACTLY this procedure (do not improvise the diff parsing):

STEP 1 — fetch the diff and owner/repo:
  gh pr diff ${PRNUM} > /tmp/pr_${PRNUM}.diff
  OWNER_REPO=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')

STEP 2 — run this python3 script verbatim (it parses commentable RIGHT-side lines, snaps each finding to a valid line within ±3, optionally dedupes against existing PR comments, and writes the review payload):

  cat > /tmp/build_review.py <<'PY'
  import json, re, subprocess, sys
  PR = "${PRNUM}"
  data = json.load(open('/tmp/swarm_findings.json'))
  findings = data['findings']; counts = data['counts']; dedupe = data.get('dedupe', False)
  # 1. valid RIGHT-side (new-file) line numbers per path
  valid = {}; cur=None; new_ln=None
  for line in open('/tmp/pr_%s.diff' % PR):
      if line.startswith('diff --git '): cur=None; new_ln=None; continue
      if line.startswith('+++ '):
          p=line[4:].strip(); cur=None if p=='/dev/null' else (p[2:] if p.startswith('b/') else p)
          if cur: valid.setdefault(cur,set())
          continue
      if line.startswith('@@'):
          m=re.search(r'\\+(\\d+)(?:,(\\d+))?',line); new_ln=int(m.group(1)) if m else None; continue
      if cur is None or new_ln is None: continue
      if line.startswith('+') and not line.startswith('+++'): valid[cur].add(new_ln); new_ln+=1
      elif line.startswith('-') and not line.startswith('---'): pass
      elif line.startswith('\\\\'): pass
      else: valid[cur].add(new_ln); new_ln+=1
  # 2. optional dedupe vs existing PR comments (existing comments file passed via EXISTING_JSON env)
  import os
  posted={}
  if dedupe and os.environ.get('EXISTING_JSON'):
      for c in json.load(open(os.environ['EXISTING_JSON'])):
          ln=c.get('line') or c.get('original_line')
          if c.get('path') and ln: posted.setdefault(c['path'],[]).append(ln)
  # 3. map findings
  comments=[]; unmapped=[]
  for f in findings:
      if dedupe and any(abs(l-f['line'])<=6 for l in posted.get(f['file'],[])):
          continue
      vs=valid.get(f['file']); ln=f['line']; chosen=None
      if vs:
          if ln in vs: chosen=ln
          else:
              cands=[l for l in vs if abs(l-ln)<=3]
              if cands: chosen=min(cands,key=lambda l:(abs(l-ln),l))
      if chosen is not None:
          comments.append({"path":f['file'],"line":chosen,"side":"RIGHT","body":"**[%s]** %s"%(f['severity'],f['body'])})
      else:
          unmapped.append(f)
  # 4. summary body
  hi=[f for f in findings if f['severity']=='high' or f['severity']=='critical']
  lines=["## 🤖 AI Swarm Code Review",""]
  lines.append("Deep multi-agent review: expert subagents partitioned the diff by subsystem; every finding was adversarially verified by an independent skeptic before posting.")
  lines.append("")
  lines.append("**Confirmed findings: %d** — %s. %d posted as inline comments below." % (len(findings), json.dumps(counts), len(comments)))
  if hi:
      lines.append(""); lines.append("Highlights (high severity):")
      for f in hi[:6]: lines.append("- **%s** — %s" % (f['file'].split('/')[-1], f['title']))
  if unmapped:
      lines.append(""); lines.append("Findings that could not be mapped to a diff line (shown here instead):")
      for f in unmapped: lines.append("- **[%s] %s:%s** — %s" % (f['severity'], f['file'], f['line'], f['title']))
  lines.append(""); lines.append("_Advisory; severities are the swarm's estimate. Generated with Claude Code._")
  payload={"event":"COMMENT","body":"\\n".join(lines),"comments":comments}
  json.dump(payload, open('/tmp/review_payload.json','w'))
  print("MAPPED",len(comments),"UNMAPPED",len(unmapped))
  PY
  ${DEDUPE ? `gh api --paginate repos/$OWNER_REPO/pulls/${PRNUM}/comments > /tmp/existing_comments.json; EXISTING_JSON=/tmp/existing_comments.json python3 /tmp/build_review.py` : `python3 /tmp/build_review.py`}

STEP 3 — submit ONE review:
  gh api --method POST repos/$OWNER_REPO/pulls/${PRNUM}/reviews --input /tmp/review_payload.json --jq '{id, state, html_url}'

STEP 4 — if the API returns 422 mentioning a specific line/path, remove that one comment from /tmp/review_payload.json (python or jq) and resubmit so the rest still post. Repeat at most 3 times.

STEP 5 — verify and report: count how many comments belong to the new review id and return a concise report: number of inline comments posted, number unmapped, and the review html_url.`,
    { label: 'post:github-review', phase: 'Post' },
  )
  posted = { attempted: true, report: postResult }
  log('Auto-posted GitHub review.')
} else if (POST && MODE === 'pr' && !confirmedAll.length) {
  log('No confirmed findings — nothing to post.')
} else if (!POST && MODE === 'pr') {
  log('post=false — skipping GitHub posting (findings returned in result).')
}

return {
  mode: MODE,
  base: BASE,
  prNumber: PRNUM,
  passes: PASSES,
  rawFindings: rawTotal,
  confirmedCount: confirmedAll.length,
  counts,
  confirmed: confirmedAll,
  posted,
}
