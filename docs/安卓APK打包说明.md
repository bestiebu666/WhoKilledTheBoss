# 安卓 APK 打包说明

**工程路径**：`D:\who-kill-boss\谁杀死了老板\WhoKilledTheBoss`
**引擎版本**：Godot 4.7.2 stable
**本次产物**：`谁杀死了老板-安卓版-v1.2.apk`（638,785,995 字节 ≈ 609 MiB）
**构建日期**：2026-10-16

---

## 一、工具链（Toolchain）

| 组件 | 版本 / 路径 | 是否必需 | 说明 |
|---|---|---|---|
| Godot 引擎 | 4.7.2 stable<br>`D:\godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` | 必需 | **必须用 `_console.exe`** 版本，普通 exe 在命令行下拿不到 stdout 日志 |
| Godot 导出模板 | `4.7.2.stable`<br>`C:\Users\a\AppData\Roaming\Godot\export_templates\4.7.2.stable\android_release.apk` | 必需 | 缺模板会报「缺少导出模板」。版本必须与引擎**完全一致** |
| JDK | 17<br>`D:\android-tools\jdk17` | 必需 | Godot 用它调 `apksigner` 签名；JDK 17 兼容性最好 |
| Android SDK Build-Tools | 34.0.0<br>`C:\Users\a\AppData\Local\Android\Sdk\build-tools\34.0.0` | 必需 | 提供 `apksigner` / `zipalign` / `aapt2` |
| Android SDK Platform | android-34<br>`…\Sdk\platforms\android-34` | 必需 | 提供 `android.jar` 供编译期引用 |
| Android Platform-Tools | 37.0.1<br>`…\Sdk\platform-tools\adb.exe` | 测试用 | 安装、启动、抓日志、截图 |
| Android 模拟器 | `…\Sdk\emulator\emulator.exe`，AVD `WKTB_Tablet` | 测试用 | Android 14 / x86_64 / 2560×1600 |
| 发布签名密钥库 | `…\WhoKilledTheBoss\build\release.keystore` | 必需 | RSA 2048，别名 `whokilledtheboss` |

> 打包机需在 Godot 的「编辑器设置 → 导出 → Android」里配置好 **Android SDK 路径** 与 **JDK 路径**；
> 本工程另有两点是**按项目**配置的：本机 `export_presets.cfg` 中直接写了 keystore 绝对路径，`project.godot` 中写入了渲染后端与纹理格式。仓库不上传含签名信息的本机预设；请复制 `export_presets.example.cfg` 为 `export_presets.cfg`，再填写自己的密钥库路径、别名和口令。

---

## 二、打包命令

在工程根目录执行（Git Bash 写法）：

```bash
cd "/d/who-kill-boss/谁杀死了老板/WhoKilledTheBoss"

"/d/godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" \
  --headless --path . --export-release "Android" "build/android/谁杀死了老板-v1.2.apk"
```

Windows `cmd` 写法：

```bat
cd /d "D:\who-kill-boss\谁杀死了老板\WhoKilledTheBoss"
"D:\godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" ^
  --headless --path . --export-release "Android" "build/android/谁杀死了老板-v1.2.apk"
```

**参数说明**

- `--headless` —— 无窗口运行，适合 CI / 命令行。导出功能在 headless 下完全可用。
- `--path .` —— 指定工程目录（当前目录）。
- `--export-release "Android"` —— 使用名为 **Android** 的导出预设（即 `export_presets.cfg` 里的 `[preset.1]`），发布模式。调试包对应 `--export-debug`。
- 最后一项 —— **输出路径**，会覆盖预设里写的 `export_path`。省略则输出到预设默认位置。
- 构建耗时实测约 **40 秒**（打包 + 对齐 + 签名 + 校验）。

命令行会实时打印进度（`正在添加文件… / 正在对齐 APK… / 正在签名发布 APK… / 正在校验 APK…`），最后出现 `[ DONE ] export` 即成功。

> 若手工重跑后发现 `export_presets.cfg` 被截成 0 字节或预设「消失」，几乎一定是**磁盘写满**——导出前先确认剩余空间（本次构建时 D 盘剩余 173 GB）。

---

## 三、需配置的参数

参数分两处：`project.godot`（引擎级）与 `export_presets.cfg`（导出级）。

### 3.1 应用身份

| 参数 | 配置键 | 当前值 |
|---|---|---|
| 应用名称（桌面显示名） | `project.godot` → `application/config/name` | `谁杀死了老板` |
| 应用名称（安卓标签名） | `export_presets.cfg` → `package/name` | `谁杀死了老板` |
| 包名（唯一标识） | `package/unique_name` | `com.whokilledtheboss.game` |
| 版本名 | `version/name` | `1.2` |
| 版本号（整数，覆盖安装须递增） | `version/code` | `3` |

> 包名一旦发布**不可更改**（改了就是另一个应用，用户需重新安装）。版本号用于覆盖安装判断，**每次出新包必须递增**。

### 3.2 图标

| 参数 | 配置键 | 当前值 |
|---|---|---|
| 主图标 192×192 | `launcher_icons/main_192x192` | `res://assets/android/icon_main.png` |
| 自适应前景 432×432 | `launcher_icons/adaptive_foreground_432x432` | `res://assets/android/icon_fg.png` |
| 自适应背景 432×432 | `launcher_icons/adaptive_background_432x432` | `res://assets/android/icon_bg.png` |
| 单色（主题图标） | `launcher_icons/adaptive_monochrome_432x432` | **留空**（见第七节坑 4） |

### 3.3 屏幕与显示

| 参数 | 配置键 | 当前值 | 说明 |
|---|---|---|---|
| 屏幕方向 | `project.godot` → `display/window/handheld/orientation` | `0` | `0` = 横屏锁定（本作 1600×900，必须横屏）|
| 基准分辨率 | `display/window/size/viewport_width/height` | 1600 × 900 | |
| 拉伸模式 | `window/stretch/mode` | `canvas_items` | |
| 拉伸比例 | `window/stretch/aspect` | `expand` | 宽屏按比例扩展可视区，不裁切 |
| 沉浸式全屏 | `screen/immersive_mode` | `true` | 隐藏系统栏 |
| 支持屏幕尺寸 | `screen/support_small/normal/large/xlarge` | 全 `true` | |

> 屏幕方向的可选值：`0` 横屏、`1` 竖屏、`2` 反向横屏、`3` 反向竖屏、`4` 传感器横屏、`5` 传感器竖屏、`6` 跟随传感器。

### 3.4 系统版本与架构

| 参数 | 配置键 | 当前值 | 说明 |
|---|---|---|---|
| 最低安卓版本 | `gradle_build/min_sdk` | 空 → **默认 API 24（Android 7.0）** | 留空即用引擎默认。填数字可抬高门槛 |
| 目标安卓版本 | `gradle_build/target_sdk` | 空 → **默认 API 36（Android 16）** | 留空即用引擎默认 |
| CPU 架构 | `architectures/arm64-v8a` | `true`（仅此项开启） | 只出 arm64，**可省约 72 MB** |
| | `architectures/armeabi-v7a` / `x86` / `x86_64` | `false` | 现代设备不需要 |

### 3.5 渲染与资源（安卓适配关键项，均在 `project.godot`）

| 参数 | 当前值 | 为什么必须这么设 |
|---|---|---|
| `renderer/rendering_method.mobile` | `gl_compatibility` | 安卓只有 Vulkan(`mobile`) 与 GLES3(`gl_compatibility`) 两条路；`gl_compatibility` 兼容性最好。**只改 `.mobile`**，桌面端仍走 Forward+，`glow` 等效果不丢 |
| `textures/vram_compression/import_etc2_astc` | `true` | 默认烘焙的是桌面专用 DXT/S3TC，**安卓 GPU 采样不了**；开启后每张贴图同时产出 ETC2 变体 |

### 3.6 签名

| 参数 | 配置键 | 当前值 |
|---|---|---|
| 启用签名 | `package/signed` | `true` |
| 密钥库 | `keystore/release` | `…\WhoKilledTheBoss\build\release.keystore` |
| 别名 / 口令 | `keystore/release_user` / `keystore/release_password` | 仅写入本机私有 `export_presets.cfg`，不得提交 |

> **同一把密钥库**签出的包可**直接覆盖安装**、免卸载；换密钥库则必须卸载重装。

### 3.7 权限

`export_presets.cfg` 中约 240 项 `permissions/*`，本作**只开了 3 项**：`internet`、`access_network_state`、`get_accounts`（引擎默认）。
游戏完全离线可玩，未申请相机、存储、定位等敏感权限。

---

## 四、构建产物

| 产物 | 路径 | 大小 |
|---|---|---|
| 导出原始包 | `WhoKilledTheBoss\build\android\谁杀死了老板-v1.2.apk` | 638,785,995 字节 |
| 只读签名数据 | `…\build\android\谁杀死了老板-v1.2.apk.idsig` | 5,039,649 字节 |
| **交付副本** | `谁杀死了老板\安卓版\谁杀死了老板-安卓版-v1.2.apk` | 同上 |
| 实测截图 | `谁杀死了老板\安卓版\模拟器实测-v1.2\` | 8 张 PNG |

**SHA-256**（交付副本）

```
d8591f937d5197423d0f546ac42a921f31599fe56133d5ebcb7dee59b86c8710
```

`.idsig` 是 Android v4 签名方案的旁挂文件，仅供 `adb install --incremental` 使用，**分发时无须带上**。

### 校验命令

```bash
SDK="/c/Users/a/AppData/Local/Android/Sdk"

# 1) 签名校验（Git Bash 下直接调 apksigner.bat 拿不到输出，必须走 java -jar）
"/d/android-tools/jdk17/bin/java.exe" -jar "$SDK/build-tools/34.0.0/lib/apksigner.jar" \
  verify --verbose --print-certs "安卓版/谁杀死了老板-安卓版-v1.2.apk"

# 2) 清单校验（包名 / 版本 / ABI / minSdk / 图标 / 屏幕方向）
"$SDK/build-tools/34.0.0/aapt2.exe" dump badging "安卓版/谁杀死了老板-安卓版-v1.2.apk"

# 3) 哈希校验
sha256sum "安卓版/谁杀死了老板-安卓版-v1.2.apk"
```

本次实测结果：

- 签名：`v2 scheme = true`、`v3 scheme = true`；证书 `CN=WhoKilledTheBoss`，SHA-256 `739a17e8…`
- 清单：`package=com.whokilledtheboss.game`、`versionCode=3`、`versionName=1.2`、`native-code=arm64-v8a`、`sdkVersion=24`、`targetSdkVersion=36`
- `screenOrientation=0`（横屏）

---

## 五、在安卓设备上安装与测试

### 5.1 真机（玩家侧，最简单）

1. 把 `谁杀死了老板-安卓版-v1.2.apk` 传到平板（微信/QQ 传文件、数据线、U 盘、网盘均可）
2. 用平板「文件管理」找到该文件，点击安装
3. 若提示「禁止安装未知来源应用」→ 点「设置」→ 允许来自此来源 → 返回继续安装
4. 桌面出现「谁杀死了老板」图标，点开即玩

因为与上一版**同一签名**，可直接覆盖安装，不必先卸载。

### 5.2 命令行（开发者侧，本机已实测）

```bash
SDK="/c/Users/a/AppData/Local/Android/Sdk"
ADB="$SDK/platform-tools/adb.exe"

# ① 启动模拟器（-no-snapshot 冷启动；不要用 -no-snapshot-save，会卡死 qemu）
cd "$SDK/emulator" && ./emulator.exe -avd WKTB_Tablet -no-snapshot -no-boot-anim -port 5554 &

# ② 等待开机完成
"$ADB" wait-for-device
"$ADB" shell getprop sys.boot_completed        # 返回 1 即已开机

# ③ 安装（路径含中文时加 MSYS_NO_PATHCONV=1，且用正斜杠盘符路径）
MSYS_NO_PATHCONV=1 "$ADB" install -r \
  "D:/who-kill-boss/谁杀死了老板/安卓版/谁杀死了老板-安卓版-v1.2.apk"

# ④ 确认版本
"$ADB" shell dumpsys package com.whokilledtheboss.game | grep -i version

# ⑤ 启动并抓日志
"$ADB" logcat -c
"$ADB" shell monkey -p com.whokilledtheboss.game -c android.intent.category.LAUNCHER 1
"$ADB" logcat -d | grep -iE "godot|FATAL|AndroidRuntime"

# ⑥ 截图
"$ADB" exec-out screencap -p > shot.png
```

**本次实测结论**（Android 14 模拟器 / 2560×1600 / arm64 包经该镜像 ARM 转译运行）：

- 覆盖安装 1.1 → 1.2 成功，耗时约 25 秒；`versionCode=3 / versionName=1.2`
- 引擎日志：`Godot Engine v4.7.2.stable`、`renderingDevice: opengl3`、`renderer: gl_compatibility`
- `[ContentDB] 载入完成：8 个探索点 / 4 个 NPC / 3 轮 / 3 幕`
- 全链路通过：标题页 → 选幕页 → 第一幕 3D 场景 → 点感叹号拾取线索（进度 1/14）
  → 右上角「回顾 ▼」→ 第 1 轮 → 点结论 → 弹出当时线索卡
- **零 `E godot` 报错、零 `SCRIPT ERROR`、零 `FATAL`**
  （仅有一条无害警告 `Failed to load cached shader, recompiling`——首启编译器缓存为空，属正常现象）

---

## 六、一键脚本（可选）

如需反复出包，可在工程根目录放一个 `打包安卓.bat`（**必须 CRLF 换行 + GBK 编码**，用 UTF-8 或 LF 会导致 `cmd.exe` 解析异常）：

```bat
@echo off
chcp 936 >nul
cd /d "%~dp0"
set GODOT="D:\godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
%GODOT% --headless --path . --export-release "Android" "build\android\谁杀死了老板.apk"
pause
```

注意：命令行输出路径会**覆盖**预设里的 `export_path`，脚本里请写你真正想要的位置。

---

## 七、本工程专属的坑（实测记录）

1. **必须用 console 版 Godot**：普通 exe 从命令行启动后 stdout 不回流，出错时只能干瞪眼。
2. **字体必须「内置 + ResourceLoader 加载」**：导出后 `.ttf` 被当作「已导入字体」，裸文件**不进包**（加 `include_filter` 也无效）。代码须写成
   `if ResourceLoader.exists(p): load(p) elif FileAccess.file_exists(p): FontFile.load_dynamic_font(p)`。
   本作已内置 Noto Sans SC（OFL 授权，可随包分发）；微软雅黑/黑体版权受限，**不可**打包。
3. **贴图必须重烘成 ETC2**：改完 `import_etc2_astc` 后要 **touch 所有 png/jpg 强制重导入**——该全局开关不在 `.import` 的选项哈希里，不改文件等于没改。
   ⚠ 但**千万别 touch `.glb`**，否则会重建成上百 MB 的 `.scn`。
4. **不要填单色启动图标**：Godot 4.7.2 的安卓模板会 `replacing with themed_icon.xml data`，把彩色自适应图标的 `icon.xml` 覆盖成单色。所以 `adaptive_monochrome_432x432` 保持留空。
   （构建日志里的 `mipmap/themed_icon … no such path exists` 是模板自带警告，无害。）
5. **build-tools 版本警告可忽略**：`Could not find version of build tools that matches Target SDK, using 34.0.0`——目标 SDK 36 但本机只装了 34.0.0 的构建工具，签名照常成功。
6. **导出前查磁盘**：磁盘写满会把 `export_presets.cfg` 静默截断为 0 字节，表现为「预设突然消失」。
7. **包体偏大**（609 MiB）：主因是 3D 模型面数过高（部分单个道具 50 万～150 万三角面，常规移动端道具为 1 千～2 万）。作者当前要求**不减面**；
   如需瘦身，可在 Blender 内做保守减面（预计可降至 60～120 MB），须先出对比图确认不崩面再替换。

---

*文档生成于 2026-10-16，对应构建 v1.2（versionCode 3）。*
