# 知体 Anatomy Course

独立 HarmonyOS 应用：把 Human Atlas 的 3D 人体解剖浏览器移植到 ArkWeb，并提供原生搜索、收藏、历史、笔记和课程知识问答。使用 CODEX 完成开发与验证。

包名 `cn.gdut.anatomycourse`，HarmonyOS 6.1.1 / API 24，ArkTS + ArkUI + RDB。可与“听见”同时安装。

## 功能

- 离线浏览 2,234 个网格、3,432 个解剖概念；按系统显隐、旋转、缩放、展开和独立显示。
- 原生中英文搜索与 Web 结构选择双向同步，收藏、浏览记录、结构笔记保存在本地。
- 内置 12 篇鸿蒙课程讲义，支持新增、编辑、删除，资料与切分片段在同一事务内更新。
- 对话式问答、逐字输出、停止、重试；编号引用可点击查看原文及高亮上下文。
- `AskCourse` 使用 `@InsightIntentLink` 注册，支持 Want / URI 携带问题并自动提问。
- 默认离线摘录模式；可选 HTTPS 模型代理、embedding 缓存、关键词与语义 RRF 混合检索、SSE 云端生成。

**默认模式是可追溯的资料摘录整理，不运行本地大模型。** 云端代码已提供并通过协议测试，但仓库不包含模型密钥，也未预置可用的公共模型服务。启用云端需自行部署代理；问题和课程片段会发送到配置的服务。

## 在 DevEco Studio 检验

1. 安装 Node.js 22.13+（推荐 24）和 DevEco Studio，安装 HarmonyOS 6.1.1 / API 24 SDK。
2. 在本目录执行 Web 构建，首次会安装 npm 依赖：

   ```powershell
   .\scripts\build-web.ps1 -NodePath 'C:\Program Files\nodejs\node.exe' -Install
   ```

   Node 路径请替换为本机实际路径。DevEco 自带 Node 18 仅用于 Hvigor，不适用于 Vite 8。

3. DevEco Studio 打开**本目录**，等待 OHPM 同步完成，选择 `entry/default` 和 API 24 手机模拟器，点击 Run。
4. 命令行构建可运行：

   ```powershell
   .\scripts\build.ps1 -DevEcoHome 'D:\HUAWEI\DevEco Studio'
   ```

输出 `entry/build/default/outputs/default/entry-default-unsigned.hap`。本次模拟器允许安装未签名调试包；真机请在 DevEco 配置自己的开发签名。

`rawfile/atlas` 是 Web 构建输出，不提交仓库。**首次克隆必须先执行第 2 步**；模型原始文件位于 `web/public/models`，随源码提供，运行时不下载。

## 快速体验

- 问答：点击“如何让 ArkWeb 离线加载模型？”；答案下方点击引用卡片查看原文。
- 资料：新增一篇含独特关键词的资料，提问该关键词，修改后再次提问，删除后确认不再命中。
- 解剖：搜索 `心脏` 或 `heart`，选择结果，进入详情收藏或写笔记；在“学习”页重新定位。
- 意图：“问答 → 设置 → 通过 Want 唤起问答”，或使用 [意图命令](doc/INTENTS.md)。

## 验证与文档

```powershell
node scripts/test-core.cjs
node scripts/test-client.cjs
node --test cloud/server.test.mjs
node web/scripts/validate-atlas.mjs
node web/scripts/validate-interactions.mjs
node web/scripts/validate-harmony.mjs
```

以上 `node` 使用 22.13+ / 24；SQLite 测试推荐 Node 24。Web 类型检查由 `build-web.ps1` 执行。

- [架构、数据库与移植说明](doc/DESIGN.md)
- [运行验证与已知边界](doc/VALIDATION.md)
- [云端接入与协议](doc/CLOUD.md)
- [ArkAF 意图与 Want 验证](doc/INTENTS.md)
- [第三方来源和许可](doc/ATTRIBUTION.md)

个人实验报告、报告模板、签名证书、密钥和本机缓存不提交到仓库。
