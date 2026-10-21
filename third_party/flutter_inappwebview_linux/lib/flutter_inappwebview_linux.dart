// 占位插件：故意不提供任何 Linux WebView 实现。
//
// 上游 flutter_inappwebview_linux 在 CMake 阶段要求 WPE WebKit 开发包，而 Ubuntu
// 软件源里没有 libwpewebkit-*，导致 flutter build linux 直接失败。
// 本应用在 Linux 桌面本就不使用 WebView（见 AuthTurnstile.isSupported），
// 因此用本占位插件替换：不编译 WPE，运行时行为不变。
