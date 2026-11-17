#!/usr/bin/env node
/**
 * probe.mjs — read-only connectivity probe for the DSH bridge.
 *
 * Usage: node tools/probe.mjs [--url http://127.0.0.1:PORT] [--seconds 6]
 *
 * Steps:
 *  1. discover the running DSH Web GUI (same logic as the bridge)
 *  2. verify the minted browser-session cookie with POST /api/session/list
 *  3. print compact session rows for running / recently active sessions
 *  4. open /api/remote.mux $events for N seconds and print received frames
 *     (ready / emit / waterfall / cancel) — useful to confirm approvals channel.
 *
 * It never sends a prompt, answer, or any mutating RPC.
 */
import { discoverDsh } from '../lib/dsh-auth.mjs';
import { DshRpc } from '../lib/rpc.mjs';
import { openMux, openEventStream } from '../vendor/ws-mux.mjs';

function argValue (name) {
  const index = process.argv.indexOf (name);
  return index >= 0 ? process.argv[index + 1] : null;
}

const explicitUrl = argValue ('--url');
const seconds = Number (argValue ('--seconds') || 6);

console.log ('[1/4] discovering DSH Web GUI ...');
const dsh = await discoverDsh ({ explicitUrl });
console.log ('      origin:', dsh.origin, '(source:', dsh.source + ')');
console.log ('      cookie:', dsh.cookie.name.slice (0, 14) + '...' , '(value redacted)');

const rpc = new DshRpc ({ origin: dsh.origin, cookie: dsh.cookie });
console.log ('[2/4] session/list ...');
const items = await rpc.listSessions ();
const running = items.filter ((row) => row.running);
console.log ('      ok: sessions=' + items.length + ' running=' + running.length);

console.log ('[3/4] running / recently active sessions:');
const cutoff = Date.now () - 15 * 60 * 1000;
const active = items.filter ((row) => row.running || (row.updatedAt || 0) > cutoff).slice (0, 8);
for (const row of active) {
  const values = (row.projections && row.projections.values) || {};
  console.log ('      ' + row.sessionId + '  running=' + row.running
    + '  origin=' + (row.origin || 'session')
    + '  title=' + JSON.stringify (values.title || null));
}

console.log ('[4/4] opening $events for ' + seconds + 's ...');
const mux = await openMux ({ baseUrl: dsh.origin, cookie: dsh.cookie });
const events = openEventStream (mux);
events.onEmit ((frame) => console.log ('      emit:', frame.event, JSON.stringify (frame.args).slice (0, 160)));
events.onWaterfall ((frame) => console.log ('      WATERFALL:', frame.event, 'agentId=' + frame.agentId, JSON.stringify (frame.request).slice (0, 240)));
events.onCancel ((frame) => console.log ('      cancel:', JSON.stringify (frame)));
events.on ('error', (error) => console.log ('      events error:', error.message));
const ready = await Promise.race ([
  events.ready,
  new Promise ((resolve, reject) => setTimeout (() => reject (new Error ('$events ready timeout')), 5000))
]);
console.log ('      $events ready: generation ' + String (ready.clientId).slice (0, 8));
await new Promise ((resolve) => setTimeout (resolve, seconds * 1000));
events.close ();
await mux.close ();
console.log ('done.');
