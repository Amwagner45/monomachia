// The lanes board's Sessions view: reads a Claude Code transcript (one JSON
// object per line, ~/.claude/projects/<folder>/<session id>.jsonl) into the
// turns the board shows, and finds what the session is waiting on. Pure, no
// I/O: server.mjs reads the files, tests/lanes-board.test.mjs checks this.

const CLIP = 4000;
const clip = (s, n = CLIP) => (s.length > n ? `${s.slice(0, n)}\n… (${s.length - n} more characters)` : s);

// What a tool call does, in one line.
export function toolSummary(name, input = {}) {
  const pick = input.command ?? input.file_path ?? input.notebook_path ?? input.pattern ?? input.url ?? input.query
    ?? input.description ?? input.prompt ?? input.skill ?? input.message;
  if (name === 'AskUserQuestion') return (input.questions ?? []).map((q) => q.question).join(' · ');
  if (name === 'TodoWrite') return `${(input.todos ?? []).length} todos`;
  if (typeof pick === 'string') return pick.split(/\r?\n/)[0].slice(0, 300);
  const first = Object.values(input).find((v) => typeof v === 'string');
  return first ? first.split(/\r?\n/)[0].slice(0, 300) : '';
}

const textOf = (content) => (typeof content === 'string' ? content
  : (content ?? []).map((c) => (c.type === 'text' ? c.text : c.type === 'image' ? '[image]' : '')).filter(Boolean).join('\n'));

// A user turn the app wrote rather than the owner: slash-command echoes and the like.
function userText(raw) {
  const cmd = raw.match(/<command-name>([^<]*)<\/command-name>/);
  if (cmd) return `${cmd[1].trim()} ${raw.match(/<command-args>([^<]*)<\/command-args>/)?.[1] ?? ''}`.trim();
  if (/^\s*<(local-command-stdout|local-command-caveat|system-reminder|task-notification)/.test(raw)) return null;
  return raw.replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, '').trim() || null;
}

// lines: the transcript's lines (the first may be cut off, when only its tail
// was read). Returns the turns, newest last, plus the session's title and folder
// when the transcript names them, and the tool call still waiting on a result.
export function parseTranscript(lines, { limit = 400 } = {}) {
  const entries = [];
  const results = new Map(); // tool_use id -> result entry
  let title = null;
  let cwd = null;
  let firstPrompt = null;
  for (const line of lines) {
    let o;
    try { o = JSON.parse(line); } catch { continue; }
    if (o.type === 'custom-title' && o.customTitle) title = o.customTitle;
    if (o.cwd) cwd = o.cwd;
    if (o.isSidechain || o.isMeta) continue;
    const time = o.timestamp ? Date.parse(o.timestamp) : null;
    if (o.type === 'user' && o.message) {
      const c = o.message.content;
      if (Array.isArray(c) && c.some((x) => x.type === 'tool_result')) {
        for (const r of c.filter((x) => x.type === 'tool_result')) {
          const e = { kind: 'result', time, tool: r.tool_use_id, error: !!r.is_error, text: clip(textOf(r.content)) };
          results.set(r.tool_use_id, e);
          entries.push(e);
        }
        continue;
      }
      const text = userText(textOf(c));
      if (text) { entries.push({ kind: 'user', time, text: clip(text) }); firstPrompt ??= text; }
    } else if (o.type === 'assistant' && o.message) {
      for (const c of o.message.content ?? []) {
        if (c.type === 'text' && c.text.trim()) entries.push({ kind: 'assistant', time, text: clip(c.text, 20000) });
        else if (c.type === 'tool_use') {
          entries.push({ kind: 'tool', time, id: c.id, name: c.name, summary: toolSummary(c.name, c.input),
            input: c.name === 'AskUserQuestion' ? c.input : clip(JSON.stringify(c.input, null, 2), 3000) });
        }
      }
    } else if (o.type === 'system' && o.stopReason) {
      entries.push({ kind: 'system', time, text: clip(String(o.stopReason), 1000) });
    }
  }
  // The newest tool call with no result yet: running, or waiting on a dialog.
  const open = [...entries].reverse().find((e) => e.kind === 'tool' && !results.has(e.id)) ?? null;
  const shown = entries.slice(-limit);
  return {
    entries: shown,
    more: entries.length - shown.length,
    title: title ?? (firstPrompt ? firstPrompt.split(/\r?\n/)[0].slice(0, 80) : null),
    cwd,
    open: open && { id: open.id, name: open.name, summary: open.summary, time: open.time,
      questions: open.name === 'AskUserQuestion' ? open.input.questions ?? [] : null },
  };
}

// ---------- the relay (relay-hook.mjs on the session's side) ----------

export const SESSION_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export const PENDING_ID = /^[a-z0-9]{4,16}-[a-z0-9]{4,16}$/;

// AskUserQuestion's answers, as the tool takes them: question text -> the
// chosen label, several labels joined with ", ".
export function questionAnswers(questions, picks) {
  const answers = {};
  questions.forEach((q, i) => {
    const p = picks?.[i];
    const labels = (Array.isArray(p) ? p : p == null ? [] : [p]).map((s) => String(s).trim()).filter(Boolean);
    if (!labels.length) throw new Error(`No answer for "${q.question}"`);
    if (!q.multiSelect && labels.length > 1) throw new Error(`"${q.question}" takes one answer`);
    answers[q.question] = labels.join(', ');
  });
  return answers;
}

// The board's answer to a pending item, checked, in the shape the hook reads.
export function relayAnswer(pending, body) {
  if (pending.kind === 'stop') {
    const text = String(body.reply ?? '').trim();
    if (body.release) return { release: true };
    if (!text) throw new Error('Type a reply first');
    return { reply: text.slice(0, 20000) };
  }
  if (body.release) return { release: true };
  if (pending.kind === 'question') {
    const questions = pending.input?.questions ?? [];
    return { behavior: 'allow', updatedInput: { ...pending.input, answers: questionAnswers(questions, body.picks) } };
  }
  if (body.behavior === 'allow') {
    const out = { behavior: 'allow' };
    if (body.always && Array.isArray(pending.suggestions) && pending.suggestions.length) out.updatedPermissions = pending.suggestions;
    return out;
  }
  if (body.behavior === 'deny') {
    const why = String(body.message ?? '').trim();
    return { behavior: 'deny', message: why ? `The owner declined from the lanes board: ${why.slice(0, 4000)}` : 'The owner declined this from the lanes board.' };
  }
  throw new Error('Allow or deny?');
}
