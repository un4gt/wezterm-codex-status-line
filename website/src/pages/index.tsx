import type {ReactNode} from 'react';
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

const npxInstallCommand = 'npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.1/wezterm-codex-status-line-0.1.1.tgz wezterm-codex-status-line install --no-title-bridge';
const uvxInstallCommand = 'uvx wezterm-codex-status-line install --no-title-bridge';

const documentRoutes = [
  {
    label: '安装指南',
    title: '安装状态栏',
    description: '使用 npx 或 uvx 安装，查看平台要求。',
    to: '/docs/getting-started/installation',
    Icon: Download,
  },
  {
    label: '加载状态栏',
    title: '配置 .wezterm.lua',
    description: '在现有配置中加载状态栏，并检查安装结果。',
    to: '/docs/getting-started/wezterm-config',
    Icon: Braces,
  },
  {
    label: '自定义显示',
    title: '个性化配置',
    description: '调整字段、颜色和行数，导入网页下载的配置。',
    to: '/docs/guides/configuration',
    Icon: FileSliders,
  },
  {
    label: '版本维护',
    title: '更新与卸载',
    description: '更新插件并保留配置，或按步骤卸载。',
    to: '/docs/getting-started/update-uninstall',
    Icon: RefreshCw,
  },
  {
    label: '问题排查',
    title: '常见问题与诊断',
    description: '处理安装失败、等待状态、配置和显示问题。',
    to: '/docs/troubleshooting/common-issues',
    Icon: Wrench,
  },
  {
    label: '命令参考',
    title: '命令行参考',
    description: '查询命令、选项、输出格式和退出码。',
    to: '/docs/guides/cli-reference',
    Icon: ListTree,
  },
];

function StatusRailMock(): ReactNode {
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
          <span>交互预览</span>
        </Link>
      </div>

      <Link
        className={styles.statusRail}
        to="/preview"
        aria-label="状态栏示例：Codex，gpt-5.6-sol，high，OpenAI provider，~/src/app，main 分支，上下文剩余 72%，输入 10M，输出 204K，缓存率 60%，估算费用 22.48 美元">
        <span className={`${styles.statusCell} ${styles.statusBrand}`}>
          <Terminal aria-hidden="true" size={13} strokeWidth={2.2} />
          CODEX
        </span>
        <span className={styles.statusCell}>gpt-5.6-sol</span>
        <span className={`${styles.statusCell} ${styles.statusEffort}`}>high</span>
        <span className={`${styles.statusCell} ${styles.hideOnTablet}`}>p:openai</span>
        <span className={`${styles.statusCell} ${styles.hideOnMobile}`}>~/src/app</span>
        <span className={`${styles.statusCell} ${styles.statusBranch}`}>
          <GitBranch aria-hidden="true" size={13} />
          main
        </span>
        <span className={`${styles.statusCell} ${styles.statusContext}`}>
          <span>Ctx</span>
          <span className={styles.contextMeter} aria-hidden="true">
            <span />
          </span>
          <strong>72% left</strong>
        </span>
        <span className={`${styles.statusCell} ${styles.hideOnTablet}`}>↑10M ↓204K</span>
        <span className={`${styles.statusCell} ${styles.hideOnTablet}`}>Cache 60%</span>
        <span className={`${styles.statusCell} ${styles.hideOnTablet}`}>Cost ~$22.48</span>
        <span className={`${styles.statusCell} ${styles.statusMark}`} aria-label="WezTerm Codex Status Line 项目图标">
          
        </span>
      </Link>
    </div>
  );
}

function HomepageHeader(): ReactNode {
  return (
    <header className={styles.masthead}>
      <div className={`container ${styles.mastheadInner}`}>
        <div className={styles.metaLine}>
          <span className={styles.liveState}>
            <span aria-hidden="true" />
            v0.1.1
          </span>
          <span className={styles.metaDivider} />
          <span className={styles.metaTag}>WezTerm</span>
          <span className={styles.metaDot}>·</span>
          <span className={styles.metaTag}>Codex CLI</span>
          <span className={styles.metaDot}>·</span>
          <Link className={styles.metaTag} to="/docs/getting-started/installation#要求">平台要求</Link>
        </div>

        <div className={styles.titleRow}>
          <div className={styles.titleCopy}>
            <Heading as="h1">WezTerm Codex Status Line</Heading>
            <p>
              在 Codex 窗格下方查看模型、推理强度、Git 分支、上下文和 Token 用量。
            </p>
          </div>
          <div className={styles.actions}>
            <Link className={styles.primaryAction} to="/docs/getting-started/installation">
              <BookOpen aria-hidden="true" size={15} />
              开始使用
            </Link>
            <Link className={styles.secondaryAction} href="https://github.com/un4gt/wezterm-codex-status-line">
              <Code2 aria-hidden="true" size={15} />
              GitHub
            </Link>
          </div>
        </div>

        <StatusRailMock />
      </div>
    </header>
  );
}

export default function Home(): ReactNode {
  return (
    <Layout
      title="WezTerm 中的 Codex 底部状态栏"
      description="为每个 Codex 窗格显示独立状态栏，自定义字段、颜色和布局。">
      <HomepageHeader />
      <main className={styles.main}>
        <section className={styles.install} aria-labelledby="install-heading">
          <div className={`container ${styles.installGrid}`}>
            <div className={styles.sectionIntro}>
              <span className={styles.sectionIndex}>01 / INSTALL</span>
              <Heading as="h2" id="install-heading">安装状态栏</Heading>
              <p>选择一个安装命令，再按安装指南将状态栏加入 WezTerm 配置。</p>
              <Link className={styles.introLink} to="/docs/getting-started/installation">
                查看详细安装步骤 <ArrowRight aria-hidden="true" size={14} />
              </Link>
            </div>
            <div className={styles.commandBlock}>
              <Tabs groupId="installer" defaultValue="npx" values={[{label: 'npx', value: 'npx'}, {label: 'uvx', value: 'uvx'}]}>
                <TabItem value="npx"><CodeBlock language="powershell">{npxInstallCommand}</CodeBlock></TabItem>
                <TabItem value="uvx"><CodeBlock language="bash">{uvxInstallCommand}</CodeBlock></TabItem>
              </Tabs>
            </div>
          </div>
        </section>

        <section className={styles.routes} aria-labelledby="routes-heading">
          <div className="container">
            <div className={styles.sectionHeading}>
              <div>
                <span className={styles.sectionIndex}>02 / DOCUMENTATION</span>
                <Heading as="h2" id="routes-heading">使用指南</Heading>
              </div>
              <p>安装、配置、更新和问题排查。</p>
            </div>
            <div className={styles.routeGrid}>
              {documentRoutes.map(({label, title, description, to, Icon}, index) => (
                <Link className={styles.routeCard} to={to} key={to}>
                  <div className={styles.routeHeader}>
                    <span className={styles.routeBadge}>
                      <Icon aria-hidden="true" size={14} />
                      <span>{String(index + 1).padStart(2, '0')} / {label}</span>
                    </span>
                    <ArrowRight className={styles.routeArrow} aria-hidden="true" size={14} />
                  </div>
                  <Heading as="h3">{title}</Heading>
                  <p>{description}</p>
                </Link>
              ))}
            </div>
          </div>
        </section>

        <HomepageFeatures />
      </main>
    </Layout>
  );
}
