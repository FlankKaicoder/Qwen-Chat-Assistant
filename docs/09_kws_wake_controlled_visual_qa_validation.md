# 实验 09：KWS 唤醒与受控式语音视觉问答完整链路验证

> 项目：RK3588 端侧多模态智能语音助手系统  
> 平台：LubanCat / RK3588  
> 仓库目录：`/home/cat/ai/qwen3vl2b`  
> 实验编号：09  
> 实验主题：KWS 唤醒词检测、实时唤醒、受控式语音触发拍照、Qwen3-VL 图文理解、TTS 播放完整链路验证  
> 实验状态：**受控式完整链路通过；官方 once/listen 一体化入口仍需优化**  
> 记录日期：2026-07-10

---

## 1. 实验背景

在实验 08 中，系统已经验证了：

```text
语音命令
  -> ASR
  -> 拍照意图判断
  -> CameraAdapter 自动拍照
  -> Qwen3-VL 图文理解
  -> TTS 播放
```

实验 08 的代表结果为：

```text
recognized_text  : 看一下画面
new_photo_count  : 1
new_photo_path   : /home/cat/图片/voice_20260709_160531.jpg
qwen_answer_chars: 335
underrun_count   : 0
```

但是实验 08 仍然没有接入唤醒词检测。也就是说，用户还不能通过“鲁班猫”唤醒系统，再进入语音视觉问答。

因此实验 09 的目标是在实验 08 的基础上继续向完整语音助手靠近：

```text
实时 KWS 唤醒
  -> 语音命令录音
  -> Sherpa-ONNX ASR
  -> 拍照意图判断
  -> 摄像头拍照
  -> Qwen3-VL 图文理解
  -> TTS 合成播放
```

本实验过程中并不是一次性成功，而是经历了 KWS 资产缺失、KWS 检测结果误判、录音增益干扰、脚本变量错误、摄像头拍照阻塞、Python timeout 无法杀掉子进程、官方 once/listen 录音窗口不稳定等多个问题。实验 09 的价值不仅在于最终链路跑通，更在于完整体现了端侧多模块系统的工程排查过程。

---

## 2. 实验目标

实验 09 主要回答以下问题：

```text
1. KWS 模型资产是否齐全；
2. wake_keywords.txt 是否可以被 Sherpa-ONNX KeywordSpotter 正确使用；
3. 文件级 KWS 检测是否能区分“鲁班猫”和负样本；
4. 实时 KWS wake 是否可以从麦克风检测到“鲁班猫”；
5. KWS 唤醒后是否可以进入命令录音；
6. 命令录音是否可以被 ASR 正确识别为拍照意图；
7. 拍照意图是否可以触发 CameraAdapter.capture()；
8. 摄像头拍照脚本是否存在阻塞风险；
9. Qwen3-VL 图文推理是否可以正常返回；
10. TTS 播放是否仍然保持 underrun_count=0；
11. 最终是否可以完成“鲁班猫 -> 拍照看画面 -> 语音回答”的主链路。
```

---

## 3. 实验前系统状态

实验 09 开始前，系统已有如下基础能力：

```text
实验 03：CameraAdapter.capture() 拍照链路通过
实验 04：Sherpa-ONNX 中文 ASR 离线识别通过
实验 05：Qwen3-VL RKNN/RKLLM 图文推理通过
实验 06：Matcha-TTS + Vocos + ALSA 播放通过
实验 07：普通语音问答闭环通过
实验 08：语音触发视觉问答通过
```

项目核心目录：

```text
/home/cat/ai/qwen3vl2b
```

主要入口：

```text
voice_assistant.py record
voice_assistant.py stt
voice_assistant.py wake
voice_assistant.py kws-file
voice_assistant.py ask
voice_assistant.py once
voice_assistant.py listen
voice_assistant.py listen-forever
```

音频配置：

```text
mic_device     : plughw:2,0
speaker_device : plughw:2,0
sample_rate    : 16000
channels       : 2
input_channel  : left
wake_input_gain: 8.0
asr_input_gain : 5.0
```

摄像头配置：

```text
camera device : /dev/video11
photo_dir     : /home/cat/图片
capture_script: /home/cat/ai/qwen3vl2b/scripts/capture-photo.sh
```

---

## 4. KWS 配置与模型资产

KWS 使用 Sherpa-ONNX keyword spotting 模型：

```text
models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20
```

配置项位于 `config/default.yaml`：

```text
models.kws.tokens          : models/.../tokens.txt
models.kws.encoder         : models/.../encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx
models.kws.decoder         : models/.../decoder-epoch-13-avg-2-chunk-16-left-64.onnx
models.kws.joiner          : models/.../joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx
models.kws.keywords_file   : config/wake_keywords.txt
models.kws.num_threads     : 2
models.kws.keywords_score  : 4.0
models.kws.keywords_threshold: 0.07
```

唤醒词文件 `config/wake_keywords.txt`：

```text
l ǔ b ān m āo @鲁班猫
p āi zh ào zh ù sh ǒu @拍照助手
```

---

## 5. 实验 09 总体流程

实验 09 实际被拆分为多个阶段：

| 阶段 | 实验名 | 目的 | 结果 |
|---|---|---|---|
| 09.0 | KWS 资产与初始化预检 | 检查模型文件、配置、import、VoiceAssistant 初始化 | 通过 |
| 09.1 | `kws-file` 初测 | 文件级 KWS 检测 | 初始误判，后续修正 |
| 09.1b | 正负样本对比 | 判断返回码是否代表检测成功 | 发现返回码不能代表检出 |
| 09.1c | 原始双声道录音 + 大范围扫参 | 避免 ASR 增益干扰，寻找 KWS 参数 | 脚本设计过重，中断 |
| 09.1d | 快速扫参 | 复用原始 WAV，少量组合扫参 | 通过 |
| 09.1e | 官方 `kws-file` 复测 | 验证官方入口对 raw stereo WAV 可用 | 通过 |
| 09.2 | 实时 `wake --mode kws` | 验证麦克风实时唤醒 | 通过 |
| 09.4 | 官方 `listen` 视觉链路 | 验证唤醒后直接视觉问答 | 卡在拍照阶段 |
| 09.4a | split wake -> once | 分离 KWS 与 once，定位卡点 | 卡在拍照阶段 |
| 09.4b | 摄像头卡死诊断 | 排查 capture-photo / v4l2 / CameraAdapter | 定位偶发阻塞 |
| 09.4c | 拍照参数与 timeout 修复 | 降低采集参数，初步加 timeout | 部分有效，但仍不充分 |
| 09.4d | once live debug | 观察 once 真实输出 | 发现录音窗口不稳定 |
| 09.4e | 拍照命令 ASR 校准 | 单独保存录音验证 ASR | 通过 |
| 09.4f | 受控 record -> stt -> ask | 绕开 once 录音窗口，验证视觉链路 | 初次卡住，修复后通过 |
| 09.5 | KWS + 受控视觉问答 | 最终主链路验证 | 通过 |

---

## 6. 09.0：KWS 资产与初始化预检

### 6.1 初始问题

实验 09.0 最初检查发现 KWS 文件缺失：

```text
missing_kws_config_or_files: 4
[RESULT] Experiment 09.0 PRECHECK BLOCKED_OR_NEEDS_FIX
```

缺失的文件包括：

```text
tokens.txt
encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx
decoder-epoch-13-avg-2-chunk-16-left-64.onnx
joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx
```

### 6.2 解决方法

在 Windows 下载 KWS 模型包：

```text
sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20.tar.bz2
```

通过 `scp` 传到 RK3588 板端：

```bash
scp sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20.tar.bz2 \
  cat@10.198.26.64:/home/cat/ai/kws_assets_inbox/
```

板端解压并复制到项目模型目录：

```bash
cd /home/cat/ai/kws_assets_inbox
tar -xf sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20.tar.bz2

cd /home/cat/ai/qwen3vl2b
mkdir -p models
cp -av /home/cat/ai/kws_assets_inbox/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20 models/
```

### 6.3 预检通过结果

补齐模型后重新运行 09.0：

```text
missing_kws_config_or_files: 0
import_fail_count          : 0
compile_fail_count         : 0
init_return_code           : 0
[RESULT] Experiment 09.0 PRECHECK PASSED
```

结论：

```text
KWS 模型资产已补齐；
wake_keywords.txt 存在；
listen / listen-forever CLI 入口存在；
wake.py / orchestrator.py 可导入；
VoiceAssistant 可初始化。
```

---

## 7. 09.1：文件级 KWS 检测初测与误判修正

### 7.1 初次文件级 KWS 检测

最初使用 `voice_assistant.py record` 录制一段“鲁班猫”，然后执行：

```bash
python voice_assistant.py kws-file wake_record.wav
```

结果为：

```text
record_return_code: 0
kws_return_code   : 0
kws stdout        : 空
kws stderr        : 空
detected_key_text : 空
[RESULT] Experiment 09.1 PASSED_BY_COMMAND
```

脚本一开始把 `kws_return_code=0` 误判为 KWS 通过。

### 7.2 源码检查后修正判断

检查 `voice_assistant/cli.py`：

```python
elif args.cmd == "kws-file":
    print(assistant.detect_wake_wav(args.wav))
```

检查 `voice_assistant/wake.py`：

```python
def detect_wav(self, wav_path):
    ...
    if keyword:
        return keyword
    ...
    return ""
```

因此：

```text
kws_return_code=0 只能说明命令正常退出；
stdout 为空才是真实检测结果；
stdout 为空表示没有检测到关键词。
```

结论修正为：

```text
09.1 不是 KWS 检测通过；
只是 kws-file 命令没有崩溃。
```

---

## 8. 09.1b：正负样本对比

为了验证 `kws-file` 返回码是否能代表检出，录制了两段：

```text
正样本：鲁班猫
负样本：你好你好
```

结果：

```text
summary_positive_lubancat_record_rc: 0
summary_positive_lubancat_kws_rc   : 0
summary_positive_lubancat_stdout   : 空
summary_negative_hello_record_rc   : 0
summary_negative_hello_kws_rc      : 0
summary_negative_hello_stdout      : 空
```

结论：

```text
正负样本 stdout 都为空；
返回码都为 0；
因此返回码不能代表关键词是否检出。
```

进一步分析发现，初次录音使用了 `voice_assistant.py record`，它会对 ASR 输入做增益处理：

```text
asr_input_gain: 5.0
```

而 KWS 读 WAV 时又使用：

```text
wake_input_gain: 8.0
```

这会导致输入被二次放大，可能削波失真，不适合直接用于 KWS 文件检测。

---

## 9. 09.1c：原始双声道录音与大范围扫参

### 9.1 设计目标

为了避免 ASR 增益干扰，改成直接使用 `arecord` 录制原始 stereo WAV：

```text
arecord -D plughw:2,0 -f S16_LE -r 16000 -c 2
```

然后扫描：

```text
channel: left / right / mix
gain: 1 / 2 / 4 / 8
score: 1.5 / 2.0 / 4.0
threshold: 0.005 / 0.01 / 0.03 / 0.05 / 0.07 / 0.1 / 0.2
```

### 9.2 脚本问题

该脚本出现两个工程问题：

#### 问题 1：误用了 Bash 特殊变量 `SECONDS`

脚本里使用变量：

```bash
SECONDS="${2:-4}"
```

但 `SECONDS` 是 Bash 内置特殊变量，会自动记录脚本运行秒数。因此实际录音长度从期望的 4 秒变成了 6 秒、18 秒等异常长度。

#### 问题 2：扫参组合过多

组合数量为：

```text
channel 3 种 × gain 4 种 × score 3 种 × threshold 7 种 × 正负样本 2 次
= 504 次检测
```

每次还重新创建 `KeywordSpotter`，在 RK3588 上很慢，看起来像卡住，因此中断该实验。

结论：

```text
09.1c 暴露了脚本设计问题；
不能把过重的扫参脚本直接放到端侧板子上长时间跑。
```

---

## 10. 09.1d：快速 KWS 扫参验证

### 10.1 优化思路

09.1d 复用了 09.1c 已经录好的原始 stereo WAV，仅扫描较小范围：

```text
channels: left / right
gains: 1.0 / 2.0 / 4.0 / 8.0
thresholds: 0.005 / 0.01 / 0.03 / 0.05 / 0.07 / 0.1
score: 4.0
```

### 10.2 结果

```text
sweep_return_code: 0
positive_mean    : -44.2 dB
positive_max     : -19.6 dB
negative_mean    : -52.8 dB
negative_max     : -24.9 dB
best_count       : 48
[RESULT] Experiment 09.1d PASSED_FOUND_KWS_SETTING
```

所有候选组合中，正样本均检测到：

```text
keyword=鲁班猫
```

负样本均为空。

关键结论：

```text
KWS 模型本身是可用的；
正样本“鲁班猫”可以检出；
负样本“你好你好”不会误检；
当前配置 left + gain=8.0 + score=4.0 + threshold=0.07 也属于可用组合。
```

---

## 11. 09.1e：官方 kws-file raw stereo WAV 复测

使用 09.1c 生成的原始 stereo WAV，通过官方入口复测：

```bash
python voice_assistant.py kws-file positive_lubancat.raw_stereo.wav
python voice_assistant.py kws-file negative_hello.raw_stereo.wav
```

结果：

```text
positive_return_code: 0
negative_return_code: 0
positive_keyword    : 鲁班猫
negative_keyword    :
[RESULT] Experiment 09.1e PASSED_OFFICIAL_KWS_FILE
```

结论：

```text
官方 kws-file 入口可用；
原始 stereo WAV 输入可以正确检测“鲁班猫”；
负样本不会误检。
```

---

## 12. 09.2：实时 KWS 唤醒验证

执行：

```bash
python voice_assistant.py wake --mode kws --timeout 20
```

用户说：

```text
鲁班猫
```

结果：

```text
wake_return_code: 0
wake_text       : 鲁班猫
[RESULT] Experiment 09.2 PASSED_REALTIME_KWS_WAKE
```

结论：

```text
实时麦克风 KWS 唤醒通过；
Sherpa-ONNX KeywordSpotter 可以在板端从 plughw:2,0 实时检测“鲁班猫”。
```

---

## 13. 09.4：官方 listen 视觉问答尝试

### 13.1 实验目标

尝试直接运行官方入口：

```bash
python voice_assistant.py listen --wake-mode kws --wake-timeout 25 --seconds 5
```

目标：

```text
鲁班猫
  -> 唤醒成功
看一下画面
  -> ASR
  -> 自动拍照
  -> Qwen3-VL
  -> TTS
```

### 13.2 现象

终端看起来“卡住”，但查看输出文件发现：

```text
wake=鲁班猫
识别文本：看一下画面
检测到拍照意图，正在拍照...
```

说明：

```text
KWS 成功；
ASR 成功；
拍照意图命中；
程序卡在拍照阶段。
```

结论：

```text
09.4 并不是 KWS 或 ASR 失败；
真正卡点在 CameraAdapter.capture() / capture-photo.sh / V4L2 拍照链路。
```

---

## 14. 09.4a：split wake -> once 定位

为了确认是否是 `listen` 集成问题，改成两段：

```text
python voice_assistant.py wake --mode kws
python voice_assistant.py once --seconds 5
```

结果：

```text
wake_return_code : 0
wake_text        : 鲁班猫
once_return_code : 124
recognized_text  : 看一下画面
new_photo_count  : 0
qwen_answer_chars: 0
underrun_count   : 0
[RESULT] Experiment 09.4a FAILED_OR_NEEDS_CHECK
```

once stdout：

```text
识别文本：看一下画面
检测到拍照意图，正在拍照...
```

结论：

```text
KWS、ASR、意图判断均已成功；
程序仍然卡在拍照阶段。
```

---

## 15. 09.4b：摄像头拍照卡死诊断

### 15.1 诊断内容

09.4b 分别测试：

```text
1. scripts/capture-photo.sh 直接调用；
2. v4l2-ctl 1280x720 直接采集；
3. CameraAdapter.capture()；
4. dmesg 摄像头驱动日志。
```

### 15.2 结果

```text
capture_photo_return_code: 124
v4l2_direct_return_code  : 0
raw_1280x720_ok          : 1
camera_adapter_return_code: 0
camera_adapter_ok        : 1
[RESULT] Experiment 09.4b CAMERA_CAPTURE_TIMEOUT
```

具体含义：

```text
scripts/capture-photo.sh 直接调用时出现 45 秒超时；
底层 v4l2-ctl 1280x720 直接采集成功；
CameraAdapter.capture() 后续又成功生成照片；
dmesg 中没有明显 fatal error / DMA 错误 / reset。
```

结论：

```text
摄像头设备本身不是完全不可用；
问题是拍照脚本在某些条件下存在偶发阻塞；
需要降低采集参数，并给 CameraAdapter 增加可靠的超时保护。
```

---

## 16. 09.4c：拍照参数调整与初步 timeout 修复

### 16.1 降低 capture-photo.sh 参数

原始参数：

```text
width="1920"
height="1080"
skip="30"
```

修改为：

```text
width="1280"
height="720"
skip="5"
```

原因：

```text
09.4b 中 v4l2-ctl 1280x720 直接采集稳定成功；
当前项目演示和 Qwen 图像理解不强依赖 1920x1080；
降低分辨率和跳帧数量可以减少 V4L2 拍照阻塞风险。
```

### 16.2 初步给 CameraAdapter 加 timeout

最初希望把：

```python
proc = subprocess.run(cmd, check=True, text=True, capture_output=True)
```

改为：

```python
proc = subprocess.run(
    cmd,
    check=True,
    text=True,
    capture_output=True,
    timeout=self.capture_timeout,
)
```

但第一次自动 patch 没有真正把 `timeout=self.capture_timeout` 加入 `subprocess.run()`，后续检查时发现需要重新 patch。

### 16.3 单独拍照验证

修改后单独验证：

```text
capture_return_code       : 0
camera_adapter_return_code: 0
image_path                : /home/cat/图片/voice_20260709_235917.jpg
codec_name=mjpeg
width=1280
height=720
pix_fmt=yuvj420p
```

结论：

```text
降低拍照参数后，单独 capture-photo.sh 和 CameraAdapter.capture() 均可成功；
但这还不能完全说明 ask/once 中不会再卡住。
```

---

## 17. 09.4d：once live debug 与录音窗口问题

将 once 的 stdout/stderr 实时显示，避免“终端无输出就误判卡住”。

### 17.1 第一次现象

用户实际说：

```text
看一下画面
```

程序识别为：

```text
recognized_text: 对
```

结果：

```text
once_return_code : 0
new_photo_count  : 0
qwen_answer_chars: 64
underrun_count   : 0
[RESULT] Experiment 09.4d FAILED_OR_NEEDS_CHECK
```

### 17.2 第二次现象

用户实际说：

```text
拍照，看一下画面
```

程序识别为：

```text
recognized_text: 啊
```

结果：

```text
once_return_code : 0
new_photo_count  : 0
qwen_answer_chars: 23
underrun_count   : 0
[RESULT] Experiment 09.4d FAILED_OR_NEEDS_CHECK
```

结论：

```text
once 入口本身可以正常返回；
但 once 的录音交互窗口不稳定；
用户容易在真正开始录音前后说话，导致只录到“对”“啊”等片段；
这不是 ASR 模型不能识别拍照命令，而是 once 入口缺少清晰提示、倒计时、调试 WAV 保存。
```

---

## 18. 09.4e：拍照命令 ASR 校准

为了验证 ASR 是否真的能识别拍照命令，使用 `record --out` 保存 WAV，再单独 STT。

测试三句话：

```text
看一下画面
拍照
拍照，看一下画面
```

结果：

```text
case: look_screen
phrase: 看一下画面
recognized: 看一下画面
mean_volume: -12.9 dB
max_volume: 0.0 dB

case: take_photo
phrase: 拍照
recognized: 拍照
mean_volume: -19.3 dB
max_volume: 0.0 dB

case: photo_screen
phrase: 拍照，看一下画面
recognized: 拍照看一下画面
mean_volume: -17.1 dB
max_volume: 0.0 dB
```

结论：

```text
ASR 模型本身可以正确识别拍照命令；
once 中识别成“对”“啊”是录音时机/录音片段问题；
“拍照，看一下画面”是最稳命令，因为同时包含“拍照”和“画面”。
```

注意：

```text
max_volume 多次达到 0.0 dB；
说明峰值顶满，后续应稍微远离麦克风，避免削波。
```

---

## 19. 09.4f：受控 record -> STT -> ask --force-photo

### 19.1 设计目的

为了绕开 once 的录音窗口问题，将完整链路拆成受控步骤：

```text
record --out command.wav
  -> stt command.wav
  -> 判断拍照意图
  -> ask --force-photo
  -> CameraAdapter 拍照
  -> Qwen3-VL
  -> TTS
```

### 19.2 第一次结果：仍然卡在 ask --force-photo

第一次 09.4f 结果：

```text
record_return_code: 0
stt_return_code   : 0
recognized_text   : 拍照看一下画面
photo_intent      : 1
ask_return_code   : 124
new_photo_count   : 0
qwen_answer_chars : 15
[RESULT] Experiment 09.4f FAILED_OR_NEEDS_CHECK
```

stdout 停在：

```text
检测到拍照意图，正在拍照...
```

这说明：

```text
record 成功；
ASR 成功；
意图判断成功；
真正卡点仍在 ask --force-photo 调用 CameraAdapter.capture() 时。
```

### 19.3 根因进一步定位

虽然 `CameraAdapter.capture()` 中已经尝试加入：

```python
timeout=self.capture_timeout
```

但使用 `subprocess.run(... timeout=35, capture_output=True)` 时，如果 `capture-photo.sh` 内部启动了 `v4l2-ctl` 等子进程，超时可能只杀掉 shell 脚本本身，子进程仍然存活并占用管道或设备，导致 Python 进程继续等待。

因此需要进程组级 timeout。

---

## 20. 09.4g：CameraAdapter 进程组级 timeout 修复

### 20.1 修复目标

重写 `voice_assistant/camera.py` 中拍照脚本执行方式：

```text
subprocess.run
  -> subprocess.Popen
  -> start_new_session=True
  -> communicate(timeout=...)
  -> 超时时 os.killpg(proc.pid, SIGKILL)
```

这样可以保证：

```text
capture-photo.sh 超时时，不仅杀 shell 脚本；
还会杀掉它拉起的 v4l2-ctl / ffmpeg 等子进程；
避免摄像头设备或 stdout/stderr 管道被子进程长期占用。
```

### 20.2 修复后的 CameraAdapter 关键逻辑

```python
proc = subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    start_new_session=True,
)

try:
    stdout, stderr = proc.communicate(timeout=self.capture_timeout)
except subprocess.TimeoutExpired as exc:
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass

    stdout, stderr = proc.communicate()

    raise RuntimeError(
        f"capture script timed out after {self.capture_timeout}s\n"
        f"cmd: {' '.join(cmd)}\n"
        f"stdout:\n{stdout}\n"
        f"stderr:\n{stderr}"
    ) from exc
```

### 20.3 修复意义

这个修复不是为了让每次拍照都一定成功，而是为了做到：

```text
成功时正常返回图片；
失败或阻塞时明确报错；
不会让完整语音助手在拍照阶段无限等待；
不会遗留 capture-photo / v4l2-ctl / ffmpeg 子进程。
```

这是多进程外设调用中非常关键的工程保护。

---

## 21. 09.4f after pg_timeout：受控视觉问答通过

完成进程组级 timeout 修复后，重新运行 09.4f。

结果：

```text
record_return_code: 0
stt_return_code   : 0
ask_return_code   : 0
recognized_text   : 拍照看一下画面
photo_intent      : 1
mean_volume       : -19.0 dB
max_volume        : 0.0 dB
new_photo_count   : 1
new_photo_path    : /home/cat/图片/voice_20260710_002152.jpg
qwen_answer_chars : 555
underrun_count    : 0
[RESULT] Experiment 09.4f PASSED_CONTROLLED_VOICE_PHOTO_QA
```

照片信息：

```text
codec_name=mjpeg
width=1280
height=720
pix_fmt=yuvj420p
```

Qwen3-VL 成功描述了真实办公室画面，包括人物、显示器、鼠标、办公环境等。

结论：

```text
受控版语音视觉问答完整链路通过；
进程组级 timeout 修复后，ask --force-photo 不再卡死；
CameraAdapter 可以稳定返回 1280x720 JPEG；
Qwen3-VL 和 TTS 均正常。
```

---

## 22. 09.5：KWS + 受控式语音视觉问答最终验证

### 22.1 实验设计

09.5 将已经验证通过的模块串起来：

```text
实时 KWS wake
  -> 用户说“鲁班猫”
  -> wake 返回“鲁班猫”
  -> 受控 record 保存 command.wav
  -> 用户说“拍照，看一下画面”
  -> STT 识别
  -> 拍照意图判断
  -> ask --force-photo
  -> CameraAdapter.capture()
  -> Qwen3-VL
  -> TTS
```

### 22.2 最终结果

```text
wake_return_code  : 0
wake_text         : 鲁班猫
record_return_code: 0
stt_return_code   : 0
ask_return_code   : 0
recognized_text   : 拍照看一下画面
photo_intent      : 1
mean_volume       : -20.9 dB
max_volume        : -0.0 dB
new_photo_count   : 1
new_photo_path    : /home/cat/图片/voice_20260710_003137.jpg
qwen_answer_chars : 520
underrun_count    : 0
[RESULT] Experiment 09.5 PASSED_KWS_CONTROLLED_VOICE_PHOTO_QA
```

照片信息：

```text
codec_name=mjpeg
width=1280
height=720
pix_fmt=yuvj420p
```

运行结束后检查残留进程：

```text
process after run: 空
```

说明没有残留：

```text
voice_assistant.py
capture-photo.sh
v4l2-ctl
ffmpeg
arecord
aplay
demo
imgenc
```

结论：

```text
KWS 唤醒 + 受控式语音视觉问答完整链路通过。
```

---

## 23. 本实验中的关键问题与排查思路

### 23.1 问题一：KWS 资产缺失

现象：

```text
missing_kws_config_or_files: 4
```

排查：

```text
检查 config/default.yaml 中 KWS 路径；
检查 models 目录；
确认 tokens / encoder / decoder / joiner 缺失。
```

解决：

```text
下载 sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20；
复制到 models 目录；
重新运行 09.0 预检。
```

结论：

```text
09.0 通过，KWS 初始化条件成立。
```

---

### 23.2 问题二：误把 return_code=0 当成 KWS 检出

现象：

```text
kws_return_code=0
stdout 为空
```

排查：

```text
查看 cli.py 和 wake.py；
确认 detect_wav() 未检出时返回空字符串；
print("") 仍然返回码为 0。
```

解决：

```text
判断 KWS 检出必须看 stdout 是否为“鲁班猫”；
不能只看 return_code。
```

结论：

```text
返回码表示命令执行成功，不表示关键词检测成功。
```

---

### 23.3 问题三：ASR 增益处理后的 WAV 不适合 KWS 文件检测

现象：

```text
voice_assistant.py record 生成的 command.wav 用 kws-file 检不出；
原始 stereo WAV 可检出。
```

原因：

```text
record 使用 asr_input_gain=5.0；
kws-file 读取时又使用 wake_input_gain=8.0；
可能导致二次放大和削波失真。
```

解决：

```text
KWS 文件级验证使用原始 stereo WAV；
ASR 文件验证才使用 record 生成的 mono/gain WAV。
```

---

### 23.4 问题四：Bash 特殊变量 SECONDS 造成录音时长异常

现象：

```text
期望录 4 秒，实际录成 6 秒、18 秒。
```

原因：

```text
SECONDS 是 Bash 内置特殊变量，会自动增长。
```

解决：

```text
脚本中不要使用 SECONDS 作为普通变量；
改成 REC_SECONDS / CMD_SECONDS / WAKE_TIMEOUT 等明确名称。
```

---

### 23.5 问题五：扫参组合过多导致端侧看似卡死

现象：

```text
09.1c 扫参长时间无响应。
```

原因：

```text
组合数量 504 次；
每次重新创建 KeywordSpotter；
RK3588 上执行过慢。
```

解决：

```text
缩小搜索空间；
复用已有 WAV；
增加进度输出；
外层加 timeout。
```

---

### 23.6 问题六：官方 listen/once 看似卡住，实则 stdout 被重定向

现象：

```text
运行 09.4 后终端停在 run listen，看起来无反应。
```

原因：

```text
脚本将 listen stdout/stderr 重定向到文件；
终端不会实时显示内部进度。
```

解决：

```text
查看 listen_stdout.txt / listen_stderr.txt；
后续使用 live debug 版本，通过 tee 实时显示。
```

---

### 23.7 问题七：拍照脚本偶发阻塞

现象：

```text
输出停在：检测到拍照意图，正在拍照...
```

排查步骤：

```text
1. 直接运行 capture-photo.sh；
2. 直接运行 v4l2-ctl 1280x720；
3. 单独调用 CameraAdapter.capture()；
4. 查看 dmesg；
5. 检查残留进程。
```

结果：

```text
capture-photo.sh 直接调用可能 timeout；
v4l2-ctl 1280x720 直接采集成功；
CameraAdapter 某些情况下成功；
dmesg 无 fatal error。
```

结论：

```text
不是摄像头彻底不可用；
是拍照脚本链路存在偶发阻塞风险。
```

---

### 23.8 问题八：普通 Python timeout 不能可靠杀掉子进程

现象：

```text
CameraAdapter 中 subprocess.run(timeout=35) 后，ask --force-photo 仍可能被外层 timeout 180s 杀掉。
```

原因推测：

```text
subprocess.run 启动的是 capture-photo.sh；
capture-photo.sh 内部又启动 v4l2-ctl / ffmpeg；
超时杀掉 shell 后，子进程可能仍然存在；
子进程继续占用管道或设备，导致 Python 等待。
```

解决：

```text
使用 Popen(start_new_session=True) 创建独立进程组；
超时时使用 os.killpg(proc.pid, SIGKILL) 杀掉整个进程组。
```

---

### 23.9 问题九：once 录音交互窗口不稳定

现象：

```text
用户说“看一下画面”，once 识别成“对”；
用户说“拍照，看一下画面”，once 识别成“啊”。
```

对比：

```text
record --out 单独录制时，ASR 可以正确识别所有拍照命令。
```

结论：

```text
ASR 模型本身没有问题；
问题在 once 入口缺少明确录音提示、倒计时、调试 WAV 保存；
用户容易在真正录音窗口之外说话。
```

后续优化方向：

```text
1. once 录音前打印更明确提示；
2. 录音前延迟 0.5~1 秒；
3. 增加提示音 beep；
4. 保留 command_debug.wav；
5. 引入 VAD 自动端点检测。
```

---

## 24. 最终稳定版本的工程修改

### 24.1 capture-photo.sh 参数调整

最终采用：

```bash
device="/dev/video11"
width="1280"
height="720"
pixfmt="NV12"
skip="5"
```

原因：

```text
1280x720 已能满足 Qwen3-VL 图文理解；
相比 1920x1080 + skip=30，采集耗时和阻塞风险更低；
实验 09.5 输出图片 confirmed 为 1280x720 JPEG。
```

### 24.2 CameraAdapter 进程组级 timeout

最终 `camera.py` 的关键能力：

```text
Popen(start_new_session=True)
communicate(timeout=self.capture_timeout)
os.killpg(proc.pid, SIGKILL)
清晰记录 stdout/stderr
```

该修改让系统具备：

```text
摄像头拍照成功时正常返回；
拍照脚本异常时不会无限卡住；
失败时能给出具体 stdout/stderr；
不会残留 v4l2-ctl / ffmpeg 子进程。
```

---

## 25. 当前系统能力状态

实验 09 结束后，系统能力可以总结为：

```text
KWS 模型资产：已补齐
KWS 文件级检测：通过
KWS 实时唤醒：通过
ASR 拍照命令识别：通过
CameraAdapter 拍照：通过，已加进程组级 timeout
Qwen3-VL 图文理解：通过
TTS 播放：通过，underrun_count=0
受控式 KWS + 视觉问答完整链路：通过
官方 once/listen 一体化链路：仍需优化录音交互窗口
```

最终通过链路：

```text
鲁班猫
  -> wake_text=鲁班猫
  -> record command.wav
拍照，看一下画面
  -> recognized_text=拍照看一下画面
  -> photo_intent=1
  -> CameraAdapter.capture()
  -> /home/cat/图片/voice_20260710_003137.jpg
  -> Qwen3-VL 回答 520 字
  -> TTS 播放
  -> underrun_count=0
```

---

## 26. 实验 09 最终结论

实验 09 最终结论如下：

```text
实验 09 成功验证了 RK3588 端侧语音助手的 KWS 唤醒能力，以及 KWS 唤醒后进入受控式语音视觉问答的完整主链路。

在实验过程中，系统经历了 KWS 模型资产缺失、KWS 检测返回值误判、录音增益干扰、扫参脚本过重、摄像头拍照偶发阻塞、Python timeout 子进程清理不彻底、once/listen 录音窗口不稳定等问题。

通过逐层拆分验证，最终将问题收敛到 CameraAdapter 拍照子进程管理和 once/listen 录音交互设计，并完成了 CameraAdapter 的进程组级 timeout 修复。

最终 09.5 成功跑通：KWS wake -> 受控 record -> STT -> 拍照意图 -> CameraAdapter -> Qwen3-VL -> TTS，全链路 return_code=0，生成 1280x720 摄像头照片，Qwen3-VL 返回有效图文描述，TTS 播放无 underrun。
```

---

## 27. 后续优化建议

### 27.1 优先优化 once/listen 录音窗口

当前官方 `once/listen` 的问题不是核心模块能力不足，而是用户交互窗口不稳定。建议：

```text
1. 录音开始前打印明确提示；
2. 增加 0.5~1 秒准备延迟；
3. 增加 beep 提示音；
4. 每次 once 保存 command_debug.wav；
5. 输出识别文本、音量、录音文件路径；
6. 可以加入 VAD，自动判断用户说完再停止录音。
```

### 27.2 将 09.5 受控链路封装成正式 CLI

可以新增一个入口：

```bash
python voice_assistant.py listen-controlled
```

内部流程参考 09.5：

```text
wake
  -> controlled record --out
  -> stt
  -> intent
  -> ask/force-photo
```

这样既保留调试可观测性，又能形成更稳定的演示入口。

### 27.3 进一步提升摄像头链路稳定性

建议继续优化：

```text
1. capture-photo.sh 内部也加 timeout；
2. 采集失败自动 retry 1~2 次；
3. 保存 capture stdout/stderr 到 temp_dir；
4. 发生 V4L2 timeout 时自动 fuser 检查；
5. 未来可以改为常驻摄像头采集进程，避免每次重新打开 /dev/video11。
```

### 27.4 音频输入优化

目前多次出现：

```text
max_volume: 0.0 dB
```

说明峰值顶满，建议：

```text
1. 用户离麦克风稍远；
2. 适当降低 asr_input_gain；
3. 记录不同 gain 下 ASR 准确率；
4. 对 KWS 和 ASR 使用不同录音处理路径。
```

---

## 28. 简历与面试可提炼点

实验 09 可以在简历或面试中体现以下能力：

```text
1. 端侧 KWS 唤醒模型部署与配置能力；
2. Sherpa-ONNX KeywordSpotter 在 RK3588 上的实际验证；
3. 多模块链路拆分验证能力：KWS / ASR / Camera / Qwen / TTS；
4. 复杂系统问题定位能力：从“整机卡住”定位到 CameraAdapter 子进程管理；
5. Linux 多进程与外设调用经验：Popen、进程组、killpg、timeout；
6. V4L2 摄像头采集参数调优：分辨率、skip、NV12、JPEG 转换；
7. 语音助手工程化经验：录音窗口、调试 WAV、误识别分析、残留进程清理；
8. 端侧多模态闭环能力：唤醒 -> 语音 -> 视觉 -> LLM/VLM -> 语音输出。
```

可写成简历描述：

```text
实现 RK3588 端侧多模态语音助手唤醒与视觉问答链路，集成 Sherpa-ONNX KWS/ASR、V4L2 摄像头采集、Qwen3-VL RKNN/RKLLM 图文推理和 Matcha-TTS/Vocos 语音播报。通过分阶段实验验证 KWS 文件级与实时唤醒能力，定位并修复摄像头拍照脚本偶发阻塞问题，为 CameraAdapter 增加进程组级 timeout 与子进程清理机制，最终跑通“鲁班猫”唤醒后语音触发拍照、图文理解和语音播报的完整受控链路，生成 1280×720 实时照片，Qwen3-VL 返回有效图像描述，播放侧 underrun_count=0。
```

---

## 29. 实验 09 归档日志路径

关键输出目录：

```text
09.0 预检通过：
output/exp09_0_kws_listen_precheck_after_kws_copy_20260709_165342

09.1d KWS 快速扫参通过：
output/exp09_1d_kws_fast_sweep_existing_wav_20260709_233508

09.1e 官方 kws-file 通过：
output/exp09_1e_official_kws_file_raw_verify_20260709_233907

09.2 实时 KWS wake 通过：
output/exp09_2_realtime_wake_kws_20260709_234037

09.4b 摄像头卡住诊断：
output/exp09_4b_camera_hang_diagnose_20260709_235609

09.4f 受控视觉问答通过：
output/exp09_4f_controlled_record_stt_photo_qa_after_pg_timeout_20260710_002140

09.5 KWS + 受控视觉问答最终通过：
output/exp09_5_kws_controlled_voice_photo_qa_20260710_003109
```

最终照片：

```text
/home/cat/图片/voice_20260710_003137.jpg
```

最终图片格式：

```text
codec_name=mjpeg
width=1280
height=720
pix_fmt=yuvj420p
```

---

## 30. 最终状态一句话总结

```text
实验 09 已经完成 KWS 唤醒到受控式语音视觉问答的完整链路验证；系统具备“鲁班猫”唤醒、语音触发拍照、Qwen3-VL 图文理解和 TTS 播放能力。当前稳定入口为受控式链路，官方 once/listen 仍需继续优化录音交互窗口。
```
