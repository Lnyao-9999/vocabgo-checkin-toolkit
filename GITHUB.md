# 上传到 GitHub（3 分钟）

仓库已经整理好，直接推即可。

## 1. 在 GitHub 新建仓库
网页 → New repository → 名字建议 `vocabgo-checkin-toolkit` → **不要**勾选 Add README/LICENSE（本地已有）→ Create。

## 2. 本地初始化并推送

```powershell
cd "A:\deepseek work area\vocabgo-checkin-toolkit"

git init
git add .
git commit -m "feat: 词达人打卡自动化工具包（PC微信小程序 / 手机投屏 + 离线音频识别）"

# 把 <你的账号> 换成 GitHub 用户名
git remote add origin https://github.com/<你的账号>/vocabgo-checkin-toolkit.git
git branch -M main
git push -u origin main
```

如果这台机器没装 git：`winget install --id Git.Git -e`（或到 git-scm.com 下载）。

## 3. 建议补充（可选）
- Settings → About：填 "Windows + PowerShell + 离线音频识别，自动完成词达人打卡"
- Topics: `automation` `powershell` `wechat-miniprogram` `vocabgo` `agent` `dsh-skill`
- Issues 里说明：只支持 Windows；UI 改版会失效；仅供学习研究

## 4. 作为 DSH 技能安装（别人怎么用）

```powershell
git clone https://github.com/<你的账号>/vocabgo-checkin-toolkit.git
cd vocabgo-checkin-toolkit
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

装完在 DSH 里说「用 vocabgo-daily-checkin 技能帮我打卡」即可。
