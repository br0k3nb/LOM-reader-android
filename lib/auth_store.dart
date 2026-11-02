import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'reader_api.dart';

// Public web OAuth audience used by the deployed LOTM reader. Android's package
// and signing certificate must also be registered in the same Google project.
const googleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue:
      '149159576823-8k9vuolgao75f068vnsj66ufqp1k6f6e.apps.googleusercontent.com',
);

class AuthStore extends ChangeNotifier {
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  AuthStore(
    this.api, {
    FlutterSecureStorage? storage,
    this._googleTokenProvider,
  }) : _storage = storage ?? const FlutterSecureStorage();
  final ReaderApi api;
  final FlutterSecureStorage _storage;
  final Future<String> Function()? _googleTokenProvider;
  Map<String, dynamic>? user;
  bool busy = false;
  String? busyMessage;
  String? error;
  bool _googleReady = false;
  String? get userId => user?['id'] as String?;
  String? get email => user?['email'] as String?;

  Future<void> initialize() async {
    try {
      final saved = await _storage.read(key: 'reader_account');
      if (saved != null) {
        final data = jsonDecode(saved) as Map;
        api.session = data['session'] as String?;
        user = Map<String, dynamic>.from(data['user'] as Map);
      }
    } catch (_) {
      api.session = null;
      user = null;
    }
    _notify();
  }

  Future<void> refresh() async {
    if (api.session == null || busy) return;
    try {
      final data = await api.request('/api/auth/session');
      if (data['user'] == null) {
        await _clear();
        return;
      }
      user = Map<String, dynamic>.from(data['user']);
      await _save();
      error = null;
    } on ReaderApiException catch (e) {
      if (e.status == 401) await _clear();
    } catch (_) {
      /* Retain the cached identity when offline. */
    }
    _notify();
  }

  Future<void> _save() => _storage.write(
    key: 'reader_account',
    value: jsonEncode({'user': user, 'session': api.session}),
  );
  Future<void> _clear() async {
    api.session = null;
    user = null;
    await _storage.delete(key: 'reader_account');
    _notify();
  }

  Future<bool> emailSignIn(
    String email,
    String password, {
    bool register = false,
  }) async {
    return _perform(
      () => api.authenticate(register ? 'register' : 'login', {
        'email': email.trim(),
        'password': password,
      }),
    );
  }

  Future<String> _nativeGoogleToken() async {
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(serverClientId: googleServerClientId);
      _googleReady = true;
    }
    final account = await google.authenticate();
    final token = account.authentication.idToken;
    if (token == null) {
      throw const ReaderApiException(
        'Google did not return an identity. Please try again.',
        401,
      );
    }
    return token;
  }

  Future<bool> googleSignIn() async => _perform(() async {
    busyMessage = 'Opening Google…';
    _notify();
    final token = await (_googleTokenProvider ?? _nativeGoogleToken)();
    busyMessage = 'Signing in…';
    _notify();
    return api.authenticate('google', {'credential': token});
  });

  Future<bool> _perform(Future<Map<String, dynamic>> Function() action) async {
    if (busy) return false;
    busy = true;
    busyMessage = 'Signing in…';
    error = null;
    _notify();
    try {
      final account = await action();
      if (account['id'] is! String || account['email'] is! String) {
        throw const FormatException('Invalid account');
      }
      user = account;
      await _save();
      return true;
    } on GoogleSignInException catch (e) {
      // Credential Manager also reports configuration failures as "canceled".
      // Always surface a result, including when no account chooser appeared.
      error = switch (e.code) {
        GoogleSignInExceptionCode.canceled =>
          'Google sign-in did not finish. Try again. If no account chooser opens, the app’s Google sign-in setup may need to be completed.',
        GoogleSignInExceptionCode.clientConfigurationError =>
          'Google sign-in is not configured for this Android build yet. You can still sign in with email.',
        _ => 'Google sign-in could not finish. Please try again or use email.',
      };
    } on ReaderApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Unable to sign in. Check your connection and try again.';
    } finally {
      busy = false;
      busyMessage = null;
      _notify();
    }
    return false;
  }

  Future<void> signOut() async {
    busy = true;
    _notify();
    try {
      await api.request('/api/auth/logout', body: {});
    } catch (_) {
      /* Local sign-out works offline. */
    }
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _clear();
    error = null;
    busy = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
