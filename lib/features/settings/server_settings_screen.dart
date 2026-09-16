import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';

/// 服务节点在启动时建立 SignalR 连接，因此保存后下次启动应用生效。
class ServerSettingsScreen extends ConsumerWidget {
  const ServerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(settingsControllerProvider);
    final selected = controller.settings.apiServer;
    return Scaffold(
      appBar: AppBar(title: const Text('服务器节点')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          Text(
            '选择与网页版相同的内容服务节点。保存后请重新启动应用，正在进行的阅读不会被中断。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: ApiServer.values.map((server) {
                return RadioListTile<ApiServer>(
                  value: server,
                  groupValue: selected,
                  title: Text(server.label),
                  subtitle: Text(server.apiOrigin),
                  onChanged: (value) {
                    if (value == null) return;
                    controller.update((settings) =>
                        settings.copyWith(apiServer: value));
                  },
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}
