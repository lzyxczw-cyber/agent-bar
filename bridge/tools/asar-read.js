#!/usr/bin/env node
// Minimal read-only ASAR reader for DSH desktop's app.asar (no npm deps).
// Layout observed: [pickle: uint32 size=4][uint32 headerBufLen]
//                  [pickle: uint32 payload][uint32 jsonLen][json padded]
//                  [file data...]
// Usage:
//   node asar-read.js list [prefix]
//   node asar-read.js read <path-in-asar>
//   node asar-read.js grep <regex> [prefix] [--max N]
//   node asar-read.js extract <path-in-asar> <out-file>
// The archive path can be overridden with DSH_ASAR.
'use strict';
const fs = require('fs');
const path = require('path');

const ASAR = process.env.DSH_ASAR || '/Applications/DeepSeek Harness.app/Contents/Resources/app.asar';

function openArchive() {
  const fd = fs.openSync(ASAR, 'r');
  const head = Buffer.alloc(8);
  fs.readSync(fd, head, 0, 8, null);
  const headerBufLen = head.readUInt32LE(4);
  const outer = Buffer.alloc(headerBufLen);
  fs.readSync(fd, outer, 0, headerBufLen, 8);
  const jsonLen = outer.readUInt32LE(4);
  const txt = outer.slice(8, 8 + jsonLen).toString('utf8');
  const header = JSON.parse(txt);
  return { fd, header, dataOffset: 8 + headerBufLen };
}

function getNode(header, relPath) {
  const parts = relPath.split('/').filter(Boolean);
  let node = header;
  for (const part of parts) {
    if (!node.files || !Object.prototype.hasOwnProperty.call(node.files, part)) return null;
    node = node.files[part];
  }
  return node;
}

function readEntry(archive, relPath) {
  const node = getNode(archive.header, relPath);
  if (!node || node.files) return null;
  if (node.unpacked) {
    try { return fs.readFileSync(path.join(ASAR + '.unpacked', relPath)); } catch (e) { return null; }
  }
  if (node.offset === undefined) return null;
  const off = archive.dataOffset + parseInt(node.offset, 10);
  const buf = Buffer.alloc(node.size);
  fs.readSync(archive.fd, buf, 0, node.size, off);
  return buf;
}

function walk(archive, prefix, cb) {
  const start = prefix ? getNode(archive.header, prefix) : archive.header;
  if (!start) return;
  const base = prefix ? prefix.replace(/\/+$/, '') : '';
  (function rec(node, rel) {
    if (!node.files) { cb(rel, node); return; }
    for (const name of Object.keys(node.files)) rec(node.files[name], rel ? rel + '/' + name : name);
  })(start, base);
}

function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const archive = openArchive();
  if (cmd === 'list' || cmd === 'grep') {
    const args = [];
    let max = cmd === 'list' ? 1000000 : 200;
    for (let i = 0; i < rest.length; i++) {
      if (rest[i] === '--max') max = parseInt(rest[++i], 10);
      else args.push(rest[i]);
    }
    const prefix = args[1] || '';
    if (cmd === 'list') {
      walk(archive, args[0] || '', (rel, node) => {
        if (node.files) return;
        console.log(rel + '\t' + node.size);
      });
      return;
    }
    const re = new RegExp(args[0], 'i');
    let hits = 0;
    walk(archive, prefix, (rel, node) => {
      if (hits >= max) return;
      if (node.files || !/\.(js|mjs|cjs|json|ts|md|yml|yaml)$/.test(rel)) return;
      if (node.size > 4 * 1024 * 1024) return;
      const buf = readEntry(archive, rel);
      if (!buf) return;
      const lines = buf.toString('utf8').split('\n');
      for (let i = 0; i < lines.length && hits < max; i++) {
        if (re.test(lines[i])) { console.log(rel + ':' + (i + 1) + ': ' + lines[i].trim().slice(0, 400)); hits++; }
      }
    });
    return;
  }
  if (cmd === 'read') {
    const buf = readEntry(archive, rest[0]);
    if (!buf) { console.error('not found: ' + rest[0]); process.exit(2); }
    process.stdout.write(buf);
    return;
  }
  if (cmd === 'extract') {
    const buf = readEntry(archive, rest[0]);
    if (!buf) { console.error('not found: ' + rest[0]); process.exit(2); }
    fs.mkdirSync(path.dirname(rest[1]), { recursive: true });
    fs.writeFileSync(rest[1], buf);
    console.log('wrote ' + rest[1] + ' (' + buf.length + ' bytes)');
    return;
  }
  console.error('usage: list|read|grep|extract ...');
  process.exit(1);
}
main();
