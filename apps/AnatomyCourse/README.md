# 知体 Anatomy Course · 实验二

独立 HarmonyOS 人体解剖浏览器，把 Human Atlas 的 Web 应用移植到 ArkWeb，提供原生搜索、收藏、浏览历史和结构笔记。使用 CODEX 完成开发与验证。

包名 `cn.gdut.anatomycourse`，HarmonyOS 6.1.1 / API 24，ArkTS + ArkUI + RDB。可与原课程学习项目和“听见”同时安装。

2026-10-14 布置的“课程知识问答助手”属于仓库根目录的课程学习项目，与本实验分开。知体仅包含“浏览”“学习”两页，默认打开 3D 浏览。

## 功能

- 离线浏览 2,234 个网格、3,432 个解剖概念；按系统显隐、旋转、缩放、展开和独立显示。
- 原生中英文搜索与 Web 结构选择双向同步，支持概念或模型编号定位。
- 收藏、最近浏览和结构笔记保存在本地；升级保留已有学习记录。
- 模型加载进度、加载失败与重试；初始化、搜索和保存失败时显示提示。
- “学习 → 关于”展示上游项目、BodyParts3D 模型和许可署名。

模型和网页全部随应用打包，运行时无需下载；不申请互联网或网络状态权限；所有网页资源由原生层映射为本地文件。

## 在 DevEco Studio 检验

1. 安装 Node.js 22.13+（推荐 24）和 DevEco Studio，安装 HarmonyOS 6.1.1 / API 24 SDK。
2. 在本目录执行 Web 构建，首次安装 npm 依赖：

   ```powershell
   .\scripts\build-web.ps1 -NodePath 'C:\Program Files\nodejs\node.exe' -Install
   ```

   Node 路径请替换为本机实际路径。DevEco 自带 Node 18 仅用于 Hvigor，不适用于 Vite 8。

3. DevEco Studio 打开**本目录**，等待 OHPM 同步完成，选择 `entry/default` 和 API 24 手机模拟器，点击 Run。
4. 命令行构建：

   ```powershell
   .\scripts\build.ps1 -DevEcoHome 'D:\HUAWEI\DevEco Studio'
   ```

输出 `entry/build/default/outputs/default/entry-default-unsigned.hap`。本次模拟器允许安装未签名调试包；真机请在 DevEco 配置自己的开发签名。

`rawfile/atlas` 是 Web 构建输出，不提交仓库。**首次克隆必须先执行第 2 步**；模型原始文件位于 `web/public/models`，随源码提供。

## 快速体验

1. 打开应用，在“浏览”页等待本地模型加载，拖动旋转、双指缩放。
2. 搜索 `心脏` 或 `heart`，选择结果，在详情中收藏或写笔记。
3. 切换“学习”，查看收藏或浏览历史，点击“定位模型”返回 3D。
4. 关闭并重新打开应用，确认收藏和笔记保留；“关于”可查看来源与许可。

## 验证与文档

```powershell
node scripts/test-study.cjs
node scripts/test-bridge.cjs
node web/scripts/validate-atlas.mjs
node web/scripts/validate-interactions.mjs
node web/scripts/validate-harmony.mjs
```

以上 `node` 使用 22.13+ / 24；SQLite 测试推荐 Node 24。Web 类型检查由 `build-web.ps1` 执行。

- [架构、数据库与移植说明](doc/DESIGN.md)
- [运行验证与已知边界](doc/VALIDATION.md)
- [第三方来源和许可](doc/ATTRIBUTION.md)

个人实验报告、报告模板、签名证书、密钥和本机缓存不提交到仓库。
