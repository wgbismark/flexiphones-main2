import 'dart:math' as math;
import 'dart:ui';

import 'package:flexiphones/shared_widgets/generalwidgets.dart';
import 'package:flutter/material.dart';

class FlexiNavItem {
  const FlexiNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge = 0,
    this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Count shown on the icon (e.g. bag items); 0 hides it.
  final int badge;

  /// When set, tapping runs this instead of selecting the tab (e.g. a tab
  /// that opens another screen).
  final VoidCallback? onTap;
}

/// The app's bottom bar: a floating rounded pill. The highlight behind the
/// chosen tab slides over with a stretch — its leading edge runs ahead and
/// the trailing edge catches up, like a drop of liquid — and the chosen
/// icon fills in and gives a small bounce.
class FlexiNavBar extends StatefulWidget {
  const FlexiNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.floating = true,
    this.accent = const Color(0xFF0071E3),
  });

  final List<FlexiNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// false: flat, edge to edge (used where space is tight).
  final bool floating;
  final Color accent;

  @override
  State<FlexiNavBar> createState() => _FlexiNavBarState();
}

class _FlexiNavBarState extends State<FlexiNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late int _from = widget.currentIndex;
  late int _to = widget.currentIndex;

  @override
  void didUpdateWidget(covariant FlexiNavBar old) {
    super.didUpdateWidget(old);
    final want = widget.currentIndex.clamp(0, widget.items.length - 1);
    if (want != _to) {
      _from = _currentVisual();
      _to = want;
      _c.forward(from: 0);
    }
  }

  /// Where the highlight is right now (mid-animation), rounded to a slot.
  int _currentVisual() => (_c.isAnimating && _c.value < 0.5) ? _from : _to;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    final n = widget.items.length;
    final bar = LayoutBuilder(
      builder: (context, box) {
        final slot = box.maxWidth / n;
        return AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final t = _c.isAnimating || _c.value > 0 ? _c.value : 1.0;
            // Leading edge fast, trailing edge slow: a stretch in between.
            final lead = Curves.easeOutCubic.transform(t);
            final trail = Curves.easeInOutCubic.transform(
              (t * 1.25 - 0.25).clamp(0.0, 1.0),
            );
            final movingRight = _to >= _from;
            final fromL = _from * slot, toL = _to * slot;
            double left, right;
            if (movingRight) {
              right = fromL + slot + (toL - fromL) * lead;
              left = fromL + (toL - fromL) * trail;
            } else {
              left = fromL + (toL - fromL) * lead;
              right = fromL + slot + (toL - fromL) * trail;
            }
            if (_from == _to) {
              left = toL;
              right = toL + slot;
            }
            const inset = 5.0;
            // Lifts a touch while it travels, then settles.
            final lift = math.sin(t * math.pi);
            return Stack(
              children: [
                Positioned(
                  left: left + inset,
                  width: (right - left - inset * 2).clamp(0, box.maxWidth),
                  top: 5 - lift * 2,
                  bottom: 5 + lift * 2,
                  child: _GlassLens(lift: lift),
                ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: _NavButton(
                          item: widget.items[i],
                          selected: i == _to,
                          accent: widget.accent,
                          muted: ch.onSurfaceVariant,
                          onTap: () {
                            final it = widget.items[i];
                            if (it.onTap != null) {
                              it.onTap!();
                            } else {
                              widget.onTap(i);
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );

    if (!widget.floating) {
      return Container(
        height: 62,
        color: ch.surface,
        child: bar,
      );
    }
    // Frosted, see-through bar floating over the page.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 28,
                offset: const Offset(0, 12),
                spreadRadius: -6,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 66,
                decoration: BoxDecoration(
                  color: ch.surface.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.6)),
                ),
                child: bar,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The selected tab's bubble: clear frosted glass with a bright rim on top
/// and a soft shadow underneath, so it reads as a separate layer floating
/// above the bar. No colour of its own.
class _GlassLens extends StatelessWidget {
  const _GlassLens({required this.lift});
  final double lift;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10 + 0.06 * lift),
            blurRadius: 14 + 8 * lift,
            offset: Offset(0, 5 + 3 * lift),
            spreadRadius: -3,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.95),
                  Colors.white.withOpacity(0.70),
                ],
              ),
              border: Border.all(color: Colors.white, width: 1.2),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.accent,
    required this.muted,
    required this.onTap,
  });

  final FlexiNavItem item;
  final bool selected;
  final Color accent;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // No tint: the glass bubble marks the tab; the icon just goes dark.
    final color =
        selected
            ? Theme.of(context).colorScheme.onSurface
            : muted.withOpacity(0.75);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            key: ValueKey(selected),
            tween: Tween(begin: selected ? 0.7 : 1, end: 1),
            duration: Duration(milliseconds: selected ? 600 : 200),
            curve: selected ? Curves.elasticOut : Curves.easeOut,
            builder:
                (_, s, child) => Transform.translate(
                  offset: Offset(0, selected ? -2 * (s.clamp(0, 1)) : 0),
                  child: Transform.scale(scale: s, child: child),
                ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    selected ? item.activeIcon : item.icon,
                    key: ValueKey(selected),
                    size: 24,
                    color: color,
                  ),
                ),
                if (item.badge > 0)
                  Positioned(
                    top: -5,
                    right: -9,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 17),
                      height: 17,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF375F),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        item.badge > 9 ? "9+" : "${item.badge}",
                        style: ptstyle(
                          size: 9,
                          weight: 800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: ptstyle(
              size: selected ? 10.5 : 10,
              weight: selected ? 700 : 500,
              color: color,
            ),
            child: Text(item.label, maxLines: 1, overflow: TextOverflow.clip),
          ),
        ],
      ),
    );
  }
}
