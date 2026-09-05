import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/platform/desktop_platform.dart';
import '../data/repositories/app_update_repository.dart';
import '../data/repositories/profile_repository.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  void _switchBranch(int delta) {
    final count = 5;
    final next = (widget.shell.currentIndex + delta + count) % count;
    widget.shell.goBranch(next);
  }

  @override
  void initState() {
    super.initState();
    autoCheckInResult.addListener(_showCheckInResult);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showCheckInResult());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    AppUpdate? update;
    try {
      update = await const AppUpdateRepository().check();
    } catch (_) {
      return;
    }
    if (!mounted || update == null) return;
    final found = update;
    final target = found.downloadUrl ?? found.releaseUrl;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.system_update_outlined),
        title: Text('发现新版本 ${found.tag}'),
        content: const Text('可以下载适合当前平台的安装包。安装前会由系统再次确认。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await launchUrl(
                Uri.parse(target),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('下载更新'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    autoCheckInResult.removeListener(_showCheckInResult);
    super.dispose();
  }

  void _showCheckInResult() {
    final result = autoCheckInResult.value;
    if (result == null || !mounted) return;
    autoCheckInResult.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.event_available_outlined),
          title: const Text('签到成功'),
          content: Text(
            '获得 ${result.experience} 经验和 ${result.reward} 金币\n'
            '连续签到 ${result.streak} 天 · 当前等级 ${result.level}',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: isDesktopPlatform
          ? <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.tab, control: true):
                  () => _switchBranch(1),
              const SingleActivator(
                LogicalKeyboardKey.tab,
                control: true,
                shift: true,
              ): () => _switchBranch(-1),
            }
          : const <ShortcutActivator, VoidCallback>{},
      child: Focus(
        autofocus: true,
        child: Scaffold(
      // 两侧各自成层：NavigationBar 的 500ms 指示器动画不再连带重栅格整页内容。
      body: RepaintBoundary(child: widget.shell),
      bottomNavigationBar: RepaintBoundary(
        child: NavigationBar(
          selectedIndex: widget.shell.currentIndex,
          onDestinationSelected: (index) => widget.shell.goBranch(
            index,
            initialLocation: index == widget.shell.currentIndex,
          ),
          destinations: const <Widget>[
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: '发现',
            ),
            NavigationDestination(
              icon: Icon(Icons.collections_bookmark_outlined),
              selectedIcon: Icon(Icons.collections_bookmark),
              label: '书架',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: '历史',
            ),
            NavigationDestination(
              icon: _UnreadBadge(child: Icon(Icons.forum_outlined)),
              selectedIcon: _UnreadBadge(child: Icon(Icons.forum)),
              label: '社区',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: '搜索',
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

/// 单独订阅未读数，避免资料刷新把整个 shell（连带 indexedStack 里所有 tab）标脏。
class _UnreadBadge extends ConsumerWidget {
  const _UnreadBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(
      profileProvider.select(
        (profile) => profile.value?.unreadNotificationCount ?? 0,
      ),
    );
    return Badge(
      isLabelVisible: unread > 0,
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: child,
    );
  }
}
