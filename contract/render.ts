import packageInfo from '../packages/npm/package.json';
import {cacheRate, costText, estimateCost, isModelPrice, usageCounts, validPriceModel, type PricingConfig, type TokenUsage} from './pricing';

export const versionText = `v${packageInfo.version}`;

export const segmentIds = [
  'label',
  'model',
  'reasoning',
  'activity',
  'provider',
  'personality',
  'service_tier',
  'cwd',
  'project',
  'git',
  'permissions',
  'approval',
  'context',
  'context_used',
  'context_window',
  'used_tokens',
  'cache_rate',
  'cost',
  'input_tokens',
  'cached_tokens',
  'output_tokens',
  'reasoning_tokens',
  'thread_id',
  'task_progress',
  'codex_version',
  'icon',
] as const;

export const legacySegmentIds = [
  'label',
  'model',
  'reasoning',
  'provider',
  'cwd',
  'git',
  'context',
  'used_tokens',
] as const;

export type SegmentId = (typeof segmentIds)[number];
export type ModelDisplay = 'name' | 'icon_name' | 'icon';
export const modelIcons = {astra: '✦', sol: '☀', terra: '⊕', luna: '☾'} as const;
export type Layout = 'tiny' | 'narrow' | 'medium' | 'wide';
export type GoalStatus =
  | 'active'
  | 'paused'
  | 'blocked'
  | 'usageLimited'
  | 'budgetLimited'
  | 'complete';

export interface SegmentTheme {
  bg: string;
  fg: string;
}

export interface StatuslineConfig {
  schema: 1;
  options: {
    debug?: boolean;
    label: string;
    codex_home?: string;
    log?: {enabled: boolean; marker: string};
    compat?: {update_right_status: boolean};
    codex_config?: {enabled: boolean; path: string; cache_ttl_seconds: number};
    bottom_pane: {
      enabled?: boolean;
      rows: 1 | 2;
      layout_debounce_ms?: number;
      close_grace_seconds?: number;
      prevent_focus: boolean;
    };
    sessions: {
      enabled?: boolean;
      binding_mode: 'auto' | 'hook' | 'heuristic';
      bridge_dir?: string;
      allow_fallback_latest: boolean;
      resume_fallback_enabled?: boolean;
      resume_fallback_max_age_seconds?: number;
      resume_fallback_clock_skew_seconds?: number;
      resume_fallback_scan_ttl_seconds?: number;
      cache_ttl_seconds?: number;
      full_scan_ttl_seconds?: number;
      tail_ttl_seconds?: number;
      open_fail_clear_seconds?: number;
      initial_seek_bytes?: number;
      activity_seek_bytes?: number;
      activity_max_seek_bytes?: number;
      max_meta_lines?: number;
      max_tail_lines?: number;
    };
    git: {enabled: boolean; cache_ttl_seconds?: number};
    title_bridge: {enabled: boolean; app_name?: string};
    user_vars?: {
      model: string[];
      thinking: string[];
      provider: string[];
      active: string[];
    };
    process_match?: {
      enabled: boolean;
      names: string[];
      argv_markers: string[];
      terminal_names: string[];
      grace_seconds: number;
      tree_cache_ttl_seconds: number;
    };
    activity?: {
      labels: Record<
        | 'plan'
        | 'review'
        | 'goal_active'
        | 'goal_paused'
        | 'goal_blocked'
        | 'goal_usage_limited'
        | 'goal_budget_limited'
        | 'goal_complete',
        string
      >;
    };
    icon?: {text: string};
    pricing?: PricingConfig;
    render: {
      powerline: boolean;
      plain_fallback: boolean;
      model_display?: ModelDisplay;
      segment_order: SegmentId[];
      disabled_segments: SegmentId[];
    };
    theme: {
      bg: string;
      fg: string;
      dim: string;
      segments: Partial<Record<SegmentId, SegmentTheme>> & Record<(typeof legacySegmentIds)[number], SegmentTheme>;
      glyphs?: {sep: string; branch: string; folder: string};
    };
  };
}

export interface PreviewState {
  label?: string;
  model?: string;
  reasoning?: string;
  activity?: {
    mode?: 'default' | 'plan';
    review?: boolean;
    goal?: {
      status: GoalStatus;
      token_budget?: number;
      tokens_used?: number;
      time_used_seconds?: number;
    };
  };
  provider?: string;
  personality?: string;
  service_tier?: string;
  cwd?: string;
  project?: string;
  git?: string;
  permissions?: string;
  approval?: string;
  thread_id?: string;
  task_progress?: {completed?: number; total?: number};
  codex_version?: string;
  waiting?: string;
  usage?: TokenUsage & {
    total?: number;
    reasoning?: number;
    context_remaining_percent?: number;
    context_tokens?: number;
    context_window?: number;
  };
}

export interface RenderSegment extends SegmentTheme {
  kind: SegmentId | 'version';
  text: string;
}

export interface RenderPlan {
  layout: Layout;
  columns: number;
  lines: RenderSegment[][];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, keys: readonly string[]) {
  return Object.keys(value).every((key) => keys.includes(key));
}

function isColor(value: unknown): value is string {
  return typeof value === 'string' && /^#[0-9a-fA-F]{6}$/.test(value);
}

function isNumberInRange(value: unknown, min = 0, max = Number.POSITIVE_INFINITY) {
  return typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
}

function isIntegerInRange(value: unknown, min = 0, max = Number.MAX_SAFE_INTEGER) {
  return Number.isInteger(value) && (value as number) >= min && (value as number) <= max;
}

function isStringList(value: unknown) {
  return Array.isArray(value)
    && value.length >= 1
    && value.length <= 32
    && new Set(value).size === value.length
    && value.every((item) => typeof item === 'string' && item.length >= 1 && item.length <= 512);
}

function isSegmentList(value: unknown, minimum: number) {
  return Array.isArray(value)
    && value.length >= minimum
    && value.length <= segmentIds.length
    && new Set(value).size === value.length
    && value.every((id) => segmentIds.includes(id));
}

function validOptionalNumber(value: unknown, min = 0, max = Number.POSITIVE_INFINITY) {
  return value === undefined || isNumberInRange(value, min, max);
}

function validOptionalInteger(value: unknown, min = 0, max = Number.MAX_SAFE_INTEGER) {
  return value === undefined || isIntegerInRange(value, min, max);
}

export function isStatuslineConfig(value: unknown): value is StatuslineConfig {
  if (!isRecord(value) || !hasOnlyKeys(value, ['schema', 'options']) || value.schema !== 1 || !isRecord(value.options)) return false;
  const options = value.options;
  const optionKeys = [
    'debug', 'label', 'codex_home', 'log', 'compat', 'codex_config', 'bottom_pane', 'sessions',
    'git', 'title_bridge', 'user_vars', 'process_match', 'activity', 'icon', 'pricing', 'render', 'theme',
  ];
  if (!hasOnlyKeys(options, optionKeys)) return false;
  if (typeof options.label !== 'string' || options.label.length < 1 || options.label.length > 24) return false;
  if (options.debug !== undefined && typeof options.debug !== 'boolean') return false;
  if (options.codex_home !== undefined && (typeof options.codex_home !== 'string' || options.codex_home.length > 4096)) return false;

  if (options.log !== undefined) {
    if (!isRecord(options.log) || !hasOnlyKeys(options.log, ['enabled', 'marker'])) return false;
    if (typeof options.log.enabled !== 'boolean' || typeof options.log.marker !== 'string' || options.log.marker.length < 1 || options.log.marker.length > 128) return false;
  }
  if (options.compat !== undefined) {
    if (!isRecord(options.compat) || !hasOnlyKeys(options.compat, ['update_right_status']) || typeof options.compat.update_right_status !== 'boolean') return false;
  }
  if (options.codex_config !== undefined) {
    if (!isRecord(options.codex_config) || !hasOnlyKeys(options.codex_config, ['enabled', 'path', 'cache_ttl_seconds'])) return false;
    if (typeof options.codex_config.enabled !== 'boolean' || typeof options.codex_config.path !== 'string' || !isNumberInRange(options.codex_config.cache_ttl_seconds)) return false;
  }

  if (!isRecord(options.bottom_pane) || !hasOnlyKeys(options.bottom_pane, ['enabled', 'rows', 'layout_debounce_ms', 'close_grace_seconds', 'prevent_focus'])) return false;
  const debounce = options.bottom_pane.layout_debounce_ms;
  if (debounce !== undefined && (typeof debounce !== 'number' || !Number.isInteger(debounce) || debounce < 250 || debounce > 5000)) return false;
  if (![1, 2].includes(options.bottom_pane.rows as number) || typeof options.bottom_pane.prevent_focus !== 'boolean') return false;
  if (options.bottom_pane.enabled !== undefined && typeof options.bottom_pane.enabled !== 'boolean') return false;
  if (!validOptionalNumber(options.bottom_pane.close_grace_seconds)) return false;

  if (!isRecord(options.sessions) || !hasOnlyKeys(options.sessions, [
    'enabled', 'binding_mode', 'bridge_dir', 'allow_fallback_latest', 'resume_fallback_enabled',
    'resume_fallback_max_age_seconds', 'resume_fallback_clock_skew_seconds',
    'resume_fallback_scan_ttl_seconds', 'cache_ttl_seconds', 'full_scan_ttl_seconds',
    'tail_ttl_seconds', 'open_fail_clear_seconds', 'initial_seek_bytes', 'activity_seek_bytes',
    'activity_max_seek_bytes', 'max_meta_lines', 'max_tail_lines',
  ])) return false;
  if (!['auto', 'hook', 'heuristic'].includes(options.sessions.binding_mode as string) || typeof options.sessions.allow_fallback_latest !== 'boolean') return false;
  if (options.sessions.enabled !== undefined && typeof options.sessions.enabled !== 'boolean') return false;
  if (options.sessions.bridge_dir !== undefined && typeof options.sessions.bridge_dir !== 'string') return false;
  if (options.sessions.resume_fallback_enabled !== undefined && typeof options.sessions.resume_fallback_enabled !== 'boolean') return false;
  if (!validOptionalInteger(options.sessions.resume_fallback_max_age_seconds, 1, 300)) return false;
  if (!validOptionalInteger(options.sessions.resume_fallback_clock_skew_seconds, 0, 30)) return false;
  for (const key of ['resume_fallback_scan_ttl_seconds', 'cache_ttl_seconds', 'full_scan_ttl_seconds', 'tail_ttl_seconds', 'open_fail_clear_seconds'] as const) {
    if (!validOptionalNumber(options.sessions[key])) return false;
  }
  for (const key of ['initial_seek_bytes', 'activity_seek_bytes', 'activity_max_seek_bytes'] as const) {
    if (!validOptionalInteger(options.sessions[key])) return false;
  }
  if (!validOptionalInteger(options.sessions.max_meta_lines, 1, 10000) || !validOptionalInteger(options.sessions.max_tail_lines, 1, 100000)) return false;

  if (!isRecord(options.git) || !hasOnlyKeys(options.git, ['enabled', 'cache_ttl_seconds']) || typeof options.git.enabled !== 'boolean' || !validOptionalNumber(options.git.cache_ttl_seconds)) return false;
  if (!isRecord(options.title_bridge) || !hasOnlyKeys(options.title_bridge, ['enabled', 'app_name']) || typeof options.title_bridge.enabled !== 'boolean') return false;
  if (options.title_bridge.app_name !== undefined && (typeof options.title_bridge.app_name !== 'string' || options.title_bridge.app_name.length < 1 || options.title_bridge.app_name.length > 64)) return false;

  if (options.user_vars !== undefined) {
    const userVars = options.user_vars;
    if (!isRecord(userVars) || !hasOnlyKeys(userVars, ['model', 'thinking', 'provider', 'active'])) return false;
    if (!(['model', 'thinking', 'provider', 'active'] as const).every((key) => isStringList(userVars[key]))) return false;
  }
  if (options.process_match !== undefined) {
    if (!isRecord(options.process_match) || !hasOnlyKeys(options.process_match, ['enabled', 'names', 'argv_markers', 'terminal_names', 'grace_seconds', 'tree_cache_ttl_seconds'])) return false;
    if (typeof options.process_match.enabled !== 'boolean') return false;
    if (!isStringList(options.process_match.names) || !isStringList(options.process_match.argv_markers) || !isStringList(options.process_match.terminal_names)) return false;
    if (!isNumberInRange(options.process_match.grace_seconds) || !isNumberInRange(options.process_match.tree_cache_ttl_seconds)) return false;
  }
  if (options.activity !== undefined) {
    const activity = options.activity;
    const labelKeys = ['plan', 'review', 'goal_active', 'goal_paused', 'goal_blocked', 'goal_usage_limited', 'goal_budget_limited', 'goal_complete'] as const;
    if (!isRecord(activity) || !hasOnlyKeys(activity, ['labels'])) return false;
    const labels = activity.labels;
    if (!isRecord(labels) || !hasOnlyKeys(labels, labelKeys)) return false;
    if (!labelKeys.every((key) => typeof labels[key] === 'string' && labels[key].length >= 1 && labels[key].length <= 32)) return false;
  }
  if (options.icon !== undefined) {
    if (!isRecord(options.icon) || !hasOnlyKeys(options.icon, ['text']) || typeof options.icon.text !== 'string' || options.icon.text.length < 1 || options.icon.text.length > 8) return false;
  }
  if (options.pricing !== undefined) {
    const pricing = options.pricing;
    if (!isRecord(pricing) || !hasOnlyKeys(pricing, ['models']) || !isRecord(pricing.models)) return false;
    if (Object.keys(pricing.models).length > 64) return false;
    if (!Object.entries(pricing.models).every(([model, price]) => validPriceModel(model) && isModelPrice(price))) return false;
  }

  if (!isRecord(options.render) || !hasOnlyKeys(options.render, ['powerline', 'plain_fallback', 'model_display', 'segment_order', 'disabled_segments'])) return false;
  if (typeof options.render.powerline !== 'boolean' || typeof options.render.plain_fallback !== 'boolean') return false;
  if (options.render.model_display !== undefined && !['name', 'icon_name', 'icon'].includes(options.render.model_display as string)) return false;
  if (!isSegmentList(options.render.segment_order, 1) || !isSegmentList(options.render.disabled_segments, 0)) return false;

  const theme = options.theme;
  if (!isRecord(theme) || !hasOnlyKeys(theme, ['bg', 'fg', 'dim', 'segments', 'glyphs'])) return false;
  const themes = theme.segments;
  if (!isColor(theme.bg) || !isColor(theme.fg) || !isColor(theme.dim) || !isRecord(themes)) return false;
  if (!hasOnlyKeys(themes, segmentIds)) return false;
  if (!legacySegmentIds.every((id) => id in themes)) return false;
  for (const segmentTheme of Object.values(themes)) {
    if (!isRecord(segmentTheme) || !hasOnlyKeys(segmentTheme, ['bg', 'fg']) || !isColor(segmentTheme.bg) || !isColor(segmentTheme.fg)) return false;
  }
  if (theme.glyphs !== undefined) {
    const glyphs = theme.glyphs;
    if (!isRecord(glyphs) || !hasOnlyKeys(glyphs, ['sep', 'branch', 'folder'])) return false;
    if (!(['sep', 'branch', 'folder'] as const).every((key) => typeof glyphs[key] === 'string' && glyphs[key].length <= 8)) return false;
  }
  return true;
}

const dropOrder: SegmentId[] = [
  'provider', 'personality', 'service_tier', 'codex_version', 'thread_id', 'approval', 'permissions',
  'cached_tokens', 'reasoning_tokens', 'input_tokens', 'output_tokens', 'context_window', 'context_used',
  'task_progress', 'project', 'cwd', 'cache_rate', 'cost', 'used_tokens', 'git', 'reasoning', 'model',
];

export function compactNumber(value?: number): string | undefined {
  if (value === undefined || !Number.isFinite(value)) return undefined;
  const absolute = Math.abs(value);
  const sign = value < 0 ? '-' : '';
  if (absolute < 1000) return `${sign}${Math.round(absolute)}`;
  const units: Array<[number, string]> = [[1e12, 'T'], [1e9, 'B'], [1e6, 'M'], [1e3, 'K']];
  let unitIndex = units.findIndex(([candidate]) => absolute >= candidate);
  if (unitIndex < 0) return `${sign}${Math.round(absolute)}`;
  let [divisor, suffix] = units[unitIndex];
  const scaled = absolute / divisor;
  const digits = scaled < 10 ? 2 : scaled < 100 ? 1 : 0;
  let formatted = scaled.toFixed(digits);
  if (Number(formatted) >= 1000 && unitIndex > 0) {
    [divisor, suffix] = units[--unitIndex];
    const promoted = absolute / divisor;
    formatted = promoted.toFixed(promoted < 10 ? 2 : promoted < 100 ? 1 : 0);
  }
  return `${sign}${formatted.replace(/\.0+$|(?<=\.[0-9])0+$/, '')}${suffix}`;
}

export function contextBar(percent: number, cells: number): string {
  const safePercent = Math.max(0, Math.min(100, percent));
  const width = Math.max(1, Math.floor(cells));
  const filled = Math.max(0, Math.min(width, Math.round((safePercent / 100) * width)));
  return `${'█'.repeat(filled)}${'░'.repeat(width - filled)}`;
}

export function renderLayout(columns: number): Layout {
  if (columns < 60) return 'tiny';
  if (columns < 90) return 'narrow';
  if (columns < 120) return 'medium';
  return 'wide';
}

function activityText(config: StatuslineConfig, state: PreviewState) {
  const labels = config.options.activity?.labels;
  if (state.activity?.review) return labels?.review || 'REVIEW';
  if (state.activity?.mode === 'plan') return labels?.plan || 'PLAN';
  const goalStatus = state.activity?.goal?.status;
  if (!goalStatus) return undefined;
  const key: Record<GoalStatus, keyof NonNullable<StatuslineConfig['options']['activity']>['labels']> = {
    active: 'goal_active',
    paused: 'goal_paused',
    blocked: 'goal_blocked',
    usageLimited: 'goal_usage_limited',
    budgetLimited: 'goal_budget_limited',
    complete: 'goal_complete',
  };
  return labels?.[key[goalStatus]] || {
    active: 'GOAL', paused: 'GOAL PAUSED', blocked: 'GOAL BLOCKED', usageLimited: 'GOAL LIMITED',
    budgetLimited: 'GOAL BUDGET', complete: 'GOAL DONE',
  }[goalStatus];
}

function modelText(model: string | undefined, display: ModelDisplay = 'name') {
  if (!model || display === 'name') return model;
  for (const token of model.toLowerCase().match(/[a-z0-9]+/g) ?? []) {
    if (!Object.prototype.hasOwnProperty.call(modelIcons, token)) continue;
    const icon = modelIcons[token as keyof typeof modelIcons];
    return display === 'icon' ? icon : `${icon} ${model}`;
  }
  return model;
}

function segmentText(id: SegmentId, config: StatuslineConfig, state: PreviewState, layout: Layout) {
  if (id === 'label') return state.label || config.options.label || 'CODEX';
  if (id === 'model') return modelText(state.model, config.options.render.model_display);
  if (id === 'reasoning') return state.reasoning;
  if (id === 'activity') return activityText(config, state);
  if (id === 'provider') return layout === 'wide' && state.provider ? `p:${state.provider}` : state.provider;
  if (id === 'personality') return state.personality ? `persona:${state.personality}` : undefined;
  if (id === 'service_tier') return state.service_tier ? `tier:${state.service_tier}` : undefined;
  if (id === 'cwd') return state.cwd;
  if (id === 'project') return state.project;
  if (id === 'git') return state.git;
  if (id === 'permissions') return state.permissions;
  if (id === 'approval') return state.approval;
  if (id === 'thread_id') return state.thread_id ? `id:${state.thread_id.slice(0, 8)}` : undefined;
  if (id === 'task_progress') {
    const completed = state.task_progress?.completed;
    const total = state.task_progress?.total;
    return completed !== undefined && total ? `Tasks ${completed}/${total}` : undefined;
  }
  if (id === 'codex_version') return state.codex_version ? `v${state.codex_version.replace(/^v/, '')}` : undefined;
  if (id === 'icon') return config.options.icon?.text || '';

  const usage = state.usage;
  if (id === 'context') {
    if (!usage) return state.waiting;
    const percent = usage.context_remaining_percent;
    if (percent !== undefined) {
      const rounded = Math.max(0, Math.min(100, Math.round(percent)));
      if (layout === 'wide' || layout === 'medium') return `Ctx ${contextBar(rounded, layout === 'wide' ? 10 : 8)} ${rounded}% left`;
      return layout === 'narrow' ? `Ctx ${rounded}% left` : `Ctx ${rounded}%`;
    }
    const current = compactNumber(usage.context_tokens);
    return current ? `Ctx ${current}` : state.waiting;
  }
  if (id === 'context_used' && usage?.context_remaining_percent !== undefined) return `Ctx ${Math.max(0, Math.min(100, 100 - Math.round(usage.context_remaining_percent)))}% used`;
  if (id === 'context_window') {
    const value = compactNumber(usage?.context_window);
    return value ? `${value} window` : undefined;
  }
  if (id === 'used_tokens') {
    if (!usage) return undefined;
    const counts = usageCounts(usage);
    if (counts.input === undefined && counts.output === undefined) return undefined;
    return `↑${compactNumber(counts.input) ?? '—'} ↓${compactNumber(counts.output) ?? '—'}`;
  }
  if (id === 'cache_rate') {
    if (!usage) return undefined;
    const rate = cacheRate(usage);
    return rate === undefined ? 'Cache —' : `Cache ${rate}%`;
  }
  if (id === 'cost') {
    return usage ? costText(estimateCost(state.model, usage, config.options.pricing)) : undefined;
  }
  if (id === 'input_tokens') {
    const value = usage && compactNumber(usageCounts(usage).input);
    return value ? `↑${value}` : undefined;
  }
  if (id === 'cached_tokens') {
    const value = compactNumber(usage?.cached);
    return value && value !== '0' ? `${value} cached` : undefined;
  }
  if (id === 'output_tokens') {
    const value = compactNumber(usage?.output);
    return value ? `↓${value}` : undefined;
  }
  if (id === 'reasoning_tokens') {
    const value = compactNumber(usage?.reasoning);
    return value && value !== '0' ? `${value} reasoning` : undefined;
  }
  return undefined;
}

function planWidth(segments: RenderSegment[], powerline: boolean) {
  return segments.reduce((width, segment, index) => width + Array.from(segment.text).length + (powerline ? 2 : 0) + (index ? (powerline ? 1 : 2) : 0), 0);
}

function fitSegments(segments: RenderSegment[], columns: number, powerline: boolean) {
  let result = [...segments];
  for (const id of dropOrder) {
    if (planWidth(result, powerline) <= columns) break;
    result = result.filter((segment) => segment.kind !== id);
  }
  return result;
}

function themeFor(config: StatuslineConfig, id: SegmentId): SegmentTheme {
  return config.options.theme.segments[id] || {bg: config.options.theme.bg, fg: config.options.theme.fg};
}

function withVersion(segments: RenderSegment[], config: StatuslineConfig): RenderSegment[] {
  const theme = config.options.theme;
  return [...segments, {kind: 'version', text: versionText, bg: theme.bg, fg: theme.dim || theme.fg}];
}

export function buildRenderPlan(config: StatuslineConfig, state: PreviewState, columns: number): RenderPlan {
  const safeColumns = Math.max(1, Math.floor(columns || 120));
  const layout = renderLayout(safeColumns);
  const disabled = new Set(config.options.render.disabled_segments || []);
  const hidden = new Set<SegmentId>(layout === 'tiny'
    ? ['reasoning', 'provider', 'personality', 'service_tier', 'cwd', 'project', 'git', 'permissions', 'approval', 'context_used', 'context_window', 'used_tokens', 'cache_rate', 'cost', 'input_tokens', 'cached_tokens', 'output_tokens', 'reasoning_tokens', 'thread_id', 'task_progress', 'codex_version']
    : layout === 'narrow'
      ? ['provider', 'personality', 'service_tier', 'project', 'permissions', 'approval', 'context_used', 'context_window', 'cache_rate', 'cost', 'input_tokens', 'cached_tokens', 'output_tokens', 'reasoning_tokens', 'thread_id', 'task_progress', 'codex_version']
      : []);
  const configured = config.options.render.segment_order || segmentIds;
  const isLegacyOrder = configured.every((id) => legacySegmentIds.includes(id as (typeof legacySegmentIds)[number]));
  const appendable = isLegacyOrder ? ['activity', 'icon'] as SegmentId[] : segmentIds.filter((id) => !configured.includes(id));
  const expanded = [...configured, ...appendable.filter((id) => !configured.includes(id))];
  const order = [...expanded.filter((id) => id !== 'icon'), ...expanded.filter((id) => id === 'icon')];
  const segments = order.flatMap((id) => {
    if (disabled.has(id) || hidden.has(id)) return [];
    const text = segmentText(id, config, state, layout);
    if (!text) return [];
    return [{kind: id, text, ...themeFor(config, id)}];
  });

  if (config.options.bottom_pane.rows === 1) {
    return {layout, columns: safeColumns, lines: [fitSegments(withVersion(segments, config), safeColumns, config.options.render.powerline)]};
  }
  const usageIds = new Set<SegmentId>(['context', 'context_used', 'context_window', 'used_tokens', 'cache_rate', 'cost', 'input_tokens', 'cached_tokens', 'output_tokens', 'reasoning_tokens']);
  return {
    layout,
    columns: safeColumns,
    lines: [
      fitSegments(withVersion(segments.filter(({kind}) => !usageIds.has(kind)), config), safeColumns, config.options.render.powerline),
      fitSegments(segments.filter(({kind}) => usageIds.has(kind)), safeColumns, config.options.render.powerline),
    ],
  };
}
