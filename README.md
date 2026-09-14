# HarmonyOS NEXT 课程学习项目

学号：3124001415。使用 ArkTS、ArkUI 和 Stage 模型开发，可在 DevEco Studio 中打开和运行。

## 功能

- 冷启动先显示白底校徽与校名图片，约 1 秒后进入首页；桌面图标使用校徽。
- 首页展示项目标题、姓名、学号和班级或专业。
- 个人信息可在首页点击“编辑”修改，使用 Preferences 保存在当前设备。
- 任务列表为每项课程任务提供独立按钮，点击进入对应详情页。
- 详情页展示任务说明、要求和操作指引，支持页面返回按钮与系统返回。
- 任务 01：2026 年 9 月 3 日布置的课程学习项目，提供首页、个人资料、任务列表和任务详情。
- 任务 02：2026 年 9 月 7 日布置的电子名片管理，要求在 2026 年 9 月 11 日前提交到自己的代码仓库。
- 任务 03：2026 年 9 月 13 日布置的有声计算器，支持标准计算、按键读音和结果播报；说明文档位于根目录 `doc`。

首次启动已预填学号。姓名、班级或专业需按实际情况填写，不使用示例人物代替。

## 电子名片

首页点击“电子名片”进入名片夹，也可通过“打开任务列表 → 任务 02 → 进入任务应用”进入。

- 新增、查看、编辑和删除名片，保存姓名、电话、邮箱、单位 / 学校、职位 / 身份、地址和备注。
- 姓名必填，电话和邮箱至少填写一项；保存时检查电话、邮箱格式和内容长度。
- 支持“同学、老师、工作、其他”分组，以及收藏和仅看收藏。
- 按姓名、单位、职位、电话或邮箱搜索，可与分组、收藏筛选组合使用。
- 详情页的联系方式支持长按复制；删除前需确认，取消后保留名片。
- 编辑后返回时提示是否放弃未保存修改。
- 名片通过 Preferences 保存在当前设备，重新打开应用后读取本地数据。名片不会上传到 GitHub，卸载应用或清除应用数据会移除本机保存的内容。

操作示例：首页 → 电子名片 → 新增 → 填写姓名与电话或邮箱 → 保存名片 → 点击名片查看详情 → 编辑、收藏或删除。

## 在 DevEco Studio 中运行

1. 打开本仓库根目录（包含 `build-profile.json5` 的目录）。
2. 等待项目同步和 OHPM 依赖安装完成。
3. 使用 HarmonyOS 6.1.1 / API 24 SDK，选择 `entry` 模块和 `default` 产品。
4. 启动 API 24 手机模拟器（例如 Pura 90），点击 Run。
5. 首页 → 编辑 → 填写个人信息 → 保存；首页 → 打开任务列表 → 查看任务详情；首页 → 电子名片 → 管理联系人。
6. 首页 → 有声计算器，或任务列表 → 任务 03 → 进入任务应用。语音默认开启，可用顶部按钮关闭或重新开启。

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

## 设备测试

在 DevEco Studio 中选择测试目录 `entry/src/ohosTest/ets/test`，运行 `List.test.ets` 注册的六套 Hypium 测试。测试前先启动应用、填写并保存完整个人资料，确认设备的系统输入法可用。UI 流程涉及多次页面操作，建议将单用例超时设为 180000 毫秒，整轮等待时间设为 600 秒。

| 测试文件 | 检查内容 |
| --- | --- |
| `Ability.test.ets` | 中文个人资料保存、移除内存缓存后的磁盘重读，结束后恢复原资料 |
| `ProfileFlow.test.ets` | 连续两次编辑保存后首页班级与学号即时刷新、重新进入表单读回，结束后经界面恢复原资料 |
| `CardStore.test.ets` | 名片增删改查、磁盘重读、搜索 / 分组 / 收藏、并发写入、字段校验和异常数据处理；使用独立测试存储 |
| `CardFlow.test.ets` | 从首页新增名片、表单提示、查看与编辑、分组与收藏筛选、关键词搜索、取消删除和确认删除；仅清理本次建立的 QA 名片 |
| `CalculatorEngine.test.ets` | 四则、连续等号、百分比、一元运算、输入编辑、数值范围及错误恢复 |
| `CalculatorFlow.test.ets` | 首页入口、按键计算、错误提示与恢复、语音开关、重播与返回 |

也可在构建两个 HAP 后，从仓库根目录运行以下 PowerShell 命令。`127.0.0.1:5555` 为本次模拟器地址；其他设备请替换为 `hdc list targets` 返回的目标标识。

```powershell
$taskHdc = 'D:\HUAWEI\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$taskDevice = '127.0.0.1:5555'
& $taskHdc list targets
& $taskHdc -t $taskDevice install 'entry/build/default/outputs/default/entry-default-unsigned.hap'
& $taskHdc -t $taskDevice install 'entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap'
& $taskHdc -t $taskDevice shell aa start -b cn.gdut.iotsoft.cdz3124001415 -a EntryAbility
& $taskHdc -t $taskDevice shell aa test -b cn.gdut.iotsoft.cdz3124001415 -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 180000 -w 600
```

构建和设备测试的实际结果见 [原有功能验证记录](docs/verification.md) 和 [有声计算器验证记录](doc/calculator.md)。上述表格说明测试覆盖内容，不代表所有环境都已通过验证。

计算模型的 26 项测试和语音服务的 8 项异步回调测试可独立运行：

```powershell
& 'D:\HUAWEI\DevEco Studio\tools\node\node.exe' scripts/test-calculator-engine.cjs --deveco-home 'D:\HUAWEI\DevEco Studio'
& 'D:\HUAWEI\DevEco Studio\tools\node\node.exe' scripts/test-calculator-speech.cjs --deveco-home 'D:\HUAWEI\DevEco Studio'
```

## 新增课程任务

修改 `entry/src/main/ets/model/CourseData.ets` 的 `COURSE_TASKS`，添加一个具有唯一 `id` 的 `CourseTask`。列表按钮和详情内容由这份数据生成，无需重复编写路由页面。

| 文件 | 用途 |
| --- | --- |
| `entry/src/main/ets/pages/Splash.ets` | 白底图片启动页、1 秒展示与首页跳转 |
| `entry/src/main/ets/pages/Index.ets` | 课程首页 |
| `entry/src/main/ets/pages/Tasks.ets` | 任务列表 |
| `entry/src/main/ets/pages/TaskDetail.ets` | 任务详情 |
| `entry/src/main/ets/pages/Profile.ets` | 个人信息编辑 |
| `entry/src/main/ets/model/ProfileStore.ets` | 本机资料存储 |
| `entry/src/main/ets/pages/BusinessCards.ets` | 名片列表、搜索、分组和收藏筛选 |
| `entry/src/main/ets/pages/CardEditor.ets` | 新增与编辑名片、表单校验、未保存修改提示 |
| `entry/src/main/ets/pages/CardDetail.ets` | 名片详情、收藏切换和删除确认 |
| `entry/src/main/ets/model/BusinessCard.ets` | 名片模型、字段校验、搜索和排序 |
| `entry/src/main/ets/model/CardStore.ets` | 本地名片持久化、写入排队和异常处理 |
| `entry/src/main/ets/pages/Calculator.ets` | 有声计算器页面与按键交互 |
| `entry/src/main/ets/model/CalculatorEngine.ets` | 独立计算状态机和数值格式化 |
| `entry/src/main/ets/services/CalculatorSpeech.ets` | 系统中文语音、播报队列与资源释放 |
| `entry/src/main/ets/model/CourseData.ets` | 任务 01 / 02 / 03 说明与功能页入口 |
| `entry/src/main/resources/base/profile/main_pages.json` | 页面注册 |
| `entry/src/ohosTest/ets/test/List.test.ets` | 六套设备测试的统一入口 |
| `scripts/build.ps1` | 应用及设备测试包构建脚本 |

## GitHub

目标仓库：[Sylphiette666/3124001415-Harmony_Next](https://github.com/Sylphiette666/3124001415-Harmony_Next)。任务 02 的提交期限为 2026 年 9 月 11 日前。

提交源码、资源、运行说明和项目配置；构建缓存、设备测试临时文件及证书密钥不进入版本控制。个人资料和联系人数据在运行设备中保存，不会随源码提交。

验证记录和界面截图见 [docs/verification.md](docs/verification.md)。

启动页、图标来源和验证截图见 [启动外观说明](docs/branding.md)。

班级保存后首页显示问题的修复与回归记录见 [个人信息刷新修复](docs/profile-refresh.md)。

有声计算器的操作说明、设计和本次验证记录见 [doc/calculator.md](doc/calculator.md)。任务 03 要求在 2026 年 9 月 17 日前提交，文档按要求保存在根目录 `doc`。
