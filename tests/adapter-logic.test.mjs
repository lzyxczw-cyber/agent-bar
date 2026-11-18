import test from 'node:test';
import assert from 'node:assert/strict';
import {
  aggregateApp,
  codexStandbyStatus,
  grokActivityStatus,
  hermesIdleReport,
  hermesIdleStatus,
  hermesMessageSelect,
  hermesSessionSelect,
  hermesTimestampMs,
  inferHermesRunning,
  latestHermesMessages,
  normalizeHermesSession,
  standbyParentStatus,
  workbuddyStandbyStatus
} from '../tools/lib/adapter-logic.mjs';
import { applyUsageTick, usageTotal } from '../bridge/lib/usage.mjs';

function localTime(year, month, day, hour = 12) {
  return new Date(year, month - 1, day, hour, 0, 0, 0).getTime();
}

const NOW = localTime(2026, 11, 17);

test('usage total ignores missing fields and non-objects', () => {
  assert.equal(usageTotal(null), 0);
  assert.equal(usageTotal({ uncachedInputTokens: 3, outputTokens: 4 }), 7);
  assert.equal(usageTotal({ outputTokens: '2' }), 2);
});

test('first sighting does not count the existing session total', () => {
  const first = applyUsageTick(null, [
    { id: 's1', tokenUsage: { uncachedInputTokens: 1000, outputTokens: 50 }, updatedAt: NOW }
  ], new Date(NOW));
  assert.equal(first.state.tokensToday, 0);
  assert.equal(first.state.bySession.s1, undefined);
  assert.equal(first.state.sessions.s1, 1050);
  assert.equal(first.dirty, true);
  assert.equal(first.sessionsToday, 1);

  const second = applyUsageTick(first.state, [
    { id: 's1', tokenUsage: { uncachedInputTokens: 1100, outputTokens: 80 }, updatedAt: NOW + 1000 }
  ], new Date(NOW + 1000));
  assert.equal(second.gained, 130);
  assert.equal(second.state.tokensToday, 130);
  assert.equal(second.state.bySession.s1, 130);
  assert.equal(second.state.sessions.s1, 1180);
});

test('negative or flat totals do not decrease today, and a dropped session loses its baseline', () => {
  const seeded = applyUsageTick({
    day: '2026-11-17',
    sessions: { s1: 100, s2: 40 },
    bySession: { s1: 10 },
    tokensToday: 10,
    history: [],
    since: NOW - 1000
  }, [
    { id: 's1', tokenUsage: { outputTokens: 90 }, updatedAt: NOW }
  ], new Date(NOW));
  assert.equal(seeded.state.tokensToday, 10);
  assert.equal(seeded.state.sessions.s1, 90);
  assert.equal(seeded.state.sessions.s2, undefined);

  const again = applyUsageTick(seeded.state, [
    { id: 's1', tokenUsage: { outputTokens: 95 }, updatedAt: NOW },
    { id: 's2', tokenUsage: { outputTokens: 40 }, updatedAt: NOW }
  ], new Date(NOW));
  assert.equal(again.gained, 5);
  assert.equal(again.state.bySession.s2, undefined);
  assert.equal(again.state.sessions.s2, 40);
  assert.equal(again.state.tokensToday, 15);
});

test('midnight rolls a non-zero day into history and starts from zero', () => {
  const history = [];
  for (let index = 0; index < 14; index++) history.push({ day: '2026-10-' + String(index + 1).padStart(2, '0'), tokens: index + 1 });
  const rolled = applyUsageTick({
    day: '2026-11-16',
    sessions: { s1: 10 },
    bySession: { s1: 10 },
    tokensToday: 80,
    history,
    since: localTime(2026, 11, 16)
  }, [
    { id: 's1', tokenUsage: { outputTokens: 10 }, updatedAt: NOW }
  ], new Date(NOW));
  assert.equal(rolled.state.day, '2026-11-17');
  assert.equal(rolled.state.tokensToday, 0);
  assert.equal(rolled.state.sessions.s1, 10);
  assert.equal(rolled.state.history.length, 14);
  assert.equal(rolled.state.history[13].day, '2026-11-16');
  assert.equal(rolled.state.history[13].tokens, 80);
  assert.equal(rolled.state.history[0].day, '2026-10-02');

  const empty = applyUsageTick({
    day: '2026-11-16',
    sessions: {},
    bySession: {},
    tokensToday: 0,
    history: [],
    since: NOW
  }, [], new Date(NOW));
  assert.deepEqual(empty.state.history, []);
});

test('a session updated yesterday is not counted as today', () => {
  const tick = applyUsageTick(null, [
    { id: 'old', tokenUsage: { outputTokens: 5 }, updatedAt: localTime(2026, 11, 16, 23) }
  ], new Date(NOW));
  assert.equal(tick.sessionsToday, 0);
});

test('hermes timestamps accept seconds or milliseconds, and the select lists stay on a whitelist', () => {
  assert.equal(hermesTimestampMs(1_700_000_000), 1_700_000_000_000);
  assert.equal(hermesTimestampMs(1_700_000_000_000), 1_700_000_000_000);
  assert.equal(hermesTimestampMs(0), null);
  assert.equal(hermesTimestampMs('nope'), null);
  assert.equal(
    hermesSessionSelect(['id', 'started_at', 'ended_at', 'title', 'id;drop']),
    'SELECT id, title, started_at, ended_at FROM sessions WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 12'
  );
  assert.equal(hermesSessionSelect(['id', 'title']), null);
  assert.equal(
    hermesMessageSelect(['session_id', 'timestamp', 'role', 'role;drop'], ['abc', "bad'id"]),
    "SELECT session_id, role, timestamp FROM messages WHERE session_id IN ('abc') ORDER BY timestamp DESC LIMIT 80"
  );
  assert.equal(hermesMessageSelect(['session_id', 'timestamp'], []), null);
});

test('hermes running sessions are inferred, capped, and skip ended or stale rows', () => {
  const sessions = [
    normalizeHermesSession({ id: 'sess-new', title: 'Newer', cwd: '/tmp/project', started_at: (NOW - 5000) / 1000, ended_at: null }),
    normalizeHermesSession({ id: 'sess-old', title: 'Stale', started_at: (NOW - 60_000) / 1000, ended_at: null }),
    normalizeHermesSession({ id: 'sess-ended', title: 'Done', started_at: (NOW - 1000) / 1000, ended_at: NOW / 1000 }),
    normalizeHermesSession({ id: 'sess-mid', title: '', cwd: '/work/repo', started_at: (NOW - 20_000) / 1000, ended_at: null }),
    normalizeHermesSession({ id: 'sess-third', title: 'Third', started_at: (NOW - 30_000) / 1000, ended_at: null }),
    normalizeHermesSession({ id: 'sess-fourth', title: 'Fourth', started_at: (NOW - 40_000) / 1000, ended_at: null })
  ];
  const messages = latestHermesMessages([
    { session_id: 'sess-new', role: 'assistant', timestamp: (NOW - 1000) / 1000, reasoning: '  checking the build  ', content: 'ignored' },
    { session_id: 'sess-new', role: 'user', timestamp: (NOW - 5000) / 1000, content: 'older' },
    { session_id: 'sess-old', role: 'tool', tool_name: 'Bash', timestamp: (NOW - 120_000) / 1000, content: 'too old' },
    { session_id: 'sess-mid', role: 'tool', tool_name: 'Read', timestamp: NOW - 2000, content: 'file' },
    { session_id: 'sess-third', role: 'assistant', timestamp: NOW - 3000, content: 'third' },
    { session_id: 'sess-fourth', role: 'assistant', timestamp: NOW - 4000, content: 'fourth' },
    { session_id: 'sess-ended', role: 'assistant', timestamp: NOW - 500, content: 'ended' }
  ]);
  const running = inferHermesRunning(sessions, messages, NOW, 3);
  assert.deepEqual(running.map((report) => report.id), ['hermes-sess-new', 'hermes-sess-mid', 'hermes-sess-thi']);
  assert.equal(running[0].thought, 'checking the build');
  assert.equal(running[0].project, 'project');
  assert.equal(running[1].tool, 'Read');
  assert.equal(running[1].project, 'repo');
  assert.equal(running.length, 3);

  const idle = hermesIdleReport(sessions, NOW);
  assert.equal(idle.id, 'hermes');
  assert.equal(idle.status, 'idle');
  assert.equal(idle.tool, '空闲');

  const quiet = { 'sess-old': { at: NOW - 2 * 60 * 1000 } };
  assert.equal(hermesIdleReport(sessions, NOW, quiet).status, 'done');
  assert.equal(hermesIdleReport(sessions, NOW, { 'sess-old': { at: NOW - 10 * 60 * 1000 } }).status, 'idle');
  assert.equal(hermesIdleStatus(NOW - 30 * 1000, NOW), 'running');
  assert.equal(hermesIdleStatus(null, NOW), 'idle');
});

test('aggregateApp keeps one parent and at most three child sessions', () => {
  const adapter = { group: 'hermes', name: 'Hermes', bundleID: null };
  const reports = [1, 2, 3, 4].map((index) => ({
    id: 'hermes-s' + index,
    status: 'running',
    project: 'p' + index,
    tool: 'tool' + index,
    startedAt: index * 1000,
    thought: 't' + index,
    tokens: index
  }));
  const parent = aggregateApp(adapter, reports);
  assert.equal(parent.id, 'hermes');
  assert.equal(parent.status, 'running');
  assert.equal(parent.sessions.length, 3);
  assert.deepEqual(parent.sessions.map((session) => session.id), ['hermes-s4', 'hermes-s3', 'hermes-s2']);
  assert.equal(parent.tokens, 10);
  assert.equal(parent.appBundleID, null);

  const idle = aggregateApp(adapter, [{ id: 'hermes', status: 'idle', project: 'Hermes', tool: '空闲', startedAt: 5 }]);
  assert.equal(idle.status, 'idle');
  assert.deepEqual(idle.sessions, []);
  const finished = aggregateApp(adapter, [{ id: 'hermes', status: 'done', project: 'Hermes', tool: '本轮完成', startedAt: 5 }]);
  assert.equal(finished.status, 'done');
  const failed = aggregateApp(adapter, [{ id: 'hermes', status: 'failed', project: 'Hermes', tool: '失败', startedAt: 5 }]);
  assert.equal(failed.status, 'failed');
  assert.equal(standbyParentStatus('idle'), 'idle');
  assert.equal(standbyParentStatus('done'), 'done');
  assert.equal(standbyParentStatus(''), 'idle');
  assert.equal(standbyParentStatus(undefined), 'idle');
  assert.equal(aggregateApp(adapter, []), null);
});

test('standby is idle unless a round just ended', () => {
  assert.equal(codexStandbyStatus(null, NOW), 'idle');
  assert.equal(codexStandbyStatus({ status: 'completed', completed_at: (NOW - 60 * 1000) / 1000 }, NOW), 'done');
  assert.equal(codexStandbyStatus({ status: 'completed', completed_at: (NOW - 60 * 60 * 1000) / 1000 }, NOW), 'idle');
  assert.equal(codexStandbyStatus({ status: 'failed', completed_at: (NOW - 30 * 1000) / 1000 }, NOW), 'failed');
  assert.equal(codexStandbyStatus({ status: 'completed' }, NOW), 'idle');
  assert.equal(codexStandbyStatus({ status: 'inProgress', completed_at: (NOW - 10 * 1000) / 1000 }, NOW), 'idle');

  assert.equal(workbuddyStandbyStatus(null, NOW), 'idle');
  assert.equal(workbuddyStandbyStatus({ endedAt: null }, NOW), 'idle');
  assert.equal(workbuddyStandbyStatus({ endedAt: new Date(NOW - 60 * 1000).toISOString() }, NOW), 'done');
  assert.equal(workbuddyStandbyStatus({ endedAt: new Date(NOW - 60 * 60 * 1000).toISOString() }, NOW), 'idle');

  assert.equal(grokActivityStatus({ streaming: true, now: NOW }), 'running');
  assert.equal(grokActivityStatus({ sentAt: NOW - 20 * 1000, assistantReplied: false, now: NOW }), 'running');
  assert.equal(grokActivityStatus({ sentAt: NOW - 20 * 1000, assistantReplied: true, now: NOW }), 'done');
  assert.equal(grokActivityStatus({ sentAt: NOW - 10 * 60 * 1000, assistantReplied: true, now: NOW }), 'idle');
  assert.equal(grokActivityStatus({ now: NOW }), 'idle');
});
