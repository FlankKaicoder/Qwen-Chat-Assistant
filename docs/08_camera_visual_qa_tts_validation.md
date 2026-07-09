# 实验 08：摄像头拍照 -> Qwen3-VL 图文问答 -> TTS 语音播报验证

> 项目：RK3588 端侧多模态智能语音助手系统  
> 平台：LubanCat / RK3588  
> 仓库目录：`/home/cat/ai/qwen3vl2b`  
> 实验编号：08  
> 实验主题：真实摄像头照片采集、Qwen3-VL 图像理解、TTS 中文语音播报、`once` 语音触发视觉问答验证  
> 实验状态：**通过**  
> 记录日期：2026-07-09

---

## 1. 实验背景

前置实验已经完成了端侧多模态语音助手的主要基础链路：

```text
实验 03：摄像头拍照链路
  /dev/video11 -> V4L2 NV12 -> FFmpeg JPEG -> CameraAdapter

实验 05：Qwen3-VL 图文推理链路
  图片 / 文本 -> QwenRunner -> Qwen3-VL -> 文本回答

实验 06：TTS 中文合成与播放链路
  文本回答 -> Sherpa-ONNX Matcha-TTS -> Vocos -> plughw:2,0 播放

实验 07：单轮语音问答闭环
  record -> stt -> qwen -> full-answer tts -> play
```

到实验 07 结束时，项目已经具备：

```text
用户语音输入
  -> 麦克风录音
  -> Sherpa-ONNX 中文 ASR
  -> Qwen3-VL 本地推理
  -> 文本回答
  -> Sherpa-ONNX Matcha-TTS
  -> Vocos 声码器
  -> PcmSpeakerStream
  -> ALSA plughw:2,0
  -> 板端中文语音播放
```

但实验 07 主要验证的是普通语音问答闭环，并没有验证真实摄像头画面是否可以进入完整语音助手流程。

因此实验 08 的目标是进一步验证视觉能力链路：

```text
真实摄像头画面
  -> 拍照
  -> Qwen3-VL 图像理解
  -> 中文文本描述
  -> TTS 语音播报
```

本实验仍然不接 KWS 唤醒词，避免将唤醒词检测、录音、ASR、意图、摄像头、Qwen、TTS 全部一次性混在一起。实验 08 先分三步逐级验证视觉问答能力：

```text
08.1 CameraAdapter.capture() 手动拍照 -> Qwen -> TTS
08.2 官方 ask --force-photo -> 自动拍照 -> Qwen -> TTS
08.3 官方 once 语音触发 -> ASR -> 意图判断 -> 自动拍照 -> Qwen -> TTS
```

---

## 2. 实验目标

实验 08 需要回答以下问题：

```text
1. CameraAdapter.capture() 是否可以在当前阶段继续正常拍摄真实图片；
2. 真实摄像头图片是否可以送入 Qwen3-VL 进行图文理解；
3. Qwen3-VL 对真实摄像头图片的回答是否可以送入 TTS 播放；
4. voice_assistant.py ask --force-photo 是否可以自动触发拍照；
5. once 入口能否通过语音指令触发拍照意图；
6. ASR 识别结果是否会影响拍照意图判断；
7. 语音触发拍照问答时是否仍然保持 underrun_count=0；
8. 实验 08 通过后，系统是否具备“语音触发视觉问答”的能力。
```

---

## 3. 实验总体拆分

实验 08 分为三个子实验：

```text
08.1 CameraAdapter.capture() -> Qwen3-VL -> TTS
08.2 voice_assistant.py ask --force-photo -> Qwen3-VL -> TTS
08.3 voice_assistant.py once -> 语音指令 -> 自动拍照 -> Qwen3-VL -> TTS
```

每一步的定位意义不同：

| 子实验 | 验证入口 | 目的 |
|---|---|---|
| 08.1 | 独立 Python 调用 CameraAdapter，再显式 ask 和 tts-stream | 验证底层能力串联成立 |
| 08.2 | 官方 `ask --force-photo` | 验证 ask 入口可以自己触发拍照 |
| 08.3 | 官方 `once` | 验证语音指令可以触发视觉问答 |

---

## 4. 相关代码关系

### 4.1 摄像头拍照链路

摄像头模块的核心链路仍然是实验 03 已验证过的：

```text
voice_assistant/camera.py
  -> CameraAdapter.capture()
      -> scripts/capture-photo.sh
          -> /dev/video11
          -> v4l2-ctl
          -> NV12 raw frame
          -> ffmpeg
          -> JPEG
      -> 解析 jpg= / raw=
      -> 移动 JPEG 到 /home/cat/图片
      -> 删除临时 NV12
      -> 返回最终图片路径
```

输出图片通常为：

```text
/home/cat/图片/voice_YYYYMMDD_HHMMSS.jpg
```

本实验中拍照结果均为：

```text
codec_name=mjpeg
width=1920
height=1080
pix_fmt=yuvj420p
```

说明拍照输出仍然是 1920×1080 JPEG，格式正常。

---

### 4.2 Qwen 图文推理链路

Qwen 图文理解由 `voice_assistant/qwen_runner.py` 负责，其核心职责为：

```text
1. 读取 config/default.yaml 中 qwen 配置；
2. 组装 demo 启动参数；
3. 设置 LD_LIBRARY_PATH；
4. 使用 pexpect 启动交互式 demo；
5. 等待 user: 提示；
6. 发送带 <image> 标记的问题；
7. 等待 robot: 输出；
8. 清理 runtime 日志；
9. 返回最终中文回答。
```

典型输入形式为：

```text
<image>请用一句中文简短描述摄像头拍到的画面。
```

当使用 `ask --force-photo` 时，CLI 会自动拍照，并在文本中补充图片标记。

---

### 4.3 TTS 播放链路

TTS 播放沿用实验 06 已验证的官方入口：

```bash
python3 voice_assistant.py tts-stream "中文文本"
```

内部链路为：

```text
voice_assistant.py tts-stream
  -> StreamingTtsPlayer
  -> SherpaTts
  -> Sherpa-ONNX Matcha-TTS
  -> Vocos
  -> PcmSpeakerStream
  -> plughw:2,0
```

播放侧使用项目配置：

```text
speaker_device       : plughw:2,0
playback_sample_rate : 44100
playback_channels    : 2
playback_mode        : stereo_dup
```

本实验重点关注：

```text
tts_return_code 是否为 0
underrun_count 是否为 0
abnormal 是否为空
```

---

## 5. 实验 08.1：CameraAdapter.capture -> Qwen -> TTS

### 5.1 实验目的

实验 08.1 不直接使用官方 `ask --force-photo`，而是显式调用：

```text
CameraAdapter.capture()
  -> 获取真实摄像头照片路径
  -> voice_assistant.py ask --image PHOTO --no-speak --no-play
  -> 解析 Qwen 回答
  -> voice_assistant.py tts-stream
```

这样可以先验证三段能力能否手动串联。

---

### 5.2 输出目录

```text
output/exp08_1_camera_qwen_tts_20260709_155723
```

---

### 5.3 运行结果

summary：

```text
out_dir           : output/exp08_1_camera_qwen_tts_20260709_155723
camera_return_code: 0
qwen_return_code  : 0
tts_return_code   : 0
photo_path        : /home/cat/图片/voice_20260709_155724.jpg
qwen_answer_chars : 31
underrun_count    : 0
```

最终结果：

```text
[RESULT] Experiment 08.1 PASSED_BY_COMMAND
[NOTE] Please confirm by listening whether the camera description was spoken.
```

照片格式：

```text
codec_name=mjpeg
width=1920
height=1080
pix_fmt=yuvj420p
```

Qwen 回答：

```text
一个穿着白大褂的人在实验室里，从高处俯视着下方的实验台和设备。
```

TTS 播放文本：

```text
下面播放摄像头画面理解结果：一个穿着白大褂的人在实验室里，从高处俯视着下方的实验台和设备。
```

异常检查：

```text
abnormal: 空
```

---

### 5.4 结果分析

实验 08.1 证明：

```text
1. CameraAdapter.capture() 可以继续正常调用摄像头拍照；
2. 拍摄图片是 1920×1080 JPEG；
3. Qwen3-VL 可以对真实摄像头图片生成有效中文描述；
4. Qwen 回答可以送入 tts-stream 进行中文语音播报；
5. 该链路没有出现异常日志；
6. 播放过程中没有出现 underrun。
```

因此 08.1 判定：**通过**。

---

## 6. 实验 08.2：官方 ask --force-photo -> Qwen -> TTS

### 6.1 实验目的

08.1 是手动调用 `CameraAdapter.capture()`，而 08.2 进一步验证官方入口：

```bash
python3 voice_assistant.py ask "请用一句中文简短描述摄像头拍到的画面。" \
  --force-photo \
  --no-speak \
  --no-play
```

目标是确认：

```text
voice_assistant.py ask
  -> --force-photo
  -> 自动调用 CameraAdapter.capture()
  -> 自动将图片路径传入 QwenRunner
  -> 输出图文理解回答
```

随后再将回答送入 `tts-stream` 播放。

---

### 6.2 输出目录

```text
output/exp08_2_force_photo_ask_tts_20260709_155930
```

---

### 6.3 运行结果

summary：

```text
out_dir          : output/exp08_2_force_photo_ask_tts_20260709_155930
qwen_return_code : 0
tts_return_code  : 0
photo_path       : /home/cat/图片/voice_20260709_155930.jpg
qwen_answer_chars: 34
underrun_count   : 0
```

最终结果：

```text
[RESULT] Experiment 08.2 PASSED_BY_COMMAND
[NOTE] Please confirm by listening whether the force-photo answer was spoken.
```

照片格式：

```text
codec_name=mjpeg
width=1920
height=1080
pix_fmt=yuvj420p
```

Qwen 回答：

```text
一个男人正俯身在充满未来感的白色电路板上，似乎在进行精密操作或检查。
```

TTS 播放文本：

```text
下面播放官方拍照问答结果：一个男人正俯身在充满未来感的白色电路板上，似乎在进行精密操作或检查。
```

异常检查：

```text
abnormal: 空
```

---

### 6.4 结果分析

实验 08.2 的意义比 08.1 更接近项目真实功能，因为它验证的是官方 ask 入口，而不是手动提前拍照。

该结果说明：

```text
1. ask --force-photo 可以自动触发 CameraAdapter.capture()；
2. 自动拍摄的照片路径能够被 CLI 正确传入 QwenRunner；
3. Qwen3-VL 对真实摄像头照片产生了与画面相关的描述；
4. TTS 可以正常播报该描述；
5. qwen_return_code=0，tts_return_code=0；
6. underrun_count=0；
7. abnormal 为空。
```

因此 08.2 判定：**通过**。

---

## 7. 实验 08.3：once 语音触发拍照问答

### 7.1 实验目的

08.3 进一步验证更接近真实助手使用方式的链路：

```text
用户语音输入
  -> voice_assistant.py once
  -> ASR 识别
  -> 意图判断
  -> 自动拍照
  -> Qwen3-VL 图文理解
  -> TTS 语音播报
```

本实验仍然不接 KWS 唤醒词，入口为：

```bash
python3 voice_assistant.py once --seconds 5
```

用户录音时说：

```text
看一下画面
```

---

## 8. 实验 08.3 第一次测试：ASR 误识别导致未触发拍照

### 8.1 输出目录

```text
output/exp08_3_once_voice_photo_qa_20260709_160244
```

---

### 8.2 运行结果

summary：

```text
out_dir          : output/exp08_3_once_voice_photo_qa_20260709_160244
once_return_code : 0
recognized_text  : 来来来
new_photo_count  : 0
new_photo_path   : 
qwen_answer_chars: 24
underrun_count   : 0
```

结果：

```text
[RESULT] Experiment 08.3 NEEDS_CHECK
```

ASR 识别文本：

```text
来来来
```

Qwen 回答：

```text
你好呀！😊 有什么我可以帮你的吗？（*^▽^*）
```

异常检查：

```text
abnormal: 空
```

---

### 8.3 问题分析

这一次不能判定为系统主链路失败，原因是：

```text
1. once_return_code=0，说明程序没有崩溃；
2. ASR 将语音识别成“来来来”；
3. “来来来”不包含“拍照 / 画面 / 摄像头 / 看一下”等视觉触发关键词；
4. 因此 IntentRouter 没有触发 force_photo；
5. new_photo_count=0 是合理结果；
6. Qwen 只是把“来来来”当成普通聊天文本处理。
```

因此第一次 08.3 结果应记录为：

```text
ASR 识别偏差导致拍照意图未触发。
```

它暴露出的不是摄像头、Qwen 或 TTS 问题，而是完整语音助手中实际存在的工程问题：

```text
ASR 识别质量会直接影响意图判断。
```

---

## 9. 实验 08.3 第二次测试：语音触发视觉问答成功

### 9.1 输出目录

```text
output/exp08_3_once_voice_photo_qa_20260709_160523
```

---

### 9.2 运行结果

summary：

```text
out_dir          : output/exp08_3_once_voice_photo_qa_20260709_160523
once_return_code : 0
recognized_text  : 看一下画面
new_photo_count  : 1
new_photo_path   : /home/cat/图片/voice_20260709_160531.jpg
qwen_answer_chars: 335
underrun_count   : 0
```

最终结果：

```text
[RESULT] Experiment 08.3 PASSED_BY_COMMAND
[NOTE] Please confirm by listening whether the voice-triggered photo answer was spoken.
```

照片格式：

```text
codec_name=mjpeg
width=1920
height=1080
pix_fmt=yuvj420p
```

ASR 识别文本：

```text
看一下画面
```

Qwen 回答：

```text
好的，这是对您提供的图片的分析。
这是一张从低角度拍摄的照片，视角似乎是从一个倒置的物体上向下看。整个场景呈现出一种未来感或高科技实验室的氛围。
- **主要人物**：照片中有一个穿着白色实验服的人，他/她正俯身在某个设备上进行操作。
- **环境与设备**：
- 地面和墙壁是白色的，上面有复杂的、类似电路板的图案。
- 画面下方可以看到一个带有圆形开口的装置，可能是某种传感器或仪器的一部分。
- 左侧有一个发出蓝绿色光的物体，看起来像是一台机器或显示器的边框。
- **视角**：由于拍摄角度是倒置的（即人物和设备在照片中是向上仰视），这可能意味着相机被安装在一个非常高的位置，或者整个场景本身是反向的。
综合来看，这张图片描绘了一个充满科技感的实验室或研究环境。
```

异常检查：

```text
abnormal: 空
```

---

### 9.3 结果分析

第二次 08.3 是本实验最关键的通过结果。

它证明完整链路已经成立：

```text
用户说“看一下画面”
  -> ASR 正确识别为“看一下画面”
  -> 意图判断命中视觉/拍照分支
  -> 自动调用 CameraAdapter.capture()
  -> 生成新照片 /home/cat/图片/voice_20260709_160531.jpg
  -> Qwen3-VL 对真实图片生成图文回答
  -> TTS 播放回答
  -> 未出现 underrun
```

关键证据包括：

```text
recognized_text  : 看一下画面
new_photo_count  : 1
new_photo_path   : /home/cat/图片/voice_20260709_160531.jpg
qwen_answer_chars: 335
underrun_count   : 0
abnormal         : 空
```

因此 08.3 判定：**通过**。

---

## 10. 实验 08 总体结果汇总

| 子实验 | 内容 | 状态 | 关键结果 |
|---|---|---|---|
| 08.1 | `CameraAdapter.capture()` -> Qwen -> TTS | 通过 | 摄像头图片被 Qwen 描述，TTS 播放，`underrun_count=0` |
| 08.2 | `ask --force-photo` -> Qwen -> TTS | 通过 | 官方 ask 入口可自动拍照并播报回答 |
| 08.3 第一次 | `once` 语音触发视觉问答 | 需复测 | ASR 识别为“来来来”，未触发拍照 |
| 08.3 第二次 | `once` 语音触发视觉问答 | 通过 | ASR 识别“看一下画面”，自动拍照，Qwen 回答，TTS 播放 |

---

## 11. 当前已经具备的能力

实验 08 完成后，项目已经具备如下能力：

```text
真实摄像头拍照
  -> 1920×1080 JPEG
  -> Qwen3-VL 图文理解
  -> 中文文本描述
  -> TTS 中文语音播报
```

并进一步具备：

```text
语音指令
  -> ASR
  -> 意图判断
  -> 自动拍照
  -> Qwen3-VL 图像理解
  -> TTS 语音回答
```

这意味着项目从实验 07 的普通语音问答：

```text
语音输入 -> ASR -> Qwen -> TTS -> 语音回答
```

推进到了实验 08 的多模态视觉问答：

```text
语音输入 -> ASR -> 意图判断 -> 摄像头 -> Qwen3-VL -> TTS -> 语音回答
```

---

## 12. 关键问题与定位结论

### 12.1 问题：ASR 误识别会导致视觉意图无法触发

第一次 08.3 的结果为：

```text
recognized_text  : 来来来
new_photo_count  : 0
```

这说明完整助手中存在实际工程问题：

```text
ASR 输出文本是意图判断的输入；
如果 ASR 把“看一下画面”识别成无关文本，IntentRouter 就无法触发拍照分支。
```

该问题不属于摄像头、Qwen、TTS 失败，而属于：

```text
ASR + 意图规则鲁棒性问题。
```

---

### 12.2 当前可接受处理方式

当前实验阶段可以接受的处理方式是：

```text
1. 说短句；
2. 靠近麦克风；
3. 使用更明确的触发词，例如“拍照”“看一下画面”；
4. 避免过长、模糊或口语化过强的指令。
```

第二次 08.3 使用：

```text
看一下画面
```

成功触发视觉问答，说明当前 IntentRouter 至少已经能够处理这类明确视觉意图。

---

### 12.3 后续可优化方向

为了提升完整助手体验，后续可以继续优化：

```text
1. 在 IntentRouter 中增加更多视觉触发关键词：
   看看、看一下、画面、摄像头、拍照、照片、前面、识别一下、描述一下。

2. 增加 ASR 容错映射：
   例如将“看一下话面”“看下画面”“看一下照片”等近似文本映射到视觉意图。

3. 对常用短指令做规则兜底：
   “拍照”直接触发 force_photo；
   “看一下画面”直接触发 force_photo；
   “描述一下”在视觉模式下触发 force_photo。

4. 记录 ASR 误识别样本：
   将失败样本纳入后续调试表，分析是否需要调节 asr_input_gain 或麦克风距离。
```

---

## 13. 当前保留的工程取舍

实验 08 当前仍然不接 KWS 唤醒词，原因是：

```text
1. 实验 08 目标是验证视觉问答能力，而不是唤醒词；
2. KWS 会引入新的不确定性；
3. 当前阶段应优先完成“语音触发视觉问答”的封口；
4. KWS 可以在实验 09 中单独验证。
```

当前推荐的项目展示链路为：

```text
python3 voice_assistant.py once --seconds 5
用户说：看一下画面
系统自动拍照并语音描述画面
```

这个链路已经足以展示项目的端侧多模态能力。

---

## 14. 当前可复用命令

### 14.1 运行 08.1：CameraAdapter -> Qwen -> TTS

```bash
cd /home/cat/ai/qwen3vl2b

EXP=output/exp08_1_camera_qwen_tts_$(date +%Y%m%d_%H%M%S)
./scripts/exp08_1_camera_qwen_tts.sh "$EXP"
```

查看结果：

```bash
OUT=$(ls -td output/exp08_1_camera_qwen_tts_* | head -1)

cat "$OUT/summary.txt"
cat "$OUT/photo_ffprobe.txt"
cat "$OUT/qwen_answer.txt"
cat "$OUT/abnormal.txt"
```

---

### 14.2 运行 08.2：ask --force-photo -> Qwen -> TTS

```bash
cd /home/cat/ai/qwen3vl2b

EXP=output/exp08_2_force_photo_ask_tts_$(date +%Y%m%d_%H%M%S)
./scripts/exp08_2_force_photo_ask_tts.sh "$EXP"
```

查看结果：

```bash
OUT=$(ls -td output/exp08_2_force_photo_ask_tts_* | head -1)

cat "$OUT/summary.txt"
cat "$OUT/photo_ffprobe.txt"
cat "$OUT/qwen_answer.txt"
cat "$OUT/abnormal.txt"
```

---

### 14.3 运行 08.3：once 语音触发视觉问答

```bash
cd /home/cat/ai/qwen3vl2b

EXP=output/exp08_3_once_voice_photo_qa_$(date +%Y%m%d_%H%M%S)
./scripts/exp08_3_once_voice_photo_qa.sh "$EXP" 5
```

录音开始后建议说：

```text
看一下画面
```

查看结果：

```bash
OUT=$(ls -td output/exp08_3_once_voice_photo_qa_* | head -1)

echo "========== summary =========="
cat "$OUT/summary.txt"

echo
cat "$OUT/photo_ffprobe.txt" 2>/dev/null || true

echo
cat "$OUT/recognized_text.txt"

echo
cat "$OUT/qwen_answer.txt"

echo
cat "$OUT/abnormal.txt"
```

---

## 15. 实验通过标准

实验 08 的通过标准为：

```text
08.1：
  camera_return_code = 0
  qwen_return_code   = 0
  tts_return_code    = 0
  qwen_answer_chars  > 0
  underrun_count     = 0
  abnormal           = 空

08.2：
  qwen_return_code   = 0
  tts_return_code    = 0
  qwen_answer_chars  > 0
  underrun_count     = 0
  abnormal           = 空

08.3：
  once_return_code   = 0
  recognized_text    命中视觉意图
  new_photo_count    > 0
  qwen_answer_chars  > 0
  underrun_count     = 0
  abnormal           = 空
```

本次实测均满足最终通过条件。

---

## 16. 对后续实验的建议

实验 08 已经封口。后续建议进入：

```text
实验 09：KWS 唤醒词 listen / listen-forever 完整助手流程
```

目标链路：

```text
唤醒词
  -> 录音
  -> ASR
  -> 意图判断
  -> 普通问答 / 摄像头拍照问答
  -> Qwen3-VL
  -> TTS 播放
```

实验 09 需要重点关注：

```text
1. KWS 模型资产是否齐全；
2. wake_keywords.txt 中唤醒词是否匹配；
3. listen / listen-forever 是否能持续监听；
4. 唤醒后是否能稳定进入 command 录音；
5. 唤醒词和普通语音命令之间是否存在误触发；
6. 长时间运行是否存在资源释放、音频设备占用、进程残留问题。
```

---

## 17. 实验 08 最终结论

实验 08 判定：**通过**。

本实验完成了 RK3588 端侧多模态智能语音助手的视觉问答链路验证：

```text
真实摄像头拍照
  -> Qwen3-VL 图文理解
  -> TTS 中文语音播报
```

并进一步完成了官方单轮入口中的语音触发视觉问答：

```text
用户说“看一下画面”
  -> ASR 识别
  -> 意图判断
  -> 自动拍照
  -> Qwen3-VL 分析图片
  -> 整段 TTS 播放
  -> plughw:2,0 输出
```

实验 08 的关键结论如下：

```text
1. 真实摄像头图片可以稳定采集为 1920×1080 JPEG；
2. CameraAdapter.capture() 与 Qwen3-VL 图文理解链路可以串联；
3. 官方 ask --force-photo 可以自动拍照并完成图文问答；
4. Qwen3-VL 的图文回答可以被 TTS 中文播报；
5. once 入口可以通过“看一下画面”触发自动拍照问答；
6. 成功样例中 new_photo_count=1，qwen_answer_chars=335；
7. 播放过程中 underrun_count=0；
8. abnormal 为空；
9. 第一次 08.3 的“来来来”结果说明 ASR 识别质量会影响意图触发，但不影响视觉链路通过判定。
```

最终项目能力从实验 07 的：

```text
语音输入 -> ASR -> Qwen -> TTS -> 语音回答
```

推进到实验 08 的：

```text
语音输入 -> ASR -> 意图判断 -> 摄像头拍照 -> Qwen3-VL 图像理解 -> TTS -> 语音回答
```

这标志着端侧多模态语音助手已经具备核心视觉问答能力。

---

# 实验 08 阶段性封口

```text
voice_assistant.py once
  -> record_command()
  -> transcribe_wav()
  -> IntentRouter 命中视觉意图
  -> CameraAdapter.capture()
  -> ask_qwen(image_path=photo)
  -> full-answer TTS playback
  -> plughw:2,0
```

实验 08 正式完成。
