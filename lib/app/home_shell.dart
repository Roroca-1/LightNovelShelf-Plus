import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/platform/desktop_platform.dart';
import '../data/repositories/app_update_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/unread_counts.dart';
import '../shared/layout/adaptive_layout.dart';
import '../shared/widgets/unread_badge.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  void _switchBranch(int delta) {
    final count = 5;
    final next = (widget.shell.currentIndex + delta + count) % count;
    widget.shell.goBranch(next);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    autoCheckInResult.addListener(_showCheckInResult);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showCheckInResult());
    // 移动端启动检查交给 features/update/app_updater.dart；
    // 桌面端没有安装包下载/安装流程，仍走 Plus 的发布页入口。
    if (isDesktopPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(communityUnreadCountProvider.notifier).reconcile());
    }
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
        content: const Text(
          '可以下载适合当前平台的安装包。安装前会由系统再次确认。\n'
          '下载前请先阅读更新日志，确认更新内容。',
        ),
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
    WidgetsBinding.instance.removeObserver(this);
    autoCheckInResult.removeListener(_showCheckInResult);
    super.dispose();
  }

  void _showCheckInResult() {
    final notice = autoCheckInResult.value;
    if (notice == null || !mounted) return;
    autoCheckInResult.value = null;
    final result = notice.result;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.event_available_outlined),
          title: const Text('签到成功'),
          content: Text(
            '获得 ${notice.gainedExperience} 经验和 ${result.reward} 金币\n'
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

  final GlobalKey _bodyKey = GlobalKey();

  void _goBranch(int index) => widget.shell.goBranch(
    index,
    initialLocation: index == widget.shell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final rail = useNavigationRail(MediaQuery.sizeOf(context));
    // 两侧各自成层：导航栏的 500ms 指示器动画不再连带重栅格整页内容。
    // 带 GlobalKey，窗口跨过断点换导航形态时各 tab 的页面状态跟着搬过去。
    final body = RepaintBoundary(key: _bodyKey, child: shell);
    final content = rail
        ? Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                RepaintBoundary(
                  child: NavigationRail(
                    selectedIndex: shell.currentIndex,
                    onDestinationSelected: _goBranch,
                    groupAlignment: 0,
                    destinations: <NavigationRailDestination>[
                      for (final item in _destinations)
                        NavigationRailDestination(
                          icon: item.icon,
                          selectedIcon: item.selectedIcon,
                          label: Text(item.label),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: PaneMediaQuery(removeLeft: true, child: body),
                ),
              ],
            ),
          )
        : Scaffold(
            body: body,
            bottomNavigationBar: RepaintBoundary(
              child: NavigationBar(
                selectedIndex: shell.currentIndex,
                onDestinationSelected: _goBranch,
                destinations: <Widget>[
                  for (final item in _destinations)
                    NavigationDestination(
                      icon: item.icon,
                      selectedIcon: item.selectedIcon,
                      label: item.label,
                    ),
                ],
              ),
            ),
          );
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
      child: Focus(autofocus: true, child: content),
    );
  }
}

typedef _Destination = ({Widget icon, Widget selectedIcon, String label});

const List<_Destination> _destinations = <_Destination>[
  (
    icon: Icon(Icons.explore_outlined),
    selectedIcon: Icon(Icons.explore),
    label: '发现',
  ),
  (
    icon: Icon(Icons.collections_bookmark_outlined),
    selectedIcon: Icon(Icons.collections_bookmark),
    label: '书架',
  ),
  (
    icon: Icon(Icons.history_outlined),
    selectedIcon: Icon(Icons.history),
    label: '历史',
  ),
  (
    icon: _CommunityUnreadBadge(child: Icon(Icons.forum_outlined)),
    selectedIcon: _CommunityUnreadBadge(child: Icon(Icons.forum)),
    label: '社区',
  ),
  (
    icon: Icon(Icons.search_outlined),
    selectedIcon: Icon(Icons.search),
    label: '搜索',
  ),
];

/// 单独订阅未读数，避免资料刷新把整个 shell（连带 indexedStack 里所有 tab）标脏。
class _CommunityUnreadBadge extends ConsumerWidget {
  const _CommunityUnreadBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      UnreadBadge(count: ref.watch(communityUnreadCountProvider), child: child);
}
