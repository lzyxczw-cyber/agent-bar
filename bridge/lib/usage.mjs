/**
 * Today's token spend is the increase of each session's cumulative usage
 * while the bridge is watching, not the session total.
 */

export function usageTotal (usage) {
  if (!usage || typeof usage !== 'object') return 0;
  return (Number (usage.uncachedInputTokens) || 0) + (Number (usage.outputTokens) || 0);
}

export function usageDayKey (date) {
  return [
    date.getFullYear (),
    String (date.getMonth () + 1).padStart (2, '0'),
    String (date.getDate ()).padStart (2, '0')
  ].join ('-');
}

function cloneState (previous) {
  const source = previous && typeof previous === 'object' ? previous : {};
  return {
    day: typeof source.day === 'string' ? source.day : null,
    sessions: source.sessions && typeof source.sessions === 'object' ? { ...source.sessions } : {},
    bySession: source.bySession && typeof source.bySession === 'object' ? { ...source.bySession } : {},
    tokensToday: Number (source.tokensToday) || 0,
    history: Array.isArray (source.history) ? source.history.slice () : [],
    since: Number (source.since) || null
  };
}

/**
 * Apply one observation of cumulative session totals.
 * `sessions` is `{ id, tokenUsage, updatedAt }`. `now` is a Date.
 * The returned state is a new object; `dirty` is true when it changed.
 */
export function applyUsageTick (previous, sessions, now) {
  const day = usageDayKey (now);
  const dayStart = new Date (now.getFullYear (), now.getMonth (), now.getDate ()).getTime ();
  let state = cloneState (previous);
  let dirty = false;

  if (!previous || state.day !== day) {
    const rolled = previous && state.day
      ? { day: state.day, tokens: Number (state.tokensToday) || 0 }
      : null;
    const history = Array.isArray (state.history) ? state.history.slice (-13) : [];
    if (rolled && rolled.tokens > 0) history.push (rolled);
    state = {
      day,
      sessions: {},
      bySession: {},
      tokensToday: 0,
      history,
      since: now.getTime ()
    };
    dirty = true;
  }
  if (!state.bySession || typeof state.bySession !== 'object') {
    state.bySession = {};
    dirty = true;
  }
  if (!Array.isArray (state.history)) {
    state.history = [];
    dirty = true;
  }
  if (!state.since) {
    state.since = now.getTime ();
    dirty = true;
  }
  if (typeof state.tokensToday !== 'number' || !Number.isFinite (state.tokensToday)) {
    state.tokensToday = 0;
    dirty = true;
  }

  let gained = 0;
  let sessionsToday = 0;
  const live = new Set ();
  for (const session of sessions) {
    if (!session || typeof session.id !== 'string' || session.id === '') continue;
    live.add (session.id);
    const total = usageTotal (session.tokenUsage);
    const baseline = state.sessions[session.id];
    if (typeof baseline === 'number') {
      const delta = total - baseline;
      if (delta > 0) {
        gained += delta;
        state.bySession[session.id] = (state.bySession[session.id] || 0) + delta;
        dirty = true;
      }
    } else {
      dirty = true;
    }
    state.sessions[session.id] = total;
    if ((session.updatedAt || 0) >= dayStart) sessionsToday++;
  }
  if (gained > 0) {
    state.tokensToday += gained;
    dirty = true;
  }
  for (const id of Object.keys (state.sessions)) {
    if (!live.has (id)) {
      delete state.sessions[id];
      dirty = true;
    }
  }

  return {
    state,
    dirty,
    gained,
    sessionsToday,
    day
  };
}
