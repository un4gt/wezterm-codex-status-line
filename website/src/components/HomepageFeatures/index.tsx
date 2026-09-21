import type {ReactNode} from 'react';
import Heading from '@theme/Heading';
import {Activity, GitBranch, ShieldCheck} from 'lucide-react';
import styles from './styles.module.css';

const features = {
  zh: [
    ['01', '多个会话', '同时运行多个 Codex 窗格，分别查看各自的模型和用量。', GitBranch],
    ['02', '用量与上下文', '查看剩余上下文、累计输入输出、缓存率和估算费用。', Activity],
    ['03', '自定义外观', '在浏览器中选择字段、颜色和布局，下载配置后应用到本机。', ShieldCheck],
  ],
  en: [
    ['01', 'Multiple sessions', 'Run several Codex panes and inspect each model and usage independently.', GitBranch],
    ['02', 'Usage and context', 'See remaining context, cumulative input and output, cache rate, and estimated cost.', Activity],
    ['03', 'Custom appearance', 'Choose fields, colors, and layout in the browser, then apply the downloaded configuration locally.', ShieldCheck],
  ],
} as const;

export default function HomepageFeatures({english}: {english: boolean}): ReactNode {
  const items = english ? features.en : features.zh;
  return (
    <section className={styles.features} aria-labelledby="capabilities-heading">
      <div className={`container ${styles.layout}`}>
        <div className={styles.headingBlock}><span className={styles.sectionIndex}>03 / FEATURES</span><Heading as="h2" id="capabilities-heading">{english ? 'See session information' : '查看会话信息'}</Heading><p>{english ? 'Choose the fields you need for everyday work.' : '选择你需要的字段，让状态栏适应日常工作。'}</p></div>
        <div className={styles.featureGrid}>{items.map(([index, title, description, Icon]) => <article className={styles.featureCard} key={title}><div className={styles.cardHeader}><div className={styles.iconWrapper}><Icon aria-hidden="true" size={18} /></div><span className={styles.featureIndex}>{index}</span></div><Heading as="h3">{title}</Heading><p>{description}</p></article>)}</div>
      </div>
    </section>
  );
}
