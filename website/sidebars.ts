import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docsSidebar: [
    'intro',
    {
      type: 'category',
      label: '快速开始',
      collapsed: false,
      items: [
        'getting-started/installation',
        'getting-started/wezterm-config',
        'getting-started/update-uninstall',
      ],
    },
    {
      type: 'category',
      label: '使用指南',
      items: [
        'guides/configuration',
        'guides/display-and-data',
        'guides/how-it-works',
      ],
    },
    {
      type: 'category',
      label: '故障排查',
      items: ['troubleshooting/common-issues'],
    },
    {
      type: 'category',
      label: '参考资料',
      items: [
        'reference/settings',
        'guides/cli-reference',
        'reference/security-and-files',
        'reference/codex-status-line-items',
      ],
    },
    'reference/development',
  ],
};

export default sidebars;
