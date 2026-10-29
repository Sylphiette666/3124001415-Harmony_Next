# 第三方来源与许可

本目录为实验四独立工程，按AGPL-3.0提供源码；其它App各自许可不受影响。

| 内容 | 来源 | 许可 |
|---|---|---|
| YOLOv13-N模型、前后处理与N-API基础 | [iMoonLab/yolov13](https://github.com/iMoonLab/yolov13)，由本仓库实验三端侧检测实现复用 | AGPL-3.0，根LICENSE、models/YOLOv13-LICENSE.txt及manifest |
| ONNX Runtime OHOS1.16.3头文件与两种ABI库 | [csukuangfj/onnxruntime-libs](https://github.com/csukuangfj/onnxruntime-libs/releases/tag/v1.16.3)，基于Microsoft ONNX Runtime | MIT及ThirdPartyNotices，保留在原生库目录 |
| FastAPI、PyJWT、HTTPX、pytest、jieba | 各自官方Python包，固定版本见server/requirements.txt | MIT，安装包保留自身声明 |
| Uvicorn | 官方Python包 | BSD-3-Clause |
| Pillow | 官方Python包，用于校验上传图片 | HPND等，详见安装包声明 |
| HarmonyOS系统API | 本机HarmonyOS6.1.1/API24 SDK | 使用安装环境提供的接口；系统AI模型未重新分发 |

相机生命周期、相册私有复制、可靠HTTP鉴权及原生ORT适配由实验三复用；实际语音采集由实验一复用。校园数据结构、发布界面、匹配、认领状态机、队列、申诉、信用、角色、本地同步和统计针对实验四重新实现。

蓝色归物图标为项目SVG几何图形，教学卡片由代码绘制；公开截图只使用合成教学数据。私人环境照片、真实身份材料、数据库、随机口令、JWT、报告和模板不纳入版本库。模型大小、摘要与导出来源见 [MODELS.md](MODELS.md)。
