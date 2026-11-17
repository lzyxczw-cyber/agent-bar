/**
 * protocol.mjs — classify a DSH session/list probe.
 *
 * Finding no GUI is "unavailable" (the app may keep its simulated demo).
 * Finding a DSH-like server whose session/list envelope, auth, or route does
 * not match this bridge is "mismatch": callers must surface that instead of
 * pretending the simulated demo is live data.
 */

const MISMATCH_CODES = new Set (['gateway/protocol', 'gateway/not-found', 'auth/unauthorized']);

export function classifyDshProbe ({ discovered, error = null, value = null } = {}) {
  if (!discovered) return { protocol: 'unavailable', mismatch: false, error: null };
  if (error) {
    const code = typeof error.code === 'string' ? error.code : '';
    const message = typeof error.message === 'string' && error.message !== '' ? error.message : 'DSH protocol probe failed';
    if (MISMATCH_CODES.has (code)) return { protocol: 'mismatch', mismatch: true, error: message };
    return { protocol: 'unavailable', mismatch: false, error: message };
  }
  if (!value || typeof value !== 'object' || Array.isArray (value) || !Array.isArray (value.items)) {
    return { protocol: 'mismatch', mismatch: true, error: 'session/list value is not { items: [] }' };
  }
  return { protocol: 'ok', mismatch: false, error: null };
}
