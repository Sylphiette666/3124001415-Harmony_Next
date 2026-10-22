# 模型与推理库来源

## YOLOv13-N

- 官方项目：[iMoonLab/yolov13](https://github.com/iMoonLab/yolov13)，导出来源提交`73289949533efac82bb5f72ec19b746618656bd2`。
- 官方权重：[YOLOv13 release 的 yolov13n.pt](https://github.com/iMoonLab/yolov13/releases/tag/yolov13)。上游发布的是PT权重，本项目将其导出为ONNX，没有用其它YOLO版本替代。
- 许可：AGPL-3.0，保留于`models/YOLOv13-LICENSE.txt`。独立实验三工程按AGPL-3.0开放源码；ONNX Runtime部分沿用其自身MIT许可。
- 预期导出参数：640、batch1、opset17、float32、无动态维度、不内置NMS。文件来源、权重SHA256、ONNX SHA256、尺寸和形状记录在`models/manifest.json`。

ONNX随包提供，普通DevEco构建不要求安装PyTorch。需要重新导出时，可使用Python3.12环境：

```powershell
git clone https://github.com/iMoonLab/yolov13.git yolov13-source
git -C yolov13-source checkout 73289949533efac82bb5f72ec19b746618656bd2
python -m venv .export-env
.\.export-env\Scripts\python.exe -m pip install -r models/requirements-export.txt
# 将官方release中的yolov13n.pt保存到自己的下载目录
.\.export-env\Scripts\python.exe models/export_model.py --source-dir yolov13-source --weights <官方权重路径>
```

CPU导出使用上游已有的非FlashAttention路径；不需要安装只适用于特定Linux/CUDA环境的FlashAttention wheel。检查器直接使用ONNX Runtime执行图，不使用模型元数据中的Python表达式。

## ONNX Runtime鸿蒙构建

本机OHPM注册表未提供名称恰为`onnxruntime-ohos`的包，因此采用真正的原生ONNX Runtime鸿蒙构建，通过N-API封装。库来自维护者[csukuangfj/onnxruntime-libs v1.16.3](https://github.com/csukuangfj/onnxruntime-libs/releases/tag/v1.16.3)，为`onnxruntime-ohos`平台产物。不是伪造同名HAR接口，也不在服务端执行图片识别。

| 架构 | 下载压缩包SHA256 |
| --- | --- |
| arm64-v8a | 3367a54ef1f1c429d1116540e4e5bca98ff28b6de1603d53f4f73ebc24504b85 |
| x86_64 | 6b86433b489ac709dc397a8e07e32d308d4438176b6df11413090c1ff07ac15e |

解压后的头文件、对应so和上游LICENSE/ThirdPartyNotices位于`entry/src/main/cpp/third_party/onnxruntime`，CMake链接并由Hvigor打入两种ABI。N-API包装位于`detector.cpp`，通过上游支持的`ORT_API_MANUAL_INIT`取得C API并管理会话。会话使用CPU执行提供程序、2个intra-op线程和1个inter-op线程，按模型路径缓存。

## 实验参考图

`sample-bus.jpg`来自同一官方源代码的`ultralytics/assets/bus.jpg`。它仅是输入照片；识别框由随包模型实际生成。示例便于没有相机的模拟器复验，不预置检测结果。

本机API24模拟器实测拒绝加载维护者的1.27.0构建，设备日志出现原生重定位与入口符号错误；改用兼容的1.16.3包后可建立真实模型会话。以设备行为确认兼容版本，不将编译成功视为运行成功。原始库文件保持上游字节内容。
