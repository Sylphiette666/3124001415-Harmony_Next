# 第三方来源与许可

本目录为独立实验三工程，不改变其它独立 App 的许可。

| 内容 | 来源 | 许可与保留文件 |
| --- | --- | --- |
| YOLOv13-N 权重、导出实现、示例 bus.jpg | [iMoonLab/yolov13](https://github.com/iMoonLab/yolov13)，提交 `73289949533efac82bb5f72ec19b746618656bd2`；权重来自官方 yolov13 release | AGPL-3.0；`LICENSE`、`models/YOLOv13-LICENSE.txt`；导出参数和文件摘要见 `models/manifest.json` |
| ONNX Runtime 1.16.3 OHOS 头文件与两种 ABI 原生库 | [csukuangfj/onnxruntime-libs v1.16.3](https://github.com/csukuangfj/onnxruntime-libs/releases/tag/v1.16.3)，基于 Microsoft ONNX Runtime | MIT；`entry/src/main/cpp/third_party/onnxruntime/LICENSE`、`ThirdPartyNotices.txt`，保留上游附带文件 |
| FastAPI、Uvicorn、PyJWT、HTTPX、pytest | 各自官方 Python 包，固定版本见 `server/requirements.txt` | FastAPI/PyJWT/HTTPX/pytest：MIT；Uvicorn：BSD-3-Clause；安装包保留自身许可 |

新增 ArkUI 界面、TaskPool/N-API 适配、前后处理、本地清单与上传服务随本独立工程按 AGPL-3.0 提供源码。模型不是原创训练成果，COCO80类别名称作中文显示适配。图标为本项目 SVG 几何绘制。

公开截图只使用上游提供的示例输入照片及应用界面。相机联调拍摄的私人环境、设备密钥、JWT、数据库及报告不在仓库中。来源详情和下载摘要见 [MODELS.md](MODELS.md)。
