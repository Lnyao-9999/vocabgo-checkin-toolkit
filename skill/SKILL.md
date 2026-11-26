---
name: vocabgo-daily-checkin
description: 在 Windows 上用"截图识别元素→按序号点击"的方式自动完成词达人(vocabgo)小程序的每日打卡/练习（电脑版微信小程序窗口）。不用固定坐标：每次截图后由 ui.py 识别选项行、单词块、绿色按钮、拼写输入框的真实位置再点。覆盖词义选择、听音频选中文、搭配词多选、词组搭配、拼写填空。用户要求代做词达人打卡、自动答题、或复用微信小程序自动化时使用。
---

# 词达人（vocabgo）每日打卡自动化 · 元素识别版

## 核心原则（务必遵守）

1. **绝不使用固定坐标。** 每次打卡的选项数量、位置、页面高度都可能不同。
2. 每个动作都走同一条链路：**截图 → `ui.py` 识别元素 → 按序号选中 → 点击 → 再截图验证**。
3. 结果以界面为准：绿色「✓ 回答正确」才算过；红色「✗」会进单词详情卡。

## 环境（只有电脑版微信这一种接入方式）

| 项 | 要求 |
|---|---|
| 微信 | **电脑版微信**里打开词达人小程序（进程 `WeChatAppEx`，窗口 `Chrome_WidgetWin_0`） |
| 系统 | Windows + PowerShell 5.1+ |
| Python | 需要（`ui.py` 做元素识别）：`numpy`、`pillow`；听音频另需 `sounddevice`、`soundcard` |

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
python -m pip install --only-binary=:all: -i https://pypi.tuna.tsinghua.edu.cn/simple numpy pillow sounddevice soundcard
```

## 工具

| 命令 | 作用 |
|---|---|
| `auto.ps1 info` | 确认窗口在、是否前台（`FG_MATCH=True`） |
| `auto.ps1 shot -Out a.png` | 截图（给模型读题用） |
| `auto.ps1 ui` | 打印识别到的元素 JSON：`rows`/`chips`/`buttons`/`input`/`back`/`kind` |
| `auto.ps1 opt -N 3` | 点第 3 个**答案行**（自上而下） |
| `auto.ps1 chip -N 2` | 点第 2 个**单词块/网格词** |
| `auto.ps1 continue` | 点最下面的绿色按钮（继续 / 提交 / 开始练习） |
| `auto.ps1 btn -N 1` | 点第 1 个绿色按钮（弹窗「确认」常用） |
| `auto.ps1 back` | 点左上返回（自动识别位置） |
| `auto.ps1 spell -Text guilty` | 拼写题一条龙：点输入框 → 剪贴板粘贴整词 → 点提交 |
| `auto.ps1 type -Text xxx` | 只粘贴文本到当前输入框 |
| `auto.ps1 key -Vk 8 -N 4` | 原始按键（8=退格，13=回车） |

`ui.py` 的输出示例：

```json
{"kind":"options",
 "rows":[{"i":1,"x":252,"y":254,"w":433,"h":54}, ...],
 "chips":[], "buttons":[{"i":1,"x":252,"y":349,...}],
 "input":null, "back":{"x":40,"y":72}}
```

`kind` 含义：`options` 四选一题 / `chips` 词组搭配或多选 / `grid` 选词页 / `spelling` 拼写题 / `dialog` 弹窗。

## 标准循环

```powershell
$auto = "<skill目录>\scripts\auto.ps1"
& $auto shot -Out .\s.png     # 1) 截图（模型读题）
& $auto ui                    # 2) 看识别结果（元素数量/顺序）
& $auto opt -N 2              # 3) 按判断点第 N 个元素
& $auto shot -Out .\s2.png    # 4) 验证：是否出现 ✓ 回答正确
& $auto continue              # 5) 点继续进入下一题
```

## 五类画面怎么判

| kind | 画面特征 | 怎么做 |
|---|---|---|
| `options` | 一句英文/一个按钮组，下面 4 个整行选项 | 读句子判断词义 → `opt -N <行号>` |
| `chips` | 中文释义 + 2~5 个空 + 若干英文词块（或"选搭配词"多选） | 数出词块序号（左上→右下）→ 按短语顺序 `chip -N` |
| `grid` | "选择单词"页，一堆词方块 | 交给用户选；或按坐标换算点 `chip` |
| `spelling` | 单词提示前 2~3 字母 + 下划线 + 中文 + 提交 | `spell -Text <整词>` |
| `dialog` | 白底弹窗（题型说明/加分提示） | `btn -N 1` 点确认，或点空白关闭 |

## 听音频题（`▶播放` + 4 个中文选项）

1. **先看页面有没有文字线索**：通常没有。
2. **选项集合启发式**：本轮练习只涉及 N 个词（单词卡阶段记下来），4 个中文选项里只有属于这些词的才可能是答案；唯一命中就点它。
3. **剩两个候选时录音识别**（音频走电脑扬声器）：
   ```powershell
   cd <skill目录>\audio
   python listen2.py --seconds 3 --bank app_templates --save rec.wav
   ```
   - 模板优先用**小程序自己的发音**（在单词卡点 🔊 或答对后点 ▶ 时录制，存 `app_templates/<word>.wav`）；
   - 同音色模板 dist≈0.4（可靠），TTS 模板跨音色 dist≈2.2（不可靠，仅兜底）；
   - `ranking[0].word` 即识别结果，`dist < 1.0` 视为高置信。
4. 仍不确定：问用户，或先猜（答错只扣分，流程继续）。

## 输入与控件的坑

1. **拼音/中文输入法会吃掉英文**：拼写题一律用 `auto.ps1 spell`（内部走剪贴板 + Ctrl+V），不要逐字母敲。
2. **首次点击可能被吞**：同一个动作点第二次；`FG_MATCH=False` 时先 `auto.ps1 info` 重新激活。
3. **双击文本会弹词典**：不要在正文上连点。
4. **弹窗遮挡**：`dialog` 状态下先 `btn -N 1`（确认），再处理下面的题。
5. 每次点击后等 600~1200ms 再截图，小程序有动画/网络延迟。

## 收尾

练习完成会出现「恭喜您 +N 积分 +M 能量包」。随后：
`auto.ps1 back` 回首页 → `auto.ps1 ui` 找到「打卡」格 → `chip -N <序号>` → 截图确认「今日打卡 已完成 / +5积分 / 累计 N 天」。

## 文件清单

```
scripts/auto.ps1    元素识别 + 点击的入口（推荐只记这一个）
scripts/ui.py       截图 → 元素 JSON（rows/chips/buttons/input/back/kind）
scripts/wx.ps1      底层窗口操作（截图/点击/按键，调试用）
audio/listen2.py    默认扬声器回环录音 + MFCC/DTW 识别（听音频题）
audio/listen.py     PortAudio 版录音（备用）
audio/match_file.py 对已有 wav 打分
audio/tts_words.ps1 Windows TTS 批量生成候选词模板
audio/templates/    TTS 模板（兜底）
audio/app_templates/小程序真实发音模板（高精度，按需积累）
词汇表.md           实词释义/搭配/拼写提示字母对照
docs/              各题型参考截图
```

## 排错

| 现象 | 处理 |
|---|---|
| `window not found` | 电脑版微信里没打开词达人小程序 |
| `ui.py produced no output` | 没装 Python / 缺 numpy、pillow |
| `no element detected` | 页面在加载或有弹窗 → 重新 `shot`；先关弹窗 |
| 点击无效 | 再点一次；确认 `info` 的 `FG_MATCH=True` |
| 识别序号和看到的不一致 | 以 `shot` 截图为准重新数；必要时 `ui` 再看一次 JSON |
| 音频识别全静音 | 音频没走电脑扬声器（耳机/手机外放） |
