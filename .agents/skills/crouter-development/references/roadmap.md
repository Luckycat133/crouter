# 可执行开发路线图

任务状态真源。最近对照基线为 `554fd5c5e4a0b6cc8b198565de8c2b4a3495a558`；审阅日期 2026-11-07。事实与 CI 证据见 [基线与来源](baseline-and-sources.md)。旧 PROJECT.md 仍是历史审计，不代表本轮产品进度。

状态使用 TODO / IN_PROGRESS / BLOCKED / DONE；TODO 可以包含已落地子项，需写清剩余验收，不能把部分实现升级成整体完成。按优先级和依赖选择任务，不按编号大小。新任务追加 ID，不能为了维持固定数量重编号旧任务。

## 当前接续顺序

DEV-01 保留历史窄范围 DONE。**先执行 DEV-15 的当前基线修复与核验，再推进 DEV-02 / DEV-03，最后完成 DEV-04 / DEV-05 的交互闭环。** 原生菜单的只读文档/版本探针可并行。用户只要求更新技能时，仅维护这些材料，不执行路线图里的运行时修复。

## P0：可信基线、统一解析与交互闭环

| ID | 状态 | 交付 | 依赖 | 核心验收 |
| --- | --- | --- | --- | --- |
| DEV-01 | DONE | 历史选择器缺口修复与回归，范围见交付记录 | 无 | CAT-01, CAT-03, CFG-04, UX-02, UX-03 的已记录子集 |
| DEV-15 | TODO | 修复当前 CI 的参数拆分；核对新 tier helper、CLI 入口与退役快捷方式的测试/文档；建立当前 SHA 基线 | 无 | BUILD-01, CLI-01, CLI-02, CLI-03, CLI-04, CFG-05 |
| DEV-02 | TODO | 纯模型解析与 LaunchPlan；统一显式/交互/记忆选择；先核对套餐凭证隔离 | DEV-01, DEV-15 | CFG-01, CFG-02, CFG-03, CFG-04, CFG-05, CFG-06, AUTH-01 |
| DEV-03 | TODO | 目录 HTTP/认证/query/取消；保留有效缓存；来源与模型绑定状态 | DEV-01, DEV-15 | CAT-01, CAT-02, CAT-03, CAT-04, CAT-05, CFG-06 |
| DEV-04 | TODO | 裸命令首页、中文搜索/收藏/最近、来源详情、返回与取消 | DEV-02, DEV-03 | UX-01, UX-02, UX-03, UX-04, UX-05 |
| DEV-05 | TODO | 账户/订阅/Key 向导、批量输入、失败补偿、脱敏诊断 | DEV-04 | UX-06, AUTH-01, AUTH-02, AUTH-03 |
| DEV-06 | TODO | 完成新 TTY 入口与脚本/原生 CLI 兼容、旧状态迁移说明 | DEV-04, DEV-05, DEV-15 | UX-01, STATE-01, CLI-01, CLI-02, CLI-03 |

DEV-15 不重新实现 q 搜索、BASE_URL 探测或免费价格判断；它让已存在修复在最新集成下可验证。修复 CI 后继续读后续检查结果，禁止只将 ShellCheck 变绿就宣称基线全部通过。

DEV-02 必须同时测“取消后没有 Claude”与“取消前没有 hooks/代理/assets”；检查旧 context 文件已删但内存值仍残留的路径。DEV-03 只完成目录/状态剩余部分，不重做已有选择器。

DEV-06 已有的子项是仅安装 crouter、删除连字符快捷入口；这些不是待恢复功能。尚未完成的是交互主入口、无 TTY 行为、包装入口防递归及迁移体验。DEV-15 负责先建立现状回归，DEV-06 负责与新交互集成。

首个产品闭环：隔离环境内从主页添加 mock 来源与假凭证，搜索模型，确认启动 stub Claude；任一步取消都无启动和半成品凭证。先交付可操作流程，不先建庞大配置平台。

## P1：原生菜单与可靠自动切换

| ID | 状态 | 交付 | 依赖 | 核心验收 |
| --- | --- | --- | --- | --- |
| DEV-07 | TODO | 真实版本 modelPicker 最小验证、临时 settings、优先级与能力记录 | DEV-02, DEV-04 | CC-01, CC-02, CC-03 |
| DEV-08 | TODO | 来源/账户/额度池/CredentialRef 关系及旧 registry 迁移 | DEV-05 | AUTH-01, AUTH-02, AUTH-03, AUTH-04, STATE-01 |
| DEV-09 | TODO | 来源集合/锁定、费用边界和备用模型链；接续已有会话排除能力 | DEV-08 | ROUTE-01, ROUTE-02, ROUTE-03, SESSION-04 |
| DEV-10 | TODO | 错误分类、严格冷却、粘性调度、总重试预算、取消与断流 | DEV-08, DEV-09 | ROUTE-04, ROUTE-05, ROUTE-06, ROUTE-07, STREAM-01, STREAM-02, STREAM-03 |
| DEV-11 | TODO | 多会话隔离、共享健康、并发刷新和进程所有权 | DEV-07, DEV-10 | SESSION-01, SESSION-02, SESSION-03, SESSION-04 |

modelPicker 的文档支持不代表目标 Claude 版本已实测；临时 --settings 中菜单是整份覆盖，不能假设客户端自动合并用户菜单。网关目录发现是另一条机制。

## P2：反代来源与发布

| ID | 状态 | 交付 | 依赖 | 核心验收 |
| --- | --- | --- | --- | --- |
| DEV-12 | TODO | 已有 endpoint 向导、协议/能力清单、结构化错误 | DEV-03, DEV-05 | ADAPTER-01, ADAPTER-02 |
| DEV-13 | TODO | 复用 Antigravity 生命周期，接入真实支持的登录/状态能力 | DEV-11, DEV-12 | ADAPTER-03, SESSION-03 |
| DEV-14 | TODO | 迁移/回滚、终端回归、客户端版本记录、文档与完整离线回归 | DEV-06, DEV-07, DEV-11, DEV-12, DEV-13 | RELEASE-01, BUILD-01, 所有适用验收 |

未指定其他 App 优先级不阻塞通用接入；不凭目录名自动安装陌生反代。直接原生 Claude 登录与代理来源保持边界。

## 实施、迁移与授权

每个切片记录用户流程、模块、输入输出、失败恢复、验收与迁移范围。接口/schema、同一文件或迁移写入不能无协调并行；先分文件所有权。保留用户未提交改动，不替用户选择另一套账户或计费策略。

支持当前有效的 provider/run/use 和原生登录。退役快捷方式不复活；清理旧链接须逐项证明属于该 checkout，不能按 claude-* 通配符删除。现有 app 仅兼容、不扩展、不静默改用户保存的选择。无参数 TTY 行为更改要发布说明，stdin 继续属于 Claude。

旧配置兼容读取、显式迁移、失败可回滚；不执行导入代码、不扩大费用授权。供应商 ID/价格、技术栈和遥测不顺手改。技能更新不升级 VERSION、不修无关运行时、不修改 pre-push 或弱化 CI。

## 交付记录

### DEV-01 模型选择器契约（历史 DONE）

基线 `5af76a7`，实现提交 `7550f57d923b06c7af15e3ab263ad54542ce1c05`，交付记录提交 `9f81bb01046476d406070b9a8ffef140e7664938`。覆盖 BASE_URL 探测、未知/双边费率、未知窗口的文件清理、q/分片按键、取消退出码及调用方不启动 Claude。CI 增加两个 picker 的语法入口。

历史执行报告：test/model-picker.sh 8/8，撤销修复后的红测试，以及隔离变更的 sh/dash 全量对照。未执行真实 provider、真实 Claude、真实凭证和非 macOS 验证；当时本机缺 ShellCheck。此处是历史作者记录，本轮没有重新运行或认证这些结果。

完整原记录保存在 [9f81bb0 的路线图](https://github.com/Luckycat133/crouter/blob/9f81bb01046476d406070b9a8ffef140e7664938/.agents/skills/crouter-development/references/roadmap.md)。当时“工作树改动未提交”的描述只适用于当时；不要复制为当前状态。当前 SHA 的 CI 失败与后续 skipped 见基线参考。

### 后续交付模板

```text
任务/状态：DEV-xx / DONE 或 BLOCKED
基线与实现 commit：...
用户流程与验收 ID（具体子项）：...
实际命令、环境、退出码与脱敏证据：...
CI SHA / run / 已执行或 skipped：...
未执行：真实客户端/平台/上游/LLM 行为评测...
迁移/回滚、剩余风险、后续任务：...
```

只有声明范围的证据齐备才写 DONE。技能结构通过不更新产品状态；历史任务 DONE 不代表最新 SHA 通过。基线修复后更新 DEV-15 和证据，不删除历史失败记录来制造持续全绿的印象。
