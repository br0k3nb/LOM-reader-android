import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Writes are serialized and atomically renamed; a killed process cannot truncate state.
class StateStore extends ChangeNotifier {
  StateStore(this.file);
  final File file;
  Map<String, dynamic> data = {
    'version': 1,
    'progress': <String, dynamic>{},
    'bookmarks': <String, dynamic>{},
    'settings': <String, dynamic>{},
  };
  Future<void> _pending = Future.value();
  Map<String, dynamic> get progress => data['progress'] as Map<String, dynamic>;
  Map<String, dynamic> get bookmarks =>
      data['bookmarks'] as Map<String, dynamic>;
  Map<String, dynamic> get settings => data['settings'] as Map<String, dynamic>;
  String get owner => data['progressOwner'] as String? ?? 'anonymous';

  Future<void> switchProfile(String nextOwner) async {
    if (owner == nextOwner) return;
    final profiles =
        data.putIfAbsent('profiles', () => <String, dynamic>{}) as Map;
    final previous = owner;
    profiles[previous] = Map<String, dynamic>.from(progress);
    data['progress'] = Map<String, dynamic>.from(
      profiles[nextOwner] as Map? ??
          (previous == 'anonymous' ? progress : <String, dynamic>{}),
    );
    data['progressOwner'] = nextOwner;
    await persist();
  }

  Future<void> load() async {
    if (await file.exists()) {
      data = validate(jsonDecode(await file.readAsString()));
    }
  }

  static Map<String, dynamic> validate(dynamic value) {
    if (value is! Map<String, dynamic> || value['version'] != 1) {
      throw const FormatException('Unsupported reading backup.');
    }
    for (final name in ['progress', 'bookmarks', 'settings']) {
      if (value[name] is! Map<String, dynamic>) {
        throw FormatException('Invalid $name in backup.');
      }
    }
    for (final entry in (value['progress'] as Map).entries) {
      final p = entry.value;
      if (!RegExp(
            r'^(lotm|coi)/(webnovel|oldtl|pt-br)$',
          ).hasMatch(entry.key as String) ||
          p is! Map ||
          p['slug'] is! int ||
          p['slug'] < 1 ||
          p['slug'] > 1500 ||
          p['scrollRatio'] is! num ||
          !p['scrollRatio'].isFinite ||
          p['scrollRatio'] < 0 ||
          p['scrollRatio'] > 1) {
        throw const FormatException('Invalid chapter progress in backup.');
      }
    }
    if (value['progressOwner'] != null && value['progressOwner'] is! String) {
      throw const FormatException('Invalid account scope.');
    }
    if (value['profiles'] != null) {
      if (value['profiles'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid account profiles.');
      }
      for (final profile in (value['profiles'] as Map).values) {
        validate({
          'version': 1,
          'progress': profile,
          'bookmarks': <String, dynamic>{},
          'settings': <String, dynamic>{},
        });
      }
    }
    for (final entry in (value['bookmarks'] as Map).entries) {
      if (!RegExp(
            r'^(lotm|coi)/(webnovel|oldtl|pt-br)/[1-9][0-9]{0,3}$',
          ).hasMatch(entry.key as String) ||
          entry.value is! Map ||
          entry.value['note'] is! String ||
          (entry.value['note'] as String).length > 10000) {
        throw const FormatException('Invalid bookmark in backup.');
      }
      final bookmark = entry.value as Map;
      if (bookmark['title'] != null &&
          (bookmark['title'] is! String ||
              (bookmark['title'] as String).length > 500)) {
        throw const FormatException('Invalid bookmark title in backup.');
      }
      if (bookmark['updatedAt'] != null &&
          (bookmark['updatedAt'] is! int || bookmark['updatedAt'] < 0)) {
        throw const FormatException('Invalid bookmark date in backup.');
      }
    }
    // The reader accepts only its known settings. Ignore other imported properties.
    final s = value['settings'] as Map<String, dynamic>;
    const numbers = {
      'fontSize': [12, 64],
      'fontWeight': [100, 900],
      'lineHeight': [1, 3],
    };
    for (final entry in numbers.entries) {
      final n = s[entry.key];
      if (n != null &&
          (n is! num ||
              !n.isFinite ||
              n < entry.value[0] ||
              n > entry.value[1])) {
        throw const FormatException('Invalid reader settings.');
      }
    }
    for (final key in ['theme', 'font', 'textAlign']) {
      if (s[key] != null &&
          (s[key] is! String ||
              (s[key] as String).length > 80 ||
              !RegExp(r'^[a-zA-Z0-9 ,_-]+$').hasMatch(s[key]))) {
        throw const FormatException('Invalid reader settings.');
      }
    }
    for (final key in [
      'hyphens',
      'indent',
      'navbarVisible',
      'navbarSticky',
      'showComments',
      'showBottomBanner',
      'solidBackground',
    ]) {
      if (s[key] != null && s[key] is! bool) {
        throw const FormatException('Invalid reader settings.');
      }
    }
    return Map<String, dynamic>.from(value);
  }

  Future<void> persist() {
    final snapshot = jsonEncode(data);
    _pending = _pending.catchError((Object _) {}).then((_) async {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(snapshot, flush: true);
      await temp.rename(file.path);
    });
    notifyListeners();
    return _pending;
  }

  Future<void> import(String text) async {
    if (text.length > 5 * 1024 * 1024) {
      throw const FormatException('Backup is too large.');
    }
    final next = validate(jsonDecode(text));
    data = next;
    await persist();
  }

  Future<void> saveProgress(
    String edition,
    int slug,
    num ratio, {
    num? scroll,
  }) {
    final existing = progress[edition];
    final offset =
        scroll ??
        (existing is Map && existing['slug'] == slug
            ? existing['scroll'] as num? ?? 0
            : 0);
    progress[edition] = {
      'slug': slug,
      'scrollRatio': ratio.clamp(0, 1),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'scroll': offset.round().clamp(0, 100000000),
      'pageIndex': (offset / 800).floor().clamp(0, 10000000),
    };
    return persist();
  }
}
