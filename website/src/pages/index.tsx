import type {ReactNode} from 'react';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import CodeBlock from '@theme/CodeBlock';
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import {
  ArrowRight,
  BookOpen,
  Braces,
  Code2,
  Download,
  Eye,
  FileSliders,
  GitBranch,
  ListTree,
  RefreshCw,
  Terminal,
  Wrench,
} from 'lucide-react';
import HomepageFeatures from '@site/src/components/HomepageFeatures';

import styles from './index.module.css';

const copy = {
  zh: {
    preview: '交互预览',
    requirements: '平台要求',
    tagline: '在 Codex 窗格下方查看模型、推理强度、Git 分支、上下文和 Token 用量。',
    start: '开始使用',
    installTitle: '安装状态栏',
    installDescription: '选择一个安装命令，再按安装指南将状态栏加入 WezTerm 配置。',
    installLink: '查看详细安装步骤',
    docsTitle: '使用指南',
    docsDescription: '安装、配置、更新和问题排查。',
    featureTitle: '查看会话信息',
    featureDescription: '选择你需要的字段，让状态栏适应日常工作。',
    statusAria: '状态栏示例：Codex，gpt-5.6-sol，high，OpenAI provider，~/src/app，main 分支，上下文剩余 72%，输入 10M，输出 204K，缓存率 60%，估算费用 22.48 美元',
  },
  en: {
    preview: 'Interactive preview',
    requirements: 'Requirements',
    tagline: 'See the model, reasoning effort, Git branch, context, and token usage below every Codex pane.',
    start: 'Get started',
    installTitle: 'Install the status line',
    installDescription: 'Choose an installer, then follow the guide to load the status line in WezTerm.',
    installLink: 'Read the installation guide',
    docsTitle: 'Documentation',
    docsDescription: 'Install, configure, update, and troubleshoot.',
    featureTitle: 'See session information',
    featureDescription: 'Choose the fields you need for everyday work.',
    statusAria: 'Status line example: Codex, gpt-5.6-sol, high, OpenAI provider, ~/src/app, main branch, 72 percent context left, 10M input, 204K output, 60 percent cache, estimated cost 22.48 US dollars',
  },
} as const;

const routes = {
  zh: [
    ['安装指南', '安装状态栏', '使用 npx 或 uvx 安装，查看平台要求。', '/docs/getting-started/installation', Download],
    ['加载状态栏', '配置 .wezterm.lua', '在现有配置中加载状态栏，并检查安装结果。', '/docs/getting-started/wezterm-config', Braces],
    ['自定义显示', '个性化配置', '调整字段、颜色和行数，导入网页下载的配置。', '/docs/guides/configuration', FileSliders],
    ['版本维护', '更新与卸载', '更新插件并保留配置，或按步骤卸载。', '/docs/getting-started/update-uninstall', RefreshCw],
    ['问题排查', '常见问题与诊断', '处理安装失败、等待状态、配置和显示问题。', '/docs/troubleshooting/common-issues', Wrench],
    ['命令参考', '命令行参考', '查询命令、选项、输出格式和退出码。', '/docs/guides/cli-reference', ListTree],
  ],
  en: [
    ['Installation', 'Install the status line', 'Install with npx or uvx and check platform requirements.', '/docs/getting-started/installation', Download],
    ['Load the status line', 'Configure .wezterm.lua', 'Load the status line and verify the installation.', '/docs/getting-started/wezterm-config', Braces],
    ['Customize the display', 'Personalize the layout', 'Adjust fields, colors, and rows, then import the downloaded JSON.', '/docs/guides/configuration', FileSliders],
    ['Maintain versions', 'Update and uninstall', 'Update the plugin while preserving configuration, or remove it cleanly.', '/docs/getting-started/update-uninstall', RefreshCw],
    ['Troubleshooting', 'Common issues and diagnostics', 'Resolve installation, waiting-state, configuration, and display problems.', '/docs/troubleshooting/common-issues', Wrench],
    ['Command reference', 'CLI reference', 'Look up commands, options, output formats, and exit codes.', '/docs/guides/cli-reference', ListTree],
  ],
} as const;

const npxInstallCommand = 'npx --yes wezterm-codex-status-line@0.1.2 install --no-title-bridge';
const uvxInstallCommand = 'uvx wezterm-codex-status-line@0.1.2 install --no-title-bridge';

function StatusRailMock({english}: {english: boolean}): ReactNode {
  const text = english ? copy.en : copy.zh;
  return (
    <div className={styles.terminalWindow}>
      <div className={styles.terminalHeader}>
        <div className={styles.terminalDots}>
          <span className={styles.dotClose} />
          <span className={styles.dotMin} />
          <span className={styles.dotMax} />
        </div>
        <span className={styles.terminalTitle}>wezterm — codex-statusline</span>
        <Link className={styles.terminalAction} to="/preview">
          <Eye size={13} />
          <span>{text.preview}</span>
        </Link>
      </div>

      <Link className={styles.statusRail} to="/preview" aria-label={text.statusAria}>
        <span className={`${styles.statusCell} ${styles.statusBrand}`}><Terminal aria-hidden="true" size={13} strokeWidth={2.2} />CODEX</span>
        <span className={styles.statusCell}>gpt-5.6-sol</span>
        <span className={`${styles.statusCell} ${styles.statusEffort}`}>high</span>
        <span className={`${styles.statusCell} ${styles.hideOnTablet}`}>p:openai</span>
        <span className={`${styles.statusCell} ${styles.hideOnMobile}`}>~/src/app</span>
        <span className={`${styles.statusCell} ${styles.statusBranch}`}><GitBranch aria-hidden="true" size={13} />main</span>
        <span className={`${styles.statusCell} ${styles.statusContext}`}><span>Ctx</span><span className={styles.contextMeter} aria-hidden="true"><span /></span><strong>72% left</strong></span>
        <span className={`${styles.statusCell} ${styles.hideOnTablet}`}>↑10M ↓204K</span>
        <span className={`${styles.statusCell} ${styles.hideOnTablet}`}>Cache 60%</span>
        <span className={`${styles.statusCell} ${styles.hideOnTablet}`}>Cost ~$22.48</span>
        <span className={`${styles.statusCell} ${styles.statusMark}`} aria-label="WezTerm Codex Status Line project icon"></span>
      </Link>
    </div>
  );
}

function HomepageHeader({english}: {english: boolean}): ReactNode {
  const text = english ? copy.en : copy.zh;
  return (
    <header className={styles.masthead}>
      <div className={`container ${styles.mastheadInner}`}>
        <div className={styles.metaLine}><span className={styles.liveState}><span aria-hidden="true" />v0.1.2</span><span className={styles.metaDivider} /><span className={styles.metaTag}>WezTerm</span><span className={styles.metaDot}>·</span><span className={styles.metaTag}>Codex CLI</span><span className={styles.metaDot}>·</span><Link className={styles.metaTag} to={`/docs/getting-started/installation#${english ? 'requirements' : '要求'}`}>{text.requirements}</Link></div>
        <div className={styles.titleRow}>
          <div className={styles.titleCopy}><Heading as="h1">WezTerm Codex Status Line</Heading><p>{text.tagline}</p></div>
          <div className={styles.actions}><Link className={styles.primaryAction} to="/docs/getting-started/installation"><BookOpen aria-hidden="true" size={15} />{text.start}</Link><Link className={styles.secondaryAction} href="https://github.com/un4gt/wezterm-codex-status-line"><Code2 aria-hidden="true" size={15} />GitHub</Link></div>
        </div>
        <StatusRailMock english={english} />
      </div>
    </header>
  );
}

export default function Home(): ReactNode {
  const {i18n} = useDocusaurusContext();
  const english = i18n.currentLocale === 'en';
  const text = english ? copy.en : copy.zh;
  const documentRoutes = english ? routes.en : routes.zh;
  return (
    <Layout title={english ? 'Codex status line for WezTerm' : 'WezTerm 中的 Codex 底部状态栏'} description={text.tagline}>
      <HomepageHeader english={english} />
      <main className={styles.main}>
        <section className={styles.install} aria-labelledby="install-heading"><div className={`container ${styles.installGrid}`}><div className={styles.sectionIntro}><span className={styles.sectionIndex}>01 / INSTALL</span><Heading as="h2" id="install-heading">{text.installTitle}</Heading><p>{text.installDescription}</p><Link className={styles.introLink} to="/docs/getting-started/installation">{text.installLink} <ArrowRight aria-hidden="true" size={14} /></Link></div><div className={styles.commandBlock}><Tabs groupId="installer" defaultValue="npx" values={[{label: 'npx', value: 'npx'}, {label: 'uvx', value: 'uvx'}]}><TabItem value="npx"><CodeBlock language="powershell">{npxInstallCommand}</CodeBlock></TabItem><TabItem value="uvx"><CodeBlock language="bash">{uvxInstallCommand}</CodeBlock></TabItem></Tabs></div></div></section>
        <section className={styles.routes} aria-labelledby="routes-heading"><div className="container"><div className={styles.sectionHeading}><div><span className={styles.sectionIndex}>02 / DOCUMENTATION</span><Heading as="h2" id="routes-heading">{text.docsTitle}</Heading></div><p>{text.docsDescription}</p></div><div className={styles.routeGrid}>{documentRoutes.map(([label, title, description, to, Icon], index) => <Link className={styles.routeCard} to={to} key={to}><div className={styles.routeHeader}><span className={styles.routeBadge}><Icon aria-hidden="true" size={14} /><span>{String(index + 1).padStart(2, '0')} / {label}</span></span><ArrowRight className={styles.routeArrow} aria-hidden="true" size={14} /></div><Heading as="h3">{title}</Heading><p>{description}</p></Link>)}</div></div></section>
        <HomepageFeatures english={english} />
      </main>
    </Layout>
  );
}
