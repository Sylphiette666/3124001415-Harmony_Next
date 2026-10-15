# 运行验证记录

验证日期：2026-10-15。环境：Windows、DevEco Studio 的 HarmonyOS 6.1.1 / API 24 SDK、Pura 90 手机模拟器；Web 与协议测试使用 Node.js 24.19。

## 已完成的检查

| 范围 | 检查与结果 |
|---|---|
| Web 数据完整性 | 2,234 个网格、3,432 个概念、2,288,268 个三角面及全部二进制缓冲校验通过 |
| Web 交互 | 桌面/移动布局、点击、拖动、多点触控、取消、空视图检查通过 |
| 新增桥接 | 中文搜索、精确 ID、无效 ID 不覆盖选中项、ready/isolate/reset、注销检查通过 |
| 类型及打包 | TypeScript 检查与 Vite 构建通过；DevEco Hvigor assembleHap 通过 |
| 知识库 | 12 篇种子、Unicode 切分与偏移、关键词/RRF、Want 参数解析通过 |
| 数据事务 | 实际 SQLite 上验证 CRUD、回滚、过期向量拒绝、并发串行化、收藏与笔记通过 |
| 原生网络适配 | 分字节 UTF-8、CRLF SSE、流截断、错误/状态码、HTTPS、资源释放通过 |
| 云代理 | 6 项本地模拟模型服务测试全部通过，包含非法引用和缺失配置 |
| 模拟器资料 CRUD | 新增 Zebranova/AzureMark 可检索；修改为 GoldMark 后旧值消失；删除后无匹配，资料恢复为 12 篇 |
| 模拟器知识问答 | 逐字输出、停止/重试入口、引用及高亮原文可用；冷/热启动 Want 自动提问通过 |
| 模拟器解剖浏览 | 离线资源加载并显示人体；心脏搜索与结构选择可用；收藏、笔记在强制停止再启动后保留 |
| ArkAF | @InsightIntentLink 已生成 insight_intent.json；验证方式为 Want / 应用内调试入口 |

测试命令见根 README。模拟器安装并运行的是本工程构建的未签名调试 HAP。编译仍有 SDK 异常声明、弃用 API 和资源同名警告，不影响本次编译；Vite 有单个 JS 包大于 500 kB 的提示。

## 实际运行截图

- [3D 浏览](screenshots/atlas-final.jpeg)
- [课程问答](screenshots/qa-final.jpeg)
- [引用原文](screenshots/source-final.jpeg)
- [重启后的收藏与笔记](screenshots/favorites-final.jpeg)
- [修改资料后的回答](screenshots/qa-crud-updated.jpeg)
- [删除资料后的无匹配提示](screenshots/qa-crud-deleted.jpeg)

## 边界与后续验证

默认模式检索本地资料后逐字展示摘录，不是本地大模型。云端 embedding 与生成代理代码可部署，但尚未配置真实公共 HTTPS 模型服务，未宣称完成真实云模型端到端验收。无网络分支已实现，未通过切断模拟器网络进行实测；请求截断和服务失败由协议测试验证。

未验证真机系统意图分发、Data Augmentation Kit、IPC 服务化、语音播报；这些不属于本次必选交付。ArkAF 装饰器和模拟器 Want 链路已验证。首次克隆需先构建 Web，再由 DevEco 同步 OHPM 依赖。模型数据用于教学浏览。
