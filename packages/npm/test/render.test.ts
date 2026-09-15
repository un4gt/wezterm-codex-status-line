import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {
  buildRenderPlan,
  compactNumber,
  isStatuslineConfig,
  segmentIds,
  versionText,
  type StatuslineConfig,
} from '../../../contract/render.ts';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const defaults = JSON.parse(fs.readFileSync(path.join(root, 'contract', 'default-config.json'), 'utf8')) as StatuslineConfig;
const sample = JSON.parse(fs.readFileSync(path.join(root, 'contract', 'sample-state.json'), 'utf8'));
const cases = JSON.parse(fs.readFileSync(path.join(root, 'contract', 'render-cases.json'), 'utf8'));
const usageCases = JSON.parse(fs.readFileSync(path.join(root, 'contract', 'usage-cases.json'), 'utf8'));

test('compact token formatting', () => {
  assert.equal(compactNumber(999), '999');
  assert.equal(compactNumber(999950), '1M');
  assert.equal(compactNumber(4203817), '4.2M');
});

test('configuration shape validation', () => {
  assert.equal(isStatuslineConfig(defaults), true);
  assert.deepEqual(defaults.options.render.segment_order, [...segmentIds]);
  assert.equal(new Set(defaults.options.render.segment_order).size, segmentIds.length);
  assert.equal(defaults.options.render.segment_order.at(-1), 'icon');
  assert.equal(defaults.options.icon?.text, '');
  const missingTheme = structuredClone(defaults) as any;
  delete missingTheme.options.theme;
  assert.equal(isStatuslineConfig(missingTheme), false);
  const invalidColor = structuredClone(defaults);
  invalidColor.options.theme.segments.git.fg = 'green';
  assert.equal(isStatuslineConfig(invalidColor), false);
  const invalidResumeWindow = structuredClone(defaults);
  invalidResumeWindow.options.sessions.resume_fallback_max_age_seconds = 0;
  assert.equal(isStatuslineConfig(invalidResumeWindow), false);
});

test('project icon precedes the installed plugin version', () => {
  const config = structuredClone(defaults);
  config.options.render.segment_order = [
    'icon',
    ...config.options.render.segment_order.filter((id) => id !== 'icon'),
  ];
  const plan = buildRenderPlan(config, sample, 140);
  assert.equal(plan.lines[0].at(-2)?.kind, 'icon');
  assert.equal(plan.lines[0].at(-1)?.kind, 'version');
  assert.equal(plan.lines[0].at(-1)?.text, versionText);
});

test('model display is optional and accepts only supported modes', () => {
  const config = structuredClone(defaults) as any;
  assert.equal(config.options.render.model_display, 'name');
  delete config.options.render.model_display;
  assert.equal(isStatuslineConfig(config), true);
  for (const value of ['name', 'icon_name', 'icon', 'auto', '', true, 1, null]) {
    config.options.render.model_display = value;
    assert.equal(isStatuslineConfig(config), ['name', 'icon_name', 'icon'].includes(value as string));
  }
});

test('model display follows the active model and preserves unknown names', () => {
  const config = structuredClone(defaults);
  const examples = [
    ['gpt-6-astra', '✦'], ['gpt-5.6-sol', '☀'],
    ['openai/gpt-5.6-terra', '⊕'], ['GPT-5.6-LUNA', '☾'],
    ['Astra', '✦'], ['Sol', '☀'], ['Terra', '⊕'], ['Luna', '☾'],
    ['gpt-5.6-codex', undefined], ['solar', undefined], ['terramodel', undefined],
    ['lunatic', undefined], ['toString', undefined], ['', undefined], [undefined, undefined],
  ] as const;
  for (const display of [undefined, 'name', 'icon_name', 'icon'] as const) {
    config.options.render.model_display = display;
    for (const [model, icon] of examples) {
      const expected = !model ? undefined : !icon || !display || display === 'name'
        ? model : display === 'icon' ? icon : `${icon} ${model}`;
      for (const columns of [50, 140]) {
        const plan = buildRenderPlan(config, {model}, columns);
        assert.equal(plan.lines.flat().find((segment) => segment.kind === 'model')?.text,
          expected, `${model}, ${display}, ${columns}`);
      }
    }
  }
  config.options.render.disabled_segments.push('model');
  assert.equal(buildRenderPlan(config, {model: 'gpt-6-astra'}, 140)
    .lines.flat().some((segment) => segment.kind === 'model'), false);
});

test('optional layout debounce retains schema 1 compatibility', () => {
  const old = structuredClone(defaults);
  delete old.options.bottom_pane.layout_debounce_ms;
  assert.equal(isStatuslineConfig(old), true);
  for (const value of [250, 1000, 5000, 249, 5001, 250.5, '1000', null]) {
    const config = structuredClone(defaults) as any;
    config.options.bottom_pane.layout_debounce_ms = value;
    assert.equal(isStatuslineConfig(config), [250, 1000, 5000].includes(value as number));
  }
});

test('pricing overrides validate and preserve schema 1 compatibility', () => {
  const config = structuredClone(defaults) as any;
  delete config.options.pricing;
  assert.equal(isStatuslineConfig(config), true);
  config.options.pricing = {models: {'my-model': {input: 0, cached_input: 0.01, output: 2}}};
  assert.equal(isStatuslineConfig(config), true);
  for (const value of [-1, 1000001, null, '1', true, Infinity, NaN]) {
    config.options.pricing.models['my-model'].input = value;
    assert.equal(isStatuslineConfig(config), false, String(value));
  }
  for (const pricing of [{}, {models: []}, {models: {'Bad Model': {input: 1, cached_input: 0, output: 2}}},
    {models: {'my-model': {input: 1, output: 2}}}]) {
    config.options.pricing = pricing;
    assert.equal(isStatuslineConfig(config), false);
  }
});

for (const fixture of usageCases) {
  test(`usage and cost: ${fixture.name}`, () => {
    const config = structuredClone(defaults);
    config.options.pricing = fixture.pricing;
    const state = {model: fixture.model, usage: fixture.usage};
    for (const rows of [1, 2] as const) {
      for (const powerline of [true, false]) {
        config.options.bottom_pane.rows = rows;
        config.options.render.powerline = powerline;
        const plan = buildRenderPlan(config, state, 180);
        const usageLine = plan.lines[rows - 1];
        const actual = ['used_tokens', 'cache_rate', 'cost'].map((id) => usageLine.find((segment) => segment.kind === id)?.text);
        assert.deepEqual(actual, fixture.expected);
      }
    }
    config.options.render.disabled_segments.push('cache_rate', 'cost');
    assert.equal(buildRenderPlan(config, state, 180).lines.flat().some((segment) => ['cache_rate', 'cost'].includes(segment.kind)), false);
  });
}

for (const fixture of cases) {
  test(`render contract: ${fixture.name}`, () => {
    const config = structuredClone(defaults);
    if (fixture.patch.rows) config.options.bottom_pane.rows = fixture.patch.rows;
    if (fixture.patch.modelDisplay) config.options.render.model_display = fixture.patch.modelDisplay;
    if (fixture.patch.disabledAdd) {
      config.options.render.disabled_segments = [
        ...new Set([...config.options.render.disabled_segments, ...fixture.patch.disabledAdd]),
      ];
    }
    const state = structuredClone(sample);
    if (fixture.state) Object.assign(state, fixture.state);
    const plan = buildRenderPlan(config, state, fixture.columns);
    const actual = {
      layout: plan.layout,
      lines: plan.lines.map((line) => line.map((segment) => [segment.kind, segment.text])),
    };
    const expected = JSON.parse(JSON.stringify(fixture.expected).replaceAll('$version', versionText));
    assert.deepEqual(actual, expected);
  });
}
