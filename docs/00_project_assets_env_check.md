# 00 项目资产与环境确认实验

> 项目：RK3588 端侧多模态智能语音助手系统  
> 平台：LubanCat / RK3588  
> 仓库：Qwen-Chat-Assistant  
> 实验编号：00  
> 实验主题：代码仓库、GitHub 访问、模型资产、摄像头、麦克风、喇叭与配置文件基线确认  

---

## 1. 实验背景

本项目目标是在 RK3588 / LubanCat 上复现并拓展一个端侧多模态智能语音聊天助手。

项目整体链路为：

```text
KWS 唤醒词检测
    -> 中文指令录音
    -> 本地 ASR 语音识别
    -> 意图判断
    -> 摄像头拍照
    -> Qwen3-VL RKNN/RKLLM 多模态推理
    -> TTS 语音合成
    -> ALSA 喇叭 / 耳机播放
```

由于该项目涉及较多本地大文件资产，包括：

```text
Qwen3-VL vision RKNN 模型
Qwen3-VL LLM RKLLM 模型
RKNN runtime
RKLLM runtime
demo / imgenc 可执行程序
KWS / ASR / TTS / Vocos 语音模型
```

这些内容通常不会直接提交到 GitHub 仓库，因此第一个实验不直接运行完整助手，而是先确认：

```text
1. GitHub 访问方式是否可用
2. 代码仓库是否成功拉取
3. 摄像头设备是否存在
4. 麦克风设备是否可采集
5. 播放设备是否可出声
6. 项目配置文件是否需要根据当前板端修正
7. 模型与 runtime 资产是否齐全
```

本实验的目标是建立后续实验的环境基线，避免后面在 Qwen、ASR、TTS 或摄像头模块中出现问题时无法定位原因。

---

## 2. 实验目录

项目目录：

```text
/home/cat/ai/qwen3vl2b
```

主要文件结构：

```text
/home/cat/ai/qwen3vl2b
├── assets/
├── config/
│   ├── default.yaml
│   └── wake_keywords.txt
├── scripts/
│   ├── capture-photo.sh
│   ├── run_listen.sh
│   ├── run_listen_forever.sh
│   ├── test_camera.sh
│   ├── test_qwen_text.sh
│   ├── test_stt_record.sh
│   ├── test_tts_play.sh
│   └── test_wake_record.sh
├── voice_assistant/
│   ├── asr.py
│   ├── audio_io.py
│   ├── camera.py
│   ├── cli.py
│   ├── config.py
│   ├── intent.py
│   ├── orchestrator.py
│   ├── qwen_runner.py
│   ├── streaming_tts.py
│   ├── text_clean.py
│   ├── tts.py
│   └── wake.py
├── voice_assistant.py
├── run_qwen3vl.sh
├── requirements.txt
├── demo.jpg
└── readme.md
```

---

## 3. GitHub 访问问题定位与解决

### 3.1 初始问题

最开始直接在板端使用 HTTPS clone：

```bash
git clone https://github.com/FlankKaicoder/Qwen-Chat-Assistant.git qwen3vl2b
```

出现错误：

```text
fatal: 无法访问 'https://github.com/FlankKaicoder/Qwen-Chat-Assistant.git/'：Empty reply from server
```

随后测试 GitHub 网络：

```bash
ping -c 3 github.com
curl -v https://github.com 2>&1 | head -20
```

现象为：

```text
ping github.com 可以成功
curl https://github.com 连接 443 端口超时
```

说明：

```text
ICMP 可达不代表 HTTPS 可达；
当前问题不是仓库地址错误，也不是 git 命令错误，而是板端访问 github.com:443 超时。
```

### 3.2 分层网络测试

执行：

```bash
cd /home/cat/ai

echo "========== DNS =========="
getent hosts github.com
getent hosts ssh.github.com
getent hosts raw.githubusercontent.com

echo
echo "========== curl IPv4 =========="
curl -4Iv --connect-timeout 10 https://github.com 2>&1 | head -40

echo
echo "========== curl IPv6 =========="
curl -6Iv --connect-timeout 10 https://github.com 2>&1 | head -40

echo
echo "========== TCP 443 test =========="
timeout 8 bash -c 'cat < /dev/null > /dev/tcp/github.com/443' && echo "github.com:443 OK" || echo "github.com:443 FAIL"

echo
echo "========== SSH 443 test =========="
timeout 8 bash -c 'cat < /dev/null > /dev/tcp/ssh.github.com/443' && echo "ssh.github.com:443 OK" || echo "ssh.github.com:443 FAIL"

echo
echo "========== TCP 22 test =========="
timeout 8 bash -c 'cat < /dev/null > /dev/tcp/github.com/22' && echo "github.com:22 OK" || echo "github.com:22 FAIL"
```

关键结果：

```text
github.com:443      FAIL
ssh.github.com:443  OK
github.com:22       OK
```

结论：

```text
板端不能稳定使用 HTTPS clone；
但 GitHub SSH 访问可用；
后续应使用 SSH 工作流进行 git clone / pull / push。
```

### 3.3 最终处理方案

采用 GitHub SSH 方式拉取仓库。

仓库已经成功克隆到：

```text
/home/cat/ai/qwen3vl2b
```

拉取后检查：

```bash
cd /home/cat/ai/qwen3vl2b

pwd
ls -lh
find . -maxdepth 2 -type f | sort | head -80
```

确认代码、脚本和配置文件均已存在。

---

## 4. 项目默认配置检查

查看配置文件：

```bash
cd /home/cat/ai/qwen3vl2b

echo "========== config/default.yaml =========="
sed -n '1,240p' config/default.yaml

echo
echo "========== requirements.txt =========="
cat requirements.txt

echo
echo "========== wake keywords =========="
cat config/wake_keywords.txt
```

### 4.1 默认路径配置

```yaml
paths:
  project_dir: /home/cat/ai/qwen3vl2b
  temp_dir: /tmp/qwen_voice_assistant
  photo_dir: /home/cat/图片
  placeholder_image: /home/cat/ai/qwen3vl2b/demo.jpg
  capture_script: /home/cat/ai/qwen3vl2b/scripts/capture-photo.sh
```

### 4.2 原始音频配置

原始配置为：

```yaml
audio:
  mic_device: plughw:4,0
  speaker_device: plughw:4,0
  playback_channels: 2
  playback_sample_rate: 44100
  playback_mode: stereo_dup
  sample_rate: 16000
  channels: 2
  input_channel: left
  mixer_card: 4
  capture_channel_gain: 8
  wake_input_gain: 8.0
  asr_input_gain: 5.0
  command_seconds: 6
  wake_chunk_seconds: 2
```

该配置与当前板端实际声卡编号不一致，后续已修正为 `plughw:2,0`。

### 4.3 Qwen 模型配置

```yaml
qwen:
  demo: /home/cat/ai/qwen3vl2b/demo
  vision_model: /home/cat/ai/qwen3vl2b/qwen3-vl-2b_vision_rk3588.rknn
  llm_model: /home/cat/ai/qwen3vl2b/qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
  max_new_tokens: 2048
  max_context_len: 4096
  rknn_core_num: 3
```

这说明后续实验 01 运行 Qwen3-VL 基线时必须补齐：

```text
demo
imgenc
librknnrt.so
librkllmrt.so
qwen3-vl-2b_vision_rk3588.rknn
qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
```

### 4.4 唤醒词配置

```text
l ǔ b ān m āo @鲁班猫
p āi zh ào zh ù sh ǒu @拍照助手
```

默认唤醒词为：

```text
鲁班猫
拍照助手
```

---

## 5. 实验 00 自动检查脚本

为了复现环境检查过程，写入脚本：

```bash
cd /home/cat/ai/qwen3vl2b

mkdir -p output scripts docs

cat > scripts/exp00_env_asset_check.sh <<'EOF'
#!/usr/bin/env bash

set -u

OUT_DIR="${1:-output/exp00_env_asset_check_manual}"
mkdir -p "$OUT_DIR"

LOG="$OUT_DIR/exp00_env_asset_check.log"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 00: RK3588 Qwen Voice Assistant Env/Asset Check "
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out_dir : $OUT_DIR"
echo

echo "==================== 1. system info ===================="
uname -a || true
echo
cat /etc/os-release 2>/dev/null || true
echo

echo "==================== 2. repo info ===================="
git remote -v || true
echo
git branch --show-current || true
git log -1 --oneline || true
echo
ls -lh
echo

echo "==================== 3. command availability ===================="
for cmd in git python3 pip3 ffmpeg v4l2-ctl arecord aplay amixer file ldd sha256sum; do
    printf "%-12s : " "$cmd"
    if command -v "$cmd" >/dev/null 2>&1; then
        command -v "$cmd"
    else
        echo "MISSING"
    fi
done
echo

echo "==================== 4. python info ===================="
python3 --version || true
pip3 --version || true
echo

echo "==================== 5. requirements.txt ===================="
if [ -f requirements.txt ]; then
    cat requirements.txt
else
    echo "[MISS] requirements.txt"
fi
echo

echo "==================== 6. config/default.yaml ===================="
if [ -f config/default.yaml ]; then
    sed -n '1,240p' config/default.yaml
else
    echo "[MISS] config/default.yaml"
fi
echo

echo "==================== 7. required assets ===================="

check_path() {
    local p="$1"
    if [ -e "$p" ]; then
        if [ -d "$p" ]; then
            echo "[OK ] DIR  $p"
            find "$p" -maxdepth 2 -type f | head -20 | sed 's/^/      /'
        else
            echo "[OK ] FILE $p"
            ls -lh "$p"
            file "$p" 2>/dev/null || true
            sha256sum "$p" 2>/dev/null | awk '{print "      sha256:", $1}' || true
        fi
    else
        echo "[MISS]      $p"
    fi
}

REQUIRED_PATHS=(
"./demo"
"./imgenc"
"./librknnrt.so"
"./librkllmrt.so"
"./qwen3-vl-2b_vision_rk3588.rknn"
"./qwen3-vl-2b-instruct_w8a8_rk3588.rkllm"
"./models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20"
"./models/sherpa-onnx-conformer-zh-stateless2-2023-05-23"
"./models/matcha-icefall-zh-baker"
"./models/vocos-22khz-univ.onnx"
"./demo.jpg"
)

missing=0
for p in "${REQUIRED_PATHS[@]}"; do
    check_path "$p"
    if [ ! -e "$p" ]; then
        missing=$((missing + 1))
    fi
done
echo

echo "==================== 8. executable bit check ===================="
for f in ./demo ./imgenc ./run_qwen3vl.sh ./scripts/capture-photo.sh ./voice_assistant.py; do
    if [ -e "$f" ]; then
        ls -lh "$f"
        if [ -x "$f" ]; then
            echo "[OK ] executable: $f"
        else
            echo "[WARN] not executable: $f"
        fi
    else
        echo "[MISS] $f"
    fi
done
echo

echo "==================== 9. ldd check ===================="
for f in ./demo ./imgenc; do
    if [ -e "$f" ]; then
        echo
        echo "----- ldd $f -----"
        ldd "$f" || true
    else
        echo "[SKIP] $f not found"
    fi
done
echo

echo "==================== 10. camera device check ===================="
echo "----- /dev/video* -----"
ls -lh /dev/video* 2>/dev/null || true
echo

echo "----- v4l2-ctl --list-devices -----"
v4l2-ctl --list-devices || true
echo

if [ -e /dev/video11 ]; then
    echo "[OK] /dev/video11 exists"
    echo
    echo "----- v4l2-ctl -d /dev/video11 --all -----"
    v4l2-ctl -d /dev/video11 --all || true
    echo
    echo "----- v4l2-ctl -d /dev/video11 --list-formats-ext -----"
    v4l2-ctl -d /dev/video11 --list-formats-ext || true
else
    echo "[WARN] /dev/video11 not found"
fi
echo

echo "==================== 11. audio device check ===================="
echo "----- arecord -l -----"
arecord -l || true
echo

echo "----- aplay -l -----"
aplay -l || true
echo

echo "----- /proc/asound/cards -----"
cat /proc/asound/cards 2>/dev/null || true
echo

echo "==================== 12. writable dir check ===================="
mkdir -p /tmp/qwen_voice_assistant
mkdir -p /home/cat/图片

ls -ld /tmp/qwen_voice_assistant || true
ls -ld /home/cat/图片 || true

touch /tmp/qwen_voice_assistant/write_test.tmp 2>/dev/null && echo "[OK] /tmp/qwen_voice_assistant writable" || echo "[WARN] /tmp/qwen_voice_assistant not writable"
rm -f /tmp/qwen_voice_assistant/write_test.tmp

touch /home/cat/图片/write_test.tmp 2>/dev/null && echo "[OK] /home/cat/图片 writable" || echo "[WARN] /home/cat/图片 not writable"
rm -f /home/cat/图片/write_test.tmp
echo

echo "==================== 13. summary ===================="
echo "missing_required_assets: $missing"

if [ "$missing" -eq 0 ]; then
    echo "[RESULT] Required assets appear complete. You can continue to Experiment 01."
else
    echo "[RESULT] Some required assets are missing. Fill them before Experiment 01."
fi

echo
echo "log saved to: $LOG"
EOF

chmod +x scripts/exp00_env_asset_check.sh
```

运行：

```bash
cd /home/cat/ai/qwen3vl2b

EXP=output/exp00_env_asset_check_$(date +%Y%m%d_%H%M%S)
mkdir -p "$EXP"

./scripts/exp00_env_asset_check.sh "$EXP"
```

---

## 6. 模型与 runtime 资产检查结果

提取缺失项：

```bash
grep -E "\[MISS\]|\[WARN\]|missing_required_assets|\[RESULT\]" "$EXP/exp00_env_asset_check.log"
```

结果：

```text
[MISS]      ./demo
[MISS]      ./imgenc
[MISS]      ./librknnrt.so
[MISS]      ./librkllmrt.so
[MISS]      ./qwen3-vl-2b_vision_rk3588.rknn
[MISS]      ./qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
[MISS]      ./models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20
[MISS]      ./models/sherpa-onnx-conformer-zh-stateless2-2023-05-23
[MISS]      ./models/matcha-icefall-zh-baker
[MISS]      ./models/vocos-22khz-univ.onnx
[MISS] ./demo
[MISS] ./imgenc
missing_required_assets: 10
[RESULT] Some required assets are missing. Fill them before Experiment 01.
```

结论：

```text
当前代码仓库已经正常拉取；
但模型、runtime 和语音模型等大文件资产尚未补齐；
因此暂时不能进入实验 01：Qwen3-VL RKNN/RKLLM 基线验证。
```

需要补齐的文件包括：

```text
./demo
./imgenc
./librknnrt.so
./librkllmrt.so
./qwen3-vl-2b_vision_rk3588.rknn
./qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
./models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20
./models/sherpa-onnx-conformer-zh-stateless2-2023-05-23
./models/matcha-icefall-zh-baker
./models/vocos-22khz-univ.onnx
```

---

## 7. 摄像头设备检查

### 7.1 设备列表

检查命令：

```bash
ls -lh /dev/video*
v4l2-ctl --list-devices
```

关键结果：

```text
/dev/video11 存在
/dev/video-camera0 -> video11
```

设备分布：

```text
rk_hdmirx:
    /dev/video20

rkisp-statistics:
    /dev/video18
    /dev/video19

rkcif:
    /dev/video0 ~ /dev/video10

rkisp_mainpath:
    /dev/video11
    /dev/video12
    /dev/video13
    /dev/video14
    /dev/video15
    /dev/video16
    /dev/video17
```

### 7.2 /dev/video11 详细信息

检查命令：

```bash
v4l2-ctl -d /dev/video11 --all
v4l2-ctl -d /dev/video11 --list-formats-ext
```

关键结果：

```text
Driver name      : rkisp_v6
Card type        : rkisp_mainpath
Bus info         : platform:rkisp0-vir0
Driver version   : 2.2.1
Device Caps      : Video Capture Multiplanar / Streaming / Extended Pix Format
Current Format   : 1280x720 NV12
```

当前格式：

```text
Width/Height      : 1280/720
Pixel Format      : 'NV12' (Y/CbCr 4:2:0)
Bytes per Line    : 1280
Size Image        : 1382400
```

支持格式：

```text
UYVY
NV16
NV61
NV21
NV12
NM21
NM12
```

支持分辨率范围：

```text
32x32 - 3840x2160，步进 8/8
```

### 7.3 摄像头结论

```text
当前项目默认配置中的摄像头设备 /dev/video11 与板端实际设备匹配；
/dev/video11 是 rkisp_mainpath，支持 NV12；
后续实验 02 可以直接基于 /dev/video11 进行拍照链路验证。
```

---

## 8. 音频设备检查与修正

### 8.1 初始设备检查

检查命令：

```bash
arecord -l
aplay -l
cat /proc/asound/cards
```

结果：

```text
card 0: rockchip-hdmiin
    仅采集

card 1: rockchip-dp0
    仅播放

card 2: rockchip-es8388
    支持采集和播放
```

具体信息：

```text
CAPTURE:
card 0: rockchip-hdmiin, device 0
card 2: rockchip-es8388, device 0

PLAYBACK:
card 1: rockchip-dp0, device 0
card 2: rockchip-es8388, device 0
```

因此，当前板端真正适合作为语音助手输入输出的设备是：

```text
plughw:2,0
```

### 8.2 Mixer 状态检查

检查命令：

```bash
amixer -c 2 scontrols
amixer -c 2 scontents | head -200
```

关键状态：

```text
Speaker            : on
Headphone          : on
PCM                : 100%
Output 1           : 100%
Output 2           : 100%
Capture Digital    : 100%
Capture Mute       : off
Main Mic           : on
Headset Mic        : off
Left Channel Gain  : 9.00 dB
Right Channel Gain : 9.00 dB
ALC Capture        : Stereo
```

说明 ES8388 codec 已经被系统识别，输入输出 mixer 并非处于静音状态。

### 8.3 项目音频配置修正

原始配置：

```yaml
mic_device: plughw:4,0
speaker_device: plughw:4,0
mixer_card: 4
```

当前板端实际应使用：

```yaml
mic_device: plughw:2,0
speaker_device: plughw:2,0
mixer_card: 2
```

修正命令：

```bash
cd /home/cat/ai/qwen3vl2b

python3 - <<'PY'
from pathlib import Path

p = Path("config/default.yaml")
s = p.read_text()

s = s.replace("mic_device: plughw:4,0", "mic_device: plughw:2,0")
s = s.replace("speaker_device: plughw:4,0", "speaker_device: plughw:2,0")
s = s.replace("speaker_device: plughw:1,0", "speaker_device: plughw:2,0")
s = s.replace("mixer_card: 4", "mixer_card: 2")

p.write_text(s)
PY

sed -n '/audio:/,/models:/p' config/default.yaml
```

修正后的配置：

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

### 8.4 录音测试

测试命令：

```bash
cd /home/cat/ai/qwen3vl2b

mkdir -p output/exp00_audio_device_test

arecord -D plughw:2,0 \
  -f S16_LE \
  -r 16000 \
  -c 2 \
  -d 5 \
  -vv \
  output/exp00_audio_device_test/test_mic_5s.wav
```

现象：

```text
录音过程中终端音量条有明显变化；
说明麦克风输入链路可以采集到信号。
```

进一步使用 ffmpeg 检查录音文件音量：

```bash
ffmpeg -hide_banner \
  -i output/exp00_audio_device_test/test_mic_5s.wav \
  -af volumedetect \
  -f null - 2>&1 | tee output/exp00_audio_device_test/volumedetect.log

grep -E "mean_volume|max_volume" output/exp00_audio_device_test/volumedetect.log
```

结果：

```text
mean_volume: -34.8 dB
max_volume : -12.1 dB
```

结论：

```text
录音文件不是静音文件；
max_volume=-12.1 dB 说明文件内存在有效语音峰值；
麦克风采集链路通过。
```

### 8.5 播放测试问题与最终定位

最开始执行：

```bash
speaker-test -D plughw:2,0 -c 2 -t sine -f 1000 -l 1
aplay -D plughw:2,0 output/exp00_audio_device_test/test_mic_5s.wav
```

现象：

```text
命令可以运行，但听不到声音。
```

一开始怀疑方向：

```text
1. 播放设备配置错误
2. ES8388 mixer 输出路由错误
3. 声卡被占用
4. 录音文件音量过低
```

但进一步检查发现：

```text
录音文件 max_volume=-12.1 dB，并非静音；
Speaker / Headphone / PCM / Output 1 / Output 2 均已打开；
speaker-test 可以正常打开 plughw:2,0。
```

最终定位：

```text
不是 ALSA、mixer、驱动或项目配置问题；
而是耳机原本插在电脑上，没有插在 RK3588 板子的音频输出口。
```

将耳机插到板子上后，声音可以正常听到。

### 8.6 音频结论

```text
ES8388 card 2 可同时用于麦克风输入和耳机 / 喇叭输出；
当前板端音频最终配置为 plughw:2,0；
麦克风录音和播放输出均已验证通过。
```

---

## 9. 当前实验结论

实验 00 当前结论如下：

```text
1. GitHub HTTPS 访问失败，但 GitHub SSH 可用；
   后续开发应使用 SSH 地址进行 git clone / pull / push。

2. 代码仓库已经成功拉取到：
   /home/cat/ai/qwen3vl2b

3. 摄像头设备 /dev/video11 存在；
   该设备为 rkisp_mainpath，支持 NV12；
   项目默认摄像头配置与当前板端匹配。

4. 音频设备原始配置 plughw:4,0 与当前板端不匹配；
   当前板端应使用 rockchip-es8388，即 plughw:2,0。

5. 录音链路验证通过；
   arecord 音量条有变化，录音文件 max_volume=-12.1 dB。

6. 播放链路验证通过；
   最初无声是因为耳机插在电脑上，耳机插回板子后 plughw:2,0 可正常出声。

7. 当前阻塞项是模型和 runtime 资产缺失；
   missing_required_assets: 10；
   暂时不能进入实验 01。
```

---

## 10. 当前已通过内容

| 检查项 | 状态 | 说明 |
|---|---|---|
| GitHub 仓库拉取 | 通过 | HTTPS 不通，SSH 可用 |
| 代码目录结构 | 通过 | config / scripts / voice_assistant 均存在 |
| 摄像头设备 | 通过 | /dev/video11 存在，NV12 |
| 麦克风设备 | 通过 | plughw:2,0 可录音 |
| 播放设备 | 通过 | plughw:2,0 可播放 |
| 配置文件修正 | 通过 | 音频已改为 card 2 |
| 模型资产 | 未通过 | 缺失 10 项 |
| runtime 资产 | 未通过 | librknnrt.so / librkllmrt.so 缺失 |

---

## 11. 后续需要补齐的资产

进入实验 01 之前必须补齐：

```text
./demo
./imgenc
./librknnrt.so
./librkllmrt.so
./qwen3-vl-2b_vision_rk3588.rknn
./qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
```

进入后续 KWS / ASR / TTS 实验之前必须补齐：

```text
./models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20
./models/sherpa-onnx-conformer-zh-stateless2-2023-05-23
./models/matcha-icefall-zh-baker
./models/vocos-22khz-univ.onnx
```

---

## 12. 下一步实验计划

### 12.1 实验 00-B：模型资产补齐

目标：

```text
补齐 demo、imgenc、runtime、RKNN/RKLLM、KWS、ASR、TTS、Vocos 模型资产；
重新运行 exp00_env_asset_check.sh；
确认 missing_required_assets 从 10 变为 0。
```

### 12.2 实验 01：Qwen3-VL RKNN/RKLLM 基线验证

目标：

```text
不接入语音、不接入摄像头；
只验证 Qwen3-VL demo + vision RKNN + LLM RKLLM 能否独立运行。
```

### 12.3 实验 02：摄像头拍照链路验证

目标：

```text
验证 /dev/video11 -> NV12 -> JPG -> Qwen 图片输入链路。
```

### 12.4 实验 03：麦克风录音链路验证

目标：

```text
在当前 plughw:2,0 配置下，验证语音助手录音逻辑是否可用。
```

---

## 13. 实验 00 最终阶段性结论

```text
实验 00 已完成代码仓库、网络访问、摄像头设备、音频设备和配置修正验证。

当前 RK3588 板端具备继续复现实验的硬件基础；
后续阻塞点不再是摄像头或音频设备，而是模型和 runtime 大文件资产缺失。

补齐模型资产后，即可进入实验 01：Qwen3-VL RKNN/RKLLM 基线验证。
```
