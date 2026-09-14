# 有声计算器

2026-09-13：课程项目新增任务 03“有声计算器”。计算器页面可从首页的“有声计算器”卡片或任务列表中的任务 03 打开。

## 功能

- 支持数字、小数点、加减乘除、百分比、正负号、倒数、平方、平方根、退格、清除当前输入和全部清除。
- 使用单独的计算状态模型处理输入，不执行动态代码；错误结果会显示可理解的中文提示并可继续输入。
- 按键和结果通过系统中文文本转语音播报，语音使用队列顺序播放；连续运算的中间结果、变号后的数值也会播报。顶部开关可静音；重播按钮在当前显示为运算结果时可用，开始新输入、清除或出现错误后禁用，避免重播旧数值。
- 页面离开时停止播报并释放语音引擎，计算状态不会写入个人资料或电子名片存储。

## 设计与验证

页面采用与课程应用一致的浅色背景、白色显示区和高对比度数字键盘；数字、清除与运算键分区着色，运算显示区展示当前表达式和结果，错误提示使用独立文字区域。长结果缩小字号，避免隐藏有效数字；小屏和横屏可滚动操作。

计算模型单元测试覆盖四则运算、连续等号、百分比、十进制精度、清除 / 退格、一元运算、错误恢复和输入长度限制。设备 UI 测试覆盖入口、基本计算、错误恢复、语音开关、重播和返回首页。

文本转语音使用 HarmonyOS Core Speech Kit 的中文离线引擎（`language: zh-CN`、`online: 1`）。若设备没有可用语音引擎，页面会保留完整计算功能并显示重试提示，不阻塞普通计算。

## 操作与计算规则

| 操作 | 规则 / 示例 |
| --- | --- |
| 标准四则 | 按输入顺序即时计算，`2 + 3 × 4 =` 得到 `20`；再次按等号重复乘 `4`，得到 `80` |
| 小数 | 支持小数点输入，重复小数点忽略；`0.1 + 0.2 =` 显示 `0.3` |
| 百分比 | 加减取前一个数的百分比：`200 + 10 % = 220`；乘除将当前数除以 100：`200 × 10 % = 20` |
| AC / CE | AC 清除整条计算并停止旧语音；CE 只清除当前输入，保留待执行运算 |
| 退格 / 正负号 | 退格删除正在输入数值的末位；正负号切换当前数正负 |
| 倒数 / 平方 / 平方根 | 作用于当前显示的数；结果同时可播报和重播 |
| 异常恢复 | 除数为零、负数开平方或结果溢出时显示中文提示；重新输入数字或按清除键恢复 |
| 数值边界 | 手工输入最多 15 位数字；结果最多保留 15 位有效数字，特别大或小的结果采用科学记数法 |

计算器采用 JavaScript 数值运算及 15 位有效数字格式化，用于课程中的日常标准计算。没有括号和运算优先级模式。

## 模块与生命周期

- `CalculatorEngine.ets`：仅处理计算输入与状态，每次返回独立快照；`calculated` 标记本次按键是否成功产生结果，供页面统一播报，便于 ArkUI 响应式更新和单元测试。
- `Calculator.ets`：负责键盘、数值展示和中文按键名称，不持有系统语音实现细节。
- `CalculatorSpeech.ets`：创建系统离线中文引擎，按顺序播报。只在 `onComplete` 的 `type=1`（播放结束）时推进队列，合成完成不会提前播放下一项。静音、清除和离页会取消待播内容；异步初始化晚于离页完成时立即释放引擎。
- 根路由与课程任务：`main_pages.json` 注册页面，`CourseData.ets` 注册任务 03；首页和任务详情均可进入计算器。

没有新增麦克风或联网权限，语音内容限于计算按键与数值。语音开关在当前页面内生效，退出页面后重新进入默认开启。

官方参考：[Core Speech Kit 简介](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/core-speech-introduction)、[播报完成和手动停止的回调说明](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-core-speech-2)。引擎参数按本机 API 24 SDK 声明使用。

## 可重复运行的本地测试

在安装 DevEco Studio 的 Windows 环境中，从项目根目录执行：

```powershell
& 'D:\HUAWEI\DevEco Studio\tools\node\node.exe' scripts/test-calculator-engine.cjs --deveco-home 'D:\HUAWEI\DevEco Studio'
& 'D:\HUAWEI\DevEco Studio\tools\node\node.exe' scripts/test-calculator-speech.cjs --deveco-home 'D:\HUAWEI\DevEco Studio'
```

计算模型脚本转译真实的 `CalculatorEngine.ets` 和 `CalculatorEngine.test.ets`，运行相同的 26 项断言，不另维护一份测试逻辑。

脚本使用 DevEco 自带 TypeScript 转译真实语音服务，并模拟 Core Speech Kit 的异步回调。8 项用例覆盖按顺序播放、合成与播放回调的区别、重复回调、快速连按、静音清队列、离页时初始化竞态、原生错误与重试。该测试验证服务逻辑，设备能否真实发声另行验证。

## 本次验证记录（2026-09-14）

环境：DevEco Studio 6.1、HarmonyOS 6.1.1 / API 24 SDK、Windows；目标为 Pura 90 模拟器。

| 验证项 | 实际结果 |
| --- | --- |
| 应用 `default` HAP 构建 | 通过，`BUILD SUCCESSFUL`；未配置开发签名 |
| `ohosTest` HAP 构建 | 通过，`BUILD SUCCESSFUL` |
| 两个 HAP 安装到模拟器 | 均返回 `install bundle successfully` |
| 真实 ETS 计算模型及原单元测试经 Node 执行 | 26 项通过，0 项失败 |
| 真实语音服务的异步回调模拟测试 | 8 项通过，0 项失败 |
| Hypium 设备测试、页面截图和实际声音验收 | 尚未完成，受模拟器系统启动故障阻塞 |

设备限制：模拟器桌面服务 `com.ohos.sceneboard` 连续无响应，日志记录 `SceneBoard exits 4times in 240000ms` 并触发系统内核崩溃。保留用户数据重新启动后仍黑屏，`aa start` 和 `aa test` 返回屏幕锁定错误 `10106102`，设备测试返回 `-3`。因此本记录不将设备 UI 测试或真实语音播放标记为通过。诊断日志仅留在被 Git 忽略的本机测试目录中。

模拟器恢复或连接正常设备后，可按根 README 的构建及安装命令运行；仅执行本次新增设备测试时，使用以下筛选：

```powershell
& $taskHdc -t $taskDevice shell aa test -b cn.gdut.iotsoft.cdz3124001415 -m entry_test -s unittest OpenHarmonyTestRunner -s class CalculatorEngine,TalkingCalculatorUi -s timeout 180000 -w 300
```

人工语音验收：确认“语音已就绪”，依次输入 `1 2 + 3 =`，应按顺序听到各按键及结果 `15`；再次按等号应播报 `18`，按正负号后重播应为负 `18`。继续检查 `2 + 3 ×` 的中间结果 `5`、静音后的停止播放以及返回首页后停止播报。系统 `CalculatorSpeech` 日志的 `onComplete type=1` 对应播放结束，可辅助核对真实播放流程。
