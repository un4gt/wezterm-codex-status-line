import type {ChangeEvent, CSSProperties, ReactNode} from 'react';
import {useEffect, useMemo, useRef, useState} from 'react';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import {
  Activity,
  ArrowDown,
  ArrowUp,
  Check,
  Clipboard,
  Download,
  Link2,
  Palette,
  RotateCcw,
  Settings2,
  Sliders,
  Upload,
} from 'lucide-react';
import defaultConfigJson from '../../../contract/default-config.json';
import sampleStateJson from '../../../contract/sample-state.json';
import {
  buildRenderPlan,
  isStatuslineConfig,
  legacySegmentIds,
  modelIcons,
  segmentIds,
  type GoalStatus,
  type ModelDisplay,
  type PreviewState,
  type RenderSegment,
  type SegmentId,
  type SegmentTheme,
  type StatuslineConfig,
} from '../../../contract/render';

import styles from './preview.module.css';
import ModelPricing from '../components/ModelPricing';

const DEFAULT_COLUMNS = 120;
const modelPresets = [
  {family: 'astra', label: 'Astra', model: 'gpt-6-astra'},
  {family: 'sol', label: 'Sol', model: 'gpt-5.6-sol'},
  {family: 'terra', label: 'Terra', model: 'gpt-5.6-terra'},
  {family: 'luna', label: 'Luna', model: 'gpt-5.6-luna'},
] as const;

const segmentMeta: Record<SegmentId, {label: string; description: string}> = {
  label: {label: '标识', description: '固定状态栏前缀'},
  model: {label: '模型', description: '当前会话的模型'},
  reasoning: {label: '推理强度', description: '当前推理强度'},
  activity: {label: '特殊状态', description: 'Review、Plan 或 Goal'},
  provider: {label: '模型服务商', description: '当前模型服务商'},
  personality: {label: '人格设置', description: '当前人格配置'},
  service_tier: {label: '服务等级', description: '当前服务等级'},
  cwd: {label: '工作目录', description: '当前会话的工作目录'},
  project: {label: '项目名', description: 'Git 根目录名称'},
  git: {label: 'Git 分支', description: '当前分支'},
  permissions: {label: '沙箱权限', description: '当前沙箱权限'},
  approval: {label: '审批策略', description: '当前审批策略'},
  context: {label: '上下文剩余', description: '剩余比例与容量条'},
  context_used: {label: '上下文已用', description: '已用上下文比例'},
  context_window: {label: '上下文窗口', description: '模型窗口上限'},
  used_tokens: {label: '输入 / 输出', description: '↑ 累计输入（含缓存） · ↓ 累计输出'},
  cache_rate: {label: '缓存率', description: '缓存输入占总输入的比例'},
  cost: {label: '估算费用', description: '按各次请求使用的模型分别累计 Token 费用'},
  input_tokens: {label: '输入 Token', description: '累计输入，包含缓存'},
  cached_tokens: {label: '缓存 Token', description: '累计缓存输入'},
  output_tokens: {label: '输出 Token', description: '累计输出'},
  reasoning_tokens: {label: '推理 Token', description: '累计推理输出'},
  thread_id: {label: '会话 ID', description: '会话 ID 前 8 位'},
  task_progress: {label: '任务进度', description: '仅用于预览，实际会话不提供此字段'},
  codex_version: {label: 'Codex 版本', description: '当前 CLI 版本'},
  icon: {label: '项目图标', description: '固定在右侧插件版本号之前'},
};

const goalOptions: Array<{value: GoalStatus; label: string}> = [
  {value: 'active', label: '进行中'},
  {value: 'paused', label: '已暂停'},
  {value: 'blocked', label: '已阻塞'},
  {value: 'usageLimited', label: '用量受限'},
  {value: 'budgetLimited', label: '预算受限'},
  {value: 'complete', label: '已完成'},
];

const activityLabelFields = [
  ['plan', 'Plan'],
  ['review', 'Review'],
  ['goal_active', 'Goal active'],
  ['goal_paused', 'Goal paused'],
  ['goal_blocked', 'Goal blocked'],
  ['goal_usage_limited', 'Goal usage limited'],
  ['goal_budget_limited', 'Goal budget limited'],
  ['goal_complete', 'Goal complete'],
] as const;

function cloneConfig(): StatuslineConfig {
  return structuredClone(defaultConfigJson) as StatuslineConfig;
}

function cloneSample(): PreviewState {
  return structuredClone(sampleStateJson) as PreviewState;
}

function mergeConfigDefaults(defaults: unknown, value: unknown): unknown {
  if (Array.isArray(value)) return structuredClone(value);
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    const result = structuredClone(
      defaults && typeof defaults === 'object' && !Array.isArray(defaults) ? defaults : {},
    ) as Record<string, unknown>;
    for (const [key, child] of Object.entries(value)) {
      result[key] = mergeConfigDefaults(result[key], child);
    }
    return result;
  }
  return value === undefined ? structuredClone(defaults) : value;
}

function hydrateConfig(value: StatuslineConfig): StatuslineConfig {
  const hydrated = mergeConfigDefaults(defaultConfigJson, value) as StatuslineConfig;
  const configured = [...value.options.render.segment_order];
  const missing = segmentIds.filter((id) => !configured.includes(id));
  const legacy = configured.length > 0
    && configured.every((id) => legacySegmentIds.includes(id as (typeof legacySegmentIds)[number]));
  const expanded = [...configured, ...missing];
  hydrated.options.render.segment_order = [
    ...expanded.filter((id) => id !== 'icon'),
    ...expanded.filter((id) => id === 'icon'),
  ];
  if (legacy) {
    hydrated.options.render.disabled_segments = [
      ...new Set([
        ...hydrated.options.render.disabled_segments,
        ...missing.filter((id) => id !== 'activity' && id !== 'icon'),
      ]),
    ];
  }
  return hydrated;
}

function encodeConfig(config: StatuslineConfig) {
  const bytes = new TextEncoder().encode(JSON.stringify(config));
  let binary = '';
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

function decodeConfig(value: string): StatuslineConfig {
  const normalized = value.replaceAll('-', '+').replaceAll('_', '/');
  const binary = atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '='));
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  const parsed = JSON.parse(new TextDecoder().decode(bytes));
  if (!isStatuslineConfig(parsed)) throw new Error('Invalid config');
  return hydrateConfig(parsed);
}

function StringListEditor({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string[];
  onChange: (value: string[]) => void;
}): ReactNode {
  const [draft, setDraft] = useState(value.join('\n'));

  useEffect(() => setDraft(value.join('\n')), [value]);

  const commit = () => {
    const next = draft
      .split(/[\n,]/)
      .map((item) => item.trim())
      .filter(Boolean);
    if (next.length) onChange([...new Set(next)]);
    else setDraft(value.join('\n'));
  };

  return (
    <label className={styles.stackField}>
      <span>{label}</span>
      <textarea
        value={draft}
        rows={3}
        onChange={(event) => setDraft(event.target.value)}
        onBlur={commit}
      />
    </label>
  );
}

function ToggleField({
  label,
  configKey,
  checked,
  onChange,
}: {
  label: string;
  configKey: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}): ReactNode {
  return (
    <label className={styles.toggleField}>
      <span>
        <strong>{label}</strong>
        <code>{configKey}</code>
      </span>
      <input
        type="checkbox"
        role="switch"
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
      />
    </label>
  );
}

function SectionTitle({icon, title, badge}: {icon: ReactNode; title: string; badge?: string}): ReactNode {
  return (
    <div className={styles.sectionTitle}>
      <span className={styles.sectionIcon}>{icon}</span>
      <Heading as="h2">{title}</Heading>
      {badge ? <span className={styles.sectionBadge}>{badge}</span> : null}
    </div>
  );
}

function StatusRail({
  config,
  state,
  columns,
}: {
  config: StatuslineConfig;
  state: PreviewState;
  columns: number;
}): ReactNode {
  const plan = useMemo(() => buildRenderPlan(config, state, columns), [config, state, columns]);
  const renderSegment = (segment: RenderSegment, next?: RenderSegment) => {
    const style = {
      '--segment-bg': segment.bg,
      '--segment-fg': segment.fg,
      '--next-bg': next?.bg || config.options.theme.bg,
    } as CSSProperties;
    return (
      <span
        className={`${styles.previewSegment} ${
          config.options.render.powerline ? styles.powerlineSegment : ''
        } ${segment.kind === 'icon' || segment.kind === 'version' ? styles.previewIcon : ''}`}
        style={style}
        key={segment.kind}>
        {segment.text}
      </span>
    );
  };
  return (
    <div
      className={styles.terminalPreview}
      style={{'--preview-bg': config.options.theme.bg} as CSSProperties}>
      {plan.lines.map((line, lineIndex) => {
        const right = line.filter((segment) => segment.kind === 'icon' || segment.kind === 'version');
        const left = line.filter((segment) => segment.kind !== 'icon' && segment.kind !== 'version');
        return (
          <div className={styles.previewLine} key={`${lineIndex}-${plan.layout}`}>
            <div className={styles.previewSegments}>
              {left.map((segment, index) => renderSegment(segment, left[index + 1]))}
            </div>
            <div className={styles.previewSegments}>
              {right.map((segment) => renderSegment(segment))}
            </div>
          </div>
        );
      })}
    </div>
  );
}

export default function PreviewPage(): ReactNode {
  const [config, setConfig] = useState<StatuslineConfig>(cloneConfig);
  const [sample, setSample] = useState<PreviewState>(cloneSample);
  const [columns, setColumns] = useState(DEFAULT_COLUMNS);
  const [notice, setNotice] = useState('');
  const importRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const encoded = new URLSearchParams(window.location.search).get('config');
    if (!encoded) return;
    try {
      setConfig(decodeConfig(encoded));
    } catch {
      setNotice('链接中的配置无效，已使用默认配置。');
    }
  }, []);

  const showToast = (message: string) => {
    setNotice(message);
    window.setTimeout(() => {
      setNotice((current) => (current === message ? '' : current));
    }, 3000);
  };

  const updateOptions = (mutate: (next: StatuslineConfig) => void) => {
    setConfig((current) => {
      const next = structuredClone(current);
      mutate(next);
      return next;
    });
  };

  const updateSample = (key: keyof PreviewState, value: string) => {
    setSample((current) => ({...current, [key]: value}));
  };

  const updateUsage = (key: keyof NonNullable<PreviewState['usage']>, value: number) => {
    setSample((current) => {
      const usage = {...current.usage, [key]: Math.max(0, value)};
      if (key === 'input_raw' || key === 'cached' || key === 'output') {
        usage.cached = Math.min(usage.cached ?? 0, usage.input_raw ?? 0);
        usage.input = Math.max(0, (usage.input_raw ?? 0) - usage.cached);
        usage.total = usage.input + (usage.output ?? 0);
      }
      return {...current, usage};
    });
  };

  const updateActivity = (mutate: (activity: NonNullable<PreviewState['activity']>) => void) => {
    setSample((current) => {
      const activity: NonNullable<PreviewState['activity']> = structuredClone(
        current.activity ?? {mode: 'default', review: false},
      );
      mutate(activity);
      return {...current, activity};
    });
  };

  const moveSegment = (id: SegmentId, direction: -1 | 1) => {
    updateOptions((next) => {
      const order = next.options.render.segment_order;
      const from = order.indexOf(id);
      const to = from + direction;
      if (id === 'icon' || from < 0 || to < 0 || to >= order.length || order[to] === 'icon') return;
      [order[from], order[to]] = [order[to], order[from]];
    });
  };

  const toggleSegment = (id: SegmentId) => {
    updateOptions((next) => {
      const disabled = new Set(next.options.render.disabled_segments);
      if (disabled.has(id)) disabled.delete(id);
      else disabled.add(id);
      next.options.render.disabled_segments = [...disabled];
    });
  };

  const themeFor = (id: SegmentId): SegmentTheme =>
    config.options.theme.segments[id] ?? {
      bg: config.options.theme.bg,
      fg: config.options.theme.fg,
    };

  const copyShareLink = async () => {
    if (!isStatuslineConfig(config)) {
      showToast('当前配置未通过校验，请检查空标签或数值范围。');
      return;
    }
    const url = new URL(window.location.href);
    url.search = `?config=${encodeConfig(config)}`;
    try {
      await navigator.clipboard.writeText(url.toString());
      showToast('分享链接已复制。');
    } catch {
      showToast('浏览器未允许写入剪贴板。');
    }
  };

  const copyConfig = async () => {
    if (!isStatuslineConfig(config)) {
      showToast('当前配置未通过校验，请检查空标签或数值范围。');
      return;
    }
    try {
      await navigator.clipboard.writeText(`${JSON.stringify(config, null, 2)}\n`);
      showToast('配置 JSON 已复制。');
    } catch {
      showToast('浏览器未允许写入剪贴板。');
    }
  };

  const downloadConfig = () => {
    if (!isStatuslineConfig(config)) {
      showToast('当前配置未通过校验，请检查空标签或数值范围。');
      return;
    }
    const blob = new Blob([`${JSON.stringify(config, null, 2)}\n`], {type: 'application/json'});
    const anchor = document.createElement('a');
    const objectUrl = URL.createObjectURL(blob);
    anchor.href = objectUrl;
    anchor.download = 'codex_statusline_config.json';
    anchor.click();
    URL.revokeObjectURL(objectUrl);
    showToast('已开始下载 JSON。按配置指南导入后，重新加载 WezTerm 配置。');
  };

  const importConfig = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    try {
      const parsed = JSON.parse(await file.text());
      if (!isStatuslineConfig(parsed)) throw new Error();
      setConfig(hydrateConfig(parsed));
      showToast('配置已导入。');
    } catch {
      showToast('导入失败：请选择完整的状态栏配置 JSON，或重新下载后再试。');
    }
  };

  const resetAll = () => {
    setConfig(cloneConfig());
    setSample(cloneSample());
    setColumns(DEFAULT_COLUMNS);
    const url = new URL(window.location.href);
    url.searchParams.delete('config');
    window.history.replaceState({}, '', url);
    showToast('配置、模拟数据与终端宽度已恢复默认值。');
  };

  const enabledCount = config.options.render.segment_order.length
    - config.options.render.disabled_segments.length;
  const effectiveActivity = sample.activity?.review
    ? 'REVIEW'
    : sample.activity?.mode === 'plan'
      ? 'PLAN'
      : sample.activity?.goal
        ? `GOAL / ${sample.activity.goal.status}`
        : 'DEFAULT';

  return (
    <Layout title="交互预览" description="配置并实时预览 WezTerm Codex Status Line。">
      <main className={styles.page}>
        <header className={styles.header}>
          <div className="container">
            <span className={styles.kicker}>INTERACTIVE PREVIEW</span>
            <div className={styles.headerRow}>
              <div>
                <Heading as="h1">状态栏配置与预览</Heading>
                <p>{enabledCount}/{segmentIds.length} 字段启用 · {columns} 列 · {config.options.bottom_pane.rows} 行</p>
                <p>调整显示后下载 JSON，再<Link to="/docs/guides/configuration#导入网页配置">导入本机配置</Link>。下方使用模拟会话数据。</p>
              </div>
              <div className={styles.commands}>
                <button type="button" className={styles.commandButton} onClick={copyShareLink}>
                  <Link2 size={16} aria-hidden="true" />
                  <span>分享链接</span>
                </button>
                <button type="button" className={styles.commandButton} onClick={copyConfig}>
                  <Clipboard size={16} aria-hidden="true" />
                  <span>复制 JSON</span>
                </button>
                <button type="button" className={styles.commandButton} onClick={downloadConfig}>
                  <Download size={16} aria-hidden="true" />
                  <span>下载 JSON</span>
                </button>
                <button type="button" className={styles.commandButton} onClick={() => importRef.current?.click()}>
                  <Upload size={16} aria-hidden="true" />
                  <span>导入 JSON</span>
                </button>
                <button
                  type="button"
                  className={styles.iconButton}
                  onClick={resetAll}
                  aria-label="恢复全部默认值"
                  title="恢复配置、模拟数据和终端宽度">
                  <RotateCcw size={17} aria-hidden="true" />
                </button>
                <input ref={importRef} type="file" accept="application/json,.json" onChange={importConfig} hidden />
              </div>
            </div>
          </div>
        </header>

        <section className={styles.previewBand} aria-label="状态栏实时预览">
          <div className="container">
            <div className={styles.terminalWindow}>
              <div className={styles.terminalHeader}>
                <div className={styles.terminalDots} aria-hidden="true">
                  <span className={styles.dotClose} />
                  <span className={styles.dotMin} />
                  <span className={styles.dotMax} />
                </div>
                <span className={styles.terminalTitle}>wezterm · {columns} columns</span>
                <span className={styles.terminalBadge}>{effectiveActivity}</span>
              </div>
              <StatusRail config={config} state={sample} columns={columns} />
            </div>

            <div className={styles.widthControl}>
              <label htmlFor="columns">
                <Sliders size={16} aria-hidden="true" />
                <span>终端模拟宽度</span>
              </label>
              <input
                id="columns"
                type="range"
                min="40"
                max="180"
                step="1"
                value={columns}
                onChange={(event) => setColumns(Number(event.target.value))}
              />
              <output htmlFor="columns">{columns} cols</output>
            </div>
          </div>
        </section>

        <section className={styles.controlsBand}>
          <div className={`container ${styles.controls}`}>
            <div className={styles.primaryGrid}>
              <section className={styles.panel} aria-labelledby="display-heading">
                <SectionTitle icon={<Settings2 size={18} />} title="显示与主题" badge="常用" />
                <div className={styles.formGrid}>
                  <label className={styles.field}>
                    <span>状态标识 <code>label</code></span>
                    <input
                      value={config.options.label}
                      maxLength={24}
                      onChange={(event) => updateOptions((next) => { next.options.label = event.target.value; })}
                    />
                  </label>
                  <label className={styles.field}>
                    <span>项目图标 <code>icon.text</code></span>
                    <input
                      value={config.options.icon?.text ?? ''}
                      maxLength={8}
                      onChange={(event) => updateOptions((next) => { next.options.icon = {text: event.target.value}; })}
                    />
                  </label>
                  <label className={`${styles.field} ${styles.modelDisplayField}`}>
                    <span>模型显示</span>
                    <select
                      value={config.options.render.model_display ?? 'name'}
                      onChange={(event) => updateOptions((next) => {
                        next.options.render.model_display = event.target.value as ModelDisplay;
                      })}>
                      <option value="name">仅名称</option>
                      <option value="icon_name">图标＋名称</option>
                      <option value="icon">仅图标</option>
                    </select>
                    <small className={styles.fieldHint}>
                      {modelPresets.map(({family, label}) => `${modelIcons[family]} ${label}`).join('　')}
                      <br />按当前模型自动匹配，其他模型显示原名称。
                    </small>
                  </label>
                  <div className={styles.field}>
                    <span>底部行数 <code>bottom_pane.rows</code></span>
                    <div className={styles.segmented}>
                      {[1, 2].map((rows) => (
                        <button
                          type="button"
                          className={config.options.bottom_pane.rows === rows ? styles.selectedSegment : ''}
                          onClick={() => updateOptions((next) => { next.options.bottom_pane.rows = rows as 1 | 2; })}
                          key={rows}>
                          {rows} 行
                        </button>
                      ))}
                    </div>
                  </div>
                  <label className={styles.field}>
                    <span>分隔符 <code>theme.glyphs.sep</code></span>
                    <input
                      value={config.options.theme.glyphs?.sep ?? ''}
                      maxLength={8}
                      onChange={(event) => updateOptions((next) => {
                        next.options.theme.glyphs = {...next.options.theme.glyphs!, sep: event.target.value};
                      })}
                    />
                  </label>
                </div>

                <div className={styles.toggleGrid}>
                  <ToggleField
                    label="底部状态栏"
                    configKey="bottom_pane.enabled"
                    checked={config.options.bottom_pane.enabled ?? true}
                    onChange={(checked) => updateOptions((next) => { next.options.bottom_pane.enabled = checked; })}
                  />
                  <ToggleField
                    label="Powerline"
                    configKey="render.powerline"
                    checked={config.options.render.powerline}
                    onChange={(checked) => updateOptions((next) => { next.options.render.powerline = checked; })}
                  />
                  <ToggleField
                    label="纯文本回退"
                    configKey="render.plain_fallback"
                    checked={config.options.render.plain_fallback}
                    onChange={(checked) => updateOptions((next) => { next.options.render.plain_fallback = checked; })}
                  />
                  <ToggleField
                    label="Git 查询"
                    configKey="git.enabled"
                    checked={config.options.git.enabled}
                    onChange={(checked) => updateOptions((next) => { next.options.git.enabled = checked; })}
                  />
                </div>

                <div className={styles.colorGrid}>
                  {(['bg', 'fg', 'dim'] as const).map((key) => (
                    <label className={styles.globalColor} key={key}>
                      <span>{key === 'bg' ? '背景' : key === 'fg' ? '文字' : '弱化文字'}</span>
                      <input
                        type="color"
                        value={config.options.theme[key]}
                        onChange={(event) => updateOptions((next) => { next.options.theme[key] = event.target.value; })}
                      />
                      <code>{config.options.theme[key]}</code>
                    </label>
                  ))}
                </div>
              </section>

              <section className={styles.panel} aria-labelledby="state-heading">
                <SectionTitle icon={<Activity size={18} />} title="特殊状态与模拟数据" badge="实时" />
                <div className={styles.statusControls}>
                  <div className={styles.field}>
                    <span>协作模式 <code>activity.mode</code></span>
                    <div className={styles.segmented}>
                      {(['default', 'plan'] as const).map((mode) => (
                        <button
                          type="button"
                          className={(sample.activity?.mode ?? 'default') === mode ? styles.selectedSegment : ''}
                          onClick={() => updateActivity((activity) => { activity.mode = mode; })}
                          key={mode}>
                          {mode === 'default' ? 'Default' : 'Plan'}
                        </button>
                      ))}
                    </div>
                  </div>
                  <label className={styles.toggleField}>
                    <span>
                      <strong>Review 模式</strong>
                      <code>activity.review</code>
                    </span>
                    <input
                      type="checkbox"
                      role="switch"
                      checked={sample.activity?.review ?? false}
                      onChange={(event) => updateActivity((activity) => { activity.review = event.target.checked; })}
                    />
                  </label>
                  <label className={styles.field}>
                    <span>Goal 状态 <code>activity.goal.status</code></span>
                    <select
                      value={sample.activity?.goal?.status ?? ''}
                      onChange={(event) => updateActivity((activity) => {
                        const status = event.target.value as GoalStatus | '';
                        if (status) activity.goal = {...activity.goal, status};
                        else delete activity.goal;
                      })}>
                      <option value="">无 Goal</option>
                      {goalOptions.map((option) => <option value={option.value} key={option.value}>{option.label}</option>)}
                    </select>
                  </label>
                </div>
                <div className={styles.priorityStrip} aria-label="特殊状态显示优先级">
                  <span className={sample.activity?.review ? styles.priorityActive : ''}>REVIEW</span>
                  <b>›</b>
                  <span className={!sample.activity?.review && sample.activity?.mode === 'plan' ? styles.priorityActive : ''}>PLAN</span>
                  <b>›</b>
                  <span className={!sample.activity?.review && sample.activity?.mode !== 'plan' && sample.activity?.goal ? styles.priorityActive : ''}>GOAL</span>
                </div>

                <div className={styles.formGrid}>
                  <div className={styles.field}>
                    <label className={styles.field}>
                      <span>模型 <code>model</code></span>
                      <input value={sample.model ?? ''} onChange={(event) => updateSample('model', event.target.value)} />
                    </label>
                    <div className={styles.modelPresets} role="group" aria-label="模拟模型">
                      {modelPresets.map(({family, label, model}) => (
                        <button
                          type="button"
                          key={family}
                          aria-pressed={sample.model === model}
                          onClick={() => updateSample('model', model)}>
                          {modelIcons[family]} {label}
                        </button>
                      ))}
                    </div>
                  </div>
                  {(['reasoning', 'provider', 'personality', 'service_tier', 'cwd', 'project', 'git'] as const).map((key) => (
                    <label className={styles.field} key={key}>
                      <span>{segmentMeta[key].label} <code>{key}</code></span>
                      <input value={String(sample[key] ?? '')} onChange={(event) => updateSample(key, event.target.value)} />
                    </label>
                  ))}
                </div>
              </section>
            </div>

            <details className={styles.panel}>
              <summary className={styles.detailsSummary}>
                <span><Settings2 size={18} aria-hidden="true" />费用与模型单价</span>
                <small>USD / 百万 Token</small>
              </summary>
              <div className={styles.detailsBody}>
                <ModelPricing pricing={config.options.pricing} onChange={(pricing) => updateOptions((next) => {
                  next.options.pricing = pricing;
                })} />
              </div>
            </details>

            <details className={styles.panel}>
              <summary className={styles.detailsSummary}>
                <span>
                  <Sliders size={18} aria-hidden="true" />
                  Token、会话与状态预览数据
                </span>
                <small>预览数据</small>
              </summary>
              <div className={styles.detailsBody}>
                <div className={styles.formGridWide}>
                  {([
                    ['permissions', '沙箱权限'],
                    ['approval', '审批策略'],
                    ['thread_id', '会话 ID'],
                    ['codex_version', 'Codex 版本'],
                  ] as const).map(([key, label]) => (
                    <label className={styles.field} key={key}>
                      <span>{label} <code>{key}</code></span>
                      <input value={String(sample[key] ?? '')} onChange={(event) => updateSample(key, event.target.value)} />
                    </label>
                  ))}
                  <label className={styles.field}>
                    <span>任务已完成 <code>task_progress.completed</code></span>
                    <input
                      type="number"
                      min="0"
                      value={sample.task_progress?.completed ?? 0}
                      onChange={(event) => setSample((current) => ({
                        ...current,
                        task_progress: {...current.task_progress, completed: Number(event.target.value)},
                      }))}
                    />
                  </label>
                  <label className={styles.field}>
                    <span>任务总数 <code>task_progress.total</code></span>
                    <input
                      type="number"
                      min="1"
                      value={sample.task_progress?.total ?? 1}
                      onChange={(event) => setSample((current) => ({
                        ...current,
                        task_progress: {...current.task_progress, total: Number(event.target.value)},
                      }))}
                    />
                  </label>
                </div>

                <div className={styles.subsection}>
                  <Heading as="h3">Token 数据</Heading>
                  <div className={styles.formGridWide}>
                    {([
                      ['input_raw', '输入 Token（含缓存）'],
                      ['cached', '缓存 Token'],
                      ['output', '输出 Token'],
                      ['reasoning', '推理 Token'],
                      ['context_tokens', '当前上下文 Token'],
                      ['context_window', '上下文窗口'],
                    ] as const).map(([key, label]) => (
                      <label className={styles.field} key={key}>
                        <span>{label} <code>usage.{key}</code></span>
                        <input
                          type="number"
                          min="0"
                          step="1000"
                          value={sample.usage?.[key] ?? 0}
                          onChange={(event) => updateUsage(key, Number(event.target.value))}
                        />
                      </label>
                    ))}
                    <label className={styles.field}>
                      <span>上下文剩余 <code>usage.context_remaining_percent</code></span>
                      <div className={styles.rangeField}>
                        <input
                          type="range"
                          min="0"
                          max="100"
                          value={sample.usage?.context_remaining_percent ?? 0}
                          onChange={(event) => updateUsage('context_remaining_percent', Number(event.target.value))}
                        />
                        <output>{sample.usage?.context_remaining_percent ?? 0}%</output>
                      </div>
                    </label>
                  </div>
                </div>

                {sample.activity?.goal ? (
                  <div className={styles.subsection}>
                    <Heading as="h3">Goal 预览数据</Heading>
                    <div className={styles.formGridWide}>
                      {([
                        ['token_budget', 'Token 预算'],
                        ['tokens_used', '已用 Token'],
                        ['time_used_seconds', '已用时间（秒）'],
                      ] as const).map(([key, label]) => (
                        <label className={styles.field} key={key}>
                          <span>{label} <code>activity.goal.{key}</code></span>
                          <input
                            type="number"
                            min="0"
                            value={sample.activity?.goal?.[key] ?? 0}
                            onChange={(event) => updateActivity((activity) => {
                              if (activity.goal) activity.goal[key] = Number(event.target.value);
                            })}
                          />
                        </label>
                      ))}
                    </div>
                  </div>
                ) : null}

                <div className={styles.subsection}>
                  <Heading as="h3">特殊状态文字</Heading>
                  <div className={styles.formGridWide}>
                    {activityLabelFields.map(([key, label]) => (
                      <label className={styles.field} key={key}>
                        <span>{label} <code>activity.labels.{key}</code></span>
                        <input
                          value={config.options.activity?.labels[key] ?? ''}
                          maxLength={32}
                          onChange={(event) => updateOptions((next) => {
                            next.options.activity!.labels[key] = event.target.value;
                          })}
                        />
                      </label>
                    ))}
                  </div>
                </div>
              </div>
            </details>

            <section className={`${styles.panel} ${styles.segmentPanel}`} aria-labelledby="segments-heading">
              <SectionTitle icon={<Palette size={18} />} title="字段顺序与配色" badge={`${segmentIds.length} 字段`} />
              <div className={styles.segmentTable}>
                <div className={styles.tableHeader}>
                  <span>显示</span>
                  <span>序号</span>
                  <span>字段</span>
                  <span>背景色</span>
                  <span>文字色</span>
                  <span>排序</span>
                </div>
                {config.options.render.segment_order.map((id, index) => {
                  const enabled = !config.options.render.disabled_segments.includes(id);
                  const theme = themeFor(id);
                  return (
                    <div className={`${styles.segmentRow} ${!enabled ? styles.segmentDisabled : ''}`} key={id}>
                      <button
                        type="button"
                        className={`${styles.enableButton} ${enabled ? styles.enabled : ''}`}
                        onClick={() => toggleSegment(id)}
                        aria-label={`${enabled ? '隐藏' : '显示'}${segmentMeta[id].label}`}
                        title={enabled ? '隐藏字段' : '显示字段'}>
                        {enabled ? <Check size={15} aria-hidden="true" /> : null}
                      </button>
                      <span className={styles.order}>{String(index + 1).padStart(2, '0')}</span>
                      <div className={styles.segmentName}>
                        <strong>{segmentMeta[id].label}</strong>
                        <span>{segmentMeta[id].description}</span>
                        <code>{id}</code>
                      </div>
                      <label className={styles.colorInput} title={`${segmentMeta[id].label}背景色`}>
                        <input
                          type="color"
                          value={theme.bg}
                          onChange={(event) => updateOptions((next) => {
                            const current = next.options.theme.segments[id] ?? {bg: next.options.theme.bg, fg: next.options.theme.fg};
                            next.options.theme.segments[id] = {...current, bg: event.target.value};
                          })}
                        />
                        <code>{theme.bg}</code>
                      </label>
                      <label className={styles.colorInput} title={`${segmentMeta[id].label}文字色`}>
                        <input
                          type="color"
                          value={theme.fg}
                          onChange={(event) => updateOptions((next) => {
                            const current = next.options.theme.segments[id] ?? {bg: next.options.theme.bg, fg: next.options.theme.fg};
                            next.options.theme.segments[id] = {...current, fg: event.target.value};
                          })}
                        />
                        <code>{theme.fg}</code>
                      </label>
                      <div className={styles.reorder}>
                        <button
                          type="button"
                          onClick={() => moveSegment(id, -1)}
                          disabled={id === 'icon' || index === 0}
                          aria-label={`上移${segmentMeta[id].label}`}
                          title={id === 'icon' ? '项目图标固定在右侧版本号之前' : '上移'}>
                          <ArrowUp size={15} aria-hidden="true" />
                        </button>
                        <button
                          type="button"
                          onClick={() => moveSegment(id, 1)}
                          disabled={id === 'icon' || index >= config.options.render.segment_order.length - 2}
                          aria-label={`下移${segmentMeta[id].label}`}
                          title={id === 'icon' ? '项目图标固定在右侧版本号之前' : '下移'}>
                          <ArrowDown size={15} aria-hidden="true" />
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            </section>

            <details className={styles.panel}>
              <summary className={styles.detailsSummary}>
                <span>
                  <Settings2 size={18} aria-hidden="true" />
                  日志、会话与进程检测
                </span>
                <small>高级配置</small>
              </summary>
              <div className={styles.detailsBody}>
                <div className={styles.advancedGroup}>
                  <Heading as="h3">日志与底部窗格</Heading>
                  <div className={styles.toggleGrid}>
                    <ToggleField label="调试日志" configKey="debug" checked={config.options.debug ?? false} onChange={(checked) => updateOptions((next) => { next.options.debug = checked; })} />
                    <ToggleField label="写入加载日志" configKey="log.enabled" checked={config.options.log?.enabled ?? true} onChange={(checked) => updateOptions((next) => { next.options.log!.enabled = checked; })} />
                    <ToggleField label="保持 Codex 窗格焦点" configKey="bottom_pane.prevent_focus" checked={config.options.bottom_pane.prevent_focus} onChange={(checked) => updateOptions((next) => { next.options.bottom_pane.prevent_focus = checked; })} />
                    <ToggleField label="兼容右侧状态栏" configKey="compat.update_right_status" checked={config.options.compat?.update_right_status ?? false} onChange={(checked) => updateOptions((next) => { next.options.compat!.update_right_status = checked; })} />
                    <ToggleField label="读取 Codex 配置" configKey="codex_config.enabled" checked={config.options.codex_config?.enabled ?? true} onChange={(checked) => updateOptions((next) => { next.options.codex_config!.enabled = checked; })} />
                    <ToggleField label="标题桥接" configKey="title_bridge.enabled" checked={config.options.title_bridge.enabled} onChange={(checked) => updateOptions((next) => { next.options.title_bridge.enabled = checked; })} />
                  </div>
                  <div className={styles.formGridWide}>
                    <label className={styles.field}><span>Codex 数据目录 <code>codex_home</code></span><input value={config.options.codex_home ?? ''} onChange={(event) => updateOptions((next) => { next.options.codex_home = event.target.value; })} /></label>
                    <label className={styles.field}><span>日志标记 <code>log.marker</code></span><input value={config.options.log?.marker ?? ''} onChange={(event) => updateOptions((next) => { next.options.log!.marker = event.target.value; })} /></label>
                    <label className={styles.field}><span>Codex 配置路径 <code>codex_config.path</code></span><input value={config.options.codex_config?.path ?? ''} onChange={(event) => updateOptions((next) => { next.options.codex_config!.path = event.target.value; })} /></label>
                    <label className={styles.field}><span>Codex 配置缓存（秒） <code>codex_config.cache_ttl_seconds</code></span><input type="number" min="0" step="0.1" value={config.options.codex_config?.cache_ttl_seconds ?? 0} onChange={(event) => updateOptions((next) => { next.options.codex_config!.cache_ttl_seconds = Number(event.target.value); })} /></label>
                    <label className={styles.field}><span>退出宽限（秒） <code>bottom_pane.close_grace_seconds</code></span><input type="number" min="0" step="0.1" value={config.options.bottom_pane.close_grace_seconds ?? 0} onChange={(event) => updateOptions((next) => { next.options.bottom_pane.close_grace_seconds = Number(event.target.value); })} /></label>
                    <label className={styles.field}><span>Git 缓存（秒） <code>git.cache_ttl_seconds</code></span><input type="number" min="0" step="0.1" value={config.options.git.cache_ttl_seconds ?? 0} onChange={(event) => updateOptions((next) => { next.options.git.cache_ttl_seconds = Number(event.target.value); })} /></label>
                    <label className={styles.field}><span>应用名 <code>title_bridge.app_name</code></span><input value={config.options.title_bridge.app_name ?? ''} onChange={(event) => updateOptions((next) => { next.options.title_bridge.app_name = event.target.value; })} /></label>
                    <label className={styles.field}><span>Git 图标 <code>theme.glyphs.branch</code></span><input value={config.options.theme.glyphs?.branch ?? ''} maxLength={8} onChange={(event) => updateOptions((next) => { next.options.theme.glyphs = {...next.options.theme.glyphs!, branch: event.target.value}; })} /></label>
                    <label className={styles.field}><span>目录图标 <code>theme.glyphs.folder</code></span><input value={config.options.theme.glyphs?.folder ?? ''} maxLength={8} onChange={(event) => updateOptions((next) => { next.options.theme.glyphs = {...next.options.theme.glyphs!, folder: event.target.value}; })} /></label>
                  </div>
                </div>

                <div className={styles.advancedGroup}>
                  <Heading as="h3">会话绑定</Heading>
                  <div className={styles.toggleGrid}>
                    <ToggleField label="会话绑定" configKey="sessions.enabled" checked={config.options.sessions.enabled ?? true} onChange={(checked) => updateOptions((next) => { next.options.sessions.enabled = checked; })} />
                    <ToggleField label="允许最新会话回退" configKey="sessions.allow_fallback_latest" checked={config.options.sessions.allow_fallback_latest} onChange={(checked) => updateOptions((next) => { next.options.sessions.allow_fallback_latest = checked; })} />
                    <ToggleField label="恢复会话时临时匹配" configKey="sessions.resume_fallback_enabled" checked={config.options.sessions.resume_fallback_enabled ?? true} onChange={(checked) => updateOptions((next) => { next.options.sessions.resume_fallback_enabled = checked; })} />
                  </div>
                  <div className={styles.formGridWide}>
                    <label className={styles.field}>
                      <span>绑定模式 <code>sessions.binding_mode</code></span>
                      <select value={config.options.sessions.binding_mode} onChange={(event) => updateOptions((next) => { next.options.sessions.binding_mode = event.target.value as 'auto' | 'hook' | 'heuristic'; })}>
                        <option value="auto">auto</option><option value="hook">hook</option><option value="heuristic">heuristic</option>
                      </select>
                    </label>
                    <label className={styles.field}><span>会话映射目录 <code>sessions.bridge_dir</code></span><input value={config.options.sessions.bridge_dir ?? ''} onChange={(event) => updateOptions((next) => { next.options.sessions.bridge_dir = event.target.value; })} /></label>
                    {([
                      ['resume_fallback_max_age_seconds', '候选会话有效期（秒）', 1],
                      ['resume_fallback_clock_skew_seconds', '允许的时钟偏差（秒）', 0],
                      ['resume_fallback_scan_ttl_seconds', '恢复会话扫描间隔（秒）', 0],
                      ['cache_ttl_seconds', '会话缓存（秒）', 0],
                      ['full_scan_ttl_seconds', '完整扫描缓存（秒）', 0],
                      ['tail_ttl_seconds', '尾部读取缓存（秒）', 0],
                      ['open_fail_clear_seconds', '读取失败清理（秒）', 0],
                      ['initial_seek_bytes', '首次读取字节数', 0],
                      ['activity_seek_bytes', '状态读取字节数', 0],
                      ['activity_max_seek_bytes', '状态最大读取字节数', 0],
                      ['max_meta_lines', '元数据最大行数', 1],
                      ['max_tail_lines', '尾部最大行数', 1],
                    ] as const).map(([key, label, min]) => (
                      <label className={styles.field} key={key}>
                        <span>{label} <code>sessions.{key}</code></span>
                        <input type="number" min={min} value={config.options.sessions[key] ?? 0} onChange={(event) => updateOptions((next) => { next.options.sessions[key] = Number(event.target.value); })} />
                      </label>
                    ))}
                  </div>
                </div>

                <div className={styles.advancedGroup}>
                  <Heading as="h3">进程检测</Heading>
                  <div className={styles.toggleGrid}>
                    <ToggleField label="进程检测" configKey="process_match.enabled" checked={config.options.process_match?.enabled ?? true} onChange={(checked) => updateOptions((next) => { next.options.process_match!.enabled = checked; })} />
                  </div>
                  <div className={styles.formGridWide}>
                    <label className={styles.field}><span>退出宽限（秒） <code>process_match.grace_seconds</code></span><input type="number" min="0" step="0.1" value={config.options.process_match?.grace_seconds ?? 0} onChange={(event) => updateOptions((next) => { next.options.process_match!.grace_seconds = Number(event.target.value); })} /></label>
                    <label className={styles.field}><span>进程树缓存（秒） <code>process_match.tree_cache_ttl_seconds</code></span><input type="number" min="0" step="0.1" value={config.options.process_match?.tree_cache_ttl_seconds ?? 0} onChange={(event) => updateOptions((next) => { next.options.process_match!.tree_cache_ttl_seconds = Number(event.target.value); })} /></label>
                  </div>
                  <div className={styles.listGrid}>
                    <StringListEditor label="进程名 · process_match.names" value={config.options.process_match?.names ?? []} onChange={(value) => updateOptions((next) => { next.options.process_match!.names = value; })} />
                    <StringListEditor label="命令行标记 · process_match.argv_markers" value={config.options.process_match?.argv_markers ?? []} onChange={(value) => updateOptions((next) => { next.options.process_match!.argv_markers = value; })} />
                    <StringListEditor label="终端进程名 · process_match.terminal_names" value={config.options.process_match?.terminal_names ?? []} onChange={(value) => updateOptions((next) => { next.options.process_match!.terminal_names = value; })} />
                  </div>
                </div>

                <div className={styles.advancedGroup}>
                  <Heading as="h3">WezTerm user vars</Heading>
                  <div className={styles.listGrid}>
                    {(['model', 'thinking', 'provider', 'active'] as const).map((key) => (
                      <StringListEditor
                        label={`${key} · user_vars.${key}`}
                        value={config.options.user_vars?.[key] ?? []}
                        onChange={(value) => updateOptions((next) => { next.options.user_vars![key] = value; })}
                        key={key}
                      />
                    ))}
                  </div>
                </div>
              </div>
            </details>
          </div>
        </section>

        {notice ? (
          <div className={styles.toast} role="status" aria-live="polite">
            <Check size={16} aria-hidden="true" />
            <span>{notice}</span>
          </div>
        ) : null}
      </main>
    </Layout>
  );
}
