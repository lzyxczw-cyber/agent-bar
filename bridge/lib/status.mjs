/**
 * Status vocabulary for external agent reports.
 *
 * `idle` is 待命: the agent has not started, or no round is in progress.
 * `done` is 完成: this round ended. Unknown values stay idle so a missing
 * heartbeat is not painted as a completed round.
 */
const EXTERNAL_STATUSES = new Set (['idle', 'running', 'waiting', 'done', 'failed']);

export function canonicalExternalStatus (raw) {
  const status = typeof raw === 'string' ? raw.trim ().toLowerCase () : '';
  if (status === 'approval') return 'waiting';
  if (EXTERNAL_STATUSES.has (status)) return status;
  return 'idle';
}
