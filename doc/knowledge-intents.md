# 课程知识问答 ArkAF 意图与 Want

本任务属于校徽图标的课程 App：`cn.gdut.iotsoft.cdz3124001415`，不是实验二的 `cn.gdut.anatomycourse`。

`entry/src/main/ets/entryability/EntryAbility.ets` 使用 `@InsightIntentLink` 注册 `AskCourse`，教育领域，URI `courselearning://ask`。问题参数 `question` 为必填字符串。API 24 构建器生成意图元数据，可在以下构建目录检查：

`entry/build/default/intermediates/res/default/resources/base/profile/insight_intent.json`

EntryAbility 统一处理 `onCreate` / `onNewWant`。冷启动有问题时直接加载问答页；热启动通过窗口 UIContext 路由打开或复用问答页。正常启动保留学校启动页。页面等待资料库初始化完成且处于可见状态后消费问题，每个请求只消费一次；正在保存资料时延后消费。

## 模拟器验证

先构建和安装课程根工程，设备标识以 `hdc list targets` 为准。本次为 `127.0.0.1:5557`：

```powershell
$taskHdc = 'D:\HUAWEI\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$taskDevice = '127.0.0.1:5557'
$taskHap = Join-Path (Get-Location) 'entry\build\default\outputs\default\entry-default-unsigned.hap'
& $taskHdc -t $taskDevice install -r $taskHap
# 冷启动：页面自动打开并发问
& $taskHdc -t $taskDevice shell aa force-stop cn.gdut.iotsoft.cdz3124001415
Start-Sleep -Seconds 2
& $taskHdc -t $taskDevice shell aa start -b cn.gdut.iotsoft.cdz3124001415 -a EntryAbility --ps question '留言板怎样与原生通信'
# 热启动：先回首页并打开电子名片，然后执行
& $taskHdc -t $taskDevice shell aa start -b cn.gdut.iotsoft.cdz3124001415 -a EntryAbility --ps question '怎样使用ArkAF意图'
# URI 参数：ArkAF 链接所使用的应用 URI
& $taskHdc -t $taskDevice shell aa start -b cn.gdut.iotsoft.cdz3124001415 -a EntryAbility -U 'courselearning://ask?question=ArkAF'
```

也可在问答“设置”中点击“通过 Want 唤起问答”，该按钮构造同一课程包名、URI 和问题参数。

验收要点：自动进入问答并显示携带的问题；答案逐字出现且带来源；再次显示页面不重复发问；从名片、留言板等旧任务中触发也能跳转；返回课程首页仍可继续其他任务。

2026-10-19 实际模拟器验证通过：冷启动问题、问答页内热启动新问题、从电子名片页唤起，以及 URI 查询参数 `question=ArkAF`。新问题出现与回答结束后在布局完成时滚动到最新内容，逐字增量期间不强制滚动。根 HAP 内已检查生成的 `resources/base/profile/insight_intent.json`。

模拟器 Want 与生成元数据能验证应用内链路，不等同于真机系统助手已完成线上意图分发。本作业允许的模拟器验证方式已采用。实验二安装包不再声明课程问答意图。
