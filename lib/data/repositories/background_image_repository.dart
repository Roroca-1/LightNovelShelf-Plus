import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/cover_seed.dart';

const int _maxWallpaperEdge = 1600;
const int _directCopyMaxBytes = 1536 * 1024;

class ImportedBackgroundImage {
  const ImportedBackgroundImage(this.path, this.seedColorValue);
  final String path;
  final String? seedColorValue;
}

class BackgroundImageRepository {
  const BackgroundImageRepository();

  Future<String?> extractSeed(String path) async {
    final seed = await resolveCoverSeedColor(
      FileImage(File(path)),
      size: const Size(128, 128),
    );
    return seed == null ? null : formatHexColor(seed);
  }

  Future<ImportedBackgroundImage?> pickAndImport(String slot) async {
    final XFile? picked;
    if (Platform.isAndroid) {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
        // A full-resolution camera photo wastes memory and decode time when it
        // is only ever used as a dimmed app background.
        maxWidth: _maxWallpaperEdge.toDouble(),
        maxHeight: _maxWallpaperEdge.toDouble(),
        imageQuality: 68,
      );
    } else {
      picked = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(
            label: '图片',
            extensions: <String>['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
          ),
        ],
      );
    }
    if (picked == null) return null;

    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}background-images',
    );
    await directory.create(recursive: true);

    final rawExt = picked.name.contains('.')
        ? picked.name.split('.').last.toLowerCase()
        : 'png';
    File target;

    if (Platform.isAndroid) {
      target = File(
        '${directory.path}${Platform.pathSeparator}$slot.$rawExt',
      );
      final source = File(picked.path);
      if (await source.exists()) {
        if (await source.length() == 0) {
          throw const FormatException('图片文件为空。');
        }
        await source.copy(target.path);
      } else {
        final bytes = await picked.readAsBytes();
        if (bytes.isEmpty) throw const FormatException('图片文件为空。');
        await target.writeAsBytes(bytes, flush: true);
      }
    } else {
      final source = File(picked.path);
      final sourceBytes = await source.exists() ? await source.length() : -1;
      if (sourceBytes == 0) throw const FormatException('图片文件为空。');

      // 桌面与 iOS 若选入超大原图，导入时直接缩到背景所需分辨率，减少常驻解码开销。
      final resized = await _downscaleIfLarge(picked, sourceBytes);
      if (resized != null) {
        target = File('${directory.path}${Platform.pathSeparator}$slot.png');
        await target.writeAsBytes(resized, flush: true);
      } else if (await source.exists()) {
        target = File(
          '${directory.path}${Platform.pathSeparator}$slot.$rawExt',
        );
        await source.copy(target.path);
      } else {
        final bytes = await picked.readAsBytes();
        if (bytes.isEmpty) throw const FormatException('图片文件为空。');
        target = File(
          '${directory.path}${Platform.pathSeparator}$slot.$rawExt',
        );
        await target.writeAsBytes(bytes, flush: true);
      }
    }

    await _cleanupStaleSlotFiles(directory, slot, target.path);
    return ImportedBackgroundImage(target.path, await extractSeed(target.path));
  }

  Future<Uint8List?> _downscaleIfLarge(XFile picked, int knownSize) async {
    if (knownSize > 0 && knownSize <= _directCopyMaxBytes) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) throw const FormatException('图片文件为空。');
    if (bytes.length <= _directCopyMaxBytes) return null;

    ui.Codec? probe;
    ui.FrameInfo? probeFrame;
    ui.Codec? scaled;
    ui.FrameInfo? scaledFrame;
    try {
      probe = await ui.instantiateImageCodec(bytes);
      probeFrame = await probe.getNextFrame();
      final w = probeFrame.image.width;
      final h = probeFrame.image.height;
      if (w <= _maxWallpaperEdge && h <= _maxWallpaperEdge) return null;

      final targetWidth = w >= h ? _maxWallpaperEdge : null;
      final targetHeight = h > w ? _maxWallpaperEdge : null;
      scaled = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      scaledFrame = await scaled.getNextFrame();
      final data = await scaledFrame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      probeFrame?.image.dispose();
      probe?.dispose();
      scaledFrame?.image.dispose();
      scaled?.dispose();
    }
  }

  Future<void> _cleanupStaleSlotFiles(
    Directory directory,
    String slot,
    String keepPath,
  ) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is! File || entity.path == keepPath) continue;
        final name = entity.uri.pathSegments.isEmpty
            ? ''
            : entity.uri.pathSegments.last;
        if (name.startsWith('$slot.')) {
          await entity.delete();
        }
      }
    } catch (_) {
      // 清理旧扩展名文件失败不影响新背景使用。
    }
  }
}
