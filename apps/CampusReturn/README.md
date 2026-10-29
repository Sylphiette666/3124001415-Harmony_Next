# 归物 校园智能失物招领

实验四“鸿蒙综合应用开发”的独立原生 App，包名 `cn.gdut.campusreturn`。在 DevEco Studio 中打开本目录，使用 HarmonyOS 6.1.1 / API 24。它与听见、知体、识物和根目录课程 App 分别安装。

支持图片和语音辅助登记、可确认的结构化字段、多因子匹配、串行凭证核验、竞领择优、冒领申诉、信用分、管理员统计，以及 RDB 离线缓存和可靠重传。

## 启动后端

需要 Python 3.12 或更新版本。在本目录执行：

```powershell
./scripts/run-server.ps1
```

脚本在 `.venv` 安装固定依赖，在 `.local` 生成随机 JWT 密钥、SQLite 数据库和四个教学账号，并启动本机 `127.0.0.1:8766`。首次执行加入三条**合成校园卡**和三条**合成图书**登记；重复执行不重复生成或重置账号。账号为 alice（失主）、bob（拾获者）、charlie（另一失主）、admin（管理员），**随机口令查看本机 `.local/accounts.json`**，没有公共固定密码。此文件、数据库及密钥不提交。

手工方式：

```powershell
python -m venv .venv
./.venv/Scripts/python.exe -m pip install -r server/requirements.txt
./.venv/Scripts/python.exe -m server.manage demo --seed
./.venv/Scripts/python.exe -m uvicorn server.app:app_factory --factory --host 127.0.0.1 --port 8766
```

接口交互文档运行后见 `http://127.0.0.1:8766/docs`。远程部署应由自己的 HTTPS 入口转发；App 仅允许 HTTPS 或本机回环 HTTP。

## 构建并联调

```powershell
& 'D:/HUAWEI/DevEco Studio/tools/ohpm/bin/ohpm.bat' install --all
./scripts/build.ps1 -DevEcoHome 'D:/HUAWEI/DevEco Studio'
& 'D:/HUAWEI/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe' rport tcp:8766 tcp:8766
```

构建输出为 `entry/build/default/outputs/default/entry-default-unsigned.hap`。模拟器可安装未签名 HAP；真机需在 DevEco 配置自己的开发签名。工程同时包含 arm64-v8a 和 x86_64 原生库，不需下载模型或构建 Web 资源。

启动“归物”→连接，填写 `http://127.0.0.1:8766`、账号及本机随机口令→保存并连接。切换账号会切换对应缓存和待传队列。普通用户没有“管理”页，管理员接口仍独立校验服务端角色。

## 操作验证

1. alice 在“广场→我的失物→查看匹配”查看总分及五项因子，申请认领，回答教学问题（合成卡片上的演示编号为 `202600001`）。
2. bob 在“认领”查看同一招领的队列和材料。全部申请完成核验后点“确认领取”，由服务端按凭证分80%＋信用分20%择优；不可跳过核验。
3. charlie 可从完成的招领进入“领取记录 / 申诉”，关联自己的失物登记，提交高于原核验等级的 L2/L3 证据。bob 或 admin 在“我的 / 管理→申诉”核对并裁定。
4. “发布”可拍照、从系统相册选图，或使用合成教学卡测试。点击识别后确认类别、OCR；口述或输入描述，再提取类别、颜色、地点、时间，全部允许修改。拾获发布必须填写私密问题和标准答案。
5. 断开后端连接后发布，待传数据入库；重新打开 App 仍保留。恢复连接后在前台每15秒检查并监听网络恢复事件，自动重传；“我的→立即重试同步”可立即重试。
6. admin 可查看 SQL 汇总、申诉、违规和禁止认领名单；切换均衡／地点优先／文字优先权重，调整阈值保存。候选查询按新策略重算，已经生成的匹配保留原始分数作为审计记录。

权重对照：alice的图书登记 `demo-book-lost` 对应两条候选，同地点异编号 `demo-book-near` 和异地点同编号 `demo-book-text`。地点优先时约为0.8213/0.3991，文字优先时约为0.3161/0.8994，排序与超过0.62阈值的候选互换。原始材料保持不变，方便教师复验。

Core Vision OCR、通用图像分类及 Natural Language Kit 使用真实系统 API；缺少系统模型或能力时明确提示。图像分类另有随包 YOLOv13-N 端侧补充，不能可靠分类时需手选。语音使用实际麦克风 PCM→Core Speech，模拟器不可用时可改用文字。**不能把模拟器上的降级提示当作真机 AI 能力已验证**。具体实测见 [验收记录](doc/VALIDATION.md)。

## 测试与文档

```powershell
./.venv/Scripts/python.exe -m pytest server/tests -q
node scripts/test-client.cjs --deveco-home 'D:/HUAWEI/DevEco Studio'
```

客户端测试需要带 `node:sqlite` 的 Node 22.13+，加载真实 ETS 规则、缓存与同步代码；使用真实 SQLite 事务及模拟网络，不等同于设备 RDB 测试。

- [设计、状态机和接口](doc/DESIGN.md)
- [实测记录和复验步骤](doc/VALIDATION.md)
- [模型版本、摘要和来源](doc/MODELS.md)
- [第三方许可](doc/ATTRIBUTION.md)

本独立工程按 AGPL-3.0 提供完整源码；第三方原生库保留自身许可。个人报告和模板仅保存在仓库外。
