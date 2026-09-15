import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {fileURLToPath} from 'node:url';

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const tsxCli = path.join(packageRoot, 'node_modules', 'tsx', 'dist', 'cli.mjs');
const sourceCli = path.join(packageRoot, 'src', 'cli.ts');

function run(args: string[], env: NodeJS.ProcessEnv) {
  return spawnSync(process.execPath, [tsxCli, sourceCli, ...args], {encoding: 'utf8', env});
}

test('CLI install, configure, guard, and uninstall', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'wcsline-node-test-'));
  const codex = path.join(root, 'codex');
  const wezterm = path.join(root, 'wezterm');
  const config = path.join(wezterm, 'codex_statusline_config.json');
  const common = ['--codex-home', codex, '--wezterm-module-dir', wezterm, '--config-file', config];
  const env = {...process.env, CODEX_STATUSLINE_USER_HOME: root};
  try {
    let result = run(['update', ...common, '--help'], env);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Usage:/);
    assert.equal(fs.existsSync(path.join(codex, 'wezterm-statusline', 'bridge.json')), false);
    assert.equal(fs.existsSync(path.join(wezterm, 'codex_statusline.lua')), false);

    result = run([
      'configure', ...common, '--label', 'TEST', '--rows', '2', '--disable', 'provider',
      '--no-powerline',
      '--theme-bg', '#010203', '--theme-fg', '#f1f2f3',
      '--color', 'label:#112233:#ffffff', '--color', 'git:#223344:#aabbcc', '--json',
    ], env);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).status, 'changed');
    const configured = JSON.parse(fs.readFileSync(config, 'utf8'));
    assert.equal(configured.options.bottom_pane.rows, 2);
    assert.equal(configured.options.render.powerline, false);
    assert.equal(configured.options.theme.bg, '#010203');
    assert.deepEqual(configured.options.theme.segments.git, {bg: '#223344', fg: '#aabbcc'});

    configured.options.pricing = {models: {'gpt-5.6-sol': {input: 3, cached_input: 1, output: 5}}};
    const imported = path.join(root, 'custom-pricing.json');
    fs.writeFileSync(imported, JSON.stringify(configured));
    result = run(['configure', ...common, '--from', imported, '--json'], env);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(fs.readFileSync(config, 'utf8')).options.pricing, configured.options.pricing);

    result = run(['preview', ...common, '--json'], env);
    assert.equal(result.status, 0, result.stderr);
    assert.match(JSON.parse(result.stdout).preview, /gpt-5\.6-sol/);
    assert.match(JSON.parse(result.stdout).preview, /↑10M ↓204K/);
    assert.match(JSON.parse(result.stdout).preview, /Cache 60%/);
    assert.ok(JSON.parse(result.stdout).preview.includes('Cost ~$19.02'));

    result = run(['install', ...common, '--no-title-bridge', '--json'], env);
    assert.equal(result.status, 0, result.stderr);
    const manifest = JSON.parse(fs.readFileSync(path.join(codex, 'wezterm-statusline', 'bridge.json'), 'utf8'));
    assert.equal(manifest.schema, 4);
    assert.equal(manifest.package.runner, 'npx');
    const modules = fs.readdirSync(path.join(packageRoot, '..', '..', 'codex_statusline'), {recursive: true})
      .filter((name) => String(name).endsWith('.lua')).map((name) => path.join('codex_statusline', String(name)));
    for (const name of modules) {
      const installed = path.join(wezterm, name);
      assert.deepEqual(fs.readFileSync(installed), fs.readFileSync(path.join(packageRoot, '..', '..', name)));
      assert.ok(manifest.lua_modules.includes(installed));
    }

    const weztermConfig = path.join(wezterm, 'wezterm.lua');
    fs.writeFileSync(weztermConfig, 'require("codex_statusline").setup()\n');
    result = run(['doctor', ...common, '--json'], env);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).status, 'unchanged');

    fs.writeFileSync(config, '{invalid json');
    result = run(['doctor', ...common, '--json'], env);
    assert.equal(result.status, 1, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout).warnings, ['config']);
    fs.writeFileSync(config, `${JSON.stringify(configured, null, 2)}\n`);

    const installedCore = path.join(wezterm, 'codex_statusline_core.lua');
    const coreContent = fs.readFileSync(installedCore);
    fs.writeFileSync(installedCore, 'corrupted');
    result = run(['doctor', ...common, '--json'], env);
    assert.equal(result.status, 1, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout).warnings, ['asset_integrity']);
    fs.writeFileSync(installedCore, coreContent);
    const layoutFile = path.join(wezterm, 'codex_statusline', 'layout.lua');
    const layoutContent = fs.readFileSync(layoutFile);
    fs.rmSync(layoutFile);
    result = run(['doctor', ...common, '--json'], env);
    assert.equal(result.status, 1, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout).warnings, ['asset_integrity']);
    fs.writeFileSync(layoutFile, layoutContent);

    result = run(['uninstall', ...common, '--force'], env);
    assert.equal(result.status, 3);
    assert.match(result.stderr, /Remove require/);

    fs.rmSync(weztermConfig);
    result = run(['uninstall', ...common, '--json'], env);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.existsSync(config), true);
    for (const name of modules) assert.equal(fs.existsSync(path.join(wezterm, name)), false);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});
