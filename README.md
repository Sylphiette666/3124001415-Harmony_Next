# HarmonyOS NEXT 课程学习项目

学号：3124001415。使用 ArkTS、ArkUI 和 Stage 模型开发，可在 DevEco Studio 中打开和运行。

## 功能

- 首页展示项目标题、姓名、学号和班级或专业。
- 个人信息可在首页点击“编辑”修改，使用 Preferences 保存在当前设备。
- 任务列表为每项课程任务提供独立按钮，点击进入对应详情页。
- 详情页展示任务说明、要求和操作指引，支持页面返回按钮与系统返回。
- 当前录入 2026 年 9 月 3 日布置的课程学习项目任务。

首次启动已预填学号。姓名、班级或专业需按实际情况填写，不使用示例人物代替。

## 在 DevEco Studio 中运行

1. 打开本仓库根目录（包含 `build-profile.json5` 的目录）。
2. 等待项目同步和 OHPM 依赖安装完成。
3. 使用 HarmonyOS 6.1.1 / API 24 SDK，选择 `entry` 模块和 `default` 产品。
4. 启动 API 24 手机模拟器，点击 Run。当前工程已在 Pura 90 模拟器验证。
5. 首页 → 编辑 → 填写个人信息 → 保存；首页 → 打开任务列表 → 查看任务详情。

原有包名和签名配置保持不变。当前生成的 HAP 未签名，适用于本次模拟器验证；真机运行需使用自己的开发签名配置。

## 命令行构建

Windows PowerShell：

```powershell
.\scripts\build.ps1 -DevEcoHome 'D:\HUAWEI\DevEco Studio'
```

构建结果：`entry/build/default/outputs/default/entry-default-unsigned.hap`。

构建设备测试包：

```powershell
.\scripts\build.ps1 -DevEcoHome 'D:\HUAWEI\DevEco Studio' -Target ohosTest
```

在 DevEco Studio 的设备测试中运行 `entry/src/ohosTest/ets/test/Ability.test.ets`。该测试检查中文资料保存、清除内存缓存后的磁盘重读，并恢复原有资料。

## 新增课程任务

修改 `entry/src/main/ets/model/CourseData.ets` 的 `COURSE_TASKS`，添加一个具有唯一 `id` 的 `CourseTask`。列表按钮和详情内容由这份数据生成，无需重复编写路由页面。

| 文件 | 用途 |
| --- | --- |
| `entry/src/main/ets/pages/Index.ets` | 课程首页 |
| `entry/src/main/ets/pages/Tasks.ets` | 任务列表 |
| `entry/src/main/ets/pages/TaskDetail.ets` | 任务详情 |
| `entry/src/main/ets/pages/Profile.ets` | 个人信息编辑 |
| `entry/src/main/ets/model/ProfileStore.ets` | 本机资料存储 |
| `entry/src/main/resources/base/profile/main_pages.json` | 页面注册 |

## GitHub

目标仓库名：`3124001415-Harmony_Next`。提交源码、资源和项目配置；构建缓存、设备测试临时文件及证书密钥不进入版本控制。个人资料在运行设备中保存，不会随源码提交。

验证记录和界面截图见 [docs/verification.md](docs/verification.md)。
