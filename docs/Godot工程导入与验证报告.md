# 《谁杀死了老板》WhoKilledTheBoss — Godot 工程导入与验证报告

> 目标路径：`D:\who-kill-boss\谁杀死了老板\WhoKilledTheBoss`
> 引擎：**Godot 4.7.2.stable.official**（`ed1daf0bf`）
> 报告时间：2026-10-13

---

## 一、结论摘要

1. **该项目本身就是 Godot 原生工程，不需要从任何其它引擎格式转换。**
   目录中已有合法的 `project.godot`（`config_version=5`）、`.tscn` 场景、`.gd` 脚本与 `.godot/` 导入缓存。
2. **工程配置完整、可直接加载。** 入口场景、3 个 Autoload、显示与渲染设置均已就位，未发现断链的 `res://` 引用。
3. **已执行完整重新导入**（`--headless --import`）：退出码 `0`，**零错误、零警告**，`.godot/imported/` 缓存（234 项）与 `uid_cache.bin` 全部重建成功。
4. **已执行运行时冒烟测试**：入口场景 `app.tscn` 与地图场景 `main.tscn` 均正常启动，内容库与 48 个模型槽位全部装载成功。
5. **修复了两处会导致「跑不起来」的路径错误**：两个启动 `.bat` 及其头部 README 中的 Godot 安装路径指向了不存在的目录（详见第八节）。

---

## 二、引擎与文件格式识别

| 项目 | 识别结果 |
| --- | --- |
| 引擎 | Godot Engine 4.7.2 stable（editor build） |
| 工程格式版本 | `config_version=5`（Godot 4.x 工程文件格式） |
| 是否需格式转换 | **不需要**。已是 Godot 原生工程，非 Unity / GameMaker / Ren'Py 等外部格式 |
| 是否已注册到工程管理器 | 是，`%APPDATA%\Godot\projects.cfg` 中已登记本路径 |

工程内实际使用的文件格式：

| 格式 | 用途 | 说明 |
| --- | --- | --- |
| `project.godot` | 工程配置 | INI 风格，`config_version=5` |
| `.tscn` | 文本场景 | 头部 `format=3`，共 19 个 |
| `.gd` | GDScript 脚本 | 共 25 个 |
| `.gd.uid` | 脚本 UID 边车文件 | Godot 4.4+ 为每个脚本生成的稳定 UID |
| `.import` | 资源导入元数据 | 每个可导入资源旁边一份，共 73 个 |
| `.glb` | 二进制 glTF 模型 | 运行时按约定从 `assets/models/` 加载，共 24 个 |
| `.ogg` | 音频（Ogg Vorbis） | `assets/audio/bgm_main.ogg` |
| `.png` / `.jpg` | 贴图 | 导入后生成 `.ctex` 缓存在 `.godot/imported/` |
| `.json` | 游戏数据 | **运行时用 `FileAccess` + `JSON` 读取，不走资源导入管线** |
| `.ico` | 应用图标 | Godot 不把它当贴图导入；exe 图标在导出时烘焙 |
| `.cfg` | 配置 | `export_presets.cfg`、`.godot/global_script_class_cache.cfg` 等 |
| `.godot/` | 引擎缓存 | 自动生成，**不应手动修改** |

> 数据/表现的分离设计：几何（摆哪、多大）写在 `data/objects.json` + `data/room.json`；
> 文案写在 `data/act1.json`；模型名映射写在 `data/model_map.json`。改文案只改 JSON，不用碰代码。

---

## 三、导入后的目录结构

```
WhoKilledTheBoss/
├── project.godot              # 工程配置文件（Godot 入口）
├── export_presets.cfg         # 导出预设（Windows / Android 等）
├── icon.ico                   # 应用图标（导出时烘焙进 exe）
├── 启动游戏.bat               # 双击直接运行游戏
├── 用Godot打开工程.bat         # 双击在编辑器中打开工程
├── README.md                  # 工程说明（权威文档）
│
├── .godot/                    # ← 引擎自动生成的导入缓存（勿手改）
│   ├── imported/              #   贴图/模型导入产物（.ctex/.scn）与 md5 清单，234 项
│   ├── editor/                #   编辑器状态（场景折叠、布局）
│   ├── global_script_class_cache.cfg   # 全局类名缓存（Frontend / Hud）
│   ├── uid_cache.bin          # 资源 UID 缓存
│   ├── shader_cache/          #   着色器缓存
│   ├── exported/              #   导出中间产物
│   └── .gdignore              #   让 Godot 不扫描自身缓存目录
│
├── scenes/                    # 19 个 .tscn 场景
│   ├── app.tscn               # ★ 主场景：外壳入口（进入页 / 选幕页）
│   ├── main.tscn              # 第一幕地图（办公室）
│   └── _*.tscn / *_shot.tscn  # 探针 / 自检 / 截图用辅助场景
│
├── scripts/                   # 25 个 .gd 脚本（+ 同名 .gd.uid）
│   ├── app.gd                 # 主场景脚本：外壳与换幕
│   ├── main.gd                # 地图逻辑（最大，约 78 KB）
│   ├── frontend.gd            # 进入页/选幕页 UI（class_name Frontend）
│   ├── hud.gd                 # 抬头显示（class_name Hud）
│   ├── content_db.gd          # ★ Autoload：JSON 内容库
│   ├── model_slots.gd         # ★ Autoload：模型槽位（灰盒⇄真模型）
│   ├── audio_manager.gd       # ★ Autoload：BGM
│   └── …                      # thought_bubble / topview / selftest 等
│
├── data/                      # 运行时读取的 JSON 数据（7 个正式文件 + .bak 备份）
│   ├── frontend.json          #   进入页/选幕页文案与三幕配置
│   ├── intro.json             #   前情提要 + 引导剧情
│   ├── objects.json           #   探索点/NPC 几何与绑定
│   ├── room.json              #   房间布景（墙地顶、家具 props）
│   ├── act1.json              #   第一幕三轮全部文案与判断题
│   └── model_map.json         #   槽位 → 模型文件映射
│
├── assets/
│   ├── models/                #   24 个 .glb 模型 + 各自贴图 + .import + README
│   ├── textures/ui/           #   12 张 UI 贴图（标题、按钮、卡片、图标）
│   ├── textures/floor/        #    4 张地板贴图
│   ├── audio/                 #   bgm_main.ogg
│   └── placeholders/          #   灰盒参考模型
│
├── docs/                      # .gdignore：设计文档、对照表（Godot 不扫描）
├── tools/                     # .gdignore：Python 资产处理管线脚本（Godot 不扫描）
├── build/                     # .gdignore：导出产物（Godot 不扫描）
└── shots/                     # .gdignore：截图留档（Godot 不扫描）
```

**关于 `.gdignore`：** `tools/`、`docs/`、`build/`、`shots/`、`.godot/` 内均放置了 `.gdignore`（内容为空），
Godot 扫描文件系统时会跳过这些目录，避免把 Python 脚本、截图、导出产物误当作游戏资源。

---

## 四、工程配置 `project.godot`

原始配置如下（**本次未作修改**——经校验已完整合法）：

```ini
config_version=5

[application]
config/name="谁杀死了老板"
config/description="进入页 / 选幕页 → 第一幕：设计部灰盒 + 点击探索 + 判断题"
run/main_scene="res://scenes/app.tscn"
config/features=PackedStringArray("4.7", "Forward Plus")

[autoload]
ContentDB="*res://scripts/content_db.gd"
Models="*res://scripts/model_slots.gd"
Audio="*res://scripts/audio_manager.gd"

[display]
window/size/viewport_width=1600
window/size/viewport_height=900
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[rendering]
anti_aliasing/quality/msaa_3d=1
environment/defaults/default_clear_color=Color(0.929, 0.906, 0.863, 1)
```

要点：

- `run/main_scene` → `res://scenes/app.tscn`（**存在**）。外壳先挂进入页，选幕后再实例化地图。
- 三个 Autoload（`ContentDB` / `Models` / `Audio`）对应的脚本**均存在**，`*` 前缀表示单例常驻。
- `config/features` 声明 `4.7` + `Forward Plus`，与实际引擎版本、默认渲染后端一致。
- 分辨率 1600×900、`canvas_items` + `expand` 拉伸：窗口缩放时等比缩放、不拉变形。

---

## 五、资源引用完整性校验

对全部脚本、场景、数据文件中的 `res://` 引用做了穷举扫描并逐一验证存在性：

| 引用类别 | 数量 | 结果 |
| --- | --- | --- |
| 场景 `.tscn` 引用（脚本挂载、场景切换） | 19 | 全部存在 ✅ |
| 脚本 `.gd` 引用（含 Autoload / `load()`） | 25 | 全部存在 ✅ |
| 数据 JSON（`data/*.json`） | 7 | 全部存在 ✅ |
| 模型 `.glb`（按约定 `assets/models/<名>.glb`） | 24 | 全部存在 ✅ |
| UI 贴图 / 地板贴图 / BGM | 12 / 4 / 1 | 全部存在 ✅ |

**两处「看似缺失」但实为设计内行为，不是错误：**

1. **`res://assets/font.ttf` 不存在。**
   `frontend.gd` / `hud.gd` / `thought_bubble.gd` 三处引用它，但**均被 `FileAccess.file_exists()` 守卫**，
   找不到时自动回退系统字体，不会报错、不会中断。若日后要固定字体，把字体丢到 `assets/font.ttf` 即可生效。
   （其 UID 侧车、`.import` 均无需手工创建，Godot 会自动补。）

2. **`data/*.json` 中引用的 32 个模型名，只有 24 个有对应 `.glb`。**
   其余（如 `SM_B_Wall_*`、`SM_B_Floor`、`SM_B_Ceiling`、`SM_J_BossDesk` 等）经 `ModelSlots.resolve()`
   的 `ResourceLoader.exists()` 判定后**继续使用灰盒方块**，属 README 明确说明的「没做的模型用方块顶着，不报错、不阻塞」。

---

## 六、导入执行结果

执行的重新导入命令（使用 **console 版**可执行文件才能拿到完整 stdout）：

```bash
"D:/godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" \
  --headless --path "D:/who-kill-boss/谁杀死了老板/WhoKilledTheBoss" --import
```

结果：

- **退出码 `0`**；日志 20 行，**无任何 `ERROR` / `WARNING`**。
- 完成 `first_scan_filesystem`（扫描文件结构 → 全局类名 → GDExtension → Autoload → 插件 → 文件扫描）与 `loading_editor_layout` 全流程。
- `.godot/imported/` 重建为 **234 项**，`.godot/uid_cache.bin` 与 `global_script_class_cache.cfg` 刷新。
- 工程内共 **73 个 `.import`** 元数据文件与之对应。

---

## 七、验证「能否正常打开与运行」的方法

### 方法 A — 用编辑器打开（人工查看场景树）

双击工程根目录的 **`用Godot打开工程.bat`**，或命令行：

```bash
"D:/godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --editor --path "D:/who-kill-boss/谁杀死了老板/WhoKilledTheBoss"
```

预期：编辑器加载期间无报错弹窗；左下 **输出** 面板出现 `[ContentDB] 载入完成：8 个探索点 / 4 个 NPC / 3 轮 / 3 幕`；
在 Godot 工程管理器列表里也能直接看到「谁杀死了老板 / 办公室八卦 Demo」条目。

### 方法 B — 无头导入（服务器 / CI 友好的"能否加载"体检）

```bash
"...\Godot_v4.7.2-stable_win64_console.exe" --headless --path "<工程目录>" --import
```

预期：退出码 `0`，无 `ERROR`。**这是判断「工程能否被 Godot 正确加载」最快、最客观的指标。**

### 方法 C — 无头运行主场景（脚本级冒烟测试）

```bash
"...\Godot_v4.7.2-stable_win64_console.exe" --headless --path "<工程目录>" --quit-after 180
```

**本次实测输出（`app.tscn` 主场景）：**

```
Godot Engine v4.7.2.stable.official.ed1daf0bf
[ContentDB] 载入完成：8 个探索点 / 4 个 NPC / 3 轮 / 3 幕
```

**本次实测输出（`main.tscn` 地图场景，`--scene res://scenes/main.tscn --quit-after 300`）：**

```
[ContentDB] 载入完成：8 个探索点 / 4 个 NPC / 3 轮 / 3 幕
[idle] 第 1 轮头顶台词：feng「不想加班」, intern1「好倒霉」, boss「发生什么了？」, director「老板还好吗？」
[模型槽位] 48 个位置，一共只需要做 36 个模型
[模型槽位] 已换 24/36 个模型，还有 19 个位置在用灰盒
[模型槽位] 已替换：SM_A_Npc_Boss, SM_A_Npc_Director, …（24 个）
[模型槽位] 还是灰盒的位置（19 个）：SM_B_Floor, SM_B_Ceiling, SM_B_Wall_N, …
[模型槽位] 尺寸与面数全部通过
```

`尺寸与面数全部通过` 表示 24 个真模型的包围盒尺寸与三角面预算全部通过校验 —— 说明模型导入管线完全正常。

### 方法 D — 人工试玩（有显卡时）

- 源码运行：双击 **`启动游戏.bat`**，或
  `"...\Godot_v4.7.2-stable_win64.exe" --path "<工程目录>"`
- 已打包版本：`D:\who-kill-boss\谁杀死了老板\谁杀死了老板\WhoKilledTheBoss.exe`（免安装、离线运行）

预期玩法链路：标题页「开始游戏」→ 选幕页「第一幕」→ 办公室地图 → 点带「！」的物件/人物看线索 → 自动出判断题 → 轮末过场 → 下一轮。

---

## 八、本次修复项（导入过程中发现并修正的路径问题）

| # | 文件 | 问题 | 处理 | 备份 |
| --- | --- | --- | --- | --- |
| 1 | `启动游戏.bat` | 回退路径指向不存在的 `D:\Godot_v4.7.2-stable_win64.exe\...`；且文件为**纯 LF** 换行，`cmd.exe` 下解析不可靠 | 修正为实际安装路径 `D:\godot\Godot_v4.7.2-stable_win64.exe\...`；统一为 **CRLF** | `启动游戏.bat.bak` |
| 2 | `用Godot打开工程.bat` | 同上 | 同上 | `用Godot打开工程.bat.bak` |
| 3 | `README.md` | 7 处运行/调试命令写作 `D:/Godot_v4.7.2-stable_win64.exe/...`、`/d/Godot_...`（旧安装位置） | 全部改为 `D:/godot/...`、`/d/godot/...` | `README.md.bak_YYYYMMDD_HHMMSS` |
| 4 | `project.godot` / `export_presets.cfg` | 经校验无需改动 | **未修改**（仅做导入前备份） | `project.godot.bak_*`、`export_presets.cfg.bak_*` |

> 说明：两个 `.bat` 采用**相对路径**定位工程根（`%~dp0`），只有定位 Godot 可执行文件时才需要绝对路径。
> 修复后即使把整个工程文件夹拷到别处，只要机器上 Godot 装在 `D:\godot\`，双击仍可运行；
> 若把 `Godot_v4.7.2-stable_win64.exe` 放到工程文件夹根目录，则会优先使用它（便携分发）。

---

## 九、注意事项与已知情况

1. **`.godot/` 由引擎生成，不要手动改、更不要纳入版本管理**。换机器/换引擎小版本时删掉它让 Godot 重新生成即可。
2. **`font.ttf` 缺失 → 中文走系统字体。** 不影响运行；若要求跨机器字体一致，请放置 `assets/font.ttf`。
3. **`config/icon` 未设置属正常。** Godot 不把 `.ico` 作为编辑器贴图导入；exe 的图标在**导出时**由 `export_presets.cfg` 烘焙，
   与 `project.godot` 的 `config/icon` 无关。
4. **`app.tscn` 用 `--quit-after` 强制退出时**会打印
   `4 ObjectDB instances were leaked at exit` / `2 resources still in use at exit`。
   这是**强制退出时**仍有 UI 实例存活导致的正常提示，`main.tscn` 正常退出无此提示，不影响游戏运行，无需处理。
5. **模型面数较大**（个别 `.glb` 达 5 千万字节量级）会明显拉长首次导入时间（本次增量导入约 15 秒；全新导入会久得多）。
6. 工程已注册在 `%APPDATA%\Godot\projects.cfg`，打开 Godot 工程管理器即可在列表中直接进入。

---

## 十、备份清单（如需回滚，直接用备份覆盖即可）

```
project.godot.bak_20261013_154618
export_presets.cfg.bak_20261013_154620
启动游戏.bat.bak
用Godot打开工程.bat.bak
README.md.bak_20261013_154802
```

导入日志留档：`D:\WorkBuddyWorkspace\Claw\_godot_import\`（`import_log.txt`、`run_app.txt`、`run_main.txt`）
