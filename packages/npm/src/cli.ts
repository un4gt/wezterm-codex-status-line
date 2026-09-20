import {
  cancel,
  confirm,
  intro,
  isCancel,
  multiselect,
  outro,
  select,
  text,
} from '@clack/prompts';
import Ajv2020 from 'ajv/dist/2020.js';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import {spawn, spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import packageInfo from '../package.json' with {type: 'json'};
import {
  buildRenderPlan,
  segmentIds,
  type PreviewState,
  type SegmentId,
  type StatuslineConfig,
} from '../../../contract/render.js';

const VERSION = packageInfo.version;
const PACKAGE_NAME = 'wezterm-codex-status-line';
const ASSET_NAMES = [
  'codex_statusline_bridge.ps1',
  'codex_statusline_bridge.py',
  'codex_statusline_bridge.js',
  'codex_statusline_core.lua',
  'codex_statusline/version.lua',
  'codex_statusline/domain/common.lua',
  'codex_statusline/domain/process.lua',
  'codex_statusline/domain/session.lua',
  'codex_statusline/domain/prices.lua',
  'codex_statusline/domain/pricing.lua',
  'codex_statusline/domain/render.lua',
  'codex_statusline/util.lua',
  'codex_statusline/config.lua',
  'codex_statusline/session_index.lua',
  'codex_statusline/rollout.lua',
  'codex_statusline/git.lua',
  'codex_statusline/process.lua',
  'codex_statusline/formatting.lua',
  'codex_statusline/legacy_renderer.lua',
  'codex_statusline/renderer.lua',
  'codex_statusline/layout.lua',
  'codex_statusline/state.lua',
  'codex_statusline/wezterm_adapter.lua',
  'codex_statusline/lifecycle.lua',
  'codex_statusline.lua',
] as const;
const TITLE_VALUE = ['app-name', 'model', 'reasoning', 'project-name'];
const HEX_COLOR = /^#[0-9a-fA-F]{6}$/;
const BOOLEAN_FLAGS = new Set([
  '--dry-run', '--force', '--help', '--json', '--no-color', '--no-powerline',
  '--no-title-bridge', '--powerline', '--purge-config', '--title-bridge', '--yes',
]);

class CliError extends Error {
  constructor(message: string, readonly exitCode = 1) {
    super(message);
  }
}

type JsonObject = Record<string, unknown>;
type FlagValue = string | true | string[];
type Flags = Map<string, FlagValue>;

function assetsDir() {
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'assets');
}

function readJson<T>(target: string): T {
  return JSON.parse(fs.readFileSync(target, 'utf8')) as T;
}

function writeJsonAtomic(target: string, value: unknown) {
  fs.mkdirSync(path.dirname(target), {recursive: true});
  const temp = `${target}.${process.pid}.${crypto.randomUUID()}.tmp`;
  fs.writeFileSync(temp, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  fs.renameSync(temp, target);
}

function copyAssetsAtomic(targets: Array<[string, string]>) {
  const staged: Array<[string, string]> = [];
  try {
    for (const [source, target] of targets) {
      fs.mkdirSync(path.dirname(target), {recursive: true});
      const temp = `${target}.${process.pid}.${crypto.randomUUID()}.tmp`;
      fs.copyFileSync(source, temp);
      staged.push([temp, target]);
    }
    for (const [temp, target] of staged) fs.renameSync(temp, target);
  } finally {
    for (const [temp] of staged) fs.rmSync(temp, {force: true});
  }
}

function quoteCommand(value: string) {
  return `"${value.replaceAll('"', '\\"')}"`;
}

function backup(target: string) {
  if (!fs.existsSync(target)) return;
  const timestamp = new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 17);
  fs.copyFileSync(target, `${target}.bak-${timestamp}`);
}

function parseFlags(args: string[]) {
  const values: Flags = new Map();
  const positional: string[] = [];
  const addValue = (name: string, value: string | true) => {
    const current = values.get(name);
    if (current === undefined) values.set(name, value);
    else if (typeof value === 'string') {
      if (Array.isArray(current)) current.push(value);
      else if (typeof current === 'string') values.set(name, [current, value]);
      else values.set(name, [value]);
    }
  };
  for (let index = 0; index < args.length; index += 1) {
    const value = args[index];
    if (!value.startsWith('--')) {
      positional.push(value);
      continue;
    }
    const [name, inline] = value.split('=', 2);
    if (inline !== undefined) addValue(name, inline);
    else if (BOOLEAN_FLAGS.has(name)) addValue(name, true);
    else if (args[index + 1] && !args[index + 1].startsWith('--')) addValue(name, args[++index]);
    else addValue(name, true);
  }
  return {values, positional};
}

function flagString(flags: Flags, name: string) {
  const value = flags.get(name);
  if (Array.isArray(value)) return value.at(-1);
  return typeof value === 'string' ? value : undefined;
}

function flagStrings(flags: Flags, name: string) {
  const value = flags.get(name);
  if (Array.isArray(value)) return value;
  return typeof value === 'string' ? [value] : [];
}

function hasFlag(flags: Flags, name: string) {
  return flags.has(name);
}

function resolvePaths(flags: Flags) {
  const home = path.resolve(process.env.CODEX_STATUSLINE_USER_HOME || os.homedir());
  const codexHome = path.resolve(flagString(flags, '--codex-home') || process.env.CODEX_HOME || path.join(home, '.codex'));
  const moduleDir = path.resolve(flagString(flags, '--wezterm-module-dir') || path.join(home, '.config', 'wezterm'));
  const bridgeRoot = path.join(codexHome, 'wezterm-statusline');
  return {
    home,
    codexHome,
    moduleDir,
    bridgeRoot,
    bridgeBin: path.join(bridgeRoot, 'bin'),
    manifest: path.join(bridgeRoot, 'bridge.json'),
    config: path.resolve(flagString(flags, '--config-file') || path.join(moduleDir, 'codex_statusline_config.json')),
    hooks: path.join(codexHome, 'hooks.json'),
  };
}

function publicPaths(paths: ReturnType<typeof resolvePaths>) {
  return {
    codex_home: paths.codexHome,
    wezterm_module_dir: paths.moduleDir,
    config: paths.config,
    manifest: paths.manifest,
    hooks: paths.hooks,
  };
}

function isOurHandler(handler: unknown) {
  if (!handler || typeof handler !== 'object') return false;
  const value = handler as Record<string, unknown>;
  return `${value.command || ''} ${value.commandWindows || ''}`.includes('codex_statusline_bridge.');
}

function mergeHook(hooksPath: string, expected: JsonObject) {
  const document: JsonObject = fs.existsSync(hooksPath)
    ? readJson<JsonObject>(hooksPath)
    : {description: 'Hooks used by the WezTerm Codex statusline bridge.', hooks: {}};
  const hooks = (document.hooks && typeof document.hooks === 'object' ? document.hooks : {}) as JsonObject;
  const groups = Array.isArray(hooks.SessionStart) ? hooks.SessionStart : [];
  const kept = groups.flatMap((group) => {
    if (!group || typeof group !== 'object' || !Array.isArray((group as JsonObject).hooks)) return [group];
    const handlers = ((group as JsonObject).hooks as unknown[]).filter((handler) => !isOurHandler(handler));
    return handlers.length ? [{...(group as JsonObject), hooks: handlers}] : [];
  });
  hooks.SessionStart = [...kept, {hooks: [expected]}];
  document.hooks = hooks;
  backup(hooksPath);
  writeJsonAtomic(hooksPath, document);
}

function removeHook(hooksPath: string) {
  if (!fs.existsSync(hooksPath)) return;
  const document = readJson<JsonObject>(hooksPath);
  const hooks = (document.hooks && typeof document.hooks === 'object' ? document.hooks : {}) as JsonObject;
  const groups = Array.isArray(hooks.SessionStart) ? hooks.SessionStart : [];
  hooks.SessionStart = groups.flatMap((group) => {
    if (!group || typeof group !== 'object' || !Array.isArray((group as JsonObject).hooks)) return [group];
    const handlers = ((group as JsonObject).hooks as unknown[]).filter((handler) => !isOurHandler(handler));
    return handlers.length ? [{...(group as JsonObject), hooks: handlers}] : [];
  });
  document.hooks = hooks;
  backup(hooksPath);
  writeJsonAtomic(hooksPath, document);
}

function weztermConfigWithRequire(home: string, moduleDir: string) {
  const candidates = [path.join(home, '.wezterm.lua'), path.join(moduleDir, 'wezterm.lua')];
  return candidates.find((candidate) => fs.existsSync(candidate)
    && /require\s*\(\s*["']codex_statusline["']\s*\)/.test(fs.readFileSync(candidate, 'utf8')));
}

function checksum(target: string) {
  return crypto.createHash('sha256').update(fs.readFileSync(target)).digest('hex');
}

function loadManifest(target: string) {
  try { return readJson<JsonObject>(target); } catch { return {}; }
}

function installedAssetsHealthy(paths: ReturnType<typeof resolvePaths>) {
  const assets = loadManifest(paths.manifest).assets;
  if (!assets || typeof assets !== 'object' || Array.isArray(assets)) return false;
  const recorded = new Map(Object.entries(assets).map(([target, hash]) => [
    path.resolve(target).toLowerCase(),
    hash,
  ]));
  return ASSET_NAMES.every((name) => {
    const target = path.join(name.endsWith('.lua') ? paths.moduleDir : paths.bridgeBin, name);
    return fs.existsSync(target) && recorded.get(path.resolve(target).toLowerCase()) === checksum(target);
  });
}

function updateManifest(paths: ReturnType<typeof resolvePaths>, runner: 'npx' | 'uvx', titleRecord?: unknown) {
  const files = ASSET_NAMES.map((name) => path.join(
    name.endsWith('.lua') ? paths.moduleDir : paths.bridgeBin,
    name,
  ));
  const existing = loadManifest(paths.manifest);
  const manifest = {
    ...existing,
    schema: 4,
    package: {name: PACKAGE_NAME, version: VERSION, runner, installed_at_unix_ms: Date.now()},
    wezterm_module_dir: paths.moduleDir,
    config_path: paths.config,
    lua_modules: files.filter((file) => file.endsWith('.lua')),
    bridge_bin: paths.bridgeBin,
    bridge_runtime: process.execPath,
    assets: Object.fromEntries(files.filter(fs.existsSync).map((file) => [file, checksum(file)])),
    ...(titleRecord ? {codex_title_bridge: titleRecord} : {}),
  };
  writeJsonAtomic(paths.manifest, manifest);
}

function runPowerShell(action: 'Install' | 'Uninstall', paths: ReturnType<typeof resolvePaths>, titleBridge: boolean, quiet = false) {
  const executable = process.env.ComSpec ? 'powershell.exe' : 'pwsh';
  const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(assetsDir(), 'install.ps1'), `-${action}`,
    '-UserHome', paths.home, '-CodexHome', paths.codexHome, '-WezTermModuleDir', paths.moduleDir];
  if (action === 'Install' && titleBridge) args.push('-EnableCodexTitleBridge');
  const result = spawnSync(executable, args, {stdio: quiet ? 'pipe' : 'inherit', encoding: 'utf8'});
  if (result.error || result.status !== 0) {
    const details = quiet ? `: ${String(result.stderr || result.stdout || '').trim()}` : '';
    throw new CliError(`PowerShell ${action.toLowerCase()} failed${details}`, 1);
  }
}

async function rpcSession<T>(codexHome: string, callback: (request: (method: string, params: unknown) => Promise<any>) => Promise<T>) {
  const command = process.env.CODEX_STATUSLINE_CODEX_COMMAND || 'codex';
  const child = spawn(command, ['app-server', '--stdio'], {cwd: codexHome, env: {...process.env, CODEX_HOME: codexHome}, stdio: ['pipe', 'pipe', 'pipe']});
  const lines = readline.createInterface({input: child.stdout});
  let nextId = 1;
  const pending = new Map<number, {resolve: (value: unknown) => void; reject: (reason: unknown) => void}>();
  lines.on('line', (line) => {
    try {
      const message = JSON.parse(line);
      const waiter = pending.get(message.id);
      if (!waiter) return;
      pending.delete(message.id);
      if (message.error) waiter.reject(new Error(JSON.stringify(message.error)));
      else waiter.resolve(message.result);
    } catch {/* ignore app-server notifications */}
  });
  const request = (method: string, params: unknown) => new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, {resolve, reject});
    child.stdin.write(`${JSON.stringify({id, method, params})}\n`);
    setTimeout(() => {
      if (pending.delete(id)) reject(new Error(`Timed out waiting for ${method}`));
    }, 10000).unref();
  });
  try { return await callback(request); }
  finally { child.stdin.end(); child.kill(); lines.close(); }
}

function titleState(read: any, codexHome: string) {
  const layer = (read.layers || []).find((item: any) => item?.name?.type === 'user' && item?.name?.profile == null);
  const present = Object.prototype.hasOwnProperty.call(layer?.config?.tui || {}, 'terminal_title');
  return {
    present,
    value: present ? layer.config.tui.terminal_title : null,
    effective: read?.config?.tui?.terminal_title,
    version: layer?.version || null,
    file: layer?.name?.file || path.join(codexHome, 'config.toml'),
  };
}

async function enableTitleBridge(codexHome: string, existing?: any) {
  return rpcSession(codexHome, async (request) => {
    const before = titleState(await request('config/read', {includeLayers: true}), codexHome);
    if (existing?.enabled && JSON.stringify(before.value) !== JSON.stringify(existing.installed_value)) {
      throw new CliError('tui.terminal_title changed after installation; refusing to overwrite it', 3);
    }
    if (JSON.stringify(before.value) !== JSON.stringify(TITLE_VALUE)) {
      await request('config/batchWrite', {edits: [{keyPath: 'tui.terminal_title', value: TITLE_VALUE, mergeStrategy: 'replace'}], filePath: before.file, expectedVersion: before.version, reloadUserConfig: false});
    }
    const after = titleState(await request('config/read', {includeLayers: true}), codexHome);
    if (JSON.stringify(after.value) !== JSON.stringify(TITLE_VALUE)) throw new CliError('Codex did not persist tui.terminal_title');
    return existing?.enabled ? {...existing, installed_value: TITLE_VALUE, version_after: after.version} : {
      enabled: true,
      key_path: 'tui.terminal_title',
      config_file: after.file,
      original_present: before.present,
      original_value: before.value,
      installed_value: TITLE_VALUE,
      version_before: before.version,
      version_after: after.version,
    };
  });
}

async function restoreTitleBridge(codexHome: string, record: any) {
  await rpcSession(codexHome, async (request) => {
    const current = titleState(await request('config/read', {includeLayers: true}), codexHome);
    if (JSON.stringify(current.value) !== JSON.stringify(record.installed_value)) return;
    await request('config/batchWrite', {edits: [{keyPath: 'tui.terminal_title', value: record.original_present ? record.original_value : null, mergeStrategy: 'replace'}], filePath: current.file, expectedVersion: current.version, reloadUserConfig: false});
  });
}

function expectedNodeHook(paths: ReturnType<typeof resolvePaths>) {
  return {
    type: 'command',
    command: `${quoteCommand(process.execPath)} ${quoteCommand(path.join(paths.bridgeBin, 'codex_statusline_bridge.js'))}`,
    commandWindows: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ${quoteCommand(path.join(paths.bridgeBin, 'codex_statusline_bridge.ps1'))}`,
    timeout: 5,
  };
}

async function install(flags: Flags, update = false) {
  const paths = resolvePaths(flags);
  let titleBridge: boolean;
  if (hasFlag(flags, '--title-bridge')) titleBridge = true;
  else if (hasFlag(flags, '--no-title-bridge')) titleBridge = false;
  else if (update) titleBridge = Boolean((loadManifest(paths.manifest).codex_title_bridge as any)?.enabled);
  else if (hasFlag(flags, '--yes')) titleBridge = true;
  else if (process.stdin.isTTY) {
    const answer = await confirm({message: '启用 Codex terminal title bridge？', initialValue: true});
    if (isCancel(answer)) throw new CliError('Cancelled', 2);
    titleBridge = answer;
  } else throw new CliError('Non-interactive install requires --title-bridge or --no-title-bridge', 2);

  if (hasFlag(flags, '--dry-run')) {
    return {status: 'unchanged', changes: ['dry-run'], paths: publicPaths(paths)};
  }

  if (process.platform === 'win32') {
    runPowerShell('Install', paths, titleBridge, hasFlag(flags, '--json'));
    updateManifest(paths, 'npx');
  } else {
    const existing = loadManifest(paths.manifest);
    const titleRecord = titleBridge ? await enableTitleBridge(paths.codexHome, existing.codex_title_bridge) : existing.codex_title_bridge;
    const targets: Array<[string, string]> = ASSET_NAMES.map((name) => [
      path.join(assetsDir(), name),
      path.join(name.endsWith('.lua') ? paths.moduleDir : paths.bridgeBin, name),
    ]);
    copyAssetsAtomic(targets);
    mergeHook(paths.hooks, expectedNodeHook(paths));
    updateManifest(paths, 'npx', titleRecord);
  }
  return {status: 'changed', changes: [update ? 'updated' : 'installed'], paths: publicPaths(paths)};
}

function loadDefaultConfig() {
  return readJson<StatuslineConfig>(path.join(assetsDir(), 'contract', 'default-config.json'));
}

function validateConfig(config: unknown) {
  const schema = readJson(path.join(assetsDir(), 'contract', 'config.schema.json'));
  const AjvConstructor = Ajv2020 as unknown as new (options: Record<string, unknown>) => {compile: (value: unknown) => any};
  const validate = new AjvConstructor({allErrors: true, strict: false}).compile(schema);
  if (!validate(config)) throw new CliError(`Invalid config: ${validate.errors?.map((item: {message?: string}) => item.message).join(', ')}`, 2);
  return config as StatuslineConfig;
}

function loadConfig(target: string) {
  return fs.existsSync(target) ? validateConfig(readJson(target)) : loadDefaultConfig();
}

function colorPromptValidator(value: string) {
  return HEX_COLOR.test(value) ? undefined : '请输入 #RRGGBB';
}

function applyColorSpecs(config: StatuslineConfig, specs: string[]) {
  for (const spec of specs) {
    const [id, bg, fg, extra] = spec.split(':');
    if (extra !== undefined || !segmentIds.includes(id as SegmentId) || !HEX_COLOR.test(bg || '') || !HEX_COLOR.test(fg || '')) {
      throw new CliError(`Invalid --color ${spec}; expected segment:#RRGGBB:#RRGGBB`, 2);
    }
    config.options.theme.segments[id as SegmentId] = {bg, fg};
  }
}

function applyConfigFlags(config: StatuslineConfig, flags: Flags) {
  const label = flagString(flags, '--label');
  if (label) config.options.label = label;
  const rows = Number(flagString(flags, '--rows'));
  if (rows === 1 || rows === 2) config.options.bottom_pane.rows = rows;
  const binding = flagString(flags, '--binding-mode');
  if (binding === 'auto' || binding === 'hook' || binding === 'heuristic') config.options.sessions.binding_mode = binding;
  if (hasFlag(flags, '--powerline')) config.options.render.powerline = true;
  if (hasFlag(flags, '--no-powerline')) config.options.render.powerline = false;
  const order = flagString(flags, '--segments');
  if (order) config.options.render.segment_order = order.split(',').map((item) => item.trim()) as SegmentId[];
  const disabled = flagString(flags, '--disable');
  if (disabled !== undefined) config.options.render.disabled_segments = disabled ? disabled.split(',').map((item) => item.trim()) as SegmentId[] : [];
  const themeBg = flagString(flags, '--theme-bg');
  const themeFg = flagString(flags, '--theme-fg');
  const themeDim = flagString(flags, '--theme-dim');
  if (themeBg) config.options.theme.bg = themeBg;
  if (themeFg) config.options.theme.fg = themeFg;
  if (themeDim) config.options.theme.dim = themeDim;
  if (hasFlag(flags, '--color') && flagStrings(flags, '--color').length === 0) {
    throw new CliError('--color requires segment:#RRGGBB:#RRGGBB', 2);
  }
  applyColorSpecs(config, flagStrings(flags, '--color'));
  return config;
}

async function configure(flags: Flags) {
  const paths = resolvePaths(flags);
  let config = loadConfig(paths.config);
  const imported = flagString(flags, '--from');
  if (imported) config = validateConfig(readJson(path.resolve(imported)));
  const hasSettings = [...flags.keys()].some((key) => ['--label', '--rows', '--binding-mode', '--powerline', '--no-powerline', '--segments', '--disable', '--theme-bg', '--theme-fg', '--theme-dim', '--color', '--from'].includes(key));
  if (process.stdin.isTTY && !hasSettings) {
    intro('WezTerm Codex Status Line');
    const label = await text({message: '状态标签', initialValue: config.options.label, validate: (value) => value.length ? undefined : '不能为空'});
    if (isCancel(label)) throw new CliError('Cancelled', 2);
    const rows = await select({message: '状态 pane 行数', initialValue: config.options.bottom_pane.rows, options: [{value: 1, label: '1 行'}, {value: 2, label: '2 行'}]});
    if (isCancel(rows)) throw new CliError('Cancelled', 2);
    const powerline = await confirm({message: '使用 Powerline segment', initialValue: config.options.render.powerline});
    if (isCancel(powerline)) throw new CliError('Cancelled', 2);
    const enabled = await multiselect<string>({message: '显示项目', required: true, initialValues: segmentIds.filter((id) => !config.options.render.disabled_segments.includes(id)), options: segmentIds.map((id) => ({value: id, label: id}))});
    if (isCancel(enabled)) throw new CliError('Cancelled', 2);
    const order = await text({message: '显示顺序（逗号分隔）', initialValue: config.options.render.segment_order.join(',')});
    if (isCancel(order)) throw new CliError('Cancelled', 2);
    const customizeTheme = await confirm({message: '自定义主题颜色？', initialValue: false});
    if (isCancel(customizeTheme)) throw new CliError('Cancelled', 2);
    config.options.label = label;
    config.options.bottom_pane.rows = rows as 1 | 2;
    config.options.render.powerline = powerline;
    config.options.render.segment_order = String(order).split(',').map((item) => item.trim()) as SegmentId[];
    config.options.render.disabled_segments = segmentIds.filter((id) => !(enabled as SegmentId[]).includes(id));
    if (customizeTheme) {
      const themeBg = await text({message: '终端背景色', initialValue: config.options.theme.bg, validate: colorPromptValidator});
      if (isCancel(themeBg)) throw new CliError('Cancelled', 2);
      const themeFg = await text({message: '默认文字色', initialValue: config.options.theme.fg, validate: colorPromptValidator});
      if (isCancel(themeFg)) throw new CliError('Cancelled', 2);
      const themeDim = await text({message: '弱化文字色', initialValue: config.options.theme.dim, validate: colorPromptValidator});
      if (isCancel(themeDim)) throw new CliError('Cancelled', 2);
      const themed = await multiselect<string>({message: '选择要改色的 segment', required: false, options: segmentIds.map((id) => ({value: id, label: id}))});
      if (isCancel(themed)) throw new CliError('Cancelled', 2);
      config.options.theme.bg = String(themeBg);
      config.options.theme.fg = String(themeFg);
      config.options.theme.dim = String(themeDim);
      for (const id of themed as SegmentId[]) {
        const currentTheme = config.options.theme.segments[id] ?? {
          bg: config.options.theme.bg,
          fg: config.options.theme.fg,
        };
        const bg = await text({message: `${id} 背景色`, initialValue: currentTheme.bg, validate: colorPromptValidator});
        if (isCancel(bg)) throw new CliError('Cancelled', 2);
        const fg = await text({message: `${id} 文字色`, initialValue: currentTheme.fg, validate: colorPromptValidator});
        if (isCancel(fg)) throw new CliError('Cancelled', 2);
        config.options.theme.segments[id] = {bg: String(bg), fg: String(fg)};
      }
    }
  } else config = applyConfigFlags(config, flags);
  validateConfig(config);
  const preview = renderText(config, readJson(path.join(assetsDir(), 'contract', 'sample-state.json')), Number(flagString(flags, '--width') || 120), !hasFlag(flags, '--no-color'));
  if (!hasFlag(flags, '--json')) console.log(`\n${preview}\n`);
  if (!hasFlag(flags, '--dry-run')) writeJsonAtomic(paths.config, config);
  if (process.stdin.isTTY && !hasSettings) outro(hasFlag(flags, '--dry-run') ? '预演完成，未写入配置' : `配置已写入 ${paths.config}`);
  return {status: hasFlag(flags, '--dry-run') ? 'unchanged' : 'changed', changes: [hasFlag(flags, '--dry-run') ? 'dry-run' : 'configured'], paths: publicPaths(paths)};
}

function hexToRgb(value: string) {
  return [1, 3, 5].map((index) => Number.parseInt(value.slice(index, index + 2), 16));
}

function renderText(config: StatuslineConfig, state: PreviewState, width: number, color = true) {
  const plan = buildRenderPlan(config, state, width);
  const useAnsi = color && config.options.render.powerline && process.stdout.isTTY;
  return plan.lines.map((line) => line.map((segment) => {
    if (!useAnsi) return segment.text;
    const [br, bg, bb] = hexToRgb(segment.bg);
    const [fr, fg, fb] = hexToRgb(segment.fg);
    return `\x1b[48;2;${br};${bg};${bb}m\x1b[38;2;${fr};${fg};${fb}m ${segment.text} \x1b[0m`;
  }).join(useAnsi ? '' : ' | ')).join('\n');
}

function preview(flags: Flags) {
  const paths = resolvePaths(flags);
  const config = loadConfig(paths.config);
  const statePath = flagString(flags, '--state');
  const state = statePath ? readJson<PreviewState>(path.resolve(statePath)) : readJson<PreviewState>(path.join(assetsDir(), 'contract', 'sample-state.json'));
  const output = renderText(config, state, Number(flagString(flags, '--width') || process.stdout.columns || 120), !hasFlag(flags, '--no-color'));
  if (!hasFlag(flags, '--json')) console.log(output);
  return {status: 'unchanged', changes: [], preview: output, paths: publicPaths(paths)};
}

function doctor(flags: Flags) {
  const paths = resolvePaths(flags);
  let configHealthy = true;
  if (fs.existsSync(paths.config)) {
    try { validateConfig(readJson(paths.config)); }
    catch { configHealthy = false; }
  }
  const checks = {
    manifest: fs.existsSync(paths.manifest),
    lua_entry: fs.existsSync(path.join(paths.moduleDir, 'codex_statusline.lua')),
    lua_core: fs.existsSync(path.join(paths.moduleDir, 'codex_statusline_core.lua')),
    asset_integrity: installedAssetsHealthy(paths),
    hooks: fs.existsSync(paths.hooks) && JSON.stringify(readJson(paths.hooks)).includes('codex_statusline_bridge'),
    wezterm_require: Boolean(weztermConfigWithRequire(paths.home, paths.moduleDir)),
    config: configHealthy,
  };
  const healthy = Object.values(checks).every(Boolean);
  if (!hasFlag(flags, '--json')) for (const [name, ok] of Object.entries(checks)) console.log(`${ok ? 'OK' : 'MISSING'}  ${name}`);
  if (!healthy) process.exitCode = 1;
  return {status: healthy ? 'unchanged' : 'failed', changes: [], warnings: Object.entries(checks).filter(([, ok]) => !ok).map(([name]) => name), paths: publicPaths(paths)};
}

async function uninstall(flags: Flags) {
  const paths = resolvePaths(flags);
  const activeConfig = weztermConfigWithRequire(paths.home, paths.moduleDir);
  if (activeConfig) throw new CliError(`Remove require("codex_statusline") from ${activeConfig}, then run uninstall again`, 3);
  if (hasFlag(flags, '--dry-run')) return {status: 'unchanged', changes: ['dry-run'], paths: publicPaths(paths)};
  const manifest = loadManifest(paths.manifest);
  if (process.platform === 'win32') runPowerShell('Uninstall', paths, false, hasFlag(flags, '--json'));
  else {
    if (manifest.codex_title_bridge) await restoreTitleBridge(paths.codexHome, manifest.codex_title_bridge);
    removeHook(paths.hooks);
    for (const name of ASSET_NAMES) fs.rmSync(path.join(name.endsWith('.lua') ? paths.moduleDir : paths.bridgeBin, name), {force: true});
    fs.rmSync(paths.manifest, {force: true});
  }
  if (hasFlag(flags, '--purge-config')) fs.rmSync(paths.config, {force: true});
  return {status: 'changed', changes: ['uninstalled'], paths: publicPaths(paths)};
}

function help() {
  console.log(`WezTerm Codex Status Line ${VERSION}\n\nUsage:\n  wezterm-codex-status-line <install|configure|preview|doctor|update|uninstall> [options]\n\nGlobal options:\n  --codex-home PATH  --wezterm-module-dir PATH  --config-file PATH\n  --json  --no-color  --yes  --version\n\nConfigure options:\n  --label TEXT  --rows 1|2  --binding-mode auto|hook|heuristic\n  --segments IDS  --disable IDS  --powerline|--no-powerline\n  --theme-bg #RRGGBB  --theme-fg #RRGGBB  --theme-dim #RRGGBB\n  --color segment:#RRGGBB:#RRGGBB (repeatable)  --dry-run`);
}

async function menu() {
  const answer = await select({message: '选择操作', options: [
    {value: 'install', label: '安装 / 更新'},
    {value: 'configure', label: '配置与预览'},
    {value: 'doctor', label: '检查安装'},
    {value: 'uninstall', label: '卸载'},
  ]});
  if (isCancel(answer)) { cancel('已取消'); return undefined; }
  return answer;
}

async function main() {
  const argv = process.argv.slice(2);
  if (argv.includes('--version')) { console.log(VERSION); return; }
  const {values: flags, positional} = parseFlags(argv);
  let command = positional.shift();
  if (positional.length) throw new CliError(`Unexpected argument: ${positional[0]}`, 2);
  if (hasFlag(flags, '--help')) { help(); return; }
  if (!command && process.stdin.isTTY) command = await menu();
  if (!command) { help(); return; }
  let result: any;
  if (command === 'install') result = await install(flags);
  else if (command === 'update') result = await install(flags, true);
  else if (command === 'configure' || command === 'config') result = await configure(flags);
  else if (command === 'preview') result = preview(flags);
  else if (command === 'doctor') result = doctor(flags);
  else if (command === 'uninstall') result = await uninstall(flags);
  else if (command === 'help' || command === '--help') { help(); return; }
  else throw new CliError(`Unknown command: ${command}`, 2);
  if (hasFlag(flags, '--json')) console.log(JSON.stringify({schema: 1, command, version: VERSION, ...result}, null, 2));
  else if (result?.status === 'changed') console.log(`${command}: complete`);
}

main().catch((error) => {
  const cliError = error instanceof CliError ? error : new CliError(error instanceof Error ? error.message : String(error));
  console.error(`Error: ${cliError.message}`);
  process.exitCode = cliError.exitCode;
});
