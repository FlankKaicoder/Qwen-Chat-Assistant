# RK3588 端侧多模态智能语音助手——深入学习路线（项目驱动版）

> 项目：RK3588 端侧多模态智能语音助手系统  
> 平台：LubanCat / RK3588  
> 仓库：`FlankKaicoder/Qwen-Chat-Assistant`  
> 项目目录：`/home/cat/ai/qwen3vl2b`  
> 实验范围：Exp00～Exp12  
> 学习定位：**不再从零基础概念逐项讲起，而是以已经完成的项目为主线，深入理解代码、Runtime、数据流、进程生命周期、性能与工程问题。基础概念在实际学习中遇到不懂时再单独补充。**

---

# 1. 学习目标重新定义

前一版路线偏向“从零开始补基础”，会花较多时间解释：

```text
Terminal
Shell
CLI
Python class
module
process
文件系统
```

这些内容不再作为独立主章节。

新版路线假设已经具备：

```text
基本 Linux 命令使用能力
基本 Python 阅读能力
基本 Git 使用能力
基本 RK3588 / NPU / DDR 概念
基本深度学习与模型推理知识
```

后续学习重点改成：

```text
项目代码到底怎么组织
→ 每个模块到底调用了什么
→ 数据到底怎么流动
→ 模型与 Runtime 到底怎么配合
→ CPU / NPU / DDR 分别参与什么
→ 外部 Linux 进程是如何被 Python 管理的
→ 为什么实验中会出现那些故障
→ 当时为什么那样定位
→ 修复为什么有效
→ 如果面试官继续追问，应该能讲到什么深度
```

最终目标不是背实验步骤，而是达到：

> **能够脱离实验文档，从代码、Runtime、Linux 系统和模型推理四个角度，独立解释整个项目。**

---

# 2. 学习方法

新版学习过程统一采用下面的结构。

每一个主题按照：

```text
① 先看该模块在完整系统中的位置
② 看项目真实代码和调用链
③ 看输入 / 输出数据格式
④ 看 Runtime / 系统调用 / 子进程关系
⑤ 对照已经完成的实验
⑥ 复盘真实出现过的故障
⑦ 分析根因与修复
⑧ 总结可迁移的工程经验
⑨ 最后形成面试表达
```

不再默认每个概念都从定义讲起。

遇到不熟悉的概念，例如：

```text
PTY
waitpid
mmap
RKNPU context
Transducer joiner
Vocoder
ALSA underrun
RSS
Mock patch target
```

再单独停下来深入补充。

---

# 3. 学习总路线

新版路线分为 11 个核心章节。

```text
第 0 章  项目架构与实验演进快速复盘

第 1 章  仓库代码结构与完整调用链

第 2 章  音频输入、KWS 与 ASR 推理链

第 3 章  摄像头、V4L2、NV12 与图像输入链

第 4 章  Qwen3-VL、RKNN、RKLLM 与端侧推理 Runtime

第 5 章  TTS、Vocos、PCM 与音频播放链

第 6 章  VoiceAssistant / ControlledSession / 状态机与系统编排

第 7 章  IntentRouter、Prompt 与请求级推理控制

第 8 章  Linux 子进程、pexpect、timeout、进程组与 Zombie

第 9 章  自动化测试、Mock、回归测试与可观测性

第 10 章 多轮稳定性、Soak Test、性能与资源分析

第 11 章 Exp00～Exp12 反向复盘 + 完整架构 + 面试表达
```

学习顺序不再按照“Linux基础→Python基础→外设”展开，而是按照项目真实架构展开。

---

# 4. 第 0 章：项目架构与实验演进快速复盘

## 4.1 目标

这一章只进行一次快速校准，不再详细讲基础概念。

最终需要重新建立三张图：

### 业务数据流

```text
KWS
 ↓
命令录音
 ↓
ASR
 ↓
IntentRouter
     ├─ Text
     │   ↓
     │  Qwen
     │
     └─ Visual
         ↓
       Camera
         ↓
       Qwen3-VL
          ↓
        Answer
          ↓
         TTS
          ↓
       Speaker
```

### 软件调用层

```text
voice_assistant.py
        ↓
      cli.py
        ↓
controlled_session.py / orchestrator.py
        ↓
 ┌──────┼─────────┬──────────┬─────────┐
wake.py asr.py camera.py qwen_runner.py tts.py
```

### 运行实体

```text
Python 主进程
│
├── arecord
├── capture-photo.sh
│   ├── v4l2-ctl
│   └── ffmpeg
├── Qwen demo
└── ALSA / PCM 播放相关路径
```

## 4.2 重点

不再讨论“什么是 CPU”“什么是 CLI”这种基础问题。

重点回答：

```text
为什么这个项目不是一个简单 AI Demo？
为什么它需要多个模型和多个 Runtime？
哪些模块运行在 Python 进程内部？
哪些工作由外部 Linux 进程完成？
哪些模块是同步的？
哪些模块涉及异步或流式处理？
```

## 4.3 对应实验

```text
Exp00～Exp12 全部
```

这一章预计快速完成，然后正式进入代码。

---

# 5. 第 1 章：仓库代码结构与完整调用链

这是新版路线真正的起点。

## 5.1 入口分析

重点阅读：

```text
voice_assistant.py
voice_assistant/cli.py
voice_assistant/config.py
```

理解：

```text
命令行参数
→ CLI 分支
→ 配置加载
→ 对应模块初始化
→ 业务函数调用
```

重点追踪入口：

```text
record
stt
wake
kws-file
ask
once
listen
listen-controlled
```

不是为了记命令，而是为了理解不同入口对应的依赖边界。

---

## 5.2 模块依赖关系

重点阅读：

```text
audio_io.py
wake.py
asr.py
camera.py
qwen_runner.py
tts.py
streaming_tts.py
intent.py
orchestrator.py
controlled_session.py
```

最终自己画出：

```text
cli
 ↓
controlled_session
 ↓
VoiceAssistant
 ↓
 ├─ Recorder
 ├─ KWS
 ├─ ASR
 ├─ IntentRouter
 ├─ CameraAdapter
 ├─ QwenRunner
 └─ TTS
```

---

## 5.3 第一类真实工程问题：CLI 重依赖耦合

重点复盘 Exp02、Exp03、Exp04、Exp05 中反复出现的问题：

```text
record / camera / ask 本来只需要某个模块
↓
cli.py 提前 import orchestrator
↓
orchestrator import 所有模块
↓
ASR / Qwen / TTS 等依赖同时被加载
↓
一个无关依赖缺失
↓
本应独立的命令也运行失败
```

深入学习：

```text
Python import 的实际执行行为
模块加载时机
顶层 import 的副作用
lazy import
dependency boundary
lightweight CLI entry
模块解耦
```

这一部分不讲 Python 基础，而是直接结合真实源码。

---

## 5.4 本章最终能力

能够从：

```bash
python voice_assistant.py listen-controlled ...
```

一直追到：

```text
controlled_session
→ VoiceAssistant
→ IntentRouter
→ QwenRunner
→ demo
```

并能解释函数之间的数据参数是怎么传的。

---

# 6. 第 2 章：音频输入、KWS 与 ASR 推理链

这一章把 Exp01、02、04、09 合在一起理解，而不是分散学习。

---

## 6.1 音频数据路径

重点理解项目实际链路：

```text
ES8388
→ ALSA PCM
→ plughw:2,0
→ Stereo S16_LE 16 kHz
→ 左声道抽取
→ gain
→ WAV / samples
→ KWS 或 ASR
```

重点不是解释采样率是什么，而是研究：

```text
为什么项目按 stereo 录制但模型使用单声道？
input_channel=left 在哪里生效？
wake_input_gain 与 asr_input_gain 为什么分开？
为什么对 KWS 和 ASR 使用同一份增益处理可能有问题？
```

---

## 6.2 `plughw` 与音频参数适配

结合实验实际分析：

```text
hw
plughw
ALSA 参数协商
sample rate
channel count
PCM format
```

重点联系 Exp06：

```text
TTS 原始输出 22050 Hz mono
→ ES8388 播放参数安装失败
→ 44100 Hz stereo
→ 播放成功
```

理解“模型输出格式”和“硬件播放格式”之间为什么必须做适配。

---

## 6.3 KWS 深入学习

重点阅读：

```text
wake.py
config/wake_keywords.txt
models.kws.*
```

理解：

```text
KeywordSpotter
streaming chunk
keywords_score
keywords_threshold
tokens
encoder / decoder / joiner
```

重点复盘 Exp09：

```text
为什么 `return_code=0` 不能证明检测到唤醒词？
为什么 stdout 才是真实语义结果？
为什么 ASR 处理后的 WAV 不适合直接拿来做 KWS 样本？
为什么大规模扫参脚本在端侧不合理？
```

---

## 6.4 ASR 深入学习

重点阅读：

```text
asr.py
SherpaAsr
OfflineRecognizer
```

结合实际模型：

```text
Conformer Transducer
encoder
decoder
joiner
tokens.txt
```

理解项目实际推理过程：

```text
waveform
→ feature
→ encoder
→ decoder / joiner
→ token
→ 中文文本
```

重点解释 Exp04 中的：

```text
RTF = 0.0468
```

并进一步理解：

```text
RTF
吞吐
端到端延迟
模型推理时间
录音窗口时间
```

它们不是同一个指标。

---

## 6.5 本章工程问题

重点复盘：

```text
录音峰值 0 dB
KWS/ASR gain 不同
ASR 误识别导致 Intent 误路由
固定时长录音窗口不稳定
KWS 唤醒后录音准备延迟
```

最终目标是能解释：

> ASR 准确率问题为什么会被放大成整个多模态助手的业务错误。

---

# 7. 第 3 章：摄像头、V4L2、NV12 与图像输入链

对应 Exp03、08、09、10。

---

## 7.1 真实图像路径

重点理解：

```text
IMX415 Sensor
→ MIPI CSI
→ Rockchip ISP
→ rkisp_mainpath
→ /dev/video11
→ V4L2
→ NV12
→ FFmpeg
→ JPEG
→ Qwen3-VL
```

这里会结合之前学过的 RK3588 Camera/ISP 知识，不再从 Sensor 是什么讲起。

---

## 7.2 `/dev/video11` 与 V4L2

深入理解：

```text
rkisp_v6
rkisp_mainpath
Video Capture Multiplanar
Streaming
V4L2 buffer
mmap
stream on/off
```

重点分析项目为什么采用：

```bash
v4l2-ctl --stream-mmap
```

而不是在 Python 内部直接实现整套 V4L2 ioctl。

---

## 7.3 NV12 数据布局

不仅计算：

```text
1280 × 720 × 1.5
```

还需要理解：

```text
Y plane
interleaved UV plane
stride
frame size
为什么 ISP 常输出 YUV
为什么模型最终使用 JPEG
```

重点建立：

```text
摄像头格式
≠
AI 模型输入格式
```

之间的转换意识。

---

## 7.4 CameraAdapter 的工程设计

重点阅读：

```text
camera.py
capture-photo.sh
```

追踪：

```text
CameraAdapter.capture()
→ Popen()
→ capture-photo.sh
→ v4l2-ctl
→ ffmpeg
→ 解析 stdout
→ 移动 JPEG
→ 删除 NV12
```

重点理解：

```text
为什么 Python 不直接完成一切？
为什么 Shell 脚本要输出 jpg= / raw=？
临时目录与最终 photo_dir 为什么分开？
```

---

## 7.5 摄像头卡死问题的深度复盘

Exp09 / Exp10 是重点案例。

复盘过程：

```text
完整链路卡住
↓
先拆 CameraAdapter
↓
发现完整 NV12 已经生成
↓
说明 Sensor / ISP / V4L2 主采集已完成
↓
JPEG 没生成
↓
继续隔离 FFmpeg
↓
定位 stdin 等待问题
↓
增加 -nostdin
```

进一步深入：

```text
为什么子进程环境下 stdin 会成为阻塞点？
为什么 timeout 只杀 Python 调起的 Shell 还不一定够？
为什么需要进程组？
为什么需要 start_new_session / killpg？
```

这部分会与第 8 章进程管理再次合流。

---

# 8. 第 4 章：Qwen3-VL、RKNN、RKLLM 与端侧推理 Runtime

这是整个项目最重要的 AI 部署章节。

对应 Exp05、08、10、12。

---

## 8.1 首先区分四个对象

必须明确：

```text
模型本身
RKNN / RKLLM 模型文件
Runtime
demo 可执行程序
Python QwenRunner
```

真实关系：

```text
QwenRunner
→ pexpect
→ demo
→ librknnrt.so / librkllmrt.so
→ RKNN Vision / RKLLM LLM
→ RK3588
```

---

## 8.2 模型资产与 Runtime 资产

结合 Exp05 逐个理解：

```text
demo
imgenc
librknnrt.so
librkllmrt.so
qwen3-vl-2b_vision_rk3588.rknn
qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
```

重点回答：

```text
为什么模型文件存在仍然不能推理？
Runtime 动态库解决什么问题？
LD_LIBRARY_PATH 为什么影响 demo？
ELF 动态链接与模型 Runtime 是什么关系？
```

---

## 8.3 Vision 与 LLM 两部分

深入理解项目中的：

```text
Vision Encoder RKNN
+
LLM RKLLM
```

重点分析：

```text
图片如何编码为视觉特征
视觉 token / image placeholder 如何进入 LLM
文本问答为什么仍使用同一套 Qwen demo
VLM 与纯文本 LLM 在调用层面的区别
```

这里会明确区分：

```text
项目实际验证到什么
```

与：

```text
Qwen3-VL 架构理论知识
```

避免把理论推断写成项目实测事实。

---

## 8.4 RKNN / RKLLM 与 CPU / NPU / DDR

结合已经学过的 RKNN SDK 知识，重点研究：

```text
模型文件从存储加载
→ Runtime context
→ DDR
→ 输入 tensor
→ NPU / CPU 执行
→ 中间 buffer
→ output
```

进一步讨论：

```text
rknn_core_num=3 到底控制什么
三个 NPU core 与三份模型 context 是否是一回事
权重 / activation / internal tensor 如何理解
为什么端侧大模型性能受 DDR 带宽和访存影响
```

---

## 8.5 W8A8 的正确项目表述

项目中使用：

```text
qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
```

学习中可以深入理解：

```text
W8A8
权重量化
激活量化
scale / zero point
量化对存储、带宽、计算的影响
```

但必须保持项目事实边界：

> **当前实验资料证明的是“使用了现成 W8A8 RKLLM 模型”，不能描述成“本项目自行完成了 Qwen 的 W8A8 量化”。**

---

## 8.6 QwenRunner

重点阅读：

```text
qwen_runner.py
```

深入理解：

```text
pexpect.spawn
PTY
expect
user:
robot:
交互式 demo
clean answer
child close
```

Exp12 的 Zombie 问题会从这里自然引出。

---

## 8.7 请求级 max_new_tokens

重点复盘 Exp10：

```text
Prompt 要求 80 字
但 max_new_tokens=2048
→ 实际回答 928 字
```

然后代码改造：

```text
CLI
→ ControlledSession
→ VoiceAssistant
→ QwenRunner.ask()
→ _spawn()
→ demo max_new_tokens
```

理解：

```text
Prompt 约束
vs
生成参数约束
```

以及为什么请求级参数比直接改全局 YAML 更合理。

---

## 8.8 性能分析

结合 Exp10：

```text
Qwen 62.528 s
→ 请求级 128 tokens
→ 约 12 s
```

深入分析：

```text
首 token 延迟
prefill
decode
生成 token 数
视觉 encoder
LLM decode
总 pipeline latency
```

资料没有实测拆分的数据，需要明确哪些属于理论分析。

---

# 9. 第 5 章：TTS、Vocos、PCM 与音频播放链

对应 Exp06、07。

---

## 9.1 TTS 模型链

理解实际流程：

```text
Chinese Text
→ Matcha-TTS
→ acoustic representation
→ Vocos
→ waveform samples
→ PCM
```

重点区分：

```text
声学模型
vocoder
最终 waveform
```

---

## 9.2 Sherpa-ONNX OfflineTts

重点阅读：

```text
tts.py
streaming_tts.py
audio_io.py
```

追踪：

```text
text
→ OfflineTts.generate
→ numpy samples
→ PcmSpeakerStream
→ ALSA
```

---

## 9.3 22050 mono → 44100 stereo

结合 Exp06 实际问题深入分析：

```text
模型输出格式
→ 音频设备支持格式
→ 重采样
→ 声道转换
→ 播放
```

重点理解：

```text
为什么 plughw 仍然可能无法接受某些参数
硬件参数协商
应用端主动适配
```

---

## 9.4 流式 TTS 与 underrun

Exp07 是核心案例。

实验结果：

```text
单独 tts-stream：underrun=0
完整 Qwen 回答单独 tts-stream：underrun=0
once 流式生成 + 流式播放：underrun>0
```

因此问题被定位到：

```text
Qwen 生成节奏
+
TTS 合成节奏
+
ALSA 消费节奏
```

之间的缓冲。

深入学习：

```text
producer-consumer
buffer
PCM period
ALSA underrun
流式系统 backpressure
```

最后理解为什么项目选择：

```text
完整回答生成完
→ 整段 TTS
→ 播放
```

牺牲部分首包延迟，换取稳定性。

---

# 10. 第 6 章：VoiceAssistant / ControlledSession / 状态机与系统编排

对应 Exp07～10。

---

## 10.1 Orchestrator

重点阅读：

```text
orchestrator.py
```

不是学习“Orchestrator 是什么”，而是逐函数追踪：

```text
run_once
run_once_from_text
ask_qwen
capture_photo
TTS
```

看它如何连接：

```text
ASR
IntentRouter
CameraAdapter
QwenRunner
TTS
```

---

## 10.2 ControlledSession

重点阅读：

```text
controlled_session.py
```

分析为什么 Exp09 的脚本式流程最终要变成 Exp10 的正式入口。

状态：

```text
WAIT_WAKE
WAKE_DETECTED
PREPARE_RECORD
RECORDING
ASR
INTENT_DISPATCH
QWEN_PIPELINE_START
QWEN_PIPELINE_DONE
TTS_START
TTS_DONE
COMPLETED
FAILED
```

重点学习：

```text
状态机为什么比一串 if/else 更利于调试
状态日志如何形成可观测性
失败发生在哪个 state 为什么非常重要
```

---

## 10.3 `once`、`listen` 与 `listen-controlled`

对比三个入口设计。

重点回答：

```text
为什么 once 单轮链路能通过但真实使用仍不稳定？
为什么 Exp09 最后采用受控式流程？
ControlledSession 相比原入口增加了哪些工程约束？
```

---

## 10.4 数据流与控制流分离

深入理解：

```text
数据流：
PCM → Text → JPEG → Tensor → Text → PCM

控制流：
Wake → Record → ASR → Intent → Camera/Qwen → TTS
```

明确：

```text
VoiceAssistant / ControlledSession
主要解决控制流

模型 / audio / image
主要构成数据流
```

---

# 11. 第 7 章：IntentRouter、Prompt 与请求级推理控制

对应 Exp10、11。

这是非常值得深入学的一章，因为它体现的不是“AI 模型训练”，而是端侧 AI 产品中的决策逻辑。

---

## 11.1 从错误设计开始

旧逻辑：

```python
any(keyword in text for keyword in photo_keywords)
```

问题：

```text
“几个”
“描述”
“有什么”
“图片”
```

都会导致普通文本误触发 Camera。

分析：

```text
字符串子串规则
召回率
误触发
上下文缺失
规则冲突
```

---

## 11.2 Intent 与 Prompt 解耦

Exp10 关键问题：

```text
原始用户文本
→ 被改写成 Qwen Prompt
→ 再被 IntentRouter 分析
→ Prompt 里的词反而触发 Camera
```

深入理解为什么必须：

```text
先基于原始用户输入判断 Intent
↓
need_photo 固化
↓
再根据 Intent 构造 Prompt
```

以及 `need_photo_override` 的意义。

---

## 11.3 Exp11 正式规则设计

深入学习五类规则：

```text
explicit_capture
direct_visual_command
visual_action + visual_context
text_context_blocker
normal_text
```

重点不是背关键词，而是理解：

```text
规则优先级
显式命令优先
组合语义
阻断规则
可解释调试字段
```

---

## 11.4 monkey patch → 正式实现

复盘：

```text
IntentRouter.analyze = _exp10_strict_analyze
```

为什么实验阶段可快速验证，但不适合长期代码。

理解：

```text
monkey patch
技术债
运行时行为与源码定义不一致
可测试性
维护性
```

---

## 11.5 Prompt 消融

Exp10 发现：

```text
复杂的否定式 Prompt
```

对 2B 模型效果不一定最好。

最终极简：

```text
请简短回答这个问题：<用户问题>
```

效果更稳定。

深入讨论：

```text
模型容量
instruction following
Prompt complexity
generation budget
task-specific prompt
```

---

# 12. 第 8 章：Linux 子进程、pexpect、timeout、进程组与 Zombie

这是项目最能体现 Linux 工程能力的一章。

对应 Exp09、10、12。

---

## 12.1 项目中的进程树

需要实际建立：

```text
Python voice_assistant.py
│
├── arecord
│
├── capture-photo.sh
│   ├── v4l2-ctl
│   └── ffmpeg
│
└── demo
```

分析：

```text
谁是 parent
谁是 child
Shell 为什么还会产生孙进程
```

---

## 12.2 subprocess 生命周期

结合 CameraAdapter：

```text
Popen
communicate
timeout
terminate
kill
returncode
stdout
stderr
```

重点研究：

```text
timeout 并不意味着整个子进程树都会消失
```

---

## 12.3 process group / session

结合 Exp09：

```text
start_new_session=True
os.killpg()
```

理解：

```text
PID
PPID
PGID
SID
```

以及为什么：

```text
只 kill Shell
```

可能留下：

```text
v4l2-ctl / ffmpeg
```

---

## 12.4 pexpect 与 PTY

结合 QwenRunner：

```text
Python
→ pexpect
→ pseudo terminal
→ demo
```

理解：

```text
为什么不是普通 subprocess.run
为什么交互式 demo 需要 expect user:
为什么 PTY close 不等于 wait/reap
```

---

## 12.5 Zombie

Exp12 为核心案例。

真实现象：

```text
demo <defunct>
State: Z
父 Python 不退出时持续存在
```

深入分析 Linux 语义：

```text
child 已退出
↓
内核保留 exit status
↓
parent 尚未 wait
↓
Zombie
```

修复链：

```text
child.close(force=True)
→ waitpid(WNOHANG)
→ 必要时 SIGKILL
→ waitpid(pid, 0)
```

重点理解：

> `close()`、`kill()`、`wait()`、`reap()` 是不同概念。

---

## 12.6 为什么单轮实验发现不了 Zombie

分析：

```text
一次 Python
→ demo Zombie
→ Python 很快退出
→ 系统回收
```

与：

```text
长期 Python
→ demo Zombie
→ parent 一直活着
→ Zombie 累积
```

这也是 Exp12 same-process test 的工程价值。

---

# 13. 第 9 章：自动化测试、Mock、回归测试与可观测性

对应 Exp11、12。

---

## 13.1 单元测试

重点研究：

```text
tests/test_intent_router.py
unittest
positive case
negative case
boundary case
```

理解：

```text
为什么规则代码特别适合单测
为什么硬件链路不应该全部通过真实设备测试
```

---

## 13.2 Mock 集成测试

重点复盘 Exp11 第一次失败：

错误 Mock：

```python
assistant.camera = fake_camera
assistant.qwen = fake_qwen
```

但真实代码调用：

```text
self.capture_photo()
QwenRunner(self.config)
```

导致 Mock 没拦住真实 Camera/Qwen。

深入理解：

> **Mock 要 patch “被测代码实际查找对象的位置”，不是 patch 自己认为应该存在的位置。**

然后分析：

```text
mock target
dependency injection
patch boundary
side effect
```

---

## 13.3 回归测试

理解 Exp11 为什么重构 IntentRouter 后必须同时验证：

```text
unit test
mock integration
real text
real vision
KWS/ASR/Qwen/TTS full chain
```

形成测试金字塔意识。

---

## 13.4 可观测性

结合 ControlledSession / Exp12：

```text
summary.json
state.log
recognized_text.txt
intent_debug.json
qwen_prompt.txt
qwen_answer.txt
audio_stats.json
```

理解：

```text
日志不是“保存越多越好”
而是每层必须能回答一个诊断问题
```

例如：

```text
ASR 是否正确？
Intent 是否正确？
是否拍照？
Prompt 是什么？
Qwen 花了多久？
TTS 花了多久？
是否有残留进程？
```

---

# 14. 第 10 章：多轮稳定性、Soak Test、性能与资源分析

对应 Exp12。

---

## 14.1 为什么单轮 PASS 不够

分析：

```text
单轮测试
→ Python 退出
→ OS 自动回收资源
```

所以可能隐藏：

```text
FD leak
thread leak
Zombie
RSS growth
长期 latency degradation
```

---

## 14.2 Same-process Test

重点学习：

```text
一个 Python
一个 VoiceAssistant
连续 10 轮
```

监控：

```text
RSS
FD
Thread
residual process
photo count
latency
temperature
```

理解为什么同进程测试比重复启动 CLI 更能发现生命周期问题。

---

## 14.3 Soak Test

分析 40 轮：

```text
20 visual
20 text
```

重点不是“40”这个数字，而是学习：

```text
warm-up
steady state
early window
late window
趋势
漂移
异常值
```

---

## 14.4 RSS 不等于泄漏

深入分析：

```text
RSS 初期增长
≠
必然 memory leak
```

需要结合：

```text
是否单调增长
FD 是否增加
thread 是否增加
子进程是否残留
后期是否进入平台区
```

一起判断。

---

## 14.5 性能拆解

最终建立一个延迟模型：

```text
Total latency
=
Wake
+ Record
+ ASR
+ Camera(optional)
+ Vision
+ LLM
+ TTS
+ Playback
```

结合 Exp10/12 的日志，分析哪个阶段真正占主要时间。

并区分：

```text
算法性能
模型性能
Runtime 性能
I/O 性能
业务等待时间
```

---

# 15. 第 11 章：Exp00～Exp12 反向复盘

到这里再按照实验顺序重新看项目。

这一次不再学习“实验做了什么”，而是回答：

```text
为什么当时必须先做这个实验？
它隔离了哪个变量？
当时的 PASS Gate 是什么？
出现了什么错误判断？
为什么后续实验推翻或修正了前面的实现？
这个实验留下了什么长期代码？
什么只是临时脚本？
```

---

## 15.1 Exp00～03：硬件与基础 I/O

复盘：

```text
环境 / asset
音频
录音
Camera
```

重点：

```text
如何建立可靠 baseline
为什么先证明 hardware / I/O，再碰 AI 模型
```

---

## 15.2 Exp04～06：三个模型链独立验证

```text
ASR
Qwen
TTS
```

重点：

```text
模型能力独立验证
Runtime 资产
输入输出格式
最小可验证链路
```

---

## 15.3 Exp07～09：模块串联

```text
ASR → Qwen → TTS
Camera → Qwen → TTS
KWS → ASR → Camera → Qwen → TTS
```

重点：

```text
为什么模块独立通过后，串联仍会出现新问题？
```

典型：

```text
underrun
ASR 误识别
Camera timeout
进程残留
```

---

## 15.4 Exp10：工程化

重点：

```text
正式入口
状态机
日志
max_new_tokens
Prompt
Intent
Camera 稳定性
性能
```

这是从 Demo 到 Application 的转折点。

---

## 15.5 Exp11：代码质量

重点：

```text
重构
配置化
单元测试
Mock
Regression
```

---

## 15.6 Exp12：系统稳定性

重点：

```text
same-process
Zombie
waitpid
RSS/FD/thread
40-round soak test
test harness validity
```

---

# 16. 学习过程中必须明确的“项目事实边界”

后续所有讲解都需要严格区分：

## 项目确实做过

例如：

```text
在 RK3588 上部署并运行现成的 Qwen3-VL RKNN/RKLLM 模型
使用 W8A8 RKLLM 模型资产
集成 Sherpa-ONNX KWS / ASR / TTS
使用 V4L2 / FFmpeg 进行 Camera 采集
重构 IntentRouter
编写单元测试 / Mock 集成测试
定位并修复 Zombie
完成 40 轮 soak test
```

## 项目没有证明做过

不能说：

```text
自行完成 Qwen W8A8 量化
自行完成 RKNN 模型转换
自定义 RKNN 算子
修改 NPU kernel driver
进行编译器图优化
修改 RKLLM Runtime
完成模型训练 / 微调
```

这些可以作为理论扩展学习，但不能混入项目实际成果。

---

# 17. 最终需要掌握的 6 张图

新版路线结束后，需要能不看资料画出：

## 17.1 业务数据流图

```text
Mic
→ KWS
→ ASR
→ Intent
→ Text / Camera
→ Qwen
→ TTS
→ Speaker
```

## 17.2 Python 调用图

```text
CLI
→ ControlledSession
→ VoiceAssistant
→ 各模块
```

## 17.3 进程树

```text
Python
├─ arecord
├─ capture-photo.sh
│  ├─ v4l2-ctl
│  └─ ffmpeg
└─ demo
```

## 17.4 Qwen Runtime 图

```text
QwenRunner
→ pexpect / PTY
→ demo
→ RKNN / RKLLM Runtime
→ Model
→ RK3588
```

## 17.5 Camera 数据流图

```text
Sensor
→ CSI
→ ISP
→ NV12
→ DDR
→ V4L2
→ FFmpeg
→ JPEG
→ Qwen3-VL
```

## 17.6 稳定性监控图

```text
Long-running Python
│
├─ RSS
├─ FD
├─ Threads
├─ Process State
├─ Temperature
├─ Latency
└─ Route / Photo correctness
```

---

# 18. 最终面试掌握层级

学习完成后，每个模块至少达到三层表达能力。

## 第一层：30 秒说明

例如：

> 项目使用 Sherpa-ONNX 完成 KWS、ASR 和 TTS，使用 V4L2 采集摄像头画面，通过 RKNN/RKLLM Runtime 在 RK3588 上运行 Qwen3-VL，并由 Python Orchestrator 完成文本/视觉意图分流和完整语音交互。

## 第二层：2～3 分钟技术展开

能够讲：

```text
真实代码结构
数据格式
Runtime
关键配置
一次调用如何执行
```

## 第三层：追问与故障

能够解释：

```text
为什么 ASR 会影响 Intent
为什么 Prompt 限长不可靠
为什么 FFmpeg 会卡
为什么 streaming TTS 会 underrun
为什么错误 Mock 会调用真实硬件
为什么 demo 会 Zombie
为什么 waitpid 能解决
为什么 RSS 上升不一定是 leak
```

第三层才是这个项目真正能够体现工程能力的部分。

---

# 19. 推荐实际学习顺序

正式学习时按照：

```text
0. 项目快速校准
   ↓
1. 仓库代码调用链
   ↓
2. Audio + KWS + ASR
   ↓
3. Camera + V4L2 + NV12
   ↓
4. Qwen3-VL + RKNN/RKLLM Runtime
   ↓
5. TTS + Playback
   ↓
6. Orchestrator + ControlledSession
   ↓
7. IntentRouter + Prompt + max_new_tokens
   ↓
8. subprocess + pexpect + Zombie
   ↓
9. Unit Test + Mock + Regression
   ↓
10. Same-process + Soak + Performance
   ↓
11. Exp00～12 反向复盘
   ↓
完整项目白板讲解
   ↓
简历 / 面试表达
```

---

# 20. 后续讲解方式

从本路线开始，默认不再对已经明显掌握的基础概念展开大量解释。

每一节优先：

```text
真实代码
→ 真实调用链
→ 真实数据
→ 真实 Runtime
→ 真实实验问题
```

如果学习过程中对某个基础点不理解，再单独暂停，例如：

```text
“waitpid 具体是什么意思？”
“PTY 和普通 pipe 有什么区别？”
“joiner 为什么存在？”
“NV12 的 UV 到底怎么排列？”
“为什么 RKNN 三核不等于三份独立模型？”
```

再针对该问题进行深入补充。

这样既不会把时间花在已经会的基础知识上，也不会跳过真正影响项目理解的底层机制。

---

# 21. 当前起点

新版路线正式学习的第一章为：

> **第 1 章：仓库代码结构与完整调用链**

第一阶段不会再解释 CLI 是什么，而是直接从：

```text
voice_assistant.py
→ cli.py
→ controlled_session.py
→ orchestrator.py
```

开始追踪。

随后会选两条真实调用链：

```text
文本链路：
listen-controlled
→ KWS
→ ASR
→ IntentRouter
→ QwenRunner
→ TTS
```

以及：

```text
视觉链路：
listen-controlled
→ KWS
→ ASR
→ IntentRouter
→ CameraAdapter
→ QwenRunner
→ TTS
```

作为整个深入学习阶段的代码主线。
