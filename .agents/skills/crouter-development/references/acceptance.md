# 验收矩阵与技能评测

验收 ID 是要求，不是通过标记。先看 [当前基线](baseline-and-sources.md) 的 SHA/CI/用户报告，再读下方证据映射。复合项按实际断言给出覆盖子集；CI 全绿只证明已存在测试通过。

## 产品回归

| ID | Given / When | Then |
| --- | --- | --- |
| UX-01 | TTY 裸 crouter；无选择、有选择、管道 stdin 分别运行 | 主页/向导正确；非 TTY 不挂起、不消费 Claude stdin，run 脚本兼容 |
| UX-02 | 搜索 qwen、中文名称、粘贴多字符、逐字与分片输入 | q 不退出，Unicode 不截断，结果稳定；复用已有 picker 回归 |
| UX-03 | 有旧模型时取消选择，或向导中返回/取消 | 不启动旧模型、不产生部分保存、不写真实凭证；另以 CFG-03 测启动前副作用 |
| UX-04 | 小终端、resize、无颜色、异常、SIGINT/SIGTERM | 界面可用，raw mode、光标和屏幕恢复 |
| UX-05 | 已配置常用模型，搜索并回车 | 不反复追问 provider/key/effort，可收藏和恢复最近选择 |
| UX-06 | 一次粘贴多 key，含空行/重复/写入失败 | 不泄密去重，取消不落盘，部分失败补偿或准确报告 |
| CFG-01 | positional、--model、TUI 和记忆路径选择相同模型 | 得到等价 LaunchPlan；同一应用操作而非两套逻辑 |
| CFG-02 | Ollama 改选 MLX，或切换模型特定 effort/插件 | 新配置先解析，再启动正确服务；无旧服务副作用 |
| CFG-03 | 浏览、取消、apply-only；hooks/代理/assets/凭证访问放 spy | 不执行启动 hooks、代理/MCP 初始化或推理；目录专用认证单独授权 |
| CFG-04 | 大窗口切到未知或小窗口模型 | context/output/compact/effort 不泄漏；磁盘状态和最终 child env 都检查 |
| CFG-05 | 单模型模式与显式辅助分工分别换主模型 | 单模型映射统一，明确分工保留；helper 存在且 stderr 无 command not found |
| CAT-01 | 仅 BASE_URL、专用目录认证、URL 含 query | 请求构造正确且可达；认证不串 origin；不能只凭基础探测通过就关闭整项 |
| CAT-02 | 目录超时、非 2xx、空/畸形数据、分页、取消 | 有界请求；保留最后有效缓存并标注过期，不用错误覆盖目录 |
| CAT-03 | 费率缺失、输入零但输出收费、不同费率形状 | 显示未知或真实费率，不误标免费；单位/分档有来源证据 |
| CAT-04 | 同 provider 不同 endpoint、计费面或账户的权限不同 | 缓存按适用范围隔离；公共目录不冒充账户权益 |
| AUTH-01 | 仅 API key，无套餐 key | 不复制为套餐凭证，不标记订阅已配置 |
| AUTH-02 | 环境引用、Keychain 拒绝/锁定、portable 凭证加载 | 区分缺失与拒绝；秘密不进 argv/log/报告，不静默丢失 |
| AUTH-03 | 添加、更换、删除 key 中途写入失败 | 元数据与凭证一致、回滚可验证、不删无关凭证 |
| AUTH-04 | 两把 key 共用额度池 vs 共享关系未知 | 已知共享限制同步；未知不造独立余额或恢复时间 |
| ROUTE-01 | 订阅耗尽，仅剩 API，未授权付费兜底 | API mock 零请求，明确说明费用边界 |
| ROUTE-02 | 锁定来源或禁用跨模型 fallback | 不解锁、不换模型，迁移不扩大授权 |
| ROUTE-03 | 允许同模型跨来源和显式备用模型链 | 只用允许且能力兼容的候选，来源/模型变化可见 |
| ROUTE-04 | 401 刷新后成功，并发凭证同时过期 | 刷新单飞且有界；失败转 reauth，不死循环 |
| ROUTE-05 | 403 模型权限、429 Retry-After、402 耗尽 | 错误作用域正确；fake clock 到期前不打冷却候选，不造恢复时间 |
| ROUTE-06 | 首候选持续 503、第二候选成功；或全候选冷却 | 策略内 failover；总次数/deadline 有界，无忙循环 |
| ROUTE-07 | 上游也重试；请求发送后断网、结果未知 | 避免重试乘法，说明不确定结果，不承诺 exactly-once |
| STREAM-01 | 部分 SSE/tool_use 后断流 | 不拼接第二候选，不重放已输出工具调用 |
| STREAM-02 | 客户端取消/断开时有 timer 或静默上游 | 终止上游与 timer，释放资源，取消后无新请求 |
| STREAM-03 | 工具回合、心跳、usage、上游错误 | 事件关联与透传正确，错误脱敏且保留有效类型 |
| SESSION-01 | 两会话用不同模型，再修改默认选择 | 默认和活动会话隔离，在途请求不串模型 |
| SESSION-02 | 共享额度/刷新状态时增删凭证 | 原子更新、快照一致、失效引用明确报错 |
| SESSION-03 | 两会话复用代理，结束其一；端口有他人进程 | 不误杀共享/非所属进程，可检测所有权变化 |
| CC-01 | 真实支持版本加载会话临时 modelPicker | 菜单可见且实际请求 model 正确，不只检 JSON |
| CC-02 | 旧版本、用户 --settings、managed allowlist | 正确降级/冲突提示；整份菜单优先级被验证，不写全局文件 |
| CC-03 | 小窗口、不同模态、工具历史、MCP 的不兼容切换 | 不丢历史、不谎称无损热切，原生登录不受影响 |
| ADAPTER-01 | 自定义 endpoint 有目录或无目录 | 均可配置；目录失败不等同于推理失败 |
| ADAPTER-02 | 上游不支持账户管理或已持有调度权 | 明确 unsupported 或来源级调度，不造账户/额度 |
| ADAPTER-03 | 托管反代安装失败、需登录、刷新失败、升级回滚 | 有恢复路径，未授权不安装/登录，生命周期正确 |
| STATE-01 | 迁移、重复迁移、损坏文件、并发、符号链接攻击 | 不丢配置/凭证、不扩权，原子写/权限/回滚正确 |
| RELEASE-01 | 干净 checkout 安装卸载，旧用户配置存在 | 仅安装当前入口，版本一致，保留无关文件，真实验证范围明确 |

## 集成与调用链回归

| ID | Given / When | Then |
| --- | --- | --- |
| BUILD-01 | 当前 SHA 的 CI；带空格路径；同时考虑成功和提前失败 | 按实际 job/步骤/断言记录结果；失败后的 skipped 不算通过，成功也不代表未写反例已覆盖 |
| CLI-01 | crouter provider、run、use、原生 claude 路径及参数转发 | 保持有效契约；stub 的 argv/stdin/env/退出码准确，帮助无启动副作用 |
| CLI-02 | 脚本以 claude 命名，PATH 中包含包装器；显式/未设真实 CLAUDE_BIN | provider 分发与原生子命令可区分；防止自调用循环，不覆盖真实 CLI |
| CLI-03 | 安装/卸载，旧 claude-* 残留、另一 checkout 链接和同名普通文件 | 不新建退役入口；不删除无关文件，残留迁移策略明确且可重复 |
| CLI-04 | helper 调用有缺失、stderr 有错误但后续命令返回 0 | 回归能捕获缺失 helper 与错误映射，不能只检查最终退出码 |
| CFG-06 | 先加载旧 provider-context，再选未知窗口或显式另一模型 | 不把旧内存值重新保存或传给 child；同时测 browse、--model、apply-only |
| CAT-05 | 交替加载带/不带目录字段的 provider；非 2xx 却有 data 数组 | 目录字段重置；query 保留、状态先判定；凭证 origin 隔离 |
| SESSION-04 | CROUTER_ALL_EXCLUDE_PROVIDERS 排除来源，另开直接启动和其他会话 | 排除早于凭证发现且不进目录；不泄漏到直接启动或其他会话，不冒充完整策略 UI |
| CFG-07 | 从 bin/crouter 传入受支持的带空格别名、canonical ID、退役免费别名；比较保存与启动 | 受支持别名先规范化再验证；退役路由不转收费；apply-only 与最终启动的 model/context/effort/tier 一致，不能仅 eval hook |
| CAT-06 | A 账户/旧 endpoint 写缓存，切 B/新 endpoint/另一计费面，再从首页和统一网关读取 | 调用者验证适用 scope/时效；不展示或路由成 B 已授权模型；同作用域离线缓存清楚标注；不在首页解密全部 key |
| UX-07 | 从裸 crouter 选择添加来源，有目录和无目录的本地 mock endpoint 各一次 | 真正可填写并保存 URL/协议/认证与模型，或准确标明仅配置内置来源；不能只复用 keys 菜单宣称已实现 |
| UX-08 | 首页选模型后 apply-only/use/启动任一步失败，再返回首页 | 新默认的提交策略明确、失败不静默破坏旧有效选择；只有成功启动才更新最近成功；可原地恢复，不把预写状态当成功 |

## 当前证据映射（2026-11-14）

对应 SHA `528a2e175c8d93e26dfc1cf2ecd77e73ee7894bd`，CI run `43163712510`。下表复核已有 CI，不是本轮重跑。日志两轮 sh/dash 均完成；精确链接与用户本地报告见基线。

| 范围 | 已通过的证据 | 仍未证明 |
| --- | --- | --- |
| 集成基线 | ShellCheck、全部声明的 Node syntax、现有 test/*.sh 两轮、版本元数据 | 没有编写的功能反例、真实平台/供应商/客户端 |
| provider 配置与 AUTH-01 | provider-config/provider-matrix/provider-refresh 的全 36 集合和固定字段；普通 API key 不推断套餐 | 所有别名权益/价目实时有效、36 家真实推理可用 |
| CFG/CLI 的已测子集 | launch-planning：save-only 零启动、未知窗口、tiers、参数、帮助、防递归；launch-stdin、selection、原生 backend | 完整 LaunchPlan、模型特定 effort 一致、所有带空格别名、所有主页失败路径 |
| CAT 的已测子集 | catalog：规范化/价格、query/auth-origin、非 2xx/redirect、大小/timeout/abort、同 scope 旧缓存、分页；共 8 目录/状态用例 | inventory/unified 的 scope 消费、所有供应商形状/单位、真实目录权限 |
| 策略构造 | catalog.sh 同时运行 5 个 route-policy 用例：默认不付费、同模型付费、两独立许可、API-only | ROUTE-01 的完整网关零请求、Keychain 拒绝、旧 dual-source、来源锁定/备用链 |
| 统一路由 | unified-routes/gateway-path/surface：默认、token、header/model_map、严格空 MCP、去重和错误传播 | 持续 503 耗尽后切换、全冷却硬禁止、取消/断流状态机 |
| 选择器 | model-picker 的目录、价格、q、EOF/HUP、取消前 hook/Claude 零副作用 | 裸首页多屏流程、收藏/最近/批量、中文输入全部边界、真实终端可用性 |
| 隔离与迁移 | 原有 key registry、assets、cleanup、lifecycle、migration、安装卸载断言 | 新多账号 schema/多会话额度协调、真实 macOS Keychain 锁定和共享进程完整场景 |
| skill | 包结构检查、16 个校验器 fixture；CI 记录 18 个行为案例的格式存在 | 18 个案例未实际运行 LLM；本次新增案例也不等于行为评测通过 |

不能把上表的部分覆盖变成整行验收完成。新 CFG-07/CAT-06/UX-07/UX-08 是本次审查补充要求，尚无本轮产品执行记录。

## 测试层级和命令

纯逻辑用固定时钟/种子；mock HTTP 绑定 loopback，记录实际 endpoint/header/model，请求计数覆盖负例。PTY 从真实入口驱动按键、Unicode 分片、粘贴、取消、resize。使用临时 HOME/XDG/STATE 与 stub claude/security，不 source 用户 config，不执行真实 provider hooks。

广泛运行时改动/发布按 CLAUDE.md 门禁执行；仅技能维护不重复整产品测试：

```sh
failed=0
for shell in sh dash; do
  for test_file in test/*.sh; do
    TEST_SHELL="$shell" "$shell" "$test_file" || failed=1
  done
done
test "$failed" -eq 0
```

syntax 逐文件检查，不能 `sh -n file1 file2` 冒充循环。Node 入口含两个 picker；保留 CI ShellCheck 规则及带空格路径反例。缺工具或完整 checkout 写未执行，不能把别人的日志写成自己运行。

真实兼容需记录 Claude/终端/平台和授权，推理可能计费。额度耗尽用 mock，不为验收消耗真实余额。结构检查、校验器测试、产品离线、真实客户端、LLM 行为评测分层报告。

## 技能行为评测与完成定义

[案例](../evals/cases.json) 的 must/must_not 按 agent 实际读取、计划、工具操作和报告判定，不是关键词计分。结构通过只证明材料可读取/引用合法；新增案例不能写成已运行。

关键失败：App 当客户端、越权付费/流向、只包装 flags、流式重放、覆盖用户工作、恢复退役入口、误报 skipped/未执行、将 CI 全绿解释为全产品完成。相反，承认并复用当前成功基线，不强迫重复历史开发，也是正确行为。

功能 DONE 需真实入口可达，成功/取消/失败路径有适用证据，共用应用操作、状态迁移可恢复，文档准确。交付记录必须说明范围与未验证项；历史 DONE 和当前 HEAD 健康度分别维护。
