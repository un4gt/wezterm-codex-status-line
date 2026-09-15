---
sidebar_position: 3
title: 开发与验证
description: 了解源码事实源、生成文件、测试命令与文档发布流程。
---

# 开发与验证

## 源码事实源

| 内容 | 事实源 | 生成或同步目标 |
| --- | --- | --- |
| WezTerm runtime | 根目录 `codex_statusline*.lua`、`codex_statusline/` 与 bridge 文件 | npm/Python 包内 `assets/` |
| 配置 contract | `contract/config.schema.json`、`default-config.json`、render fixtures | 两个包与 `website/static/config.schema.json` |
| 预览渲染 | `contract/render.ts` | npm/Python/Web 测试共同核对的行为 |
| 文档站 | `website/docs/`、`website/src/` | `website/build/` |

不要手工修改两个包的 `assets/` 或 `website/static/config.schema.json`。对应同步命令会覆盖这些文件。

## Runtime 检查

```powershell
python -m unittest tests.test_bridge -v
python -m unittest tests.test_lifecycle_log -v
python -m py_compile codex_statusline_bridge.py scripts\analyze_lifecycle_log.py tests\test_bridge.py

npx --yes --package=fengari-node-cli fengari tests/core_test.lua
npx --yes --package=fengari-node-cli fengari tests/statusline_lifecycle_test.lua
npx --yes --package=fengari-node-cli fengari tests/statusline_scenario_test.lua
npx --yes --package=fengari-node-cli fengari tests/statusline_resume_test.lua
```

`tests/statusline_scenario_test.lua` 使用虚拟时钟和二叉分屏树，覆盖多 owner、左右分屏、焦点、尺寸变化、防抖、unknown、迁移和异步关闭，并检查 50 次创建与回收的行数守恒。现场复现后可分析最新 WezTerm 日志：

```powershell
python scripts/run_lifecycle_tests.py
python scripts/analyze_lifecycle_log.py
```

分析器默认只检查最近一次模块加载后的事件，会报告退出关闭延迟、重启后未创建新状态 pane，以及持续访问已删除 pane 等生命周期异常；`--all-loads` 可检查完整历史，`--json` 可生成适合 issue 附件或自动比较的结构化结果。

本机有兼容 Lua 5.4 工具链时，也可以执行语法与原生 Lua 测试：

```powershell
lua54 tests\core_test.lua
lua54 tests\statusline_lifecycle_test.lua
lua54 tests\statusline_scenario_test.lua
lua54 tests\statusline_resume_test.lua
luac54 -p codex_statusline.lua
luac54 -p codex_statusline_core.lua
```

## 包资源与 CLI

先同步并验证生成资源：

```powershell
node scripts\sync-package-assets.mjs
python scripts\verify-package-assets.py
```

npm CLI：

```powershell
cd packages\npm
npm ci
npm run typecheck
npm test
npm run build
npm pack --dry-run
```

Python CLI：

```powershell
cd packages\python
uv sync --frozen
uv run python -m unittest discover -s tests -v
uv build
uv run wezterm-codex-status-line --help
```

## 文档站点

```powershell
cd website
npm ci
npm run typecheck
npm run build
npm run start
```

`prestart` 与 `prebuild` 会先同步公开 schema。生产输出位于 `website/build/`；Docusaurus 构建将断链视为错误。

修改字段、默认值或渲染规则时，至少同步检查：

1. 根目录 Lua 默认值和 `contract/render.ts` 是否一致。
2. `config.schema.json` 与 `default-config.json` 是否一致。
3. npm、Python 与网页的导入校验是否一致。
4. CLI 预览、网页预览与 Lua fixture 是否覆盖相同列宽。
5. 用户文档只描述已实现行为；未实现设计保留在仓库内部文档中，不加入用户侧栏。

## WezTerm 加载检查

仅在方便操作本机 WezTerm 时执行：

```powershell
wezterm --config-file .\tests\wezterm_test_config.lua show-keys --lua
```

测试、构建和安装脚本不得主动 reload 用户正在使用的 WezTerm。

Windows PowerShell 7 可运行真实 GUI 隔离验证：

```powershell
pwsh -NoProfile -File scripts/run_wezterm_live_test.ps1
```

独立 class 与配置文件不加载个人设置。测试桩提供进程信号，真实 API 完成分屏、绘制和回收，核对 50 次循环的行数、右侧普通 pane 和焦点，再检查复杂布局不被重排。结果写入临时目录，完成或超时后只关闭测试进程树；测试不会启动 Codex 或发起模型调用。

运行代码按 `domain/` 纯算法、配置/数据源、格式化/渲染、`layout`/`state`/`lifecycle` 与 `wezterm_adapter` 分层。兼容入口和配置 schema 1 保持不变，内部状态迁移至 schema 8。

## CI 与 Pages

CI 在 Windows、macOS 与 Linux 上运行 bridge、Lua、两套 CLI 和资源一致性检查；网站 job 单独执行 `npm ci`、类型检查和生产构建。

`deploy-docs.yml` 在 `main` 的网站、contract 或 runtime 相关文件变化时构建 GitHub Pages。仓库管理员首次部署前需要在 `Settings → Pages` 中把 Source 设为 `GitHub Actions`。

## 发布前清单

1. `git diff --check` 无空白错误。
2. 四组 Lua 测试、bridge 测试和两套 CLI 测试通过。
3. 生成资源已同步，`verify-package-assets.py` 通过。
4. npm tarball 与 Python wheel 包含同版本资源和 contract。
5. `doctor`、安装、更新与安全卸载在隔离用户目录中完成 smoke test。
6. Docusaurus 类型检查和生产构建通过，关键页面在桌面与移动宽度下无溢出。
