import 'dart:io';
import 'package:flutter/services.dart';

String formatBytes(num bytes, {bool gb = false}) {
  if (gb || bytes >= 1000000000) {
    return '${(bytes / 1000000000).toStringAsFixed(3)} GB';
  }
  if (bytes >= 1000000) return '${(bytes / 1000000).toStringAsFixed(1)} MB';
  if (bytes >= 1000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
  return '${bytes.round()} B';
}

String formatEta(int? seconds) {
  if (seconds == null) return 'Calculating…';
  if (seconds < 60) return 'Less than a minute';
  if (seconds < 3600) return '~${(seconds / 60).ceil()} min';
  return '~${seconds ~/ 3600} h ${(seconds % 3600 / 60).ceil()} min';
}

Future<int> directoryBytes(Directory directory) async {
  if (!await directory.exists()) return 0;
  var bytes = 0;
  await for (final file in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (file is File) {
      try {
        bytes += await file.length();
      } on FileSystemException {
        /* A checkpoint may be renamed during a scan. */
      }
    }
  }
  return bytes;
}

class StorageUsage {
  const StorageUsage({
    this.downloads = 0,
    this.app = 0,
    this.data = 0,
    this.free = 0,
  });
  final int downloads, app, data, free;
  int get total => app + data;
  static Future<StorageUsage> measure(Directory root) async {
    final downloads = await directoryBytes(root);
    try {
      final result = await const MethodChannel(
        'dev.lotm.reader/storage',
      ).invokeMapMethod<String, num>('usage');
      return StorageUsage(
        downloads: downloads,
        app: result?['appBytes']?.toInt() ?? 0,
        data: result?['dataBytes']?.toInt() ?? downloads,
        free: result?['freeBytes']?.toInt() ?? 0,
      );
    } on MissingPluginException {
      return StorageUsage(downloads: downloads, data: downloads);
    }
  }
}
