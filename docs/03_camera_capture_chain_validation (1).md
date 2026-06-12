# 实验 03：RK3588 摄像头拍照链路验证

> 项目：RK3588 端侧多模态智能语音助手系统  
> 平台：LubanCat / RK3588  
> 仓库目录：`/home/cat/ai/qwen3vl2b`  
> 实验编号：03  
> 实验主题：`/dev/video11 -> NV12 -> JPEG -> CameraAdapter` 摄像头拍照链路验证  
> 实验日期：2026-06-12  
> 实验状态：**通过**

---

## 1. 实验背景

实验 01 和实验 02 已经完成了音频硬件链路与项目录音链路验证，确认：

```text
rockchip-es8388
    -> plughw:2,0
    -> arecord 录音
    -> FFmpeg 声道抽取与增益
    -> 16 kHz 单声道 WAV
```

在进入 ASR、KWS、TTS、Qwen3-VL 图文推理以及完整语音助手闭环之前，需要先单独验证摄像头链路。

本实验不接入：

```text
ASR
KWS
TTS
Qwen3-VL
RKNN / RKLLM runtime
完整 orchestrator
```

原因是完整图文问答链路同时涉及摄像头、图片转换、模型文件、运行时库和 CLI 调度。如果直接运行完整助手，一旦失败，将难以判断问题究竟来自摄像头、图片编码、模型资产还是 Python 依赖。

因此实验 03 只验证：

```text
摄像头设备
    -> V4L2 采集
    -> NV12 原始帧
    -> JPEG 图片
    -> 项目 Shell 拍照脚本
    -> Python CameraAdapter
```

---

## 2. 实验目标

实验 03 需要回答以下问题：

```text
1. /dev/video11 是否可以稳定输出图像帧；
2. 摄像头是否支持项目使用的 NV12 格式；
3. 1280×720 NV12 原始帧大小是否正确；
4. FFmpeg 是否可以将 NV12 正确转换为 JPEG；
5. 项目自带 scripts/capture-photo.sh 是否可以生成照片；
6. 项目拍照脚本生成的照片是否为真实摄像头画面；
7. voice_assistant/camera.py 中的 CameraAdapter 是否可以独立工作；
8. CameraAdapter 是否可以移动最终 JPG 并删除临时 NV12；
9. 当前 voice_assistant.py camera 入口是否存在额外依赖耦合。
```

---

## 3. 摄像头基础设备

前置环境检查已经确认摄像头主节点为：

```text
/dev/video11
```

设备类型：

```text
Driver name : rkisp_v6
Card type   : rkisp_mainpath
Device Caps : Video Capture Multiplanar / Streaming
```

项目当前使用的像素格式为：

```text
NV12
```

`/dev/video11` 支持的最大目标分辨率包括：

```text
1920×1080
1280×720
最高可到 3840×2160
```

本实验分别验证：

```text
项目默认拍照：1920×1080 NV12
底层回退采集：1280×720 NV12
```

---

## 4. 相关代码与依赖关系

### 4.1 配置文件

摄像头相关路径位于：

```text
config/default.yaml
```

核心配置关系：

```yaml
paths:
  temp_dir: /tmp/qwen_voice_assistant
  photo_dir: /home/cat/图片
  capture_script: /home/cat/ai/qwen3vl2b/scripts/capture-photo.sh
```

含义：

```text
capture_script
    指向底层拍照 Shell 脚本；

temp_dir
    CameraAdapter 的临时采集工作目录；

photo_dir
    最终 JPEG 图片保存目录。
```

---

### 4.2 Shell 拍照脚本

文件：

```text
scripts/capture-photo.sh
```

该脚本的默认参数为：

```bash
device="/dev/video11"
width="1920"
height="1080"
pixfmt="NV12"
skip="30"
out_dir="/home/cat/图片"
prefix="camera"
```

脚本链路：

```text
v4l2-ctl
    -> 设置 1920×1080 NV12
    -> mmap 方式申请 4 个缓冲区
    -> 跳过前 30 帧
    -> 保存 1 帧 NV12
    -> FFmpeg 转换为 JPEG
```

核心采集命令：

```bash
v4l2-ctl -d "$device" \
  --set-fmt-video="width=${width},height=${height},pixelformat=${pixfmt}" \
  --stream-mmap=4 \
  --stream-skip="$skip" \
  --stream-count=1 \
  --stream-to="$raw_path"
```

核心转换命令：

```bash
ffmpeg -y \
  -f rawvideo \
  -pix_fmt nv12 \
  -s "${width}x${height}" \
  -i "$raw_path" \
  -frames:v 1 \
  "$jpg_path"
```

脚本最终通过标准输出返回：

```text
jpg=最终 JPEG 路径
raw=原始 NV12 路径
raw_size=原始文件大小
device=摄像头节点
format=采集格式
```

这组键值对供 Python `CameraAdapter` 解析。

---

### 4.3 Python CameraAdapter

文件：

```text
voice_assistant/camera.py
```

核心类：

```python
class CameraAdapter:
    ...
```

`CameraAdapter.capture()` 的工作流程为：

```text
1. 创建临时工作目录：
   /tmp/qwen_voice_assistant/capture_work

2. 生成时间戳：
   YYYYMMDD_HHMMSS

3. 调用 capture-photo.sh：
   --out-dir 临时工作目录
   --prefix voice
   --timestamp 当前时间戳

4. 解析 Shell 脚本输出的 jpg= 和 raw=；

5. 将 JPG 从临时工作目录移动到：
   /home/cat/图片

6. 删除临时 NV12 文件；

7. 返回最终 JPG 的 Path。
```

依赖关系如下：

```text
CameraAdapter
    -> config/default.yaml
    -> scripts/capture-photo.sh
        -> v4l2-ctl
        -> ffmpeg
        -> /dev/video11
```

Python 侧只使用标准库：

```text
shutil
subprocess
datetime
pathlib
```

因此 CameraAdapter 本身不依赖：

```text
sherpa_onnx
ASR 模型
Qwen 模型
RKNN / RKLLM runtime
```

---

## 5. 实验 03.1：摄像头双路径基础验证

### 5.1 输出目录

```text
output/exp03_camera_capture_20260612_143534
```

主要文件：

```text
exp03_camera_capture_check.log
latest_project_capture.jpg
v4l2_frame_1280x720.nv12
v4l2_frame_1280x720.jpg
07_test_camera_script.log
08_capture_photo_with_arg.log
08_capture_photo_no_arg.log
09_new_images_sorted.log
10_v4l2_raw_capture.log
10_ffmpeg_nv12_to_jpg.log
```

---

### 5.2 自动检查脚本

实验创建并运行：

```text
scripts/exp03_camera_capture_check.sh
```

脚本同时验证两条路径：

```text
路径 A：项目自带 capture-photo.sh

路径 B：v4l2-ctl 直接采集
        -> FFmpeg 转换 JPEG
```

这样可以区分：

```text
摄像头驱动问题
项目脚本问题
图片转换问题
Python 上层入口问题
```

---

## 6. 项目 Shell 拍照脚本结果

直接无参数运行：

```bash
bash scripts/capture-photo.sh
```

日志结果：

```text
29.98 fps

jpg=/home/cat/图片/camera_20260612_143535.jpg
raw=/home/cat/图片/camera_20260612_143535.nv12
raw_size=3110400
device=/dev/video11
format=1920x1080 NV12
```

说明项目脚本完成了：

```text
/dev/video11
    -> 1920×1080 NV12
    -> 跳过前 30 帧
    -> 保存原始帧
    -> 转换为 JPEG
```

1920×1080 NV12 理论单帧大小为：

```text
1920 × 1080 × 3 / 2
= 3,110,400 bytes
```

脚本输出：

```text
raw_size=3110400
```

与理论值完全一致。

实验脚本随后将新生成的项目照片复制为：

```text
output/exp03_camera_capture_20260612_143534/latest_project_capture.jpg
```

---

## 7. 底层 V4L2 回退采集结果

为了独立验证摄像头驱动和格式，实验通过 `v4l2-ctl` 直接采集一帧：

```bash
v4l2-ctl -d /dev/video11 \
  --set-fmt-video=width=1280,height=720,pixelformat=NV12 \
  --stream-mmap=3 \
  --stream-count=1 \
  --stream-to=v4l2_frame_1280x720.nv12
```

然后使用 FFmpeg 转换：

```bash
ffmpeg -y \
  -f rawvideo \
  -pix_fmt nv12 \
  -s 1280x720 \
  -i v4l2_frame_1280x720.nv12 \
  -frames:v 1 \
  v4l2_frame_1280x720.jpg
```

输出文件：

```text
output/exp03_camera_capture_20260612_143534/v4l2_frame_1280x720.nv12
output/exp03_camera_capture_20260612_143534/v4l2_frame_1280x720.jpg
```

---

## 8. 原始 NV12 文件大小验证

1280×720 的 NV12 单帧理论大小为：

```text
1280 × 720 × 3 / 2
= 1,382,400 bytes
```

实际结果：

```text
actual_size  : 1382400
expected_size: 1382400
[OK] NV12 raw frame size is correct
```

结论：

```text
V4L2 输出的数据长度与 1280×720 NV12 格式完全匹配；
不存在少帧、文件截断或错误像素格式问题。
```

---

## 9. JPEG 图片格式与解码验证

### 9.1 项目脚本图片

文件：

```text
latest_project_capture.jpg
```

信息：

```text
JPEG image data
baseline
precision 8
1920×1080
components 3
```

FFprobe：

```text
codec_name=mjpeg
codec_type=video
width=1920
height=1080
pix_fmt=yuvj420p
format_name=image2
size=67068
```

完整解码结果：

```text
[OK] project image decode passed
```

---

### 9.2 底层回退图片

文件：

```text
v4l2_frame_1280x720.jpg
```

信息：

```text
JPEG image data
baseline
precision 8
1280×720
components 3
```

FFprobe：

```text
codec_name=mjpeg
codec_type=video
width=1280
height=720
pix_fmt=yuvj420p
format_name=image2
size=60397
```

完整解码结果：

```text
[OK] fallback image decode passed
```

---

## 10. 图片真实性验证

三张图片 SHA256：

```text
latest_project_capture.jpg:
aada1b7debb7bafadd58aff42bf747a9f72093ca48af34a1bc9b19ad2c71baa1

v4l2_frame_1280x720.jpg:
220adb37b93fcedd866b721ba3f2c8b870d5819ac354a0a59290bd455b9a7d31

demo.jpg:
58c5c9898c5359bcf53797711e3d954c8ef529e141cb012ffc433376933839e7
```

三者哈希均不相同。

因此可以排除：

```text
项目脚本直接复制 demo.jpg；
底层验证图片使用了占位图片；
两条采集路径只是重复引用同一个已有文件。
```

用户人工查看后确认：

```text
latest_project_capture.jpg 图像正确；
v4l2_frame_1280x720.jpg 图像正确；
不存在全黑、全绿、花屏、明显偏色或错误场景。
```

---

## 11. 实验基础结论

自动实验最终输出：

```text
[OK ] project script produced image:
output/exp03_camera_capture_20260612_143534/latest_project_capture.jpg

[OK ] fallback V4L2 produced image:
output/exp03_camera_capture_20260612_143534/v4l2_frame_1280x720.jpg

[RESULT] Experiment 03 basic camera capture PASSED.
```

这说明：

```text
1. 项目自带拍照脚本可以出图；
2. V4L2 直接采集也可以出图；
3. 摄像头驱动、节点、权限和格式均正常；
4. FFmpeg 可以完成 NV12 到 JPEG 的转换；
5. 项目脚本链路和底层链路都已通过。
```

---

## 12. 实验中发现的参数调用问题

实验脚本第一次尝试：

```bash
bash scripts/capture-photo.sh \
  output/exp03_camera_capture_20260612_143534/project_capture_arg.jpg
```

返回：

```text
Unknown option: output/.../project_capture_arg.jpg
```

原因不是拍照失败，而是 `capture-photo.sh` 不接受位置参数。

该脚本只接受命名选项：

```text
--device
--width
--height
--pixfmt
--skip
--out-dir
--prefix
--timestamp
```

正确调用方式：

```bash
scripts/capture-photo.sh \
  --out-dir output/test_camera \
  --prefix photo \
  --timestamp manual
```

因此这次失败属于：

```text
测试调用方式错误
```

而不属于：

```text
摄像头链路错误
```

---

## 13. `test_camera.sh` 的依赖耦合问题

项目自带测试脚本运行时失败：

```text
Capturing one photo through CameraAdapter...

ModuleNotFoundError: No module named 'sherpa_onnx'
```

完整导入链路：

```text
scripts/test_camera.sh
    -> voice_assistant.py
    -> voice_assistant.cli
    -> voice_assistant.orchestrator
    -> voice_assistant.asr
    -> import sherpa_onnx
```

问题本质：

```text
camera 命令本身不需要 ASR；
但 cli.py 在处理 camera 命令之前导入了 orchestrator；
orchestrator 又在顶部导入 asr.py；
最终导致 camera 命令被 sherpa_onnx 阻塞。
```

这与实验 02 中 `record` 命令遇到的问题属于同一种设计问题：

```text
CLI 顶层全局导入过重；
独立模块命令被完整助手依赖链耦合。
```

需要强调：

```text
这不是摄像头、capture-photo.sh 或 CameraAdapter 的错误；
而是 voice_assistant.py camera 命令入口的依赖解耦尚未完成。
```

---

## 14. 实验 03.2：CameraAdapter 独立验证

### 14.1 实验目的

为了绕开 `cli.py -> orchestrator -> asr.py` 的重依赖，创建独立测试脚本：

```text
scripts/test_camera_adapter_only.py
```

该脚本只导入：

```text
voice_assistant.config
voice_assistant.camera
```

不导入：

```text
orchestrator
asr
sherpa_onnx
Qwen
TTS
```

这样可以直接验证 `CameraAdapter.capture()` 本身。

---

### 14.2 输出目录

```text
output/exp03_2_camera_adapter_20260612_153441
```

---

### 14.3 配置读取结果

```text
project_dir    : /home/cat/ai/qwen3vl2b
config         : /home/cat/ai/qwen3vl2b/config/default.yaml
capture_script : /home/cat/ai/qwen3vl2b/scripts/capture-photo.sh
temp_dir       : /tmp/qwen_voice_assistant
photo_dir      : /home/cat/图片
```

说明 CameraAdapter 正确读取了项目配置。

---

### 14.4 CameraAdapter 执行结果

执行：

```text
[RUN] CameraAdapter.capture()
```

结果：

```text
image_path : /home/cat/图片/voice_20260612_153441.jpg
size_bytes : 68346
sha256     : d799f43fb8a1d21443c75be2aaa01b2c5ae8414249b6c99db0d32626e44f7bb3
[OK] CameraAdapter.capture() passed
```

输出文件：

```text
/home/cat/图片/voice_20260612_153441.jpg
```

文件大小：

```text
68346 bytes
约 67 KB
```

---

### 14.5 CameraAdapter 输出图片验证

文件类型：

```text
JPEG image data
baseline
precision 8
1920×1080
components 3
```

FFprobe：

```text
codec_name=mjpeg
width=1920
height=1080
pix_fmt=yuvj420p
format_name=image2
size=68346
```

解码结果：

```text
[OK] returned image decode passed
```

因此 CameraAdapter 成功完成：

```text
配置读取
    -> 调用 capture-photo.sh
    -> 采集 1920×1080 NV12
    -> 转换 JPEG
    -> 解析脚本输出
    -> 移动图片
    -> 返回最终路径
```

---

## 15. 临时文件清理验证

检查目录：

```text
/tmp/qwen_voice_assistant/capture_work
```

结果无文件输出：

```text
==================== capture work residue ====================
```

说明没有残留本次采集的临时 NV12 文件。

这证明 `CameraAdapter.capture()` 中的清理逻辑正常：

```python
raw.unlink(missing_ok=True)
```

CameraAdapter 会：

```text
保留最终 JPEG；
删除临时原始 NV12；
避免长期运行时原始帧持续占用磁盘。
```

---

## 16. 两种采集路径对比

| 项目 | 项目脚本路径 | 底层回退路径 |
|---|---|---|
| 输入节点 | `/dev/video11` | `/dev/video11` |
| 分辨率 | 1920×1080 | 1280×720 |
| 像素格式 | NV12 | NV12 |
| 采集工具 | `capture-photo.sh` 内部调用 `v4l2-ctl` | 直接调用 `v4l2-ctl` |
| 预热方式 | 跳过前 30 帧 | 本次直接保存 1 帧 |
| 原始文件 | 3,110,400 bytes | 1,382,400 bytes |
| 图片转换 | FFmpeg | FFmpeg |
| 输出格式 | JPEG | JPEG |
| 解码验证 | 通过 | 通过 |
| 人工查看 | 正常 | 正常 |

项目脚本跳过前 30 帧的意义是：

```text
摄像头刚启动时，自动曝光、自动白平衡和 ISP 状态可能尚未稳定；
跳过前若干帧后再保存，可以减少首帧偏暗、偏色或曝光不稳定。
```

---

## 17. 当前完整摄像头依赖关系

```text
config/default.yaml
    │
    ├── capture_script
    │       └── scripts/capture-photo.sh
    │               ├── /dev/video11
    │               ├── v4l2-ctl
    │               └── ffmpeg
    │
    ├── temp_dir
    │       └── /tmp/qwen_voice_assistant/capture_work
    │
    └── photo_dir
            └── /home/cat/图片

voice_assistant/camera.py
    └── CameraAdapter.capture()
            ├── subprocess.run(capture-photo.sh)
            ├── 解析 jpg= / raw=
            ├── shutil.move(JPEG)
            ├── 删除临时 NV12
            └── 返回最终图片 Path
```

当前链路中，摄像头模块本身不需要：

```text
sherpa_onnx
ASR 模型
KWS 模型
TTS 模型
Qwen3-VL 模型
RKNN runtime
RKLLM runtime
```

只有通过当前未解耦的 `voice_assistant.py camera` 入口运行时，才会被错误地要求导入 `sherpa_onnx`。

---

## 18. 实验通过项

| 检查项 | 状态 | 结果 |
|---|---|---|
| `/dev/video11` 存在 | 通过 | `rkisp_mainpath` |
| NV12 采集 | 通过 | 1280×720 与 1920×1080 |
| V4L2 mmap 采集 | 通过 | 可以保存完整原始帧 |
| 1280×720 NV12 大小 | 通过 | 1,382,400 bytes |
| 1920×1080 NV12 大小 | 通过 | 3,110,400 bytes |
| FFmpeg NV12 转 JPEG | 通过 | 两种分辨率均正常 |
| 项目 `capture-photo.sh` | 通过 | 输出 1920×1080 JPEG |
| 项目图片完整解码 | 通过 | FFmpeg 解码正常 |
| 底层图片完整解码 | 通过 | FFmpeg 解码正常 |
| 图片人工检查 | 通过 | 画面正确 |
| 图片非占位图 | 通过 | SHA256 与 `demo.jpg` 不同 |
| `CameraAdapter.capture()` | 通过 | 返回最终 JPEG |
| CameraAdapter 移动图片 | 通过 | 保存到 `/home/cat/图片` |
| CameraAdapter 删除临时 raw | 通过 | `capture_work` 无残留 |
| `voice_assistant.py camera` | 暂未通过 | 被 `sherpa_onnx` 导入耦合阻塞 |

---

## 19. 实验 03 最终结论

实验 03 判定：**通过**。

本实验已经证明：

```text
1. RK3588 / LubanCat 的摄像头节点 /dev/video11 可正常工作；
2. rkisp_mainpath 可以输出 NV12 图像；
3. V4L2 mmap 采集链路正常；
4. 1280×720 和 1920×1080 两种分辨率均可完成采集；
5. 原始 NV12 文件大小与理论值完全一致；
6. FFmpeg 可以正确完成 NV12 到 JPEG 的转换；
7. 项目 capture-photo.sh 可以生成真实的 1920×1080 摄像头照片；
8. 项目照片和底层回退照片均能完整解码；
9. 用户人工确认两张图片画面均正确；
10. 图片不是 demo.jpg 或其他占位图片；
11. Python CameraAdapter 可以独立完成完整拍照流程；
12. CameraAdapter 可以移动最终 JPEG 并删除临时 NV12；
13. 摄像头模块本身不依赖 sherpa_onnx；
14. 当前剩余问题只是 voice_assistant.py camera 入口的重依赖耦合。
```

因此后续实验中，若 Qwen3-VL 图文问答失败，不应再优先怀疑：

```text
摄像头硬件
/dev/video11
NV12 采集
FFmpeg 图片转换
capture-photo.sh
CameraAdapter
```

应重点检查：

```text
CLI 依赖解耦
Qwen demo
imgenc
RKNN / RKLLM runtime
视觉模型与语言模型文件
图片输入参数
完整 orchestrator 调度
```

---

## 20. 当前可复用命令

### 20.1 使用项目脚本拍照

```bash
cd /home/cat/ai/qwen3vl2b

scripts/capture-photo.sh
```

默认输出到：

```text
/home/cat/图片/camera_YYYYMMDD_HHMMSS.jpg
```

---

### 20.2 指定输出目录和前缀

```bash
scripts/capture-photo.sh \
  --out-dir output/camera_test \
  --prefix photo \
  --timestamp manual
```

输出：

```text
output/camera_test/photo_manual.nv12
output/camera_test/photo_manual.jpg
```

---

### 20.3 直接运行 CameraAdapter

```bash
python3 scripts/test_camera_adapter_only.py \
  --config config/default.yaml
```

预期：

```text
[OK] CameraAdapter.capture() passed
```

---

### 20.4 底层直接采集 1280×720 NV12

```bash
v4l2-ctl -d /dev/video11 \
  --set-fmt-video=width=1280,height=720,pixelformat=NV12 \
  --stream-mmap=3 \
  --stream-count=1 \
  --stream-to=frame_1280x720.nv12
```

---

### 20.5 NV12 转 JPEG

```bash
ffmpeg -y \
  -f rawvideo \
  -pix_fmt nv12 \
  -s 1280x720 \
  -i frame_1280x720.nv12 \
  -frames:v 1 \
  frame_1280x720.jpg
```

---

## 21. 后续实验建议

实验 03 已经封口。

下一阶段建议进入：

```text
实验 04：ASR 依赖与模型资产验证
```

主要目标：

```text
1. 检查并安装与 Python 3.9 / RK3588 匹配的 sherpa_onnx；
2. 检查 ASR 模型目录和文件完整性；
3. 单独验证离线 wav -> 中文文本；
4. 验证 voice_assistant.py stt；
5. 不接 KWS、不接 TTS、不接 Qwen；
6. 继续保持模块化验证，避免完整链路问题混杂。
```

同时应记录一个待修复项：

```text
将 camera 子命令也改为 lazy import / 轻量入口，
使 voice_assistant.py camera 不再依赖 sherpa_onnx。
```

该问题不影响实验 03 的通过判定，可以在后续 CLI 统一重构阶段处理。

---

# 实验 03 阶段性封口

```text
/dev/video11
    -> V4L2 NV12
    -> FFmpeg JPEG
    -> capture-photo.sh
    -> CameraAdapter
    -> /home/cat/图片/voice_*.jpg
```

整条摄像头拍照链路已经验证通过，实验 03 正式完成。
