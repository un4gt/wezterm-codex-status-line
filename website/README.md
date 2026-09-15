# 文档站点

本目录是 `WezTerm Codex Status Line` 的 Docusaurus 文档站点。

```powershell
npm ci
npm run start
```

生产构建：

```powershell
npm run typecheck
npm run build
npm run serve
```

GitHub Pages 地址：<https://un4gt.github.io/wezterm-codex-status-line/>

交互预览：<https://un4gt.github.io/wezterm-codex-status-line/preview>

`prestart` 与 `prebuild` 会从仓库根目录的 `contract/config.schema.json` 同步公开 schema。不要直接编辑 `static/config.schema.json`。

首次部署需要在仓库 `Settings → Pages` 中将 Source 设为 `GitHub Actions`。
