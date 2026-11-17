#!/usr/bin/env node
/**
 * agentbar-report.mjs — report an external agent (Codex, Claude Code, any
 * CLI wrapper) into Agent Bar's live feed.
 *
 * Writes one JSON report per agent into the external agents directory that the
 * bridge scans every tick:
 *   ~/Library/Application Support/AgentBar/agents/<id>.json   (0600)
 *   (override with --dir <dir> or AGENTBAR_AGENTS_DIR)
 *
 * The write is atomic (write temp + rename) and keeps startedAt from the first
 * report. Only the fields you pass are replaced; everything else is preserved,
 * so a heartbeat can be as short as:
 *   node tools/agentbar-report.mjs --id codex --status running
 * and completion is:
 *   node tools/agentbar-report.mjs --id codex --status done
 *
 * Usage:
 *   node tools/agentbar-report.mjs --id codex --name Codex --status running \
 *     --project agent-notch --tool "Bash: swift build" --thought "正在编译..."
 *   node tools/agentbar-report.mjs --id codex --status done
 *   node tools/agentbar-report.mjs --id codex --remove
 *   echo '{"id":"codex","status":"running","tool":"Bash"}' | node tools/... --json -
 *
 * Zero dependencies. Never stores or prints secrets.
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const STATUSES = new Set (['running', 'waiting', 'done', 'failed']);
const FIELD_FLAGS = {
  '--id': 'id',
  '--name': 'name',
  '--status': 'status',
  '--project': 'project',
  '--tool': 'tool',
  '--detail': 'detail',
  '--thought': 'thought',
  '--tokens': 'tokens',
  '--cwd': 'cwd',
  '--model': 'model',
  '--preset': 'preset'
};

function usage () {
  return [
    '用法: node tools/agentbar-report.mjs --id <id> [选项]',
    '',
    '把外部 agent 的运行状态写入 Agent Bar 的实时状态条。',
    '',
    '选项:',
    '  --id <id>           agent 标识（写入 <id>.json，必填）',
    '  --name <name>       显示名称（默认 <id>）',
    '  --status <state>    running | waiting | done | failed',
    '  --project <name>    项目名',
    '  --tool <text>       当前工具/动作，如 "Bash: swift build"',
    '  --detail <text>     补充说明',
    '  --thought <text>    最新思考文本（会原样保留，交给状态条显示）',
    '  --tokens <n>        累计 token 数',
    '  --cwd <path>        工作目录',
    '  --model <name>      模型名',
    '  --preset <name>     预设名',
    '  --json <json>       用一段 JSON 更新（传 - 表示从 stdin 读取）',
    '  --remove            删除该 agent 的报告文件',
    '  --dir <dir>         报告目录（默认 ~/Library/Application Support/AgentBar/agents）',
    '  --help, -h          显示帮助',
    '',
    '示例:',
    '  node tools/agentbar-report.mjs --id codex --name Codex --status running \\',
    '    --project agent-notch --tool "Bash: swift build" --thought "正在编译..."',
    '  node tools/agentbar-report.mjs --id codex --status done',
    '  node tools/agentbar-report.mjs --id codex --remove',
    '  echo \'{"id":"claude","status":"running","tool":"Edit"}\' | \\',
    '    node tools/agentbar-report.mjs --json -',
    ''
  ].join ('\n');
}

function defaultDirectory () {
  const fromEnv = process.env.AGENTBAR_AGENTS_DIR;
  if (typeof fromEnv === 'string' && fromEnv.trim () !== '') return path.resolve (fromEnv.trim ());
  return path.join (os.homedir (), 'Library', 'Application Support', 'AgentBar', 'agents');
}

class CliError extends Error {}

function parseArgs (argv) {
  const options = { json: null, remove: false, help: false, dir: null, fields: {} };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    const next = () => {
      const value = argv[++index];
      if (value === undefined) throw new CliError ('缺少 ' + arg + ' 的值');
      return value;
    };
    if (arg === '--help' || arg === '-h') options.help = true;
    else if (arg === '--remove') options.remove = true;
    else if (arg === '--json') options.json = next ();
    else if (arg === '--dir') options.dir = path.resolve (next ());
    else if (Object.hasOwn (FIELD_FLAGS, arg)) options.fields[FIELD_FLAGS[arg]] = next ();
    else throw new CliError ('未知参数: ' + arg);
  }
  return options;
}

function readStdin () {
  return new Promise ((resolve, reject) => {
    let data = '';
    process.stdin.setEncoding ('utf8');
    process.stdin.on ('data', (chunk) => {
      data += chunk;
      if (data.length > 1024 * 1024) {
        process.stdin.destroy ();
        reject (new CliError ('stdin 内容过大'));
      }
    });
    process.stdin.on ('end', () => resolve (data));
    process.stdin.on ('error', (error) => reject (new CliError ('读取 stdin 失败: ' + error.message)));
  });
}

async function readJsonInput (jsonFlag, hasFieldFlags) {
  let raw = null;
  if (jsonFlag !== null) raw = jsonFlag === '-' ? await readStdin () : jsonFlag;
  // Bare piped JSON is only consumed when no field flags are present, so shell
  // hooks that pipe their own JSON into this command (Claude Code hooks do)
  // never have that payload written into the report by accident.
  else if (!process.stdin.isTTY && !hasFieldFlags) raw = await readStdin ();
  if (raw === null) return {};
  const text = raw.trim ();
  if (text === '') return {};
  let parsed;
  try {
    parsed = JSON.parse (text);
  } catch (error) {
    throw new CliError ('JSON 解析失败: ' + error.message);
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray (parsed)) throw new CliError ('JSON 输入必须是对象');
  return parsed;
}

function safeId (value) {
  if (value === undefined || value === null) throw new CliError ('缺少 --id');
  const id = String (value).trim ();
  if (id === '' || id.length > 80) throw new CliError ('--id 必须是 1-80 个字符');
  if (id === '.' || id === '..' || id.startsWith ('.')) throw new CliError ('--id 不能以点开头');
  if (/[\/\\\u0000-\u001f]/u.test (id)) throw new CliError ('--id 不能包含路径分隔符或控制字符');
  return id;
}

function numberOrNull (value) {
  if (value === undefined || value === null || value === '') return null;
  const number = Number (value);
  return Number.isFinite (number) ? number : null;
}

function stringOrNull (value) {
  if (value === undefined || value === null) return null;
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String (value);
  return null;
}

function readExisting (file) {
  try {
    const parsed = JSON.parse (fs.readFileSync (file, 'utf8'));
    return parsed && typeof parsed === 'object' && !Array.isArray (parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function normalizeJsonFields (merged) {
  for (const key of ['name', 'project', 'tool', 'detail', 'thought', 'cwd', 'model', 'preset']) {
    if (!(key in merged)) continue;
    const value = stringOrNull (merged[key]);
    if (value === null) delete merged[key];
    else merged[key] = value;
  }
  if ('tokens' in merged) {
    const tokens = numberOrNull (merged.tokens);
    if (tokens === null) delete merged.tokens;
    else merged.tokens = Math.max (0, Math.round (tokens));
  }
  return merged;
}

function writeReport ({ directory, id, payload, fields }) {
  const file = path.join (directory, id + '.json');
  const now = Date.now ();
  const existing = readExisting (file);
  const merged = { ...existing, ...payload, ...fields };
  merged.id = id;
  merged.updatedAt = now;
  const startedAt = numberOrNull (existing.startedAt);
  merged.startedAt = startedAt !== null ? startedAt : (numberOrNull (payload.startedAt) ?? now);
  let status = merged.status;
  if (status === undefined || status === null || status === '') status = 'running';
  status = String (status).trim ().toLowerCase ();
  if (!STATUSES.has (status)) throw new CliError ('--status 必须是 running | waiting | done | failed');
  merged.status = status;
  normalizeJsonFields (merged);

  fs.mkdirSync (directory, { recursive: true, mode: 0o700 });
  const temporary = path.join (directory, '.' + id + '.' + process.pid + '.' + now + '.tmp');
  try {
    fs.writeFileSync (temporary, JSON.stringify (merged, null, 2) + '\n', { mode: 0o600 });
    fs.chmodSync (temporary, 0o600);
    fs.renameSync (temporary, file);
  } catch (error) {
    try { fs.unlinkSync (temporary); } catch {}
    throw new CliError ('写入失败: ' + error.message);
  }
  return { file, status: merged.status, startedAt: merged.startedAt };
}

function removeReport ({ directory, id }) {
  const file = path.join (directory, id + '.json');
  try {
    fs.unlinkSync (file);
    return { file, removed: true };
  } catch (error) {
    if (error.code === 'ENOENT') return { file, removed: false };
    throw new CliError ('删除失败: ' + error.message);
  }
}

async function main () {
  const options = parseArgs (process.argv.slice (2));
  if (options.help) { process.stdout.write (usage ()); return; }
  const payload = await readJsonInput (options.json, Object.keys (options.fields).length > 0);
  const id = safeId (options.fields.id !== undefined ? options.fields.id : payload.id);
  const directory = options.dir || defaultDirectory ();

  if (options.remove) {
    const result = removeReport ({ directory, id });
    console.log (result.removed ? '已删除 agent 报告: ' + result.file : '报告不存在（已忽略）: ' + result.file);
    return;
  }

  const fields = {};
  for (const [key, value] of Object.entries (options.fields)) {
    if (key === 'id') continue;
    fields[key] = value;
  }
  const result = writeReport ({ directory, id, payload, fields });
  console.log ('已写入 agent 报告: ' + result.file);
  console.log ('  id=' + id + ' status=' + result.status + ' startedAt=' + result.startedAt + ' updatedAt=' + Date.now ());
}

main ().catch ((error) => {
  const message = error instanceof CliError ? error.message : (error && error.stack ? error.stack : String (error));
  process.stderr.write (message + '\n\n' + usage ());
  process.exit (error instanceof CliError ? 2 : 1);
});
