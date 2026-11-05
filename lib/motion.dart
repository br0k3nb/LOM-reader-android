import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Widget tests settle every animation, so looping ambience is off there.
final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

/// Whether looping, decorative motion (flicker, embers, shimmer) may run.
bool ambientMotion(BuildContext context) =>
    !_underTest && !MediaQuery.disableAnimationsOf(context);

bool _reduced(BuildContext context) => MediaQuery.disableAnimationsOf(context);

/// A number that counts up to [value] whenever it changes.
class CountUp extends StatelessWidget {
  const CountUp(
    this.value, {
    super.key,
    this.style,
    this.format,
    this.duration = const Duration(milliseconds: 900),
    this.textAlign,
  });
  final int value;
  final TextStyle? style;
  final String Function(int)? format;
  final Duration duration;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.toDouble()),
    duration: _reduced(context) ? Duration.zero : duration,
    curve: Curves.easeOutCubic,
    builder: (context, v, _) {
      final n = v.round();
      return Text(format?.call(n) ?? '$n', style: style, textAlign: textAlign);
    },
  );
}

/// A rounded progress bar that grows into place, with an optional gradient
/// and a moving sheen while [shimmer] is on.
class GlowBar extends StatefulWidget {
  const GlowBar({
    super.key,
    required this.value,
    this.height = 6,
    this.colors = const [Color(0xffb89a5c), Color(0xffd8bd82)],
    this.track = const Color(0xff2b3842),
    this.shimmer = false,
    this.markers = const [],
  });
  final double value;
  final double height;
  final List<Color> colors;
  final Color track;
  final bool shimmer;

  /// Positions (0–1) drawn as small ticks, e.g. weekly tiers.
  final List<double> markers;
  @override
  State<GlowBar> createState() => _GlowBarState();
}

class _GlowBarState extends State<GlowBar> with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSheen();
  }

  @override
  void didUpdateWidget(GlowBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSheen();
  }

  void _syncSheen() {
    if (widget.shimmer && ambientMotion(context)) {
      if (!_sheen.isAnimating) _sheen.repeat();
    } else {
      _sheen.stop();
    }
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: widget.value.clamp(0, 1).toDouble()),
    duration: _reduced(context)
        ? Duration.zero
        : const Duration(milliseconds: 1000),
    curve: Curves.easeOutQuart,
    builder: (context, v, _) => AnimatedBuilder(
      animation: _sheen,
      builder: (context, _) => CustomPaint(
        size: Size(double.infinity, widget.height),
        painter: _BarPainter(
          v,
          widget.colors,
          widget.track,
          _sheen.isAnimating ? _sheen.value : null,
          widget.markers,
        ),
      ),
    ),
  );
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.value, this.colors, this.track, this.sheen, this.markers);
  final double value;
  final List<Color> colors;
  final Color track;
  final double? sheen;
  final List<double> markers;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final full = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.drawRRect(full, Paint()..color = track);
    if (value > 0) {
      final w = math.max(size.height, size.width * value);
      final rect = Rect.fromLTWH(0, 0, w, size.height);
      final bar = RRect.fromRectAndRadius(rect, r);
      canvas.drawRRect(
        bar.inflate(1.5),
        Paint()
          ..color = colors.last.withValues(alpha: .25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawRRect(
        bar,
        Paint()..shader = LinearGradient(colors: colors).createShader(rect),
      );
      if (sheen != null) {
        canvas.save();
        canvas.clipRRect(bar);
        final x = -60 + (w + 120) * sheen!;
        canvas.drawRect(
          Rect.fromLTWH(x - 30, 0, 60, size.height),
          Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: .45),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromLTWH(x - 30, 0, 60, size.height)),
        );
        canvas.restore();
      }
    }
    for (final m in markers) {
      final x = size.width * m.clamp(0, 1);
      canvas.drawRect(
        Rect.fromLTWH(x - 1, 0, 2, size.height),
        Paint()..color = const Color(0xff0c1319).withValues(alpha: .7),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.value != value || old.sheen != sheen || old.colors != colors;
}

/// A circular progress ring with a gradient sweep and a glowing head.
class GlowRing extends StatelessWidget {
  const GlowRing({
    super.key,
    required this.value,
    required this.size,
    this.stroke = 9,
    this.colors = const [Color(0xffb89a5c), Color(0xffffe2a3)],
    this.track = const Color(0xff2b3842),
    this.child,
  });
  final double value;
  final double size;
  final double stroke;
  final List<Color> colors;
  final Color track;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0, 1).toDouble()),
      duration: _reduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => CustomPaint(
        painter: _RingPainter(v, stroke, colors, track),
        child: Center(child: child),
      ),
      child: child,
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.stroke, this.colors, this.track);
  final double value, stroke;
  final List<Color> colors;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (value <= 0) return;
    final sweep = 2 * math.pi * value;
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: math.max(sweep, .01),
      colors: colors,
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 4
        ..strokeCap = StrokeCap.round
        ..color = colors.last.withValues(alpha: .18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
    final angle = -math.pi / 2 + sweep;
    final head = center + Offset(math.cos(angle), math.sin(angle)) * radius;
    canvas.drawCircle(
      head,
      stroke * .9,
      Paint()
        ..color = colors.last.withValues(alpha: .55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(head, stroke * .28, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}

/// The streak flame: a flickering icon with a breathing halo and embers
/// drifting upward. Static when ambient motion is off.
class LivingFlame extends StatefulWidget {
  const LivingFlame({
    super.key,
    required this.color,
    this.size = 116,
    this.lit = true,
    this.intensity = 1,
    this.icon = Icons.local_fire_department,
  });
  final Color color;
  final double size;
  final bool lit;

  /// 0–1: how many embers and how bright the halo.
  final double intensity;
  final IconData icon;
  @override
  State<LivingFlame> createState() => _LivingFlameState();
}

class _LivingFlameState extends State<LivingFlame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ambientMotion(context) && widget.lit) {
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop.stop();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _loop,
      builder: (context, _) {
        final t = _loop.value * 2 * math.pi;
        final flicker = widget.lit && _loop.isAnimating
            ? 1 + .035 * math.sin(t * 7) + .02 * math.sin(t * 13 + 1)
            : 1.0;
        final breathe = _loop.isAnimating ? .5 + .5 * math.sin(t * 2) : .5;
        final glow = widget.lit
            ? (.22 + .16 * breathe) * (.6 + .4 * widget.intensity)
            : .08;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _EmberPainter(
              _loop.isAnimating ? _loop.value : null,
              widget.color,
              widget.lit ? (4 + 10 * widget.intensity).round() : 0,
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    widget.color.withValues(alpha: glow),
                    widget.color.withValues(alpha: 0),
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: Transform.scale(
                scaleY: flicker,
                scaleX: 2 - flicker,
                alignment: Alignment.bottomCenter,
                child: ShaderMask(
                  shaderCallback: (rect) => LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: widget.lit
                        ? [
                            widget.color,
                            Color.lerp(widget.color, Colors.white, .45)!,
                          ]
                        : [widget.color, widget.color],
                  ).createShader(rect),
                  child: Icon(
                    widget.icon,
                    size: widget.size * .58,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _EmberPainter extends CustomPainter {
  _EmberPainter(this.t, this.color, this.count);
  final double? t;
  final Color color;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    if (t == null || count == 0) return;
    for (var i = 0; i < count; i++) {
      final seed = i * 0.6180339 % 1;
      final phase = (t! * (1.2 + seed) + seed) % 1;
      final x =
          size.width * (.3 + .4 * seed) +
          math.sin((phase * 3 + seed * 9) * math.pi) * size.width * .08;
      final y = size.height * (.78 - .7 * phase);
      final fade = phase < .15 ? phase / .15 : 1 - (phase - .15) / .85;
      canvas.drawCircle(
        Offset(x, y),
        1.2 + 1.6 * (1 - phase),
        Paint()
          ..color = Color.lerp(
            color,
            Colors.white,
            .3,
          )!.withValues(alpha: (fade * .85).clamp(0, 1))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      );
    }
  }

  @override
  bool shouldRepaint(_EmberPainter old) => old.t != t || old.count != count;
}

/// A one-shot burst of confetti from the centre of the box, for big
/// moments. Plays once; reduced motion shows nothing.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    this.colors = const [
      Color(0xffd8bd82),
      Color(0xffffc857),
      Color(0xff80bea4),
      Color(0xff9fc2dd),
      Color(0xffb28dff),
      Color(0xffff6a3d),
    ],
    this.count = 70,
    this.delay = Duration.zero,
  });
  final List<Color> colors;
  final int count;
  final Duration delay;
  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || _reduced(context)) return;
    _started = true;
    if (widget.delay <= Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_c.value, widget.colors, widget.count),
        ),
      ),
    ),
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.colors, this.count);
  final double t;
  final List<Color> colors;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final origin = Offset(size.width / 2, size.height * .38);
    final random = math.Random(42);
    for (var i = 0; i < count; i++) {
      final angle = random.nextDouble() * 2 * math.pi;
      final speed = 180 + random.nextDouble() * 320;
      final spin = (random.nextDouble() - .5) * 18;
      final w = 4 + random.nextDouble() * 5;
      final h = 2 + random.nextDouble() * 4;
      final color = colors[i % colors.length];
      final ease = 1 - math.pow(1 - t, 3).toDouble();
      final dx = math.cos(angle) * speed * ease;
      final dy = math.sin(angle) * speed * ease * .8 + 260 * t * t;
      final opacity = t < .7 ? 1.0 : 1 - (t - .7) / .3;
      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          const Radius.circular(1.5),
        ),
        Paint()..color = color.withValues(alpha: opacity.clamp(0, 1)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// Rotating light rays behind a reward, like a treasure reveal.
class LightRays extends StatefulWidget {
  const LightRays({
    super.key,
    required this.color,
    this.size = 220,
    this.child,
  });
  final Color color;
  final double size;
  final Widget? child;
  @override
  State<LightRays> createState() => _LightRaysState();
}

class _LightRaysState extends State<LightRays>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ambientMotion(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Transform.rotate(
              angle: _c.value * 2 * math.pi,
              child: CustomPaint(
                size: Size.square(widget.size),
                painter: _RayPainter(widget.color),
              ),
            ),
          ),
        ),
        ?widget.child,
      ],
    ),
  );
}

class _RayPainter extends CustomPainter {
  _RayPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: .38), color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    const rays = 12;
    for (var i = 0; i < rays; i++) {
      final a = i * 2 * math.pi / rays;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * math.cos(a - .09), c.dy + r * math.sin(a - .09))
        ..lineTo(c.dx + r * math.cos(a + .09), c.dy + r * math.sin(a + .09))
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.drawCircle(
      c,
      r * .45,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: .35), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r * .45)),
    );
  }

  @override
  bool shouldRepaint(_RayPainter old) => old.color != color;
}

/// A gentle pulse (scale and glow) that invites a tap on something
/// claimable.
class Pulse extends StatefulWidget {
  const Pulse({
    super.key,
    required this.child,
    this.color = const Color(0xffd8bd82),
    this.active = true,
    this.radius = 24,
  });
  final Widget child;
  final Color color;
  final bool active;
  final double radius;
  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  void _sync() {
    if (widget.active && ambientMotion(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Pulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) {
      final v = Curves.easeInOut.transform(_c.value);
      return Transform.scale(
        scale: 1 + .02 * v,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: .10 + .22 * v),
                      blurRadius: 10 + 14 * v,
                      spreadRadius: -2,
                    ),
                  ]
                : const [],
          ),
          child: child,
        ),
      );
    },
    child: widget.child,
  );
}

/// Scales in with a soft overshoot after [delay] ms. Used for grid cells and
/// badges so a screen assembles itself instead of popping in at once.
class PopIn extends StatefulWidget {
  const PopIn({super.key, required this.child, this.delay = 0});
  final Widget child;
  final int delay;
  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final Animation<double> _scale = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutBack,
  );
  bool _started = false;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_reduced(context)) {
      _c.value = 1;
    } else if (widget.delay <= 0) {
      _c.forward();
    } else {
      _timer = Timer(Duration(milliseconds: widget.delay), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: ScaleTransition(scale: _scale, child: widget.child),
  );
}

/// A diagonal sheen that sweeps across [child] every few seconds.
class Shine extends StatefulWidget {
  const Shine({super.key, required this.child, this.active = true});
  final Widget child;
  final bool active;
  @override
  State<Shine> createState() => _ShineState();
}

class _ShineState extends State<Shine> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  void _sync() {
    if (widget.active && ambientMotion(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Shine oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // Sweep during the first 35% of each cycle, rest otherwise.
        final p = (_c.value / .35).clamp(0, 1).toDouble();
        if (!_c.isAnimating || p >= 1) return child!;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(-1 + 3 * p - 1, -1),
            end: Alignment(-1 + 3 * p, 1),
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: .35),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(rect),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
