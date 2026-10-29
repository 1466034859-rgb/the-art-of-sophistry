# 分发给别人玩 & 收集日志/反馈

本文回答两件事：**怎么把游戏发出去**、**怎么把别人的报错和反馈收回来**。

---

## 一、三种分发方式

### 方式 A：发工程 zip（最简单，现在就能用）

在本机运行：

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\make_share_zip.ps1
```

会生成 `dist\Sophistry-playtest.zip`（已排除缓存、日志、截图和调试脚本）。对方：

1. 解压；
2. 安装 Godot 4.7（https://godotengine.org/download/）；
3. 双击 `run_game.bat`（或打开 `project.godot` 按 F5）。

缺点：对方必须装 Godot。适合发给愿意折腾的朋友。

### 方式 B：导出 Windows exe（推荐，但本机做不了）

本机没有 4.7 export templates，且证书链异常无法自动下载。做法：

1. 在一台能正常联网的机器上安装 Godot 4.7；
2. 打开 Godot → 编辑器 → 管理导出模板 → 下载并安装 4.7 模板；
3. 把本工程拷过去，运行 `tools\build_windows.ps1`；
4. 产物在 `build\Sophistry.exe`，把 `build` 文件夹压缩发给别人即可，对方双击就能玩。

### 方式 C：Web 版（itch.io）

同样需要 export templates。在 Godot 里装模板后，导出 Web 预设，把 `index.html` 等文件上传 itch.io。
适合“点开链接就能玩”的场景。

---

## 二、对方遇到问题时怎么把日志发回来

游戏里已经内置了完整链路，**不需要教对方找 AppData**：

1. 游戏内点 **主菜单「反馈 / 诊断包」** 或 **故事页顶栏「反馈」**；
2. 选类型、写一句“在哪一步、发生了什么”，可留联系方式；
3. 点「保存反馈（含日志/截图）」；
4. 面板会显示一个**本地文件夹路径**，例如：

   ```
   C:\Users\<玩家>\AppData\Roaming\Godot\app_userdata\诡辩之术\feedback\20260614_213015_xxxx
   ```

5. 让对方把这个文件夹整个压缩发给你。

文件夹里有：

| 文件 | 内容 |
| --- | --- |
| `feedback.json` | 反馈正文、类型、联系方式、系统信息、最近 80 条游戏事件 |
| `session.log` | 本次会话日志（含引擎报错，由 `OS.add_logger` 捕获） |
| `screenshot.png` | 玩家点保存时的画面 |
| `如何反馈.txt` | 给玩家看的说明 |

玩家也可以点「打开反馈文件夹」直接打开目录。游戏运行期间，日志会持续写到：

```
%APPDATA%\Godot\app_userdata\诡辩之术\logs\session_*.log
```

### 内置的调试信息（让玩家帮你定位）

- 游戏内按 **F3**：显示 FPS、当前场景、日志路径、最近 10 条事件（选了什么、结算结果）。
- 选错分支、空选项等异常会自动写进日志；如果真出现空选项，界面会给「跳过异常步骤」按钮，保证卡不死。

---

## 三、想自动收集？配置 webhook

打开 `data/distribution.json`：

```json
{
  "version": "0.6-playtest",
  "webhook_url": "https://your-server.example.com/feedback",
  "feedback_form_url": "https://your-survey-link"
}
```

- 填了 `webhook_url` 后，玩家点「保存反馈」会**自动 POST** 一份 JSON（就是 `feedback.json` 的内容）到你的地址；
  本地仍然会保存一份，网络失败也不丢。
- `feedback_form_url` 填在线问卷链接后，反馈面板会出现「在线问卷」按钮。
- 接收端只需要一个能存 POST JSON 的接口；不想写服务的话，可以用飞书/钉钉机器人，
  但它们的消息格式不同，建议自建一个轻量中转（或直接用调查问卷）。

> 隐私：只收集玩家手写的内容、系统信息（OS/Godot 版本/分辨率）、游戏事件、反馈时截图，
> 不采集账号、聊天记录或文件。联系方式是选填。发布前建议在说明里写一句。

---

## 四、发布前检查清单

1. 改版本号：`data/distribution.json` 的 `version`（会写进日志和反馈）。
2. 跑一遍：`powershell -File tools\dev.ps1 all`（全绿再发）。
3. 自己走一遍反馈流程：保存反馈 → 打开文件夹 → 确认四个文件都在。
4. 打包：`powershell -File tools\make_share_zip.ps1`。
5. 发给 1–2 个朋友先试，让他们**卡住就点反馈**，把文件夹发回来。
6. 收到反馈后：`session.log` 看报错，`feedback.json` 的 `events` 看玩家走到了哪一步。
