# 2026-11-07 开发交接与本地验收

用户授权更新全 provider、继续开发并上传；完整测试由用户拉取后交给本地 agent。本文件区分已提交实现与尚未通过的门禁，不能据此直接发布。

## 实现切片

- 28 个远端 provider 型号/别名/认证面/目录策略更新，8 个本地或原生来源保留部署身份并补齐 loader 目录策略。全部 36 项有审计记录和固定期望 fixture。
- 新 `lib/catalog.js`：目录规范化、双边价格、窗口上界、认证 origin、query、非 2xx、有限 GET 重试/分页、超时/大小上限、账户作用域缓存及失败保留最后有效目录。
- `lib/model-state.js`：模型绑定窗口、锁、0600 原子记录、旧文件镜像与失败补偿；不自动迁移凭证。
- `bin/crouter`：补上缺失 tier helper；选择/保存先于 PRE_START、认证代理和 assets；显式/记忆选择使用模型绑定窗口；检查 Claude 包装入口递归；`--` 后参数直接转交 Claude。
- `lib/home.js`：裸命令在 stdin/stdout 均为 TTY 时打开中文首页；模型搜索、继续、登记 Key 增删、目录刷新、诊断、同模型付费兜底开关、原生 Claude。脚本继续使用 run。没有实现收藏、完整账户/额度池、批量 Key、自定义 URL 向导或真实 Claude /model 菜单，不把基础首页写成全部交互完成。
- 原诊断/统一网关组装分别移到 `lib/commands.sh`、`lib/unified.sh`，TUI 经 argv/结构化 inventory 复用应用操作，不拼 shell 或解析人类输出。代理转发进程本身没有全面重写。
- `lib/route-build.js` 的显式套餐/API 候选需分别授权付费和跨模型 fallback；Keychain 拒绝语义、旧 dual-source 与全局预算仍未完成。
- `test/model-picker.sh` 改为引用安全的环境参数包装器，不再用 `env $(picker_env)`；同一回归仍保留目录、价格、q、EOF/HUP、取消，新增取消前 hook 零副作用。固定 vendor 断言移到 fixture，不运行时生成期望值。

## 此环境实际执行

Node 22.16、Linux sh/dash；临时 HOME/XDG、假凭证与 loopback HTTP。

```sh
node --test test/catalog.test.js test/route-policy.test.js
TEST_SHELL=sh sh test/launch-planning.sh
TEST_SHELL=dash dash test/launch-planning.sh
TEST_SHELL=sh sh test/model-picker.sh
TEST_SHELL=dash dash test/model-picker.sh
```

13 个 Node 用例通过；启动计划与 picker 回归在 sh/dash 均通过。修改的 Node 文件通过 node --check，修改的 shell/provider 文件逐个通过 sh -n/dash -n。测试曾捕获目录中断错误顺序与缓存二次规范化缺陷，修正后重跑通过。

**未执行：** 全仓 test/*.sh、完整 36-provider fixture（此环境只重建修改文件）、ShellCheck（未安装）、真实 macOS Keychain、真实 Claude UI/版本、真实供应商目录认证与推理、完整迁移/安装/卸载、LLM skill 行为评测。首页完整真实终端操作仍待走查。没有读取真实 Key；不会把 mock 成功说成上游成功。

## 本地 agent 执行顺序

先阅读 crouter-development，记录实际 HEAD、工作树；保留用户改动。不要把下面命令跑在真实 HOME/config/Keychain 上。先确认各测试自己创建隔离 fixture；有调用真实 provider hook 的测试先修成 stub。

1. 跑技能结构检查、Node syntax、每个 shell 文件 syntax 和与 CI 相同的 ShellCheck。不得全局压低 ShellCheck 级别或用 skip 掩盖失败。
2. 跑上面三组新增回归，然后 `TEST_SHELL=sh sh test/provider-matrix.sh` 与 dash 对照。核对 fixture 的每个变更与审计来源，不从实际输出重新生成 golden 来消红。
3. 跑原有 selection、cli-usage、launch-stdin、model-state-isolation、surface-candidates、surface-auth、provider-assets、unified-routes、gateway-path、lifecycle、prelaunch-cleanup、install/uninstall 和 device-migration。迁移测试只能使用假凭证。
4. 旧测试若明确测试“已授权付费/跨模型”，在 fixture 中显式设置这两个授权变量；同时保留新“未授权 API 零请求”反例。若旧预期只是旧型号，按来源更新精确 fixture；不得删除 endpoint/header/model_map 断言。
5. 部分旧测试只复制旧模块列表到临时仓库。按当前依赖补齐 catalog/commands/unified/model-state；不要因此放宽运行时错误。
6. 全量执行并保存失败列表，不因第一项失败就误报其余通过：

```sh
for shell in sh dash; do
  failed=0
  for file in test/*.sh; do
    if TEST_SHELL="$shell" "$shell" "$file"; then :; else
      printf 'FAIL %s %s\n' "$shell" "$file" >&2
      failed=1
    fi
  done
  test "$failed" -eq 0 || exit 1
done
```

最后经授权再做真实终端首页、供应商模型工具回合与并发会话；无真实凭证时报告未验证，不请求账户全集。修复失败后补反例和证据，更新路线图状态，不能只把文件存在当 DONE。

## 重点风险与下一步

先验证拆分模块后的旧测试兼容与静态检查，再完善 DEV-02 的不可变 LaunchPlan、DEV-03 的账户 scope 消费与失败细节、DEV-04/05 的收藏/批量/失败恢复。DEV-09 只有显式 surface 的初步授权边界，尚无完整来源锁定/备用模型链。DEV-10 gateway 最后 5xx、严格冷却、断流和取消仍需测试并实现；本次没有冒充完成。

已保存老 provider-context 的迁移按模型绑定读取；新 JSON 是权威记录，旧镜像不跨模型生效。回滚代码之前备份 `.state` 与 XDG 状态，凭证使用已有加密迁移流程；不要把状态或迁移包提交 Git。没有执行真实账号迁移。
