#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

function codexHome() {
  return path.resolve(process.env.CODEX_HOME || path.join(os.homedir(), '.codex'));
}

function writeJsonAtomic(target, value) {
  fs.mkdirSync(path.dirname(target), {recursive: true});
  const temp = `${target}.${process.pid}.${crypto.randomUUID()}.tmp`;
  fs.writeFileSync(temp, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  fs.renameSync(temp, target);
}

function readThreadId(transcriptPath, fallback) {
  if (!transcriptPath) return fallback;
  try {
    const lines = fs.readFileSync(transcriptPath, 'utf8').split(/\r?\n/, 20);
    for (const line of lines) {
      if (!line) continue;
      try {
        const item = JSON.parse(line);
        const candidate = item?.type === 'session_meta' ? item?.payload?.id : undefined;
        if (candidate) return candidate;
      } catch {
        // A partial rollout line is expected while Codex is writing.
      }
    }
  } catch {
    // The hook payload session id remains a safe fallback.
  }
  return fallback;
}

async function main() {
  const paneId = process.env.WEZTERM_PANE || '';
  if (!/^\d+$/.test(paneId)) return;

  let raw = '';
  for await (const chunk of process.stdin) raw += chunk;
  if (!raw) return;

  const payload = JSON.parse(raw);
  const sessionId = String(payload.session_id || '');
  if (!/^[0-9a-fA-F-]{36}$/.test(sessionId)) throw new Error('Invalid Codex session_id');
  const transcriptPath = typeof payload.transcript_path === 'string' ? payload.transcript_path : null;
  const threadId = readThreadId(transcriptPath, sessionId);
  const mapping = {
    schema: 1,
    pane_id: paneId,
    thread_id: threadId.toLowerCase(),
    session_id: sessionId.toLowerCase(),
    rollout_path: transcriptPath,
    cwd: String(payload.cwd || ''),
    source: String(payload.source || ''),
    generation: crypto.randomUUID(),
    written_at_unix_ms: Date.now(),
  };
  writeJsonAtomic(path.join(codexHome(), 'wezterm-statusline', 'panes', `${paneId}.json`), mapping);
}

main().catch((error) => {
  console.error(`codex statusline bridge: ${error.message}`);
  process.exitCode = 1;
});
