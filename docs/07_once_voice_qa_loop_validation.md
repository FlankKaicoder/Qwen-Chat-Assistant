# 实验 07：ASR -> Qwen -> TTS 单轮语音问答闭环验证

> 项目：RK3588 端侧多模态智能语音助手系统  
> 平台：LubanCat / RK3588  
> 仓库目录：`/home/cat/ai/qwen3vl2b`  
> 实验编号：07  
> 实验主题：`record -> stt -> qwen -> tts/play` 单轮语音问答闭环验证、官方 `once` 入口验证、流式 TTS underrun 定位与修复  
> 实验状态：**通过**  
> 记录日期：2026-07-09

---

## 1. 实验背景

前置实验已经完成了完整语音助手所需的三个核心模块验证：

```text
实验 04：Sherpa-ONNX 离线中文 ASR 链路
  麦克风录音 -> 16kHz WAV -> 中文文本

实验 05：Qwen3-VL 本地图文/文本推理链路
  ASR 文本 / 图片 -> Qwen3-VL -> 文本回答

实验 06：Sherpa-ONNX Matcha-TTS 中文语音合成与播放链路
  Qwen 文本回答 -> TTS 合成 -> plughw:2,0 播放
```

到实验 06 结束时，系统已经分别具备：

```text
语音输入 -> ASR -> Qwen -> 文本回答

Qwen 文本回答 -> TTS -> 语音播放
```

但前面仍然只是分段验证，还没有确认项目能否完成完整单轮闭环：

```text
用户说话
  -> 麦克风录音
  -> ASR 识别
  -> Qwen3-VL 生成回答
  -> TTS 合成
  -> 板端喇叭 / 耳机播放
```

因此实验 07 的核心目标是把实验 04、05、06 已验证的三段链路串起来，并进一步验证项目官方入口：

```bash
python3 voice_assistant.py once
```

是否能够作为完整单轮语音助手入口稳定工作。

---

## 2. 实验目标

实验 07 需要回答以下问题：

```text
1. 手动串联 record -> stt -> ask -> tts-stream 是否能完成完整闭环；
2. 项目官方 VoiceAssistant 是否可以完整导入和初始化；
3. 官方 once 入口是否可以完成 record -> stt -> qwen 文本闭环；
4. 官方 once 入口是否可以完成 record -> stt -> qwen -> tts -> play 语音闭环；
5. once 流式 TTS 播放中出现的 ALSA underrun 是否影响主链路；
6. underrun 的来源是 TTS / ALSA 播放链路，还是 once 流式集成策略；
7. 是否可以通过保守修复将 once 改为“完整回答后整段 TTS 播放”来消除 underrun；
8. 修复后的 once 是否仍能正常完成完整语音问答。
```

---

## 3. 实验 07 总体拆分

本实验拆分为以下阶段：

```text
07.1 手动串联 record -> stt -> ask -> tts-stream 完整闭环
07.2 官方 once 入口预检：CLI / import / VoiceAssistant 初始化
07.3 官方 once --no-speak --no-play 文本闭环
07.4 官方 once 带 TTS 播放完整语音闭环
07.5 TTS underrun 复核定位
07.6 once 流式 TTS 代码位置检查
07.7 patch once：改为完整回答后整段 TTS 播放
07.8 修复后 once clean verify
```

实验顺序遵循模块化原则：

```text
先手动串联证明能力存在；
再验证官方入口是否可用；
最后定位和修复播放稳定性问题。
```

---

## 4. 实验 07.1：手动串联完整闭环

### 4.1 实验目的

实验 07.1 不使用官方 `once`，而是显式串联四个已经验证过的轻量入口：

```text
voice_assistant.py record
  -> voice_assistant.py stt
  -> voice_assistant.py ask --no-speak --no-play
  -> voice_assistant.py tts-stream
```

目的是先确认三段能力组合后可以形成完整问答闭环。

---

### 4.2 输出目录

```text
output/exp07_1_record_stt_qwen_tts_once_20260709_142444
```

---

### 4.3 运行结果

关键 summary：

```text
record_return_code: 0
stt_return_code   : 0
qwen_return_code  : 0
tts_return_code   : 0
recognized_text   : 请用一句话介绍自己
[RESULT] Experiment 07.1 PASSED_BY_COMMAND
[NOTE] Please confirm by listening whether the Qwen answer was spoken.
```

ASR 识别结果：

```text
请用一句话介绍自己
```

Qwen prompt：

```text
请用一到两句中文简短回答下面的问题：请用一句话介绍自己
```

Qwen 回答：

```text
我是一个人工智能助手，能够帮助你解答问题、提供信息和完成各种任务。
```

TTS 播放文本：

```text
下面播放语音助手回答：我是一个人工智能助手，能够帮助你解答问题、提供信息和完成各种任务。
```

异常检查：

```text
abnormal: 空
qwen stderr: 空
tts stderr : 空
```

录音音量：

```text
mean_volume: -20.7 dB
max_volume : 0.0 dB
```

---

### 4.4 实验结论

实验 07.1 判定：**通过**。

说明手动串联链路已经完整成立：

```text
麦克风录音
  -> Sherpa-ONNX ASR
  -> Qwen3-VL 回答
  -> Matcha-TTS 中文合成
  -> 板端播放
```

需要记录的问题：

```text
max_volume = 0.0 dB
```

表示录音峰值已经顶到上限。当前 ASR 正常，因此不需要立即修改；如果后续出现爆音、削波或识别不稳定，可以降低 `asr_input_gain` 或麦克风输入增益。

---

## 5. 实验 07.2：官方 once 入口预检

### 5.1 实验目的

实验 07.2 验证官方完整入口前，先检查：

```text
1. voice_assistant.py once 子命令是否存在；
2. 完整依赖是否可以 import；
3. VoiceAssistant 是否可以初始化；
4. ASR / Qwen / TTS / Camera / Intent / Orchestrator 是否存在导入耦合问题。
```

---

### 5.2 输出目录

```text
output/exp07_2_once_entry_precheck_20260709_142627
```

---

### 5.3 once help

```text
usage: voice_assistant.py once [-h] [--seconds SECONDS] [--no-speak]
                               [--no-play]

optional arguments:
  -h, --help         show this help message and exit
  --seconds SECONDS
  --no-speak
  --no-play
```

说明 `once` 入口存在，并支持：

```text
--seconds   录音秒数
--no-speak  不进行 TTS 合成
--no-play   不进行播放
```

---

### 5.4 import 检查

导入检查结果：

```text
[OK] yaml
[OK] numpy
[OK] pexpect
[OK] sherpa_onnx
[OK] voice_assistant.config
[OK] voice_assistant.audio_io
[OK] voice_assistant.asr
[OK] voice_assistant.qwen_runner
[OK] voice_assistant.tts
[OK] voice_assistant.streaming_tts
[OK] voice_assistant.camera
[OK] voice_assistant.intent
[OK] voice_assistant.orchestrator
```

说明完整链路所需模块均可导入。

---

### 5.5 VoiceAssistant 初始化

```text
[OK] config loaded
[OK] VoiceAssistant initialized
assistant_type: VoiceAssistant
```

summary：

```text
init_return_code: 0
[RESULT] Experiment 07.2 PRECHECK PASSED
```

异常检查：

```text
abnormal: 空
```

---

### 5.6 实验结论

实验 07.2 判定：**通过**。

说明当前项目的完整 `VoiceAssistant` 已经可以初始化，后续可以正式测试官方 `once` 入口。

---

## 6. 实验 07.3：官方 once 文本闭环

### 6.1 实验目的

实验 07.3 使用官方入口：

```bash
python3 voice_assistant.py once --seconds 6 --no-speak --no-play
```

验证官方入口是否可以完成：

```text
record -> stt -> qwen -> 文本输出
```

暂时不播放 TTS，目的是先排除播放链路干扰。

---

### 6.2 输出目录

```text
output/exp07_3_once_no_speak_no_play_20260709_142851
```

---

### 6.3 运行结果

summary：

```text
once_return_code: 0
[RESULT] Experiment 07.3 PASSED_BY_COMMAND
```

stdout：

```text
识别文本：前有一句话介绍自己
正在调用 Qwen demo，请等待模型回答...
当然可以！请告诉我您想让我帮您完成的句子或内容，比如：
- 您希望自我介绍时提到什么？（例如职业、兴趣、背景等）
- 有没有特定的语气或风格要求？（正式/亲切/简洁等）
我会根据您的需求来帮助您撰写。
```

stderr：

```text
Recording WAVE '/tmp/qwen_voice_assistant/command.wav' : Signed 16 bit Little Endian, Rate 16000 Hz, Stereo
```

异常检查：

```text
abnormal: 空
```

---

### 6.4 结果分析

实验链路通过，但 ASR 文本存在误识别：

```text
原始意图：请用一句话介绍自己
识别结果：前有一句话介绍自己
```

这导致 Qwen 回答偏向“帮你撰写句子”，而不是直接介绍自己。

该问题不是 Qwen 链路失败，而是 ASR 语义偏差导致的下游输入偏差。

---

### 6.5 实验结论

实验 07.3 判定：**通过，但回答语义受 ASR 误识别影响**。

说明官方 `once --no-speak --no-play` 文本闭环成立：

```text
录音
  -> ASR
  -> Qwen
  -> 文本输出
```

后续需要在实际体验中继续优化：

```text
1. 录音音量；
2. 说话清晰度；
3. ASR 输入增益；
4. 意图容错和关键词规则。
```

---

## 7. 实验 07.4：官方 once 带 TTS 播放完整闭环

### 7.1 实验目的

实验 07.4 不再添加 `--no-speak --no-play`，直接运行官方完整入口：

```bash
python3 voice_assistant.py once --seconds 5
```

验证：

```text
record -> stt -> qwen -> streaming tts -> speaker
```

---

### 7.2 输出目录

```text
output/exp07_4_once_with_tts_play_20260709_143037
```

---

### 7.3 运行结果

summary：

```text
once_return_code: 0
recognized_text: 你是谁
qwen_answer_chars: 68
[RESULT] Experiment 07.4 PASSED_BY_COMMAND
[NOTE] Please confirm by listening whether the assistant answer was spoken.
```

用户人工确认：

```text
确实听到了语音
```

ASR 识别结果：

```text
你是谁
```

Qwen 回答：

```text
我是一个AI助手，没有具体的个人身份。我是由阿里云研发的通义千问模型，旨在提供帮助和解答问题。如果您有任何需要协助的地方，请随时告诉我！
```

stdout：

```text
识别文本：你是谁
将使用流式 TTS：Qwen 每生成一句就直接写入喇叭 PCM 播放。
正在调用 Qwen demo，请等待模型回答...
我是一个AI助手，没有具体的个人身份。我是由阿里云研发的通义千问模型，旨在提供帮助和解答问题。如果您有任何需要协助的地方，请随时告诉我！
```

stderr：

```text
Recording WAVE '/tmp/qwen_voice_assistant/command.wav' : Signed 16 bit Little Endian, Rate 16000 Hz, Stereo
underrun!!! (at least 3563.717 ms long)
underrun!!! (at least 143.672 ms long)
```

---

### 7.4 结果分析

实验 07.4 的主链路通过：

```text
once_return_code = 0
ASR 识别正确
Qwen 回答正常
用户人工确认听到语音
```

但发现播放稳定性问题：

```text
underrun!!!
```

underrun 表示 ALSA 播放端在某些时刻没有收到足够的 PCM 数据，播放缓冲区发生断流。

结合 stdout：

```text
将使用流式 TTS：Qwen 每生成一句就直接写入喇叭 PCM 播放。
```

初步判断原因是：

```text
Qwen 生成文本 / TTS 合成下一段音频需要时间
  -> ALSA 播放端已经启动
  -> 下一段 PCM 尚未及时写入
  -> 触发 underrun
```

---

### 7.5 实验结论

实验 07.4 判定：**通过，但发现 once 流式 TTS 播放存在 underrun 警告**。

该问题不影响主链路通过，但会影响语音播放稳定性和体验，需要继续定位。

---

## 8. 实验 07.5：TTS underrun 复核定位

### 8.1 实验目的

实验 07.5 对比三种情况：

```text
case A：短文本单独 tts-stream
case B：上一次 Qwen 回答文本单独 tts-stream
case C：官方 once 流式 TTS
```

目的是判断 underrun 来自：

```text
1. TTS 模型本身；
2. tts-stream / PcmSpeakerStream / ALSA 播放链路；
3. once 中 Qwen 流式生成与 TTS 流式播放的集成策略。
```

---

### 8.2 输出目录

```text
output/exp07_5_tts_underrun_compare_20260709_143432
```

---

### 8.3 对比结果

summary：

```text
caseA_short_tts_stream_underrun_count      : 0
caseB_qwen_answer_tts_stream_underrun_count: 0
caseC_once_streaming_tts_underrun_count    : 2
caseC_once_return_code                     : 0
caseC_recognized_text                      : 你是谁
[DIAGNOSIS] underrun likely comes from once streaming integration / buffering.
[RESULT] Experiment 07.5 COMPLETED
```

case A stderr：

```text
空
```

case B stderr：

```text
空
```

case C stderr：

```text
Recording WAVE '/tmp/qwen_voice_assistant/command.wav' : Signed 16 bit Little Endian, Rate 16000 Hz, Stereo
underrun!!! (at least 3496.055 ms long)
underrun!!! (at least 433.989 ms long)
```

异常检查：

```text
abnormal_without_underrun: 空
```

---

### 8.4 结果分析

结论非常明确：

```text
单独 tts-stream 播放短文本：无 underrun
单独 tts-stream 播放 Qwen 回答：无 underrun
官方 once 流式播放：出现 2 次 underrun
```

因此可以排除：

```text
1. Matcha-TTS 模型本身不稳定；
2. Vocos 声码器不稳定；
3. PcmSpeakerStream 基础播放链路不稳定；
4. ALSA / plughw:2,0 本身无法稳定播放。
```

问题收敛到：

```text
voice_assistant.py once 中的流式 TTS 集成缓冲策略。
```

---

### 8.5 实验结论

实验 07.5 判定：**完成定位**。

结论：

```text
TTS 模型、tts-stream 官方入口、ALSA 播放链路本身稳定；
underrun 主要来自 voice_assistant.py once 中的流式 TTS 集成缓冲不足。
```

---

## 9. 实验 07.6：once 流式 TTS 代码位置检查

### 9.1 实验目的

实验 07.6 检查源码，确认 once 流式 TTS 的执行路径：

```text
1. once 是在哪个函数中执行；
2. once 是否默认使用 StreamingTtsPlayer；
3. StreamingTtsPlayer 是何时打开 PcmSpeakerStream；
4. PcmSpeakerStream 如何写入 ALSA；
5. QwenRunner 如何按句回调。
```

---

### 9.2 输出目录

```text
output/exp07_6_once_streaming_code_inspect_20260709_143648
```

---

### 9.3 编译结果

```text
compile_return_code: 0
[RESULT] Experiment 07.6 CODE_INSPECT_COMPLETED
```

说明相关源码语法正常。

---

### 9.4 关键代码关系

`voice_assistant/orchestrator.py` 中：

```text
run_once_from_text()
  -> if speak and play:
      print("将使用流式 TTS：Qwen 每生成一句就直接写入喇叭 PCM 播放。")
      player = StreamingTtsPlayer(self.config)
      return self.ask_qwen(..., on_sentence=player.enqueue)
```

`voice_assistant/qwen_runner.py` 中：

```text
ask_stream()
  -> _SentenceBuffer
  -> sentence_buffer.feed(...)
  -> sentence_buffer.finish()
  -> on_sentence(text)
```

`voice_assistant/streaming_tts.py` 中：

```text
StreamingTtsPlayer
  -> 后台线程 _run()
  -> 从 queue 取 text
  -> SherpaTts.synthesize_samples(text)
  -> speaker.write_samples(sample_rate, samples)
```

`voice_assistant/audio_io.py` 中：

```text
PcmSpeakerStream
  -> playback_channels
  -> playback_sample_rate
  -> subprocess.Popen(aplay, stdin=PIPE)
  -> write_samples()
  -> stdin.write(pcm)
  -> stdin.flush()
```

---

### 9.5 源码层结论

once 原始路径是：

```text
voice_assistant.py once
  -> cli.py
  -> assistant.run_once_from_microphone()
  -> assistant.run_once_from_text()
  -> QwenRunner.ask_stream()
  -> _SentenceBuffer 按句切分
  -> StreamingTtsPlayer.enqueue()
  -> TTS 后台线程合成
  -> PcmSpeakerStream.write_samples()
  -> aplay 播放
```

问题点在于：

```text
播放端打开后，Qwen 句子生成和 TTS 合成并不能保证持续供给 PCM。
```

因此一旦某一句生成或合成耗时较长，ALSA 播放缓冲区就可能断流，产生 underrun。

---

## 10. 实验 07.7：保守修复 once 播放策略

### 10.1 实验目的

根据 07.5 和 07.6 的定位结果，实验 07.7 采用保守修复策略：

```text
原策略：
Qwen 边生成 -> TTS 边播放

新策略：
先得到完整 Qwen 回答 -> 再整段 TTS 播放
```

优点：

```text
提高播放稳定性，优先消除 underrun。
```

代价：

```text
首句语音播报延迟增加。
```

---

### 10.2 输出目录

```text
output/exp07_7_patch_once_nonstream_tts_20260709_150739
```

---

### 10.3 修改前逻辑

`run_once_from_text()` 原本在 `speak and play` 时执行：

```python
if speak and play:
    print("将使用流式 TTS：Qwen 每生成一句就直接写入喇叭 PCM 播放。", flush=True)
    player = StreamingTtsPlayer(self.config)
    try:
        ack_text = str(self.config["models"]["tts"].get("ack_text", "")).strip()
        if ack_text:
            player.enqueue(ack_text)
        return self.ask_qwen(
            text,
            image_path=image_path,
            force_photo=force_photo,
            on_sentence=player.enqueue,
        )
    finally:
        player.close()
return self.ask_qwen(text, image_path=image_path, force_photo=force_photo)
```

该逻辑会把 Qwen 的每一句输出实时送入 TTS 播放队列。

---

### 10.4 修改后逻辑

修改为：

```python
answer = self.ask_qwen(text, image_path=image_path, force_photo=force_photo)

if speak and play:
    print("将使用整段 TTS：先得到完整 Qwen 回答，再合成并播放。", flush=True)
    player = StreamingTtsPlayer(self.config)
    try:
        player.enqueue(answer)
    finally:
        player.close()

return answer
```

修改后的 `run_once_from_text()` 关键片段：

```text
73      def run_once_from_text(
74          self,
75          text: str,
76          *,
77          image_path: str | Path | None = None,
78          force_photo: bool = False,
79          speak: bool = True,
80          play: bool = True,
81      ) -> str:
82          answer = self.ask_qwen(text, image_path=image_path, force_photo=force_photo)
83
84          if speak and play:
85              print("将使用整段 TTS：先得到完整 Qwen 回答，再合成并播放。", flush=True)
86              player = StreamingTtsPlayer(self.config)
87              try:
88                  player.enqueue(answer)
89              finally:
90                  player.close()
91
92          return answer
```

---

### 10.5 编译与运行结果

summary：

```text
patch_return_code  : 0
compile_return_code: 0
once_return_code   : 0
underrun_count     : 0
recognized_text    : 你是谁
[RESULT] Experiment 07.7 PASSED_NO_UNDERRUN
[NOTE] Please confirm by listening whether the assistant answer was spoken.
```

stderr：

```text
Recording WAVE '/tmp/qwen_voice_assistant/command.wav' : Signed 16 bit Little Endian, Rate 16000 Hz, Stereo
```

没有出现：

```text
underrun!!!
```

---

### 10.6 关于 qwen_answer 解析为空的问题

实验 07.7 的 `qwen_answer.txt` 为空，但这不是 Qwen 没有回答，而是脚本解析逻辑未适配修改后的 stdout 顺序。

实际 stdout 中已经出现回答：

```text
识别文本：你是谁
正在调用 Qwen demo，请等待模型回答...
将使用整段 TTS：先得到完整 Qwen 回答，再合成并播放。
我是一个AI助手，没有具体的个人身份。我是由阿里云研发的通义千问模型，旨在提供帮助和解答问题。如果您有任何需要协助的地方，请随时告诉我！
```

因此 07.7 需要后续用更干净的 parser 复测一次。

---

### 10.7 实验结论

实验 07.7 判定：**通过，underrun 消失**。

说明：

```text
once 默认流式 TTS 会产生 ALSA underrun；
改为完整回答后整段 TTS 播放后，underrun 消失；
播放链路本身稳定，问题来自流式集成缓冲策略。
```

---

## 11. 实验 07.8：修复后 once clean verify

### 11.1 实验目的

实验 07.8 不再修改主程序，只修正验证脚本的输出解析逻辑，重新验证修复后的 once：

```text
1. once_return_code 是否为 0；
2. ASR 是否有识别结果；
3. Qwen 回答是否可以正确解析；
4. TTS 播放是否不再出现 underrun；
5. 异常检查是否为空。
```

---

### 11.2 输出目录

```text
output/exp07_8_once_nonstream_verify_clean_20260709_151026
```

---

### 11.3 运行结果

summary：

```text
once_return_code   : 0
underrun_count     : 0
recognized_text    : 谢谢
qwen_answer_chars  : 27
[RESULT] Experiment 07.8 PASSED_CLEAN_VERIFY
[NOTE] Please confirm by listening whether the assistant answer was spoken.
```

ASR 识别结果：

```text
谢谢
```

Qwen 回答：

```text
不客气！如果你有任何问题或需要帮助，随时告诉我哦～ 😊
```

stderr：

```text
Recording WAVE '/tmp/qwen_voice_assistant/command.wav' : Signed 16 bit Little Endian, Rate 16000 Hz, Stereo
```

异常检查：

```text
abnormal_without_underrun: 空
```

---

### 11.4 结果分析

本次用户实际说的是“谢谢”，ASR 正确识别为：

```text
谢谢
```

Qwen 回答为：

```text
不客气！如果你有任何问题或需要帮助，随时告诉我哦～ 😊
```

这说明语义链路正常：

```text
用户说“谢谢”
  -> ASR 识别“谢谢”
  -> Qwen 生成“不客气”
  -> TTS 播放
```

更重要的是：

```text
underrun_count = 0
```

说明修复后的整段 TTS 策略稳定。

---

### 11.5 实验结论

实验 07.8 判定：**通过**。

修复后 once 官方入口可以完成：

```text
record -> stt -> qwen -> full-answer tts -> play
```

并且不再出现 ALSA underrun。

---

## 12. 实验 07 总体结果汇总

| 子实验 | 内容 | 状态 | 关键结论 |
|---|---|---|---|
| 07.1 | 手动串联 `record -> stt -> ask -> tts-stream` | 通过 | 完整能力链路成立 |
| 07.2 | once 入口预检 | 通过 | import 与 VoiceAssistant 初始化正常 |
| 07.3 | once 文本闭环 | 通过 | 官方入口可完成录音、识别、Qwen 文本回答 |
| 07.4 | once 语音闭环 | 通过但有警告 | 听到语音，但出现 2 次 underrun |
| 07.5 | underrun 对比定位 | 完成 | underrun 来自 once 流式集成缓冲，不是 TTS/ALSA 本身 |
| 07.6 | 代码位置检查 | 完成 | 锁定 `ask_stream -> player.enqueue -> PcmSpeakerStream` 路径 |
| 07.7 | patch once 为整段 TTS | 通过 | `underrun_count=0` |
| 07.8 | clean verify | 通过 | 修复后 once 稳定完成语音问答 |

---

## 13. 最终能力状态

实验 07 完成后，项目已经具备：

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

官方入口：

```bash
python3 voice_assistant.py once
```

已经完成单轮语音问答闭环验证。

---

## 14. 关键问题与修复总结

### 14.1 问题：官方 once 流式播放出现 underrun

现象：

```text
underrun!!! (at least 3563.717 ms long)
underrun!!! (at least 143.672 ms long)
```

复现实验：

```text
07.4 官方 once 带 TTS 播放
07.5 case C once streaming TTS
```

---

### 14.2 定位：不是 TTS / ALSA 基础链路问题

07.5 对比结果：

```text
caseA_short_tts_stream_underrun_count      : 0
caseB_qwen_answer_tts_stream_underrun_count: 0
caseC_once_streaming_tts_underrun_count    : 2
```

说明：

```text
单独 tts-stream 播放稳定；
同一段 Qwen 回答文本单独 tts-stream 播放稳定；
once 中边生成边播报才出现 underrun。
```

---

### 14.3 根因：流式集成缓冲不足

原始流程：

```text
QwenRunner.ask_stream()
  -> 按句切分 Qwen 输出
  -> player.enqueue(sentence)
  -> StreamingTtsPlayer 后台线程合成
  -> PcmSpeakerStream 写入 aplay
```

问题：

```text
Qwen 生成下一句和 TTS 合成下一段都需要时间；
ALSA 播放端一旦启动，需要连续 PCM 数据；
如果下一段音频来不及供给，就会出现 underrun。
```

---

### 14.4 修复：完整回答后整段播放

修改后流程：

```text
answer = self.ask_qwen(...)
player.enqueue(answer)
player.close()
return answer
```

效果：

```text
07.7 underrun_count = 0
07.8 underrun_count = 0
```

代价：

```text
首句语音播报延迟增加。
```

但对于当前项目收尾和简历展示而言，稳定性优先级更高。

---

## 15. 当前保留的工程取舍

### 15.1 当前采用方案

当前采用：

```text
非流式整段 TTS 播放
```

原因：

```text
1. 代码改动小；
2. 行为稳定；
3. 可解释性强；
4. 实验已证明 underrun 消失；
5. 适合当前项目阶段封口。
```

---

### 15.2 后续可优化方向

如果后续想保留流式体验，可以继续改进为：

```text
方案 A：预缓冲第一段音频
  先合成第一段 TTS samples，再打开 aplay。

方案 B：双队列缓冲
  Qwen 文本队列 -> TTS 音频队列 -> 播放队列。

方案 C：缓存 1~2 个 TTS chunk 后再开始播放
  降低 ALSA 首段断流概率。

方案 D：增大 aplay / ALSA 缓冲区
  需要结合 PcmSpeakerStream 和系统声卡参数进一步测试。
```

但这些优化复杂度较高，当前项目可以先保留稳定的整段播放方案。

---

## 16. 当前可复用命令

### 16.1 官方 once 单轮语音问答

```bash
cd /home/cat/ai/qwen3vl2b

python3 voice_assistant.py once --seconds 5
```

建议说短句：

```text
你是谁
谢谢
介绍自己
```

---

### 16.2 不播放，仅测试文本闭环

```bash
cd /home/cat/ai/qwen3vl2b

python3 voice_assistant.py once \
  --seconds 5 \
  --no-speak \
  --no-play
```

---

### 16.3 手动串联完整闭环

```bash
cd /home/cat/ai/qwen3vl2b

EXP=output/exp07_1_record_stt_qwen_tts_once_$(date +%Y%m%d_%H%M%S)
./scripts/exp07_1_record_stt_qwen_tts_once.sh "$EXP" 6
```

---

### 16.4 underrun 对比复核

```bash
cd /home/cat/ai/qwen3vl2b

EXP=output/exp07_5_tts_underrun_compare_$(date +%Y%m%d_%H%M%S)
./scripts/exp07_5_tts_underrun_compare.sh "$EXP" 5
```

---

### 16.5 修复后 clean verify

```bash
cd /home/cat/ai/qwen3vl2b

EXP=output/exp07_8_once_nonstream_verify_clean_$(date +%Y%m%d_%H%M%S)
./scripts/exp07_8_once_nonstream_verify_clean.sh "$EXP" 5
```

---

## 17. 后续实验建议

实验 07 已经封口。后续可以进入：

```text
实验 08：摄像头拍照 -> Qwen3-VL 图文问答 -> TTS 播放
```

建议实验 08 目标链路：

```text
voice_assistant.py ask --force-photo
  或
CameraAdapter.capture()
  -> Qwen3-VL 图文问答
  -> TTS 播放
```

实验 08 暂时仍不接 KWS，优先验证：

```text
真实摄像头照片
  -> Qwen3-VL 图像理解
  -> 中文语音播报
```

再后续可以进入：

```text
实验 09：KWS 唤醒词 listen / listen-forever 完整助手流程
```

即：

```text
唤醒词
  -> 录音
  -> ASR
  -> 意图判断
  -> 摄像头 / Qwen
  -> TTS 播放
```

---

## 18. 实验 07 最终结论

实验 07 判定：**通过**。

本实验完成了 RK3588 端侧多模态语音助手的单轮语音问答闭环：

```text
record
  -> stt
  -> qwen
  -> tts
  -> play
```

并进一步完成了官方 once 入口稳定性优化：

```text
1. 手动串联闭环通过；
2. 官方 VoiceAssistant 初始化通过；
3. 官方 once 文本闭环通过；
4. 官方 once 语音闭环通过；
5. 定位原始 once 流式 TTS 存在 ALSA underrun；
6. 证明单独 tts-stream 和 ALSA 播放链路稳定；
7. 将 once 改为完整回答后整段 TTS 播放；
8. 修复后 once_return_code=0，underrun_count=0；
9. 用户确认可以听到语音回答。
```

最终项目从实验 06 的：

```text
Qwen 文本回答 -> TTS -> 语音输出
```

推进到实验 07 的：

```text
用户语音输入 -> ASR -> Qwen -> TTS -> 语音回答
```

这标志着端侧智能语音助手的核心单轮闭环已经正式打通。

---

# 实验 07 阶段性封口

```text
voice_assistant.py once
  -> record_command()
  -> transcribe_wav()
  -> ask_qwen()
  -> full-answer TTS playback
  -> plughw:2,0
```

实验 07 正式完成。
