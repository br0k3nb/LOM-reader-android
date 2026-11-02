import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'auth_store.dart';
import 'background_downloads.dart' show writeJson;
import 'reader_api.dart';
import 'state_store.dart';

/// Uses the same logical page height, deduplication keys and newer-position
/// merge rule as the website. Each account has its own durable offline queue.
class CloudSync extends ChangeNotifier {
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  CloudSync(this.auth, this.state, this.file);
  final AuthStore auth;
  final StateStore state;
  final File file;
  Map<String, dynamic> _accounts = {};
  String? _owner;
  Timer? _debounce, _retry;
  bool syncing = false;
  String? error;
  DateTime? lastSynced;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _writes = Future.value();
  String get _queueOwner => _owner ?? 'anonymous';
  Map<String, dynamic> get _account =>
      Map<String, dynamic>.from(_accounts[_queueOwner] as Map? ?? {});
  Map<String, dynamic> get daily =>
      Map<String, dynamic>.from(_account['daily'] as Map? ?? {});
  Map<String, dynamic> get chapters =>
      Map<String, dynamic>.from(_account['chapters'] as Map? ?? {});
  int get pending => (_account['events'] as List? ?? []).length;
  int get todayPages => (daily[_date()] as num?)?.toInt() ?? 0;

  String _date() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> initialize() async {
    try {
      if (await file.exists()) {
        _accounts =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {
      _accounts = {};
    }
    await activate();
    _retry = Timer.periodic(const Duration(minutes: 1), (_) => synchronize());
  }

  Future<void> activate() async {
    if (_disposed) return;
    final owner = auth.userId;
    if (_owner == owner && state.owner == (owner ?? 'anonymous')) return;
    _generation++;
    _owner = owner;
    _debounce?.cancel();
    syncing = false;
    error = null;
    lastSynced = null;
    await state.switchProfile(owner ?? 'anonymous');
    if (owner != null) {
      final anonymous = Map<String, dynamic>.from(
        _accounts['anonymous'] as Map? ?? {},
      );
      final account = _account;
      final events = List<dynamic>.from(account['events'] as List? ?? []);
      final keys = events.map(_eventKey).toSet();
      for (final event in anonymous['events'] as List? ?? []) {
        if (keys.add(_eventKey(event))) events.add(event);
      }
      account['events'] = events;
      _accounts[owner] = account;
      anonymous['events'] = <dynamic>[];
      _accounts['anonymous'] = anonymous;
      await _persist();
    }
    _notify();
    if (owner != null) unawaited(synchronize());
  }

  Future<void> _persist() {
    final snapshot = jsonDecode(jsonEncode(_accounts));
    _writes = _writes
        .catchError((Object _) {})
        .then((_) => writeJson(file, snapshot));
    return _writes;
  }

  Future<void> record(String edition, int slug, num scroll) async {
    if (_disposed) return;
    if (_owner != auth.userId) return;
    final p = edition.split('/');
    final account = _account;
    final events = List<dynamic>.from(account['events'] as List? ?? []);
    final floors = Map<String, dynamic>.from(account['floors'] as Map? ?? {});
    final date = _date();
    final key = '$edition/$slug/$date';
    final previous = (floors[key] as num?)?.toInt() ?? -1;
    final last = (scroll / 800).floor().clamp(0, 5000);
    for (var i = previous + 1; i <= last; i++) {
      events.add({
        'book': p[0],
        'tl': p[1],
        'slug': slug,
        'pageIndex': i,
        'date': date,
      });
    }
    floors[key] = last > previous ? last : previous;
    account['events'] = events.length > 5000
        ? events.sublist(events.length - 5000)
        : events;
    account['floors'] = floors;
    _accounts[_queueOwner] = account;
    await _persist();
    _notify();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1400), synchronize);
  }

  String _eventKey(dynamic e) =>
      '${e['book']}/${e['tl']}/${e['slug']}/${e['pageIndex']}/${e['date']}';

  Future<void> _merge(Map<String, dynamic> remote) async {
    final account = _account;
    if (remote['daily'] is Map) account['daily'] = remote['daily'];
    if (remote['chapters'] is Map) account['chapters'] = remote['chapters'];
    _accounts[_owner!] = account;
    var changed = false;
    for (final raw in remote['progress'] as List? ?? []) {
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      final key = '${entry['book']}/${entry['tl']}';
      try {
        StateStore.validate({
          'version': 1,
          'progress': {key: entry},
          'bookmarks': <String, dynamic>{},
          'settings': <String, dynamic>{},
        });
      } catch (_) {
        continue;
      }
      final local = state.progress[key];
      if (local is! Map ||
          (entry['updatedAt'] as num? ?? 0) >
              (local['updatedAt'] as num? ?? 0)) {
        state.progress[key] = entry;
        changed = true;
      }
    }
    if (changed) await state.persist();
    await _persist();
  }

  Future<void> synchronize() async {
    if (_disposed) return;
    final owner = _owner;
    if (owner == null || syncing || owner != auth.userId) return;
    final generation = _generation;
    syncing = true;
    error = null;
    _notify();
    bool current() =>
        !_disposed &&
        owner == _owner &&
        owner == auth.userId &&
        generation == _generation;
    try {
      final remote = await auth.api.request('/api/reading/sync');
      if (!current()) return;
      await _merge(remote);
      if (!current()) return;
      final positions = state.progress.entries.toList();
      var index = 0;
      do {
        final events = List<dynamic>.from(
          _account['events'] as List? ?? [],
        ).take(200).toList();
        final payload = <String, dynamic>{'events': events};
        if (index < positions.length) {
          final entry = positions[index++];
          final p = entry.key.split('/');
          final value = Map<String, dynamic>.from(entry.value as Map);
          payload['progress'] = {
            'book': p[0],
            'tl': p[1],
            'slug': value['slug'],
            'scrollRatio': value['scrollRatio'],
            'scroll': value['scroll'] ?? 0,
            'pageIndex': value['pageIndex'] ?? 0,
            'updatedAt': value['updatedAt'] ?? 0,
          };
        }
        if (events.isEmpty && payload['progress'] == null) break;
        final result = await auth.api.request(
          '/api/reading/sync',
          body: payload,
        );
        if (!current()) return;
        final sent = events.map(_eventKey).toSet();
        final account = _account;
        account['events'] = (account['events'] as List? ?? [])
            .where((e) => !sent.contains(_eventKey(e)))
            .toList();
        _accounts[owner] = account;
        await _merge(result);
      } while (current() && (pending > 0 || index < positions.length));
      if (current()) lastSynced = DateTime.now();
    } on ReaderApiException catch (e) {
      if (current()) {
        error = e.status == 401
            ? 'Session expired. Sign in again to sync.'
            : 'Sync paused. Your progress is saved on this device.';
        if (e.status == 401) unawaited(auth.refresh());
      }
    } catch (_) {
      if (current()) error = 'Offline. Your progress will sync when connected.';
    } finally {
      if (current()) {
        syncing = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _debounce?.cancel();
    _retry?.cancel();
    super.dispose();
  }
}
