# 实验 06：Sherpa-ONNX Matcha-TTS 中文语音合成与播放链路验证

> 项目：RK3588 端侧多模态智能语音助手系统  
> 平台：LubanCat / RK3588  
> 仓库目录：`/home/cat/ai/qwen3vl2b`  
> 实验编号：06  
> 实验主题：TTS 模型资产补齐、Sherpa-ONNX Matcha-TTS 最小合成、ALSA 播放、项目 `tts-stream` 入口验证、Qwen 回答语音播报验证  
> 实验状态：**通过**  
> 记录日期：2026-07-09

---

## 1. 实验背景

前置实验已经完成：

```text
实验 01-02：音频硬件与项目录音链路验证
实验 03：摄像头拍照链路验证
实验 04：Sherpa-ONNX 离线中文 ASR 链路验证
实验 05：Qwen3-VL 图文推理与 ASR -> Qwen 半闭环验证
```

到实验 05 结束时，系统已经具备：

```text
麦克风录音
  -> Sherpa-ONNX 中文 ASR
  -> Qwen3-VL 本地图文推理
  -> 文本回答
```

但是完整语音助手还缺少最后一段输出能力：

```text
Qwen 文本回答
  -> TTS 中文语音合成
  -> 板端喇叭 / 耳机播放
```

因此实验 06 的目标不是直接运行完整 `once/listen`，而是单独验证：

```text
中文文本
  -> Sherpa-ONNX Matcha-TTS
  -> Vocos 声码器
  -> PCM / WAV
  -> plughw:2,0
  -> 板端中文语音播放
```

这样可以把 TTS 模块从 ASR、Qwen、摄像头、KWS 等复杂链路中剥离出来，避免完整助手失败时无法判断问题来源。

---

## 2. 实验目标

实验 06 需要回答以下问题：

```text
1. TTS 模型资产是否齐全；
2. 当前项目配置中的 Matcha-TTS 路径是否正确；
3. Sherpa-ONNX OfflineTts 是否可以在 RK3588 上完成中文 TTS；
4. Matcha 声学模型和 Vocos 声码器是否可以正常配合；
5. TTS 输出音频采样率、声道数、幅值是否正常；
6. 合成后的 WAV 是否可以通过 ALSA 播放；
7. 项目官方 voice_assistant.py tts-stream 入口是否可用；
8. Qwen 生成的文本回答是否能被 TTS 播放出来。
```

---

## 3. 实验 06 总体拆分

本实验拆分为：

```text
06.0 TTS 资产、依赖、入口预检
06.1 TTS 模型资产搜索与补齐
06.2 Sherpa-ONNX TTS 最小 WAV 合成验证
06.3 TTS 合成 WAV 播放验证
06.4 voice_assistant.py tts-stream 官方入口验证
06.5 Qwen 文本回答 -> TTS 播放验证
```

---

## 4. 当前 TTS 配置

项目配置文件：

```text
config/default.yaml
```

TTS 相关配置为：

```yaml
models:
  tts:
    type: matcha
    acoustic_model: /home/cat/ai/qwen3vl2b/models/matcha-icefall-zh-baker/model-steps-3.onnx
    vocoder: /home/cat/ai/qwen3vl2b/models/vocos-22khz-univ.onnx
    lexicon: /home/cat/ai/qwen3vl2b/models/matcha-icefall-zh-baker/lexicon.txt
    tokens: /home/cat/ai/qwen3vl2b/models/matcha-icefall-zh-baker/tokens.txt
    data_dir: /home/cat/ai/qwen3vl2b/models/matcha-icefall-zh-baker
```

音频播放相关配置为：

```yaml
audio:
  speaker_device: plughw:2,0
  playback_channels: 2
  playback_sample_rate: 44100
  playback_mode: stereo_dup
```

这说明：

```text
1. TTS 使用 Sherpa-ONNX Matcha-TTS；
2. 声学模型为 model-steps-3.onnx；
3. 声码器为 vocos-22khz-univ.onnx；
4. 播放侧期望输出到 plughw:2,0；
5. 播放侧目标采样率为 44100 Hz；
6. 播放侧目标声道数为 2。
```

---

## 5. 相关代码关系

### 5.1 `voice_assistant/tts.py`

核心类：

```python
class SherpaTts:
```

主要职责：

```text
1. 读取 config/default.yaml 中 models.tts 配置；
2. 根据 type=matcha 构造 OfflineTtsMatchaModelConfig；
3. 加载 acoustic_model、vocoder、lexicon、tokens、data_dir；
4. 构造 sherpa_onnx.OfflineTts；
5. 调用 tts.generate(text, sid, speed) 生成音频 samples。
```

核心依赖：

```text
sherpa_onnx
numpy
matcha-icefall-zh-baker/model-steps-3.onnx
vocos-22khz-univ.onnx
lexicon.txt
tokens.txt
```

---

### 5.2 `voice_assistant/streaming_tts.py`

核心类：

```python
class StreamingTtsPlayer:
```

主要职责：

```text
1. 创建后台 TTS 播放线程；
2. 接收待播放文本；
3. 调用 SherpaTts 合成 samples；
4. 调用 PcmSpeakerStream.write_samples 写入播放管道；
5. 关闭播放流。
```

---

### 5.3 `voice_assistant/audio_io.py`

相关类：

```python
class PcmSpeakerStream:
```

从实验日志中确认其读取配置：

```text
speaker_device        -> audio["speaker_device"]
playback_channels     -> audio.get("playback_channels", 2)
playback_sample_rate  -> audio.get("playback_sample_rate", 44100)
playback_mode         -> audio.get("playback_mode", "stereo_dup")
```

这说明项目的官方 TTS 播放入口不是简单地直接播放 22050 Hz mono，而是会按照项目播放配置写入 ALSA 播放流。

---

## 6. 实验 06.0：TTS 资产、依赖、入口预检

### 6.1 实验目的

实验 06.0 用于确认：

```text
1. TTS 模型文件是否存在；
2. Python 是否可以导入 sherpa_onnx；
3. 项目是否存在 tts 或 tts-stream 子命令；
4. TTS 代码实现依赖哪些文件；
5. 当前声卡播放配置是否仍为 plughw:2,0。
```

---

### 6.2 预检结果

关键输出：

```text
[MISS]      ./models/matcha-icefall-zh-baker
[MISS]      ./models/vocos-22khz-univ.onnx
missing_tts_assets: 2
[RESULT] Experiment 06.0 PRECHECK BLOCKED: TTS assets missing.
```

同时 Python 依赖检查中出现：

```text
[FAIL] import onnxruntime: ModuleNotFoundError: No module named 'onnxruntime'
[FAIL] import soundfile: ModuleNotFoundError: No module named 'soundfile'
[FAIL] import scipy: ModuleNotFoundError: No module named 'scipy'
```

但本项目 TTS 主路径实际通过：

```text
sherpa_onnx.OfflineTts
```

执行，因此本阶段真正阻塞项不是 `onnxruntime / soundfile / scipy`，而是 TTS 模型资产缺失。

---

### 6.3 CLI 入口检查

实验发现项目没有：

```bash
voice_assistant.py tts
```

合法入口为：

```bash
voice_assistant.py tts-stream "中文文本"
```

帮助信息：

```text
usage: voice_assistant.py tts-stream [-h] text
```

结论：

```text
后续官方入口验证应使用 tts-stream，而不是 tts。
```

---

## 7. 实验 06.1：TTS 模型资产搜索与补齐

### 7.1 初始搜索结果

在板端搜索：

```text
/home/cat/ai
/home/cat
/media/cat
/home/cat/Downloads
/home/cat/下载
```

关键结果：

```text
matcha_candidate_count: 0
vocos_candidate_count : 0
auto_copied: 0
missing_tts_required_files: 4
[RESULT] Experiment 06.1 BLOCKED: TTS assets still missing.
```

缺失文件为：

```text
./models/matcha-icefall-zh-baker/model-steps-3.onnx
./models/matcha-icefall-zh-baker/lexicon.txt
./models/matcha-icefall-zh-baker/tokens.txt
./models/vocos-22khz-univ.onnx
```

结论：

```text
板端本地没有可自动复用的 TTS 模型资产，需要外部下载后传入。
```

---

### 7.2 Windows 端下载资产

在 Windows 端下载：

```text
E:\3588_qwen\tts_assets
```

需要下载两个资产：

```text
matcha-icefall-zh-baker.tar.bz2
vocos-22khz-univ.onnx
```

最初使用 `curl.exe` 下载时多次出现：

```text
curl: (56) schannel: server closed abruptly (missing close_notify)
curl: (35) schannel: failed to receive handshake, SSL/TLS connection failed
```

说明：

```text
不是 URL 错误，而是 GitHub 下载过程中 TLS / 网络链路反复中断。
```

后续使用 `aria2c` 断点续传解决。

---

### 7.3 Windows 端资产解压结果

解压后 `matcha-icefall-zh-baker` 目录内容：

```text
matcha-icefall-zh-baker
├── dict
├── date.fst
├── lexicon.txt          1.4M
├── model-steps-3.onnx   73M
├── number.fst
├── phone.fst
├── README.md
└── tokens.txt           20K
```

Vocos 文件：

```text
vocos-22khz-univ.onnx    53,884,024 bytes，约 51.4 MB
```

---

### 7.4 板端上传与复制

上传到板端中转目录：

```text
/home/cat/ai/tts_assets_inbox
```

最开始只传入了 Matcha 目录，缺少：

```text
/home/cat/ai/tts_assets_inbox/vocos-22khz-univ.onnx
```

补传 Vocos 后，复制到项目目录：

```bash
cd /home/cat/ai/qwen3vl2b

mkdir -p models

cp -av /home/cat/ai/tts_assets_inbox/matcha-icefall-zh-baker ./models/
cp -av /home/cat/ai/tts_assets_inbox/vocos-22khz-univ.onnx ./models/
```

---

### 7.5 最终验收结果

重新运行资产验收脚本后：

```text
[OK] ./models/matcha-icefall-zh-baker/model-steps-3.onnx
-rw-r--r-- 1 cat cat 73M ./models/matcha-icefall-zh-baker/model-steps-3.onnx

[OK] ./models/matcha-icefall-zh-baker/lexicon.txt
-rw-r--r-- 1 cat cat 1.4M ./models/matcha-icefall-zh-baker/lexicon.txt

[OK] ./models/matcha-icefall-zh-baker/tokens.txt
-rw-r--r-- 1 cat cat 20K ./models/matcha-icefall-zh-baker/tokens.txt

[OK] ./models/vocos-22khz-univ.onnx
-rw-r--r-- 1 cat cat 52M ./models/vocos-22khz-univ.onnx

auto_copied: 0
missing_tts_required_files: 0
[RESULT] Experiment 06.1 PASSED: TTS assets prepared.
```

结论：

```text
TTS 模型资产补齐完成，实验 06.1 通过。
```

---

## 8. 实验 06.2：Sherpa-ONNX TTS 最小 WAV 合成验证

### 8.1 实验目的

实验 06.2 不播放音频，只验证：

```text
中文文本
  -> SherpaTts
  -> sherpa_onnx.OfflineTts
  -> samples
  -> WAV 文件
```

这样可以判断：

```text
1. Matcha-TTS 是否能正常加载；
2. Vocos 声码器是否能正常加载；
3. 中文文本是否能合成出非空波形；
4. 输出音频采样率、幅值、时长是否合理。
```

---

### 8.2 测试文本

```text
你好，我是三五八八语音助手。现在正在进行端侧中文语音合成实验。
```

---

### 8.3 合成结果

关键结果：

```text
sample_rate: 22050
samples_shape: (145847,)
samples_min: -0.5880312919616699
samples_max: 0.6243456602096558
duration_seconds: 6.614
pcm_peak: 20457
return_code: 0
elapsed_seconds: 5
[RESULT] Experiment 06.2 PASSED
```

输出 WAV 信息：

```text
RIFF WAVE audio
Microsoft PCM
16 bit
mono
22050 Hz
Duration: 00:00:06.61
File Size: 292k
Bit Rate: 353k
```

音量检测：

```text
mean_volume: -22.9 dB
max_volume : -4.1 dB
```

异常检查：

```text
无 error / failed / traceback / killed / oom / ModuleNotFound
```

---

### 8.4 实验结论

实验 06.2 判定：**通过**。

说明：

```text
Sherpa-ONNX Matcha-TTS + Vocos 已经可以在 RK3588 上完成中文语音合成；
输出音频为 22050 Hz / mono / 16-bit PCM WAV；
音频时长、峰值、音量均正常；
TTS 模型推理链路成立。
```

---

## 9. 实验 06.3：TTS 合成 WAV 播放验证

### 9.1 实验目的

实验 06.3 验证合成 WAV 能否通过 ALSA 播放。

测试两种播放方式：

```text
方式 A：直接播放 TTS 原始输出
        22050 Hz / mono

方式 B：转换后播放
        44100 Hz / stereo
```

---

### 9.2 直接播放 22050 Hz mono 失败

直接播放命令：

```bash
aplay -D plughw:2,0 output/exp06_2_tts_min_synth_wav_xxx/tts_min_synth.wav
```

结果：

```text
aplay_return_code: 1
aplay_elapsed_seconds: 0
```

错误信息：

```text
Playing WAVE '.../tts_min_synth.wav' : Signed 16 bit Little Endian, Rate 22050 Hz, Mono
aplay: set_params:1407: Unable to install hw params:
ACCESS:  RW_INTERLEAVED
FORMAT:  S16_LE
CHANNELS: 1
RATE: 22050
```

说明：

```text
当前 ES8388 / plughw:2,0 播放链路无法直接安装 22050 Hz / mono 的硬件参数。
```

这不是 TTS 合成失败，而是播放设备参数适配问题。

---

### 9.3 转换为 44100 Hz stereo 后播放成功

转换目标：

```text
44100 Hz / stereo / 16-bit PCM
```

转换后 WAV 信息：

```text
Input File     : 'output/exp06_3_tts_wav_playback_xxx/tts_min_synth_44100_stereo.wav'
Channels       : 2
Sample Rate    : 44100
Precision      : 16-bit
Duration       : 00:00:06.61
```

播放结果：

```text
aplay_converted_return_code: 0
[RESULT] Experiment 06.3 PASSED_BY_COMMAND
```

人工确认：

```text
板端可以听到转换后的中文语音。
```

---

### 9.4 实验结论

实验 06.3 判定：**通过，但发现播放参数适配问题**。

结论：

```text
1. TTS 原始输出为 22050 Hz / mono；
2. 当前 ES8388 播放链路不能直接播放 22050 Hz mono；
3. 转换为 44100 Hz / stereo 后可以正常播放；
4. 项目播放链路应使用 playback_sample_rate=44100、playback_channels=2；
5. 这与 config/default.yaml 中的播放配置一致。
```

该发现对后续完整助手非常重要：

```text
不能简单地把 TTS 原始 samples 直接写入声卡；
需要通过 PcmSpeakerStream 进行采样率和声道适配。
```

---

## 10. 实验 06.4：`voice_assistant.py tts-stream` 官方入口验证

### 10.1 实验目的

实验 06.4 验证项目官方入口：

```bash
voice_assistant.py tts-stream "中文文本"
```

是否可以完成：

```text
中文文本
  -> StreamingTtsPlayer
  -> SherpaTts
  -> PcmSpeakerStream
  -> plughw:2,0
  -> 板端播放
```

---

### 10.2 测试文本

```text
你好，我是三五八八端侧语音助手。现在正在验证流式中文语音合成和播放。
```

---

### 10.3 运行结果

关键结果：

```text
return_code: 0
elapsed_seconds: 12
[RESULT] Experiment 06.4 PASSED_BY_COMMAND
[NOTE] Please confirm by listening whether the official tts-stream voice was audible.
```

标准输出：

```text
空
```

标准错误：

```text
空
```

异常检查：

```text
无 error / failed / traceback / xrun / Broken pipe / Unable to install hw params
```

人工听音确认：

```text
板端听到了中文语音。
```

---

### 10.4 实验结论

实验 06.4 判定：**通过**。

说明：

```text
voice_assistant.py tts-stream 官方入口可以正常完成 TTS 合成与播放；
PcmSpeakerStream 播放链路可以处理项目配置中的 44100 Hz / stereo 输出要求；
官方 TTS 播放入口没有出现 06.3 中直接播放 22050 Hz mono 的硬件参数问题。
```

这说明后续完整助手应该优先使用官方 `tts-stream` / `StreamingTtsPlayer` 链路，而不是直接 `aplay` TTS 原始输出。

---

## 11. 实验 06.5：Qwen 文本回答 -> TTS 播放验证

### 11.1 实验目的

实验 06.5 验证实验 05 的 Qwen 文本输出是否可以接入实验 06 的 TTS 播放入口。

链路：

```text
demo.jpg
  -> Qwen3-VL 图片问答
  -> qwen_answer.txt
  -> tts-stream
  -> 板端语音播放
```

本实验不重新录音，不接 ASR，目的是单独验证：

```text
大模型回答文本
  -> TTS 语音播报
```

---

### 11.2 Qwen 输入

图片：

```text
demo.jpg
```

问题：

```text
<image>请用一句中文简短介绍这张图片。
```

---

### 11.3 Qwen 输出

Qwen 回答：

```text
一位宇航员在月球上悠闲地坐着，手持绿色啤酒瓶，背景是地球和星空。
```

统计：

```text
qwen_return_code: 0
qwen_elapsed_seconds_wall: 19
qwen_elapsed_seconds: 18.979
answer_chars: 32
```

---

### 11.4 TTS 播放文本

实际播放文本：

```text
下面播放大模型对图片的回答：一位宇航员在月球上悠闲地坐着，手持绿色啤酒瓶，背景是地球和星空。
```

统计：

```text
tts_text_chars: 46
tts_return_code: 0
tts_elapsed_seconds: 15
```

标准错误：

```text
qwen stderr: 空
tts stderr : 空
```

异常检查：

```text
无 error / failed / traceback / killed / oom / xrun / Broken pipe
```

最终结果：

```text
[RESULT] Experiment 06.5 PASSED_BY_COMMAND
[NOTE] Please confirm by listening whether the Qwen answer was spoken.
```

人工听音确认：

```text
板端听到了大模型回答被中文语音播报出来。
```

---

### 11.5 实验结论

实验 06.5 判定：**通过**。

说明：

```text
Qwen3-VL 的文本回答可以被送入项目 TTS 播放入口；
TTS 可以在板端把大模型回答转换为中文语音并播放；
实验 05 的“大模型文本回答”和实验 06 的“语音输出”已经成功衔接。
```

---

## 12. 实验 06 总体结果

| 子实验 | 内容 | 状态 | 关键结论 |
|---|---|---|---|
| 06.0 | TTS 预检 | 阻塞后解决 | 缺少 Matcha 和 Vocos 资产 |
| 06.1 | TTS 资产补齐 | 通过 | `missing_tts_required_files: 0` |
| 06.2 | 最小 TTS WAV 合成 | 通过 | 输出 22050 Hz mono WAV |
| 06.3 | WAV 播放验证 | 通过 | 22050 mono 直放失败，44100 stereo 播放成功 |
| 06.4 | 官方 `tts-stream` | 通过 | 板端听到中文语音 |
| 06.5 | Qwen 回答 -> TTS | 通过 | 板端听到大模型回答 |

---

## 13. 当前已具备能力

实验 06 完成后，系统已具备：

```text
中文文本
  -> Sherpa-ONNX Matcha-TTS
  -> Vocos 声码器
  -> PcmSpeakerStream
  -> ALSA plughw:2,0
  -> 板端中文语音播放
```

并且已经完成：

```text
Qwen3-VL 图片问答文本
  -> TTS 中文语音播报
```

结合实验 05，当前系统已经具备以下两段能力：

```text
1. 语音输入 -> ASR -> Qwen3-VL -> 文本回答
2. Qwen3-VL -> 文本回答 -> TTS -> 语音播放
```

下一步只需要把这两段串联起来，即可进入完整语音问答闭环。

---

## 14. 关键问题与定位结论

### 14.1 问题 1：TTS 模型资产缺失

现象：

```text
[MISS] ./models/matcha-icefall-zh-baker
[MISS] ./models/vocos-22khz-univ.onnx
```

结论：

```text
不是代码错误，也不是 sherpa_onnx 运行错误，而是模型资产未补齐。
```

处理方式：

```text
Windows 下载 matcha-icefall-zh-baker 和 vocos-22khz-univ.onnx；
上传到 /home/cat/ai/tts_assets_inbox；
复制到项目 models 目录。
```

---

### 14.2 问题 2：GitHub 下载反复中断

现象：

```text
curl: (56) schannel: server closed abruptly
curl: (35) schannel: failed to receive handshake
```

结论：

```text
属于下载链路不稳定，不是文件路径错误。
```

处理方式：

```text
使用 aria2c 进行断点续传。
```

---

### 14.3 问题 3：直接播放 22050 Hz mono 失败

现象：

```text
aplay: set_params:1407: Unable to install hw params
RATE: 22050
CHANNELS: 1
```

结论：

```text
当前 ES8388 / plughw:2,0 不适合直接播放 TTS 原始 22050 Hz mono WAV。
```

处理方式：

```text
转换为 44100 Hz / stereo 后播放成功；
项目官方 PcmSpeakerStream 应按 playback_sample_rate=44100、playback_channels=2 播放。
```

---

### 14.4 问题 4：没有 `tts` 子命令

现象：

```text
voice_assistant.py: error: argument cmd: invalid choice: 'tts'
```

结论：

```text
项目当前没有 tts 子命令，只有 tts-stream 子命令。
```

正确用法：

```bash
python3 voice_assistant.py tts-stream "你好，我是三五八八语音助手。"
```

---

## 15. 当前可复用命令

### 15.1 TTS 资产验收

```bash
cd /home/cat/ai/qwen3vl2b

EXP=output/exp06_1_find_tts_assets_after_copy_$(date +%Y%m%d_%H%M%S)
./scripts/exp06_1_find_tts_assets.sh "$EXP"

sed -n '/final expected asset check/,/log saved/p' "$EXP/run.log"
```

---

### 15.2 最小 TTS WAV 合成

```bash
cd /home/cat/ai/qwen3vl2b

EXP=output/exp06_2_tts_min_synth_wav_$(date +%Y%m%d_%H%M%S)
./scripts/exp06_2_tts_min_synth_wav.sh "$EXP"
```

查看结果：

```bash
OUT=$(ls -td output/exp06_2_tts_min_synth_wav_* | head -1)

grep -E "\[RESULT\]|sample_rate|duration_seconds|pcm_peak|mean_volume|max_volume" "$OUT/run.log"
```

---

### 15.3 播放 TTS WAV

```bash
cd /home/cat/ai/qwen3vl2b

EXP=output/exp06_3_tts_wav_playback_$(date +%Y%m%d_%H%M%S)
./scripts/exp06_3_tts_wav_playback.sh "$EXP"
```

---

### 15.4 官方 TTS 播放入口

```bash
cd /home/cat/ai/qwen3vl2b

python3 voice_assistant.py tts-stream "你好，我是三五八八端侧语音助手。"
```

---

### 15.5 Qwen 回答 -> TTS 播放

```bash
cd /home/cat/ai/qwen3vl2b

EXP=output/exp06_5_qwen_answer_to_tts_$(date +%Y%m%d_%H%M%S)
./scripts/exp06_5_qwen_answer_to_tts.sh "$EXP"
```

---

## 16. 对后续实验的建议

实验 06 已经封口。下一步建议进入：

```text
实验 07：ASR -> Qwen -> TTS 完整语音问答闭环
```

目标链路：

```text
麦克风录音
  -> voice_assistant.py record
  -> Sherpa-ONNX ASR
  -> Qwen3-VL 文本 / 图文理解
  -> TTS 语音合成
  -> plughw:2,0 播放
```

建议实验 07 先不接 KWS，也不接摄像头自动拍照，而是先验证：

```text
record -> stt -> ask -> tts-stream
```

原因：

```text
1. 实验 04 已经验证 record -> stt；
2. 实验 05 已经验证 stt -> qwen；
3. 实验 06 已经验证 qwen -> tts-stream；
4. 实验 07 应先把这三段串成完整闭环；
5. KWS 和摄像头触发可以放在后续实验中加入。
```

---

## 17. 实验 06 最终结论

实验 06 判定：**通过**。

本实验完成了 RK3588 端侧语音助手项目的中文语音合成与播放链路验证：

```text
TTS 资产补齐
  -> Sherpa-ONNX Matcha-TTS 模型加载
  -> Vocos 声码器加载
  -> 中文文本合成 WAV
  -> 44100 Hz stereo 播放适配
  -> voice_assistant.py tts-stream 官方入口验证
  -> Qwen 回答文本语音播报
```

最终系统已经具备：

```text
Qwen3-VL 本地文本回答
  -> 中文 TTS 合成
  -> 板端语音播放
```

这意味着项目从实验 05 的：

```text
语音输入 -> ASR -> Qwen -> 文本回答
```

推进到了实验 06 的：

```text
Qwen -> 文本回答 -> TTS -> 语音输出
```

为后续实验 07 的完整闭环：

```text
语音输入 -> ASR -> Qwen -> TTS -> 语音回答
```

奠定了基础。

---

# 实验 06 阶段性封口

```text
Qwen 文本回答
  -> Sherpa-ONNX Matcha-TTS
  -> Vocos
  -> PcmSpeakerStream
  -> plughw:2,0
  -> 板端中文语音播放
```

实验 06 正式完成。
