# ArkAF 意图入口

`EntryAbility.ets` 使用 API 24 SDK 的 `@InsightIntentLink` 声明 `AskCourse`，领域为 `education`，URI 为 `anatomycourse://ask`，必需字符串参数为 `question`。编译器生成 `extractInsightIntents`，其中包含 intentName、参数 schema、paramMappings 和 UIAbility 入口。

`onCreate` 与 `onNewWant` 共用解析函数，优先使用 `Want.parameters.question`，其次读取 URI 查询参数。页面等待数据库就绪后消费请求，并切换问答页自动提交。参数限制 600 字，非法转义或不匹配 URI 不触发提问。

## 模拟器验证

先执行 `hdc list targets`，将下列目标替换为实际设备标识：

```powershell
hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b cn.gdut.anatomycourse --ps question "ArkAF意图怎样携带问题"
hdc -t 127.0.0.1:5555 shell aa force-stop cn.gdut.anatomycourse
hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b cn.gdut.anatomycourse --ps question "数据库如何使用事务"
```

第一条验证热启动，后两条验证冷启动。URI 入口可用 URL 编码的问题替代参数：

```powershell
hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b cn.gdut.anatomycourse -U "anatomycourse://ask?question=ArkAF"
```

App 中“问答 → 设置 → 通过 Want 唤起问答”同样调用 `UIAbilityContext.startAbility`。验收检查自动进入问答、无需点击发送、不会重复发问、回答有来源。

本项目验证的是装饰器产物和 Want 链路；没有声称已通过真机系统推荐、应用市场意图审核或 Data Augmentation Kit 真机验收。
