import type {ReactNode} from 'react';
import Heading from '@theme/Heading';
import {Activity, GitBranch, ShieldCheck} from 'lucide-react';
import styles from './styles.module.css';

const features = [
  {
    index: '01',
    title: '线程精确绑定',
    description: '通过 pane 与 thread 的明确映射关系，区分同一工作目录中的并行会话。',
    Icon: GitBranch,
  },
  {
    index: '02',
    title: '增量 Rollout Tail',
    description: '按 offset 读取新增事件与用量更新，并根据当前终端宽度逐级折叠。',
    Icon: Activity,
  },
  {
    index: '03',
    title: '安全生命周期回收',
    description: '只对已记录的状态 pane ID 发起定向关闭；目标无法确认时保留 pane。',
    Icon: ShieldCheck,
  },
];

export default function HomepageFeatures(): ReactNode {
  return (
    <section className={styles.features} aria-labelledby="capabilities-heading">
      <div className={`container ${styles.layout}`}>
        <div className={styles.headingBlock}>
          <span className={styles.sectionIndex}>03 / RUNTIME DESIGN</span>
          <Heading as="h2" id="capabilities-heading">面向并行会话与长时间运行</Heading>
          <p>绑定、增量读取与退出回收均有明确的校验条件和保守失败策略。</p>
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
