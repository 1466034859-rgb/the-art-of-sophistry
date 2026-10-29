# 交付清单（《诡辩之术》 v0.5 试玩版）

## 一、交付物

目标目录：`E:\Mind\the-sound`（与开发目录 `C:\Users\14660\qq-bridge\state\slang-agent\sophistry` 内容一致）

| 内容 | 位置 |
| --- | --- |
| 可直接启动的游戏工程 | `project.godot` + `scenes/` + `core/` + `ui/` + `data/` |
| 双击启动 | `run_game.bat`（自动寻找本机 Godot 4.7） |
| 四场故事数据 | `data/stories.json` |
| Windows 导出预设与脚本 | `export_presets.cfg`、`tools/build_windows.ps1` |
| 自动化测试 | `tests/`，入口 `tools/dev.ps1` |
| 分发与反馈系统 | `autoload/feedback.gd`、`ui/feedback_panel.gd`、`docs/DISTRIBUTION.md`、`tools/make_share_zip.ps1` |
| 调研底稿（游戏设计 / 文案 / 剧情推进） | `docs/research-notes.md` |
| QA 报告 | `docs/qa-report.md` |
| 自动截图 | `screenshots/` |

## 二、怎么开玩

1. 双击 `run_game.bat`（需要本机装有 Godot 4.7；找不到会提示）。
2. 或打开 Godot 4.7 → 导入 `project.godot` → F5。
3. 主菜单 → 「故事模式 · 四场辩论」→ 选一场。

操作：空格/回车继续、数字键 1-9 选择、Esc 暂停；顶栏可开「对白记录」、开关音效。

## 三、验收对照（目标逐项）

| 目标 | 状态 | 证据 |
| --- | --- | --- |
| 观众倾向条中分双半（左你 / 右对方） | ✅ | `ui/tug_bar.gd`；故事屏右侧「总倾向 + 三组观众」均为中分双半；截图 `screenshots/12_find_flaw.png` |
| 四场辩论全部可玩、零死路 | ✅ | `data/stories.json` 四场；`dev.ps1 story` 890 项通过；200 局随机乱点全部抵达复盘 |
| UI/UX、像素风、可读性 | ✅ | 键盘操作、结构视图、对白记录、逐票揭晓、复盘时间线、Esc 暂停、像素描边标题、程序化音效 |
| 文案去 AI 味 | ✅（持续打磨） | 三遍修订：对仗式笔记改具体事实、补可观察细节、删角色自报谬误名的教师腔；规则见 `docs/research-notes.md` §3/§5 |
| 自动化测试 + 可玩性复核 | ✅ | `dev.ps1 all` 全绿（1402 + 890 + 22 + 9 + UI + boot）；阅读量统计见 `docs/qa-report.md` |
| README / 构建脚本 / 可直接开玩 | ✅ | README「0. 快速开玩」；`run_game.bat`；导出脚本就绪 |

## 四、测试矩阵（最近一次全量）

```
dev.ps1 test         1402 项  卡牌机制 / 数据 / 128 局 AI 对局
dev.ps1 story         890 项  四场 × 正确/全错/补救/隐忍 + 200 局随机乱点
dev.ps1 story-ui       22 项  四场 UI 全链路代打（真实按钮回调 + 暂停开合）
dev.ps1 story-wrong    48 项  错误分支 UI 回归（全错路径，选择页必须非空）
dev.ps1 feedback       14 项  反馈/日志/诊断（引擎报错捕获、反馈文件、面板）
dev.ps1 sfx             9 项  程序化音效流与开关
dev.ps1 ui          RESULT PASS  卡牌模式 UI 冒烟
dev.ps1 boot        RESULT PASS  启动 120 帧无脚本错误
dev.ps1 capture-story   PASS    10 张关键节点截图
```

## 五、已知限制

1. **没有打包出 exe**：本机未安装 Godot 4.7 export templates，且本机证书链异常
   （TLS 连接直接失败），无法自动下载模板。导出脚本与预设已就绪，
   在装有模板的机器上运行 `tools/build_windows.ps1` 即可产出 `build/Sophistry.exe`。
   当前交付以「装 Godot 4.7 + 双击 run_game.bat」为开玩方式。
2. **中文像素字体未替换**：本机无任何中文像素字体，强行换会糊；正文用系统 CJK 字体，
   标题用描边 + 投影模拟像素轮廓。以后可引入 Zpix / Fusion Pixel 等字体。
3. **单场约 4–5 分钟**：作为「一场完整辩论」偏短；若要做 12–18 分钟，需要加第 4 回合
   或「自由辩论」加时段（数据驱动，不用改引擎）。
4. **暂停不写存档**：暂停/退出会丢失本场进度；没有设置界面与音量滑条（只有音效开关）。
5. **没有真人试玩数据**：可玩性复核为自动化 + 截图人工检视 + 静态阅读量估算，
   真实玩家反馈仍需外部测试。

## 六、后续建议（按性价比排序）

1. 装好 export templates，产出 Windows exe（10 分钟）。
2. 加「自由辩论」把单场拉到 8–10 分钟（数据 + 一个小阶段）。
3. 抓矛盾机制（让文本历史进入策略）与复盘时间线联动。
4. 中文像素字体 + 简单转场 / 立绘剪影。
5. 设置界面（音量、文字速度、难度）与自动存档。
