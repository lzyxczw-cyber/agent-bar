/**
 * questions.mjs — shape and answer rules for DSH `user-questions/request`.
 *
 * The waterfall request (verified against DSH 0.2.2-era clients that speak the
 * same `$events/result` channel as approval/request) looks like:
 *
 *   { questions: [{ id, question, header?, detail?, multiSelect?, options?: [{ label, description? }], intent? }] }
 *
 * A successful answer is `$events/result` with:
 *
 *   { kind: 'result', value: { answers: [{ id, selected: [label...], custom? }] } }
 *
 * `selected` carries the option **labels**, not display strings or synthetic ids.
 * Cancel is a rejected outcome, not a fake answer:
 *
 *   { kind: 'rejected', error: { name: 'UserQuestionError', code: 'ASK_CANCELLED', message } }
 *
 * Intents other than absent / `plan-review` / `approval` stay read-only so this
 * bridge does not invent an outcome the official client still owns.
 */

const MAX_QUESTIONS = 8;
const MAX_OPTIONS = 12;
const MAX_TEXT = 2000;
const MAX_LABEL = 200;

export const QUESTION_CANCELLED_OUTCOME = {
  kind: 'rejected',
  error: {
    name: 'UserQuestionError',
    code: 'ASK_CANCELLED',
    message: '用户取消了问答。'
  }
};

function text (value, max) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim ();
  if (trimmed === '') return null;
  return trimmed.slice (0, max);
}

function chinese (value) {
  if (!value || typeof value !== 'object') return null;
  for (const locale of ['zh-CN', 'zh-Hans', 'zh']) {
    const candidate = text (value[locale], MAX_TEXT);
    if (candidate) return candidate;
  }
  return null;
}

/**
 * Normalize one waterfall request into feed questions.
 * `answerable` is false when a shape cannot be answered without guessing.
 */
export function normalizeUserQuestions (request) {
  const raw = request && Array.isArray (request.questions) ? request.questions : [];
  const questions = [];
  let answerable = raw.length > 0 && raw.length <= MAX_QUESTIONS;
  if (raw.length > MAX_QUESTIONS) answerable = false;
  const seen = new Set ();
  for (const item of raw.slice (0, MAX_QUESTIONS)) {
    if (!item || typeof item !== 'object' || Array.isArray (item)) { answerable = false; continue; }
    const id = text (item.id, 120);
    const prompt = text (item.question, MAX_TEXT);
    if (!id || seen.has (id) || !prompt) { answerable = false; continue; }
    seen.add (id);
    const intent = item.intent && typeof item.intent === 'object' && !Array.isArray (item.intent) ? item.intent : null;
    const intentKind = intent && typeof intent.kind === 'string' ? intent.kind : null;
    if (intentKind && intentKind !== 'plan-review' && intentKind !== 'approval') answerable = false;
    if (item.multiSelect != null && typeof item.multiSelect !== 'boolean') answerable = false;
    const multiSelect = item.multiSelect === true;
    if ((intentKind === 'approval' || intentKind === 'plan-review') && multiSelect) answerable = false;
    const allowCustom = intentKind !== 'approval';
    const options = [];
    const labels = new Set ();
    const rawOptions = Array.isArray (item.options) ? item.options : [];
    if (rawOptions.length > MAX_OPTIONS) answerable = false;
    for (const option of rawOptions.slice (0, MAX_OPTIONS)) {
      if (!option || typeof option !== 'object') { answerable = false; continue; }
      const label = text (option.label, MAX_LABEL);
      if (!label || labels.has (label)) { answerable = false; continue; }
      if (option.description != null && typeof option.description !== 'string') answerable = false;
      labels.add (label);
      options.push ({
        label,
        description: text (option.description, 400),
        display: null
      });
    }
    if (intentKind === 'approval') {
      const actions = [intent.approve, intent.reject, ...(intent.always == null ? [] : [intent.always])];
      if (actions.some ((label) => typeof label !== 'string' || !labels.has (label)) || actions.length !== labels.size) {
        answerable = false;
      }
      const display = intent.display && typeof intent.display === 'object' ? intent.display : {};
      const subject = intent.subject && typeof intent.subject === 'object' ? intent.subject : {};
      const shown = new Map ();
      if (typeof intent.approve === 'string') shown.set (intent.approve, chinese (display.approve) || intent.approve);
      if (typeof intent.reject === 'string') shown.set (intent.reject, '拒绝');
      if (typeof intent.always === 'string') shown.set (intent.always, '始终允许');
      for (const option of options) {
        const replacement = shown.get (option.label);
        if (replacement && replacement !== option.label) option.display = replacement;
      }
    }
    if (options.length === 0 && !allowCustom) answerable = false;
    questions.push ({
      id,
      question: prompt,
      header: text (item.header, 80),
      detail: text (item.detail, MAX_TEXT),
      multiSelect,
      allowCustom,
      intent: intentKind,
      options
    });
  }
  if (questions.length === 0) answerable = false;
  return { questions, answerable };
}

/**
 * Build the `value` object for `{ kind: 'result', value }` from a pending
 * question set and a client answer list. Rejects anything that is not a
 * complete answer of the labels DSH already offered.
 */
export function buildQuestionResult (questions, answers) {
  if (!Array.isArray (questions) || questions.length === 0) return { ok: false, reason: 'invalid-questions' };
  if (!Array.isArray (answers)) return { ok: false, reason: 'invalid-answers' };
  if (answers.length !== questions.length) return { ok: false, reason: 'incomplete-answers' };
  const byId = new Map ();
  for (const answer of answers) {
    if (!answer || typeof answer !== 'object' || Array.isArray (answer)) return { ok: false, reason: 'invalid-answers' };
    if (typeof answer.id !== 'string' || byId.has (answer.id)) return { ok: false, reason: 'invalid-answers' };
    byId.set (answer.id, answer);
  }
  const normalized = [];
  for (const question of questions) {
    const answer = byId.get (question.id);
    if (!answer) return { ok: false, reason: 'incomplete-answers' };
    const allowed = new Set ((question.options || []).map ((option) => option.label));
    const selectedRaw = answer.selected == null ? [] : answer.selected;
    if (!Array.isArray (selectedRaw)) return { ok: false, reason: 'invalid-answers' };
    const selected = [];
    const seen = new Set ();
    for (const label of selectedRaw) {
      if (typeof label !== 'string' || !allowed.has (label) || seen.has (label)) return { ok: false, reason: 'unknown-option' };
      seen.add (label);
      selected.push (label);
    }
    // Keep wire order stable: the order of the options DSH sent.
    const ordered = (question.options || []).map ((option) => option.label).filter ((label) => seen.has (label));
    let custom = null;
    if (answer.custom != null) {
      if (typeof answer.custom !== 'string') return { ok: false, reason: 'invalid-answers' };
      const trimmed = answer.custom.trim ();
      if (trimmed !== '') {
        if (trimmed.length > MAX_TEXT) return { ok: false, reason: 'custom-too-long' };
        custom = trimmed;
      }
    }
    if (custom && question.allowCustom !== true) return { ok: false, reason: 'custom-not-allowed' };
    if (!question.multiSelect && (ordered.length > 1 || (ordered.length > 0 && custom))) {
      return { ok: false, reason: 'single-select' };
    }
    if (ordered.length === 0 && !custom) return { ok: false, reason: 'incomplete-answers' };
    const row = { id: question.id, selected: ordered };
    if (custom) row.custom = custom;
    normalized.push (row);
  }
  return { ok: true, value: { answers: normalized } };
}
