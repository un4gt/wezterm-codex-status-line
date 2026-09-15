import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const data = JSON.parse(fs.readFileSync(path.join(root, 'contract/model-pricing.json'), 'utf8'));
const rows = Object.entries(data.models).map(([model, price]) => {
  if (!/^[a-z0-9][a-z0-9._-]*$/.test(model)
      || !['input', 'cached_input', 'output'].every((key) => Number.isFinite(price[key]) && price[key] >= 0)) {
    throw new Error(`Invalid built-in model price: ${model}`);
  }
  return `  ["${model}"] = { input = ${price.input}, cached_input = ${price.cached_input}, output = ${price.output} },`;
});
const target = path.join(root, 'codex_statusline/domain/prices.lua');
const content = `-- Generated from contract/model-pricing.json by scripts/sync-model-pricing.mjs.\n-- ${data.source} (verified ${data.verified_at}; USD / 1M tokens, standard short context)\nreturn {\n${rows.join('\n')}\n}\n`;
if (!fs.existsSync(target) || fs.readFileSync(target, 'utf8') !== content) fs.writeFileSync(target, content);
