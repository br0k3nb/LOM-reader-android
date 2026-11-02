import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'library_store.dart';
import 'models.dart';

/// The WebView uses the bundled renderer. Native requests provide illustrations
/// for online chapters; downloaded chapters require no network requests.
class ReaderServer {
  ReaderServer(this.library);
  final LibraryStore library;
  HttpServer? _server;
  Edition? edition;
  bool online = false;
  final String _token = List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  Uri get uri => Uri.parse('http://127.0.0.1:${_server!.port}/?token=$_token');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_serve);
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method != 'GET') {
        response.statusCode = 405;
        return;
      }
      if (request.uri.queryParameters['token'] == _token) {
        response.cookies.add(
          Cookie('lotm_session', _token)
            ..httpOnly = true
            ..sameSite = SameSite.strict
            ..path = '/',
        );
      } else if (!request.cookies.any(
        (c) => c.name == 'lotm_session' && c.value == _token,
      )) {
        response.statusCode = 403;
        return;
      }
      response.headers.set(
        'Content-Security-Policy',
        "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-src 'none'; base-uri 'none'; form-action 'none'",
      );
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.headers.set('Cache-Control', 'no-store');
      final path = request.uri.path == '/'
          ? 'index.html'
          : request.uri.path.substring(1);
      if (!LibraryStore.safePath(path)) {
        response.statusCode = 400;
        return;
      }
      response.headers.contentType = _type(path);
      if (path.startsWith('assets/images/')) {
        final e = edition;
        if (e == null) {
          response.statusCode = 404;
          return;
        }
        final bytes = await library.readIllustration(
          e,
          '/$path',
          online: online,
        );
        if (bytes == null) {
          response.statusCode = 404;
          return;
        }
        response.add(bytes);
      } else {
        final key = path.startsWith('fonts/')
            ? 'assets/$path'
            : 'assets/reader/$path';
        final bytes = await rootBundle.load(key);
        response.add(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      }
    } catch (_) {
      response.statusCode = 404;
    } finally {
      await response.close();
    }
  }

  ContentType _type(String path) {
    if (path.endsWith('.html')) return ContentType.html;
    if (path.endsWith('.js')) {
      return ContentType('text', 'javascript', charset: 'utf-8');
    }
    if (path.endsWith('.css')) {
      return ContentType('text', 'css', charset: 'utf-8');
    }
    if (path.endsWith('.webp')) return ContentType('image', 'webp');
    if (path.endsWith('.png')) return ContentType('image', 'png');
    if (path.endsWith('.jpg')) return ContentType('image', 'jpeg');
    if (path.endsWith('.woff2')) return ContentType('font', 'woff2');
    if (path.endsWith('.woff')) return ContentType('font', 'woff');
    if (path.endsWith('.ttf')) return ContentType('font', 'ttf');
    return ContentType.binary;
  }

  Future<void> close() async {
    await _server?.close(force: true);
  }
}
