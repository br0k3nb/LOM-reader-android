import 'dart:async';
import 'package:flutter/material.dart';
import 'models.dart';
import 'storage_usage.dart';

const ink = Color(0xff0c1319);
const panel = Color(0xff16212a);
const gold = Color(0xffd8bd82);
const muted = Color(0xff9aabb8);

ThemeData readerTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: gold,
    brightness: Brightness.dark,
    surface: ink,
    primary: gold,
    secondary: const Color(0xffa4bad1),
  );
  return ThemeData(
    fontFamily: 'ReaderRoboto',
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: ink,
    appBarTheme: const AppBarTheme(
      backgroundColor: ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xff26343f)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.all(18),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xff101a22),
      indicatorColor: Color(0xff334037),
      height: 76,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: gold,
      linearTrackColor: Color(0xff2b3842),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: panel,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
  );
}

/// Entries animate once, never restart as download progress updates. Honor the
/// system's reduced-motion setting and cancel delayed starts when disposed.
class MotionEntry extends StatefulWidget {
  const MotionEntry({super.key, required this.child, this.delay = 0});
  final Widget child;
  final int delay;
  @override
  State<MotionEntry> createState() => _MotionEntryState();
}

class _MotionEntryState extends State<MotionEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  Timer? _timer;
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _timer?.cancel();
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _timer = Timer(Duration(milliseconds: widget.delay), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _animation,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, .045),
        end: Offset.zero,
      ).animate(_animation),
      child: widget.child,
    ),
  );
}

class ReaderPanel extends StatelessWidget {
  const ReaderPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.accent = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool accent;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280),
    margin: const EdgeInsets.only(bottom: 16),
    padding: padding,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: accent
            ? [const Color(0xff26352f), const Color(0xff16212a)]
            : [panel, const Color(0xff131d25)],
      ),
      border: Border.all(
        color: accent ? gold.withValues(alpha: .26) : const Color(0xff26343f),
      ),
    ),
    child: child,
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(
    this.label, {
    super.key,
    this.icon = Icons.public,
    this.ready = false,
  });
  final String label;
  final IconData icon;
  final bool ready;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: (ready ? const Color(0xff80bea4) : gold).withValues(alpha: .10),
      borderRadius: BorderRadius.circular(50),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: ready ? const Color(0xff80bea4) : gold),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ready ? const Color(0xff80bea4) : gold,
            ),
          ),
        ),
      ],
    ),
  );
}

class StorageCard extends StatelessWidget {
  const StorageCard(this.usage, {super.key, this.onRefresh});
  final StorageUsage usage;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) => ReaderPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.storage_rounded, size: 20, color: gold),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'On your phone',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (onRefresh != null)
              IconButton(
                tooltip: 'Refresh storage usage',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 20),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          formatBytes(usage.total, gb: true),
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w300,
            letterSpacing: -1,
          ),
        ),
        const Text(
          'App files and saved data',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: usage.total > 0
                ? (usage.downloads / usage.total).clamp(0, 1)
                : 0,
            minHeight: 5,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 24,
          runSpacing: 10,
          children: [
            Metric('Downloads', formatBytes(usage.downloads)),
            Metric(
              'App + other data',
              formatBytes(
                (usage.total - usage.downloads).clamp(0, usage.total),
              ),
            ),
            if (usage.free > 0)
              Metric('Device space free', formatBytes(usage.free, gb: true)),
          ],
        ),
      ],
    ),
  );
}

class Metric extends StatelessWidget {
  const Metric(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 11)),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class DownloadCard extends StatelessWidget {
  const DownloadCard({
    super.key,
    required this.edition,
    required this.status,
    required this.queued,
    required this.busy,
    required this.onDownload,
    required this.onRemove,
    required this.onVerify,
    required this.onRead,
  });
  final Edition edition;
  final DownloadStatus status;
  final bool queued, busy;
  final VoidCallback onDownload, onRemove, onVerify, onRead;
  @override
  Widget build(BuildContext context) {
    final s = status;
    final illustrations = s.phase == 'Downloading illustrations';
    final progress = illustrations
        ? (s.imagesTotal == 0 ? 1.0 : s.imagesDone / s.imagesTotal)
        : (s.total == 0 ? 0.0 : s.done / s.total);
    return ReaderPanel(
      accent: s.active,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  edition.book == 'lotm'
                      ? Icons.menu_book_rounded
                      : Icons.hourglass_bottom_rounded,
                  color: gold,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      edition.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      edition.language,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (s.complete)
                const Icon(
                  Icons.check_circle,
                  color: Color(0xff80bea4),
                  size: 22,
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  s.active
                      ? s.phase
                      : s.complete
                      ? 'Ready for offline reading'
                      : queued && busy
                      ? 'Queued'
                      : s.phase,
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
              ),
              Text(
                '${s.done}/${s.total}',
                style: const TextStyle(
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(end: progress.clamp(0, 1)),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 650),
            builder: (_, value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: value, minHeight: 5),
            ),
          ),
          if (illustrations)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${s.imagesDone}/${s.imagesTotal} illustrations',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              Metric('Saved', formatBytes(s.bytes)),
              if (s.active)
                Metric(
                  illustrations ? 'Estimated total' : 'Est. chapters only',
                  s.estimatedBytes > 0
                      ? '~${formatBytes(s.estimatedBytes)}'
                      : 'Calculating…',
                ),
              if (s.active)
                Metric(
                  illustrations ? 'Time remaining' : 'Chapters remaining',
                  formatEta(s.etaSeconds),
                ),
              if (s.active && s.bytesPerSecond > 0)
                Metric('Transfer rate', '${formatBytes(s.bytesPerSecond)}/s'),
            ],
          ),
          if (s.active && !illustrations)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Illustrations follow the chapters. Estimates adjust as files arrive.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
          if (s.missingImages > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${s.missingImages} illustration(s) are unavailable on the website.',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                s.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!s.complete && !s.active)
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onDownload,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(s.done > 0 ? 'Resume' : 'Download'),
                ),
              if (s.complete)
                FilledButton.tonalIcon(
                  onPressed: onRead,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Read'),
                ),
              if (s.complete)
                TextButton(
                  onPressed: busy ? null : onVerify,
                  child: const Text('Verify files'),
                ),
              if (s.done > 0 && !s.active)
                TextButton(
                  onPressed: busy ? null : onRemove,
                  child: const Text('Remove'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
