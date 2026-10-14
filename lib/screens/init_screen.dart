// ignore_for_file: use_build_context_synchronously

import 'dart:math' as math;

import 'package:flexiphones/helpers/assets_helper.dart';
import 'package:flexiphones/helpers/navigation_helper.dart';
import 'package:flexiphones/provider/provider_class.dart';
import 'package:flexiphones/screens/agent_dashboard/agent_home_shell.dart';
import 'package:flexiphones/screens/layout/layout.dart';
import 'package:flexiphones/shared_widgets/generalwidgets.dart';
import 'package:flexiphones/shared_widgets/neu.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class InitScreen extends StatefulWidget {
  /// [openAgent]: after loading, open the agent dashboard (an agent-only
  /// account just signed in).
  const InitScreen({super.key, this.openAgent = false});

  final bool openAgent;

  @override
  State<InitScreen> createState() => _InitScreenState();
}

class _InitScreenState extends State<InitScreen>
    with TickerProviderStateMixin {
  bool _navigated = false;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  // The loading ring keeps circling until home opens.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  // Slow clock for the background particles.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _spin.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((x) async {
      await checkUser();
    });

    super.initState();
  }

  /// Sends the user to Home no matter what happened above — offline,
  /// a slow/erroring endpoint, or a genuinely successful load all end
  /// the same way: the splash never gets left stuck.
  void _goHome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    final nav = Navigator.of(context);
    final isAgent =
        Provider.of<SharedProvider>(context, listen: false).isAgentAccount;
    final p = Provider.of<SharedProvider>(context, listen: false);
    p.sessionStartup = false;
    NavigationHelper.pushAndRemoveUntil(context, HomePage());
    if (widget.openAgent && isAgent) {
      nav.push(MaterialPageRoute(builder: (_) => const AgentHomeShell()));
    }
    // A session that ended while loading (24h token expired): sign in again.
    p.showPendingSignIn();
  }

  Future<void> checkUser() async {
    final sharedProvider = Provider.of<SharedProvider>(context, listen: false);
    sharedProvider.sessionStartup = true;

    try {
      final hasConnection = await sharedProvider
          .hasInternetConnection(true, context)
          .timeout(const Duration(seconds: 12), onTimeout: () => false);

      // No internet: NoInternetPage is already showing (pushed inside
      // hasInternetConnection). Stop here — don't fire off a chain of
      // network calls that have nothing to talk to.
      if (!hasConnection) return;

      if (!mounted) return;

      await sharedProvider.getUserDetails();
      // Restores the separate partner (agent) session from secure storage,
      // or clears it if it's missing/expired (partner tokens last 24h).
      await sharedProvider.loadPartnerSession();
      // Renew a token with under 2 hours left (or end an expired one)
      // before anything is requested with it.
      await sharedProvider.ensureFreshSessions().timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
      await sharedProvider.hasSeenAdThisWeek();
      await sharedProvider.initTHM(context);

      if (!mounted) return;

      if (sharedProvider.userData == null) {
        await _loadGuestData(sharedProvider);
      } else {
        await _loadUserData(sharedProvider);
      }
    } catch (_) {
      // Whatever failed (timeout, bad response, unfinished endpoint on
      // the backend, etc.) — don't leave the splash frozen. Home still
      // works fine with whatever data did load; individual screens
      // handle their own empty/error states.
    } finally {
      _goHome();
    }
  }

  Future<void> _loadGuestData(SharedProvider sharedProvider) async {
    await Future.wait([
      sharedProvider.getProducts(context, refresh: true, next: false),
      sharedProvider.getHotDeals(),
      sharedProvider.getTopDeals(refresh: true, next: false),
      sharedProvider.getBrands(),
    ]).timeout(const Duration(seconds: 12), onTimeout: () => []);
  }

  Future<void> _loadUserData(SharedProvider sharedProvider) async {
    await Future.wait([
      sharedProvider.getProducts(context, refresh: true, next: false),
      sharedProvider.getHotDeals(),
      sharedProvider.getTopDeals(refresh: true, next: false),
      sharedProvider.getVendors(refresh: true, next: false),
      sharedProvider.getOrders(refresh: true, next: false),
      sharedProvider.getRepaymentCL(refresh: true, next: false),
      sharedProvider.getRecentViewed(),
      sharedProvider.loadCartItems(),
      sharedProvider.getNotifications(),
      sharedProvider.getBrands(),
      sharedProvider.getFavorites(),
    ]).timeout(const Duration(seconds: 12), onTimeout: () => []);
  }

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    final rise = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0, 0.6, curve: Curves.easeOutBack),
    );
    final glow = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
    );
    final text = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.5, 1, curve: Curves.easeOutCubic),
    );
    const disc = 220.0;

    return Scaffold(
      backgroundColor: Neu.bg(context),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Floating particles drifting up behind everything
          AnimatedBuilder(
            animation: Listenable.merge([_drift, glow]),
            builder:
                (_, _) => CustomPaint(
                  painter: _ParticlesPainter(
                    t: _drift.value,
                    opacity: glow.value,
                  ),
                ),
          ),
          // A slow blue glow circling the centre
          AnimatedBuilder(
            animation: Listenable.merge([glow, _spin]),
            builder: (_, _) {
              final t = _spin.value * 2 * math.pi;
              return Center(
                child: Transform.translate(
                  offset: Offset(30 * math.cos(t), 30 * math.sin(t)),
                  child: Opacity(
                    opacity: glow.value,
                    child: Container(
                      width: 380,
                      height: 380,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Neu.blue.withOpacity(0.18),
                            Neu.blue.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // The disc, dead centre of the screen
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([rise, _spin]),
              builder:
                  (_, _) => SizedBox(
                    width: disc,
                    height: disc,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const SizedBox(
                          width: disc - 6,
                          height: disc - 6,
                          child: NeuInset(
                            radius: (disc - 6) / 2,
                            child: SizedBox(),
                          ),
                        ),
                        CustomPaint(
                          size: const Size(disc - 6, disc - 6),
                          painter: _RingPainter(
                            progress: _spin.value,
                            opacity: rise.value.clamp(0.0, 1.0),
                          ),
                        ),
                        Transform.scale(
                          scale: 0.85 + 0.15 * rise.value,
                          child: Container(
                            width: 168,
                            height: 168,
                            decoration: BoxDecoration(
                              color: Neu.bg(context),
                              shape: BoxShape.circle,
                              boxShadow: Neu.raised(
                                context,
                                distance: 10,
                                blur: 24,
                                depth: rise.value.clamp(0.0, 1.0),
                              ),
                            ),
                            padding: const EdgeInsets.all(34),
                            child: Opacity(
                              opacity: rise.value.clamp(0.0, 1.0),
                              child: Image.asset(
                                AssetsHelper.logoImage,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ),
          ),
          // Tagline just under the disc
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: disc + 70),
              child: AnimatedBuilder(
                animation: text,
                builder:
                    (_, child) => Opacity(
                      opacity: text.value,
                      child: Transform.translate(
                        offset: Offset(0, 16 * (1 - text.value)),
                        child: child,
                      ),
                    ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: "Your phone. ",
                            style: ptstyle(
                              size: 24,
                              weight: 800,
                              color: ch.onSurface,
                            ).copyWith(letterSpacing: -0.8),
                          ),
                          TextSpan(
                            text: "Paid daily.",
                            style: ptstyle(
                              size: 24,
                              weight: 800,
                              color: Neu.blue,
                            ).copyWith(letterSpacing: -0.8),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Quality phones on easy daily payments",
                      style: ptstyle(
                        size: 13,
                        weight: 500,
                        color: ch.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Wordmark at the bottom
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: FadeTransition(
                  opacity: text,
                  child: Text(
                    "FLEXIPHONES",
                    style: ptstyle(
                      size: 11,
                      weight: 700,
                      color: ch.onSurfaceVariant.withOpacity(0.5),
                    ).copyWith(letterSpacing: 4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft dots of light rising slowly and twinkling, like dust in a sunbeam.
class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter({required this.t, required this.opacity});
  final double t;
  final double opacity;

  static final _seeds = List.generate(46, (i) {
    final r = math.Random(i * 7919 + 13);
    return (
      x: r.nextDouble(),
      y: r.nextDouble(),
      size: 1.2 + r.nextDouble() * 3.4,
      speed: 0.25 + r.nextDouble() * 0.75,
      phase: r.nextDouble() * math.pi * 2,
      sway: 6 + r.nextDouble() * 18,
      blue: r.nextDouble() < 0.55,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    for (final s in _seeds) {
      final y = ((s.y - t * s.speed) % 1.0 + 1.0) % 1.0;
      final x =
          s.x * size.width + math.sin(t * math.pi * 2 * s.speed + s.phase) * s.sway;
      final twinkle = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(t * 40 * s.speed + s.phase));
      // Fade out near the top and bottom edges.
      final edge = math.min(1.0, math.min(y, 1 - y) * 6);
      final a = (opacity * twinkle * edge).clamp(0.0, 1.0);
      final color = (s.blue ? Neu.blue : Colors.white).withOpacity(
        s.blue ? a * 0.45 : a * 0.95,
      );
      canvas.drawCircle(
        Offset(x, y * size.height),
        s.size,
        Paint()
          ..color = color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.size * 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter old) =>
      old.t != t || old.opacity != opacity;
}

/// A blue comet arc chasing round the disc while the app loads.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.opacity});
  final double progress;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - 8,
    );
    final start = progress * 2 * math.pi - math.pi / 2;
    const sweep = math.pi * 0.9;
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: sweep,
            colors: [
              Neu.blue.withOpacity(0),
              Neu.blue.withOpacity(opacity),
            ],
            transform: GradientRotation(start),
          ).createShader(rect);
    canvas.drawArc(rect, start, sweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.opacity != opacity;
}
