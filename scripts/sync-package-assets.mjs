import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import './sync-model-pricing.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const packageVersion = JSON.parse(fs.readFileSync(path.join(root, 'packages/npm/package.json'), 'utf8')).version;
for (const [file, pattern] of [
  ['packages/python/pyproject.toml', /^version = "([^"]+)"/m],
  ['packages/python/src/wezterm_codex_status_line/__init__.py', /^__version__ = "([^"]+)"/m],
  ['codex_statusline/version.lua', /version = "([^"]+)"/],
  ['install.ps1', /\$PackageVersion = '([^']+)'/],
]) {
  const version = fs.readFileSync(path.join(root, file), 'utf8').match(pattern)?.[1];
  if (version !== packageVersion) throw new Error(`${file}: version ${version} does not match package ${packageVersion}`);
}
const assets = [
  ...fs.readdirSync(path.join(root, 'codex_statusline'), {recursive: true})
    .filter((file) => file.endsWith('.lua'))
    .map((file) => path.join('codex_statusline', file)),
  'codex_statusline.lua',
  'codex_statusline_core.lua',
  'codex_statusline_bridge.ps1',
  'codex_statusline_bridge.py',
  'codex_statusline_bridge.js',
  'install.ps1',
];
const contract = ['config.schema.json', 'default-config.json', 'sample-state.json', 'render-cases.json', 'model-pricing.json', 'usage-cases.json'];
const targets = [
  path.join(root, 'packages', 'npm', 'assets'),
  path.join(root, 'packages', 'python', 'src', 'wezterm_codex_status_line', 'assets'),
];

for (const target of targets) {
  fs.rmSync(target, {recursive: true, force: true});
  fs.mkdirSync(path.join(target, 'contract'), {recursive: true});
  for (const file of assets) {
    fs.mkdirSync(path.dirname(path.join(target, file)), {recursive: true});
    fs.copyFileSync(path.join(root, file), path.join(target, file));
  }
  for (const file of contract) fs.copyFileSync(path.join(root, 'contract', file), path.join(target, 'contract', file));
}
