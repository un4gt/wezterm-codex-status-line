import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(root, 'contract', 'config.schema.json');
const target = path.join(root, 'website', 'static', 'config.schema.json');

fs.mkdirSync(path.dirname(target), {recursive: true});
fs.copyFileSync(source, target);
