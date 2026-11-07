# 验收矩阵与技能评测

验收 ID 是任务与测试的对应关系，不是通过标记。每项绑定代码 SHA、真实测试文件、命令、平台和退出码；拆分复合场景时明确覆盖哪一半。历史记录与当前结果分开，未运行或 skipped 不写通过。

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

## 最新集成回归

这些是当前基线新增的验收要求，不是声称已存在对应测试。

| ID | Given / When | Then |
| --- | --- | --- |
| BUILD-01 | 最新 SHA 的 CI；环境路径含空格；ShellCheck 提前失败 | 正确逐项构造环境 argv；后续 skipped 不计通过，修复后实际执行剩余步骤 |
| CLI-01 | crouter provider、run、use、原生 claude 路径及参数转发 | 保持有效契约；stub 的 argv/stdin/env/退出码准确，帮助无启动副作用 |
| CLI-02 | 脚本以 claude 命名，PATH 中包含包装器；显式/未设真实 CLAUDE_BIN | provider 分发与原生子命令可区分；防止自调用循环，不覆盖真实 CLI |
| CLI-03 | 安装/卸载，旧 claude-* 残留、另一 checkout 链接和同名普通文件 | 不新建退役入口；不删除无关文件，残留迁移策略明确且可重复 |
| CLI-04 | helper 调用有缺失、stderr 有错误但后续命令返回 0 | 回归能捕获缺失 helper 与错误映射，不能只检查最终退出码 |
| CFG-06 | 先加载旧 provider-context，再选未知窗口或显式另一模型 | 不把旧内存值重新保存或传给 child；同时测 browse、--model、apply-only |
| CAT-05 | 交替加载带/不带目录字段的 provider；非 2xx 却有 data 数组 | 目录字段重置；query 保留、状态先判定；凭证 origin 隔离 |
| SESSION-04 | CROUTER_ALL_EXCLUDE_PROVIDERS 排除来源，另开直接启动和其他会话 | 排除早于凭证发现且不进目录；不泄漏到直接启动或其他会话，不冒充完整策略 UI |

## 测试层级和命令

纯逻辑使用固定时钟/随机种子；mock HTTP 绑定 loopback，记录实际 endpoint/header/model，注入慢响应、跨域、失败和断流。假凭证必须显然是假值。

PTY 覆盖分片 Unicode、粘贴、取消、resize 和终端恢复；静态截图不能替代交互。离线整合使用临时 HOME/XDG/STATE 和 stub claude/security，不 source 用户配置、不执行未知 hooks。

在可运行完整 checkout 中，发布矩阵应将 shell 选择传入测试，并累计失败，不让最后一个通过覆盖前面的失败：

```sh
failed=0
for shell in sh dash; do
  for test_file in test/*.sh; do
    TEST_SHELL="$shell" "$shell" "$test_file" || failed=1
  done
done
test "$failed" -eq 0
```

语法检查逐文件执行，不能用 `sh -n file1 file2` 代替循环。Node 入口含两个 picker；使用 CI 的 ShellCheck 规则而非全局忽略新告警。测试带空格临时路径，避免 env $(...) 的意外拆分。缺工具、平台或完整 checkout 就准确写未执行。

真实兼容需实际 Claude 版本/终端/平台和授权；真实推理可能计费，额度耗尽优先用 mock。skills 静态检查、校验器反例、产品测试、真实客户端、LLM 行为评测分开报告。

## 技能行为评测

[evals/cases.json](../evals/cases.json) 提供触发、反向和边界任务。隔离 checkout 中检查 agent 是否读取当前证据、选择正确范围、实际运行要求的检查并准确报告；must/must_not 是判定项，不是关键词得分。案例的 acceptance_ids 只关联要求，不意味着已通过。

关键失败：把 App 当产品客户端、越过费用/数据流向、只包装 flags、流式重放、覆盖用户工作、恢复已退役入口、把 skipped 当通过，或未执行却宣称成功。缺凭证时完成离线部分并说明限制是正确行为。

技能校验器只检查结构、引用、唯一 ID、任务依赖与 DONE 记录的存在；不验证记录是否真实，也不运行 LLM。改校验器时运行 validate.test.mjs 的正反例；原有技能应仍可通过，新增任务不要求硬编码数量。

## 完成定义

功能从真实入口可达，成功与取消/失败均有测试，共用应用操作，迁移可恢复且不泄密；验收具体子项有证据，文档与实际能力一致。历史 DONE 的范围和新 HEAD 的健康度分开，不能借技能检查替代产品验收。
