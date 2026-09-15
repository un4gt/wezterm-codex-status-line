import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const repositoryUrl = 'https://github.com/un4gt/wezterm-codex-status-line';

const config: Config = {
  title: 'WezTerm Codex Status Line',
  tagline: '在 WezTerm 底部查看 Codex 会话状态、上下文与用量',
  favicon: 'img/terminal-mark.svg',

  future: {
    v4: true,
  },

  url: 'https://un4gt.github.io',
  baseUrl: '/wezterm-codex-status-line/',
  organizationName: 'un4gt',
  projectName: 'wezterm-codex-status-line',
  onBrokenLinks: 'throw',

  i18n: {
    defaultLocale: 'zh-Hans',
    locales: ['zh-Hans'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          editUrl: `${repositoryUrl}/edit/main/website/`,
          showLastUpdateAuthor: false,
          showLastUpdateTime: false,
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: 'img/social-card.png',
    metadata: [
      {
        name: 'description',
        content: '为 WezTerm 中的 Codex CLI 提供独立、线程精确绑定的底部状态 pane。',
      },
      {name: 'theme-color', content: '#0d0f12'},
    ],
    colorMode: {
      defaultMode: 'dark',
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'Codex Status Line',
      logo: {
        alt: 'WezTerm Codex Status Line',
        src: 'img/terminal-mark.svg',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docsSidebar',
          position: 'left',
          label: '文档',
        },
        {
          to: '/docs/getting-started/installation',
          label: '安装',
          position: 'left',
        },
        {
          to: '/docs/guides/configuration',
          label: '配置',
          position: 'left',
        },
        {
          to: '/preview',
          label: '预览',
          position: 'left',
        },
        {
          to: '/docs/troubleshooting/common-issues',
          label: '排障',
          position: 'left',
        },
        {
          href: repositoryUrl,
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: '项目导航',
          items: [
            {label: '安装', to: '/docs/getting-started/installation'},
            {label: '配置参考', to: '/docs/guides/configuration'},
            {label: '故障排查', to: '/docs/troubleshooting/common-issues'},
            {label: 'GitHub 仓库', href: repositoryUrl},
            {label: '问题反馈', href: `${repositoryUrl}/issues`},
          ],
        },
      ],
      copyright: `© ${new Date().getFullYear()} WezTerm Codex Status Line · Docusaurus`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.vsDark,
      additionalLanguages: ['bash', 'lua', 'powershell', 'toml'],
    },
    tableOfContents: {
      minHeadingLevel: 2,
      maxHeadingLevel: 3,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
