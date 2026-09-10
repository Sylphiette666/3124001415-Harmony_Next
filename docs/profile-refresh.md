# 个人信息首页刷新修复

2026-09-10：修复填写班级并保存后，首页仍显示“请填写班级或专业”的问题。

## 原因与修复

编辑页和 Preferences 中已有保存的班级，问题出在首页显示。原来的 `infoRow(label, value)` 使用 `@Builder` 按值接收字段，创建时取到的文字不会随着 `profile` 更新而刷新；学号行也有同样的问题。姓名直接绑定状态，因此表现不同。

学号和班级两行改为直接读取首页的 `@State profile`，保留原有布局。返回首页时已有的 `onPageShow` 会读取资料，文字随状态同步更新。存储键和数据格式不变，已保存的班级可以直接显示，无需重新输入。

参考：[华为官方关于 Builder 参数传递与 UI 刷新的说明](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1546)。

## 回归场景

新增 `ProfileFlow.test.ets`，从首页进入编辑页并备份表单中的原资料；保存姓名、学号与中文班级，返回首页立即检查显示；再次进入编辑页读回保存的字段，再只修改班级并检查第二次刷新。最后通过编辑页恢复原资料，检查首页和重新打开的表单。

该 UI 测试要求已填写完整个人资料。若原资料不完整，会在输入测试内容前退出，保持原资料。测试全程使用真实页面，避开设备测试模块与主模块的存储目录差异；填写班级后先收起键盘，再点击保存。本地存储的去缓存读盘由 `Ability.test.ets` 独立验证。

## 已确认的界面行为

- 修复前：实际保存已成功，姓名变化，但学号保留初始值、班级仍显示占位文字。
- 修复后：安装更新并重新进入首页，已保存的原班级、姓名和学号均正确显示。

## 验证结果

主应用和最终设备测试包均编译成功，使用 Pura 90 / HarmonyOS 6.1.1（API 24）模拟器验证。修复后的主应用上，原有 7 项业务测试全部通过；完善测试操作方式后，新增个人资料用例单独运行通过。该用例验证两次修改后的即时显示、表单读回，以及原资料恢复。

```text
Tests run: 1, Failure: 0, Error: 0, Pass: 1, Ignore: 0
TestFinished-ResultCode: 0
```

[新增用例实际结果](profile-refresh-test-results.txt)。可使用下面的命令单独复现（需先安装主应用和测试包，并填写完整个人资料）：

```powershell
& 'D:\HUAWEI\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -t '127.0.0.1:5555' shell aa test -b cn.gdut.iotsoft.cdz3124001415 -m entry_test -s unittest OpenHarmonyTestRunner -s class ProfileHomepageRefresh -s timeout 180000 -w 180
```
