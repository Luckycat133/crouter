# 2026-11-07 provider 与交互切片交接

本轮在 `fdcaf9120b9b4d0bb6c811d0ce75f935435e754d` 上更新 provider 与运行时，不是仅改技能。详细源矩阵：仓库根 `docs/provider-refresh-2026-11-07.md`、`docs/provider-review-2026-11-07.json`。详细命令、风险和未执行项目：`docs/provider-refresh-handoff.md`。先核对当前 HEAD，以上日期不代表未来自动保持最新。

## 已有代码，不应重复开发

- 全部 36 个来源有审计记录；28 个远端声明更新，8 个本地/原生部署身份保留，loader 补目录策略。
- `lib/catalog.js`、`catalog.sh`、`catalog-inventory.js` 共同处理目录数据和凭证边界；不是通过启动推理代理取得目录。
- `lib/model-state.js` 以模型绑定窗口，原子记录和旧镜像兼容；`lib/provider.sh` 已实现缺失 tier helper。
- `bin/crouter` 选择/保存先于启动；诊断和网关组装移到 commands.sh/unified.sh。裸 TTY 首页在 home.js，普通搜索复用 picker；不存在完整不可变 LaunchPlan。
- 显式 surfaces 默认不从套餐退到 API；付费和跨模型需两个独立授权，旧自定义 dual-source 仍需后续收敛。

## 先验收，不把实现存在当完成

已执行：13 个 Node 用例；launch-planning 和 model-picker 在 sh/dash 的隔离回归；修改文件语法检查。未执行：全量旧 suite、完整 36-source fixture、ShellCheck、真实 macOS Keychain、真实 Claude/上游、首页完整真实终端、LLM eval。没有真实账号或付费请求。

本地 agent 顺序：技能结构 → Node/逐文件 shell syntax → ShellCheck → 新回归 → provider-matrix → 原有认证/路由/生命周期/迁移集成 → 全量 sh/dash → 经授权真实客户端。记录准确 SHA 和失败层级，保存证据。

原有测试复制临时仓库时必须包含新模块；测试已授权 fallback 的 fixture 必须显式设置付费/跨模型许可，同时保留未授权 API 零请求负例。模型预期仅凭一手资料调整，不从程序实际输出自动重建 golden。

## 剩余主线

DEV-15 仍待完整 CI/集成通过；DEV-02 还缺真正的 LaunchPlan 与全部模型特定设置；DEV-03 还需账户作用域消费/目录异常组合；DEV-04/05 还缺收藏、批量 Key、完整账户/额度池和恢复流程。DEV-09 仅有初步候选许可。DEV-07 原生 /model、DEV-10 严格冷却/断流取消、DEV-11 多会话、DEV-12/13 通用 endpoint/托管反代仍未完成。

不要运行当前用户未授权的登录、安装、凭证读取或推理。只做离线测试时使用 fake keys 与临时目录，实际 Keychain 权限拒绝与不存在必须分别设计测试，不能静默降级到付费来源。
