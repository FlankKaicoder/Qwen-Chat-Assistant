# 实验 10：受控式多模态语音助手工程化、短回答优化与文本/视觉双链路验证

> 项目：RK3588 端侧多模态智能语音助手系统  
> 平台：LubanCat / RK3588  
> 仓库目录：`/home/cat/ai/qwen3vl2b`  
> 实验编号：10  
> 实验主题：受控式 KWS 交互入口、阶段耗时统计、请求级生成长度控制、摄像头阻塞修复、视觉意图路由重构、文本/视觉双链路完整验证  
> 实验状态：**文本与视觉两条受控式完整语音链路均通过；连续多轮稳定性验证与临时代码重构尚未完成**  
> 记录日期：2026-08-02

---

## 1. 实验背景

实验 09 已经验证了如下受控式视觉问答主链路：

```text
KWS 唤醒“鲁班猫”
  -> 受控录音
  -> Sherpa-ONNX ASR
  -> 拍照意图判断
  -> CameraAdapter 拍照
  -> Qwen3-VL 图文推理
  -> TTS 合成播放
```

实验 09 的最终结论是：

```text
核心模块能力已经成立；
受控式 KWS + 视觉问答链路能够完整运行；
官方 once/listen 入口仍存在录音交互窗口不稳定问题；
CameraAdapter 已增加进程组级 timeout 和残留进程清理。
```

但是实验 09 的最终链路仍存在明显的工程问题：

```text
1. 受控式流程仍然是实验脚本，没有形成正式 CLI；
2. Qwen 回答过长，视觉回答可达到 900 字以上；
3. Qwen 推理和 TTS 播放耗时过高；
4. 仅依靠 Prompt 限制回答长度不稳定；
5. 摄像头偶发卡在 NV12 转 JPEG 阶段；
6. 文本 Prompt 可能被 IntentRouter 再次分析并误触发拍照；
7. photo_keywords 中存在“字”“几个”“描述”等过宽关键词；
8. 小参数量模型对复杂、否定式 Prompt 非常敏感；
9. 尚未分别验证“普通文本问答”和“视觉问答”两条正式业务链路。
```

因此实验 10 不再只是证明模块“能够运行”，而是进一步完成：

```text
实验脚本
  -> 正式受控式 CLI
  -> 可观测状态机
  -> 分阶段耗时统计
  -> 请求级生成长度控制
  -> 稳定摄像头采集
  -> 正确意图路由
  -> 简短视觉回答
  -> 简短文本回答
  -> 文本与视觉两条完整 TTS 闭环
```

实验 10 是整个 RK3588 多模态语音助手从“链路复现”走向“可演示工程入口”的关键实验。

---

## 2. 实验目标

实验 10 主要回答以下问题：

```text
1. 能否将实验 09 的受控式流程封装成正式 listen-controlled CLI；
2. 能否明确记录 WAIT_WAKE、RECORDING、ASR、QWEN、TTS 等阶段状态；
3. 能否统计 Qwen、TTS 和完整链路的阶段耗时；
4. Prompt 中要求“80 个汉字以内”是否真的能限制模型输出；
5. QwenRunner 能否支持请求级 max_new_tokens，而不修改全局配置；
6. 视觉回答能否从 900 字以上压缩到一至两句；
7. 摄像头超时究竟发生在 V4L2 采集还是 FFmpeg 转换阶段；
8. 如何修复 FFmpeg 在子进程环境中等待标准输入导致的卡死；
9. 如何避免普通文本问题被 Prompt 模板或宽泛关键词误判为拍照；
10. 如何将原始用户意图判断与重写后的 Qwen Prompt 解耦；
11. 2B 量级模型适合什么样的普通问答 Prompt；
12. 最终能否分别跑通视觉语音闭环和文本语音闭环；
13. 完成后是否能够保证无 underrun、无残留子进程。
```

---

## 3. 实验前系统状态

### 3.1 项目路径

```text
/home/cat/ai/qwen3vl2b
```

### 3.2 硬件与外设

```text
平台       : LubanCat / RK3588
摄像头     : IMX415
视频设备   : /dev/video11
麦克风设备 : plughw:2,0
播放设备   : plughw:2,0
```

### 3.3 主要模型与组件

```text
KWS  : Sherpa-ONNX Zipformer Keyword Spotter
ASR  : sherpa-onnx-conformer-zh-stateless2-2023-05-23
VLM  : Qwen3-VL-2B Vision RKNN
LLM  : Qwen3-VL-2B-Instruct W8A8 RKLLM
TTS  : Sherpa-ONNX Matcha-TTS + Vocos
Camera: V4L2 + NV12 + FFmpeg JPEG
```

### 3.4 Qwen 初始配置

实验开始时，`config/default.yaml` 中的主要生成参数为：

```text
max_new_tokens : 2048
max_context_len: 4096
rknn_core_num  : 3
```

这意味着，即使上层 Prompt 写了“回答不超过 80 个汉字”，底层 demo 仍允许生成最多 2048 个 token。

---

## 4. 实验 10 总体流程

实验 10 实际经历了多个阶段，主要过程如下：

| 阶段 | 内容 | 结果 |
|---|---|---|
| 10.0 | 受控入口开发前基线检查 | 通过 |
| 10.1 | 新增 `listen-controlled` 与状态日志 | 初次受 Python 环境影响 |
| 10.1b | 使用项目虚拟环境重新验证受控入口 | 通过 |
| 10.2 | 增加阶段耗时与 concise 模式 | 功能加入 |
| 10.2b | 仅依赖 Prompt 限制回答长度 | 失败，仍输出 928 字 |
| 10.2d | 打通请求级 `max_new_tokens` | 通过 |
| 10.2e | 128 tokens、关闭 TTS 的快速验证 | 性能通过，视觉语义失败 |
| 10.2f | 增加视觉专用 Prompt | 代码完成，摄像头超时 |
| 10.2f-a | 三次摄像头隔离测试 | NV12 正常，JPEG 未生成 |
| 10.2f-b | NV12 -> JPEG 隔离定位 | 确认 FFmpeg 需要 `-nostdin` |
| 10.2f-c | 修复 `capture-photo.sh` 并三次复测 | 3/3 通过 |
| 10.2f-d | 重新执行语音视觉测试 | ASR 误识别，本轮无效 |
| 10.2f-e | 绕过 ASR，直接视觉简短问答 | 通过 |
| 10.2g | KWS + ASR + 视觉 + TTS 完整闭环 | 通过 |
| 10.3 | 普通文本问答完整闭环初测 | 误触发摄像头，失败 |
| 10.3a | 意图路由与 Qwen Prompt 解耦 | 通过 |
| 10.3b | 直接文本问答 | 不拍照，但语义失败 |
| 10.3d | 身份与算术双问题验证 | 身份通过，算术失败 |
| 10.3e 系列 | Prompt 拆分、关键词清理 | 多轮修正 |
| 10.3e-v4 | 严格视觉意图策略 | 通过 |
| 10.3e-v3 复测 | 删除“字”并应用 Prompt 拆分 | 通过 |
| 10.3g | 普通问答 Prompt 消融 | 极简自然问句方案最佳 |
| 10.3h | 将极简普通问答 Prompt 写入正式代码 | 通过 |
| 10.3f 最终复测 | 身份与算术双问题 | 两项均通过 |
| 10.3 final | KWS + ASR + 文本 Qwen + TTS | 通过 |

---

## 5. 最终受控式入口设计

实验 10 新增了正式受控式入口：

```bash
python voice_assistant.py listen-controlled
```

核心实现文件：

```text
voice_assistant/controlled_session.py
```

该入口将实验 09 中分散的受控流程整合为一个状态明确、可记录、可回归的单轮会话。

### 5.1 状态机

受控式会话主要状态如下：

```text
WAIT_WAKE
  -> WAKE_DETECTED
  -> PREPARE_RECORD
  -> RECORDING
  -> ASR
  -> INTENT_DISPATCH
  -> QWEN_PIPELINE_START
  -> QWEN_PIPELINE_DONE
  -> TTS_START / TTS_SKIPPED
  -> TTS_DONE
  -> COMPLETED
```

失败时可以记录：

```text
FAILED
error
exit_code
```

### 5.2 主要输出文件

每次运行保存独立输出目录，包括：

```text
summary.txt
summary.json
state.log
command.wav
recognized_text.txt
intent_debug.json
qwen_prompt.txt
qwen_answer.txt
audio_stats.json
```

这些文件使每次测试都可以回答：

```text
唤醒词是否命中；
录音音量是否正常；
ASR 识别了什么；
原始意图是否需要拍照；
实际 Prompt 是什么；
Qwen 回答有多长；
Qwen/TTS 各耗时多少；
是否生成新照片；
最终是否成功；
是否存在残留进程。
```

---

## 6. 10.0：开发前基线检查

实验 10.0 检查了以下内容：

```text
1. 核心源码文件是否存在；
2. Python 文件是否能够编译；
3. VoiceAssistant 是否可以初始化；
4. 实验 07 的“完整回答后整段 TTS”修复是否仍然存在；
5. CameraAdapter 是否保留 Popen(start_new_session=True)；
6. 是否保留 communicate(timeout=...)；
7. 是否保留 os.killpg() 进程组清理；
8. 拍照默认参数是否为 1280x720、skip=5；
9. 系统中是否存在残留的 Qwen、v4l2-ctl、ffmpeg 等进程。
```

结果：

```text
核心文件存在；
Python compile/import/init 均成功；
完整回答 TTS 逻辑存在；
CameraAdapter 进程组 timeout 存在；
摄像头参数为 1280x720、skip=5；
无残留进程。
```

结论：实验 10 可以在实验 09 的稳定版本上继续开发。

---

## 7. 10.1：新增 `listen-controlled`

### 7.1 设计目的

实验 09 的受控流程仍依赖多个外部命令。实验 10.1 将其封装为正式入口：

```text
KWS
  -> 固定准备延迟
  -> 固定时长录音
  -> ASR
  -> 原始意图判断
  -> Qwen/视觉处理
  -> TTS
```

### 7.2 首次运行失败：Python 环境不一致

初次实时验证失败，并不是代码逻辑问题，而是测试脚本调用了系统 Python：

```text
python3
```

但 `sherpa_onnx` 等依赖位于项目虚拟环境或本地包目录：

```text
.venv/bin/python
.python_packages
```

因此系统 Python 无法加载完整依赖。

### 7.3 修复

后续所有实验统一使用：

```bash
/home/cat/ai/qwen3vl2b/.venv/bin/python
```

并设置：

```bash
export PYTHONPATH="$PWD:$PWD/.python_packages${PYTHONPATH:+:$PYTHONPATH}"
```

### 7.4 10.1b 实时受控入口通过

代表结果：

```text
wake_text       : 鲁班猫
recognized_text : 拍照看一下画面
mean_volume     : -31.306 dBFS
max_volume      : -4.745 dBFS
new_photo_count : 1
qwen_answer_chars: 917
elapsed_seconds : 138.853
underrun_count  : 0
residual_process: 0
```

结论：

```text
listen-controlled 入口本身能够完整运行；
主要问题已经从“链路是否可用”转变为“回答和耗时是否可接受”。
```

---

## 8. 10.2：增加阶段耗时与简短回答模式

实验 10.2 增加了：

```text
answer_mode
answer_max_chars
qwen_max_new_tokens
pipeline_elapsed_seconds
tts_elapsed_seconds
total elapsed_seconds
```

目标是将原本很长的视觉回答压缩为适合语音播报的一至两句。

### 8.1 concise 模式初始 Prompt

普通简短回答 Prompt 大致为：

```text
你是端侧语音助手。
必须只输出最终答案，不要解释分析过程，
不要使用标题、列表或分点。
请用一到两句中文直接回答，
尽量控制在 80 个汉字以内。
```

### 8.2 10.2b：仅依赖 Prompt 限长失败

虽然 Prompt 明确要求 80 个汉字以内，实际结果仍然是：

```text
answer_chars               : 928
pipeline_elapsed_seconds   : 62.528
tts_elapsed_seconds        : 47.853
total_elapsed_seconds      : 120.921
```

说明：

```text
Prompt 只能表达生成偏好；
它不是底层生成上限；
小模型不一定稳定遵守自然语言中的字数约束。
```

---

## 9. 请求级 `max_new_tokens` 改造

### 9.1 根因定位

源码检查发现：

```text
QwenRunner._spawn()
```

固定使用：

```text
self.qwen["max_new_tokens"]
```

即配置文件中的：

```text
2048
```

上层任何“80 个汉字以内”的要求都不会改变底层 token 上限。

### 9.2 调用链改造

实验 10.2d 将请求级生成长度贯通到完整调用链：

```text
listen-controlled CLI
  -> controlled_session
  -> VoiceAssistant.run_once_from_text()
  -> VoiceAssistant.ask_qwen()
  -> QwenRunner.ask()
  -> QwenRunner._spawn()
  -> Qwen demo --max_new_tokens
```

新增参数：

```text
max_new_tokens
concise_max_new_tokens
```

策略：

```text
普通模式保留全局 2048；
concise 模式使用请求级 128；
后续算术 Prompt 消融可进一步使用 32。
```

### 9.3 设计意义

这种方式避免了直接修改全局配置：

```text
长回答任务仍可使用 2048；
语音播报任务可以使用 128；
单次请求可以独立控制生成预算。
```

这属于比单纯修改 Prompt 更可靠的推理阶段控制。

---

## 10. 10.2e：128 tokens 快速验证

关闭 TTS，仅验证 Qwen 阶段：

```text
qwen_max_new_tokens       : 128
pipeline_elapsed_seconds  : 11.019
answer_chars              : 34
```

性能明显改善，但回答为：

```text
我无法提供具体答案，因为图像信息不完整。请提供更多上下文或问题细节。
```

该结果说明：

```text
请求级 token 限制已经生效；
推理耗时显著下降；
但是通用 Prompt 没有充分告诉模型应直接使用当前摄像头图片；
视觉回答语义仍然不合格。
```

---

## 11. 视觉专用 Prompt

实验 10.2f 为视觉任务单独设计 Prompt：

```text
请根据当前摄像头拍摄的图片，
直接描述画面中最主要的人物、物体和场景。
只输出一到两句中文结论，
不要解释推理过程，
不要使用标题、列表或分点，
不要说无法查看图片，
尽量控制在 80 个汉字以内。
```

设计原则：

```text
1. 明确说明输入是“当前摄像头拍摄的图片”；
2. 明确要求描述人物、物体和场景；
3. 避免模型回答“无法查看图片”；
4. 保留一到两句和 80 字左右的长度约束；
5. 配合 max_new_tokens=128。
```

代码完成后，实时测试却在摄像头阶段超时，因此进入摄像头隔离排查。

---

## 12. 摄像头超时问题

### 12.1 10.2f-a：连续三次摄像头隔离

三次执行均出现：

```text
capture timeout: 45 seconds
```

但每一次都生成了完整原始帧：

```text
NV12 文件大小: 1382400 bytes
```

对于 1280×720 NV12：

```text
1280 × 720 × 1.5 = 1382400 bytes
```

内核日志也显示摄像头完成了：

```text
stream on
stream off
```

同时：

```text
无 JPG；
无残留 v4l2-ctl；
无残留 ffmpeg；
stderr 为 <<<<<<。
```

其中：

```text
<<<<<<
```

表示 `v4l2-ctl` 跳过 5 帧并保存 1 帧的进度，不是报错。

### 12.2 阶段性结论

根据完整 NV12 文件和 stream on/off 可以排除：

```text
摄像头设备不可用；
V4L2 无法采集；
ISP 没有输出；
分辨率或像素格式错误。
```

问题已经收敛到：

```text
NV12 原始帧采集成功之后，
FFmpeg 将 NV12 转为 JPEG 的阶段发生阻塞。
```

---

## 13. 10.2f-b：NV12 转 JPEG 隔离实验

使用已经保存的 1382400 字节 NV12 文件，不再访问摄像头，分别测试：

```text
1. 原始 FFmpeg 命令；
2. FFmpeg + -nostdin；
3. OpenCV 转换。
```

结果：

```text
expected_size             : 1382400
actual_size               : 1382400

original_return_code      : 124
original_elapsed_seconds  : 15
original_jpg_exists       : 0

nostdin_return_code       : 0
nostdin_elapsed_seconds   : 0
nostdin_jpg_exists        : 1

opencv_return_code        : 0
opencv_jpg_exists         : 1
```

输出文件：

```text
nostdin.jpg : 167 KB
opencv.jpg  : 302 KB
source.nv12 : 1.4 MB
```

### 13.1 根因

原始 FFmpeg 子进程在当前调用环境中会等待标准输入，导致：

```text
图像转换已经具备完成条件；
但进程不退出；
外层 CameraAdapter 等待；
最终触发 timeout。
```

增加：

```bash
-nostdin
```

后 FFmpeg 立即完成。

### 13.2 修复

`capture-photo.sh` 的 FFmpeg 调用增加：

```bash
ffmpeg \
  -nostdin \
  -hide_banner \
  -loglevel error \
  -y \
  ...
```

同时增加：

```text
转换阶段 timeout；
独立 FFmpeg stderr；
失败时输出 raw_path、jpg_path 和 return code；
成功后删除临时 stderr。
```

---

## 14. 10.2f-c：修复后摄像头三次稳定性验证

修复后连续三次拍照：

```text
capture_total          : 3
capture_pass_count     : 3
capture_fail_count     : 0
capture_timeout_count  : 0
residual_process_count : 0
```

每次结果：

```text
capture_return_code: 0
elapsed_seconds    : 1
codec_name         : mjpeg
width              : 1280
height             : 720
pix_fmt            : yuvj420p
```

结论：

```text
V4L2 采集稳定；
NV12 原始帧完整；
FFmpeg -nostdin 修复有效；
JPEG 转换稳定；
连续三次无超时；
无残留子进程。
```

本阶段没有立即加入重试机制，因为根因已经是确定性的 FFmpeg 标准输入阻塞。直接修复根因比用重试掩盖问题更合理。

---

## 15. 10.2f-d：一次无效的语音视觉测试

摄像头修复后重新运行完整语音视觉测试，ASR 结果为：

```text
recognized_text : 冲
```

音量：

```text
mean_volume_dbfs : -40.167
max_volume_dbfs  : -22.906
```

相比正确识别时，录音明显偏小。

虽然本次仍生成了图片并返回了视觉描述，但由于用户原始指令未被正确识别，因此不能用于验证视觉 Prompt。

该轮应判定为：

```text
摄像头修复             : PASS
请求级 128 tokens      : PASS
回答长度               : PASS
ASR                     : FAIL
视觉 Prompt 正确性     : 本轮无效，不能判断
```

此轮同时暴露出另一个问题：

```text
photo_intent_hint : 0
new_photo_count   : 1
```

说明受控会话对原始识别文本判断为非视觉请求，但下层仍然拍照。后续确认这是因为重写后的 Prompt 被 IntentRouter 再次分析。

---

## 16. 10.2f-e：直接视觉简短问答通过

为排除 KWS 和 ASR 干扰，直接执行：

```text
固定视觉 Prompt
  -> 强制拍照
  -> Qwen max_new_tokens=128
  -> 不执行 TTS
```

结果：

```text
status                    : PASSED
qwen_max_new_tokens       : 128
prompt_chars              : 91
answer_chars              : 28
pipeline_elapsed_seconds  : 11.432
new_photo_count           : 1
new_photo_path            : /home/cat/图片/voice_20260802_224629.jpg
```

图片：

```text
codec_name : mjpeg
width      : 1280
height     : 720
pix_fmt    : yuvj420p
```

回答：

```text
一名男子正俯身于一个带有电路板图案的白色设备上进行操作。
```

结论：

```text
视觉专用 Prompt 有效；
请求级 128 tokens 有效；
视觉回答内容正确；
回答长度适合 TTS；
Qwen 阶段约 11 秒；
无残留进程。
```

---

## 17. 10.2g：完整视觉语音闭环通过

完整链路：

```text
KWS
  -> 录音
  -> ASR
  -> 视觉意图
  -> 摄像头拍照
  -> Qwen3-VL 简短回答
  -> TTS 合成与播放
```

结果：

```text
controlled_return_code   : 0
status                   : PASSED
recognized_text          : 来找我看一下画面
photo_intent_hint        : 1
new_photo_count          : 1
qwen_max_new_tokens      : 128
answer_chars             : 34
pipeline_elapsed_seconds : 12.001
tts_elapsed_seconds      : 12.285
total_elapsed_seconds    : 41.805
underrun_count           : 0
bad_answer_count         : 0
residual_process_count   : 0
```

ASR 将原本预计的：

```text
拍照看一下画面
```

识别为：

```text
来找我看一下画面
```

虽然前半句有误，但“看一下画面”仍满足视觉意图。

图片：

```text
/home/cat/图片/voice_20260802_224948.jpg
1280×720 MJPEG
```

回答：

```text
办公室内，一名戴眼镜的年轻男子坐在办公桌前，手持耳机，正专注地工作。
```

音量：

```text
mean_volume_dbfs : -23.020
max_volume_dbfs  : 0.000
```

本轮出现峰值满幅，存在削波风险，但 ASR、视觉、Qwen 和 TTS 均正常，因此主链路判定通过。

---

## 18. 视觉路线性能优化效果

优化前代表结果：

```text
回答长度 : 928 字
Qwen耗时 : 62.528 秒
TTS耗时  : 47.853 秒
总耗时   : 120.921 秒
```

优化后完整视觉闭环：

```text
回答长度 : 34 字
Qwen耗时 : 12.001 秒
TTS耗时  : 12.285 秒
总耗时   : 41.805 秒
```

变化：

| 指标 | 优化前 | 优化后 | 降幅 |
|---|---:|---:|---:|
| 回答长度 | 928 字 | 34 字 | 96.34% |
| Qwen 阶段 | 62.528 s | 12.001 s | 80.81% |
| TTS 阶段 | 47.853 s | 12.285 s | 74.33% |
| 完整总耗时 | 120.921 s | 41.805 s | 65.43% |

主要优化来源：

```text
1. 请求级 max_new_tokens 从 2048 限制到 128；
2. 通用视觉问答 Prompt 改为摄像头画面专用 Prompt；
3. 回答从长篇分析改为一至两句直接描述；
4. TTS 输入文本显著缩短；
5. 摄像头转换不再因 FFmpeg 标准输入阻塞。
```

---

## 19. 10.3：普通文本问答初测失败

视觉链路通过后，实验 10.3 验证普通文本问答：

```text
KWS
  -> ASR：“你是谁”
  -> 不拍照
  -> Qwen 文本回答
  -> TTS
```

实际结果：

```text
recognized_text         : 你是谁
photo_intent_hint       : 0
new_photo_count         : 1
answer_chars            : 30
pipeline_elapsed_seconds: 11.361
tts_elapsed_seconds     : 10.258
```

回答：

```text
我无法提供具体答案，因为没有足够的信息来确定问题的具体内容。
```

该轮失败有两个问题：

```text
1. 原始文本意图是非视觉，但实际仍然拍照；
2. 文本回答语义不正确。
```

---

## 20. Prompt 导致意图误触发

### 20.1 原调用关系

初始调用关系为：

```text
recognized_text = “你是谁”
  -> controlled_session 判断 photo_intent_hint=0
  -> 将文本重写成简短 Prompt
  -> assistant.run_once_from_text(prompt)
  -> orchestrator.ask_qwen()
  -> IntentRouter.analyze(prompt)
  -> 再次判断是否拍照
```

也就是说：

```text
原始用户命令做了一次路由；
重写后的 Qwen Prompt 又做了一次路由。
```

### 20.2 误触发关键词

重写 Prompt 中包含：

```text
尽量控制在80个汉字以内
```

而 `photo_keywords` 中存在：

```text
字
```

因此：

```text
original_need_photo  : False
rewritten_need_photo : True
matched_keywords     : ['字']
```

这说明业务意图与模型 Prompt 没有解耦。

---

## 21. 10.3a：意图路由与 Qwen Prompt 解耦

实验 10.3a 增加：

```text
need_photo_override
```

新的调用原则：

```text
原始 ASR 文本
  -> IntentRouter 只判断一次
  -> 得到 need_photo
  -> controlled_session 生成 Qwen Prompt
  -> need_photo_override 传入 orchestrator
  -> orchestrator 不再重新分析 Prompt
```

主要调用链：

```text
VoiceAssistant.run_once_from_text(
    prompt,
    need_photo_override=False / True
)
```

`ask_qwen()` 中：

```text
need_photo_override is None
  -> 兼容旧入口，继续由 IntentRouter 判断

need_photo_override is not None
  -> 使用上层已经确定的路由结果
  -> 重写 Prompt 不再改变拍照行为
```

单元测试：

```text
capture_count_after_text   : 0
capture_count_after_visual : 1
```

结论：

```text
文本 Prompt 与业务路由成功解耦；
普通文本不会因为 Prompt 中的“图片”“字”等词再次触发拍照；
视觉请求仍能显式触发一次摄像头采集。
```

---

## 22. 直接文本问答语义问题

意图解耦后，直接执行“你是谁”：

```text
need_photo_override : False
new_photo_count     : 0
```

说明路由已经正确。

但回答为：

```text
我无法处理与RK3588设备无关的请求，请提供具体问题。
```

原因是普通文本 Prompt 强调：

```text
你是运行在RK3588设备上的本地中文语音助手……
```

2B 模型将“运行平台”错误理解为“只能处理 RK3588 问题”。

同时，测试规则只要回答中出现：

```text
RK3588
```

就认为身份回答成功，造成了假阳性。

这说明：

```text
不仅需要改 Prompt；
还必须改测试判定规则；
不能用单个关键词代替语义验证。
```

---

## 23. 身份问题与普通问题 Prompt 拆分

为避免所有问题都携带身份描述，实验 10.3e 系列将文本 Prompt 拆成两类。

### 23.1 身份问题检测

识别以下问题：

```text
你是谁
你是什么
你叫什么
介绍一下你自己
介绍你自己
你能做什么
你的功能
```

### 23.2 身份问题 Prompt

```text
请直接回答用户的身份询问。
说明你是运行在RK3588设备上的本地中文语音助手，
可以进行普通问答和摄像头画面描述。
只输出一到两句自然中文。
```

### 23.3 普通问题 Prompt

普通问题不应该反复出现：

```text
RK3588
运行平台
语音助手
摄像头
身份
```

否则模型可能被这些高频实体吸引，忽略真正问题。

---

## 24. 关键词清理与严格视觉意图

### 24.1 删除单字关键词“字”

配置初始共有 52 个 `photo_keywords`，包括：

```text
拍照
看一下
摄像头
画面
识别
描述
有什么
几个
颜色
文字
字
OCR
...
```

实验删除：

```text
字
```

删除后：

```text
photo_keyword_count : 51
'字' in keywords    : False
```

但问题仍未完全解决：

```text
“这几个字是什么意思”
```

仍然会命中：

```text
几个
```

同样：

```text
“请描述一下线程池原理”
```

会命中：

```text
描述
```

```text
“这个问题有什么解决方法”
```

会命中：

```text
有什么
```

因此，单纯继续删关键词无法解决根本问题。

### 24.2 原始算法的问题

旧逻辑近似为：

```python
need_photo = any(
    keyword in text
    for keyword in photo_keywords
)
```

这种宽泛子串匹配适合快速 Demo，但不适合正式文本/视觉双入口。

### 24.3 严格视觉意图策略

实验 10.3e-v4 改为更保守的语法：

```text
明确拍照动作
或
明确视觉上下文
  -> 才触发摄像头
```

明确拍照动作示例：

```text
拍照
拍一张
照一张
拍个照
拍一下
拍下来
拍张照片
```

明确视觉上下文示例：

```text
摄像头
镜头
画面
当前画面
照片
图片
图像
眼前
视野里
镜头里
画面里
现在看到
```

普通通用词本身不再触发拍照：

```text
几个
有什么
描述
识别
颜色
文字
```

回归测试：

```text
“你是谁”                 -> False
“一加一等于几”           -> False
“这几个字是什么意思”     -> False
“帮我写几个汉字”         -> False
“请描述一下线程池原理”   -> False
“这个问题有什么解决方法” -> False

“拍照看一下画面”         -> True
“帮我拍一张”             -> True
“看一下镜头”             -> True
“摄像头前面有什么”       -> True
“描述当前画面”           -> True
“识别图片中的文字”       -> True
```

### 24.4 当前实现的工程说明

实验阶段为了快速验证，严格策略以附加覆盖方式写入 `intent.py`，保留旧分析函数用于对比：

```text
legacy result
strict result
```

该实现已经通过功能回归，但属于实验阶段实现。

后续应重构为：

```text
直接修改 IntentRouter.analyze() 内部逻辑；
删除文件末尾 monkey patch；
将显式拍照词和视觉上下文词写入结构化配置；
为正例、负例建立正式单元测试。
```

---

## 25. 文本 Prompt 多轮失败与消融

### 25.1 身份强提示污染普通问题

最初双问题验证：

```text
你是谁
一加一等于几
```

身份问题回答正确：

```text
我是本地中文语音助手……
```

但算术问题也返回身份介绍，说明通用 Prompt 中的身份说明压过了用户问题。

### 25.2 分离后仍被否定句吸引

普通 Prompt 曾包含：

```text
除非用户明确询问，否则不要介绍你的身份、运行平台或功能。
不要因为问题与RK3588无关而拒绝回答。
```

算术回答却变成：

```text
RK3588是一款基于ARM架构的国产芯片，常用于高性能计算和AI应用。
```

这说明对于 2B 量级模型：

```text
否定句中的 RK3588、身份、运行平台仍然是强提示；
模型可能抓住实体，而忽略“不要”；
Prompt 越长，不一定越可靠。
```

---

## 26. 10.3g：普通问答 Prompt 消融

实验不修改正式代码，测试三种 Prompt。

### 26.1 Natural

Prompt：

```text
请简短回答这个问题：一加一等于几？
```

结果：

```text
一加一等于二。
```

指标：

```text
status                  : PASSED
answer_chars            : 7
elapsed_seconds         : 8.200
semantic_ok             : True
contains_platform_topic : False
```

### 26.2 QA Format

Prompt：

```text
问题：一加一等于几？
答案：
```

结果：

```text
“一加一等于几？”这个问题看似简单，但答案取决于我们从哪个角度来理解它。
在数学上：
**1 + 1 =
```

指标：

```text
status          : SEMANTIC_FAILED
answer_chars    : 52
elapsed_seconds : 10.837
```

该格式诱导模型展开长篇分析，并在 32 tokens 时被截断。

### 26.3 Numeric Constraint

Prompt：

```text
计算1+1，只输出最终数字。
```

结果：

```text
2
```

指标：

```text
status          : PASSED
answer_chars    : 1
elapsed_seconds : 7.853
```

### 26.4 消融结论

```text
Natural：
适合作为通用普通问答模板。

QA Format：
容易让模型展开解释，不适合当前小模型和短回答目标。

Numeric Constraint：
适合计算类任务，但不能作为通用 Prompt。
```

最终普通问答模板确定为：

```text
请简短回答这个问题：<用户问题>
```

---

## 27. 10.3h：写入极简普通问答 Prompt

正式 `_build_concise_text_prompt()` 最终逻辑：

```text
身份问题：
  -> 身份专用 Prompt

普通问题：
  -> 请简短回答这个问题：<用户问题>
```

单元测试：

```text
你是谁
  -> identity=True
  -> Prompt 包含本地中文语音助手身份

一加一等于几
  -> identity=False
  -> 请简短回答这个问题：一加一等于几

中国的首都是哪里
  -> identity=False
  -> 请简短回答这个问题：中国的首都是哪里
```

普通 Prompt 中不再包含：

```text
RK3588
运行平台
语音助手
摄像头
不要
除非
```

---

## 28. 10.3f 最终文本语义回归通过

### 28.1 身份问题

问题：

```text
你是谁
```

回答：

```text
我是运行在RK3588设备上的本地中文语音助手，可提供普通问答和摄像头画面描述。
```

结果：

```text
status              : PASSED
answer_chars        : 40
elapsed_seconds     : 10.254
new_photo_count     : 0
refusal_count       : 0
semantic_ok         : True
irrelevant_identity : False
```

### 28.2 算术问题

问题：

```text
一加一等于几
```

实际 Prompt：

```text
请简短回答这个问题：一加一等于几
```

回答：

```text
一加一等于二。
```

结果：

```text
status              : PASSED
answer_chars        : 7
elapsed_seconds     : 8.111
new_photo_count     : 0
refusal_count       : 0
semantic_ok         : True
irrelevant_identity : False
```

### 28.3 最终结果

```text
status          : PASSED
case_total      : 2
case_passed     : 2
new_photo_count : 0
python_rc       : 0
residual_count  : 0
```

说明：

```text
身份 Prompt 正常；
普通问答 Prompt 正常；
严格视觉路由正常；
两类文本均未误触发摄像头；
Qwen 子进程均正常退出。
```

---

## 29. 实验 10.3 最终文本语音闭环通过

完整流程：

```text
KWS 唤醒“鲁班猫”
  -> 录制 5 秒命令
  -> ASR 识别“你是谁”
  -> 严格意图判断为非视觉请求
  -> 不启动摄像头
  -> 身份专用 Prompt
  -> Qwen 简短回答
  -> TTS 合成并播放
  -> 资源清理
```

最终结果：

```text
controlled_return_code   : 0
status                   : PASSED
recognized_text          : 你是谁
text_intent_ok           : 1
photo_intent_hint        : 0
new_photo_count          : 0
answer_chars             : 40
pipeline_elapsed_seconds : 10.453
tts_elapsed_seconds      : 11.392
total_elapsed_seconds    : 41.643
underrun_count           : 0
residual_process_count   : 0
```

意图调试：

```json
{
  "recognized_text": "你是谁",
  "need_photo": false,
  "intent_qwen_text": "你是谁",
  "heuristic_photo_hint": false
}
```

回答：

```text
我是运行在RK3588设备上的本地中文语音助手，可提供普通问答和摄像头画面描述。
```

音量：

```text
mean_volume_dbfs : -33.380
max_volume_dbfs  : -12.338
```

本轮：

```text
没有削波；
ASR 准确；
没有拍照；
Qwen 回答正确；
TTS 正常；
无 underrun；
无残留进程。
```

---

## 30. 最终文本与视觉双链路

实验 10 完成后，系统具备两条正式受控式业务链路。

### 30.1 视觉链路

```text
KWS
  -> ASR
  -> 严格视觉意图
  -> CameraAdapter
  -> V4L2 NV12
  -> FFmpeg -nostdin JPEG
  -> Qwen3-VL
  -> 128-token 简短视觉描述
  -> TTS
```

代表结果：

```text
recognized_text : 来找我看一下画面
new_photo_count : 1
answer_chars    : 34
Qwen            : 12.001 s
TTS             : 12.285 s
total           : 41.805 s
underrun        : 0
residual        : 0
```

### 30.2 文本链路

```text
KWS
  -> ASR
  -> 非视觉意图
  -> 极简文本 Prompt / 身份专用 Prompt
  -> Qwen
  -> 128-token 简短回答
  -> TTS
```

代表结果：

```text
recognized_text : 你是谁
new_photo_count : 0
answer_chars    : 40
Qwen            : 10.453 s
TTS             : 11.392 s
total           : 41.643 s
underrun        : 0
residual        : 0
```

---

## 31. 关键工程问题与排查方法

### 31.1 问题一：系统 Python 找不到 Sherpa-ONNX

现象：

```text
listen-controlled 初次运行失败；
系统 python3 无法导入项目依赖。
```

排查：

```text
检查实际 Python；
检查 .venv；
检查 .python_packages；
对比项目原有 wrapper。
```

解决：

```text
统一使用 .venv/bin/python；
设置 PYTHONPATH。
```

经验：

```text
端侧项目应固定解释器路径；
实验脚本不能默认依赖系统 Python；
环境问题与业务逻辑问题应先分离。
```

---

### 31.2 问题二：Prompt 限字无效

现象：

```text
Prompt 要求 80 字；
实际输出 928 字。
```

根因：

```text
底层 max_new_tokens 仍为 2048；
自然语言约束不等于解码上限。
```

解决：

```text
在 QwenRunner 调用链增加请求级 max_new_tokens；
concise 模式使用 128。
```

经验：

```text
生成长度优化必须同时控制 Prompt 和推理解码参数。
```

---

### 31.3 问题三：视觉短回答语义不正确

现象：

```text
回答“图像信息不完整”。
```

根因：

```text
通用 Prompt 没有明确说明模型应依据当前摄像头图片回答。
```

解决：

```text
设计视觉专用 Prompt；
明确人物、物体、场景；
禁止回答无法查看图片。
```

---

### 31.4 问题四：摄像头脚本超时但 NV12 完整

现象：

```text
45 秒 timeout；
生成完整 1382400 字节 NV12；
无 JPG。
```

排查逻辑：

```text
NV12 大小正确
  -> V4L2 已成功采集

stream on/off 正常
  -> 摄像头与 ISP 正常

无 JPG
  -> 问题在采集后的转换阶段
```

隔离测试：

```text
原 FFmpeg       -> 15 秒超时
FFmpeg -nostdin -> 立即成功
OpenCV          -> 成功
```

根因：

```text
FFmpeg 在子进程环境中等待标准输入。
```

解决：

```text
增加 -nostdin；
增加转换 timeout 和 stderr 日志。
```

---

### 31.5 问题五：普通文本误触发拍照

现象：

```text
recognized_text=你是谁
photo_intent_hint=0
new_photo_count=1
```

根因一：

```text
重写 Prompt 被 IntentRouter 二次分析。
```

根因二：

```text
Prompt 中“汉字”命中 photo_keywords 的“字”。
```

解决：

```text
need_photo_override；
原始用户文本只路由一次；
Qwen Prompt 不再改变业务路由。
```

---

### 31.6 问题六：删除“字”后仍误触发

现象：

```text
“这几个字是什么意思”仍拍照；
“请描述一下线程池原理”仍拍照。
```

根因：

```text
“几个”“描述”“有什么”等通用词仍在关键词列表；
旧算法是任一子串命中。
```

解决：

```text
严格视觉意图：
明确拍照动作或明确视觉上下文才触发。
```

---

### 31.7 问题七：复杂否定式 Prompt 干扰小模型

现象：

```text
问题：一加一等于几
回答：RK3588 是一款 ARM 芯片……
```

根因：

```text
Prompt 中多次出现 RK3588、身份、运行平台；
即使这些词位于否定句，小模型仍会将其作为生成主题。
```

解决：

```text
做 Prompt 消融；
普通问答采用极简自然问句；
身份问题单独处理。
```

经验：

```text
对小参数量端侧模型：
正向、短、直接的 Prompt 通常比复杂否定约束更稳定。
```

---

## 32. 主要代码修改

### 32.1 `voice_assistant/controlled_session.py`

新增或完善：

```text
受控式单轮会话；
状态日志；
阶段耗时；
音量统计；
summary.json / summary.txt；
intent_debug.json；
concise 模式；
视觉专用 Prompt；
身份问题 Prompt；
极简普通问答 Prompt；
请求级 max_new_tokens；
need_photo_override 传递。
```

### 32.2 `voice_assistant/cli.py`

新增：

```text
listen-controlled
```

主要参数包括：

```text
--wake-mode
--wake-timeout
--seconds
--prepare-delay
--answer-mode
--answer-max-chars
--concise-max-new-tokens
--no-speak
--no-play
--out-dir
```

### 32.3 `voice_assistant/qwen_runner.py`

改造：

```text
QwenRunner.ask() 支持 max_new_tokens；
_spawn() 支持请求级覆盖；
未传入时继续使用 config/default.yaml。
```

### 32.4 `voice_assistant/orchestrator.py`

新增：

```text
need_photo_override；
路由结果与 Prompt 解耦；
run_once_from_text() 透传 max_new_tokens；
ask_qwen() 透传请求级参数。
```

### 32.5 `scripts/capture-photo.sh`

修复：

```text
FFmpeg 增加 -nostdin；
增加转换阶段 timeout；
记录 FFmpeg stderr；
修正帮助信息中的默认分辨率和 skip。
```

### 32.6 `voice_assistant/intent.py`

实验阶段新增严格视觉意图策略：

```text
显式拍照动作；
显式视觉上下文；
普通通用词不单独触发。
```

注意：

```text
当前为实验阶段覆盖式实现；
后续应重构进 IntentRouter.analyze() 正式逻辑。
```

### 32.7 `config/default.yaml`

清理：

```text
从 photo_keywords 删除单字“字”。
```

---

## 33. 测试方法改进

实验 10 不仅修改了业务代码，也改进了测试方法。

### 33.1 不再只看 return code

例如：

```text
进程 return_code=0
```

并不代表：

```text
ASR 语义正确；
视觉意图正确；
回答语义正确；
没有意外拍照。
```

因此增加：

```text
recognized_text
photo_intent_hint
new_photo_count
answer_chars
bad_answer_count
semantic_ok
irrelevant_identity
residual_process_count
```

### 33.2 语义测试使用正反条件

身份问题：

```text
必须包含“语音助手/中文助手”等身份语义；
不能只因为出现“RK3588”就通过。
```

算术问题：

```text
必须回答 2/二/两；
不能出现 RK3588、运行平台或无关身份介绍。
```

视觉问题：

```text
必须生成新照片；
回答不能包含“无法查看图片”“信息不足”等拒答语句。
```

### 33.3 将 ASR、摄像头、Qwen 分层隔离

当完整链路失败时，按如下顺序拆分：

```text
完整语音链路
  -> 固定文本直接 Qwen
  -> 固定图片直接视觉 Qwen
  -> 单独 CameraAdapter
  -> 单独 NV12 -> JPEG
```

这种方法避免将所有问题都归因于模型或硬件。

---

## 34. 当前系统能力状态

| 能力 | 状态 |
|---|---:|
| KWS 实时唤醒 | PASS |
| 固定准备延迟与受控录音 | PASS |
| Sherpa-ONNX 中文 ASR | PASS |
| 状态机与阶段日志 | PASS |
| 音量与 WAV 统计 | PASS |
| 原始命令意图路由 | PASS |
| Prompt 与路由解耦 | PASS |
| 严格视觉意图 | PASS |
| 摄像头 1280×720 NV12 采集 | PASS |
| FFmpeg `-nostdin` JPEG 转换 | PASS |
| 摄像头连续 3 次稳定性 | PASS |
| 请求级 `max_new_tokens` | PASS |
| 视觉专用短回答 | PASS |
| 普通文本短回答 | PASS |
| 身份问题专用回答 | PASS |
| 视觉完整 TTS 闭环 | PASS |
| 文本完整 TTS 闭环 | PASS |
| 播放 underrun 检查 | PASS，均为 0 |
| 子进程残留检查 | PASS，均为 0 |
| 连续四轮以上混合稳定性 | **尚未验证** |
| `intent.py` 临时覆盖代码重构 | **尚未完成** |
| VAD 自动结束录音 | **尚未实现** |
| 常驻摄像头与模型服务 | **尚未实现** |

---

## 35. 当前性能状态

### 35.1 直接模型验证

```text
视觉简短问答：
Qwen 约 11.432 秒
回答 28 字

身份文本问答：
Qwen 约 10.254 秒
回答 40 字

算术文本问答：
Qwen 约 8.111 秒
回答 7 字
```

### 35.2 完整语音闭环

```text
视觉闭环：
Qwen 12.001 秒
TTS  12.285 秒
总计 41.805 秒

文本闭环：
Qwen 10.453 秒
TTS  11.392 秒
总计 41.643 秒
```

总耗时还包含：

```text
等待用户说唤醒词；
1 秒准备延迟；
固定 5 秒录音；
ASR；
拍照（视觉路线）；
Qwen；
TTS。
```

从唤醒成功到播放结束，仍大约需要 29 秒左右。

---

## 36. 已知限制与技术债

### 36.1 总体延迟仍然较高

虽然从 120.921 秒降低到约 42 秒，但语音助手交互仍不够实时。

主要耗时：

```text
固定 5 秒录音；
Qwen 约 8～12 秒；
TTS 约 10～12 秒。
```

后续优化方向：

```text
VAD 自动结束录音；
进一步减少 max_new_tokens；
缩短回答；
TTS 模型或推理优化；
常驻 Qwen demo，避免重复启动；
并行初始化或资源复用。
```

### 36.2 严格视觉意图可能存在漏判

当前策略偏保守，可以减少误拍照，但某些省略视觉上下文的表达可能不触发：

```text
“帮我看看这个”
“这是什么”
“读一下”
```

如果用户没有说“画面、图片、镜头”等上下文，系统可能判为普通文本。

后续可以结合：

```text
最近一次会话上下文；
GUI/按键状态；
摄像头模式状态；
轻量分类器；
结构化意图规则。
```

### 36.3 Prompt 结果存在生成随机性

即使同一个 Prompt，多次运行也可能略有不同。当前实验只证明代表性运行通过，尚未统计：

```text
10 次成功率；
回答长度分布；
语义正确率；
视觉描述一致性。
```

### 36.4 `intent.py` 需要正式重构

当前严格策略是为了实验快速验证而附加到文件末尾。正式版本应：

```text
直接重写 IntentRouter.analyze()；
删除 monkey patch；
将 capture phrases 和 visual contexts 配置化；
增加 pytest 单元测试。
```

### 36.5 还没有执行实验 10.4

计划中的：

```text
视觉 -> 文本 -> 视觉 -> 文本
```

四轮或更多连续稳定性验证尚未执行。

因此当前结论应表述为：

```text
单轮文本和单轮视觉受控闭环均通过；
多轮长期稳定性尚待验证。
```

---

## 37. 后续实验建议

### 37.1 实验 10.4：连续混合稳定性

建议执行至少四轮：

```text
第 1 轮：看一下画面
第 2 轮：你是谁
第 3 轮：拍照描述当前画面
第 4 轮：一加一等于几
```

统计：

```text
KWS 成功率；
ASR 正确率；
视觉意图正确率；
意外拍照次数；
Qwen 回答正确率；
Qwen/TTS 耗时；
摄像头失败次数；
underrun；
残留进程；
内存增长。
```

### 37.2 正式重构 IntentRouter

建议将视觉意图拆成：

```text
explicit_capture_phrases
visual_context_phrases
visual_action_phrases
generic_query_phrases
```

再使用组合规则，而不是简单 `any(keyword in text)`。

### 37.3 常驻 Qwen 推理服务

当前每次请求都可能重新启动 demo。可以考虑：

```text
常驻 pexpect 会话；
请求队列；
超时和异常自动重启；
模型预热；
复用 RKNN/RKLLM 上下文。
```

这可能显著减少每轮初始化耗时。

### 37.4 VAD 与交互提示

将固定 5 秒录音改为：

```text
提示音；
检测开始说话；
检测连续静音；
自动结束录音。
```

可改善：

```text
用户不知道何时说话；
录音窗口过长；
前后静音过多；
总延迟过高。
```

### 37.5 TTS 优化

当前 30～40 字回答仍需要约 10～12 秒。可以继续测试：

```text
更短句子；
降低声学模型计算量；
线程数调优；
缓存模型初始化；
分句流式合成；
播放与后续生成流水化。
```

---

## 38. 简历与面试可提炼点

实验 10 可以体现以下能力：

```text
1. 将实验性多模块链路封装为正式 CLI 和状态机；
2. 设计可观测日志、JSON summary、阶段耗时和残留进程检查；
3. 打通请求级 max_new_tokens，优化端侧大模型生成时延；
4. 通过隔离 NV12 与 JPEG 转换定位 FFmpeg 标准输入阻塞；
5. 使用 -nostdin、timeout、stderr 日志增强外部进程可靠性；
6. 发现并修复 Prompt 被二次意图分析导致的摄像头误触发；
7. 将业务路由与模型 Prompt 解耦；
8. 从宽泛关键词匹配改为显式动作 + 视觉上下文的严格意图策略；
9. 针对 2B 小模型开展 Prompt 消融并选择极简自然问句；
10. 完成文本和视觉两条 KWS/ASR/Qwen/TTS 端侧闭环；
11. 将视觉回答从 928 字压缩到 34 字，Qwen 阶段从 62.528 秒降到 12.001 秒；
12. 保证最终播放 underrun_count=0、residual_process_count=0。
```

可用于简历的描述示例：

```text
在 RK3588 上将 KWS、离线 ASR、V4L2 摄像头、Qwen3-VL RKNN/RKLLM 推理与 Matcha-TTS/Vocos 封装为受控式多模态语音助手入口，设计会话状态机、阶段耗时、音量统计和 JSON 日志。打通请求级 max_new_tokens，将视觉回答由 928 字压缩至 34 字，Qwen 推理耗时由 62.5 s 降至 12.0 s；通过 NV12/JPEG 分段隔离定位 FFmpeg 等待标准输入问题，并以 -nostdin 和超时清理修复摄像头阻塞。进一步解耦原始用户意图与模型 Prompt，重构视觉意图规则，避免普通文本误触发拍照，最终跑通文本与视觉两条 KWS->ASR->Qwen->TTS 闭环，播放 underrun 与残留进程均为 0。
```

---

## 39. 关键归档目录

已知代表性输出目录如下：

```text
NV12 -> JPEG 隔离：
output/exp10_2fb_nv12_to_jpg_isolation_20260802_223647

FFmpeg -nostdin 修复后三次摄像头验证：
output/exp10_2fc_camera_after_nostdin_20260802_224136

ASR 误识别“冲”的无效视觉测试：
output/exp10_2fd_visual_concise_after_camera_fix_20260802_224318

直接视觉简短问答通过：
output/exp10_2fe_direct_visual_concise_20260802_224629

完整视觉语音闭环通过：
output/exp10_2g_full_visual_concise_tts_20260802_224930

普通文本语音闭环初次误拍照：
output/exp10_3_text_concise_tts_20260802_225457

意图与 Prompt 解耦：
output/exp10_3a_decouple_intent_and_prompt_20260802_225809

首次身份/普通 Prompt 拆分脚本匹配失败：
output/exp10_3e_split_identity_and_general_prompt_20260802_230830

v2 配置清理与意图测试失败：
output/exp10_3e_v2_split_prompts_robust_20260802_231035

v3 首次删除“字”后仍被“几个”等关键词误触发：
output/exp10_3e_v3_yaml_safe_prompt_split_20260802_231339

严格视觉意图回归通过：
output/exp10_3e_v4_strict_visual_intent_20260802_231954

v3 复测通过，Prompt 拆分与关键词清理正式落盘：
output/exp10_3e_v3_yaml_safe_prompt_split_20260802_232319

普通 Prompt 仍受 RK3588 干扰的失败回归：
output/exp10_3f_direct_text_semantic_v2_20260802_232510

普通问答 Prompt 消融：
output/exp10_3g_arithmetic_prompt_ablation_20260802_232820

极简普通问答 Prompt 写入正式代码：
output/exp10_3h_apply_minimal_general_prompt_20260802_233204

最终完整文本语音闭环：
output/exp10_3_text_concise_tts_final_20260802_233713
```

代表性照片：

```text
直接视觉验证：
/home/cat/图片/voice_20260802_224629.jpg

完整视觉语音闭环：
/home/cat/图片/voice_20260802_224948.jpg
```

---

## 40. 实验 10 最终结论

实验 10 完成了 RK3588 端侧多模态语音助手从“受控脚本可运行”到“文本/视觉双入口可验证”的工程化升级。

实验首先将实验 09 的受控流程封装为 `listen-controlled`，增加了明确的状态机、阶段耗时、音量统计、Prompt/回答存档和残留进程检查。随后发现仅依靠 Prompt 无法限制 Qwen 输出长度，于是将请求级 `max_new_tokens` 从 CLI 一直贯通到 QwenRunner，使 concise 模式能够使用 128 tokens。

视觉链路中，回答从 928 字缩短到 34 字，Qwen 阶段由 62.528 秒降低到 12.001 秒，TTS 由 47.853 秒降低到 12.285 秒。摄像头超时问题通过完整 NV12 文件和 JPEG 缺失现象被定位到 FFmpeg 转换阶段，最终确认 FFmpeg 在子进程环境中等待标准输入，并通过 `-nostdin` 修复，修复后三次连续拍照全部在约 1 秒内完成。

文本链路中，系统先后暴露了 Prompt 二次路由、单字关键词“字”、宽泛关键词“几个/描述/有什么”和复杂否定式 Prompt 干扰小模型等问题。通过 `need_photo_override` 将原始意图与 Qwen Prompt 解耦，使用显式拍照动作和视觉上下文建立严格意图策略，并通过 Prompt 消融选择“请简短回答这个问题：<用户问题>”作为普通问答模板，最终实现身份问题和普通算术问题均正确回答且不会启动摄像头。

最终两条完整链路均通过：

```text
视觉链路：
鲁班猫
  -> ASR
  -> 视觉意图
  -> 摄像头
  -> Qwen3-VL 简短描述
  -> TTS
  -> underrun=0
  -> residual=0

文本链路：
鲁班猫
  -> ASR
  -> 非视觉意图
  -> Qwen 简短回答
  -> TTS
  -> new_photo_count=0
  -> underrun=0
  -> residual=0
```

当前仍需注意：实验 10 只完成了代表性单轮文本和视觉闭环，尚未完成四轮以上连续混合稳定性验证；`intent.py` 中的严格意图策略仍是实验阶段覆盖式实现，需要在后续整理中正式重构。

---

## 41. 一句话总结

```text
实验 10 通过受控式 CLI、请求级生成长度控制、FFmpeg -nostdin 修复、意图与 Prompt 解耦、严格视觉路由和小模型 Prompt 消融，最终在 RK3588 上稳定跑通了“鲁班猫”唤醒后的文本问答与摄像头视觉问答两条简短 TTS 闭环，并将视觉总耗时由约 121 秒降低到约 42 秒。
```
