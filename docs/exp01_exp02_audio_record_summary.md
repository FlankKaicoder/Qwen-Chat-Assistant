# RK3588 端侧多模态智能语音助手实验 01-02 总结

> 项目：RK3588 端侧多模态智能语音助手系统  
> 平台：LubanCat / RK3588  
> 仓库目录：`/home/cat/ai/qwen3vl2b`  
> 实验范围：实验 01、实验 02  
> 当前阶段：完成音频硬件链路与项目录音链路封口，暂不进入实验 03 摄像头链路。

---

## 1. 阶段目标

在进入 ASR、KWS、TTS、Qwen3-VL、摄像头等复杂链路之前，先验证语音助手项目最底层的音频基础能力。

本阶段关注两个问题：

```text
实验 01：验证 RK3588 / LubanCat 当前音频硬件设备是否可稳定完成录音与播放。
实验 02：验证项目自己的 Python 入口和配置文件是否能驱动录音链路，生成后续 ASR 可用的 16kHz 单声道命令音频。
```

最终目标不是直接跑完整语音助手，而是把“音频设备”和“项目录音入口”从后续问题中剥离出来，避免后续 ASR / KWS / TTS 出问题时误判为硬件问题。

---

# 实验 01：音频输入 / 输出链路基线验证

## 2. 实验 01 目标

实验 01 目标是验证当前板端的 ALSA 音频设备是否真实可用。

验证内容包括：

```text
1. 查看板端声卡枚举情况；
2. 确认哪个声卡同时支持 CAPTURE 和 PLAYBACK；
3. 验证 16kHz 单声道录音；
4. 验证录音文件格式；
5. 验证录音文件可播放；
6. 验证 44.1kHz 双声道测试音可播放；
7. 确认 config/default.yaml 中的音频配置是否与实际声卡一致。
```

---

## 3. 实验 01 输出目录

本次实验输出目录：

```text
output/exp01_audio_baseline_20260611_222058
```

主要输出文件：

```text
00_exp_info.log
01_system_info.log
02_audio_devices.log
03_default_yaml_audio.log
04_mixer_card2.log
05_arecord_16k_mono.log
06_record_file_info.log
07_aplay_recorded_wav.log
08_test_tone_info.log
09_aplay_test_tone.log
10_file_list.log
record_16k_mono_5s.wav
test_tone_44100_stereo.wav
```

---

## 4. 声卡设备检查结果

### 4.1 `/proc/asound/cards`

实验中检测到 3 个声卡：

```text
0 [rockchiphdmiin ]: rockchip-hdmiin - rockchip-hdmiin
1 [rockchipdp0    ]: rockchip-dp0 - rockchip-dp0
2 [rockchipes8388 ]: rockchip-es8388 - rockchip-es8388
```

含义如下：

| card | 名称 | 功能判断 |
|---|---|---|
| 0 | rockchip-hdmiin | HDMI 输入，主要用于采集 |
| 1 | rockchip-dp0 | DP / HDMI 播放输出 |
| 2 | rockchip-es8388 | 板载音频 codec，同时支持采集和播放 |

实验 01 的核心结论是：

```text
card 2: rockchip-es8388
```

才是当前语音助手项目最适合使用的输入输出声卡。

---

### 4.2 采集设备 `arecord -l`

```text
**** List of CAPTURE Hardware Devices ****
card 0: rockchiphdmiin [rockchip-hdmiin], device 0
card 2: rockchipes8388 [rockchip-es8388], device 0
```

说明：

```text
card 2 / device 0 支持录音采集。
```

---

### 4.3 播放设备 `aplay -l`

```text
**** List of PLAYBACK Hardware Devices ****
card 1: rockchipdp0 [rockchip-dp0], device 0
card 2: rockchipes8388 [rockchip-es8388], device 0
```

说明：

```text
card 2 / device 0 支持音频播放。
```

因此当前项目应使用：

```text
plughw:2,0
```

作为麦克风和扬声器设备。

---

## 5. 项目音频配置确认

实验 01 时 `config/default.yaml` 中的音频配置为：

```yaml
audio:
  mic_device: plughw:2,0
  speaker_device: plughw:2,0
  playback_channels: 2
  playback_sample_rate: 44100
  playback_mode: stereo_dup
  sample_rate: 16000
  channels: 2
  input_channel: left
  mixer_card: 2
  capture_channel_gain: 8
  wake_input_gain: 8.0
  asr_input_gain: 5.0
  command_seconds: 6
  wake_chunk_seconds: 2
```

该配置与实验 01 中检测到的实际设备一致：

```text
mic_device     -> plughw:2,0
speaker_device -> plughw:2,0
mixer_card     -> 2
```

其中需要特别注意：

```text
channels: 2
input_channel: left
```

说明项目原本设计可能是先按双声道采集，然后取左声道作为 ASR / KWS 输入。

---

## 6. 录音测试结果

实验 01 使用如下方式录制 5 秒音频：

```bash
arecord \
  -D plughw:2,0 \
  -f S16_LE \
  -r 16000 \
  -c 1 \
  -d 5 \
  output/exp01_audio_baseline_20260611_222058/record_16k_mono_5s.wav
```

录音日志：

```text
Recording WAVE 'output/exp01_audio_baseline_20260611_222058/record_16k_mono_5s.wav' : Signed 16 bit Little Endian, Rate 16000 Hz, Mono
```

录音文件信息：

```text
RIFF WAVE audio
Microsoft PCM
16 bit
mono
16000 Hz
Duration: 00:00:05.00
Bitrate: 256 kb/s
```

对应 `soxi` 信息：

```text
Channels       : 1
Sample Rate    : 16000
Precision      : 16-bit
Duration       : 00:00:05.00 = 80000 samples
File Size      : 160k
Bit Rate       : 256k
Sample Encoding: 16-bit Signed Integer PCM
```

说明：

```text
plughw:2,0 可以完成 16kHz / mono / S16_LE 录音。
```

---

## 7. 播放测试结果

播放录音文件：

```bash
aplay -D plughw:2,0 output/exp01_audio_baseline_20260611_222058/record_16k_mono_5s.wav
```

播放日志：

```text
Playing WAVE 'output/exp01_audio_baseline_20260611_222058/record_16k_mono_5s.wav' : Signed 16 bit Little Endian, Rate 16000 Hz, Mono
```

测试音播放：

```text
Playing WAVE 'output/exp01_audio_baseline_20260611_222058/test_tone_44100_stereo.wav' : Signed 16 bit Little Endian, Rate 44100 Hz, Stereo
```

说明：

```text
plughw:2,0 可以播放 16kHz 单声道录音，也可以播放 44.1kHz 双声道测试音。
```

---

## 8. 实验 01 结论

实验 01 判定：**通过**。

结论如下：

```text
1. 当前板端真正适合语音助手项目的声卡是 card 2 / rockchip-es8388。
2. 录音设备可使用 plughw:2,0。
3. 播放设备可使用 plughw:2,0。
4. mixer_card 应为 2。
5. config/default.yaml 中的音频配置已经与实际设备匹配。
6. 16kHz / mono / 16-bit PCM 录音通过。
7. 录音文件播放通过。
8. 44.1kHz / stereo 测试音播放通过。
```

因此后续实验中，除非硬件连接或系统声卡枚举发生变化，否则不应再反复怀疑 `plughw:2,0` 方向。

---

# 实验 02：项目 Python 录音链路验证

## 9. 实验 02 目标

实验 02 的目标不是直接跑 ASR，而是验证项目自身的 Python 入口能否基于 `config/default.yaml` 完成录音。

验证重点：

```text
1. scripts/test_stt_record.sh 是否可用；
2. voice_assistant.py record 是否可用；
3. Python 依赖是否满足最小录音入口；
4. 项目是否能按配置读取 plughw:2,0；
5. 项目是否能完成双声道采集、左声道抽取、增益放大；
6. 最终是否能输出 ASR 可用的 16kHz / mono / 16-bit PCM wav。
```

实验 02 不是一次性完成，而是分成多个子阶段逐步定位：

```text
实验 02：初始脚本验证
实验 02.1：系统 Python 运行环境检查
实验 02.2：最小 Python 依赖修复
实验 02.3：配置驱动录音链路验证
实验 02.4：CLI lazy import 初次修复尝试
实验 02.5：恢复 cli.py 并重新尝试修复
实验 02.6：完整重写 cli.py，最终通过 voice_assistant.py record
```

---

## 10. 实验 02 初始脚本验证

### 10.1 输出目录

```text
output/exp02_project_audio_record_20260611_222322
```

### 10.2 项目脚本内容

`scripts/test_stt_record.sh` 内容：

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

seconds="${1:-5}"
wav="/tmp/qwen_voice_assistant/test_stt.wav"
mkdir -p /tmp/qwen_voice_assistant

echo "Recording ${seconds}s to ${wav}. Speak Chinese after recording starts."
.venv/bin/python voice_assistant.py record --seconds "$seconds" --out "$wav"
echo "Transcription:"
.venv/bin/python voice_assistant.py stt "$wav"
rm -f "$wav"
```

### 10.3 初始失败现象

运行结果：

```text
scripts/test_stt_record.sh:行11: .venv/bin/python: 没有那个文件或目录
```

结论：

```text
此时失败点不是录音，也不是 ALSA，而是项目脚本写死使用 .venv/bin/python，但仓库目录下没有 .venv。
```

---

## 11. 实验 02.1：系统 Python 运行环境检查

### 11.1 输出目录

```text
output/exp02_1_python_record_env_20260611_223414
```

### 11.2 Python 环境

```text
/usr/bin/python3
Python 3.9.2

/usr/bin/pip3
pip 20.3.4
```

`.venv` 状态：

```text
.venv 不存在
```

### 11.3 requirements.txt

```text
click==8.4.1
numpy==2.4.6
packaging==26.2
pexpect==4.9.0
ptyprocess==0.7.0
PyYAML==6.0.3
sherpa-onnx-core==1.13.2
sherpa_onnx==1.13.2
```

### 11.4 import 检查结果

```text
[FAIL] import yaml: ModuleNotFoundError: No module named 'yaml'
[OK] import numpy
[OK] import wave
[OK] import argparse
[OK] import subprocess
[MISS/FAIL] import sounddevice: ModuleNotFoundError: No module named 'sounddevice'
[MISS/FAIL] import pyaudio: ModuleNotFoundError: No module named 'pyaudio'
[MISS/FAIL] import sherpa_onnx: ModuleNotFoundError: No module named 'sherpa_onnx'
[MISS/FAIL] import onnxruntime: ModuleNotFoundError: No module named 'onnxruntime'
```

### 11.5 直接运行 `voice_assistant.py record` 的失败点

```text
ModuleNotFoundError: No module named 'yaml'
```

完整链路：

```text
voice_assistant.py
  -> voice_assistant.cli
    -> voice_assistant.config
      -> import yaml
```

结论：

```text
当前最小阻塞依赖是 PyYAML。
```

---

## 12. 实验 02.2：最小 Python 依赖修复

### 12.1 输出目录

```text
output/exp02_2_min_python_record_fix_20260611_223532
```

### 12.2 安装 PyYAML

优先使用系统 apt 安装：

```bash
sudo apt-get update
sudo apt-get install -y python3-yaml
```

安装后检查：

```text
[OK] yaml 5.3.1
```

说明：

```text
系统 Python 已可 import yaml。
```

### 12.3 创建 `.venv/bin/python` 包装器

由于项目脚本写死调用 `.venv/bin/python`，但当前没有真正虚拟环境，因此创建轻量包装器：

```bash
mkdir -p .venv/bin

cat > .venv/bin/python <<'PYWRAPPER'
#!/usr/bin/env bash
exec /usr/bin/python3 "$@"
PYWRAPPER

chmod +x .venv/bin/python
```

检查结果：

```text
.venv/bin/python -> Python 3.9.2
[OK] yaml 5.3.1
```

### 12.4 新失败点：`sherpa_onnx`

再次运行录音入口时，出现：

```text
ModuleNotFoundError: No module named 'sherpa_onnx'
```

完整链路：

```text
voice_assistant.py
  -> voice_assistant.cli
    -> from .orchestrator import VoiceAssistant
      -> from .asr import SherpaAsr
        -> import sherpa_onnx
```

这暴露出项目结构问题：

```text
record 命令本身不应该依赖 ASR；
但 cli.py 顶部全局导入 orchestrator，导致即使只执行 record，也必须先导入 asr.py 和 sherpa_onnx。
```

此时的结论不是“继续安装 sherpa_onnx”，而是先验证录音链路，并修复 CLI 依赖耦合。

---

## 13. 实验 02.3：配置驱动录音链路验证

### 13.1 输出目录

```text
output/exp02_3_config_record_only_20260611_223912
```

### 13.2 目的

为了绕开 `voice_assistant.py` 的全局导入问题，新增独立脚本：

```text
scripts/test_record_config_only.py
```

该脚本只做最小录音验证：

```text
1. 读取 config/default.yaml；
2. 获取 audio.mic_device / sample_rate / channels / input_channel / asr_input_gain；
3. 使用 arecord 按配置录制 raw wav；
4. 使用 ffmpeg 抽取左声道并放大；
5. 输出最终 16kHz 单声道 wav。
```

### 13.3 导入耦合问题定位

`voice_assistant/cli.py` 顶部导入：

```text
from .config import load_config
from .orchestrator import VoiceAssistant
from .streaming_tts import StreamingTtsPlayer
```

`voice_assistant/orchestrator.py` 顶部导入：

```text
from .asr import SherpaAsr
from .audio_io import AudioRecorder
from .camera import CameraAdapter
from .intent import IntentRouter
from .qwen_runner import QwenRunner
from .streaming_tts import StreamingTtsPlayer
from .wake import SherpaKeywordWake, SttKeywordWake
```

`voice_assistant/asr.py` 顶部导入：

```text
import sherpa_onnx
```

因此：

```text
record 命令被迫依赖 sherpa_onnx。
```

这是 CLI 设计上的依赖耦合问题。

### 13.4 配置读取结果

```text
mic_device   : plughw:2,0
sample_rate  : 16000
channels     : 2
input_channel: left
asr_gain     : 5.0
seconds      : 5
```

### 13.5 采集命令

```bash
arecord \
  -D plughw:2,0 \
  -f S16_LE \
  -r 16000 \
  -c 2 \
  -d 5 \
  output/exp02_3_config_record_only_20260611_223912/config_record_only_5s.raw_capture.wav
```

录制结果：

```text
Signed 16 bit Little Endian
Rate 16000 Hz
Stereo
Duration: 00:00:05.00
Bitrate: 512 kb/s
```

### 13.6 声道抽取与增益

处理命令：

```bash
ffmpeg -y -hide_banner \
  -i config_record_only_5s.raw_capture.wav \
  -af 'pan=mono|c0=c0,volume=5.0' \
  -ar 16000 \
  -ac 1 \
  config_record_only_5s.wav
```

含义：

```text
pan=mono|c0=c0  -> 抽取左声道
volume=5.0      -> 按 asr_input_gain 放大 5 倍
-ar 16000       -> 保持 16kHz
-ac 1           -> 输出单声道
```

### 13.7 最终音频文件信息

```text
config_record_only_5s.raw_capture.wav:
  16-bit PCM
  stereo
  16000 Hz
  5.00s
  313K

config_record_only_5s.wav:
  16-bit PCM
  mono
  16000 Hz
  5.00s
  157K
```

`soxi` 输出：

```text
Channels       : 1
Sample Rate    : 16000
Precision      : 16-bit
Duration       : 00:00:05.00 = 80000 samples
File Size      : 160k
Bit Rate       : 256k
Sample Encoding: 16-bit Signed Integer PCM
```

音量检测：

```text
mean_volume: -32.2 dB
max_volume : -8.1 dB
```

播放验证：

```text
Playing WAVE 'config_record_only_5s.wav' : Signed 16 bit Little Endian, Rate 16000 Hz, Mono
```

### 13.8 实验 02.3 结论

实验 02.3 判定：**通过**。

结论：

```text
项目配置文件中的 audio 参数是可用的。
RK3588 可以按 config/default.yaml 完成：
1. plughw:2,0 双声道采集；
2. left 左声道抽取；
3. asr_input_gain=5.0 增益放大；
4. 输出 16kHz / mono / 16-bit PCM / 5s wav；
5. 播放验证通过。
```

此时已经证明“项目配置驱动录音链路”没有问题，剩余问题集中在 `voice_assistant.py record` 的入口耦合。

---

## 14. 实验 02.4：CLI lazy import 初次修复尝试

### 14.1 输出目录

```text
output/exp02_4_cli_lazy_import_record_20260611_224219
```

### 14.2 操作

尝试通过自动替换方式删除 `cli.py` 顶部的重依赖导入：

```text
from .orchestrator import VoiceAssistant
from .streaming_tts import StreamingTtsPlayer
```

并在需要的位置插入局部导入。

### 14.3 失败原因

生成代码出现缩进错误：

```text
Sorry: IndentationError: unexpected indent (cli.py, line 67)
```

错误片段：

```text
66:     from .orchestrator import VoiceAssistant
67:         assistant = VoiceAssistant(load_config(args.config))
```

第 67 行比第 66 行多缩进一层，导致 Python 语法错误。

### 14.4 处理方式

本次实验保留了备份文件：

```text
output/exp02_4_cli_lazy_import_record_20260611_224219/cli.py.before
```

后续使用该备份恢复 `voice_assistant/cli.py`。

实验 02.4 结论：

```text
失败，失败原因是自动 patch 缩进错误，不是录音链路问题。
```

---

## 15. 实验 02.5：恢复 cli.py 并重新尝试修复

### 15.1 输出目录

```text
output/exp02_5_restore_cli_record_bypass_20260611_224550
```

### 15.2 恢复操作

从实验 02.4 的备份恢复：

```bash
cp output/exp02_4_cli_lazy_import_record_20260611_224219/cli.py.before voice_assistant/cli.py
```

恢复后的导入仍为原始状态：

```text
from .config import load_config
from .orchestrator import VoiceAssistant
from .streaming_tts import StreamingTtsPlayer
```

### 15.3 再次 patch 失败原因

脚本假设源码中存在：

```text
args = parser.parse_args(argv)
```

但实际源码为：

```text
args = build_parser().parse_args()
```

因此自动 patch 没有找到匹配点，报错：

```text
RuntimeError: cannot find args = parser.parse_args(argv)
```

由于 patch 在写回前失败，因此 `cli.py` 保持为恢复后的原始版本。

实验 02.5 结论：

```text
失败，失败原因是 patch 脚本对源码结构假设错误。
```

---

## 16. 实验 02.6：完整重写 cli.py，最终修复 record 独立运行

### 16.1 输出目录

```text
output/exp02_6_rewrite_cli_record_ok_20260611_224705
```

### 16.2 修复策略

不再使用不稳定的自动替换，而是完整重写 `voice_assistant/cli.py`。

核心原则：

```text
1. 顶部只保留轻量标准库导入；
2. record 子命令在 main() 中提前处理；
3. record 不构造 VoiceAssistant；
4. record 不导入 orchestrator.py；
5. record 不导入 asr.py；
6. record 不依赖 sherpa_onnx；
7. 非 record 命令继续在需要时局部导入 VoiceAssistant。
```

重写后顶部导入：

```python
from __future__ import annotations

import argparse
import sys
from pathlib import Path
```

关键逻辑：

```python
if args.cmd == "record":
    _record_without_heavy_import(args)
    return

from .config import load_config
from .orchestrator import VoiceAssistant
assistant = VoiceAssistant(load_config(args.config))
```

说明：

```text
record 命令会提前返回，不会执行到 orchestrator / asr / sherpa_onnx 导入。
```

### 16.3 语法检查

执行：

```bash
python3 -m py_compile \
  voice_assistant.py \
  voice_assistant/cli.py \
  voice_assistant/config.py \
  voice_assistant/audio_io.py
```

结果：

```text
无输出，表示语法检查通过。
```

### 16.4 只导入 CLI 检查

执行：

```python
import voice_assistant.cli
print("[OK] import voice_assistant.cli")
```

结果：

```text
[OK] import voice_assistant.cli
```

说明：

```text
仅导入 cli.py 时不再触发 sherpa_onnx 依赖。
```

---

## 17. `voice_assistant.py record` 官方入口验证

### 17.1 执行命令

```bash
.venv/bin/python voice_assistant.py record \
  --seconds 5 \
  --out output/exp02_6_rewrite_cli_record_ok_20260611_224705/official_record_5s.wav
```

### 17.2 读取配置结果

```text
========== lightweight record ==========
config       : config/default.yaml
mic_device   : plughw:2,0
sample_rate  : 16000
channels     : 2
input_channel: left
asr_gain     : 5.0
seconds      : 5
raw          : output/exp02_6_rewrite_cli_record_ok_20260611_224705/official_record_5s.raw_capture.wav
out          : output/exp02_6_rewrite_cli_record_ok_20260611_224705/official_record_5s.wav
```

### 17.3 原始采集命令

```bash
arecord -D plughw:2,0 \
  -f S16_LE \
  -r 16000 \
  -c 2 \
  -d 5 \
  output/exp02_6_rewrite_cli_record_ok_20260611_224705/official_record_5s.raw_capture.wav
```

采集结果：

```text
Signed 16 bit Little Endian
Rate 16000 Hz
Stereo
Duration: 00:00:05.00
Bitrate: 512 kb/s
```

### 17.4 左声道抽取与增益放大

```bash
ffmpeg -y -hide_banner \
  -i output/exp02_6_rewrite_cli_record_ok_20260611_224705/official_record_5s.raw_capture.wav \
  -af 'pan=mono|c0=c0,volume=5.0' \
  -ar 16000 \
  -ac 1 \
  output/exp02_6_rewrite_cli_record_ok_20260611_224705/official_record_5s.wav
```

处理结果：

```text
Output Audio:
pcm_s16le
16000 Hz
mono
s16
256 kb/s
```

### 17.5 最终输出文件

```text
official_record_5s.raw_capture.wav:
  313K
  RIFF WAVE audio
  Microsoft PCM
  16 bit
  stereo
  16000 Hz

official_record_5s.wav:
  157K
  RIFF WAVE audio
  Microsoft PCM
  16 bit
  mono
  16000 Hz
```

`soxi` 信息：

```text
Channels       : 1
Sample Rate    : 16000
Precision      : 16-bit
Duration       : 00:00:05.00 = 80000 samples
File Size      : 160k
Bit Rate       : 256k
Sample Encoding: 16-bit Signed Integer PCM
```

Python wave 检查：

```text
channels    : 1
sample_rate : 16000
sample_width: 2
frames      : 80000
duration_s  : 5.0
```

音量检测：

```text
mean_volume: -45.3 dB
max_volume : -19.9 dB
```

播放验证：

```text
Playing WAVE 'official_record_5s.wav' : Signed 16 bit Little Endian, Rate 16000 Hz, Mono
```

### 17.6 关于音量的说明

本次 `official_record_5s.wav` 的音量检测为：

```text
mean_volume: -45.3 dB
max_volume : -19.9 dB
```

说明：

```text
1. 文件不是静音；
2. 有有效声音峰值；
3. 平均音量偏小；
4. 后续 ASR 效果不好时，可以继续优化：
   - 麦克风距离；
   - asr_input_gain；
   - capture_channel_gain；
   - input_channel 选择；
   - 环境噪声。
```

---

## 18. STT 预期失败验证

实验 02.6 最后执行：

```bash
.venv/bin/python voice_assistant.py stt official_record_5s.wav
```

结果：

```text
ModuleNotFoundError: No module named 'sherpa_onnx'
```

这是预期结果，不是实验失败。

说明现在边界已经清楚：

```text
record：已独立运行，不依赖 sherpa_onnx，验证通过。
stt：仍然依赖 sherpa_onnx 和 ASR 模型资产，等待后续实验处理。
```

---

# 19. 实验 01-02 总结结论

## 19.1 已通过内容

```text
实验 01：音频硬件链路通过
1. card 2 / rockchip-es8388 是当前可用音频 codec；
2. plughw:2,0 支持录音；
3. plughw:2,0 支持播放；
4. 16kHz 单声道录音通过；
5. 16kHz 单声道播放通过；
6. 44.1kHz 双声道播放通过。

实验 02：项目录音链路通过
1. PyYAML 最小依赖已修复；
2. .venv/bin/python 包装器已建立；
3. 定位并修复 cli.py 全局导入耦合问题；
4. voice_assistant.py record 已可独立运行；
5. 项目可读取 config/default.yaml 中 audio 配置；
6. 项目可完成 16kHz 双声道采集；
7. 项目可抽取 left 声道；
8. 项目可按 asr_input_gain=5.0 放大；
9. 项目可输出 16kHz / mono / 16-bit PCM / 5s wav；
10. 输出 wav 可播放。
```

---

## 19.2 当前仍未解决内容

```text
1. sherpa_onnx 尚未安装；
2. ASR 模型资产尚未验证；
3. KWS 唤醒词模型尚未验证；
4. TTS / Vocos 模型尚未验证；
5. Qwen3-VL RKNN / RKLLM runtime 与模型尚未验证；
6. 摄像头拍照链路尚未进入实验 03。
```

---

## 19.3 关键问题定位

### 问题 1：脚本写死 `.venv/bin/python`

原始脚本：

```bash
.venv/bin/python voice_assistant.py record --seconds "$seconds" --out "$wav"
```

但项目目录下没有 `.venv`，导致脚本直接失败。

处理方式：

```bash
mkdir -p .venv/bin
cat > .venv/bin/python <<'PYWRAPPER'
#!/usr/bin/env bash
exec /usr/bin/python3 "$@"
PYWRAPPER
chmod +x .venv/bin/python
```

---

### 问题 2：缺少 PyYAML

现象：

```text
ModuleNotFoundError: No module named 'yaml'
```

处理方式：

```bash
sudo apt-get install -y python3-yaml
```

结果：

```text
[OK] yaml 5.3.1
```

---

### 问题 3：record 命令被 ASR 依赖卡住

原始导入链路：

```text
voice_assistant.py
  -> voice_assistant.cli
    -> orchestrator.py
      -> asr.py
        -> sherpa_onnx
```

问题本质：

```text
CLI 顶部全局导入过重，导致轻量 record 命令也依赖 ASR / Qwen / TTS。
```

修复方式：

```text
重写 cli.py：
1. record 命令提前处理；
2. record 使用 _record_without_heavy_import；
3. 非 record 命令才局部导入 VoiceAssistant；
4. tts-stream 分支才局部导入 StreamingTtsPlayer。
```

---

# 20. 当前可复用命令

## 20.1 直接录音命令

```bash
cd /home/cat/ai/qwen3vl2b

.venv/bin/python voice_assistant.py record \
  --seconds 5 \
  --out /tmp/qwen_voice_assistant/test_record.wav
```

预期输出：

```text
========== lightweight record ==========
[CMD] arecord ...
[CMD] ffmpeg ...
========== output wav ==========
channels    : 1
sample_rate : 16000
duration_s  : 5.0
```

---

## 20.2 检查录音文件

```bash
file /tmp/qwen_voice_assistant/test_record.wav
soxi /tmp/qwen_voice_assistant/test_record.wav
ffprobe -hide_banner /tmp/qwen_voice_assistant/test_record.wav
ffmpeg -hide_banner \
  -i /tmp/qwen_voice_assistant/test_record.wav \
  -af volumedetect \
  -f null - 2>&1 | grep -E "mean_volume|max_volume"
```

---

## 20.3 播放录音文件

```bash
aplay -D plughw:2,0 /tmp/qwen_voice_assistant/test_record.wav
```

---

# 21. 对后续实验的建议

由于实验 01、02 已经封口，后续实验建议按如下顺序推进：

```text
实验 03：摄像头拍照链路验证
  目标：只验证 /dev/video11 -> 图片文件，不跑 Qwen。

实验 04：ASR 依赖与模型资产验证
  目标：安装 sherpa_onnx，补齐 ASR 模型，验证 voice_assistant.py stt。

实验 05：KWS 唤醒词验证
  目标：验证 kws-file / wake 子命令。

实验 06：TTS 播放链路验证
  目标：验证文字 -> TTS -> PCM / WAV -> plughw:2,0 播放。

实验 07：Qwen3-VL 文本基线验证
  目标：不接摄像头，只跑文本问答。

实验 08：Qwen3-VL 图文基线验证
  目标：图片 + 文本输入，验证 RKNN / RKLLM / demo。

实验 09：once 单轮语音对话闭环
  目标：record -> stt -> qwen -> tts -> play。

实验 10：listen / wake 完整助手链路
  目标：唤醒词 -> 指令 -> 摄像头 / Qwen / TTS。
```

---

# 22. 最终阶段性结论

```text
截至实验 02 结束，RK3588 端侧语音助手项目已经完成音频底座封口：

1. 板端 ES8388 音频 codec 可用；
2. plughw:2,0 可同时完成采集和播放；
3. 项目配置文件中的音频参数可用；
4. Python 最小运行环境已修复；
5. cli.py 的 record 子命令已解除 ASR 重依赖；
6. voice_assistant.py record 已能独立生成 16kHz 单声道命令音频；
7. 后续 ASR / KWS / TTS / Qwen 失败时，不应再优先怀疑基础音频链路。

当前阻塞点已经从硬件音频问题，收敛到 sherpa_onnx、语音模型资产、Qwen3-VL 模型和 runtime 资产问题。
```
