# 轻书架Plus

轻书架Plus 是基于[轻书架官方 Flutter 客户端](https://github.com/LightNovelShelf/Flutter)继续开发的独立功能扩展版本，重点改善书架管理、桌面端操作、自定义外观与离线缓存体验。

当前正式支持：

- Android ARM64（`arm64-v8a`）
- Linux x86_64（AppImage）
- Windows x86_64

项目包名为 `lightnovel_shelf_plus`，Android 应用标识为 `app.lightnovel.shelf.plus`，因此可以与官方版轻书架同时安装。因没设备测试所以项目不构建或发布 iOS、macOS 软件包。

## 相较官方版新增的功能

### 书架与系列管理

- 书架支持“单本 / 系列”显示，并记住上次选择。
- 书架与历史记录支持“网格 / 列表”显示，并记住上次选择。
- 系列内也支持网格和列表模式；从书架打开系列后始终按标题排序，以保持卷册阅读顺序。
- “全部小说”提供相互独立的“单本 / 系列”和“网格 / 列表”开关，可自由组合。
- 在发现页系列中长按进入多选，支持选择多个卷册、全选并批量加入书架。
- 书架单本模式和系列子页均支持多选、全选与批量移出书架。
- 书架排序为纯显示排序，不修改服务端手动顺序：
  - 手动顺序
  - 标题升序、降序（中文优先按拼音；检测到假名时使用罗马字）
  - 最近更新、最早更新
  - 最近加入
- 漫画可加入本地书架，不调用只适用于小说系列的功能。
- 列表条目补充作者、更新时间等信息；系列条目显示卷数和更新时间。
- 阅读页进度条切换页数，而非章节
- 滚动模式可依靠滚动切换章节

### 浏览与阅读

- 发现、排行榜、全部小说、系列、书架和历史等书籍入口支持桌面端右键菜单。
- 桌面端右键菜单可直接阅读（跳过详情页）、搜索系列、加入/移出书架或进入多选。
- 阅读页支持独立文字颜色设置。
- 自动签到：应用启动后自动执行，成功时显示获得的经验、金币、连续签到天数和等级。

### 外观与桌面适配

- 支持自定义 Material 3 / Material You 主题色、系统动态配色和 OLED 纯黑模式。
- 自定义应用背景与阅读背景，可以一键同步设置。
- 背景图片支持亮度、模糊和 Material You 配色提取。
- Linux、Windows 使用更适合键鼠与高 DPI 显示器的宽屏布局和文字缩放。（待完善）
- 桌面端支持键盘焦点浏览、连续选择和右键快捷操作。

### 缓存与性能

- 首页、书架、阅读历史和个人资料优先显示本地缓存，再在后台刷新服务端数据。
- 登录状态尚在恢复时继续显示缓存内容，减少短暂出现“登录后查看书架”的情况。
- 优化封面图片缓存、尺寸请求、预解码和漫画阅读预加载。
- 优化书架草稿、系列分组与页面间切换，减少不必要的全页重建。
- 自定义背景会压缩导入尺寸并复用已解码图片，降低内存、模糊和路由切换开销。
- 设置中提供清除全部缓存、图片缓存和阅读字体缓存的入口。



## Linux / Windows 键鼠操作

键鼠功能仅在 Linux 和 Windows 启用。

### 应用与书籍列表

| 操作 | 功能 |
| --- | --- |
| `Ctrl+Tab` | 向右循环切换发现、书架、历史、社区、搜索 |
| `Ctrl+Shift+Tab` | 向左循环切换底栏 |
| `Tab` / `Shift+Tab` | 在当前页面可操作条目间向前 / 向后移动焦点 |
| `Enter` | 打开当前聚焦条目 |
| `Space` | 在书架中选择 / 取消选择当前书籍，并自动进入选择模式 |
| `Ctrl+A` | 在书架选择模式中选择当前层级全部可用书籍 |
| `Ctrl+单击` | 添加或取消一个书架条目的选择 |
| `Shift+单击` | 从上一个选择锚点连续选择到当前书架条目 |
| `Esc` | 退出选择模式；没有选择状态时返回上一级 |
| 鼠标右键 | 在鼠标位置打开书籍快捷菜单 |

### 小说阅读器

| 操作 | 功能 |
| --- | --- |
| `←` / `Page Up` | 上一页或上一屏 |
| `→` / `Page Down` | 下一页或下一屏 |
| `Space` | 下一页或下一屏 |
| `Shift+Space` | 上一页或上一屏 |
| `Esc` | 第一次显示阅读菜单；菜单已显示时返回书籍详情页 |

## 本地开发与检查

项目 CI 使用 Flutter `3.47.0` 和 Java 17。建议本地使用相同版本：

```bash
flutter --version
flutter pub get
flutter analyze
flutter test
flutter run -d <device>
```

如需注入刷新令牌：

```bash
flutter run -d <device> --dart-define=REFRESH_TOKEN=<refresh-token>
```

## 编译 Android ARM64

需要 Android SDK、Java 17，并确保 `flutter doctor -v` 能识别 Android toolchain。

```bash
flutter pub get
flutter build apk --release \
  --target-platform android-arm64 \
  --split-per-abi
```

输出：

```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

未配置仓库签名密钥时，项目使用现有的调试签名回退。这样的 APK 可以测试安装，但可能无法覆盖安装使用其他证书签名的版本。

## 编译 Linux x86_64

Arch / CachyOS 依赖：

```bash
sudo pacman -S --needed \
  clang cmake ninja pkgconf gtk3 libsecret \
  base-devel git curl unzip xz zip
```

编译 release bundle：

```bash
flutter config --enable-linux-desktop
flutter pub get
flutter build linux --release
```

输出目录：

```text
build/linux/x64/release/bundle/
```

仓库的 Release workflow 会使用 `linuxdeploy` 将此 bundle 封装为 x86_64 AppImage。

## 编译 Windows x86_64

需要 Windows 10/11、Visual Studio 2022，并安装“使用 C++ 的桌面开发”工作负载：

```powershell
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release
```

输出目录：

```text
build\windows\x64\runner\Release\
```

发布时必须保留该目录中的 EXE、DLL 和 `data` 文件夹，不能只复制可执行文件。



## 提交问题与功能建议

请在[轻书架Plus Issues](https://github.com/Roroca-1/LightNovelShelf-Plus/issues)提交问题。报告界面或性能问题时，请附上平台、应用版本、复现步骤以及截图或录屏。

## 赞助本站

<a href="https://www.ifdian.net/a/wuyu8512">赞助</a>本站可以帮助我购买更多的 Token，来使网站变得更好

<img src=".github/afdian.jpeg" height="300">

## 致谢

轻书架Plus 基于[轻书架官方 Flutter 客户端](https://github.com/LightNovelShelf/Flutter)继续开发，感谢上游项目及其贡献者提供完整的服务端客户端基础。

基于 https://github.com/celia-sh/Novella 的 Flutter 版本重新开发得来

感谢 https://github.com/Kanscape 提供的 UI 布局交互思路，如果你需要体验 iOS 上的原生组件，不妨试试上述第三方客户端
