# 实验 12：连续多轮稳定性与进程生命周期验证

## 1. 实验背景

在实验 11 中，项目已经完成了正式的 `IntentRouter` 重构，并分别验证了文本链路和视觉链路：

- KWS → ASR → 文本意图 → Qwen → TTS；
- KWS → ASR → 视觉意图 → Camera → Qwen → TTS；
- IntentRouter 单元测试与 Orchestrator 集成回归测试均已建立；
- 单轮文本、单轮视觉完整闭环能够正常工作；
- 但尚未验证长时间连续运行、多轮文本/视觉混合切换，以及长期父进程不退出时的资源生命周期。

因此实验 12 的目标不再是“证明单轮能运行”，而是验证：

> **语音助手在长期驻留、连续多轮、文本/视觉混合调用的情况下，是否仍能保持意图正确、资源稳定、子进程正确回收、性能不持续退化。**

实验 12 最终覆盖了四类问题：

1. 多轮真实 ASR 混合调用是否稳定；
2. 同一个 `VoiceAssistant` 实例反复调用时是否存在进程/线程/FD/内存泄漏；
3. Qwen `demo` 子进程在长期父进程中是否能正确退出并被回收；
4. KWS → 命令录音 → ASR → Intent → Camera/Qwen 的正式入口是否仍正常。

---

# 2. 实验目标

本实验的核心目标如下：

## 2.1 功能稳定性

验证连续执行：

```text
视觉 → 文本 → 视觉 → 文本
```

时：

- ASR 能正确识别命令；
- IntentRouter 能正确区分视觉与文本请求；
- 视觉轮次只拍 1 张照片；
- 文本轮次不误拍照；
- Qwen 能正常返回答案；
- TTS 能正常播放；
- 每轮结束后无异常残留进程。

## 2.2 长期进程生命周期

验证同一个 Python 主进程、同一个 `VoiceAssistant` 对象长期存活时：

- `demo` 是否残留；
- 是否产生 Zombie；
- FD 是否累积；
- 线程数是否累积；
- RSS 是否持续单调增长；
- 摄像头 / ffmpeg / arecord / aplay 是否残留；
- 多轮运行后推理耗时是否持续恶化。

## 2.3 Soak Test

将短期验证扩大到 40 轮：

```text
20 次视觉
+
20 次文本
=
40 次连续调用
```

通过更长时间的运行观察：

- 资源是否进入稳定平台；
- 是否出现长期漂移；
- 延迟是否逐渐增加；
- 温度是否持续升高并伴随性能劣化。

---

# 3. 实验环境

项目目录：

```bash
/home/cat/ai/qwen3vl2b
```

实验分支：

```text
exp/12-multiturn-stability
```

实验 12 起始基线：

```text
main HEAD: a8cef5b
```

实验 11 关键提交：

```text
19b90b1
refactor: formalize intent router and add regression tests
```

实验 12 开始时确认：

```text
main_contains_exp11=YES
current_head_contains_exp11=YES
```

主要运行环境：

```text
Python        : 3.9.2
Audio input   : plughw:2,0
Audio output  : plughw:2,0
ASR sample    : 16000 Hz
ASR channels  : 2
Camera        : /dev/video11
Camera script : scripts/capture-photo.sh
Photo dir     : /home/cat/图片
Qwen default max_new_tokens : 2048
```

---

# 4. 实验 12.0：基线审计

## 4.1 目的

在正式进行连续稳定性实验之前，先确认实验 11 的功能基线没有回归，包括：

- Git 分支与提交关系；
- Python 代码可编译；
- 实验 11 回归测试；
- `VoiceAssistant` 初始化；
- `listen-controlled` CLI；
- 摄像头；
- 音频设备；
- 内存；
- 文件句柄；
- 温度；
- CPU governor；
- 是否存在残留进程。

## 4.2 初次结果

代码编译：

```text
compile_return_code=0
```

回归测试：

```text
Ran 13 tests
OK
```

初始化：

```text
config_load=PASS
assistant_init=PASS
```

CLI：

```text
help_return_code=0
```

摄像头：

```text
camera_exists=1
/dev/video11
```

音频设备：

```text
card 2: rockchipes8388
```

内存：

```text
MemAvailable ≈ 14.9 GB
```

残留进程：

```text
residual_process_count=0
```

温度：

```text
约 34 ~ 35°C
```

但最终出现：

```text
dirty_count=1
result=FAIL
```

## 4.3 原因

这不是功能失败，而是因为刚刚创建的：

```text
scripts/exp12_0_baseline_audit.sh
```

尚未提交，导致 Git 工作区不是 clean。

脚本将 clean Git workspace 作为 PASS 条件，因此误判为：

```text
FAILED_OR_NEEDS_CHECK
```

将实验脚本提交后重新运行，实验 12.0 正式通过。

## 4.4 结论

实验 12 的起点基线正常：

- 实验 11 功能未回归；
- 硬件存在；
- Python 环境正常；
- 无残留进程；
- 可进入连续稳定性测试。

---

# 5. 实验 12.1：四轮真实混合交互验证

## 5.1 实验设计

为了先隔离验证 ASR、Intent、Camera、Qwen、TTS 连续切换能力，本阶段暂时使用：

```text
--skip-wake
```

即不重复验证 KWS，而是进行：

```text
录音 → ASR → IntentRouter → Camera/Qwen → TTS
```

固定顺序：

```text
Round 1：看一下画面
Round 2：一加一等于几
Round 3：拍照描述当前画面
Round 4：你是谁
```

期望拍照行为：

```text
1, 0, 1, 0
```

---

## 5.2 实验结果

总体结果：

```text
completed_round_count : 4
passed_round_count    : 4
result                : PASS
```

### Round 1：视觉

```text
expected_spoken_text   : 看一下画面
recognized_text        : 看一下画面
expected_photo         : 1
need_photo             : 1
actual_new_photo_count : 1
answer_chars           : 29
wall_elapsed_seconds   : 39.745
pipeline_seconds       : 19.512
tts_seconds            : 11.019
underrun_count         : 0
residual_process_count : 0
round_result           : PASS
```

### Round 2：文本数学问题

```text
expected_spoken_text   : 一加一等于几
recognized_text        : 一加一等于几
expected_photo         : 0
need_photo             : 0
actual_new_photo_count : 0
answer_chars           : 7
wall_elapsed_seconds   : 22.154
pipeline_seconds       : 8.242
tts_seconds            : 5.288
underrun_count         : 0
residual_process_count : 0
round_result           : PASS
```

### Round 3：视觉

```text
expected_spoken_text   : 拍照描述当前画面
recognized_text        : 拍照描述当前画面
expected_photo         : 1
need_photo             : 1
actual_new_photo_count : 1
answer_chars           : 35
wall_elapsed_seconds   : 32.819
pipeline_seconds       : 11.975
tts_seconds            : 12.267
underrun_count         : 0
residual_process_count : 0
round_result           : PASS
```

### Round 4：文本身份问题

```text
expected_spoken_text   : 你是谁
recognized_text        : 你是谁
expected_photo         : 0
need_photo             : 0
actual_new_photo_count : 0
answer_chars           : 40
wall_elapsed_seconds   : 31.106
pipeline_seconds       : 10.817
tts_seconds            : 11.696
underrun_count         : 0
residual_process_count : 0
round_result           : PASS
```

---

## 5.3 资源变化

四轮前后：

```text
MemAvailable:
15003760 KB
→
14987844 KB
```

变化：

```text
-15916 KB
≈ -15.5 MB
```

文件句柄：

```text
6176
→
6176
```

温度：

```text
34.2°C
→
37.0°C
```

最终残留：

```text
0
```

单轮内存变化：

```text
R1 : -11208 KB
R2 :  -1392 KB
R3 :  +1152 KB
R4 :   -452 KB
```

该变化不是持续单调下降，因此没有看到明显内存泄漏趋势。

---

## 5.4 延迟分析

两个文本请求耗时不同：

```text
一加一等于几：
answer_chars = 7
Qwen         ≈ 8.24 s
TTS          ≈ 5.29 s
Total        ≈ 22.15 s
```

```text
你是谁：
answer_chars = 40
Qwen         ≈ 10.82 s
TTS          ≈ 11.70 s
Total        ≈ 31.11 s
```

因此不能简单认为第 4 轮变慢是性能漂移。

主要原因是：

> **整段 TTS 模式下，回答越长，TTS 合成与播放耗时越长。**

---

# 6. 实验 12.2：同进程生命周期稳定性验证

## 6.1 为什么 12.1 还不够

12.1 的结构本质上是：

```text
测试主程序
  ├─ Python listen-controlled #1 → 退出
  ├─ Python listen-controlled #2 → 退出
  ├─ Python listen-controlled #3 → 退出
  └─ Python listen-controlled #4 → 退出
```

这类验证有一个问题：

> 即使单轮内部存在资源泄漏，只要 Python 子进程退出，Linux 也会回收绝大多数资源。

因此无法真正验证“长期驻留 Python 服务”内部是否存在：

- Zombie；
- FD 泄漏；
- 线程泄漏；
- 长期对象引用；
- 内存持续增长。

所以 12.2 改成：

```text
一个 Python
    ↓
创建一次 VoiceAssistant
    ↓
连续运行 10 轮
    ↓
最后才退出
```

---

# 7. 实验 12.2 初次运行：发现 Qwen demo Zombie

## 7.1 初次现象

第一轮视觉请求本身成功：

```text
intent_need_photo = 1
new_photo_count   = 1
semantic_ok       = 1
FD                = 6 → 6
```

但是检测到：

```text
residual_process_count = 1
```

测试程序为了防止资源继续积累，在第一轮后主动停止。

当时结果：

```text
round_count_completed : 1
round_pass_count      : 0
result                : FAIL
```

残留进程：

```text
345829 demo
```

---

## 7.2 最初排查

开始时不能确定 `demo` 是：

1. 仍然运行；
2. 退出较慢；
3. Zombie。

因此先增加了 10 秒轮询。

结果：

```text
residual_initial_count : 1
cleanup_seconds        : 10.795
residual_after_wait    : 1
```

即使等待 10 秒，`demo` 仍然存在。

说明不是普通的“异步退出延迟”。

---

# 8. 实验 12.2b：Qwen demo 生命周期精确诊断

## 8.1 诊断方法

创建独立探针，只运行：

```text
Python
 → QwenRunner
 → demo
 → 得到答案
 → QwenRunner 返回
 → 保持父进程 20 秒
 → 持续检查 /proc
```

完全绕开：

- Camera；
- ASR；
- IntentRouter；
- TTS。

目的是精确确认 `demo` 的 Linux 进程状态。

---

## 8.2 结果

Qwen 正常返回：

```text
elapsed_seconds : 8.177
answer          : 一加一等于二。
```

但是返回后立即：

```text
demo_count : 1
```

`ps`：

```text
383260 383245 ... Z ... demo <defunct>
```

`/proc/383260/status`：

```text
Name: demo
State: Z (zombie)
Pid: 383260
PPid: 383245
```

并且：

```text
+0s  : Zombie
+1s  : Zombie
+2s  : Zombie
+5s  : Zombie
+10s : Zombie
+15s : Zombie
+20s : Zombie
```

直到父 Python：

```text
parent_pid = 383245
```

退出后，再检查：

```text
demo = none
```

---

# 9. Zombie 根因分析

## 9.1 什么是 Zombie

此时 `demo` 并不是还在执行。

状态：

```text
Z (zombie)
```

表示：

> **子进程已经结束，但父进程尚未通过 `wait()` / `waitpid()` 读取退出状态，因此 Linux 仍保留其进程表项。**

因此 Zombie 本身通常已经释放：

- 模型运行内存；
- 大部分文件描述符；
- NPU 运行资源；
- CPU 运行资源。

但仍然残留：

- PID；
- exit status；
- 进程表项。

如果长期服务中每次调用都产生一个 Zombie：

```text
demo1 zombie
demo2 zombie
demo3 zombie
...
```

就会不断占用进程表，并证明父子进程生命周期管理不完整。

---

## 9.2 为什么之前实验没有发现

以前主要是：

```text
Python #1
 └─ demo
Python #1 退出

Python #2
 └─ demo
Python #2 退出
```

即使内部产生 Zombie，父 Python 很快退出，Zombie 会被系统重新接管并最终清理。

所以单轮测试表面仍然 PASS。

而实验 12.2：

```text
Python 长期不退出
```

才真正暴露出：

```text
demo 已死
但父 Python 没有 reap
```

的问题。

---

# 10. QwenRunner 生命周期修复

## 10.1 修复目标

修复 `QwenRunner._close_child()`。

原问题本质：

```text
pexpect child close
≠
保证子进程已经被父进程 reap
```

修复策略：

```text
child.close(force=True)
        ↓
os.waitpid(pid, WNOHANG)
        ↓
等待短暂退出
        ↓
若仍活着，SIGKILL 兜底
        ↓
os.waitpid(pid, 0)
        ↓
确保直接子进程被回收
```

补充的关键模块：

```python
import os
import signal
import time
```

核心原则：

> **关闭 PTY 不等于完成 Linux 子进程回收。**

最终必须确保：

```python
waitpid()
```

完成。

---

## 10.2 修复后单 Qwen 验证

修复后重新运行生命周期探针。

理想行为由修复前的：

```text
Qwen returned
+0s  demo_count=1, State=Z
...
+20s demo_count=1
```

变为：

```text
Qwen returned
+0s demo_count=0
```

并在后续同进程多轮测试中，每一轮均观察到：

```text
residual_initial_count = 0
```

这说明并不是“等待 10 秒后才被清理”，而是：

> **QwenRunner 返回调用者时，demo 已经被正确 reap。**

---

# 11. 实验 12.2 修复后：10 轮同进程验证

## 11.1 测试顺序

固定进行：

```text
01 visual
02 text
03 visual
04 text
05 visual
06 text
07 visual
08 text
09 visual
10 text
```

同一个：

```text
VoiceAssistant
```

实例连续完成。

---

## 11.2 结果

最终：

```text
round_count_expected  : 10
round_count_completed : 10
round_pass_count      : 10
result                : PASS
```

视觉：

```text
5 / 5
```

文本：

```text
5 / 5
```

照片：

```text
expected_total_new_photos : 5
actual_total_new_photos   : 5
```

---

## 11.3 demo 生命周期

每轮：

```text
residual_initial    : 0
cleanup_seconds     : 0.0
residual_after_wait : 0
```

最终：

```text
final_residual_process_count : 0
```

说明 Zombie 修复生效。

---

## 11.4 FD

```text
baseline_fd_count : 6
final_fd_count    : 6
final_fd_delta    : 0
fd_ok             : 1
```

没有 FD 泄漏。

---

## 11.5 线程

```text
baseline_thread_count : 8
final_thread_count    : 1
final_thread_delta    : -7
thread_ok             : 1
```

首次初始化阶段存在额外线程，真实运行后线程数稳定为 1。

没有线程持续累积。

---

## 11.6 RSS

```text
baseline_rss_kb    : 45556
final_rss_kb       : 232812
final_rss_delta_kb : 187256
rss_warning        : 0
```

这一增长主要发生在第一次真实模型/TTS调用之后。

后续 RSS 长期保持在约：

```text
226 ~ 234 MB
```

范围。

因此该现象更符合：

```text
第一次调用
→ runtime / allocator / shared library / cache 初始化
→ RSS 一次性阶跃
→ 后续进入平台
```

而不是：

```text
Round1 < Round2 < Round3 < ...
```

的持续泄漏。

---

## 11.7 延迟

视觉：

```text
visual_first_seconds  : 30.249
visual_last_seconds   : 29.122
visual_median_seconds : 29.122
```

文本：

```text
text_first_seconds  : 12.990
text_last_seconds   : 12.440
text_median_seconds : 12.440
```

没有出现随轮次增加而持续变慢。

---

# 12. 实验 12.3：40 轮 Same-Process Soak Test

## 12.1 目的

10 轮只能证明基本生命周期修复。

为了观察：

- 更长时间内 RSS 是否漂移；
- FD 是否积累；
- 线程是否积累；
- Qwen demo 是否重新出现残留；
- 温度升高后性能是否恶化；

将测试扩大到 40 轮。

---

## 12.2 实验组成

```text
20 次 visual
+
20 次 text
=
40 轮
```

固定：

- 同一个 Python；
- 同一个 `VoiceAssistant`；
- 真实 Camera；
- 真实 Qwen；
- 真实 TTS；
- 固定文本问题；
- 固定视觉 prompt。

---

# 13. 实验 12.3 结果

## 13.1 总体

```text
round_count_expected  : 40
round_count_completed : 40
round_pass_count      : 40
result                : PASS
```

文本：

```text
20 / 20 PASS
```

视觉：

```text
20 / 20 PASS
```

照片：

```text
expected_total_new_photos : 20
actual_total_new_photos   : 20
```

即：

> **20 个视觉轮次全部恰好拍照 1 次，20 个文本轮次全部没有误拍。**

---

## 13.2 Zombie / 子进程

40 轮：

```text
residual_initial_total    : 0
residual_after_wait_total : 0
```

最终：

```text
final_residual_process_count : 0
```

说明修复后的：

```text
QwenRunner._close_child()
```

在长时间连续运行中仍然稳定。

---

## 13.3 FD

```text
baseline_fd_count : 6
final_fd_count    : 6
final_fd_delta    : 0
fd_unique         : [6]
```

40 轮整个过程：

```text
FD = 6
```

没有任何累积。

---

## 13.4 线程

热启动后：

```text
thread_unique : [1]
```

最终：

```text
thread_ok : 1
```

没有线程泄漏。

---

# 14. RSS 长期稳定性

初始：

```text
baseline_rss_kb : 45624
```

最终：

```text
final_rss_kb : 226032
```

看绝对值似乎增加了约 180 MB。

但必须去掉第一次 runtime 热启动。

去掉前期 warm-up 后：

```text
rss_min_after_warmup_kb : 216760
rss_max_after_warmup_kb : 248512
```

早期窗口中位数：

```text
218418 KB
```

后期窗口中位数：

```text
222960 KB
```

增长：

```text
4542 KB
≈ 4.4 MB
```

40 轮运行后只出现约 4.4 MB 的窗口中位数差异，而且过程中 RSS 在：

```text
216 ~ 248 MB
```

之间来回波动。

因此没有观察到：

```text
单调持续上涨
```

这种典型泄漏特征。

最终判断：

> **RSS 在首次模型调用后发生一次性热启动阶跃，随后长期维持平台型波动，没有发现明显内存泄漏。**

---

# 15. 延迟长期稳定性

## 15.1 文本

整体：

```text
text_median_seconds : 12.505
```

早期：

```text
12.653 s
```

后期：

```text
12.537 s
```

几乎没有差异。

说明：

> **固定文本请求的长时间延迟非常稳定，没有随轮次增加而恶化。**

---

## 15.2 视觉

整体：

```text
visual_median_seconds : 25.197
```

早期：

```text
28.098 s
```

后期：

```text
24.629 s
```

后期甚至略快。

视觉耗时波动较大，主要与 Qwen 输出长度有关。

典型对比：

```text
Round 17：
answer_chars = 21
elapsed      = 20.059 s
```

```text
Round 19：
answer_chars = 79
elapsed      = 36.881 s
```

因此视觉总耗时不能只按轮次直接比较。

当前没有证据表明：

```text
运行越久
→ Qwen 越慢
```

---

# 16. 温度

12.3：

```text
baseline_temperature_c : 35.2
final_temperature_c    : 41.6
```

表格中个别采样达到：

```text
42.5°C
```

但：

- 文本延迟没有增加；
- 视觉后期中位数没有增加；
- 没有出现错误；
- 没有出现异常退出。

因此目前只能得出：

> **在本次 40 轮负载下，没有观察到温度升高伴随的持续性能退化。**

注意：

本实验并没有读取所有硬件 throttle 状态，因此不能进一步断言“绝对没有发生 DVFS / thermal throttling”。

---

# 17. 实验 12.4 初次 listen-forever 验证：INVALID

## 17.1 原始目标

为了最终补齐：

```text
KWS
→ ASR
→ Intent
→ Camera / Qwen
```

在长期入口中的表现，设计了：

```text
listen-forever
```

连续 6 轮人工 KWS 测试。

期望：

```text
1 鲁班猫 → 看一下画面
2 鲁班猫 → 一加一等于几
3 鲁班猫 → 看一下画面
4 鲁班猫 → 你是谁
5 鲁班猫 → 看一下画面
6 鲁班猫 → 一加一等于几
```

---

## 17.2 现象

开始后连续出现：

```text
arecord:
audio open error:
设备或资源忙
```

第 6 轮一度：

```text
wake=鲁班猫
```

随后开始命令录音：

```text
Recording WAVE '/tmp/qwen_voice_assistant/command.wav'
```

但随后又出现：

```text
[Errno 2]
No such file or directory:
'/tmp/qwen_voice_assistant/command.wav'
```

按 Ctrl+C 后脚本已经输出 summary 并返回 shell，但后台仍继续：

```text
等待唤醒词，第 9 轮
...
等待唤醒词，第 19 轮
```

并出现：

```text
final_arecord_count : 1
```

---

# 18. 12.4 初版为什么无效

## 18.1 Bash 后台 Pipeline PID 获取错误

原测试脚本使用：

```bash
"$PY" voice_assistant.py listen-forever \
    ... \
    2>&1 | tee "$LOG" &

LISTEN_PID=$!
```

这一写法中：

```text
Python listen-forever
        |
       tee
        &
```

`$!` 对应的是后台 pipeline 最后一个命令，实际拿到的并不是业务 Python 的真实生命周期。

结果：

- 监控进程监控错 PID；
- `wait` 等错进程；
- Ctrl+C 没有可靠终止真正的 `listen-forever`；
- `arecord` 继续存在；
- 麦克风被占用；
- 后续轮次不停报 “设备或资源忙”。

---

## 18.2 错误 RSS 是直接证据

12.4 初次 summary：

```text
first_rss_kb : 476
last_rss_kb  : 476
max_rss_kb   : 476
```

真正的 Python `VoiceAssistant` 不可能只有约 476 KB RSS。

因此该监控数据明显不是目标 Python。

---

## 18.3 实验判定

该次实验应记为：

```text
INVALID
```

而不是：

```text
Project FAIL
```

原因是：

> **测试 harness 自己的后台进程管理错误，导致测量对象和资源生命周期均不可信。**

因此：

- RSS 数据作废；
- 轮次结果作废；
- 麦克风占用属于测试脚本残留影响；
- 不能用这一轮评价正式 KWS/ASR 链路。

---

# 19. 实验 12.4a：单轮正式 KWS 链路复核

清理残留进程以后，重新使用成熟的：

```text
listen-controlled
```

执行单轮真实 KWS。

命令参数：

```text
wake_mode       : kws
wake_timeout    : 30
record_seconds  : 5
prepare_delay   : 2.0
answer_mode     : concise
max_new_tokens  : 128
no_speak
no_play
```

---

## 19.1 实际过程

状态：

```text
WAIT_WAKE
```

检测：

```text
WAKE_DETECTED | 鲁班猫
```

然后：

```text
PREPARE_RECORD | delay=2.000s
```

录音：

```text
RECORDING | seconds=5
```

音频：

```text
duration = 5.000 s
mean     = -25.824 dBFS
max      = -0.000 dBFS
```

ASR：

```text
拍照看一下画面
```

Intent：

```text
photo_hint = 1
```

拍照：

```text
/home/cat/图片/voice_20260812_183951.jpg
```

Qwen：

```text
pipeline_elapsed_seconds = 14.295
answer_chars              = 50
```

回答：

```text
一名男子倒挂在天花板上，身穿灰色上衣，戴着眼镜，
双手握着物体，背景是带有电路板图案的白色墙壁和窗户。
```

最终：

```text
COMPLETED
[RESULT] listen-controlled PASSED
```

---

## 19.2 Summary

```text
status                  : PASSED
exit_code               : 0
wake_mode               : kws
wake_text               : 鲁班猫
skip_wake               : 0
prepare_delay           : 2.0
record_seconds          : 5
recognized_text         : 拍照看一下画面
recognized_chars        : 7
photo_intent_hint       : 1
new_photo_count         : 1
answer_chars            : 50
pipeline_elapsed_seconds: 14.295
tts_elapsed_seconds     : 0.000
elapsed_seconds         : 31.774
error                   :
```

最终没有：

- `arecord` 残留；
- `demo` 残留；
- 录音文件异常；
- 意图错误。

---

# 20. 实验 12 最终结果总表

| 子实验 | 目的 | 结果 |
|---|---|---|
| 12.0 | 基线审计 | PASS |
| 12.1 | 四轮真实 ASR 混合交互 | PASS |
| 12.2 初版 | 同进程生命周期 | 发现 Zombie |
| 12.2b | demo 生命周期诊断 | 确认 Zombie |
| 12.2c | QwenRunner 回收修复 | PASS |
| 12.2 修复后 | 10 轮同进程 | 10/10 PASS |
| 12.3 | 40 轮 Soak Test | 40/40 PASS |
| 12.4 初版 | listen-forever + Bash monitor | INVALID |
| 12.4a | 单轮 KWS 正式链路复核 | PASS |

---

# 21. 实验 12 关键最终指标

## 多轮功能

```text
12.1:
4 / 4 PASS
```

```text
12.2:
10 / 10 PASS
```

```text
12.3:
40 / 40 PASS
```

## 视觉路由

40 轮中：

```text
expected photos : 20
actual photos   : 20
```

无漏拍、无文本误拍。

## Zombie

修复前：

```text
demo
State: Z (zombie)
20 秒不消失
```

修复后：

```text
residual_initial_total    : 0
residual_after_wait_total : 0
```

## FD

```text
6 → 6
```

## 线程

热启动后：

```text
1
```

稳定。

## RSS

热启动后：

```text
216 ~ 248 MB
```

早期窗口：

```text
218418 KB
```

后期窗口：

```text
222960 KB
```

增长约：

```text
4.4 MB
```

无持续单调上涨。

## 延迟

文本：

```text
early median : 12.653 s
late median  : 12.537 s
```

视觉：

```text
early median : 28.098 s
late median  : 24.629 s
```

没有长期性能恶化。

## 温度

40 轮：

```text
baseline : 35.2°C
final    : 41.6°C
max observed ≈ 42.5°C
```

没有观察到温度升高导致的明显性能退化。

---

# 22. 本实验真正解决的问题

实验 12 最重要的结果并不是：

```text
跑了 40 次
```

而是建立了一个完整的 Linux 长驻服务调试闭环：

```text
连续稳定性测试
        ↓
发现 Qwen demo 残留
        ↓
增加生命周期轮询
        ↓
确认不是 cleanup latency
        ↓
ps + /proc 精确检查
        ↓
State = Z (zombie)
        ↓
确认父 Python 未 wait/reap
        ↓
修改 QwenRunner._close_child()
        ↓
显式 waitpid
        ↓
重新单 Qwen 验证
        ↓
10 轮 same-process
        ↓
40 轮 soak
        ↓
FD / Thread / RSS / Temp / Latency 全验证
```

这是本项目从：

```text
功能跑通
```

升级到：

```text
长期运行工程稳定性
```

的关键实验。

---

# 23. Linux 知识点总结

## 23.1 子进程退出不等于完全消失

Linux 子进程结束后，父进程需要：

```c
wait()
```

或：

```c
waitpid()
```

读取退出状态。

否则：

```text
子进程已经死亡
+
父进程还活着
+
父进程未 wait
=
Zombie
```

---

## 23.2 Zombie 不是正在运行的进程

Zombie 一般已经释放绝大多数资源。

因此不能使用：

```text
kill zombie
```

解决问题。

真正的解决者必须是：

```text
父进程
```

执行：

```text
wait / waitpid
```

---

## 23.3 单轮程序容易掩盖生命周期问题

如果：

```text
Python
  ↓
child zombie
  ↓
Python 很快退出
```

测试往往看不出来。

只有：

```text
long-lived parent process
```

才能真正暴露问题。

---

## 23.4 shell pipeline 的 `$!` 要谨慎

例如：

```bash
python app.py | tee app.log &
PID=$!
```

这里：

```text
PID
```

并不天然等于你真正想管理的业务进程。

因此长期 daemon / service / soak test 更适合使用：

- Python `subprocess.Popen`；
- `start_new_session=True`；
- process group；
- systemd；
- 或显式保存真实 child PID。

---

# 24. 建议保留的实验资产

建议正式保留：

```text
scripts/exp12_0_baseline_audit.sh
scripts/exp12_1_four_round_mixed_validation.py
scripts/exp12_2_same_process_lifecycle.py
scripts/exp12_2b_qwen_demo_lifecycle_probe.py
tests/test_qwen_runner_lifecycle.py
voice_assistant/qwen_runner.py
```

其中：

```text
exp12_2b_qwen_demo_lifecycle_probe.py
```

非常适合作为以后排查类似：

- Zombie；
- child process；
- pexpect；
- process lifecycle；

问题时的诊断工具。

临时 `.bak` 文件不应提交。

实验 12.4 初版有 PID 管理缺陷的 Bash monitor 不建议作为正式最终测试工具保留，除非后续重写。

---

# 25. 建议的 Git 提交语义

本实验至少应体现两个维度：

## 生命周期修复

```text
fix: reap Qwen demo child processes in long-lived sessions
```

## 稳定性测试资产

```text
test: add multi-turn and same-process stability validation
```

实验最终完成后，再将实验 12 分支合并回：

```text
main
```

---

# 26. 项目层面的工程能力体现

实验 12 可用于体现以下能力：

## 26.1 Linux 进程管理

- `ps`
- `/proc/<pid>/status`
- `State`
- `PPid`
- `PGID`
- `SID`
- Zombie
- `waitpid`
- signal
- child process lifecycle

## 26.2 Python 子进程管理

- `pexpect`
- subprocess 生命周期；
- child cleanup；
- `close(force=True)` 与 `waitpid()` 的区别；
- 长驻父进程中的资源回收。

## 26.3 稳定性测试

- same-process validation；
- soak test；
- 10 轮 / 40 轮连续调用；
- warm-up 与稳态区分；
- early/late window 对比。

## 26.4 可观测性

持续记录：

- RSS；
- FD；
- Thread；
- temperature；
- latency；
- residual process；
- photo count；
- route accuracy。

## 26.5 故障隔离

能够区分：

```text
产品代码 FAIL
```

和：

```text
test harness INVALID
```

例如 12.4 初版就是后者。

这是一项非常重要的工程能力：

> **测试失败并不等价于被测系统失败，必须先确认测试工具自身是可信的。**

---

# 27. 可用于简历/面试的技术总结

可将实验 12 概括为：

> 针对 RK3588 端侧多模态语音助手开展长期稳定性验证，构建文本/视觉混合 same-process 与 40 轮 soak test，持续监控 RSS、FD、线程、温度、延迟和子进程状态；定位 Qwen `pexpect` 子进程在长期父进程中的 Zombie 问题，通过 `/proc` 与 `ps` 确认子进程已退出但未被父进程 `wait/reap`，重构 `QwenRunner` 清理逻辑并增加显式 `waitpid` 回收。修复后完成 10 轮和 40 轮同进程连续验证，FD 恒定、线程稳定、RSS 热启动后进入平台区、无 `demo` 残留，并再次验证 KWS→ASR→视觉问答正式链路。

---

# 28. 最终结论

实验 12 最终证明：

1. 语音助手能够连续进行文本/视觉任务切换；
2. IntentRouter 在多轮场景下没有出现明显误路由；
3. 视觉请求可以正确触发 Camera；
4. 文本请求不会误拍照；
5. Qwen/TTS 在连续运行中保持可用；
6. 发现并修复了 Qwen `demo` Zombie 生命周期问题；
7. 修复后 10 轮 same-process 全部通过；
8. 40 轮 Soak Test 全部通过；
9. FD 无增长；
10. 线程无累积；
11. RSS 首轮热启动后进入稳定平台，没有明显内存泄漏；
12. 文本与视觉延迟没有出现随运行时间增加而持续恶化；
13. 长时间运行温度上升但没有观察到明显性能退化；
14. KWS → 录音 → ASR → Intent → Camera/Qwen 正式入口再次验证通过；
15. 12.4 初版失败被证明是测试 harness 自身的 Bash 后台 PID 管理问题，而不是正式业务链路失败。

因此：

> **实验 12 已经完成从“单轮功能正确”到“长期驻留进程、多轮混合调用、资源生命周期正确”的工程验证，可以正式结束。**

下一阶段不建议继续无意义堆叠更多轮次，而应转向后续新的优化主题，例如：

- VAD / 动态录音结束；
- Qwen 长驻推理进程；
- TTS 延迟优化；
- 真正常驻的 `listen-forever` 服务化；
- 系统级性能 profiling；
- 或项目最终简历/面试材料整理。
