# 词达人打卡自动化工具包 · vocabgo-checkin-toolkit

用 AI 代理（或脚本）在 Windows 上完成「词达人」小程序（`app.vocabgo.com`）的每日**练习 + 打卡**。

**核心设计：不用固定坐标。** 每次操作都重新截图，由 `ui.py` 识别出选项行 / 单词块 / 绿色按钮 / 拼写输入框的真实位置，再按「第几个」去点。因此选项数量、位置、页面高度变化都不影响。

只走一条接入路径：**电脑版微信里打开的小程序窗口**（进程 `WeChatAppEx`）。不再需要手机投屏。

---

## 安装

需要 **Windows + PowerShell 5.1+ + Python 3.9+**。

```powershell
cd vocabgo-checkin-toolkit
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

`install.ps1` 会：
1. 把 `skill\` 复制到 `%USERPROFILE%\.agents\skills\vocabgo-daily-checkin\`（DSH 技能库）；
2. `pip install numpy pillow sounddevice soundcard`（元素识别 + 听音频识别，约 30MB，走清华镜像）。

手动等价命令：

```powershell
copy-item .\skill "$env:USERPROFILE\.agents\skills\vocabgo-daily-checkin" -Recurse -Force
python -m pip install --only-binary=:all: -i https://pypi.tuna.tsinghua.edu.cn/simple numpy pillow sounddevice soundcard
```

---

## 快速开始

在**电脑版微信**里打开词达人小程序（停在任意页面），然后：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
$auto = "$env:USERPROFILE\.agents\skills\vocabgo-daily-checkin\scripts\auto.ps1"

& $auto info                  # 期望 SIZE=<宽>x<高> FG_MATCH=True
& $auto shot -Out .\now.png   # 截图看当前在哪一屏
& $auto ui                    # 打印识别到的元素（JSON）
```

`auto.ps1` 的常用命令：

| 命令 | 作用 |
|---|---|
| `shot -Out a.png` | 截图（给模型读题 / 人看） |
| `ui` | 识别元素：`rows`(整行选项) / `chips`(词块) / `buttons`(绿色按钮) / `input`(拼写框) / `back` |
| `opt -N 3` | 点第 3 个整行选项 |
| `chip -N 2` | 点第 2 个单词块 |
| `continue` | 点最下面的绿色按钮（继续/提交） |
| `btn -N 1` | 点第 1 个绿色按钮（弹窗「确认」） |
| `spell -Text guilty` | 拼写题：点输入框 → 剪贴板粘贴整词 → 点提交 |
| `back` / `key -Vk 8 -N 4` | 返回 / 原始按键（8=退格） |

---

## 五类画面

| `ui` 输出的 kind | 画面 | 做法 |
|---|---|---|
| `options` | 英文句子/词 + 4 个整行中文选项 | 判断词义 → `opt -N <行号>` |
| `chips` | 中文释义 + 空格 + 英文词块（含"选常见搭配词"多选） | 数词块序号 → 按短语顺序 `chip -N` |
| `grid` | 选词页（一堆词方块） | 用户选，或按 `chip -N` 点 |
| `spelling` | 前几个字母 + 下划线 + 中文 + 提交 | `spell -Text <整词>` |
| `dialog` | 弹窗（题型说明/加分提示） | `btn -N 1` 确认 |

---

## 听音频题

1. `options` 页只有 `▶播放` + 4 个中文选项，无文字线索；
2. **选项集合启发式**：本轮只涉及 N 个词，选项中只有属于这些词的释义才可能是答案，唯一命中直接用；
3. 剩两个候选 → 录音识别（音频从电脑扬声器出来，用回环录音）：
   ```powershell
   cd ..\audio
   python listen2.py --seconds 3 --bank app_templates --save rec.wav
   ```
   模板优先用小程序自己的发音（单词卡点 🔊 / 答对后点 ▶ 时录下来存 `app_templates\<word>.wav`），同音色 `dist≈0.4`；TTS 模板跨音色 `dist≈2.2` 只能兜底。

---

## 目录结构

```
skill/
  SKILL.md              代理读的操作手册（元素识别流程 + 命令 + 排错）
  scripts/auto.ps1      入口：截图→识别→按序号点击
  scripts/ui.py         截图 → 元素 JSON（rows/chips/buttons/input/back）
  scripts/wx.ps1        底层窗口操作（调试用）
  audio/listen2.py      回环录音 + MFCC/DTW 识别
  audio/listen.py       PortAudio 版录音
  audio/match_file.py   对已有 wav 打分
  audio/tts_words.ps1   TTS 批量生成候选词模板
  audio/templates/      TTS 模板（兜底）
  audio/app_templates/  小程序真实发音模板（高精度）
  词汇表.md             实词释义/搭配/拼写提示字母对照
  docs/                 各题型与打卡完成页参考截图
install.ps1             一键安装
```

---

## 已知限制

- 只支持 Windows。
- 元素识别按「白底 + 描边」的通用规则找框；UI 大改（例如整页重绘成卡片流）可能失效，需要更新 `ui.py`。
- 拼写题必须用剪贴板粘贴，中文输入法会吞英文键入。
- 听音频识别精度取决于是否积累了小程序真实发音模板。
- 打卡页、选词页这类"整页图标网格"识别较弱，参与时以截图人工/模型判读为主。

## 免责声明

仅用于个人学习与自动化技术研究。代做作业/打卡可能违反平台或课程规定，风险自负。

## License

MIT
