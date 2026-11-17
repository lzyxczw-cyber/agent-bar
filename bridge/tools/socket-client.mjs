import net from 'node:net';
const socketPath = process.argv[2];
const socket = net.connect(socketPath);
let buffer = '';
let count = 0;
socket.setEncoding('utf8');
socket.on('data', (chunk) => {
  buffer += chunk;
  let index;
  while ((index = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, index);
    buffer = buffer.slice(index + 1);
    if (!line) continue;
    const parsed = JSON.parse(line);
    count++;
    console.log('line', count, 'type', parsed.type, 'ts', parsed.ts, 'eventsConnected', parsed.dsh && parsed.dsh.eventsConnected, 'running', parsed.counts && parsed.counts.running);
    if (count >= 2) { socket.destroy(); process.exit(0); }
  }
});
socket.on('error', (e) => { console.log('socket error', e.message); process.exit(1); });
setTimeout(() => { console.log('timeout, lines', count); process.exit(count ? 0 : 1); }, 4000);
