# 可执行开发路线图

任务状态真源。2026-11-14 复核 `528a2e175c8d93e26dfc1cf2ecd77e73ee7894bd`；事实及来源见 [当前基线](baseline-and-sources.md)，实施切片见 [接续交接](implementation-handoff.md)。不把旧 PROJECT.md 或首次上传时的待测试清单当当前状态。

状态使用 TODO / IN_PROGRESS / BLOCKED / DONE。DONE 限于该任务已声明和证明的范围；整套 CI 通过不自动关闭功能任务。用户本地报告与 CI 执行分别记录。保留历史记录，不为保持数量重编号任务。

## 当前决策

**现有离线集成基线已经恢复，不再把修 CI/重做 36-provider 更新作为下一轮主线。** 优先在 DEV-02/DEV-03 收敛别名、计划与目录消费边界，然后将 DEV-04/DEV-05 做成真实可用的交互闭环。DEV-07 的版本/菜单最小验证可提前并行；DEV-10 的有限重试与严格冷却可独立修，不必等待完整账户 schema 或重写网关。

## P0

| ID | 状态 | 交付 | 依赖 | 核心验收 |
| --- | --- | --- | --- | --- |
| DEV-01 | DONE | 历史 picker 窄范围修复，保留回归 | 无 | CAT-01, CAT-03, CFG-04, UX-02, UX-03 的历史子集 |
| DEV-15 | DONE | 恢复当前集成基线；36-provider、统一路由及现有 sh/dash suite、ShellCheck/Node/版本门禁通过 | 无 | BUILD-01, CLI-01, CLI-02, CLI-03, CLI-04, CFG-05 的现有断言；范围见记录 |
| DEV-02 | IN_PROGRESS | 无启动副作用、模型绑定窗口和 tiers 已有回归；补别名完整入口、保存/启动配置一致和不可变 LaunchPlan | DEV-01, DEV-15 | CFG-01, CFG-02, CFG-03, CFG-04, CFG-05, CFG-06, CFG-07, UX-08, AUTH-01 |
| DEV-03 | IN_PROGRESS | 目录 HTTP/生产端 scope/缓存单测通过；补 inventory/unified 的 scope/时效消费、目录能力组合 | DEV-01, DEV-15 | CAT-01, CAT-02, CAT-03, CAT-04, CAT-05, CAT-06, CFG-06 |
| DEV-04 | IN_PROGRESS | 裸双 TTY 首页和搜索已实现；补收藏/最近、方向键一致性、失败恢复和首页 PTY 闭环 | DEV-02, DEV-03 | UX-01, UX-02, UX-03, UX-04, UX-05, UX-07, UX-08 |
| DEV-05 | IN_PROGRESS | 复用 Key 增删和计费面选择；补批量、用户标签/账号、补偿和拒绝语义 | DEV-04 | UX-06, AUTH-01, AUTH-02, AUTH-03 |
| DEV-06 | IN_PROGRESS | 现有 run/use、stdin/argv、防递归、安装/迁移离线回归通过；新交互集成和真实平台验收仍待完成 | DEV-04, DEV-05, DEV-15 | UX-01, STATE-01, CLI-01, CLI-02, CLI-03 |

不可将 OpenRouter hook 测试当作带空格别名从 `bin/crouter` 可达的证明；不可将 loadCatalog 的 scope 测试当作主页/统一网关已隔离的证明。新反例归入对应功能任务，不回退已确认的历史基线。

## P1

| ID | 状态 | 交付 | 依赖 | 核心验收 |
| --- | --- | --- | --- | --- |
| DEV-07 | TODO | 真实 Claude 菜单最小验证、临时 settings、版本/权限优先级；不只列 /v1/models | DEV-02, DEV-04 | CC-01, CC-02, CC-03 |
| DEV-08 | TODO | Source/Account/QuotaPool/CredentialRef 与 registry 迁移；复用现有引用而非搬动秘密 | DEV-05 | AUTH-01, AUTH-02, AUTH-03, AUTH-04, STATE-01 |
| DEV-09 | IN_PROGRESS | 显式 surfaces 两种许可及正反候选单测通过；来源锁定、备用链、实际请求与旧双源边界待完成 | DEV-08 | ROUTE-01, ROUTE-02, ROUTE-03, SESSION-04 |
| DEV-10 | TODO | 先修最终 5xx failover/严格冷却/取消预算；再接完整错误分类、粘性调度与刷新 | DEV-15 | ROUTE-04, ROUTE-05, ROUTE-06, ROUTE-07, STREAM-01, STREAM-02, STREAM-03 |
| DEV-11 | TODO | 多会话共享健康、单飞刷新、进程租约/所有权与并发更新 | DEV-07, DEV-08, DEV-09, DEV-10 | SESSION-01, SESSION-02, SESSION-03, SESSION-04 |

DEV-10 调整为以已恢复的基线为起点，避免简单可靠性修复被账户重构阻塞；完整交付仍需与 DEV-08/DEV-09 的状态/许可集成。DEV-07 可并行做隔离探针，表中依赖约束其最终集成。默认不扩大费用或跨模型授权，不宣称全局账单硬预算。

## P2

| ID | 状态 | 交付 | 依赖 | 核心验收 |
| --- | --- | --- | --- | --- |
| DEV-12 | TODO | 真正的任意 endpoint/协议/凭证向导，目录缺失时手填模型；不以 Key 菜单冒充 | DEV-03, DEV-05 | ADAPTER-01, ADAPTER-02, UX-07 |
| DEV-13 | TODO | 托管 Antigravity 与确实支持的登录/状态/版本回滚 | DEV-11, DEV-12 | ADAPTER-03, SESSION-03 |
| DEV-14 | TODO | 真实终端/Claude/平台、迁移回滚和发布材料；已有离线绿灯仅为其中一项 | DEV-06, DEV-07, DEV-11, DEV-12, DEV-13 | RELEASE-01, BUILD-01 |

通用“已有反代 URL”接入的最小切片可在 DEV-03/DEV-04 时提前交付，不必等托管安装。不要因此自动安装陌生 App、读取账户全集或增加产品客户端。

## 交付记录

### DEV-01 模型选择器契约（历史 DONE）

基线 `5af76a7`，实现 `7550f57d923b06c7af15e3ab263ad54542ce1c05`，记录 `9f81bb01046476d406070b9a8ffef140e7664938`。覆盖基础目录、价格、旧窗口清理、q/分片按键、取消退出码与调用方不启动 Claude。保留 [原记录](https://github.com/Luckycat133/crouter/blob/9f81bb01046476d406070b9a8ffef140e7664938/.agents/skills/crouter-development/references/roadmap.md) 的历史范围；新 HEAD 的证据另列。

### DEV-15 当前集成基线（DONE，2026-11-14 复核）

实现链：`ac76035c97ba34c5cb4b52ffc4f8520acc594e92`、`7b701d872d00a8274771d159b74f80fe985faa42`，经 PR #4 对齐后落在 `528a2e175c8d93e26dfc1cf2ecd77e73ee7894bd`。

执行证据来自 [CI 43163712510](https://github.com/Luckycat133/crouter/actions/runs/43163712510) / [job 131000571606](https://github.com/Luckycat133/crouter/actions/runs/43163712510/job/131000571606)，2026-11-12 UTC，Ubuntu 26.04.1：ShellCheck 0.11.0、Node syntax、`TEST_SHELL="$shell" "$shell" test/*.sh` 的逐文件 sh/dash 循环、版本元数据检查均 success，后续步骤不是 skipped。日志逐项显示两轮 36-provider fixture、unified-routes、catalog 13 用例、launch-planning、model-picker、凭证/资产/生命周期/迁移以及技能校验通过。

范围：消除首次交付后的现有集成/测试契约阻塞，包括 canonical env、已授权 fallback fixture、消费后的 argv 预期、cleanup 独立 stub。保留 endpoint/header/model_map 断言和未授权候选负例。不是关闭全部 CLI/CFG/STATE 验收，也不是证明所有模型和真实客户端可用。

用户同时报告本地 deepseek 对齐及完整 provider 矩阵/统一路由通过；本地平台、精确命令、SHA 未提供，作为用户报告独立保留，不伪称本轮助手执行。对应远端 DeepSeek 配置已核对；没有据此制造“新提交了 DeepSeek 修复”的记录。

未证明：真实 Claude 菜单、首页完整终端可用性、macOS Keychain 拒绝/锁定、真实供应商推理/计费，以及新发现的调用链反例。本轮为代码/证据审查与技能维护，未修改运行时或读取真实凭证。

### 2026-11-07 provider 与交互切片（历史快照，离线门禁现已补证）

原交付更新 28 份远端声明、保留 8 份本地/原生身份，并提供目录/状态、基本首页和显式 surface 许可。原作者仅跑定向测试，详见仓库 `docs/provider-refresh-handoff.md`。原“未跑全量”的记录保留为当时事实；当前对应离线证据见 DEV-15，不继续列为待做阻塞。功能剩余范围仍见上表，供应商核查日期没有自动刷新。

### 后续记录格式

任务/具体子项、代码 SHA、证据来源（用户报告/本轮执行/CI复核/静态审查）、命令/平台/退出码、CI run 与 skipped、未验证范围、剩余风险。DONE 必须有交付记录和实现 commit；保留可复查证据，不能通过静态文件存在或删除旧失败来制造完成。
