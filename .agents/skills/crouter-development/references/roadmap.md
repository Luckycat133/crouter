# 可执行开发路线图

状态真源；2026-11-07 这轮实现以 `fdcaf9120b9b4d0bb6c811d0ce75f935435e754d` 为基线。历史事实见 [基线](baseline-and-sources.md)，当前切片见 [本轮交接](implementation-handoff.md)。旧 PROJECT.md 不是当前完成清单。

状态只用 TODO / IN_PROGRESS / BLOCKED / DONE。实现了一部分就写清子项和剩余验收，不据代码存在或单测通过把整个任务标 DONE。当前用户会拉取并让本地 agent 测试：先验证本轮增量、修复集成回归，再继续剩余交互。

## P0

| ID | 状态 | 交付 | 依赖 | 核心验收 |
| --- | --- | --- | --- | --- |
| DEV-01 | DONE | 历史 picker 窄范围修复，见历史记录 | 无 | CAT-01, CAT-03, CFG-04, UX-02, UX-03 的子集 |
| DEV-15 | IN_PROGRESS | 已补 tier helper、防递归、引用安全测试；待全量 CI/集成 | 无 | BUILD-01, CLI-01, CLI-02, CLI-03, CLI-04, CFG-05 |
| DEV-02 | IN_PROGRESS | 选择/保存先于启动、模型绑定窗口已落地；完整 LaunchPlan 待实现 | DEV-01, DEV-15 | CFG-01, CFG-02, CFG-03, CFG-04, CFG-05, CFG-06, AUTH-01 |
| DEV-03 | IN_PROGRESS | 有界目录、认证 origin、缓存、状态已落地；账户 scope 消费与组合异常待验收 | DEV-01, DEV-15 | CAT-01, CAT-02, CAT-03, CAT-04, CAT-05, CFG-06 |
| DEV-04 | IN_PROGRESS | 裸 TTY 首页/搜索/刷新已落地；收藏、最近排序、完整终端恢复待完成 | DEV-02, DEV-03 | UX-01, UX-02, UX-03, UX-04, UX-05 |
| DEV-05 | IN_PROGRESS | 首页复用 Key 增删/用途选择；批量、完整账户/额度池和补偿待完成 | DEV-04 | UX-06, AUTH-01, AUTH-02, AUTH-03 |
| DEV-06 | IN_PROGRESS | run/管道分流、包装防递归已落地；全量旧 CLI/迁移验收待完成 | DEV-04, DEV-05, DEV-15 | UX-01, STATE-01, CLI-01, CLI-02, CLI-03 |

代码边界见仓库根 `docs/provider-refresh-handoff.md`。调用命令的 fixture 可能仍复制旧模块列表；先补真实依赖再判断行为，不跳过失败。不复活 claude-<provider> 或安装 claude 包装链接。

## P1

| ID | 状态 | 交付 | 依赖 | 核心验收 |
| --- | --- | --- | --- | --- |
| DEV-07 | TODO | 真实 Claude modelPicker、临时 settings、版本/权限优先级 | DEV-02, DEV-04 | CC-01, CC-02, CC-03 |
| DEV-08 | TODO | Source/Account/QuotaPool/CredentialRef 与旧 registry 迁移 | DEV-05 | AUTH-01, AUTH-02, AUTH-03, AUTH-04, STATE-01 |
| DEV-09 | IN_PROGRESS | 显式 surfaces 已有费用/跨模型许可；来源锁定、备用链、旧双源边界待完成 | DEV-08 | ROUTE-01, ROUTE-02, ROUTE-03, SESSION-04 |
| DEV-10 | TODO | 严格冷却、错误分类、粘性调度、总重试预算、流式取消 | DEV-08, DEV-09 | ROUTE-04, ROUTE-05, ROUTE-06, ROUTE-07, STREAM-01, STREAM-02, STREAM-03 |
| DEV-11 | TODO | 多会话/额度健康、单飞刷新、进程所有权 | DEV-07, DEV-10 | SESSION-01, SESSION-02, SESSION-03, SESSION-04 |

DEV-09 的初步门禁是独立安全切片，不代表 DEV-08 数据模型已完成。不能宣称全局账单预算或所有上游均无付费风险。需要分别覆盖“Keychain 拒绝”和“未配置”而不是都当缺 Key。

## P2

| ID | 状态 | 交付 | 依赖 | 核心验收 |
| --- | --- | --- | --- | --- |
| DEV-12 | TODO | 任意已有 endpoint 向导、协议/能力契约和错误恢复 | DEV-03, DEV-05 | ADAPTER-01, ADAPTER-02 |
| DEV-13 | TODO | 托管 Antigravity 与真实支持的登录/状态能力 | DEV-11, DEV-12 | ADAPTER-03, SESSION-03 |
| DEV-14 | TODO | 迁移/回滚、真实终端/版本、完整离线门禁和发布材料 | DEV-06, DEV-07, DEV-11, DEV-12, DEV-13 | RELEASE-01, BUILD-01 |

## 当前验收顺序

本轮新增 Node/启动计划/picker → 全 36 provider fixture → 原有认证/资产/路由/生命周期/安装迁移 → 完整 sh/dash 与 ShellCheck → 经授权真实 Claude 与上游。真实验证不可由生成 JSON 或目录成功替代。

完整命令和未执行范围在仓库根 `docs/provider-refresh-handoff.md`；读者必须实际打开，不能只看本表。主线仍是交互而非更多客户端。未指定 App 不阻塞通用接入，也不授权自动安装未知反代。

## 交付记录

### DEV-01 模型选择器契约（历史 DONE）

基线 `5af76a7`，实现 `7550f57d923b06c7af15e3ab263ad54542ce1c05`，记录 `9f81bb01046476d406070b9a8ffef140e7664938`。覆盖 BASE_URL 探测、未知/双边费率、旧窗口文件清理、q/分片按键、取消退出码及调用方不启动 Claude。历史作者记录 picker 8/8 与隔离 sh/dash 回归；当时没有 ShellCheck、真实账户或真实 Claude 验证。该历史 DONE 不等于最新主分支已绿。

完整历史：[9f81bb0 路线图](https://github.com/Luckycat133/crouter/blob/9f81bb01046476d406070b9a8ffef140e7664938/.agents/skills/crouter-development/references/roadmap.md)。不要把历史工作树描述当当前状态。

### 2026-11-07 provider 与交互切片（集成待验收）

更新全部来源审计、28 份远端声明、目录/模型状态/入口模块、基础首页和显式 surface 策略。实际通过：13 个 Node 用例；启动计划及 picker 在 sh/dash 的隔离回归；改动文件语法检查。未执行全仓、完整 36-provider fixture、ShellCheck、真实客户端/Keychain/上游、LLM eval。准确实现边界见本轮交接。发布、安装、真实凭证和 VERSION 均未操作。

### 后续记录格式

任务/状态、基线与实现 commit、具体用户流程和验收子项、实际命令/环境/退出码、CI SHA/run/失败或 skipped、未执行平台/账户、迁移与剩余风险。只有声明范围证据齐备才写 DONE，不删除历史失败制造全绿。
