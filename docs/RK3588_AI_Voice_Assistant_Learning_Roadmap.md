# RK3588 端侧多模态智能语音助手——系统学习路线

> 项目：RK3588 端侧多模态智能语音助手系统  
> 平台：LubanCat / RK3588  
> 仓库：`FlankKaicoder/Qwen-Chat-Assistant`  
> 项目目录：`/home/cat/ai/qwen3vl2b`  
> 学习目标：从零基础重新理解已经完成的实验 00～12，把“做过项目”转化为“真正理解并能够独立讲清楚项目”。  
> 当前决策：**不继续新增实验，进入系统学习、项目复盘、仓库收尾与简历准备阶段。**

---

# 1. 为什么现在要重新学习整个项目

目前项目已经完成实验 00～12，主要覆盖了：

```text
项目环境与资产
→ 音频采集/播放
→ 摄像头采集
→ Sherpa-ONNX ASR
→ Qwen3-VL RKNN/RKLLM 推理
→ Matcha-TTS / Vocos
→ ASR → Qwen → TTS 单轮闭环
→ 真实摄像头视觉问答
→ KWS “鲁班猫”唤醒
→ 受控式文本/视觉双链路
→ IntentRouter 正式重构
→ 自动化测试
→ 同进程多轮稳定性
→ Qwen demo Zombie 定位和修复
→ 40 轮 Soak Test
```

从工程结果看，项目主体已经完成。

但当前最重要的问题不是“还能再加什么功能”，而是：

> 已经完成的大部分工作依赖实验指导完成，很多底层知识、代码关系、Linux 机制、AI Runtime 机制尚未形成自己的完整理解。

因此后续重点从：

```text
继续开发新功能
```

切换为：

```text
基础知识补齐
→ 项目代码理解
→ 每个实验为什么这样做
→ 故障为什么发生
→ 如何定位
→ 为什么当前修复有效
→ 如何在面试中自己解释
```

最终目标不是背命令、背代码，而是能独立回答：

```text
“这个项目从用户说‘鲁班猫’开始，到喇叭输出回答，中间到底发生了什么？”
```

并且能逐层解释每一个模块。

---

# 2. 最终要达到的掌握程度

学习完成后，至少需要具备以下能力。

## 2.1 能完整解释系统主链路

能够不看资料画出：

```text
用户说话
  ↓
麦克风
  ↓
ALSA / PCM
  ↓
KWS
  ↓
命令录音
  ↓
ASR
  ↓
IntentRouter
  ↓
文本 / 视觉分流
  ├───────────────┐
  ↓               ↓
文本 Qwen       Camera
                  ↓
                V4L2
                  ↓
               NV12/JPEG
                  ↓
               Qwen3-VL
  └───────────────┘
          ↓
       文本回答
          ↓
      Matcha-TTS
          ↓
        Vocos
          ↓
         PCM
          ↓
        ALSA
          ↓
        喇叭
```

---

## 2.2 能解释软硬件分层

能够理解：

```text
应用层
VoiceAssistant / Python / CLI
────────────────────────────
AI 模型与运行时
Sherpa-ONNX / RKNN / RKLLM
────────────────────────────
Linux 用户态
ALSA / V4L2 / FFmpeg / subprocess
────────────────────────────
Kernel / Driver
Audio Driver / Camera / ISP
────────────────────────────
Hardware
CPU / NPU / DDR / Mic / Camera / Speaker
```

并说明每层负责什么。

---

## 2.3 能理解主要进程关系

能够画出：

```text
voice_assistant.py
        │
        ├── arecord
        │
        ├── capture-photo.sh
        │      ├── v4l2-ctl
        │      └── ffmpeg
        │
        ├── Qwen demo
        │
        └── aplay / PCM Speaker
```

理解：

- 哪些是 Python 模块；
- 哪些是独立 Linux 进程；
- 谁创建谁；
- 谁应该回收谁；
- 为什么会产生 Zombie。

---

## 2.4 能真正解释已经发生过的典型问题

例如：

```text
CLI 为什么出现重依赖耦合？

为什么 record 命令会被 sherpa_onnx 阻塞？

为什么 22050 Hz mono TTS 不能直接播放？

为什么 once 的流式 TTS 会 underrun？

为什么已经生成完整 NV12，但 JPEG 仍然没有生成？

为什么普通文本会误触发摄像头？

为什么 Mock 测试可能意外运行真实硬件？

为什么 Qwen demo 会变成 Zombie？

为什么 RSS 变大不一定等于内存泄漏？
```

这些问题不是额外知识，而是本项目已经真实出现过的问题。

---

# 3. 学习原则

后续所有学习遵循以下原则。

## 3.1 从零基础开始

不因为项目已经做完 12 个实验，就默认以下概念已经掌握：

```text
Terminal
Shell
Bash
CLI
Python package
import
subprocess
ALSA
PCM
V4L2
NV12
ASR
KWS
LLM
VLM
RKNN
RKLLM
TTS
process
PID
Zombie
Mock
Regression
Soak Test
```

每个概念第一次出现时，都从最基础解释。

---

## 3.2 先理解，再看代码

推荐顺序：

```text
概念
↓
直觉模型
↓
RK3588 平台中的位置
↓
项目中的位置
↓
真实代码
↓
真实实验
↓
真实故障
```

避免一开始直接陷入代码细节。

---

## 3.3 区分“项目做过”和“理论补充”

学习过程中必须明确区分：

### 项目实际完成

只根据实验 00～12 的文档和代码说明，例如：

```text
使用了 W8A8 RKLLM 模型
```

### 理论补充

为了帮助理解，可以补充：

```text
W8A8 的基本含义
量化参数的概念
NPU Runtime 的一般工作方式
```

但不能把理论补充写成：

```text
“本项目自行完成了 W8A8 量化”
```

如果实验资料没有证明这一点，就不能这样描述。

---

# 4. 整体学习阶段

整个学习过程划分为四个阶段。

---

## 阶段 A：基础能力

```text
第 0 章：项目全局认识
第 1 章：Linux / Terminal / CLI / Git
第 2 章：Python 与项目代码结构
```

目标：

> 先拥有读懂后续项目的最低软件基础。

---

## 阶段 B：输入输出设备

```text
第 3 章：ALSA 与音频链路
第 4 章：V4L2 与摄像头链路
```

目标：

> 理解语音和图片是如何从真实硬件进入 Linux 用户程序的。

---

## 阶段 C：AI 模型链

```text
第 5 章：Sherpa-ONNX ASR
第 6 章：KWS 唤醒词
第 7 章：Qwen3-VL / RKNN / RKLLM
第 8 章：Matcha-TTS / Vocos
```

目标：

> 理解声音、文字、图像分别如何进入 AI 模型，以及模型输出如何继续进入后续模块。

---

## 阶段 D：工程能力

```text
第 9 章：Orchestrator 与状态机
第 10 章：IntentRouter
第 11 章：自动化测试
第 12 章：Linux 进程、Zombie 与稳定性
第 13 章：完整架构复盘
第 14 章：简历与面试表达
```

目标：

> 把项目从“AI Demo”理解成一个真正的端侧软件系统。

---

# 5. 第 0 章：项目全局认识

## 5.1 学习目标

先不深入代码，只回答：

```text
这个项目到底是什么？

用户输入是什么？

最终输出是什么？

RK3588 在里面负责什么？

CPU 在做什么？

NPU 在做什么？

麦克风和摄像头在做什么？

Sherpa-ONNX 在做什么？

Qwen3-VL 在做什么？

TTS 在做什么？

Python 程序在做什么？
```

---

## 5.2 需要建立的第一张大图

```text
Hardware
│
├── Mic
├── Camera
├── Speaker
├── CPU
├── NPU
└── DDR
     ↓
Linux
│
├── ALSA
├── V4L2
└── Process / File / Device
     ↓
Runtime
│
├── Sherpa-ONNX
├── RKNN
└── RKLLM
     ↓
Model
│
├── KWS
├── ASR
├── Qwen3-VL
└── TTS
     ↓
Application
│
└── VoiceAssistant
```

---

## 5.3 对应实验

主要对应：

```text
实验 00
实验 01～12 全局关系
```

---

# 6. 第 1 章：Linux、Terminal、CLI 与 Git

## 6.1 Linux 基础

从最基础理解：

```text
什么是操作系统
什么是 Linux
什么是用户空间
什么是内核空间
```

---

## 6.2 Terminal / Shell / Bash / CLI

需要区分：

```text
Terminal
Shell
Bash
CLI
Command
Argument
Option
```

例如：

```bash
python voice_assistant.py once --seconds 5
```

拆解：

```text
python
    可执行程序

voice_assistant.py
    Python 脚本

once
    CLI 子命令

--seconds
    option

5
    option value
```

---

## 6.3 Linux 文件系统基础

理解：

```text
/
home
/dev
/tmp
/proc
```

重点：

```text
/home/cat/ai/qwen3vl2b
/dev/video11
/tmp/qwen_voice_assistant
/proc/<pid>
```

---

## 6.4 Git 基础

学习：

```text
repository
working tree
stage
commit
branch
main
merge
remote
GitHub
```

对应：

```text
git status
git add
git commit
git branch
git switch
git merge
git pull
git push
```

理解实验 11、12 为什么使用独立分支。

---

## 6.5 对应实验

```text
实验 00
实验 01～02
实验 11
实验 12
```

---

# 7. 第 2 章：Python 与项目代码结构

## 7.1 Python 基础

重点学习：

```text
.py 文件
变量
函数
class
object
constructor
module
package
import
exception
```

---

## 7.2 项目目录

重点理解：

```text
voice_assistant.py

voice_assistant/
├── cli.py
├── config.py
├── audio_io.py
├── asr.py
├── camera.py
├── wake.py
├── qwen_runner.py
├── tts.py
├── streaming_tts.py
├── intent.py
├── orchestrator.py
└── controlled_session.py

config/
scripts/
models/
output/
tests/
```

---

## 7.3 CLI 调用路径

理解：

```text
用户命令
  ↓
voice_assistant.py
  ↓
cli.py
  ↓
argparse
  ↓
对应命令分支
  ↓
实际模块
```

---

## 7.4 重点案例：CLI 依赖耦合

早期项目出现：

```text
record
↓
cli.py import orchestrator
↓
orchestrator import asr
↓
asr import sherpa_onnx
↓
没有 sherpa_onnx
↓
record 也无法运行
```

需要理解：

```text
为什么这是不合理的依赖
什么是 lazy import
什么是 lightweight entry
什么是模块解耦
```

---

## 7.5 对应实验

```text
实验 02
实验 03
实验 04
实验 05
```

---

# 8. 第 3 章：ALSA 与音频链路

## 8.1 声音数字化基础

从：

```text
人的声音
↓
空气振动
↓
麦克风
↓
模拟电信号
↓
ADC
↓
数字样本
```

开始。

学习：

```text
Sampling Rate
Bit Depth
Channel
PCM
WAV
```

---

## 8.2 项目关键格式

重点理解：

```text
16000 Hz
S16_LE
Mono
Stereo
```

以及：

```text
22050 Hz
44100 Hz
```

---

## 8.3 ALSA

理解：

```text
ALSA 是什么

sound card
PCM device

hw:2,0
plughw:2,0
```

重点命令：

```bash
arecord -l
aplay -l
arecord
aplay
```

---

## 8.4 项目音频配置

理解：

```yaml
mic_device: plughw:2,0
speaker_device: plughw:2,0
sample_rate: 16000
channels: 2
input_channel: left
```

---

## 8.5 项目实际数据流

```text
Mic
↓
ES8388
↓
ALSA
↓
arecord
↓
Stereo PCM
↓
Left Channel
↓
Gain
↓
16k Mono WAV
↓
ASR
```

---

## 8.6 对应实验

```text
实验 01
实验 02
实验 06
实验 07
```

---

# 9. 第 4 章：V4L2 与摄像头图像链路

## 9.1 摄像头基础

理解：

```text
光
↓
Camera Sensor
↓
MIPI CSI
↓
ISP
↓
DDR
↓
Linux Video Device
```

---

## 9.2 `/dev/video11`

理解：

```text
Linux 为什么把设备暴露成文件
设备节点是什么
/dev/video11 与摄像头驱动是什么关系
```

---

## 9.3 V4L2

理解：

```text
Video4Linux2
v4l2-ctl
stream
buffer
mmap
```

---

## 9.4 NV12

重点学习：

```text
RGB
YUV
NV12
```

以及：

```text
1280 × 720 NV12
=
1280 × 720 × 1.5
=
1,382,400 bytes
```

为什么这个计算可以用于验证采集是否完整。

---

## 9.5 JPEG 与 FFmpeg

理解：

```text
NV12
↓
FFmpeg
↓
JPEG
```

为什么 Qwen 使用 JPEG，而摄像头底层输出 NV12。

---

## 9.6 CameraAdapter

理解：

```text
Python
↓
CameraAdapter.capture()
↓
capture-photo.sh
↓
v4l2-ctl
↓
NV12
↓
ffmpeg
↓
JPEG
```

---

## 9.7 重点故障案例

```text
完整 NV12 已生成
↓
JPEG 没生成
↓
摄像头不是主要故障点
↓
继续隔离 FFmpeg
↓
发现 stdin 等待问题
↓
增加 -nostdin
```

重点学习：

> 如何根据中间产物逐段排除问题。

---

## 9.8 对应实验

```text
实验 03
实验 08
实验 09
实验 10
```

---

# 10. 第 5 章：Sherpa-ONNX ASR

## 10.1 ASR 基础

```text
ASR
=
Automatic Speech Recognition
```

理解：

```text
Waveform
↓
Neural Network
↓
Token / Symbol
↓
Text
```

---

## 10.2 Sherpa-ONNX

理解：

```text
Sherpa-ONNX 是什么
ONNX 是什么
OfflineRecognizer 是什么
```

---

## 10.3 模型组成

重点理解：

```text
encoder
decoder
joiner
tokens.txt
```

不要求一开始深入数学推导，先理解每个组件的大致职责。

---

## 10.4 项目 ASR 链路

```text
16 kHz PCM
↓
SherpaAsr
↓
OfflineRecognizer
↓
中文文本
```

---

## 10.5 RTF

理解实验中：

```text
total_audio_seconds  = 35.617
total_decode_seconds = 1.667
overall_rtf          = 0.0468
```

RTF 的意义：

```text
推理耗时 / 音频时长
```

以及为什么：

```text
RTF < 1
```

意味着可以实时处理。

---

## 10.6 对应实验

```text
实验 04
实验 07
实验 08
实验 09
```

---

# 11. 第 6 章：KWS 唤醒词

## 11.1 KWS 基础

```text
KWS
=
Keyword Spotting
```

---

## 11.2 KWS 与 ASR 区别

```text
ASR：
整句话 → 文本

KWS：
音频流 → 是否出现目标关键词
```

---

## 11.3 项目关键词

```text
鲁班猫
拍照助手
```

对应：

```text
config/wake_keywords.txt
```

---

## 11.4 核心参数

理解：

```text
keywords_score
keywords_threshold
input_gain
chunk
stream
```

---

## 11.5 重点工程教训

理解为什么：

```text
return_code = 0
```

只能说明：

```text
程序正常结束
```

不能证明：

```text
检测到了“鲁班猫”
```

真正结果还要查看：

```text
stdout / keyword result
```

---

## 11.6 对应实验

```text
实验 09
实验 10
实验 12
```

---

# 12. 第 7 章：Qwen3-VL、LLM、VLM、RKNN、RKLLM

## 12.1 LLM

理解：

```text
Large Language Model
```

基本输入输出：

```text
Text / Tokens
↓
LLM
↓
Tokens / Text
```

---

## 12.2 VLM

理解：

```text
Vision Language Model
```

为什么可以同时理解：

```text
图片
+
文字
```

---

## 12.3 Qwen3-VL 结构的项目理解

从项目角度理解：

```text
Image
↓
Vision Encoder
↓
Visual Feature
↓
LLM
↓
Text Answer
```

---

## 12.4 项目两个主要模型资产

```text
qwen3-vl-2b_vision_rk3588.rknn

qwen3-vl-2b-instruct_w8a8_rkllm
```

学习：

```text
.rknn 是什么
.rkllm 是什么
为什么有两个模型文件
```

---

## 12.5 RKNN

理解：

```text
Rockchip NPU Runtime / Model Format
```

重点理解：

```text
Vision 模型为什么运行在 RKNN
NPU 在这里负责什么
```

---

## 12.6 RKLLM

理解：

```text
Rockchip LLM Runtime
```

重点理解：

```text
LLM 为什么通过 RKLLM 跑
```

---

## 12.7 W8A8

项目事实：

```text
使用了 W8A8 RKLLM 模型。
```

学习阶段补充：

```text
W8
=
Weight 8-bit

A8
=
Activation 8-bit
```

但必须明确：

> 当前项目资料证明的是“使用 W8A8 模型进行部署”，不是“自行完成 W8A8 量化流程”。

---

## 12.8 关键运行参数

理解：

```text
max_new_tokens
max_context_len
rknn_core_num
```

特别理解实验 10：

```text
Prompt 要求回答短
≠
模型一定短

真正的生成预算还受到
max_new_tokens
限制
```

---

## 12.9 对应实验

```text
实验 05
实验 07
实验 08
实验 10
实验 12
```

---

# 13. 第 8 章：Matcha-TTS、Vocos 与语音播放

## 13.1 TTS 基础

```text
TTS
=
Text To Speech
```

---

## 13.2 整体链路

```text
Text
↓
Matcha-TTS
↓
Acoustic Representation
↓
Vocos
↓
Waveform
↓
PCM
```

---

## 13.3 为什么需要 Matcha 和 Vocos

需要理解：

```text
声学模型
≠
最终可直接播放波形
```

因此需要声码器：

```text
Vocoder
```

---

## 13.4 项目输出

原始 TTS：

```text
22050 Hz
Mono
```

播放器期望：

```text
44100 Hz
Stereo
```

---

## 13.5 重点故障案例

```text
22050 Hz mono
↓
aplay
↓
Unable to install hw params
```

转换：

```text
44100 Hz stereo
```

后播放成功。

理解：

> 模型输出格式和硬件播放格式并不一定完全一致。

---

## 13.6 StreamingTtsPlayer

理解：

```text
SherpaTts
↓
StreamingTtsPlayer
↓
PcmSpeakerStream
↓
ALSA
```

---

## 13.7 Underrun

理解：

```text
ALSA 已经在消费 PCM
↓
下一段 PCM 来不及产生
↓
buffer 读空
↓
underrun
```

对应实验 07：

```text
Qwen 每生成一句
↓
TTS 合成
↓
播放
```

存在间歇，因此出现 underrun。

后续改为：

```text
完整回答
↓
整段 TTS
↓
播放
```

消除该问题。

---

## 13.8 对应实验

```text
实验 06
实验 07
实验 08
```

---

# 14. 第 9 章：Orchestrator 与完整状态机

## 14.1 Orchestrator

理解：

```text
Orchestrator
=
编排器
```

它不负责：

```text
真正 ASR 推理
真正 Camera 驱动
真正 Qwen 推理
真正 TTS 推理
```

它主要负责：

```text
先做什么
什么时候做
把哪个模块的输出传给哪个模块
```

---

## 14.2 VoiceAssistant

核心类：

```text
VoiceAssistant
```

需要理解其成员之间的关系：

```text
ASR
Camera
IntentRouter
QwenRunner
TTS
Wake
```

---

## 14.3 状态机

理解：

```text
WAIT_WAKE
↓
WAKE_DETECTED
↓
PREPARE_RECORD
↓
RECORDING
↓
ASR
↓
INTENT_DISPATCH
↓
QWEN_PIPELINE_START
↓
QWEN_PIPELINE_DONE
↓
TTS
↓
COMPLETED
```

---

## 14.4 controlled_session

理解实验 10 为什么新增：

```text
controlled_session.py
```

它的意义不是增加 AI 模型，而是：

```text
把实验脚本
变成
正式可观测会话
```

---

## 14.5 对应实验

```text
实验 07
实验 08
实验 09
实验 10
```

---

# 15. 第 10 章：IntentRouter

## 15.1 为什么需要 Intent

用户说：

```text
一加一等于几
```

应该：

```text
直接文本问答
```

用户说：

```text
看一下画面
```

应该：

```text
Camera
→ Qwen3-VL
```

因此系统需要：

```text
Intent Router
```

---

## 15.2 最初的关键词方案

类似：

```python
if keyword in text:
    need_photo = True
```

问题：

```text
“图片格式有哪些”
```

也可能被认为需要拍照。

---

## 15.3 正式策略

实验 11 最终形成：

```text
explicit_capture_phrases

direct_visual_commands

visual_context_phrases

visual_action_phrases

text_context_blockers
```

---

## 15.4 需要理解的设计思想

```text
关键词匹配的局限

规则优先级

配置驱动

Intent 与 Prompt 解耦

为什么 monkey patch 不适合作为正式实现
```

---

## 15.5 对应实验

```text
实验 10
实验 11
```

---

# 16. 第 11 章：自动化测试

## 16.1 为什么运行成功一次不够

理解：

```text
Demo PASS
≠
代码长期可靠
```

---

## 16.2 Unit Test

测试：

```text
IntentRouter 本身
```

---

## 16.3 Integration Test

测试：

```text
IntentRouter
+
Orchestrator
+
模块调用关系
```

---

## 16.4 Mock

理解：

```text
Mock Camera
Mock Qwen
Mock TTS
```

意义：

```text
测试逻辑
而不是每次真的运行硬件和模型
```

---

## 16.5 Regression Test

理解：

```text
以前正常的功能
在修改代码后
是否仍然正常
```

---

## 16.6 项目测试结果

实验 11 建立：

```text
6 个 Intent 单元测试
+
7 个 Orchestrator Mock 集成测试
=
13 个自动化测试
```

---

## 16.7 重点故障

首次 Mock 集成测试：

```text
以为替换了 Camera
↓
实际 patch target 错误
↓
真实 Camera / Qwen 被调用
```

需要学习：

```text
Python import binding
patch target
mock injection
```

---

## 16.8 对应实验

```text
实验 11
实验 12
```

---

# 17. 第 12 章：Linux 进程、Zombie、FD、RSS 与稳定性

## 17.1 Process

从最基础理解：

```text
Program
vs
Process
```

---

## 17.2 PID / PPID

学习：

```text
PID
PPID
Parent Process
Child Process
```

---

## 17.3 fork / exec / wait

理解：

```text
父进程
↓
创建子进程
↓
子进程执行
↓
子进程退出
↓
父进程 wait/waitpid
↓
内核回收进程表项
```

---

## 17.4 Zombie

项目真实案例：

```text
Python
↓
QwenRunner
↓
demo
↓
demo 推理结束
↓
demo 进程已经退出
↓
父 Python 未正确 reap
↓
/proc 显示
State: Z
↓
Zombie
```

---

## 17.5 修复

项目通过：

```text
child.close(force=True)
↓
waitpid()
↓
必要时 SIGKILL
↓
再次 waitpid()
```

保证子进程被回收。

---

## 17.6 FD

理解：

```text
File Descriptor
```

不仅是普通文件，还可能包括：

```text
pipe
socket
device
process pipe
```

实验 12：

```text
baseline FD = 6
final FD    = 6
```

说明没有持续 FD 泄漏。

---

## 17.7 Thread

理解：

```text
Process
vs
Thread
```

以及为什么线程数量不应该每轮不断增加。

---

## 17.8 RSS

理解：

```text
Resident Set Size
```

重点：

```text
RSS 第一次增加
≠
一定内存泄漏
```

可能是：

```text
Runtime 初始化
Allocator
Cache
Shared Library
模型相关缓存
```

真正泄漏更关注：

```text
Round1 < Round2 < Round3 < ...
```

持续增长趋势。

---

## 17.9 Soak Test

理解：

```text
长期连续运行
观察：
资源
延迟
温度
残留进程
```

项目最终：

```text
40 / 40 PASS
```

---

## 17.10 对应实验

```text
实验 12
```

---

# 18. 第 13 章：完整项目架构复盘

完成前 12 章后，需要脱离实验编号重新理解整个系统。

---

## 18.1 从用户视角

```text
用户
↓
说“鲁班猫”
↓
助手开始监听命令
↓
用户提问
↓
系统理解文本或视觉意图
↓
本地 AI 推理
↓
语音回答
```

---

## 18.2 从数据视角

```text
Waveform
↓
Text
↓
Intent
↓
Image / Text
↓
Visual / Language Feature
↓
Answer Text
↓
Waveform
```

---

## 18.3 从软件视角

```text
CLI
↓
Controlled Session
↓
VoiceAssistant
↓
Adapters / Runners
↓
Runtime
↓
Linux
↓
Hardware
```

---

## 18.4 从进程视角

```text
Python Main Process
├── arecord
├── v4l2-ctl
├── ffmpeg
├── Qwen demo
└── playback process / stream
```

---

## 18.5 从 NPU/CPU 视角

学习最终需要理解：

```text
哪些模块主要跑 CPU
哪些模块使用 NPU
哪些模块只是 I/O
哪些阶段会访问 DDR
```

这一部分学习时会根据项目资料支持程度逐项区分。

---

# 19. 第 14 章：简历与面试表达

只有真正学完以后再进入这一章。

---

## 19.1 不再按实验编号讲项目

面试时不会说：

```text
我做了实验 01
然后实验 02
然后实验 03……
```

而是讲：

```text
需求
↓
架构
↓
核心实现
↓
关键问题
↓
定位过程
↓
优化结果
↓
稳定性验证
```

---

## 19.2 重点项目故事

优先准备：

### 故事 1：CLI 重依赖解耦

```text
简单 record 被 ASR 依赖阻塞
→ 分析 import 链
→ lightweight branch / lazy import
```

### 故事 2：TTS Underrun

```text
流式 TTS
→ PCM 供给不连续
→ ALSA underrun
→ 对比实验定位
→ full-answer TTS
```

### 故事 3：FFmpeg 卡死

```text
完整 NV12
→ JPEG 不生成
→ 排除摄像头
→ FFmpeg 隔离
→ -nostdin
```

### 故事 4：Intent 误路由

```text
宽泛关键词
→ 文本误触发拍照
→ Intent / Prompt 解耦
→ Formal IntentRouter
→ Tests
```

### 故事 5：Zombie

```text
same-process
→ residual demo
→ ps
→ /proc
→ State Z
→ waitpid
→ 40-round soak
```

其中 Zombie 是整个项目最有工程含金量的排障故事之一。

---

# 20. 每一章的固定学习方法

后续每章统一按照以下方式学习：

```text
1. 最基础概念

2. 生活化直觉解释

3. Linux / RK3588 中的位置

4. 在本项目中的位置

5. 查看项目真实代码

6. 逐段解释代码

7. 回顾对应实验

8. 解释实验为什么这样设计

9. 复盘真实 Bug

10. 自己尝试判断原因

11. 总结本章系统图

12. 面试表达
```

---

# 21. 三张最终必须能独立画出的图

## 21.1 数据流图

```text
Mic
 ↓
KWS
 ↓
Recorder
 ↓
ASR
 ↓
IntentRouter
      ↙       ↘
   Text       Camera
     ↓          ↓
     └──── Qwen3-VL
              ↓
            Answer
              ↓
             TTS
              ↓
           Speaker
```

---

## 21.2 软硬件分层图

```text
Application
VoiceAssistant / Python
────────────────────────
AI Runtime
Sherpa-ONNX / RKNN / RKLLM
────────────────────────
Linux Userspace
ALSA / V4L2 / FFmpeg
────────────────────────
Kernel / Driver
Audio / Camera / ISP
────────────────────────
Hardware
CPU / NPU / DDR / Mic / Camera
```

---

## 21.3 进程图

```text
voice_assistant.py
        │
        ├── arecord
        ├── capture-photo.sh
        │      ├── v4l2-ctl
        │      └── ffmpeg
        │
        ├── Qwen demo
        └── Audio Playback
```

当能够独立画出并解释这三张图时，说明已经建立了比较完整的系统理解。

---

# 22. 对应项目实验资料索引

本学习路线主要依据已经完成的项目实验资料：

```text
实验 00
项目资产与环境确认

实验 01～02
音频硬件与项目录音链路

实验 03
摄像头采集链路

实验 04
Sherpa-ONNX ASR

实验 05
Qwen3-VL RKNN/RKLLM

实验 06
Matcha-TTS / Vocos

实验 07
ASR → Qwen → TTS 闭环

实验 08
Camera → Qwen3-VL → TTS

实验 09
KWS + 受控视觉链路

实验 10
Controlled Session / 性能 / Prompt / Camera 修复

实验 11
IntentRouter / Unit Test / Mock / Regression

实验 12
Multi-turn / Same-process / Zombie / Soak Test
```

学习过程中仍以这些实验资料作为“项目事实”的主要依据。

---

# 23. 推荐学习顺序

严格按照：

```text
00 项目大图
 ↓
01 Linux / CLI / Git
 ↓
02 Python / Code Structure
 ↓
03 ALSA Audio
 ↓
04 V4L2 Camera
 ↓
05 ASR
 ↓
06 KWS
 ↓
07 Qwen3-VL / RKNN / RKLLM
 ↓
08 TTS
 ↓
09 Orchestrator
 ↓
10 IntentRouter
 ↓
11 Testing
 ↓
12 Process / Zombie / Stability
 ↓
13 Full Project Review
 ↓
14 Resume / Interview
```

不建议跳过前面的基础章节。

---

# 24. 最终学习目标检查表

学习结束后应当能够独立回答：

- [ ] Terminal、Shell、Bash、CLI 有什么区别？
- [ ] `python voice_assistant.py once --seconds 5` 每一部分是什么意思？
- [ ] 为什么 Linux 中摄像头是 `/dev/video11`？
- [ ] ALSA、`hw:2,0`、`plughw:2,0` 分别是什么？
- [ ] 16 kHz、S16_LE、mono、stereo 是什么意思？
- [ ] PCM 和 WAV 有什么区别？
- [ ] NV12 是什么？
- [ ] 为什么 1280×720 NV12 是 1,382,400 bytes？
- [ ] V4L2 和 FFmpeg 分别负责什么？
- [ ] ASR 和 KWS 有什么区别？
- [ ] Sherpa-ONNX 是什么？
- [ ] Encoder / Decoder / Joiner 在项目中是什么？
- [ ] LLM 和 VLM 有什么区别？
- [ ] Qwen3-VL 为什么有 `.rknn` 和 `.rkllm` 两个主要模型？
- [ ] RKNN 和 RKLLM 分别是什么？
- [ ] W8A8 表示什么？
- [ ] `max_new_tokens` 为什么会影响语音助手延迟？
- [ ] Matcha-TTS 和 Vocos 为什么要同时存在？
- [ ] 什么是 ALSA underrun？
- [ ] Orchestrator 为什么不是模型？
- [ ] IntentRouter 为什么不能只用关键词包含判断？
- [ ] Unit Test、Integration Test、Mock、Regression Test 有什么区别？
- [ ] Process、Thread、PID、PPID 是什么？
- [ ] Zombie 是怎么产生的？
- [ ] `waitpid()` 为什么能解决 Zombie？
- [ ] FD 是什么？
- [ ] RSS 增长为什么不一定就是内存泄漏？
- [ ] Soak Test 为什么有意义？
- [ ] 能否完整画出项目数据流？
- [ ] 能否完整画出软硬件分层？
- [ ] 能否完整解释 Qwen demo Zombie 的定位过程？
- [ ] 能否用 3～5 分钟独立介绍整个项目？

---

# 25. 当前结论

项目开发阶段已经基本结束。

后续主线正式变为：

```text
学习
↓
理解
↓
代码阅读
↓
实验复盘
↓
系统架构理解
↓
面试表达
```

不再以“增加实验编号”为目标。

最终希望达到：

> 不依赖实验脚本和已有总结，也能够自己从硬件、Linux、Runtime、模型、业务逻辑、测试和进程生命周期几个层面解释整个 RK3588 端侧多模态语音助手项目。

---

# 26. 下一步

正式开始：

```text
第 0 章
项目全局认识
```

第一阶段先回答：

```text
1. 这个项目本质上是什么？
2. 从用户说话到系统回答，到底经过了哪些步骤？
3. RK3588 中 CPU / NPU / DDR / 外设分别参与了什么？
4. Linux、Runtime、模型、Python 应用之间是什么关系？
```

在第 0 章建立正确的大地图后，再进入 Linux / CLI / Git 的基础学习。
