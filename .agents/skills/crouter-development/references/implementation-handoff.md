# 当前接续交接

先读 [基线证据](baseline-and-sources.md) 和 [路线图](roadmap.md)。2026-11-14 已确认 `528a2e1` 的 CI 完成现有 sh/dash 离线门禁。用户报告的本地 36-provider/统一路由通过独立记录。不要再让下一位 agent 重做“第一次全量验收”，也不要把已有绿灯当作后续代码改动免测。

## 已有成果应直接复用

目录规范化与有界 HTTP、模型绑定窗口、选择先于启动、basic 中文双 TTY 首页、Key 增删、明确套餐/API 凭证、两种独立 fallback 许可、原生登录/环境/MCP/生命周期隔离及现有矩阵均已有代码和离线回归。`docs/provider-refresh-handoff.md` 是首次交付的历史快照，不是当前任务清单。

## 下一批可验收切片

### A：同一选择得到同一运行配置（DEV-02 / DEV-03）

从真实入口覆盖 `qwen3.8 27b` 等显式别名，先规范化受支持别名再验证 canonical ID；退役免费别名仍明确拒绝。不要只 eval PRE_START。核对 apply-only、浏览、记忆与启动的最终 model/context/effort/tier/required services，抽出小型纯解析结果即可，不需要先重写全部 provider。

让 loadCatalog、inventory、unified 消费同一份已验证目录视图：来源、endpoint、计费面、账户的非秘密身份与时效均有边界。不要为了检查 scope 在首页解密所有 key；可使用受控账号引用/版本或失效标记。A 账户/旧 endpoint 目录不进入 B 的首页或路由；显式离线缓存需要标注来源/过期，不代表权益。

验收：CFG-01～CFG-07、CAT-04/CAT-06 的本切片，补真实 dispatcher 和消费端反例。保存新默认与立即启动分别表达；失败不能静默破坏旧默认或假记最近成功（UX-08）。

### B：把已有首页做顺手（DEV-04 / DEV-05，主产品增量）

优先模型搜索、收藏、最近、来源/计费状态、方向键/返回一致性；加入从裸 crouter 开始的 PTY 测试，而不是只跑 picker。新来源必须实际可配置地址/协议/认证与手填模型，或把尚未支持的菜单准确命名为“配置内置来源”，不能用同一个 keys() 冒充两种流程。

账户管理先交付命名/暂停/优先级、批量 Key 预览去重与确认、失败补偿；额度池只保存已知共享关系，不虚构余额。费用设置必须说明“没有套餐、只有 API”仍是按量来源，不能显示成任何情况下都不付费。

验收：UX-01～UX-08、AUTH-02/03，任一步取消零半成品；操作失败能原地返回和修复。自定义已有 endpoint 最小切片可提前接 DEV-12，不等托管安装。

### C：与交互并行收紧可靠性（DEV-10）

保持现有代理，先用两个 loopback 上游验证首候选持续 503 后到第二候选、所有候选冷却时零早退请求、客户端取消终止上游/timer、部分 SSE/tool_use 后不重放。使用 fake clock/请求计数和总预算，不靠增加重试次数掩盖错误。该切片不必等完整账号 schema；后续再对接账户级错误分类与单飞刷新。

### D：Claude 内菜单最小验证（DEV-07）

在经授权的真实目标 Claude 版本，验证两个不同模型的可见项与实际请求 ID；同时记录用户 settings/managed 策略和不兼容历史的处理。只有 mock/配置 JSON 时标未完成。不要先做跨客户端适配，也不要通过假 Claude ID 规避能力检查。

## 测试与交付

只更新技能：结构校验、校验器反例、链接/ID/依赖一致性；读取当前 CI 即可，无需制造运行时改动。

实现上述切片：先复用 `test/catalog.sh`、`test/launch-planning.sh`、`test/model-picker.sh`、`test/provider-matrix.sh`、`test/unified-routes.sh`，按改动补反例；跨模块广泛改动按 CLAUDE.md 运行完整 sh/dash 门禁。保留固定 golden，不自动生成期望值。

每次报告分别给出本轮运行、复核已有 CI、本地用户报告和未执行部分。GitHub 中的 stub security/claude 与本地 mock 不代表真实账户验证。发布、安装、登录、读取真实凭证与付费推理仍依赖当前授权。
