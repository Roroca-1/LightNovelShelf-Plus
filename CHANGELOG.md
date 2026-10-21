# 更新日志

本文件记录轻书架Plus 每个版本的变化，按时间倒序排列。发布 CI 会把与 tag 对应的版本段落自动取作 GitHub Release 正文，因此每个版本必须以 `## V<版本>-Plus` 这样的二级标题开头，标题文字与 tag 完全一致。

## V1.13.2-Plus

> 对应上游 v1.13.2；Plus 版本号 `1.13.2+26`，关于页显示为 `1.13.2-Plus (26)`。

本次是 Plus 首次与上游 v1.13.2 完整合并的版本：一是把应用内更新器收敛成一套引擎，二是把 Plus 的发布流水线在上游新结构上重建，三是从上游带来了人机验证、平板布局与构建工具链的升级。

### 一、上游同步（v1.13.0 → v1.13.2）

- **注册加人机验证**：注册页在发送验证码前要求通过 Cloudflare Turnstile，并新增网页注册入口。（上游 `c214fb1`，v1.13.0）
- **重置密码同样验人机**：重置密码流程也接入 Turnstile，并按场景区分 Turnstile action，避免不同场景 token 混用；同时把 `inappwebview` 升级到兼容 AGP 9 的 beta 版本。（上游 `b978cb1`，v1.13.1）
- **构建工具链整体升级**：AGP 9.2.1、Gradle 9.4.1、`compileSdk 37`、NDK r30、Flutter 3.47.7，并同步升级依赖版本。（上游 `c37f6dd`）
- **CI 缓存**：为 Gradle、pub、CocoaPods 增加缓存，并开启 Gradle 构建缓存，缩短构建时间。（上游 `d64e5e9`）
- **搜索页**：移除搜索页的页码提示，简化搜索结果展示。（上游 `1dfc7fb`，Closes #24）
- **平板布局**：平板尺寸下改用 `NavigationRail` 加左右分栏，阅读器默认双页；设置页新增「重置所有设置」入口。（上游 `02c8ef0`，Closes #23）
- **我的道具**：按道具的 `usable` 属性决定是否显示「使用」按钮，不可用的道具不再出现误触入口。（上游 `f5873cd`）
- **改名卡**：补充改名卡的使用入口。（上游 `b6d8941`）
- **应用内自动更新**：上游新增自动更新引擎（`lib/data/app_update.dart`、`lib/features/update/app_updater.dart`、`lib/core/platform/android_app_installer.dart`），启动时检查新版本，Android 上可直接下载校验并安装。（上游 `6105cef`，v1.13.2）

### 二、Plus 保留与强化

上游合并没有削弱 Plus 既有能力，下列 Plus 侧特性全部保留（来源：Plus 侧 `lib/features/**`、`README.md`）：

- 书架「单本 / 系列」显示与「网格 / 列表」显示及记忆选择；系列内多选、全选与批量移出书架。
- 书架排序为纯显示排序（手动顺序 / 标题 / 最近更新 / 最近加入），中文优先按拼音、检测到假名时用罗马字，不改动服务端顺序。
- 桌面端宽屏布局、右键快捷菜单（直接阅读、搜索系列、加入 / 移出书架、多选）与键盘焦点浏览。
- 自定义 Material 3 主题色、系统动态配色、OLED 纯黑模式，以及可分别设置的应用背景与阅读背景（含亮度、模糊、Material You 取色）。
- 短 TTL（15 分钟）缓存直读：命中缓存立即渲染，过期后再拉取；配合封面与漫画预加载优化，以及设置页的清除全部 / 图片 / 字体缓存入口。
- 自动签到，以及设置页的「检查更新」入口、`autoCheckUpdate` 开关与忽略版本持久化（`app_update_ignored_version`）。
- 应用标识保持 `app.lightnovel.shelf.plus`，可与官方版轻书架同时安装。

### 三、冲突裁决与实现选择

- **更新器只留一套引擎**：采用上游的 `lib/data/app_update.dart` + `lib/features/update/app_updater.dart` + `lib/core/platform/android_app_installer.dart`，删除 Plus 旧的 `lib/data/repositories/app_update_repository.dart`。原因：上游实现自带 sha256 校验与平台安装器，能力比 Plus 的「跳发布页」更完整，两套并存会出现启动时弹两个框。
- **发布源与资产匹配改成 Plus**：`_latestReleaseUrl` 指向 `Roroca-1/LightNovelShelf-Plus/releases/latest`；资产匹配由上游的 `app-android-<abi>.apk` 改为后缀匹配，命中 Plus 历史产物名 `LightNovelShelfPlus-<ARTIFACT_TAG>-arm64-v8a.apk`。原因：产物命名是 Plus 已有的发布习惯，改命名会孤立历史版本。
- **版本号归一化**：新版本标签形如 `V1.13.2-Plus`、`V1.12.3-Plus.1`，上游只摘小写 `v`，会把大写 `V` 和 `-Plus` 后缀带进版本比较。现统一为「去前导 v/V → 截断到第一个 `-` 得到 `主.次.修订` → 逐段比较数字」，并把 `-Plus` 后紧跟的重发序号当作第四段数字参与比较：`V1.13.2-Plus` = `[1,13,2,0]`、`V1.13.2-Plus.1` = `[1,13,2,1]`、裸 `1.13.2` = `[1,13,2,0]`，`+构建号`（如 `+26`）仍不参与比较。忽略记录保存的是带序号的版本身份（如 `1.13.2-Plus.1`），所以「忽略 `1.13.2`」不会连带吞掉它的重发包。当前版本取 `PackageInfo`，缺失时回退编译期注入的 `APP_RELEASE_TAG`。
- **没有摘要就降级**：上游只有在资产带 `digest`（sha256）时才自动安装。Plus 的历史 Release 资产可能没有该字段，此时不报错、不装错包，直接打开 Release 页让用户手动下载。
- **平台并集不退化**：Android 走「下载 → 校验 → 安装」，iOS 打开 Release 页，桌面（Linux / Windows / macOS）也打开 Release 页；启动检查只执行一次、只弹一个对话框，网络失败（403、限流、超时、无网）静默处理，只在调试日志留痕。
- **关于页版本串保留 Plus 标识**：由 `pubspec.yaml` 的 `version: 1.13.2+26` 生成 `1.13.2-Plus (26)`，不采用上游的裸版本号，便于用户区分官方版与 Plus。
- **Kotlin 包名对齐 Gradle namespace**：`android/app/src/main/kotlin/.../AppUpdateFileProvider.kt` 原先声明 `package app.lightnovel.shelf`，而 `namespace` / `applicationId` 都是 `app.lightnovel.shelf.plus`；`AndroidManifest.xml` 里的相对类名 `.AppUpdateFileProvider` 会按 namespace 解析到不存在的类，ContentProvider 又在 `Application.onCreate` 之前实例化，导致 Android 每次启动必崩。现已移入 `.../shelf/plus/` 并把包声明改为 `app.lightnovel.shelf.plus`，同时由 `ci.yml` 断言每个 Kotlin 文件的包名必须等于 `build.gradle.kts` 的 namespace。原因是这类跨语言接线错误编译期发现不了，只能靠 CI 兜住。
- **Release 正文改用手写日志**：上游用 `generate_release_notes` 自动生成，Plus 改从本文件抽取对应版本段落，避免自动说明与手写日志重复；`fail_on_unmatched_files` 保留，产物缺失仍然让发布失败。

### 四、构建与发布

- **触发**：`release.yml` 监听 `v*` 与 `V*` 标签，同时保留 `workflow_dispatch`（输入 `tag` 与 `publish` 开关）。
- **工具链一致**：`ci.yml`、`release.yml`、`build-android.yml`、`build-ios.yml` 的 Flutter 版本统一为 3.47.7。
- **发布标识注入**：release 的 android / linux / windows / ios 四个作业都传 `--dart-define=APP_RELEASE_TAG=$RELEASE_TAG`；CI 用 `ci-<run_number>`，让下拉构建也能验证这条通路。
- **产物命名**：`LightNovelShelfPlus-<ARTIFACT_TAG>-arm64-v8a.apk`、`-x86_64.AppImage`、`-x86_64.deb`、`-x86_64.pkg.tar.zst`、`-x86_64-setup.exe`、`-ios-unsigned.ipa`；`ARTIFACT_TAG` 由 tag 安全化而来，保留 ASCII 字符。
- **签名与校验**：Android 要求仓库持久签名密钥存在，否则直接失败（不再退回调试签名）；构建后用 `aapt` 校验包名必须为 `app.lightnovel.shelf.plus`，iOS 用 `PlistBuddy` 校验 `CFBundleIdentifier` 一致。
- **发布正文**：publish 作业检出 tag、从 `CHANGELOG.md` 抽取 `## <RELEASE_TAG>` 段落写入临时 `RELEASE_NOTES.md`，作为 `body_path` 发布；段落缺失则直接失败，防止发出空说明。
- **缓存的取舍**：采纳上游 `gradle/actions/setup-gradle` 的 `cache-provider: basic` 与 `pub-cache`，标签构建只读缓存、不污染 main 的缓存内容。
- **Linux 构建不再要求 WPE WebKit**：上游的人机验证把 `flutter_inappwebview` 锁到带 Linux 实现的 beta 版，而该实现编译期要求 `libwpewebkit-*`，这个包在 Ubuntu 官方源（含 24.04 runner）里并不存在，首次发布流水线的 linux 作业因此报 `WPE WebKit not found` 失败。由于 Plus 的 Linux 桌面本来就声明不支持人机验证（`AuthTurnstile.isSupported` 不含 Linux），现用 `third_party/flutter_inappwebview_linux` 这个空实现占位插件替换 Linux 端实现：不编译 WPE、不注册任何 WebView，其余平台实现与行为完全不变。
- **Windows 构建兼容 VS 2026**：`flutter_inappwebview_windows` 使用 C++/WinRT 实验性协程，MSVC 14.51 把 `STL1011` 弃用提示升级成了硬错误。已在 `windows/CMakeLists.txt` 里加 `add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)` 抑制该断言，Windows 产物与运行时行为不变。

### 五、升级注意事项与已知问题

- 从旧版 Plus（如 `V1.12.3-Plus`）升级：启动检查会把 Plus 仓库最新的 Release 与当前版本比较，`V`/`v` 大小写与 `-Plus`、`-Plus.1` 后缀都能正确归一化，不会出现「已是最新却反复提示」或「漏掉新版本」。
- 同一上游版本的重发包（如 `V1.13.2-Plus.1`）会正常提示更新：重发序号参与版本比较，忽略记录也按带序号的版本身份区分，不会因「已忽略 `1.13.2`」而永久静默。
- Android 自动安装依赖 Release 资产带 `digest` 字段。若最新 Release 的 APK 没有该字段，应用会打开 Release 页提示手动下载，这是预期降级，不是故障。
- 桌面端不再单独发起发布页检查，统一由 App 内更新器负责；桌面只提供「检查更新 → 打开 Release 页」，下载安装仍需手动完成（AppImage / deb / pkg.tar.zst / 安装程序）。
- iOS 只发布无签名产物，装到真机需要使用者自行签名。
- 关闭自动检查更新后，启动不再发起任何更新请求；设置页「检查更新」入口仍可手动触发。
- 已知问题：Tag 与资产名都由 CI 安全化生成，若手写 tag 含中文或空格，`ARTIFACT_TAG` 会被替换为 `-`，请按 `V<上游版本>-Plus[.N]` 的格式打 tag。
