
# 实验04：Sherpa-ONNX离线中文ASR识别链路验证

项目：Qwen3-VL-2B RK3588语音助手

平台：

* LubanCat RK3588
* Ubuntu 22.04
* Python 3.9
* USB麦克风
* Sherpa-ONNX 1.13.2

实验日期：

2026-06

---

# 一、实验目标

在实验02完成录音链路验证后，进一步验证：

```text
真实语音
    ↓
录音
    ↓
WAV
    ↓
Sherpa-ONNX
    ↓
中文文本
```

确认：

* RK3588能够运行离线中文ASR
* Sherpa-ONNX运行环境正常
* 中文模型加载正常
* voice_assistant项目可调用ASR模块
* 麦克风录音能够被成功识别

---

# 二、实验背景

前期实验已经完成：

```text
实验02：
录音链路验证

arecord
    ↓
16kHz WAV
    ↓
保存文件
```

验证结果：

```text
录音成功
WAV格式正确
单声道16kHz
```

但当时ASR功能无法运行。

主要问题：

```text
缺少 sherpa_onnx
缺少中文ASR模型
CLI存在依赖耦合
```

因此开展实验04。

---

# 三、实验04总体规划

实验04拆分为：

```text
04.1 ASR环境预检

04.2 Sherpa-ONNX运行环境安装

04.3 官方模型识别验证

04.3.1 项目ASR集成修复

04.4 真实麦克风识别验证

04.5 Record→STT完整闭环验证
```

---

# 四、实验04.1 环境预检

检查内容：

```text
CPU架构
Python版本
glibc版本
依赖安装情况
模型目录情况
项目代码结构
```

确认：

```text
aarch64
Python 3.9.2
glibc 2.31
```

发现：

```text
sherpa_onnx未安装
ASR模型目录不存在
```

但：

```text
PyPI存在对应aarch64 wheel
```

因此平台兼容性不存在问题。

结论：

```text
环境满足部署条件
仅缺少运行时和模型资产
```

---

# 五、实验04.2 Sherpa-ONNX运行环境安装

安装版本：

```text
sherpa_onnx 1.13.2
sherpa-onnx-core 1.13.2
```

采用方式：

```text
项目私有目录安装

.python_packages
```

避免污染系统Python环境。

修复：

```text
.venv/bin/python
```

增加：

```text
PYTHONPATH

项目根目录
.python_packages
```

验证：

```python
import sherpa_onnx
```

成功。

结论：

```text
Sherpa-ONNX运行环境通过
```

---

# 六、实验04.2 中文ASR模型部署

部署模型：

```text
sherpa-onnx-conformer-zh-stateless2-2023-05-23
```

模型组成：

```text
tokens.txt

encoder-epoch-99-avg-1.int8.onnx

decoder-epoch-99-avg-1.onnx

joiner-epoch-99-avg-1.int8.onnx
```

实际大小：

```text
encoder INT8
122 MB

decoder
12 MB

joiner INT8
2.8 MB
```

配置检查：

```text
tokens
encoder
decoder
joiner
```

全部通过。

结果：

```text
ASR模型资产验证通过
```

---

# 七、实验04.3 官方模型标准音频验证

使用模型自带：

```text
test_wavs

0.wav
1.wav
2.wav
3.wav
4.wav
5.wav
6.wav
```

直接调用：

```python
sherpa_onnx.OfflineRecognizer
```

识别结果：

```text
7个音频
7个成功
0个空结果
```

统计：

```text
wav_count           : 7
non_empty_count     : 7

total_audio_seconds : 35.617

total_decode_seconds: 1.667

overall_rtf         : 0.0468
```

计算：

```text
实时倍率：

1 / 0.0468

≈ 21.4x Real Time
```

说明：

RK3588 CPU可实现约21倍实时离线识别速度。

结论：

```text
ASR核心推理链路通过
```

---

# 八、实验04.3.1 项目ASR集成修复

发现问题：

```text
voice_assistant.py stt
```

会导入：

```text
orchestrator
qwen_runner
pexpect
```

导致：

```text
ModuleNotFoundError
```

问题本质：

```text
ASR与Qwen模块耦合
```

修复方案：

在cli.py中增加：

```text
Lightweight STT Branch
```

实现：

```text
stt命令

只导入：

config.py
asr.py
audio_utils.py
```

不再依赖：

```text
Qwen
pexpect
TTS
Camera
KWS
```

修复后：

```text
voice_assistant.py stt
```

可独立运行。

结论：

```text
ASR模块成功解耦
```

---

# 九、实验04.4 真实麦克风识别验证

验证链路：

```text
真人说话
    ↓
USB麦克风
    ↓
record
    ↓
WAV
    ↓
SherpaAsr
    ↓
中文文本
```

录音统计：

```text
duration
8 s

peak
32395

peak_ratio
0.989

rms_ratio
0.105
```

音量统计：

```text
mean_volume
-19.6 dB

max_volume
0 dB
```

实际说话内容：

```text
你好我是良民健
我正在使用三五八八
```

ASR结果：

```text
你好我是良民健我正在使用三五八八
```

结果完全匹配。

结论：

```text
真实麦克风识别通过
```

---

# 十、实验04.5 Record→STT闭环验证

验证项目官方入口：

```text
voice_assistant.py record
    ↓
voice_assistant.py stt
```

识别结果：

```text
你好我是良民健我正在使用三五八八
```

输出：

```text
[RESULT] Experiment 04.5 PASSED
```

说明：

项目已具备：

```text
录音
↓
识别
↓
输出文本
```

完整能力。

---

# 十一、实验结论

实验04全部通过。

完成能力：

```text
麦克风采集
    ↓
16kHz WAV
    ↓
Sherpa-ONNX
    ↓
中文识别
    ↓
文本输出
```

验证结果：

```text
04.1 环境预检
PASS

04.2 Runtime部署
PASS

04.2 模型资产验证
PASS

04.3 官方模型识别
PASS

04.3.1 项目ASR集成修复
PASS

04.4 真实麦克风识别
PASS

04.5 Record→STT闭环
PASS
```

最终状态：

```text
RK3588语音助手

ASR链路完全打通
```

---

# 十二、后续实验规划

下一阶段进入：

```text
实验05

Qwen推理链路验证
```

目标：

```text
录音
 ↓
ASR
 ↓
Qwen3-VL-2B
 ↓
文本回答
```

实现：

```text
语音输入 → 大模型理解
```

为后续：

```text
TTS语音回复
视觉问答
完整语音助手
```

奠定基础。

