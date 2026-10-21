#include "include/flutter_inappwebview_linux/flutter_inappwebview_linux_plugin.h"

void flutter_inappwebview_linux_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  // 轻书架Plus 不在 Linux 桌面使用 WebView，这里刻意留空。
  (void)registrar;
}
