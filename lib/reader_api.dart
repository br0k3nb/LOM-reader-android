import 'dart:convert';
import 'dart:io';
import 'library_store.dart';

class ReaderApiException implements Exception {
  const ReaderApiException(this.message, this.status);
  final String message;
  final int status;
  @override
  String toString() => message;
}

/// The website owns account creation, Google verification, and session expiry.
/// Tokens never enter the chapter WebView or the reading backup.
class ReaderApi {
  ReaderApi({this.source = defaultSource, HttpClient? client})
    : _client = client ?? HttpClient();
  final String source;
  final HttpClient _client;
  String? session;
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final url = Uri.parse(source).resolve(path);
    final requestSession = session;
    final request = await _client
        .openUrl(body == null ? 'GET' : 'POST', url)
        .timeout(const Duration(seconds: 20));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set('Origin', Uri.parse(source).origin);
    if (requestSession != null) {
      request.cookies.add(Cookie('lotm_reader_session', requestSession));
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) {
        throw const FormatException('Unexpected account response');
      }
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const ReaderApiException(
        'The account service is temporarily unavailable. Please try again.',
        503,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReaderApiException(
        data['error'] as String? ?? 'Unable to reach the account service.',
        response.statusCode,
      );
    }
    for (final cookie in response.cookies) {
      if (cookie.name == 'lotm_reader_session') {
        session = cookie.value.isEmpty ? null : cookie.value;
      }
    }
    return data;
  }

  Future<Map<String, dynamic>> authenticate(
    String method,
    Map<String, dynamic> payload,
  ) async {
    final response = await request('/api/auth/$method', body: payload);
    if (response['user'] is! Map || session == null) {
      throw const FormatException('The website did not return a valid session');
    }
    return Map<String, dynamic>.from(response['user']);
  }

  void dispose() => _client.close(force: true);
}
