import test from 'node:test';
import assert from 'node:assert/strict';
import { buildQuestionResult, normalizeUserQuestions, QUESTION_CANCELLED_OUTCOME } from '../bridge/lib/questions.mjs';
import { classifyDshProbe } from '../bridge/lib/protocol.mjs';
import { canonicalExternalStatus } from '../bridge/lib/status.mjs';

test('plain single-select question is answerable and answers with the option label', () => {
  const normalized = normalizeUserQuestions ({
    questions: [{
      id: 'q1',
      question: '放在哪里？',
      header: '位置',
      options: [
        { label: '刘海', description: '菜单栏' },
        { label: 'Dock' }
      ]
    }]
  });
  assert.equal (normalized.answerable, true);
  assert.equal (normalized.questions[0].allowCustom, true);
  assert.equal (normalized.questions[0].options[0].label, '刘海');
  const built = buildQuestionResult (normalized.questions, [{ id: 'q1', selected: ['刘海'] }]);
  assert.equal (built.ok, true);
  assert.deepEqual (built.value, { answers: [{ id: 'q1', selected: ['刘海'] }] });
});

test('custom text is allowed only when the question is not an approval intent', () => {
  const plain = normalizeUserQuestions ({
    questions: [{ id: 'q1', question: '还有别的吗？', options: [{ label: '没有' }] }]
  });
  const custom = buildQuestionResult (plain.questions, [{ id: 'q1', selected: [], custom: ' 放在面板里 ' }]);
  assert.equal (custom.ok, true);
  assert.deepEqual (custom.value.answers[0], { id: 'q1', selected: [], custom: '放在面板里' });

  const approval = normalizeUserQuestions ({
    questions: [{
      id: 'perm',
      question: 'Allow Computer Use?',
      multiSelect: false,
      options: [{ label: 'Allow' }, { label: 'Deny' }],
      intent: { kind: 'approval', approve: 'Allow', reject: 'Deny', display: { approve: { 'zh-CN': '允许' } } }
    }]
  });
  assert.equal (approval.answerable, true);
  assert.equal (approval.questions[0].allowCustom, false);
  assert.equal (approval.questions[0].options[0].display, '允许');
  assert.equal (approval.questions[0].options[1].display, '拒绝');
  const rejected = buildQuestionResult (approval.questions, [{ id: 'perm', selected: [], custom: 'nope' }]);
  assert.equal (rejected.ok, false);
  assert.equal (rejected.reason, 'custom-not-allowed');
  const allowed = buildQuestionResult (approval.questions, [{ id: 'perm', selected: ['Allow'] }]);
  assert.equal (allowed.ok, true);
  assert.deepEqual (allowed.value.answers[0].selected, ['Allow']);
});

test('unknown intent, duplicate labels, and incomplete groups stay unanswered', () => {
  const unknown = normalizeUserQuestions ({
    questions: [{ id: 'q', question: '?', options: [{ label: 'A' }], intent: { kind: 'future-widget' } }]
  });
  assert.equal (unknown.answerable, false);

  const dup = normalizeUserQuestions ({
    questions: [{ id: 'q', question: '?', options: [{ label: 'A' }, { label: 'A' }] }]
  });
  assert.equal (dup.answerable, false);

  const group = normalizeUserQuestions ({
    questions: [
      { id: 'a', question: '一', options: [{ label: '是' }] },
      { id: 'b', question: '二', multiSelect: true, options: [{ label: '左' }, { label: '右' }] }
    ]
  });
  assert.equal (group.answerable, true);
  const missing = buildQuestionResult (group.questions, [{ id: 'a', selected: ['是'] }]);
  assert.equal (missing.reason, 'incomplete-answers');
  const both = buildQuestionResult (group.questions, [
    { id: 'b', selected: ['右', '左'] },
    { id: 'a', selected: ['是'] }
  ]);
  assert.equal (both.ok, true);
  assert.deepEqual (both.value.answers[1].selected, ['左', '右']);
  const conflict = buildQuestionResult (group.questions, [
    { id: 'a', selected: ['是'], custom: '其他' },
    { id: 'b', selected: ['左'] }
  ]);
  assert.equal (conflict.reason, 'single-select');
});

test('custom text over 2000 characters and an unknown label are rejected', () => {
  const plain = normalizeUserQuestions ({
    questions: [{ id: 'q1', question: '?', multiSelect: true, options: [{ label: 'A' }, { label: 'B' }] }]
  });
  assert.equal (buildQuestionResult (plain.questions, [{ id: 'q1', selected: [], custom: 'x'.repeat (2001) }]).reason, 'custom-too-long');
  assert.equal (buildQuestionResult (plain.questions, [{ id: 'q1', selected: ['C'] }]).reason, 'unknown-option');
  assert.equal (buildQuestionResult (plain.questions, [{ id: 'q1', selected: ['B', 'A'] }]).value.answers[0].selected.join (','), 'A,B');
});

test('cancel outcome is the DSH UserQuestionError, not a selected label', () => {
  assert.equal (QUESTION_CANCELLED_OUTCOME.kind, 'rejected');
  assert.equal (QUESTION_CANCELLED_OUTCOME.error.code, 'ASK_CANCELLED');
  assert.equal (QUESTION_CANCELLED_OUTCOME.error.name, 'UserQuestionError');
});

test('external status keeps a finished round apart from idle', () => {
  assert.equal (canonicalExternalStatus ('idle'), 'idle');
  assert.equal (canonicalExternalStatus (' IDLE '), 'idle');
  assert.equal (canonicalExternalStatus (null), 'idle');
  assert.equal (canonicalExternalStatus (''), 'idle');
  assert.equal (canonicalExternalStatus ('unknown'), 'idle');
  assert.equal (canonicalExternalStatus ('completed'), 'idle');
  assert.equal (canonicalExternalStatus ('done'), 'done');
  assert.equal (canonicalExternalStatus ('DONE'), 'done');
  assert.equal (canonicalExternalStatus ('running'), 'running');
  assert.equal (canonicalExternalStatus ('waiting'), 'waiting');
  assert.equal (canonicalExternalStatus ('approval'), 'waiting');
  assert.equal (canonicalExternalStatus ('failed'), 'failed');
});

test('session/list probe distinguishes unavailable, mismatch, and ok', () => {
  assert.deepEqual (classifyDshProbe ({ discovered: false }), { protocol: 'unavailable', mismatch: false, error: null });
  assert.equal (classifyDshProbe ({
    discovered: true,
    error: { code: 'gateway/protocol', message: 'non-JSON' }
  }).protocol, 'mismatch');
  assert.equal (classifyDshProbe ({
    discovered: true,
    error: { code: 'auth/unauthorized', message: '401' }
  }).mismatch, true);
  assert.equal (classifyDshProbe ({
    discovered: true,
    error: { code: 'gateway/not-found', message: '404 session/list' }
  }).protocol, 'mismatch');
  assert.equal (classifyDshProbe ({
    discovered: true,
    error: { code: 'client/network', message: 'reset' }
  }).protocol, 'unavailable');
  assert.equal (classifyDshProbe ({ discovered: true, value: { items: [] } }).protocol, 'ok');
  assert.equal (classifyDshProbe ({ discovered: true, value: { sessions: [] } }).mismatch, true);
  assert.equal (classifyDshProbe ({ discovered: true, value: null }).protocol, 'mismatch');
});
