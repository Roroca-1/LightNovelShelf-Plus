package app.lightnovel.shelf.plus

import androidx.core.content.FileProvider

// 独立子类，避免和插件声明的 androidx FileProvider 在合并清单时冲突。
class AppUpdateFileProvider : FileProvider()
