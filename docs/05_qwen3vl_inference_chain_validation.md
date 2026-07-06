# 实验 05：Qwen3-VL 本地图文推理与 ASR→Qwen 半闭环验证

> 项目：RK3588 端侧多模态智能语音助手系统  
> 平台：LubanCat / RK3588  
> 仓库目录：`/home/cat/ai/qwen3vl2b`  
> 实验编号：05  
> 实验主题：Qwen3-VL-2B RKNN/RKLLM 资产补齐、原生 demo 推理、QwenRunner 项目入口验证、ASR→Qwen 半闭环验证  
> 实验状态：**通过**  
> 记录日期：2026-07-06

---

## 1. 实验背景

前置实验已经完成了三个关键底座：

```text
实验 01-02：音频硬件与项目录音链路验证
实验 03：摄像头拍照链路验证
实验 04：Sherpa-ONNX 离线中文 ASR 链路验证
```

到实验 04 结束时，系统已经具备：

```text
麦克风
  -> 录音 record
  -> Sherpa-ONNX ASR
  -> 中文文本输出
```

但是完整语音助手的核心仍然缺少大模型推理能力：

```text
中文文本 / 图片
  -> Qwen3-VL-2B
  -> 文本回答
```

因此，实验 05 的目标不是直接运行完整助手，而是按照模块化验证原则，逐层确认：

```text
1. Qwen3-VL 所需本地资产是否齐全；
2. RKNN/RKLLM runtime 是否匹配当前 demo；
3. 原生 demo 是否能完成图文推理；
4. 项目 QwenRunner 是否能独立驱动 demo；
5. voice_assistant.py ask 入口是否能绕开完整 orchestrator 依赖；
6. ASR 输出文本是否可以送入 Qwen 并获得回答。
```

---

## 2. 实验目标

实验 05 需要回答以下问题：

```text
1. 项目根目录是否补齐 demo / imgenc / runtime / RKNN / RKLLM 资产；
2. 当前 demo 的真实启动参数是什么；
3. Qwen3-VL 原生 demo 是否能在 RK3588 上输出有效回答；
4. voice_assistant/qwen_runner.py 是否能通过 pexpect 驱动 demo；
5. voice_assistant.py ask 是否存在与 ASR / TTS / orchestrator 的依赖耦合；
6. 如何修复 ask 的轻量入口，使其只验证 Qwen 链路；
7. record -> stt -> ask 能否形成“语音输入到 Qwen 回答”的半闭环。
```

---

## 3. 实验 05 总体拆分

本实验拆分为以下阶段：

```text
05.0 Qwen 资产缺失确认与补齐
05.1 Qwen3-VL 原生 demo 图文推理验证
05.2 voice_assistant.py ask / QwenRunner 项目入口验证
05.2a QwenRunner 直接调用验证
05.2b ask 轻量入口修复
05.3 record -> stt -> qwen 半闭环验证
```

---

## 4. 实验 05.0：Qwen 资产缺失确认与补齐

### 4.1 初始缺失状态

最开始在项目根目录检查：

```bash
cd /home/cat/ai/qwen3vl2b

ls -lh \
  demo \
  imgenc \
  librknnrt.so \
  librkllmrt.so \
  qwen3-vl-2b_vision_rk3588.rknn \
  qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
```

结果显示 6 个文件全部缺失：

```text
ls: 无法访问 'demo': 没有那个文件或目录
ls: 无法访问 'imgenc': 没有那个文件或目录
ls: 无法访问 'librknnrt.so': 没有那个文件或目录
ls: 无法访问 'librkllmrt.so': 没有那个文件或目录
ls: 无法访问 'qwen3-vl-2b_vision_rk3588.rknn': 没有那个文件或目录
ls: 无法访问 'qwen3-vl-2b-instruct_w8a8_rk3588.rkllm': 没有那个文件或目录
```

这说明当时不能进入 Qwen 推理阶段。此时不是代码错误，而是模型资产和运行资产不存在。

---

### 4.2 README 与 .gitignore 说明

查看仓库说明后确认：

```text
仓库不会提交大模型资产和第三方 runtime。
```

`.gitignore` 中明确排除了：

```text
/models/
/*.rknn
/*.rkllm
/demo
/imgenc
/*.so
```

因此这些文件需要手动补齐到项目根目录。

---

### 4.3 本地板端搜索结果

对 `/home/cat/ai` 以及更广范围进行搜索后，最初没有找到 Qwen3-VL 模型，但后来深度搜索找到了已有的 runtime：

```text
/home/cat/lubancat_ai_manual_code/dev_env/rkllm/rkllm-runtime/Linux/librkllm_api/aarch64/librkllmrt.so
/home/cat/lubancat_ai_manual_code/example/3rdparty/rknpu2/Linux/aarch64/librknnrt.so
```

随后将 runtime 复制到项目根目录，缺失项从 6 个减少到 4 个：

```text
[OK] librknnrt.so
[OK] librkllmrt.so
[MISS] demo
[MISS] imgenc
[MISS] qwen3-vl-2b_vision_rk3588.rknn
[MISS] qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
missing_qwen_assets: 4
```

但是此时仍然不能进行真实 Qwen 推理，因为最核心的 `demo/imgenc` 和两个模型还缺失。

---

### 4.4 从外部下载并传入板子

最终在电脑端下载到如下目录：

```text
E:\3588_qwen\zichan
```

然后传入板端中转目录：

```text
/home/cat/ai/qwen_assets_inbox
```

传入后目录结构为：

```text
/home/cat/ai/qwen_assets_inbox/zichan/WebTool
├── Quickstart
│   ├── demo_Linux_aarch64
│   │   ├── demo
│   │   ├── imgenc
│   │   └── lib
│   │       ├── librknnrt.so
│   │       └── librkllmrt.so
│   └── demo_Android_arm64-v8a
└── Qwen3-VL-2B
    ├── qwen3-vl-2b_vision_rk3588.rknn
    └── qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
```

其中必须使用：

```text
Quickstart/demo_Linux_aarch64
```

不能使用：

```text
Quickstart/demo_Android_arm64-v8a
```

因为当前系统是 RK3588 Debian/Linux，不是 Android。

---

### 4.5 最终复制到项目根目录

执行复制：

```bash
cd /home/cat/ai/qwen3vl2b

cp -av /home/cat/ai/qwen_assets_inbox/zichan/WebTool/Quickstart/demo_Linux_aarch64/demo ./demo
cp -av /home/cat/ai/qwen_assets_inbox/zichan/WebTool/Quickstart/demo_Linux_aarch64/imgenc ./imgenc
cp -av /home/cat/ai/qwen_assets_inbox/zichan/WebTool/Quickstart/demo_Linux_aarch64/lib/librknnrt.so ./librknnrt.so
cp -av /home/cat/ai/qwen_assets_inbox/zichan/WebTool/Quickstart/demo_Linux_aarch64/lib/librkllmrt.so ./librkllmrt.so
cp -av /home/cat/ai/qwen_assets_inbox/zichan/WebTool/Qwen3-VL-2B/qwen3-vl-2b_vision_rk3588.rknn ./qwen3-vl-2b_vision_rk3588.rknn
cp -av /home/cat/ai/qwen_assets_inbox/zichan/WebTool/Qwen3-VL-2B/qwen3-vl-2b-instruct_w8a8_rk3588.rkllm ./qwen3-vl-2b-instruct_w8a8_rk3588.rkllm

chmod +x demo imgenc
```

---

### 4.6 最终资产验收结果

重新运行 `exp05_0_qwen_asset_dryrun.sh`，结果如下：

```text
[OK] demo
-rwxr-xr-x 1 cat cat 6.6M  7月  4 20:26 demo

[OK] imgenc
-rwxr-xr-x 1 cat cat 6.6M  7月  4 20:26 imgenc

[OK] librknnrt.so
-rw-r--r-- 1 cat cat 7.4M  7月  4 20:26 librknnrt.so

[OK] librkllmrt.so
-rw-r--r-- 1 cat cat 7.2M  7月  4 20:26 librkllmrt.so

[OK] qwen3-vl-2b_vision_rk3588.rknn
-rw-r--r-- 1 cat cat 812M  7月  4 20:39 qwen3-vl-2b_vision_rk3588.rknn

[OK] qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
-rw-r--r-- 1 cat cat 2.3G  7月  4 20:35 qwen3-vl-2b-instruct_w8a8_rk3588.rkllm

missing_qwen_assets: 0
[RESULT] Qwen assets complete. Continue to real Qwen inference.
```

结论：实验 05.0 通过。

---

## 5. demo 启动参数确认

补齐资产后，查看 `demo` 的真实 usage：

```bash
cd /home/cat/ai/qwen3vl2b
export LD_LIBRARY_PATH=.:${LD_LIBRARY_PATH:-}

./demo 2>&1 | head -100 || true
./demo --help 2>&1 | head -100 || true
strings ./demo | grep -iE "Usage|image_path|platform|rk3588|max_new|context|img_start|img_end|img_content" | head -100
```

输出：

```text
Usage: ./demo image_path encoder_model_path llm_model_path max_new_tokens max_context_len rknn_core_num [img_start] [img_end] [img_content]
```

这说明当前下载到的 `demo` 不需要额外传入 `rk3588` 平台参数。

因此当前项目的启动参数是匹配的：

```text
./demo image_path vision_model llm_model max_new_tokens max_context_len rknn_core_num img_start img_end img_content
```

也就是：

```text
/home/cat/ai/qwen3vl2b/demo \
  /home/cat/ai/qwen3vl2b/demo.jpg \
  /home/cat/ai/qwen3vl2b/qwen3-vl-2b_vision_rk3588.rknn \
  /home/cat/ai/qwen3vl2b/qwen3-vl-2b-instruct_w8a8_rk3588.rkllm \
  2048 4096 3 \
  <|vision_start|> <|vision_end|> <|image_pad|>
```

---

## 6. 实验 05.1：Qwen3-VL 原生 demo 图文推理验证

### 6.1 实验目的

验证最底层的原生 demo 是否可以直接完成图文问答：

```text
demo.jpg
  -> demo
  -> vision RKNN
  -> LLM RKLLM
  -> Qwen3-VL 回答
```

该实验不通过 `voice_assistant.py`，也不通过 `QwenRunner`，目的是先证明 Qwen3-VL demo 本身可用。

---

### 6.2 测试方式

使用 `pexpect` 自动启动 demo，等待 `user:` 提示符，然后发送问题：

```text
<image>请用中文简短描述这张图片里有什么。
```

---

### 6.3 运行结果

关键输出：

```text
========== clean answer ==========
这是一张太空主题的创意照片，描绘了一位宇航员在月球表面悠闲地坐着，手中拿着一瓶绿色的啤酒。背景是地球和浩瀚星空，营造出一种孤独而宁静的氛围。

elapsed_seconds: 20.549
[RESULT] Experiment 05.1 PASSED
```

内存状态：

```text
内存：15Gi total，1.1Gi used，8.7Gi free，11Gi available
交换：0B
```

说明：

```text
1. demo 可以正常启动；
2. vision RKNN 模型可以加载；
3. LLM RKLLM 模型可以加载；
4. Qwen3-VL 可以理解 demo.jpg；
5. 输出回答与图片内容一致；
6. 单次图文问答耗时约 20.549 秒。
```

实验 05.1 判定：**通过**。

---

### 6.4 关于日志中的动态库异常

实验日志中出现过：

```text
./demo: error while loading shared libraries: librkllmrt.so: cannot open shared object file: No such file or directory
```

这不是最终推理失败。

原因是脚本中用于查看 usage 的命令：

```bash
./demo 2>&1 | head -20
```

没有显式设置：

```bash
LD_LIBRARY_PATH=.
```

而真正的 pexpect 推理分支设置了：

```python
env["LD_LIBRARY_PATH"] = f"{project}:{env.get('LD_LIBRARY_PATH', '')}"
```

所以真实推理成功。

后续脚本可以将 usage 检查命令改为：

```bash
LD_LIBRARY_PATH=. ./demo 2>&1 | head -20 || true
```

---

## 7. 实验 05.2：项目 QwenRunner / CLI 入口验证

### 7.1 初始失败：voice_assistant.py ask 被 ASR 依赖阻塞

运行项目入口：

```bash
python3 voice_assistant.py ask "<image>请用中文简短描述这张图片里有什么。" \
  --image demo.jpg \
  --no-speak \
  --no-play
```

初始结果：

```text
return_code: 1
elapsed_seconds: 1
[RESULT] Experiment 05.2 FAILED
```

错误信息：

```text
Traceback (most recent call last):
  File "/home/cat/ai/qwen3vl2b/voice_assistant.py", line 6, in <module>
    main()
  File "/home/cat/ai/qwen3vl2b/voice_assistant/cli.py", line 184, in main
    from .orchestrator import VoiceAssistant
  File "/home/cat/ai/qwen3vl2b/voice_assistant/orchestrator.py", line 7, in <module>
    from .asr import SherpaAsr
  File "/home/cat/ai/qwen3vl2b/voice_assistant/asr.py", line 5, in <module>
    import sherpa_onnx
ModuleNotFoundError: No module named 'sherpa_onnx'
```

问题本质：

```text
ask --no-speak --no-play 只需要 QwenRunner，不需要 ASR；
但 cli.py 在 ask 分支执行前提前导入完整 orchestrator；
orchestrator 又导入 asr.py；
最终导致 ask 被 sherpa_onnx 阻塞。
```

这不是 Qwen 模型失败，而是 CLI 入口的依赖耦合问题。

---

## 8. 实验 05.2a：QwenRunner 直接调用验证

### 8.1 实验目的

为了确认问题是否只在 CLI 层，绕开 `voice_assistant.py ask`，直接调用：

```python
from voice_assistant.config import load_config
from voice_assistant.qwen_runner import QwenRunner

cfg = load_config("config/default.yaml")
runner = QwenRunner(cfg)
answer = runner.ask("demo.jpg", "<image>请用中文简短描述这张图片里有什么。")
```

---

### 8.2 运行结果

输出：

```text
========== answer ==========
这是一张太空主题的创意照片，描绘了一位宇航员在月球表面悠闲地坐着，手中拿着一瓶绿色的啤酒。背景是地球和浩瀚星空，营造出一种孤独而宁静的氛围。
[RESULT] Experiment 05.2a PASSED
```

结论：

```text
QwenRunner 本身没有问题；
QwenRunner 可以独立驱动 demo；
失败只发生在 voice_assistant.py ask 的 CLI 调度层。
```

实验 05.2a 判定：**通过**。

---

## 9. 实验 05.2b：修复 ask 轻量入口

### 9.1 修复思路

在 `voice_assistant/cli.py` 中新增轻量 ask 分支：

```text
ask --no-speak --no-play
  -> 只导入 config + qwen_runner
  -> 不构造 VoiceAssistant
  -> 不导入 orchestrator
  -> 不导入 asr.py
  -> 不依赖 sherpa_onnx
```

---

### 9.2 新增函数

新增：

```python
def _ask_without_heavy_import(args: argparse.Namespace) -> None:
    from .config import load_config
    from .qwen_runner import QwenRunner

    config = load_config(args.config)
    qwen = config.get("qwen", {})
    paths = config.get("paths", {})

    image_path = args.image

    if args.force_photo:
        from .camera import CameraAdapter
        image_path = str(CameraAdapter(config).capture())

    if not image_path:
        image_path = paths.get("placeholder_image", "demo.jpg")

    text = args.text
    marker = qwen.get("demo_image_marker", "<image>")

    if (args.image or args.force_photo) and marker and marker not in text:
        text = marker + text

    print("========== lightweight ask ==========")
    print("image :", image_path)
    print("text  :", text)
    print()

    answer = QwenRunner(config).ask(image_path, text)
    print(answer)
```

在 `main()` 中增加：

```python
if args.cmd == "ask" and args.no_speak and args.no_play:
    _ask_without_heavy_import(args)
    return
```

---

### 9.3 重新运行实验 05.2

结果：

```text
return_code: 0
elapsed_seconds: 14
[RESULT] Experiment 05.2 PASSED
```

标准输出：

```text
========== lightweight ask ==========
image : demo.jpg
text  : <image>请用中文简短描述这张图片里有什么。

这是一张太空主题的创意照片，描绘了一位宇航员在月球表面悠闲地坐着，手中拿着一瓶绿色的啤酒。背景是地球和浩瀚星空，营造出一种孤独而宁静的氛围。
```

标准错误为空：

```text
stderr: 空
```

异常检查为空：

```text
abnormal: 无
```

结论：

```text
voice_assistant.py ask --image demo.jpg --no-speak --no-play 已可独立完成 Qwen3-VL 推理；
ask 轻量入口修复成功；
不再被 ASR / orchestrator / sherpa_onnx 依赖耦合阻塞。
```

实验 05.2 判定：**通过**。

---

## 10. 实验 05.3：record -> stt -> qwen 半闭环验证

### 10.1 实验目的

验证前面实验 04 的 ASR 输出能否接入实验 05 的 Qwen 推理入口。

链路：

```text
麦克风录音
  -> voice_assistant.py record
  -> command.wav
  -> voice_assistant.py stt
  -> ASR 中文文本
  -> voice_assistant.py ask --image demo.jpg --no-speak --no-play
  -> Qwen3-VL 文本回答
```

该实验仍不接入 TTS，因此属于：

```text
语音输入 -> ASR -> Qwen -> 文本回答
```

半闭环。

---

### 10.2 运行结果

关键输出：

```text
recognized_text: 谁也别在这张照片
return_code: 0
elapsed_seconds: 28
[RESULT] Experiment 05.3 PASSED
```

ASR 输出：

```text
谁也别在这张照片
```

Qwen 输入：

```text
========== lightweight ask ==========
image : demo.jpg
text  : <image>谁也别在这张照片
```

Qwen 回答：

```text
这张照片里，一个宇航员正坐在月球表面，手里拿着一瓶绿色的啤酒。他身后是地球在星空中的景象。
这是一幅充满科幻感和反差幽默的画面：一个人在宇宙中享受着一杯饮料，而地球却在不远处静静旋转。这种场景让人不禁思考人类在浩瀚宇宙中的位置与存在意义。
不过，从照片内容来看，并没有“谁”在照片里，而是展现了宇航员独自一人在月球上享受片刻宁静的瞬间。这幅画面可能是在表达一种孤独但又充满希望的情感，也可能是对太空探索的一种诗意描绘。
如果你是想问“谁”应该在这张照片里，那答案就是——没有谁，因为这张照片本身就是一幅由人类创造的艺术作品，它展示的是一个想象中的场景，而不是真实存在的画面。
```

标准错误为空：

```text
qwen stderr: 空
```

异常检查为空：

```text
abnormal: 无
```

实验 05.3 判定：**通过**。

---

## 11. ASR 识别误差说明

实验 05.3 中，ASR 识别文本为：

```text
谁也别在这张照片
```

这句话语义不完全自然，推测真实语音可能接近：

```text
请描述这张照片
```

或类似表达。

这说明：

```text
1. record -> stt -> qwen 链路通过；
2. 但本次真实语音的 ASR 结果存在识别误差；
3. Qwen 仍然根据 ASR 文本和 demo.jpg 给出了合理回答；
4. 后续完整助手体验需要继续优化 ASR 录音质量和意图容错。
```

这不影响实验 05.3 的通过判定，因为实验目标是验证链路能否打通，而不是评估 ASR 语义准确率。

后续优化方向：

```text
1. 说话更靠近麦克风；
2. 降低环境噪声；
3. 检查录音 mean_volume / max_volume；
4. 调整 asr_input_gain；
5. 对“图片 / 照片 / 描述 / 看一下”等关键词做容错匹配；
6. 在 IntentRouter 中增加相近错词的规则兜底。
```

---

## 12. 本实验涉及的关键代码关系

### 12.1 QwenRunner

文件：

```text
voice_assistant/qwen_runner.py
```

核心职责：

```text
1. 读取 config/default.yaml 中 qwen 配置；
2. 组装 demo 启动参数；
3. 设置 LD_LIBRARY_PATH；
4. 使用 pexpect 启动交互式 demo；
5. 等待 user: 提示；
6. 发送用户问题；
7. 等待 robot: 输出；
8. 截取回答内容；
9. 清理 runtime 日志片段；
10. 返回最终回答。
```

启动参数来源：

```python
args = [
    str(self.qwen["demo"]),
    str(image_path),
    str(self.qwen["vision_model"]),
    str(self.qwen["llm_model"]),
    str(self.qwen["max_new_tokens"]),
    str(self.qwen["max_context_len"]),
    str(self.qwen["rknn_core_num"]),
    str(self.qwen["img_start"]),
    str(self.qwen["img_end"]),
    str(self.qwen["img_content"]),
]
```

---

### 12.2 CLI 轻量入口

实验 05 进一步说明：

```text
并不是所有命令都应该构造完整 VoiceAssistant。
```

当前已经验证过的轻量入口包括：

```text
record：只验证录音链路，不导入 ASR / Qwen / TTS
stt：只验证 ASR 链路，不导入 Qwen / TTS / Camera / KWS
ask --no-speak --no-play：只验证 Qwen 链路，不导入 ASR / TTS / KWS
```

这种结构有利于后续调试：

```text
模块失败时可以快速定位到具体链路；
避免一个独立功能被其他未准备好的模块阻塞。
```

---

## 13. 当前实验通过项

| 阶段 | 检查项 | 状态 | 关键结果 |
|---|---|---|---|
| 05.0 | Qwen 资产补齐 | 通过 | `missing_qwen_assets: 0` |
| 05.0 | QwenRunner import/init | 通过 | `QwenRunner import and init passed` |
| 05.0 | demo usage | 通过 | 不需要额外 `rk3588` 参数 |
| 05.1 | 原生 demo 图文推理 | 通过 | 20.549 s 输出有效中文描述 |
| 05.2 初始 | `voice_assistant.py ask` | 失败 | 被 `orchestrator -> asr -> sherpa_onnx` 阻塞 |
| 05.2a | QwenRunner 直接调用 | 通过 | 输出有效图片描述 |
| 05.2b | ask 轻量入口修复 | 通过 | `return_code: 0`，14 s |
| 05.3 | record -> stt -> qwen | 通过 | 28 s，Qwen 输出回答 |

---

## 14. 当前仍未完成 / 待优化项

### 14.1 TTS 尚未接入

实验 05 到目前为止只完成：

```text
语音输入 -> ASR -> Qwen -> 文本回答
```

尚未完成：

```text
Qwen 文本回答 -> TTS -> 喇叭播放
```

因此下一步应进入实验 06。

---

### 14.2 完整 once / listen 链路还未验证

当前验证的是轻量 ask：

```bash
voice_assistant.py ask ... --no-speak --no-play
```

完整命令：

```bash
voice_assistant.py once
voice_assistant.py listen
voice_assistant.py listen-forever
```

仍然会构造完整 `VoiceAssistant`，后续需要在 TTS / KWS / Camera 全部验证后再统一测试。

---

### 14.3 ASR 真实语音仍存在误识别

实验 05.3 中 ASR 结果存在语义偏差：

```text
谁也别在这张照片
```

说明完整助手体验还需要结合：

```text
录音质量优化
ASR 输入增益优化
关键词容错
意图判断规则增强
```

---

## 15. 当前可复用命令

### 15.1 Qwen 资产检查

```bash
cd /home/cat/ai/qwen3vl2b

./scripts/exp05_0_qwen_asset_dryrun.sh

OUT=$(ls -td output/exp05_0_qwen_asset_dryrun_* | head -1)
grep -E "\[MISS\]|\[OK\]|missing_qwen_assets|\[RESULT\]" "$OUT/run.log"
```

---

### 15.2 原生 demo usage 检查

```bash
cd /home/cat/ai/qwen3vl2b

export LD_LIBRARY_PATH=.:${LD_LIBRARY_PATH:-}

LD_LIBRARY_PATH=. ./demo 2>&1 | head -100 || true
LD_LIBRARY_PATH=. ./demo --help 2>&1 | head -100 || true
strings ./demo | grep -iE "Usage|image_path|platform|rk3588|max_new|context|img_start|img_end|img_content" | head -100
```

---

### 15.3 QwenRunner 直接调用

```bash
cd /home/cat/ai/qwen3vl2b

./scripts/exp05_2a_qwen_runner_direct.sh
```

---

### 15.4 项目 ask 入口调用

```bash
cd /home/cat/ai/qwen3vl2b

python3 voice_assistant.py ask "<image>请用中文简短描述这张图片里有什么。" \
  --image demo.jpg \
  --no-speak \
  --no-play
```

---

### 15.5 ASR -> Qwen 半闭环

```bash
cd /home/cat/ai/qwen3vl2b

./scripts/exp05_3_record_stt_qwen.sh
```

---

## 16. 实验 05 最终结论

实验 05 判定：**通过**。

本实验完成了 RK3588 端侧语音助手项目的 Qwen3-VL 主模型链路验证：

```text
Qwen3-VL 资产补齐
    -> demo / imgenc / RKNN runtime / RKLLM runtime / vision RKNN / LLM RKLLM
    -> 原生 demo 图文推理
    -> QwenRunner 项目模块调用
    -> voice_assistant.py ask 轻量入口
    -> record -> stt -> qwen 半闭环
```

最终已经具备：

```text
麦克风录音
    -> Sherpa-ONNX 中文 ASR
    -> Qwen3-VL-2B 本地图文推理
    -> 文本回答
```

也就是说，系统已经从实验 04 的：

```text
语音 -> 文本
```

推进到实验 05 的：

```text
语音 -> 文本 -> Qwen 多模态理解 -> 文本回答
```

这为后续实验 06 的 TTS 播放闭环奠定了基础。

---

## 17. 后续实验建议

下一步进入：

```text
实验 06：TTS 中文语音合成与播放验证
```

目标链路：

```text
Qwen 文本回答
    -> TTS
    -> PCM / WAV
    -> plughw:2,0
    -> 喇叭 / 耳机播放
```

实验 06 通过后，再继续进入：

```text
实验 07：ASR -> Qwen -> TTS 完整语音问答闭环
实验 08：摄像头拍照 -> Qwen3-VL 图文问答 -> TTS 播放
实验 09：唤醒词 listen / listen-forever 完整助手流程
```

---

# 实验 05 阶段性封口

```text
record
  -> stt
  -> ask
  -> Qwen3-VL 本地回答
```

实验 05 已完成并封口。
