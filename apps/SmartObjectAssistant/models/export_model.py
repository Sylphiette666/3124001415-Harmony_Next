"""Export trusted official YOLOv13-N weights; app inference does not need Python."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import time


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-dir', type=Path, required=True, help='iMoonLab/yolov13 source checkout')
    parser.add_argument('--weights', type=Path, required=True, help='official yolov13n.pt release asset')
    parser.add_argument('--reference-dir', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    source = args.source_dir.resolve(); weights = args.weights.resolve()
    sys.path.insert(0, str(source))
    import torch
    import numpy as np
    import onnx
    import onnxruntime as ort
    from PIL import Image
    from ultralytics import YOLO
    torch.set_num_threads(2)
    model = YOLO(str(weights))
    exported = Path(model.export(format='onnx', imgsz=640, batch=1, device='cpu', opset=17,
                                 simplify=False, dynamic=False, half=False, nms=False))
    graph = onnx.load(exported)
    onnx.checker.check_model(graph)
    target = root / 'entry/src/main/resources/rawfile/yolov13n.onnx'
    shutil.copyfile(exported, target)
    session_options = ort.SessionOptions(); session_options.intra_op_num_threads = 2
    session = ort.InferenceSession(str(target), sess_options=session_options, providers=['CPUExecutionProvider'])
    assert session.get_inputs()[0].shape == [1, 3, 640, 640]
    output_shape = session.get_outputs()[0].shape
    assert len(output_shape) == 3 and output_shape[0] == 1 and 84 in output_shape
    commit = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    manifest = {'version': '1.0.0', 'model': 'YOLOv13-N', 'inputSize': 640,
                'inputShape': session.get_inputs()[0].shape, 'outputShape': output_shape,
                'sha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'size': target.stat().st_size,
                'source': 'https://github.com/iMoonLab/yolov13', 'sourceCommit': commit,
                'weightsUrl': 'https://github.com/iMoonLab/yolov13/releases/download/yolov13/yolov13n.pt',
                'weightsSha256': hashlib.sha256(weights.read_bytes()).hexdigest(),
                'export': {'torch': torch.__version__, 'onnx': onnx.__version__, 'opset': 17, 'nms': False, 'dynamic': False},
                'license': 'AGPL-3.0'}
    (root / 'models/manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    if args.reference_dir:
        out = args.reference_dir.resolve(); out.mkdir(parents=True, exist_ok=True)
        rgb = np.array(Image.open(root / 'entry/src/main/resources/rawfile/sample-bus.jpg').convert('RGBA'))
        height, width, _ = rgb.shape
        ratio = min(640 / width, 640 / height)
        rw, rh = math.floor(width * ratio + .5), math.floor(height * ratio + .5)
        px, py = (640 - rw) // 2, (640 - rh) // 2
        fx = np.clip((np.arange(rw) + .5) / (rw / width) - .5, 0, width - 1)
        fy = np.clip((np.arange(rh) + .5) / (rh / height) - .5, 0, height - 1)
        x0, y0 = np.floor(fx).astype(int), np.floor(fy).astype(int)
        x1, y1 = np.minimum(x0 + 1, width - 1), np.minimum(y0 + 1, height - 1)
        dx, dy = (fx - x0)[None, :, None], (fy - y0)[:, None, None]
        top = rgb[y0[:, None], x0[None, :], :3] * (1 - dx) + rgb[y0[:, None], x1[None, :], :3] * dx
        bottom = rgb[y1[:, None], x0[None, :], :3] * (1 - dx) + rgb[y1[:, None], x1[None, :], :3] * dx
        prepared = np.full((640, 640, 3), 114 / 255, dtype=np.float32)
        prepared[py:py + rh, px:px + rw] = (top * (1 - dy) + bottom * dy) / 255
        tensor = prepared.transpose(2, 0, 1)[None].copy()
        started = time.perf_counter(); output = session.run(None, {session.get_inputs()[0].name: tensor})[0]
        elapsed = (time.perf_counter() - started) * 1000
        rgb.tofile(out / 'sample.rgba'); tensor.tofile(out / 'input.f32'); output.tofile(out / 'output.f32')
        (out / 'reference.json').write_text(json.dumps({'width': width, 'height': height, 'outputShape': list(output.shape),
                                                      'windowsOrtMs': elapsed, 'modelSha256': manifest['sha256']}), encoding='utf-8')
        print('Reference output', output.shape, 'CPU milliseconds', round(elapsed, 2))
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
