# 实验 11：意图路由正式重构、自动化测试与文本/视觉双链路回归验证

> 项目：RK3588 端侧多模态智能语音助手系统  
> 平台：LubanCat / RK3588  
> 仓库目录：`/home/cat/ai/qwen3vl2b`  
> Git 仓库：`FlankKaicoder/Qwen-Chat-Assistant`  
> 实验编号：11  
> 实验主题：IntentRouter 正式重构、结构化视觉意图规则、单元测试、Mock 集成测试、真实模块回归、KWS/ASR/Qwen/TTS 完整语音闭环回归  
> 实验分支：`exp/11-intent-router-refactor`  
> 最终提交：`19b90b1 refactor: formalize intent router and add regression tests`  
> 实验状态：**通过**  
> 记录日期：2026-08-04

---

## 1. 实验背景

实验 10 已经在 RK3588 上跑通了文本与视觉两条正式受控式语音链路：

```text
文本链路：
KWS
  -> ASR
  -> 文本意图
  -> Qwen 文本回答
  -> TTS

视觉链路：
KWS
  -> ASR
  -> 视觉意图
  -> 摄像头拍照
  -> Qwen3-VL 图文理解
  -> TTS
```

但是实验 10 的严格视觉意图策略仍然属于实验阶段实现。`voice_assistant/intent.py` 中原本存在两层逻辑：

```text
第一层：
IntentRouter.analyze() 使用 photo_keywords 做宽泛子串匹配。

第二层：
文件末尾追加 EXP10 严格视觉策略，保存旧 analyze()，
再通过 IntentRouter.analyze = _exp10_strict_analyze 动态覆盖原方法。
```

其中的关键代码是：

```python
_exp10_legacy_analyze = IntentRouter.analyze


def _exp10_strict_analyze(self, text):
    ...


IntentRouter.analyze = _exp10_strict_analyze
```

这种写法虽然快速解决了实验 10 中普通文本误拍照的问题，但并不适合作为长期维护方案，主要存在以下问题：

```text
1. 类定义中的 analyze() 与运行时真正执行的 analyze() 不一致；
2. 阅读源码时很难直接判断最终行为；
3. 依赖 monkey patch，代码结构不清晰；
4. 实验规则硬编码在文件末尾，没有正式配置化；
5. 没有自动化测试保护正例、负例和边界情况；
6. 后续修改关键词时可能重新引入普通文本误拍照；
7. 缺少 IntentRouter 与 Orchestrator 真实调用关系的集成验证；
8. 实验 10 的文本/视觉双链路需要在重构后重新回归。
```

因此实验 11 的核心任务不是继续增加功能，而是将已经验证有效的实验逻辑整理成正式、可测试、可回归的工程实现。

---

## 2. 实验目标

实验 11 主要回答以下问题：

```text
1. 当前 IntentRouter 的真实运行结构是什么；
2. 能否删除 EXP10 monkey patch，直接正式实现 analyze()；
3. 能否将视觉意图规则拆成结构化配置；
4. 能否避免“几个、有什么、描述、图片”等宽泛词单独触发拍照；
5. 能否同时保留“拍照、看镜头、描述当前画面、识别图片文字”等视觉能力；
6. 能否为意图路由建立自动化单元测试；
7. 能否使用 Mock 验证普通文本不调用摄像头、视觉请求只调用一次；
8. need_photo_override 与 force_photo 是否仍然正确；
9. Mock 测试是否真的阻止了真实摄像头、Qwen 和 TTS；
10. 重构后真实文本和真实视觉模块是否仍可运行；
11. 重构后完整 KWS/ASR/Qwen/TTS 文本语音闭环是否通过；
12. 重构后完整 KWS/ASR/Camera/Qwen3-VL/TTS 视觉闭环是否通过；
13. 最终能否形成独立 Git 分支、提交和回归测试资产。
```

---

## 3. 实验总体流程

实验 11 实际经历了以下阶段：

| 阶段 | 内容 | 结果 |
|---|---|---|
| 11.0 | Git、源码、IntentRouter API 与当前行为基线审计 | 完成；发现测试构造方式与 pytest 环境问题 |
| 11.1 | 创建实验分支并备份当前源码 | 通过 |
| 11.2 | 正式重写 `IntentRouter.analyze()`，删除 monkey patch | 通过 |
| 11.3 | 在 YAML 中增加结构化视觉意图规则 | 通过 |
| 11.4 | 建立 IntentRouter 单元测试与行为表 | 6 项单元测试、14 项行为回归通过 |
| 11.4b | 修复 `config/default.yaml` 文件末尾空白格式 | 通过 |
| 11.5 | 首次 Orchestrator Mock 集成测试 | 失败；Mock 注入位置错误，意外运行真实摄像头和 Qwen |
| 11.5b | 修复 Mock 注入点并增加真实照片目录对比 | 7 项集成测试通过，13 项总测试通过 |
| 11.6 | 真实文本与真实视觉模块回归 | 主链路通过；原始视觉问答出现 token 截断说明 |
| 11.7a | KWS + ASR + 文本 Qwen + TTS 完整语音回归 | 通过 |
| 11.7b | KWS + ASR + Camera + Qwen3-VL + TTS 完整语音回归 | 通过 |
| 11.8 | Git 提交与状态确认 | 通过，提交 `19b90b1` |

---

## 4. 实验 11.0：重构前基线审计

### 4.1 Git 基线

实验开始前：

```text
branch      : main
HEAD        : d9b69c0
commit      : Merge branch 'main' of github.com:FlankKaicoder/Qwen-Chat-Assistant
dirty_count : 0
```

说明实验 10 的代码已经处于干净工作区，可以安全创建实验 11 分支。

### 4.2 源码文件检查

以下关键文件全部存在：

```text
voice_assistant/intent.py
voice_assistant/orchestrator.py
voice_assistant/controlled_session.py
voice_assistant/cli.py
voice_assistant/config.py
config/default.yaml
voice_assistant.py
```

### 4.3 原始 IntentRouter

原始类定义为：

```python
@dataclass(frozen=True)
class Intent:
    need_photo: bool
    qwen_text: str


class IntentRouter:
    def __init__(
        self,
        photo_keywords: list[str],
        image_prefix_trigger: str,
        image_prefix: str,
    ):
        ...

    @classmethod
    def from_config(cls, config: dict) -> "IntentRouter":
        ...

    def analyze(self, text: str) -> Intent:
        normalized = text.strip()
        need_photo = any(
            keyword in normalized
            for keyword in self.photo_keywords
        )
        ...
```

原始实现的主要问题是：

```text
任何一个 photo_keywords 子串命中，都会将 need_photo 设为 True。
```

而当时的配置中存在大量宽泛词：

```text
看一下
看看
识别
描述
有什么
有哪些
几个
颜色
文字
图片
照片
```

这些词在普通文本问题中也很常见，例如：

```text
“一加一等于几”
“这个问题有什么解决方法”
“请描述一下线程池原理”
“图片格式有哪些”
```

因此不能继续使用简单的 `any(keyword in text)` 作为正式意图路由。

### 4.4 确认 monkey patch

审计结果：

```text
intent_analyze_assignment_count: 1
```

实际运行的 `IntentRouter.analyze()` 已经被文件末尾的 `_exp10_strict_analyze()` 覆盖。

### 4.5 基线测试脚本自身的问题

第一次基线行为脚本返回：

```text
baseline_return_code: 3
```

但这不是 IntentRouter 行为失败，而是测试脚本错误地尝试以下构造方式：

```python
IntentRouter(config)
IntentRouter(intent_config)
IntentRouter(photo_keywords)
IntentRouter()
```

正确方式应该是：

```python
IntentRouter.from_config(config)
```

这一问题说明：

```text
自动化测试不仅要检查业务代码，也必须确保测试本身按照真实 API 构造对象。
```

### 4.6 pytest 不可用

当前 Python 环境：

```text
Python 3.9.2
/usr/bin/python3: No module named pytest
```

因此实验 11 决定使用 Python 标准库 `unittest`：

```text
无需额外安装依赖；
可直接在板端运行；
以后安装 pytest 后仍可被 pytest 收集。
```

---

## 5. 创建实验分支

在干净的 `main` 分支上创建：

```bash
git switch -c exp/11-intent-router-refactor
```

创建后：

```text
active_branch : exp/11-intent-router-refactor
base_head     : d9b69c0
```

实验过程中的所有修改均保留在独立分支中，没有直接污染 `main`。

---

## 6. IntentRouter 正式设计

### 6.1 设计原则

新的路由不再将每个关键词都作为独立拍照触发条件，而是采用保守的组合语法：

```text
规则 1：明确拍照命令
  -> 拍照

规则 2：精确的短视觉命令
  -> 拍照

规则 3：视觉动作 + 视觉上下文
  -> 拍照

规则 4：宽泛询问词单独出现
  -> 不拍照

规则 5：视觉动作 + 视觉词 + 明确文本语境
  -> 不拍照
```

### 6.2 结构化规则分类

正式实现将规则拆分为五组。

#### 6.2.1 明确拍照动作

```yaml
explicit_capture_phrases:
  - 拍照
  - 拍一张
  - 照一张
  - 拍个照
  - 拍一下
  - 拍下来
  - 拍张图
  - 拍张照片
  - 拍一张照片
  - 拍个照片
  - 拍个图片
```

该组具有最高优先级。例如：

```text
“请拍照看看这段代码”
```

虽然包含“代码”文本阻断词，但用户已经明确要求拍照，因此仍然触发摄像头。

#### 6.2.2 精确短视觉命令

```yaml
direct_visual_commands:
  - 看镜头
  - 看画面
  - 看摄像头
  - 看图片
  - 看照片
  - 看图像
  - 看看镜头
  - 看看画面
```

该组采用精确匹配，避免仅靠单字“看”导致误触发。

#### 6.2.3 视觉上下文

```yaml
visual_context_phrases:
  - 摄像头
  - 当前摄像头
  - 镜头
  - 镜头里
  - 画面
  - 当前画面
  - 实时画面
  - 画面里
  - 照片
  - 照片里
  - 图片
  - 图片里
  - 图像
  - 眼前
  - 当前视野
  - 视野里
  - 现在看到
  - 当前看到
```

#### 6.2.4 视觉动作或查询动作

```yaml
visual_action_phrases:
  - 看一下
  - 看看
  - 看一看
  - 帮我看
  - 帮我看看
  - 看下
  - 看一眼
  - 你看
  - 描述一下
  - 描述
  - 识别一下
  - 识别
  - 辨认
  - 读一下
  - 念一下
  - 有什么
  - 有哪些
  - 多少个
  - 几个
  - 颜色
  - 文字
```

这些词不能单独触发摄像头，只有与视觉上下文共同出现时才可能触发。

#### 6.2.5 文本语境阻断词

```yaml
text_context_blockers:
  - 代码
  - 源码
  - 算法
  - 原理
  - 教程
  - 格式
  - 文件
  - 模型
  - 论文
  - 程序
  - 编程
  - 数据结构
```

例如：

```text
“图片格式有哪些”
```

虽然包含：

```text
视觉动作：有哪些
视觉上下文：图片
```

但同时包含：

```text
文本阻断词：格式
```

因此结果为：

```text
need_photo=False
matched_rule=blocked_text_context
```

### 6.3 正式判断顺序

核心判断顺序为：

```python
if explicit_match:
    need_photo = True
    matched_rule = "explicit_capture"

elif direct_match:
    need_photo = True
    matched_rule = "direct_visual_command"

elif context_match and action_match and not blocker_match:
    need_photo = True
    matched_rule = "visual_action_and_context"

elif context_match and action_match and blocker_match:
    need_photo = False
    matched_rule = "blocked_text_context"
```

该顺序体现以下优先级：

```text
明确用户拍照命令
  > 精确视觉短命令
  > 动作与上下文组合
  > 文本语境阻断
```

### 6.4 文本归一化

新的 `_normalize_text()` 会：

```text
转换为字符串；
去除首尾空白；
转为小写；
移除所有空白字符。
```

因此：

```text
“  看 一下 镜头  ”
```

可以归一化为：

```text
看一下镜头
```

并正确识别为视觉请求。

### 6.5 调试字段

`Intent` 数据类从原来的：

```python
@dataclass(frozen=True)
class Intent:
    need_photo: bool
    qwen_text: str
```

扩展为：

```python
@dataclass(frozen=True)
class Intent:
    need_photo: bool
    qwen_text: str
    matched_rule: str = ""
    matched_phrases: Tuple[str, ...] = ()
```

新增字段用于记录：

```text
最终命中的规则；
参与判断的词组；
为什么拍照；
为什么被文本语境阻止。
```

同时保留了原有的 `need_photo` 和 `qwen_text`，因此旧调用方仍然兼容。

---

## 7. 图像前缀行为

原系统中：

```text
image_prefix_trigger: 图片
image_prefix        : <图片>
```

新的实现只在请求已经被判定为视觉意图时，才可能增加 `<图片>` 前缀：

```python
if (
    need_photo
    and image_prefix_trigger in normalized_text
    and not cleaned_text.startswith(image_prefix)
):
    qwen_text = f"{image_prefix}{cleaned_text}"
```

因此：

```text
“识别图片中的文字”
  -> need_photo=True
  -> qwen_text=<图片>识别图片中的文字
```

而：

```text
“请解释图片格式”
  -> need_photo=False
  -> qwen_text 保持原文
```

这避免了文本问题仅因包含“图片”就被改写为视觉 Prompt。

---

## 8. 配置文件改造

`config/default.yaml` 新增了正式规则区：

```text
BEGIN EXP11 FORMAL INTENT RULES
...
END EXP11 FORMAL INTENT RULES
```

保留原有 `photo_keywords` 的原因是：

```text
1. 避免破坏已有配置结构；
2. 保留兼容性与历史信息；
3. 便于旧代码或脚本仍能读取该字段。
```

但新实现已经不再使用：

```python
any(keyword in text for keyword in photo_keywords)
```

作为最终视觉路由依据。

---

## 9. 单元测试设计

新增文件：

```text
tests/__init__.py
tests/test_intent_router.py
```

### 9.1 视觉正例

测试覆盖：

```text
拍照看一下画面
帮我拍一张
请拍一下
拍张照片
看一下镜头
摄像头前面有什么
描述当前画面
识别图片中的文字
看看实时画面
当前视野里有哪些东西
看镜头
```

预期：

```text
need_photo=True
matched_rule 非空
```

### 9.2 文本负例

测试覆盖：

```text
你是谁
一加一等于几
这几个字是什么意思
帮我写几个汉字
请描述一下线程池原理
这个问题有什么解决方法
请识别一下这个算法的复杂度
颜色空间转换的原理是什么
图片格式有哪些
请解释图像算法原理
请帮我看看图片处理代码
这个模型识别效果怎么样
空字符串
纯空白字符串
```

预期：

```text
need_photo=False
```

### 9.3 边界测试

额外测试包括：

```text
明确拍照命令是否覆盖文本阻断词；
视觉请求是否增加 <图片>；
文本请求是否不增加 <图片>；
空格归一化是否有效；
旧字段 need_photo 和 qwen_text 是否继续存在。
```

### 9.4 单元测试结果

```text
Ran 6 tests in 0.017s
OK
```

通过测试：

```text
test_backward_compatible_fields
test_explicit_capture_overrides_text_blocker
test_image_prefix_added_only_for_visual_request
test_text_negative_cases
test_visual_positive_cases
test_whitespace_normalization
```

---

## 10. 14 条行为回归表

代表性结果如下：

| 输入 | 预期 | 实际 | 规则 | 结果 |
|---|---:|---:|---|---|
| 你是谁 | 0 | 0 | 无 | PASS |
| 一加一等于几 | 0 | 0 | 无 | PASS |
| 这几个字是什么意思 | 0 | 0 | 无 | PASS |
| 帮我写几个汉字 | 0 | 0 | 无 | PASS |
| 请描述一下线程池原理 | 0 | 0 | 无 | PASS |
| 这个问题有什么解决方法 | 0 | 0 | 无 | PASS |
| 图片格式有哪些 | 0 | 0 | `blocked_text_context` | PASS |
| 请帮我看看图片处理代码 | 0 | 0 | `blocked_text_context` | PASS |
| 拍照看一下画面 | 1 | 1 | `explicit_capture` | PASS |
| 帮我拍一张 | 1 | 1 | `explicit_capture` | PASS |
| 看一下镜头 | 1 | 1 | `visual_action_and_context` | PASS |
| 摄像头前面有什么 | 1 | 1 | `visual_action_and_context` | PASS |
| 描述当前画面 | 1 | 1 | `visual_action_and_context` | PASS |
| 识别图片中的文字 | 1 | 1 | `visual_action_and_context` | PASS |

最终：

```text
case_count     : 14
mismatch_count : 0
behavior_result: PASS
```

---

## 11. 文件末尾空白问题

第一次执行：

```bash
git diff --check
```

返回：

```text
config/default.yaml:212: new blank line at EOF.
diff_check_before_return_code: 2
```

原因是自动插入 YAML 规则后，文件末尾多出一个空白行。

修复方式：

```text
逐行移除尾随空格和 Tab；
删除文件末尾多余空白行；
统一保留一个换行符结尾。
```

修复结果：

```text
diff_check_after_return_code: 0
compile_return_code          : 0
unittest_return_code         : 0
behavior_return_code         : 0
```

该问题虽然不影响程序运行，但应在提交前处理，以保持 Git diff 干净。

---

## 12. 删除 monkey patch 验证

重构后检查：

```text
intent_analyze_assignment_count: 0
exp10_symbol_count              : 0
```

说明以下实验代码已经完全移除：

```text
IntentRouter.analyze = ...
_exp10_...
EXP10 STRICT VISUAL INTENT POLICY
```

此后源码中类定义的 `analyze()` 就是运行时真正执行的方法。

---

## 13. VoiceAssistant 初始化回归

使用真实配置初始化：

```python
config = load_config("config/default.yaml")
assistant = VoiceAssistant(config)
```

结果：

```text
assistant_type     : VoiceAssistant
intent_router_type : IntentRouter
assistant_init     : PASS
```

说明新增配置和 Intent 数据字段没有破坏 Orchestrator 初始化。

---

## 14. 实验 11.5：首次 Mock 集成测试失败

### 14.1 测试目标

单元测试只验证：

```text
输入文本 -> IntentRouter -> need_photo
```

集成测试进一步需要验证：

```text
need_photo=False
  -> 摄像头调用 0 次

need_photo=True
  -> 摄像头调用 1 次

need_photo_override=False
  -> 禁止拍照

need_photo_override=True
  -> 强制拍照

force_photo=True
  -> 强制拍照
```

### 14.2 错误 Mock 设计

第一次测试尝试：

```python
self.assistant.camera = self.fake_camera
self.assistant.qwen = self.fake_qwen
```

但审计 `VoiceAssistant.ask_qwen()` 后发现，真实实现并不访问这两个属性：

```python
if uses_photo:
    image = self.capture_photo()

runner = QwenRunner(self.config)
return runner.ask(...)
```

因此错误 Mock 没有拦截：

```text
self.capture_photo()
QwenRunner(self.config)
```

### 14.3 失败现象

7 项集成测试全部失败：

```text
Ran 7 tests in 214.253s
FAILED (failures=7)
```

完整测试发现也失败：

```text
Ran 13 tests in 244.586s
FAILED (failures=7)
```

日志中出现：

```text
检测到拍照意图，正在拍照...
照片已保存：/home/cat/图片/voice_....jpg
正在调用 Qwen demo，请等待模型回答...
```

并返回真实 Qwen 回答，而不是：

```text
FAKE_QWEN_ANSWER
```

这明确证明测试期间真正执行了：

```text
真实摄像头拍照；
真实 Qwen RKNN/RKLLM 推理。
```

### 14.4 错误的残留进程结论

第一次测试结束后输出：

```text
[OK] No real camera or Qwen process was started
```

这个结论也是错误的。

当时的检查实际上只证明：

```text
测试结束后没有残留相关进程。
```

它不能证明：

```text
测试过程中从未启动真实进程。
```

这是实验 11 中非常重要的测试方法教训。

### 14.5 本次错误意外生成的照片

代表性测试照片包括：

```text
/home/cat/图片/voice_20260803_181316.jpg
/home/cat/图片/voice_20260803_181328.jpg
/home/cat/图片/voice_20260803_181350.jpg
/home/cat/图片/voice_20260803_181425.jpg
/home/cat/图片/voice_20260803_181650.jpg
/home/cat/图片/voice_20260803_181701.jpg
/home/cat/图片/voice_20260803_181723.jpg
/home/cat/图片/voice_20260803_181807.jpg
```

这些文件来自错误 Mock 测试，不应作为真实业务验证结果使用。

---

## 15. 实验 11.5b：修复 Mock 注入位置

### 15.1 正确的 Mock 原则

Mock 必须替换“被测模块真正查找和调用的符号”，而不是替换一个看起来合理但实际未使用的属性。

正确方式：

```python
patch.object(
    assistant,
    "capture_photo",
    side_effect=fake_capture_photo,
)
```

用于拦截：

```python
self.capture_photo()
```

同时：

```python
patch(
    "voice_assistant.orchestrator.QwenRunner",
    return_value=fake_qwen,
)
```

用于拦截 `orchestrator.py` 命名空间中真正创建的：

```python
QwenRunner(self.config)
```

并增加：

```python
patch(
    "voice_assistant.orchestrator.StreamingTtsPlayer",
    FakeStreamingTtsPlayer,
)
```

作为 TTS 安全屏障。

### 15.2 Fake 组件

#### Fake Capture

```text
不访问 /dev/video11；
只返回 /tmp/exp11_fake_camera_1.jpg；
记录调用次数；
不真正创建照片。
```

#### Fake QwenRunner

```text
记录 image_path；
记录 text；
记录 max_new_tokens；
固定返回 FAKE_QWEN_ANSWER。
```

#### Fake StreamingTtsPlayer

```text
记录 enqueue；
记录 close；
不进行真实 TTS 合成和 ALSA 播放。
```

### 15.3 集成测试项目

新增：

```text
tests/test_orchestrator_intent_integration.py
```

包含 7 项测试：

```text
test_automatic_text_route_does_not_capture
test_automatic_visual_route_captures_once
test_force_photo_overrides_false_route
test_override_false_blocks_camera
test_override_true_forces_camera
test_run_once_override_false
test_run_once_override_true
```

### 15.4 正确 Mock 测试结果

```text
Ran 7 tests in 0.025s
OK
```

完整测试：

```text
Ran 13 tests in 0.041s
OK
```

与错误 Mock 的两百多秒相比，修复后只需几十毫秒，进一步证明没有进入真实模型推理。

### 15.5 真实照片目录对比

测试前：

```text
photo_count_before: 27
```

测试后：

```text
photo_count_after : 27
photo_diff_count  : 0
```

因此可以严格证明：

```text
Mock 测试期间没有新增真实照片。
```

### 15.6 残留进程

```text
residual_process_count: 0
```

最终结果：

```text
[RESULT] Experiment 11.5b PASSED
```

---

## 16. Mock 测试带来的工程认识

本次失败和修复说明：

```text
1. Mock 应替换运行时查找位置，而不是原始类定义位置；
2. 如果模块使用 from xxx import Class，则应 patch 使用方模块中的 Class；
3. 如果方法内部直接调用 self.capture_photo()，应 patch 该实例方法；
4. 仅检查测试后无残留进程，不能证明测试中没有真实执行；
5. 应同时检查执行时长、固定返回值、文件系统变化和调用计数；
6. 测试本身也需要被验证，不能因为名称写着 Fake 就默认它真的隔离了硬件；
7. 端侧测试尤其要避免错误 Mock 导致模型加载、摄像头操作和长时间等待。
```

---

## 17. 实验 11.6：真实文本与视觉模块回归

该阶段不使用 KWS、ASR 和 TTS，只验证：

```text
真实 IntentRouter
真实 VoiceAssistant
真实 CameraAdapter
真实 QwenRunner
```

### 17.1 真实文本路线

输入：

```text
一加一等于几
```

回答：

```text
“一加一等于几”这个问题，从数学的角度来看，答案是：
一加一等于二。
这是最基本的算术运算之一。
```

判断：

```text
语义正确；
未触发摄像头；
真实 Qwen 文本推理正常。
```

### 17.2 真实视觉路线

输入：

```text
看一下镜头
```

新照片：

```text
/home/cat/图片/voice_20260803_185326.jpg
```

回答开头：

```text
您好，根据您提供的图片，这是一张从一个低角度拍摄的、带有强烈透视效果的照片。
...
```

模型给出了具体的人物、物体和拍摄角度信息，说明图片已经进入 Qwen3-VL。

### 17.3 原始视觉回答被截断

本轮回答最后停止在：

```text
几乎是一个倒
```

原因是本轮直接调用底层 `run_once_from_text()`，输入仍是原始问题：

```text
看一下镜头
```

并设置：

```text
max_new_tokens=128
```

它没有经过 `listen-controlled` 的视觉专用短回答 Prompt，因此模型倾向生成较长描述，最终达到 token 上限并被截断。

该现象说明：

```text
路由和图像推理通过；
底层原始视觉问答的回答长度不稳定；
正式业务入口仍应使用实验 10 已建立的视觉 concise Prompt。
```

因此该问题不属于 IntentRouter 重构回归。

---

## 18. 实验 11.7a：完整文本语音链路回归

### 18.1 操作

用户先说：

```text
鲁班猫
```

唤醒后说：

```text
一加一等于几
```

### 18.2 状态机

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
```

### 18.3 结果

```text
wake_text               : 鲁班猫
recognized_text         : 一加一等于几
photo_intent_hint       : 0
new_photo_count         : 0
qwen_prompt             : 请简短回答这个问题：一加一等于几
qwen_answer             : 一加一等于二。
answer_chars            : 7
pipeline_elapsed_seconds: 8.544
tts_elapsed_seconds     : 5.448
elapsed_seconds         : 28.215
status                  : PASSED
exit_code               : 0
error                   : 空
```

最终：

```text
[RESULT] listen-controlled PASSED
```

### 18.4 结论

完整文本链路：

```text
KWS
  -> ASR
  -> 新 IntentRouter
  -> 普通文本 concise Prompt
  -> Qwen
  -> TTS
```

重构后保持通过，并且：

```text
普通算术问题没有触发摄像头；
新增照片数量为 0；
回答简短且语义正确；
无错误；
无残留进程。
```

---

## 19. 实验 11.7b：完整视觉语音链路回归

### 19.1 操作

计划命令：

```text
拍照看一下画面
```

ASR 实际识别为：

```text
看一下画面
```

即使“拍照”两个字没有被识别出来，新的组合路由仍然通过：

```text
视觉动作：看一下
视觉上下文：画面
```

将其正确判断为视觉意图。

### 19.2 路由结果

```json
{
  "recognized_text": "看一下画面",
  "need_photo": true,
  "intent_qwen_text": "看一下画面",
  "heuristic_photo_hint": true
}
```

### 19.3 视觉专用 Prompt

```text
请根据当前摄像头拍摄的图片，直接描述画面中最主要的人物、物体和场景。
只输出一到两句中文结论，不要解释推理过程，不要使用标题、列表或分点，
不要说无法查看图片，尽量控制在80个汉字以内。
```

### 19.4 Qwen3-VL 回答

```text
一名戴眼镜的年轻男子坐在办公桌前，手持麦克风，似乎正在工作或参加会议。
```

### 19.5 输出图片

```text
/home/cat/图片/voice_20260804_141028.jpg
```

文件验证：

```text
JPEG image data
codec_name=mjpeg
width=1280
height=720
pix_fmt=yuvj420p
```

### 19.6 性能结果

```text
wake_text               : 鲁班猫
recognized_text         : 看一下画面
photo_intent_hint       : 1
new_photo_count         : 1
answer_chars            : 35
pipeline_elapsed_seconds: 11.725
tts_elapsed_seconds     : 12.261
elapsed_seconds         : 36.708
status                  : PASSED
exit_code               : 0
error                   : 空
```

自动检查全部通过：

```text
return_code_zero : PASS
status_passed    : PASS
photo_intent_true: PASS
one_new_photo    : PASS
answer_nonempty  : PASS
answer_not_bad   : PASS
error_empty      : PASS
```

最终：

```text
[RESULT] Experiment 11.7b PASSED
```

### 19.7 结论

完整视觉链路：

```text
KWS
  -> ASR
  -> 新 IntentRouter
  -> CameraAdapter
  -> 视觉专用 concise Prompt
  -> Qwen3-VL
  -> TTS
```

在重构后保持通过。

本轮还验证了一个重要边界：

```text
即使 ASR 丢失明确“拍照”词，
只要保留“看一下 + 画面”，
组合规则仍可正确触发摄像头。
```

---

## 20. 文本与视觉最终对照

| 指标 | 文本链路 11.7a | 视觉链路 11.7b |
|---|---:|---:|
| KWS | 鲁班猫 | 鲁班猫 |
| ASR | 一加一等于几 | 看一下画面 |
| photo_intent_hint | 0 | 1 |
| 新照片数 | 0 | 1 |
| Qwen 阶段 | 8.544 s | 11.725 s |
| 回答长度 | 7 字 | 35 字 |
| TTS | 5.448 s | 12.261 s |
| 总耗时 | 28.215 s | 36.708 s |
| 最终状态 | PASSED | PASSED |
| 残留进程 | 0 | 0 |

---

## 21. 主要代码修改

### 21.1 `voice_assistant/intent.py`

主要改动：

```text
1. 删除 EXP10 文件末尾 monkey patch；
2. 正式重写 IntentRouter.analyze()；
3. 增加结构化规则表；
4. 增加文本归一化；
5. 增加去重后的 phrase table；
6. 增加 substring 与 exact match 工具方法；
7. 增加 matched_rule；
8. 增加 matched_phrases；
9. 保留 photo_keywords 兼容字段；
10. 仅在视觉请求中增加 <图片> 前缀。
```

### 21.2 `config/default.yaml`

新增：

```text
explicit_capture_phrases
direct_visual_commands
visual_context_phrases
visual_action_phrases
text_context_blockers
```

### 21.3 `tests/test_intent_router.py`

包含：

```text
视觉正例；
文本负例；
阻断词；
显式拍照优先级；
图片前缀；
空白归一化；
兼容字段。
```

### 21.4 `tests/test_orchestrator_intent_integration.py`

包含：

```text
自动文本路由不拍照；
自动视觉路由拍照一次；
override=False；
override=True；
force_photo=True；
run_once_from_text 文本覆盖；
run_once_from_text 视觉覆盖；
Fake Qwen；
Fake Camera；
Fake TTS。
```

---

## 22. Git 提交

### 22.1 提交前状态

```text
M  config/default.yaml
M  voice_assistant/intent.py
A  tests/__init__.py
A  tests/test_intent_router.py
A  tests/test_orchestrator_intent_integration.py
```

### 22.2 提交命令

```bash
git add \
  voice_assistant/intent.py \
  config/default.yaml \
  tests/test_intent_router.py \
  tests/test_orchestrator_intent_integration.py \
  tests/__init__.py

git commit -m "refactor: formalize intent router and add regression tests"
```

### 22.3 提交结果

```text
[exp/11-intent-router-refactor 19b90b1]
refactor: formalize intent router and add regression tests

5 files changed,
1007 insertions(+),
195 deletions(-)
```

新增文件：

```text
tests/__init__.py
tests/test_intent_router.py
tests/test_orchestrator_intent_integration.py
```

最终：

```text
19b90b1 (HEAD -> exp/11-intent-router-refactor)
refactor: formalize intent router and add regression tests
```

`git status --short` 无输出，说明提交后工作区干净。

---

## 23. 代表性输出目录

### 23.1 重构前审计

```text
output/exp11_0_intent_refactor_precheck_20260803_174915
```

### 23.2 IntentRouter 重构与测试

```text
output/exp11_1b_diff_check_fix_20260803_180559
```

### 23.3 首次错误 Mock 测试

```text
output/exp11_5_orchestrator_mock_integration_20260803_181119
```

该目录应保留，用于说明错误 Mock 注入导致真实硬件和真实模型被执行的问题。

### 23.4 修复后的 Mock 集成测试

```text
output/exp11_5b_correct_mock_injection_20260803_183543
```

### 23.5 真实文本/视觉模块回归

```text
output/exp11_6_real_text_visual_regression_*
```

代表性视觉图片：

```text
/home/cat/图片/voice_20260803_185326.jpg
```

### 23.6 完整文本语音回归

```text
output/exp11_7a_text_voice_regression_20260804_140809
```

### 23.7 完整视觉语音回归

```text
output/exp11_7b_visual_voice_regression_20260804_141015
```

代表性图片：

```text
/home/cat/图片/voice_20260804_141028.jpg
```

---

## 24. 当前系统能力状态

实验 11 完成后，系统已经具备：

```text
KWS 唤醒；
固定窗口录音；
Sherpa-ONNX 中文 ASR；
正式 IntentRouter；
文本/视觉意图组合规则；
文本语境阻断；
force_photo；
need_photo_override；
摄像头单次拍照；
Qwen 文本推理；
Qwen3-VL 图文推理；
视觉/文本专用 concise Prompt；
Matcha-TTS + Vocos；
ALSA 播放；
状态日志与 summary；
单元测试；
Mock 集成测试；
真实文本/视觉回归测试。
```

---

## 25. 实验 11 解决的核心问题

### 25.1 解决源码与运行时行为不一致

之前：

```text
类中 analyze() 不是实际执行版本；
文件末尾 monkey patch 才是最终行为。
```

现在：

```text
IntentRouter.analyze() 本身就是正式实现。
```

### 25.2 解决宽泛关键词误拍照

之前：

```text
“几个、有什么、描述、图片”等任意子串即可触发拍照。
```

现在：

```text
需要明确拍照命令、精确视觉命令，
或视觉动作与视觉上下文组合。
```

### 25.3 解决文本视觉词语歧义

例如：

```text
图片格式有哪些
请帮我看看图片处理代码
```

现在可被 `blocked_text_context` 正确阻止。

### 25.4 建立回归测试保护

以后修改规则后，可以直接运行：

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

快速检查是否重新引入误拍照。

### 25.5 验证上层覆盖语义

已确认：

```text
need_photo_override=False
  -> 禁止摄像头

need_photo_override=True
  -> 强制摄像头

force_photo=True
  -> 即使 override=False 仍强制摄像头
```

### 25.6 建立可靠 Mock 方法

通过错误案例确认：

```text
Mock 必须 patch 使用方命名空间中的真实符号；
测试结束无残留不等于测试过程没有真实执行；
文件目录快照和固定 Fake 返回值是重要安全检查。
```

---

## 26. 已知限制与技术债

### 26.1 当前测试规模仍有限

当前共 13 项自动化测试，覆盖了代表性正负样本，但自然语言表达远不止这些。

后续应继续增加：

```text
口语化表达；
ASR 同音字；
标点符号；
省略句；
否定句；
多意图句；
“看看这个问题”等歧义表达；
更长的工程文本问题。
```

### 26.2 精确短命令对标点可能敏感

当前归一化会删除空白，但不会主动删除中文标点。

例如：

```text
看镜头。
```

可能无法命中精确 `direct_visual_commands`，需要依赖其他组合规则。后续可以考虑增加标点归一化。

### 26.3 文本阻断词仍是启发式规则

`text_context_blockers` 能解决当前代表性问题，但不能覆盖全部语义。

例如同一个词在不同上下文中的意义可能不同，因此未来仍可能需要：

```text
更丰富的规则；
轻量分类器；
小模型意图识别；
规则与模型混合路由。
```

### 26.4 原始视觉入口仍可能输出过长

实验 11.6 说明：

```text
直接将“看一下镜头”交给底层 Qwen，
即使 max_new_tokens=128，仍可能在句中被截断。
```

因此正式入口仍应使用视觉专用 concise Prompt。

### 26.5 pytest 尚未安装

目前使用 `unittest` 不影响测试，但如果后续需要：

```text
参数化；
fixture；
更丰富的 Mock；
覆盖率报告；
```

可以再正式引入 pytest。

### 26.6 尚未完成连续多轮稳定性验证

实验 11 验证了代表性单轮文本和视觉链路，但还没有验证：

```text
视觉 -> 文本 -> 视觉 -> 文本
```

连续多轮运行时的：

```text
误拍照率；
摄像头稳定性；
模型进程残留；
内存增长；
文件描述符增长；
温度与频率；
延迟漂移。
```

### 26.7 QwenRunner 仍按请求创建

`ask_qwen()` 内仍执行：

```python
runner = QwenRunner(self.config)
```

未来可研究常驻 Qwen 进程、模型预热和上下文复用。

### 26.8 固定 5 秒录音仍然存在

当前交互依赖：

```text
固定 5 秒录音窗口。
```

后续需要 VAD 自动判断开始和结束说话。

### 26.9 TTS 延迟仍明显

代表性结果：

```text
7 字文本回答 TTS : 5.448 s
35 字视觉回答 TTS: 12.261 s
```

TTS 仍是端到端体验的重要优化方向。

---

## 27. 后续实验建议

### 27.1 实验 12：连续混合多轮稳定性

建议先执行 4 轮：

```text
第 1 轮：看一下画面
第 2 轮：一加一等于几
第 3 轮：拍照描述当前画面
第 4 轮：你是谁
```

再扩展到 20 轮或 30～60 分钟。

统计：

```text
KWS 成功率；
ASR 正确率；
意图正确率；
文本误拍照次数；
视觉漏拍次数；
摄像头失败次数；
Qwen/TTS P50、P90、P99；
残留进程；
内存、线程、文件描述符；
温度和频率。
```

### 27.2 实验 13：VAD 与录音交互优化

目标：

```text
提示音；
检测开始说话；
连续静音自动停止；
最大录音时长保护。
```

### 27.3 实验 14：Qwen 常驻进程

目标：

```text
区分冷启动与热请求；
持久化 Qwen demo；
请求队列；
超时；
互斥锁；
异常自动重启；
进程组清理。
```

### 27.4 后续扩充意图测试集

将真实 ASR 结果持续加入测试集：

```text
原始语音；
ASR 文本；
预期意图；
实际意图；
命中规则；
是否误拍照。
```

形成可长期回归的意图语料库。

---

## 28. 简历与面试可提炼点

实验 11 可以体现以下能力：

```text
1. 将实验阶段 monkey patch 重构为正式类方法；
2. 将宽泛子串匹配改为显式命令、动作、视觉上下文与文本阻断组合规则；
3. 将路由规则配置化并保留旧配置兼容性；
4. 为 Intent 数据增加命中规则与词组调试信息；
5. 使用 unittest 构建正例、负例和边界自动化测试；
6. 使用 unittest.mock 隔离摄像头、Qwen 和 TTS；
7. 定位错误 Mock 注入导致真实硬件和模型被意外执行的问题；
8. 通过调用次数、固定 Fake 返回值、照片目录快照、运行时长和残留进程多维验证 Mock 有效性；
9. 完成真实文本/视觉模块回归；
10. 完成 KWS/ASR/Qwen/TTS 和 KWS/ASR/Camera/Qwen3-VL/TTS 双链路回归；
11. 使用独立 Git 分支和提交管理实验改动。
```

可用于简历的描述示例：

```text
重构 RK3588 多模态语音助手的文本/视觉意图路由，删除实验阶段 monkey patch，将宽泛关键词匹配改为“明确拍照命令、视觉动作、视觉上下文与文本语境阻断”的组合规则，并将规则配置化。基于 unittest 和 unittest.mock 建立 13 项自动化回归测试，隔离 Camera、QwenRunner 和 TTS，验证普通文本零拍照、视觉请求单次拍照及 force/override 路由语义；同时通过真实模块和 KWS->ASR->Qwen/Qwen3-VL->TTS 双链路回归，文本链路 8.54 s 完成 Qwen 回答且无新增照片，视觉链路 11.73 s 完成图文推理并生成一张 1280×720 JPEG，最终无错误和残留进程。
```

面试中可以重点说明错误 Mock 案例：

```text
最初只替换 assistant.camera 和 assistant.qwen，
但真实代码调用 self.capture_photo() 并在方法内构造 QwenRunner，
导致测试意外启动真实摄像头和模型。
随后改为 patch.object(instance, "capture_photo")，
并 patch voice_assistant.orchestrator.QwenRunner，
再结合照片目录差异、固定 Fake 返回值和测试耗时验证隔离真正生效。
```

该案例能够体现：

```text
对 Python 名称绑定与 Mock 查找位置的理解；
对测试可信度的重视；
对端侧硬件测试风险的控制；
根据日志和耗时反证测试隔离是否有效的能力。
```

---

## 29. 实验 11 最终结论

实验 11 完成了 RK3588 多模态语音助手意图路由从实验性补丁到正式工程模块的重构。

实验首先审计了 `IntentRouter` 的真实运行结构，确认原始 `analyze()` 使用宽泛 `photo_keywords` 子串匹配，而文件末尾又通过 monkey patch 覆盖为 EXP10 严格策略。随后在独立 Git 分支中删除覆盖式实现，正式重写 `IntentRouter.analyze()`，将规则拆分为明确拍照动作、精确视觉命令、视觉上下文、视觉动作和文本语境阻断五类，并将命中规则与命中词组写入 `Intent` 调试字段。

自动化测试方面，实验建立了 6 项 IntentRouter 单元测试和 7 项 Orchestrator Mock 集成测试，共 13 项测试。测试覆盖普通文本不拍照、视觉请求拍照一次、`need_photo_override`、`force_photo`、图片前缀和文本阻断等核心行为。

实验过程中首次 Mock 集成测试错误地替换了 `assistant.camera` 和 `assistant.qwen`，但真实代码调用的是 `self.capture_photo()` 并在方法内部构造 `QwenRunner`，导致测试意外运行真实摄像头和真实 Qwen 推理。通过日志中的真实图片路径、真实模型回答和两百多秒测试时长，确认 Mock 未生效。修复后改为 patch 实例的 `capture_photo` 方法和 `voice_assistant.orchestrator.QwenRunner` 符号，7 项集成测试在 0.025 秒内完成，13 项完整测试在 0.041 秒内完成，照片目录前后数量一致且无残留进程，证明硬件和模型已经被真正隔离。

真实回归方面，底层文本问题“一加一等于几”正确回答且不拍照，底层视觉请求成功生成图片并进入 Qwen3-VL。完整文本语音链路中，KWS 识别“鲁班猫”，ASR 识别“一加一等于几”，`photo_intent_hint=0`、`new_photo_count=0`，Qwen 在 8.544 秒内回答“一加一等于二。”，TTS 在 5.448 秒内完成。完整视觉语音链路中，ASR 将命令识别为“看一下画面”，新组合规则仍正确判断视觉意图并拍摄一张 1280×720 JPEG，Qwen3-VL 在 11.725 秒内生成 35 字场景描述，TTS 在 12.261 秒内完成，最终状态为 PASSED，无错误和残留进程。

最终代码提交到：

```text
branch : exp/11-intent-router-refactor
commit : 19b90b1
message: refactor: formalize intent router and add regression tests
```

因此实验 11 可以正式判定为：

```text
意图路由正式重构通过；
自动化单元测试通过；
Mock 集成测试通过；
真实文本模块回归通过；
真实视觉模块回归通过；
完整文本语音闭环通过；
完整视觉语音闭环通过；
Git 提交完成。
```

---

## 30. 一句话总结

```text
实验 11 将 RK3588 多模态语音助手的 EXP10 临时意图 monkey patch 正式重构为配置化的组合路由规则，建立 13 项单元与 Mock 集成测试，并修复错误 Mock 注入导致真实摄像头和 Qwen 被意外执行的问题，最终重新跑通文本与视觉两条 KWS->ASR->Qwen/Qwen3-VL->TTS 完整闭环，并以提交 19b90b1 完成代码归档。
```
