# 可执行开发路线图

本文件是新主线任务真源。初始状态均为 TODO：技能交付不是产品完成。旧 `PROJECT.md` 保留历史审计用途，不据其阶段名推断本路线图进度。

每个任务完成时附 commit、实际测试命令/结果、未执行的 live 检查和剩余风险；状态只用 TODO / IN_PROGRESS / BLOCKED / DONE。不要一次性把阶段全标完成。

## P0：统一解析与交互闭环

| ID | 状态 | 交付 | 依赖 | 核心验收 |
| --- | --- | --- | --- | --- |
| DEV-01 | DONE | 复核最新 HEAD；复现基线缺口；给选择/启动副作用写回归 | 无 | 失败先复现；不把已有修复重复实现 |
| DEV-02 | TODO | 抽出无副作用模型解析与 LaunchPlan，统一显式/交互/记忆模型路径 | DEV-01 | CFG-01～CFG-05 |
| DEV-03 | TODO | 修复目录请求、认证隔离、缓存和模型绑定状态 | DEV-01 | CAT-01～CAT-04 |
| DEV-04 | TODO | 无参数首页、搜索/收藏/最近、来源详情、返回与取消 | DEV-02, DEV-03 | UX-01～UX-05 |
| DEV-05 | TODO | 接入现有凭证操作的账户向导、批量输入、恢复与脱敏诊断 | DEV-04 | UX-06, AUTH-01～AUTH-03 |
| DEV-06 | TODO | 旧 CLI 与无 TTY 兼容、迁移提示，更新文档而非只加 flags | DEV-04, DEV-05 | UX-01, STATE-01 |

第一个闭环：没有用户自定义配置的测试环境，从主页添加 mock 来源/凭证，搜索模型，确认启动 stub Claude；取消任何一步都没有启动与凭证残留。这个闭环完成后再扩展复杂调度，不先做大而空的数据管理界面。

## P1：原生菜单与可靠自动切换

| ID | 状态 | 交付 | 依赖 | 核心验收 |
| --- | --- | --- | --- | --- |
| DEV-07 | TODO | 原生 modelPicker 最小验证、会话临时 settings、兼容性记录 | DEV-02, DEV-04 | CC-01～CC-03 |
| DEV-08 | TODO | 来源/账户/额度池/CredentialRef 数据关系及旧 registry 迁移 | DEV-05 | AUTH-01～AUTH-04, STATE-01 |
| DEV-09 | TODO | 明确来源集合/锁定、费用边界和备用模型链；默认关闭跨费用/跨模型 | DEV-08 | ROUTE-01～ROUTE-03 |
| DEV-10 | TODO | 错误分类、严格冷却、粘性调度、有限重试、取消与断流处理 | DEV-08, DEV-09 | ROUTE-04～ROUTE-07, STREAM-01～STREAM-03 |
| DEV-11 | TODO | 多会话隔离、共享额度健康、并发刷新和进程归属 | DEV-07, DEV-10 | SESSION-01～SESSION-03 |

菜单兼容性验证应尽早进行，可与 P0 UI 开发并行；如果发现客户端限制，调整实现，不把不能验证的热切换写成已完成。

## P2：完善反代来源与发布

| ID | 状态 | 交付 | 依赖 | 核心验收 |
| --- | --- | --- | --- | --- |
| DEV-12 | TODO | 通用已有 endpoint 向导；适配器能力清单与结构化错误 | DEV-03, DEV-05 | ADAPTER-01, ADAPTER-02 |
| DEV-13 | TODO | 把现有 Antigravity 生命周期接入托管适配器，支持真实可用的登录/状态能力 | DEV-11, DEV-12 | ADAPTER-03, SESSION-03 |
| DEV-14 | TODO | 迁移/回滚、终端回归、版本兼容、文档与完整离线回归 | 前述必要项 | RELEASE-01, 全部适用验收 |

其他 App 反代优先级尚未指定。先查现有代码和用户配置元数据；仍不明确时保留通用接入，不挑一堆陌生项目自动安装。无需为了补齐厂商列表阻塞发布已经验证的能力。

## 实施切片约定

一次变更只解决可验收的纵向流程。给每个变更列：用户动作、负责模块、结构化输入输出、失败恢复、迁移范围、验收 ID。回归测试应覆盖取消/失败/重复执行，而不是只覆盖成功。

可并行：原生菜单兼容性探针、伪终端测试夹具、目录解析纯逻辑。不可无协调并行：核心 schema、同一文件、迁移写入、调度器接口。先分文件所有权，公共接口变动先对齐。

## 迁移与范围控制

- 继续支持已发布的直接 provider 命令、`run`、安装快捷方式及原生 Claude 登录；无参数 TTY 行为变化要明确发布说明。
- 旧 `app` 入口冻结为兼容功能，不新增客户端、不自动删用户选择。首页主流程只包含 Claude Code；遗留 app 选择要解释并引导用户选择来源，不静默改选。
- 先兼容读取旧 provider shell/registry/模型状态，显式迁移到新 schema；不自动执行导入脚本，不扩大计费授权。迁移失败可恢复，重复执行无重复凭证。
- 保留旧模型特定的本地适配能力和 MCP 隔离；新增默认值不得覆盖用户明确选择。
- 不顺手改供应商模型 ID/价格/额度、不扩展遥测上传、不更换技术栈、不自动发布版本。

## 交付记录模板

```text
任务/状态：DEV-xx / DONE 或 BLOCKED
基线与提交：...
实现的用户流程：...
变更文件与兼容性：...
验收 ID 与实际执行证据：...
未执行（例如真实账户、Claude 版本、平台）：...
迁移/回滚与剩余风险：...
```

DONE 表示该任务声明的范围已完成；有 live 门禁未执行时不能把对应兼容性或发布标为通过。文档包自身校验通过不改变 DEV-01～DEV-14 的状态。

## 交付记录

### DEV-01 模型选择器契约（状态：DONE）

基线与提交：基线 HEAD `5af76a7`（`docs: add Claude Code-focused crouter development skill`）。代码与回归测试见提交 `7550f57`（`fix: correct the model picker catalog, pricing, key and cancel handling`）。

实现的用户流程：只做模型选择器这一条纵向流程——目录从哪来（只声明 BASE_URL 的 provider 也能探测到目录）、选完写什么状态（未知窗口不再留下上一个模型的旧窗口）、费率怎么显示（缺失费率显示 unknown，费率按各 provider 目录里的真实形状读取）、按键什么语义（q 是普通字符，Esc、Ctrl-C、EOF、终端挂断是取消）、取消之后怎么办（取消即不启动，退出码可区分取消与出错）。

变更文件与兼容性：

- `bin/crouter-models`：目录探测、模型状态写入、费率读取、TUI 按键与取消语义。旧参数 `--list`、`--list-free`、`--current`、`--set`、`--refresh` 的行为不变。
- `bin/crouter`：`run --browse` 遇取消不再启动 Claude Code；`run --apply-only` 遇未知窗口清掉旧窗口文件。
- `.github/workflows/ci.yml`：Node 语法检查补上 `bin/crouter-models` 与 `bin/openrouter-models`。
- `test/model-picker.sh`、`test/model-picker-tty.py`：新增回归测试与伪终端夹具。

验收 ID 与实际执行证据：

- CAT-01：只声明 BASE_URL 的 provider 现在会被探测目录（`loadModels` 原来只在 API_URL 非空时探测）。
- CAT-03：缺失费率显示 `unknown` 而不是零价；输入免费输出收费不再标 FREE；费率按 `prompt`/`completion`、`input`/`output`、`per_input_token`/`per_output_token`、分档数组四种形状读取——这四种形状取自本机缓存目录，不是猜的。
- CFG-04：选到未知窗口的模型会删除旧窗口文件，`run --apply-only` 同样如此。
- UX-01：管道 EOF 与终端挂断都按取消处理，退出码 2。
- UX-02：`q` 是普通过滤字符。
- CFG-03：取消后不启动 Claude Code、不改已选模型（本次只覆盖“取消”这一半）。
- 证据：`test/model-picker.sh` 8/8 通过；红证据是撤掉改动后同一测试失败，先红在 CAT-01，单跑费率形状用例红在 `CAT-03: tier-free was not recognised as free`。
- 全量对照：`test/*.sh` 在 `sh` 与 `dash` 下，基线 HEAD 与本次改动两次都是全绿。

未执行：

- 没有连真实 provider 拉目录，也没有发任何网络请求验证真实计价；费率形状是拿本机缓存 `~/.local/state/crouter/models-*.json` 核对的。
- 没有在真实 Claude Code 里验证 `--browse` 取消；测试用替身脚本代替 claude。
- 没有读取任何真实凭证。
- 没有验证 macOS 以外的平台。
- 本机没有 shellcheck，CI 里 `shellcheck --severity=warning` 这一步本地没跑；新增测试文件已按仓库现有风格处理变量展开与内层引号，剩余风险由 CI 首次运行确认。

迁移/回滚与剩余风险：

- 回滚：本次新增两个测试文件、修改三个已有文件，回退即恢复 `5af76a7` 行为，无数据迁移，也没有用户状态格式变化。
- 未实现、留给后续任务：
  - PRE_START、认证与 MCP 初始化仍早于选择器执行，取消时这些副作用已经发生（CFG-03 的另一半，属 DEV-02 的 LaunchPlan 拆分）。
  - gateway 最终 5xx 直接回客户端、不做 failover，属 DEV-10。
  - `createCandidateCooldown.order()` 在全部候选冷却时把冷却候选排到队尾，属 DEV-10。
  - `providers/minimax.sh` 把 API key 当套餐 key 用，属 DEV-12。
  - 选择器界面仍是英文，新加的 `unknown` 也是英文，中文交互归 DEV-04 与 DEV-05。
- 并行会话的在途改动没有纳入本次提交：`README.md`、`lib/ollama-heartbeat-proxy.mjs`、`providers/ollama.sh`、`test/ollama-heartbeat-proxy.sh`、`test/unified-routes.sh`，以及 `bin/crouter` 里的 `CROUTER_ALL_EXCLUDE_PROVIDERS` 段。因此工作树上的 `test/provider-matrix.sh` 当前为红（并行改动新增了 context 覆盖项），隔离到本次改动后为绿。
