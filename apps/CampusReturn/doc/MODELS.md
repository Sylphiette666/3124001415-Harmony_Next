# 模型和系统能力

归物优先使用系统提供的 Core Vision OCR 与通用分类标签，语音使用 Core Speech，分词和实体使用 Natural Language Kit。系统模型由 HarmonyOS 管理，工程不内置或伪造这些模型的返回值。API24模拟器可能没有相关能力；具体实测见 [VALIDATION.md](VALIDATION.md)。

类别补充使用与实验三相同的真实 **YOLOv13-N** ONNX，通过 TaskPool、N-API 和 ONNX Runtime CPU 推理。80类映射到校园类别的子集：书本→书籍、瓶子/杯子→水杯、笔记本电脑→电脑、手提包/行李箱→背包，雨伞、手机、背包保持名称。YOLO没有校园卡、钥匙等完整校园类别体系，不能给出可靠结果时保留手动选择。

- 模型：[iMoonLab/yolov13](https://github.com/iMoonLab/yolov13)，来源提交 `73289949533efac82bb5f72ec19b746618656bd2`。
- 官方权重：[yolov13n.pt](https://github.com/iMoonLab/yolov13/releases/tag/yolov13)。导出与完整清单见 [实验三模型工具](../../SmartObjectAssistant/models) 和本目录 `../models/manifest.json`。
- 文件：`entry/src/main/resources/rawfile/yolov13n.onnx`，10,288,664字节，SHA256 **8f7ae9367c0219f86ab2633da415172545aae076abda3a470d1b92634f84c0d2**。
- 输入 `[1,3,640,640]`，输出 `[1,84,8400]`，opset17、float32、静态batch1、无内置NMS。采用等比例letterbox、RGB/255、CHW，同类NMS0.45，建议阈值0.25。
- 许可AGPL-3.0，保留根LICENSE及models/YOLOv13-LICENSE.txt。

原生库来自 [csukuangfj/onnxruntime-libs v1.16.3](https://github.com/csukuangfj/onnxruntime-libs/releases/tag/v1.16.3)，是实际OHOS构建；包含arm64-v8a与x86_64。头文件、原始库、MIT与ThirdPartyNotices均在 `entry/src/main/cpp/third_party/onnxruntime`。N-API用ArrayBuffer传递张量，手动获取C API。没有服务端图片检测，也没有固定类别假结果。

| 架构 | 上游下载归档SHA256 |
|---|---|
| arm64-v8a | 3367a54ef1f1c429d1116540e4e5bca98ff28b6de1603d53f4f73ebc24504b85 |
| x86_64 | 6b86433b489ac709dc397a8e07e32d308d4438176b6df11413090c1ff07ac15e |

随包 `demo-card.jpg` 为代码绘制的合成教学卡片，编号202600001、姓名张同学，并印有“仅供教学演示 非真实证件”。它用于确认图片输入及实际能力降级，不预存OCR、分类或识别结果。发布者应确认和修改真实抽取结果。

`demo-book.jpg`和`demo-book-near.jpg`为代码绘制的合成图书封面，编号分别BK20260001、BK00009999，仅用于权重对照登记。种子资料的结构化文字是明确的教学初始数据，与点击识别时实际调用AI返回的内容分开。
