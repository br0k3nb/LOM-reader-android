import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'library_store.dart';
import 'models.dart';
import 'reader_server.dart';
import 'state_store.dart';
import 'cloud_sync.dart';
import 'habit_store.dart';
import 'design.dart';
import 'reader_hud.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.library,
    required this.state,
    required this.edition,
    required this.chapter,
    this.sync,
    this.habits,
  });
  final LibraryStore library;
  final StateStore state;
  final Edition edition;
  final Chapter chapter;
  final CloudSync? sync;
  final HabitStore? habits;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  late final ReaderServer server;
  late final WebViewController controller;
  late Edition edition;
  late Chapter chapter;
  bool loading = true;
  bool ready = false;
  bool fullscreen = false;
  bool offline = false;
  String? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    edition = widget.edition;
    chapter = widget.chapter;
    server = ReaderServer(widget.library)..edition = edition;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xff121c22))
      ..addJavaScriptChannel(
        'NativeReader',
        onMessageReceived: (message) {
          _message(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = Uri.tryParse(request.url);
            if (url != null &&
                url.host == '127.0.0.1' &&
                url.port == server.uri.port &&
                url.path == '/') {
              return NavigationDecision.navigate;
            }
            if (url != null &&
                url.fragment.isNotEmpty &&
                url.host == '127.0.0.1') {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
          onWebResourceError: (failure) {
            if (failure.isForMainFrame == true && mounted) {
              setState(() {
                error = failure.description;
                loading = false;
              });
            }
          },
        ),
      );
    _start();
  }

  Future<void> _start() async {
    try {
      await server.start();
      await controller.loadRequest(server.uri);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> _open(Edition nextEdition, Chapter next) async {
    await _flushProgress();
    final currentGeneration = ++generation;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
        edition = nextEdition;
        chapter = next;
      });
    }
    try {
      final content = await widget.library.readChapter(nextEdition, next);
      if (!mounted || currentGeneration != generation) return;
      edition = nextEdition;
      chapter = next;
      server.edition = edition;
      server.online = !content.offline;
      offline = content.offline;
      final saved = widget.state.progress[edition.key];
      final ratio = saved is Map && saved['slug'] == next.slug
          ? saved['scrollRatio']
          : 0;
      await controller.runJavaScript(
        'window.openChapter(${jsonEncode({...next.toJson(), 'html': content.html, 'scrollRatio': ratio, 'settings': widget.state.settings})});',
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted && currentGeneration == generation) {
        setState(() {
          error = widget.library.status(nextEdition).complete
              ? 'Unable to open the downloaded chapter. Verify this edition in Downloads and resume it to repair missing files.'
              : 'Unable to load this chapter online. Check your connection and retry, or download the edition for offline reading.';
          loading = false;
        });
      }
    }
  }

  Future<void> _message(String text) async {
    if (!mounted) return;
    try {
      final message = jsonDecode(text) as Map<String, dynamic>;
      switch (message['type']) {
        case 'ready':
          ready = true;
          await _open(edition, chapter);
        case 'opened':
          if (mounted) setState(() => loading = false);
        case 'progress':
          final key = '${message['book']}/${message['tl']}';
          final slug = message['slug'];
          final ratio = message['scrollRatio'];
          if (widget.library.editions.any(
                (e) =>
                    e.key == key && e.chapter(slug is int ? slug : -1) != null,
              ) &&
              ratio is num &&
              ratio.isFinite) {
            final scroll = message['scroll'];
            final offset = scroll is num && scroll.isFinite
                ? scroll.clamp(0, 100000000)
                : 0;
            await widget.state.saveProgress(
              key,
              slug as int,
              ratio,
              scroll: offset,
            );
            await widget.sync?.record(key, slug, offset);
            await widget.habits?.recordReading(
              edition: key,
              slug: slug,
              ratio: ratio,
              scroll: offset,
            );
          }
        case 'settings':
          final next = StateStore.validate({
            ...widget.state.data,
            'settings': message['settings'],
          });
          widget.state.data = next;
          await widget.state.persist();
        case 'navigate':
          await _navigate(message['path'] as String);
        case 'fullscreen':
          await _setFullscreen(!fullscreen);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Reader action failed: $e')));
      }
    }
  }

  Future<void> _navigate(String path) async {
    final uri = Uri.tryParse(path);
    if (uri == null) return;
    final segments = uri.pathSegments;
    if (segments.length == 4 && segments.first == 'read') {
      final match = widget.library.editions.where(
        (e) => e.book == segments[1] && e.tl == segments[2],
      );
      if (match.isEmpty) return;
      final target = match.first.chapter(int.tryParse(segments[3]) ?? -1);
      if (target != null) await _open(match.first, target);
    } else if (!uri.hasScheme || segments.firstOrNull == 'book') {
      await _flushProgress();
      if (mounted) Navigator.pop(context);
    } else if (uri.scheme == 'https' || uri.scheme == 'http') {
      // External references open in the browser; the offline WebView never loads them.
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _bookmark() async {
    final existing = widget.state.bookmarks[chapter.key];
    final input = TextEditingController(
      text: existing?['note'] as String? ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bookmark · Chapter ${chapter.slug}'),
        content: TextField(
          controller: input,
          maxLines: 4,
          maxLength: 10000,
          decoration: const InputDecoration(hintText: 'Optional note'),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(context, 'remove'),
              child: const Text('Remove'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == 'save') {
      widget.state.bookmarks[chapter.key] = {
        'note': input.text,
        'title': chapter.title,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
    }
    if (result == 'remove') widget.state.bookmarks.remove(chapter.key);
    input.dispose();
    if (result != null) {
      await widget.state.persist();
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (ready &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused)) {
      controller.runJavaScript("window.dispatchEvent(new Event('pagehide'));");
      _flushProgress();
    }
  }

  Future<void> _flushProgress() async {
    if (!ready || loading || error != null) return;
    try {
      final result = await controller.runJavaScriptReturningResult(
        'Math.min(1,Math.max(0,window.scrollY/Math.max(1,document.documentElement.scrollHeight-window.innerHeight)))',
      );
      final ratio = result is num ? result : num.tryParse(result.toString());
      if (ratio != null && ratio.isFinite) {
        await widget.state.saveProgress(edition.key, chapter.slug, ratio);
        await widget.habits?.recordReading(
          edition: edition.key,
          slug: chapter.slug,
          ratio: ratio,
        );
        if (widget.sync != null) unawaited(widget.sync!.synchronize());
      }
    } catch (_) {
      /* The scroll channel has already persisted the last checkpoint. */
    }
  }

  Future<void> _setFullscreen(bool enabled) async {
    await _flushProgress();
    await SystemChrome.setEnabledSystemUIMode(
      enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    if (mounted) setState(() => fullscreen = enabled);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    server.close();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop) return;
      if (fullscreen) {
        await _setFullscreen(false);
        return;
      }
      await _flushProgress();
      if (ready) {
        await controller.runJavaScript(
          "window.dispatchEvent(new Event('pagehide'));",
        );
      }
      if (context.mounted) Navigator.pop(context);
    },
    child: Scaffold(
      appBar: fullscreen
          ? null
          : AppBar(
              title: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                child: Text(
                  '${edition.book.toUpperCase()} · Chapter ${chapter.slug}',
                  key: ValueKey(chapter.key),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Tooltip(
                    message: offline ? 'Reading offline' : 'Reading online',
                    child: Icon(
                      offline ? Icons.offline_pin_outlined : Icons.public,
                      size: 20,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Bookmark and note',
                  onPressed: loading || error != null ? null : _bookmark,
                  icon: Icon(
                    widget.state.bookmarks.containsKey(chapter.key)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                  ),
                ),
              ],
            ),
      body: SafeArea(
        child: Stack(
          children: [
            AnimatedOpacity(
              opacity: loading || error != null ? 0 : 1,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              child: WebViewWidget(controller: controller),
            ),
            if (loading)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/brand/seer.webp',
                          width: 64,
                          height: 64,
                        ),
                        const SizedBox(height: 24),
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Opening chapter ${chapter.slug}',
                          style: const TextStyle(color: muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (widget.habits != null && !loading && error == null)
              Positioned(
                right: 14,
                bottom: 18,
                child: ReaderXpHud(habits: widget.habits!),
              ),
            if (error != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(error!),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () =>
                                  ready ? _open(edition, chapter) : _start(),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
