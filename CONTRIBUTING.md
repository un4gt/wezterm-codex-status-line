# 参与开发

## 获取源码

```sh
git clone https://github.com/un4gt/wezterm-codex-status-line.git
cd wezterm-codex-status-line
```

开发需要 Node.js 20 或更高版本、Python 3.10 或更高版本和 uv。Windows 安装器测试还需要 PowerShell。

以下代码块均从仓库根目录执行。

## 本地运行文档站

```sh
cd website
npm ci
npm run start
```

文档地址为 `http://localhost:3000/wezterm-codex-status-line/`，预览页为 `http://localhost:3000/wezterm-codex-status-line/preview/`。

检查文档构建：

```sh
cd website
npm run typecheck
npm run build
```

构建输出位于 `website/build/`。生产构建检查文档链接。

## 运行 Lua 与 bridge 测试

```sh
python -m unittest tests.test_bridge tests.test_lifecycle_log -v
npx --yes --package=fengari-node-cli fengari tests/core_test.lua
npx --yes --package=fengari-node-cli fengari tests/statusline_lifecycle_test.lua
npx --yes --package=fengari-node-cli fengari tests/statusline_scenario_test.lua
npx --yes --package=fengari-node-cli fengari tests/statusline_resume_test.lua
```

生命周期场景使用虚拟时钟和分屏树。Windows PowerShell 7 还可以运行真实 WezTerm 验证：

```powershell
pwsh -NoProfile -File scripts/run_wezterm_live_test.ps1
```

该脚本使用独立配置和进程，完成后关闭测试进程。日志分析命令：

```sh
python scripts/analyze_lifecycle_log.py
```

## 构建安装包

npm：

```sh
cd packages/npm
npm ci
npm pack
```

`prepack` 会同步资源、检查类型、构建 CLI 并运行测试。

Python：

```sh
node scripts/sync-package-assets.mjs
cd packages/python
uv sync --frozen
uv run python -m unittest discover -s tests -v
uv build
```

两个包都构建完成后，回到仓库根目录检查归档并测试安装：

```sh
python scripts/verify-package-assets.py
python scripts/test_remote_packages.py
```

远程包测试会从临时 HTTP 服务下载归档，在独立目录中检查安装、配置、更新和卸载。访问外网需要代理时，通过 `HTTP_PROXY`、`HTTPS_PROXY` 设置，并在 `NO_PROXY` 中包含 `localhost,127.0.0.1,::1`。

## 修改资源

| 内容 | 源文件 |
| --- | --- |
| Lua 模块和 bridge | 仓库根目录及 `codex_statusline/` |
| 配置结构和默认值 | `contract/config.schema.json`、`contract/default-config.json` |
| 预览渲染 | `contract/render.ts` |
| 模型价格 | `contract/model-pricing.json` |
| 文档和网页 | `website/docs/`、`website/src/` |
| 许可证 | 根目录 `LICENSE` |

包内 `assets/`、包目录中的 `LICENSE` 和网站的公开 schema 由同步脚本生成。修改源文件后运行相应构建。

新增配置项时，同步更新 Lua 默认值、JSON schema、预览和 CLI 校验，以及[配置选项](https://un4gt.github.io/wezterm-codex-status-line/docs/reference/settings/)。

## 编写文档

使用指南围绕用户要完成的操作组织：

- 先说明操作目的，再给可执行的示例，随后解释结果。
- 安装和配置步骤使用简短段落，完整参数放入参考页。
- 说明已实现行为和影响使用的限制；开发讨论、状态迁移和验证记录留在贡献者资料中。
- 使用“窗格”“会话”“字段”等统一术语，配置键、日志名和命令保留原文。

文风参考 [uv 使用指南](https://docs.astral.sh/uv/guides/tools/)和 [Ruff 教程](https://docs.astral.sh/ruff/tutorial/)。

## 发布

`release.yml` 只响应 `v` 加版本号的标签推送，例如 `v0.1.1`。发布前会严格校验 `v<major>.<minor>.<patch>` 格式、两个包的版本与发布说明 `release-notes/<tag>.md`；普通分支推送不会发布包。

首次发布前，在 PyPI 账户的 Publishing 页面创建 Pending Trusted Publisher：项目名 `wezterm-codex-status-line`，GitHub owner `un4gt`，repository `wezterm-codex-status-line`，workflow `release.yml`，environment `pypi`。工作流通过 OIDC 发布，不需要 PyPI token。

工作流构建和测试 npm tarball、Python wheel 与源码包，校验归档资源并验证隔离安装，然后发布 PyPI。PyPI 成功后创建正式 GitHub Release，并附上全部安装包。npm registry 暂不发布，npx 继续使用 GitHub Release 的 tarball。

发布时先提交并推送版本更新，确认 CI 通过，再创建和推送对应标签。已有标签和注册表版本不覆盖；失败的工作流修复后使用适当的新版本，或在无需改代码时重新运行失败的 job。

`deploy-docs.yml` 在 `main` 的网站及相关资源更新时部署 GitHub Pages。推送前运行 `git diff --check` 和与修改相关的检查。

## 实现资料

- [会话绑定与分屏实现](contributing/architecture.md)
- [Codex 原生状态栏源码快照](contributing/upstream-status-line.md)
