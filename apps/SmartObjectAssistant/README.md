# 识物 智能物品识别助手

物联网软件开发技术实验三。独立 HarmonyOS NEXT App，包名 `cn.gdut.smartobjects`，使用 ArkUI、ONNX Runtime 原生鸿蒙构建和 FastAPI 实现端侧检测与云端记录管理。开发与报告整理使用 CODEX。

## 工程入口

用 **DevEco Studio 6.1.1 / API 24** 打开本目录 `apps/SmartObjectAssistant`，同步 OHPM 后运行 `entry`。相机需要用户授权；相册使用系统 PhotoViewPicker，不申请整个相册的读取权限。随包模型和示例照片可用于离线验证。

```powershell
.\scripts\build.ps1 -DevEcoHome 'D:\HUAWEI\DevEco Studio'
```

安装包生成于 `entry/build/default/outputs/default/entry-default-unsigned.hap`。模拟器可直接安装未签名调试包；物理设备需要在 DevEco 配置自己的签名。工程包含 `arm64-v8a` 和 `x86_64` 原生库。

## 功能

- 相机预览、拍照、前后摄像头切换；系统相册选图；随包示例照片；记录详情中经系统确认导出原图到相册。
- 官方 YOLOv13-N 权重导出的 `yolov13n.onnx`，640×640 RGB letterbox、归一化、NCHW，解析80类 COCO 输出，分类 NMS 和原图坐标还原。
- 默认 TaskPool 后台推理，禁止重叠提交；显示预处理、推理、后处理、解码、加载耗时及主线程最大延迟。对照入口顺序运行同图、同阈值的异步与同步测试。
- 检测框、类别、置信度和分类数量；可修正类别、删除误检项并保存清单。
- 本地 RDB 保存缩略图路径、清单、时间、模型版本、阈值及耗时；按日期和类别查询。
- FastAPI 设备鉴权、短期 JWT、401 自动重新鉴权；记录按设备隔离、`recordId` 幂等及递增修订版本。
- 上传失败持久化待传状态和退避时间，网络恢复事件及页面可见期间的15秒检查自动重试；可手动立即重试。
- 启动检查模型清单；下载验证长度、SHA256及实际 ONNX 输入输出后切换，失败保留旧模型。
- 云端历史查询、时间和类别筛选、分页、分类数量统计。

## 后端与模拟器联调

后端在本机运行即可完成课程验收。它负责管理记录和模型文件；照片识别始终在 App 端执行。

```powershell
# 在本目录运行，需要 Python 3.10+
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r server/requirements.txt
.\.venv\Scripts\python.exe -m server.manage init
.\.venv\Scripts\python.exe -m server.manage provision --device-id deveco-lab3
.\.venv\Scripts\python.exe -m server.manage publish --version 1.0.0
.\.venv\Scripts\python.exe -m uvicorn server.app:app_factory --factory --host 127.0.0.1 --port 8765
```

`provision` 把随机设备密钥写入本地 `.local/deveco-lab3-device-key.txt`，服务端只存其摘要。密钥、JWT签名密钥、数据库和下载的模型版本均在 `.local`，不提交仓库。再次执行 `provision` 会轮换该设备密钥。

另开终端，将设备本地端口转发到运行后端的电脑；设备号以 `hdc list targets` 为准：

```powershell
$taskHdc = 'D:\HUAWEI\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $taskHdc list targets
& $taskHdc -t 127.0.0.1:5555 rport tcp:8765 tcp:8765
```

App右上角设置填写：`http://127.0.0.1:8765`、设备标识 `deveco-lab3`、该设备的私有密钥。保存后会自动鉴权并检查模型。HTTP仅允许本机回环调试，远程部署需HTTPS。不要在源码或报告中填写真实密钥。

也可用 `scripts/start-server.ps1 -PythonPath <python.exe> -DeviceId <设备标识>` 完成首次初始化并启动；后续启动省略 `-DeviceId`，避免无意轮换密钥。

## 模型热更新演示

```powershell
# 发布同一有效模型的新版本，模拟管理端下发新版本
.\.venv\Scripts\python.exe -m server.manage publish --version 1.0.1
```

App设置中检查版本，再点击“下载并切换”。模型文件先保存到`.part`，通过SHA256及原生会话检查后才提交版本与路径。旧版本文件保留，更新失败时继续使用旧版本。

## 检查与文档

```powershell
node scripts/test-core.cjs --deveco-home 'D:\HUAWEI\DevEco Studio'
node scripts/test-services.cjs --deveco-home 'D:\HUAWEI\DevEco Studio'
.\.venv\Scripts\python.exe -m pytest server/tests -q
```

Node测试要求Node 24（包含`node:sqlite`），直接执行实际ETS模型和服务代码。DevEco构建还检查ArkTS和C++。模型导出和Windows参考推理是可选复现步骤，见 [模型来源](doc/MODELS.md)。[设计与接口](doc/DESIGN.md)、[验收记录](doc/VALIDATION.md)、[第三方许可](doc/ATTRIBUTION.md)。

Word实验报告与封面模板保存在仓库外的本地目录。
