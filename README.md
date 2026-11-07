# crouter

[![CI](https://github.com/Luckycat133/crouter/actions/workflows/ci.yml/badge.svg)](https://github.com/Luckycat133/crouter/actions/workflows/ci.yml)
![Version](https://img.shields.io/badge/version-0.5.3-blue)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

在 Claude Code 中选择不同模型，管理 API、订阅、多 Key、本地推理和 App 反代来源。**不是其他编程客户端的统一启动器。**

`VERSION` 仍为 0.5.3；本轮是 main 上的未发布开发切片。已跑的局部回归不等于整个仓库或真实账户均通过。详见 [本轮实现与测试交接](docs/provider-refresh-handoff.md)、[2026-11-07 全 provider 审计](docs/provider-refresh-2026-11-07.md) 和历史 [CHANGELOG](CHANGELOG.md)。

## 使用

```sh
./install.sh
crouter
```

安装器只创建 crouter，不覆盖 claude，不再创建 claude-<provider> 快捷方式。要求 POSIX sh、Claude Code 和 Node.js（本轮局部测试使用 22.16）。macOS Keychain 写入仍需要 security 与 expect；平台支持以实际验收为准。

stdin/stdout 均为终端时，裸命令打开中文首页：继续当前模型、搜索模型、Key 增删/用途选择、添加已有目录来源的凭证、刷新模型列表、诊断、同模型付费兜底设置和原生 Claude 登录。搜索中的 q 是普通字符，Esc 返回，Ctrl-C 取消。首页“添加来源”目前是配置现有 provider，不是任意 URL 向导。

目前还没有完整收藏/最近排序、批量 Key、账户/共享额度池或原生 /model 菜单整合。这些是 [开发路线图](.agents/skills/crouter-development/references/roadmap.md) 的后续项。

脚本和直接用法保留：

```sh
crouter list
crouter list --all
crouter use minimax
crouter run -p 'hello'
crouter minimax
crouter moonshot --browse
crouter openrouter --model 'nvidia/nemotron-3.5-super-vl:free'
crouter models openrouter --refresh
crouter models openrouter --list
crouter minimax --model MiniMax-M3.1-Flash --apply-only
crouter claude
```

`run` 不弹菜单；非 TTY 裸命令按已选目标启动，不吞掉 Claude 的 stdin。`--` 可分隔路由参数与剩余 Claude 参数。`--apply-only` 保存模型绑定状态，不运行启动 hook、认证代理、MCP 或 Claude。目录访问是单独的只读操作，可能读取该目录专用凭证，但不发起生成。

显式选择的模型、同一 provider 的上次选择和 provider 默认分别解析。旧模型不会在升级时静默改选；保存的旧 ID 下线时，从首页重新选择。原生 `crouter claude` 保留 Claude 自己的登录；不要将其 OAuth 凭证注入普通模型网关。若自行把本脚本包装为 claude，CLAUDE_BIN 必须指向真正的 Claude 可执行文件；程序拒绝递归。

## 模型目录与配置

下面是声明默认，不是完整目录或账户权益证明。聚合平台通过目录刷新获得更多模型；本地来源以本机安装/反代能力为准，原生云保留 SDK 别名。所有型号依据、保留原因与验证级别见 [审计](docs/provider-refresh-2026-11-07.md)。

| Provider | 声明默认 | 目录策略 |
| --- | --- | --- |
| `302ai` | `claude-sonnet-5-5` | remote |
| `aihubmix` | `coding-glm-5.1-free` | remote |
| `anthropic` | `claude-sonnet-5-5` | remote |
| `antigravity` | `gemini-3.8-flash` | remote |
| `antigravity-claude` | `claude-opus-4-6-thinking` | remote |
| `bedrock` | `sonnet` | native |
| `bonsai` | `ternary-bonsai-2-27b` | static |
| `codex` | `gpt-5.6-sol` | remote |
| `dashscope` | `qwen3.8-max` | static |
| `dashscope-coding` | `qwen3.7-plus` | static |
| `deepseek` | `deepseek-flash[1m]` | remote |
| `fireworks` | `accounts/fireworks/models/glm-5p3-flash` | static |
| `foundry` | `sonnet` | native |
| `huawei` | `glm-5.3` | static |
| `infini` | `glm-5.1` | remote |
| `longcat` | `LongCat-2.5` | remote |
| `meta` | `muse-spark-1.3` | static |
| `minimax` | `MiniMax-M3.1-Flash` | static |
| `moonshot` | `k3.1-pro` | remote |
| `nagaai` | `claude-sonnet-5` | remote |
| `ollama` | `qwen3.8:27b-dflash` | remote |
| `openrouter` | `nvidia/nemotron-3.5-super-vl:free` | remote |
| `ppio` | `minimax/minimax-m3.1-flash` | static |
| `qianfan` | `deepseek-v4-pro` | static |
| `qianfan-coding` | `qianfan-code-latest` | static |
| `qianfan-team` | `deepseek-v4.1-flash` | static |
| `qiniu` | `deepseek/deepseek-v4.1-flash` | static |
| `requesty` | `anthropic/claude-sonnet-5-5` | remote |
| `siliconflow` | `Pro/moonshotai/Kimi-K2.7-Code` | remote |
| `stepfun` | `step-5-preview` | static |
| `tencent` | `tc-code-latest` | static |
| `tencent-coding` | `tc-code-latest` | static |
| `vercel` | `anthropic/claude-sonnet-5.5` | remote |
| `vertex` | `sonnet` | native |
| `xiaomi` | `mimo-v2.6-pro[1m]` | static |
| `z-ai` | `glm-5.3[1m]` | static |

目录缓存按 endpoint、认证形态、计费面和凭证摘要隔离，正常 24 小时有效；刷新失败保留最后有效缓存并标注过期。公开目录不发推理 token；认证目录不会跨 origin 发送 Key，不跟随重定向。未取得价格时显示 unknown，不凭名字含 free 就认定免费。目录可读不代表模型支持全部工具或当前账户有使用权。

模型窗口、输出上限与压缩阈值分别处理；新选择不沿用旧模型窗口。模型特定限制以适配器和实际服务为准，不把公开最大窗口强行注入所有模型。

## Key、订阅与费用边界

首页复用原来的 Keychain/环境引用管理；普通 API key 不再自动复制成套餐 key。原先依赖这种推断的配置需要明确登记真实用途。

```sh
crouter add
crouter add minimax --surface plan
crouter add minimax --surface api
crouter list keys minimax
crouter remove minimax --surface api --name minimax-api-2
password-manager-command | crouter add minimax --surface plan --stdin
```

同一显式 surfaces 来源同时配置套餐和 API 时，默认只使用套餐候选；同模型付费兜底可在首页开启，作用于从首页启动的新会话。脚本/配置可明确设置 CROUTER_ALLOW_PAID_FALLBACK=1；实际 model_map 不同还需另行授权 CROUTER_ALLOW_CROSS_MODEL_FALLBACK=1。只有 API 配置时可正常使用 API。

这不是账单硬限额或完整共享额度管理；旧自定义 dual-source/keypool、上游自身轮换与 Keychain 锁定/拒绝仍有待验收的边界。不得据此承诺所有情形不会产生费用。原有环境/Keychain 凭证不会自动迁移或删除。

## 统一网关与本地来源

```sh
crouter all --check
crouter all
```

网关在 loopback 上按 `<provider>/<model>` 路由，使用随机会话 token。`all --check` 只证明本地结构/凭证发现，不启动 provider，不证明额度或远端权限。CROUTER_ALL_EXCLUDE_PROVIDERS 可排除指定来源，排除发生在凭证发现之前。原生 Bedrock/Vertex/Foundry 认证由 Claude SDK 负责，不加入普通 HTTP 网关。

当前 all 不自动启动所有本地服务；本地反代须先运行。它也不会随模型更换热切 MCP/插件，默认使用严格空会话 profile。GET /v1/models 与真实 Claude 原生菜单兼容是不同验收；不要把目录端点存在当作完整菜单已完成。

Ollama/MLX、Bonsai、Antigravity 和 Codex 反代保留原部署身份与生命周期。浏览本地模型不会安装或启动服务。本地固定端口、Bonsai 的机器特定路径以及共享服务所有权仍需按交接文档在目标机器验证。

## 诊断、配置与迁移

`crouter doctor <provider>` 检查凭证存在性、配置的 health URL 和依赖，不启动服务、不证明模型权益。`provider show`、`config show` 是配置元数据；`config path` 返回本地可编辑文件位置。config.sh 可选且不进入 Git。`logs list` / `logs tail <provider>` 查看现有日志；共享前仍须检查脱敏。

```sh
crouter migrate export ~/crouter.crm
crouter migrate import ~/crouter.crm
crouter migrate verify ~/crouter.crm
```

迁移使用口令保护的 AES-256-GCM/scrypt 包，包含密钥。包和口令分开保存，不能进入 Git。支持 --password-stdin、--portable；导入前审查来源，冲突需要确认，写入失败执行回滚。导入配置不等于授权执行 hooks、安装服务或绕过权限。原生 OAuth/浏览器登录、云 SDK 文件和外部模型/代理需要独立处理。新模型状态 JSON 和 UI 偏好尚需完整迁移回归；不要声称本轮已验收跨机器迁移。

卸载只删除归属于本 checkout 的 crouter 链接：`crouter uninstall -y`。不会按通配符清理其他命令。历史旧快捷链接的人工迁移要验证所有权。

## 开发与验收

按 [开发入口](docs/development-plan.md) 与 crouter-development 执行。新增测试和准确未验证项见 [交接](docs/provider-refresh-handoff.md)。测试只允许假凭证、临时 HOME/XDG 和 loopback；完整 suite 与 ShellCheck 通过前不将当前开发切片当 release。

shell 外壳仍为 POSIX；目录、模型状态、TUI 和路由构建使用 Node 内置模块，无 npm 运行依赖。新增 provider 要有独立计费面/模型映射和一手来源，不扩展客户端启动器。现有 crouter app 仅保留旧兼容。

MIT，见 LICENSE。旧版更详细的历史说明可在 Git 历史查看；当前行为以代码、本轮审计和验收证据为准。
