import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../providers.dart';

class AutoCheckInNotice {
  const AutoCheckInNotice({required this.result, required this.gainedExperience});

  final DailyCheckInResult result;
  final int gainedExperience;
}

/// 自动签到成功事件。主页消费后清空，避免切换页面重复弹窗。
final ValueNotifier<AutoCheckInNotice?> autoCheckInResult =
    ValueNotifier<AutoCheckInNotice?>(null);

/// 当前账号资料；未登录时保持 `null`。
class ProfileController extends AsyncNotifier<UserProfile?> {
  ApiClient get _api => ref.read(apiClientProvider);

  @override
  Future<UserProfile?> build() async {
    // 只看登录与否，token 刷新途中的 refreshing 快照不该把资料拆掉重拉。
    final authenticated = ref.watch(
      authSnapshotProvider.select((snapshot) => snapshot.isAuthenticated),
    );
    if (!authenticated) return null;
    final cached = await ref.read(bookMetadataCacheProvider).readProfile();
    if (cached != null) {
      unawaited(_refreshInBackground());
      return cached;
    }
    return _loadFresh();
  }

  Future<UserProfile> _loadFresh() async {
    var profile = await _api.getMyProfile();
    if (!profile.growth.signedToday) {
      try {
        final result = await _api.checkIn();
        final refreshed = await _api.getMyProfile();
        autoCheckInResult.value = AutoCheckInNotice(
          result: result,
          gainedExperience:
              (refreshed.growth.experience - profile.growth.experience)
                  .clamp(0, 1 << 31)
                  .toInt(),
        );
        profile = refreshed;
      } catch (_) {
        // 自动签到不能阻止应用启动；网络恢复后下次重建资料时会再尝试。
      }
    }
    await ref.read(bookMetadataCacheProvider).writeProfile(profile);
    return profile;
  }

  Future<void> _refreshInBackground() async {
    try {
      state = AsyncValue<UserProfile?>.data(await _loadFresh());
    } catch (_) {
      // Cached profile remains usable while offline.
    }
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() async {
      if (!ref.read(authSnapshotProvider).isAuthenticated) return null;
      return _loadFresh();
    });
  }

  /// 后台对账用：不进 loading 态，未读角标不会在刷新途中闪回 0。
  Future<void> refreshQuietly() async {
    if (!ref.read(authSnapshotProvider).isAuthenticated) return;
    final profile = await _api.getMyProfile();
    state = AsyncValue<UserProfile?>.data(profile);
  }

  Future<DailyCheckInResult> checkIn() async {
    final result = await _api.checkIn();
    await reload();
    return result;
  }

  Future<void> setAvatar(String url) async {
    await _api.setAvatar(url);
    await reload();
  }
}

final AsyncNotifierProvider<ProfileController, UserProfile?> profileProvider =
    AsyncNotifierProvider<ProfileController, UserProfile?>(
      ProfileController.new,
    );
