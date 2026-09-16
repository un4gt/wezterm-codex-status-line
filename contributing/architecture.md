# 工作原理

## 1. 识别当前 pane 中的 Codex

模块从 `pane:get_foreground_process_info()` 返回的当前 pane 进程信息开始：

1. 检查前台节点及其子树中的 Codex 进程。
2. 当前台程序是 Codex 启动的 shell、Git 或 MCP 工具时，沿父进程链向上查找 Codex。
3. 到达 WezTerm 进程边界后停止。

默认识别原生 `codex` / `codex.exe`，以及 argv 中包含 `/@openai/codex/bin/codex.js` 的 npm wrapper。向上查找时不会扫描父进程的其他后代，因此不会把同一 WezTerm 进程下其他 pane 的 sibling 进程作为当前会话。

生命周期区分 `running`、`exited` 与 `unknown`。进程 API 暂时不可用时，已有绑定和最后数据会保留，不因缓存宽限到期而回收；明确退出后才开始关闭宽限计时。

## 2. `SessionStart` 写入 pane/thread 映射

安装器把 handler 合并到 `$CODEX_HOME/hooks.json`。Codex 触发 `SessionStart` 后，bridge 从环境变量读取 `WEZTERM_PANE`，再解析 hook payload，写入：

```text
$CODEX_HOME/wezterm-statusline/panes/<pane-id>.json
```

mapping schema 1 包含 pane ID、thread ID、hook session ID、rollout 路径、CWD、session source、随机 generation 和写入时间。

在 Windows Terminal、VS Code Terminal 等环境中没有数字形式的 `WEZTERM_PANE`。bridge 会在读取 stdin 之前以成功状态退出，不创建 mapping。

## 3. 校验 mapping

Lua 在读取 rollout 前检查：

1. mapping schema 是否为 1，pane ID 是否与当前 pane 一致。
2. thread ID 是否为 UUID 格式，generation 是否存在且未被当前 pane 生命周期淘汰。
3. mapping CWD 与当前 Codex CWD 是否一致（两者都可用时）。
4. rollout 路径是否位于当前 `$CODEX_HOME` 内。
5. rollout 的 `session_meta.id` 是否与 mapping thread ID 一致。

校验失败时不会继续使用该 rollout 的旧数据。

## 4. 处理 `codex resume` 的映射窗口

`auto` 模式在 bridge manifest 存在时以精确 mapping 为主。resume 后 mapping 暂时缺失、已淘汰、CWD 不匹配或 rollout 尚不可用时，可以启用受限活动回退。

候选必须同时满足：

- rollout CWD 与 pane CWD 完全一致；
- 活动时间不早于当前 Codex 进程启动时间（允许配置的 clock skew）；
- 活动时间位于配置的最大年龄范围内；
- 只有一个候选。

新 mapping 到达后立即切回精确绑定。`hook` 模式不执行这项回退；多候选或无新活动时保持等待。

## 5. 增量读取 rollout

模块为每个 pane 保存 rollout offset，按 `tail_ttl_seconds` 读取新增 JSONL。文件被截断或替换时会重置 offset。

session 索引用于定位候选 rollout，并按较长 TTL 缓存；它不会在每次 `update-status` 事件中完整重读所有 transcript。解析器只处理当前显示所需的 session metadata、turn context 和 token usage。

## 6. 合并显示数据

主要数据优先级：

| 数据 | 首选来源 | 回退来源 |
| --- | --- | --- |
| model | 最新 turn context | user var 或 Codex 配置 |
| reasoning | 有效 terminal title | turn context、user var 或 Codex 配置 |
| provider | rollout session metadata | user var 或 Codex 配置 |
| CWD | rollout session metadata | 当前 pane CWD |
| Git branch | 对当前 CWD 执行本地 Git 查询 | rollout 启动 metadata |
| token/context | 当前 rollout 的 `token_count` | 无数据时显示等待状态 |

Git 命令以参数数组执行：

```text
git -C <pane-cwd> branch --show-current
```

渲染刷新路径不会发起网络请求。

## 7. Terminal title

启用 title bridge 后，Codex 会为新会话生成类似标题：

```text
codex | high | app
```

Lua 解析 app name、reasoning 与 project 部分。MCP 子进程可能临时改变控制台标题；只要进程树仍确认 Codex 活跃，标题变化本身不会被视为退出。

## 8. 状态 pane 生命周期

- 每个 Codex owner pane 独立绑定状态栏，同一 tab 可以存在多个；切换到普通 pane 不会回收其他 owner 的状态栏。
- 通过 `owner:split({direction = "Bottom", top_level = false})` 创建 1 或 2 行局部 pane，另外占一行分隔线，至少保留 5 行给 owner。
- 状态 pane 运行本地 idle shell；渲染使用 `pane:inject_output()`，不会向 stdin 发送命令。
- `prevent_focus = true` 时，创建或点击状态 pane 后尝试把焦点还给主 pane。
- 布局签名包含 pane ID、坐标、尺寸和 zoom 状态，不包含焦点。连续两次以上采样稳定且经过 `layout_debounce_ms` 后才创建或归位；内容照常刷新。
- 拖动后的状态栏高度保持不变。复杂分屏错位时保持原位，不调整邻居；仅当 tab 内只有 owner 与其状态栏时允许关闭旧栏后重新局部分屏。
- Codex 明确退出后，模块通过当前 GUI socket 调用后台 `wezterm cli --no-auto-start kill-pane --pane-id <id>`。确认旧 ID 消失前不创建新栏，10 秒超时后停止重试，继续观察。
- pane ID 不可确认、等于主 pane ID，或安全关闭 API 不可用时，模块保留状态 pane 并记录错误。
- 后台 tab 每 2 秒检查已管理 owner，前台才创建或归位；owner 移动到其他 tab 后先清理旧状态栏。
- 手动关闭状态栏视为当前进程批次隐藏；新 Codex 批次或 `codex-statusline-show` 事件恢复，无默认快捷键。
