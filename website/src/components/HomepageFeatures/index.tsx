import type {ReactNode} from 'react';
import Heading from '@theme/Heading';
import {Activity, GitBranch, ShieldCheck} from 'lucide-react';
import styles from './styles.module.css';

const features = [
  {
    index: '01',
    title: '多个会话',
    description: '同时运行多个 Codex 窗格，分别查看各自的模型和用量。',
    Icon: GitBranch,
  },
  {
    index: '02',
    title: '用量与上下文',
    description: '查看剩余上下文、累计输入输出、缓存率和估算费用。',
    Icon: Activity,
  },
  {
    index: '03',
    title: '自定义外观',
    description: '在浏览器中选择字段、颜色和布局，下载配置后应用到本机。',
    Icon: ShieldCheck,
  },
];

export default function HomepageFeatures(): ReactNode {
  return (
    <section className={styles.features} aria-labelledby="capabilities-heading">
      <div className={`container ${styles.layout}`}>
        <div className={styles.headingBlock}>
          <span className={styles.sectionIndex}>03 / FEATURES</span>
          <Heading as="h2" id="capabilities-heading">查看会话信息</Heading>
          <p>选择你需要的字段，让状态栏适应日常工作。</p>
        </div>
        <div className={styles.featureGrid}>
          {features.map(({index, title, description, Icon}) => (
            <article className={styles.featureCard} key={title}>
              <div className={styles.cardHeader}>
                <div className={styles.iconWrapper}>
                  <Icon aria-hidden="true" size={18} />
                </div>
                <span className={styles.featureIndex}>{index}</span>
              </div>
              <Heading as="h3">{title}</Heading>
              <p>{description}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
