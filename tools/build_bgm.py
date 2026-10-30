# -*- coding: utf-8 -*-
"""
把作者的原始 BGM 处理成 Godot 能用的「循环 Ogg（Vorbis）」。

为什么不能把 WAV 直接丢进 Godot：
  1. 体积：原始 209.8s / 44.1kHz / stereo 的 WAV 是 35 MB；Ogg q6 只要 ~5 MB。
  2. 首尾安静段：AI 生成 / 歌曲类素材两头常自带引子和收尾淡出。原样循环 = 每次回到
     开头都先静一下、每次到结尾又淡没，音乐是「断」的。
     实测这首（0.05~0.1s 窗 RMS）：
       · 头：0.00~0.14s 近乎无声（-58 / -84 / -68 dB），**音乐从 0.15s 才起来**。
       · 尾：~207s 起进入编曲的收尾淡出，208.25s 后掉到 -45 dB 以下，208.6s 后彻底静音。
  3. 采样级接缝：就算裁到「音乐还在响」的位置，直接首尾相接也会有跳变（「咔」）。

裁点怎么定的（全部来自实测电平，不是拍脑袋）：
  · 起点 A = 0.15s  —— 音乐真正的 onset，把前面那段静音引子切掉。
  · 终点 B = 206.00s —— 此处电平 **-22.6 dB**，而起点 0.15s 处是 **-23.2 dB**，
    两边几乎相等 → 接缝响度天然对齐（只差 0.6 dB）。再往后 207s+ 就是收尾淡出，
    留着只会在每轮循环的末尾拖一条「越来越小」的尾巴。

交叉淡化接缝（crossfade loop，X = 40ms）：
    blend[s] = R[M-X+s]·(1 - s/X) + R[s]·(s/X)        s = 0 … X-1
    O        = R[X : M-X] ++ blend
  R 是裁剪后的整段。这样 O 的**最后一个采样 ≈ R[X-1]**，循环回 O 的**第一个采样 = R[X]**，
  采样级连续；同时也把「末尾 X」和「开头 X」真正重叠掉（而不是原样首尾相接）。
  ⚠ 注意 blend 必须接在**末尾**：若是放在开头（O = blend ++ R[X:M]），循环点会变成
    「R[M-1] → R[M-X]」= 往回跳 40ms，反而制造出一个可听的重复。脚本末尾会用
    「接缝 |相邻采样差| 在曲中分位」把这件事量出来（落在 p99.9 以上才算能听见）。

跑法（本机没有 ffmpeg，Python 侧也装不了 soundfile → 借 Blender 内置的 aud 编码 Ogg）：
    /d/blender/blender.exe --background --python tools/build_bgm.py

产物：assets/audio/bgm_main.ogg
"""

import math
import os
import wave

import aud
import numpy as np

SRC = r"D:/xwechat_files/wxid_6z2g8f1replf22_4b59/msg/file/2026-10/背景音乐.wav"
OUT_OGG = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio", "bgm_main.ogg")
TMP_WAV = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools", "_tmp_bgm_loop.wav")

CUT_A = 0.15      # 起点（秒）—— 音乐 onset
CUT_B = 206.00    # 终点（秒）—— 电平与起点对齐处
XFADE = 0.04      # 接缝交叉淡化时长（秒）
BITRATE = 192000  # Vorbis 码率（q6 档）
OGG_QUALITY = 6   # 仅用于打印


def read_wav(path):
    w = wave.open(path, "rb")
    ch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
    raw = w.readframes(n)
    w.close()
    assert sw == 2, "只处理 16bit WAV"
    a = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    return a.reshape(-1, ch), sr


def write_wav(path, data, sr):
    x = np.clip(data, -1.0, 1.0)
    i16 = (x * 32767.0).round().astype("<i2")
    w = wave.open(path, "wb")
    w.setnchannels(data.shape[1])
    w.setsampwidth(2)
    w.setframerate(sr)
    w.writeframes(i16.tobytes())
    w.close()


def rms_db(x):
    m = float(np.mean(x.astype(np.float64) ** 2))
    return 10.0 * math.log10(m + 1e-12)


def window_db(mono, sr, t0, t1):
    i0, i1 = int(t0 * sr), min(int(t1 * sr), len(mono))
    if i1 <= i0:
        return -120.0
    return rms_db(mono[i0:i1])


def seam_report(name, seq):
    """量接缝连续度：|相邻采样差| 在整段分布里的分位（越低越听不出来）。"""
    mono = seq.mean(axis=1)
    d = np.abs(np.diff(mono))
    seam = abs(float(mono[0] - mono[-1]))  # 循环点：末尾 → 开头
    pct = float((d < seam).mean()) * 100.0
    print("    %-22s 接缝跳变 %.5f → 曲中 %.1f 分位（%s）"
          % (name, seam, pct, "听不出来" if pct < 99.9 else "⚠ 可能听见"))
    return pct


print("=" * 68)
print("读入：", os.path.basename(SRC))
full, sr = read_wav(SRC)
mono_all = full.mean(axis=1)
print("  %d 声道 / %d Hz / %.2f s / %d 帧"
      % (full.shape[1], sr, len(full) / sr, len(full)))

# ---- 原始（不做任何处理）的接缝，作为「反面参照」----
print("\n[0] 原样首尾相接（不处理）")
seam_report("原始 0~209.81s", full)

# ---- 1. 裁剪 ----
a = int(round(CUT_A * sr))
b = int(round(CUT_B * sr))
R = full[a:b].copy()
M = len(R)
print("\n[1] 裁剪  %.2fs ~ %.2fs  →  %.3f s / %d 帧" % (CUT_A, CUT_B, M / sr, M))
print("    头 0.00~0.05s 电平 %.1f dB" % window_db(R.mean(axis=1), sr, 0.0, 0.05))
print("    尾 末 0.05s     电平 %.1f dB" % window_db(R.mean(axis=1), sr, (M - int(0.05 * sr)) / sr, M / sr))
print("    → 接缝两边响度对齐（差 %.1f dB）"
      % abs(window_db(R.mean(axis=1), sr, 0.0, 0.05) - window_db(R.mean(axis=1), sr, (M - int(0.05 * sr)) / sr, M / sr)))

# ---- 2. 40ms 交叉淡化接缝 ----
X = int(round(XFADE * sr))
w = np.linspace(0.0, 1.0, X, endpoint=False, dtype=np.float32)[:, None]  # 淡入权重 s/X
tail = R[M - X:M]          # 末尾 X
head = R[0:X]              # 开头 X
blend = tail * (1.0 - w) + head * w          # 末尾淡出 + 开头淡入
O = np.concatenate([R[X:M - X], blend], axis=0)
print("\n[2] 交叉淡化 X = %d 采样（%.0f ms）" % (X, XFADE * 1000))
print("    blend[0] = R[M-X] ✓（与前段末采样连续）")
print("    O 长度 %.3f s（比裁剪段短 %.0f ms，因为首尾各 X 被重叠掉）" % (len(O) / sr, XFADE * 1000))

print("\n[3] 接缝连续度对比")
seam_report("✔ 处理后（blend 收尾）", O)
# 反面：blend 放开头（错误做法），证明为什么不能那么写
O_bad = np.concatenate([blend, R[X:M]], axis=0)
seam_report("✘ blend 放开头", O_bad)

# ---- 3. 写 Ogg ----
write_wav(TMP_WAV, O, sr)
print("\n[4] 编码 Ogg Vorbis q%d / %d kbps" % (OGG_QUALITY, BITRATE // 1000))
snd = aud.Sound.file(TMP_WAV)
snd.write(OUT_OGG, sr, O.shape[1], aud.FORMAT_S16, aud.CONTAINER_OGG,
          aud.CODEC_VORBIS, BITRATE, 1024)
os.remove(TMP_WAV)

src_mb = os.path.getsize(SRC) / 1048576.0
out_mb = os.path.getsize(OUT_OGG) / 1048576.0
print("    输出 %s" % OUT_OGG)
print("    %.1f MB → %.2f MB（%.0f%%）" % (src_mb, out_mb, 100.0 * out_mb / src_mb))
print("    整段 RMS %.1f dB（Godot 里 volume_db 参考它来定）" % rms_db(O))
print("=" * 68)
print("BGM_BUILD_OK")
