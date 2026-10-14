import 'dart:async';
import 'dart:math' as math;

import 'package:flexiphones/helpers/assets_helper.dart';
import 'package:flexiphones/helpers/navigation_helper.dart';
import 'package:flexiphones/models/hot_sales.dart';
import 'package:flexiphones/models/product_m.dart';
import 'package:flexiphones/models/top_deals_m.dart';
import 'package:flexiphones/provider/provider_class.dart';
import 'package:flexiphones/screens/browse/sub_pages.dart/product_details.dart';
import 'package:flexiphones/screens/home/components/top_deals.dart';
import 'package:flexiphones/shared_widgets/fade_slide_in.dart';
import 'package:flexiphones/shared_widgets/generalwidgets.dart';
import 'package:flexiphones/shared_widgets/neu.dart';
import 'package:flexiphones/shared_widgets/product_tile.dart';
import 'package:flexiphones/shared_widgets/pull_to_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

/// The storefront, in soft UI: everything sits on one soft grey-blue
/// surface and gets its depth from light and shadow. A big title, a
/// pressed-in search well, a glowing featured carousel, three "why
/// FlexiPhones" tiles, app-icon style brand buttons, top deals, recently
/// viewed, then every phone in a grid with a sliding sort switch.
class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = Provider.of<SharedProvider>(context, listen: false);
      if (p.brands.isEmpty) p.getBrands();
      if (p.userData != null && p.favoriteIds.isEmpty) p.getFavorites();
    });
  }

  /// Pull down to reload everything on the home page from the first page.
  Future<void> _refresh() async {
    final p = Provider.of<SharedProvider>(context, listen: false);
    await Future.wait([
      p.getHotDeals(),
      p.getTopDeals(refresh: true, next: false),
      p.getProducts(context, refresh: true, next: false),
      p.getRecentViewed(),
      p.getBrands(),
      if (p.userData != null) p.getFavorites(),
    ]).timeout(const Duration(seconds: 15), onTimeout: () => []);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final p = Provider.of<SharedProvider>(context, listen: false);
    if (n.metrics.extentAfter < 600 &&
        p.pNextPAGE != null &&
        !p.loadingProducts) {
      p.getProducts(context, refresh: false, next: true);
    }
    return false;
  }

  void _open(SharedProvider p, int id) {
    p.getProductDetails(id, context);
    NavigationHelper.push(context, ProductDetailsPage(productId: id));
  }

  @override
  Widget build(BuildContext context) {
    final p = Provider.of<SharedProvider>(context);
    final ch = Theme.of(context).colorScheme;
    final signedIn = p.userData != null;

    return ColoredBox(
      color: Neu.bg(context),
      child: FlexiPullToRefresh(
        onRefresh: _refresh,
        builder:
            (physics) => NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: CustomScrollView(
                physics: physics,
                slivers: [
                  SliverToBoxAdapter(
                    child: FadeSlideIn(child: _Header(signedIn: signedIn)),
                  ),
                  if (signedIn)
                    SliverToBoxAdapter(
                      child: FadeSlideIn(
                        delay: const Duration(milliseconds: 60),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 2, 20, 22),
                          child: _SearchWell(
                            onTap: () {
                              p.getFilteredProducts();
                              p.enableSearching();
                            },
                          ),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: FadeSlideIn(
                      delay: const Duration(milliseconds: 120),
                      offset: 30,
                      child: _FeaturedCarousel(
                        deals: p.hotDeals,
                        onOpen: (id) => _open(p, id),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: FadeSlideIn(
                      delay: Duration(milliseconds: 200),
                      child: _Perks(),
                    ),
                  ),
                  if (p.brands.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: _SectionTitle(title: "Shop by brand"),
                    ),
                    SliverToBoxAdapter(child: _BrandRow(p: p)),
                  ],
                  if (p.topDeals.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _SectionTitle(
                        title: "Top deals",
                        action: "See all",
                        onAction:
                            () =>
                                NavigationHelper.push(context, TopDealsPage()),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 236,
                        child: ListView.separated(
                          clipBehavior: Clip.none,
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                          scrollDirection: Axis.horizontal,
                          itemCount: math.min(p.topDeals.length, 10),
                          separatorBuilder: (_, _) => const SizedBox(width: 16),
                          itemBuilder:
                              (_, i) => _DealCard(
                                deal: p.topDeals[i],
                                onTap: () => _open(p, p.topDeals[i].id),
                              ),
                        ),
                      ),
                    ),
                  ],
                  if (p.recentlyViewedProducts.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: _SectionTitle(title: "Pick up where you left off"),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 124,
                        child: ListView.separated(
                          clipBehavior: Clip.none,
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                          scrollDirection: Axis.horizontal,
                          itemCount: p.recentlyViewedProducts.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 18),
                          itemBuilder: (_, i) {
                            final x = p.recentlyViewedProducts[i];
                            return _RecentBubble(
                              product: x,
                              onTap: () => _open(p, x.id),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(
                    child: _SectionTitle(title: "All phones", big: true),
                  ),
                  SliverToBoxAdapter(child: _SortSwitch(p: p)),
                  _ProductGrid(p: p, onOpen: (id) => _open(p, id)),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 100,
                      child: Center(
                        child:
                            p.pNextPAGE != null && p.products.isNotEmpty
                                ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: ch.onSurfaceVariant,
                                  ),
                                )
                                : Text(
                                  p.products.isEmpty
                                      ? ""
                                      : "You've seen them all",
                                  style: ptstyle(
                                    size: 12,
                                    weight: 500,
                                    color: ch.onSurfaceVariant.withOpacity(0.6),
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
}

// ---------------------------------------------------------------------------
// Header + search
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.signedIn});
  final bool signedIn;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return "Good morning";
    if (h < 17) return "Good afternoon";
    return "Good evening";
  }

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    final p = Provider.of<SharedProvider>(context, listen: false);
    final first = (p.userData?.data.name ?? "").trim().split(" ").first;
    final big = ptstyle(
      size: 34,
      weight: 800,
      color: ch.onSurface,
      height: 1.05,
    ).copyWith(letterSpacing: -1.4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (signedIn && first.isNotEmpty
                    ? "${_greeting()}, $first"
                    : DateFormat("EEEE d MMMM").format(DateTime.now()))
                .toUpperCase(),
            style: ptstyle(
              size: 11,
              weight: 700,
              color: Neu.blue,
            ).copyWith(letterSpacing: 1.1),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: "Find your\n", style: big),
                TextSpan(
                  text: "next phone.",
                  style: big.copyWith(color: ch.onSurface.withOpacity(0.32)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchWell extends StatelessWidget {
  const _SearchWell({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: NeuInset(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 21, color: ch.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Search phones, brands, shops",
                style: ptstyle(
                  size: 14,
                  weight: 400,
                  color: ch.onSurfaceVariant,
                ),
              ),
            ),
            const Icon(Icons.tune_rounded, size: 19, color: Neu.blue),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    this.action,
    this.onAction,
    this.big = false,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, big ? 34 : 28, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              style: ptstyle(
                size: big ? 24 : 19,
                weight: 800,
                color: ch.onSurface,
              ).copyWith(letterSpacing: -0.6),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: Neu.blue,
              ),
              child: Text(action!, style: ptstyle(size: 13, weight: 600)),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Featured carousel (hot deals)
// ---------------------------------------------------------------------------

class _FeaturedCarousel extends StatefulWidget {
  const _FeaturedCarousel({required this.deals, required this.onOpen});
  final List<HotDeal> deals;
  final ValueChanged<int> onOpen;

  @override
  State<_FeaturedCarousel> createState() => _FeaturedCarouselState();
}

class _FeaturedCarouselState extends State<_FeaturedCarousel> {
  final _page = PageController(viewportFraction: 0.88);
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _auto = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_page.hasClients || widget.deals.length < 2) return;
      final next = ((_page.page ?? 0).round() + 1) % widget.deals.length;
      _page.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    final deals = widget.deals.take(6).toList();
    if (deals.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: SizedBox(height: 220, child: _FeaturedCard(pageOffset: 0)),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 236,
          child: PageView.builder(
            controller: _page,
            padEnds: false,
            clipBehavior: Clip.none,
            itemCount: deals.length,
            itemBuilder:
                (_, i) => AnimatedBuilder(
                  animation: _page,
                  builder: (_, _) {
                    final page =
                        _page.hasClients && _page.position.haveDimensions
                            ? (_page.page ?? 0)
                            : 0.0;
                    final d = (page - i).clamp(-1.0, 1.0).toDouble();
                    return Transform.scale(
                      scale: 1 - d.abs() * 0.07,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: i == 0 ? 20 : 8,
                          right: 8,
                          bottom: 16,
                        ),
                        child: PressScale(
                          onTap: () => widget.onOpen(deals[i].id),
                          child: _FeaturedCard(
                            deal: deals[i],
                            index: i,
                            pageOffset: d,
                          ),
                        ),
                      ),
                    );
                  },
                ),
          ),
        ),
        if (deals.length > 1) ...[
          const SizedBox(height: 4),
          SmoothPageIndicator(
            controller: _page,
            count: deals.length,
            effect: ExpandingDotsEffect(
              dotHeight: 6,
              dotWidth: 6,
              expansionFactor: 4,
              spacing: 5,
              activeDotColor: Neu.blue,
              dotColor: ch.onSurface.withOpacity(0.15),
            ),
          ),
        ],
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({this.deal, this.index = 0, required this.pageOffset});
  final HotDeal? deal;
  final int index;

  /// -1..1 distance from the centre; drives the parallax on the phone.
  final double pageOffset;

  static const _backdrops = [
    [Color(0xFF0A1A33), Color(0xFF1B4E9B), Color(0xFF3A8DFF)],
    [Color(0xFF1C0F2E), Color(0xFF5B2A9E), Color(0xFFBF5AF2)],
    [Color(0xFF07211C), Color(0xFF16705C), Color(0xFF30D1A0)],
    [Color(0xFF2A0F0F), Color(0xFF9E2A3F), Color(0xFFFF6B6B)],
  ];

  @override
  Widget build(BuildContext context) {
    final d = deal;
    final colors = _backdrops[index % _backdrops.length];
    final storage = d == null || d.storages.isEmpty ? null : d.storages.first;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [colors[0], colors[1]],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors[1].withOpacity(0.45),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: -6,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Glow orb behind the phone
          Positioned(
            right: -40,
            top: -30,
            width: 240,
            height: 240,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [colors[2].withOpacity(0.75), Colors.transparent],
                ),
              ),
            ),
          ),
          // Phone with parallax and a slight tilt
          Positioned(
            right: -6 + pageOffset * 40,
            top: 12,
            bottom: 12,
            width: 165,
            child: Transform.rotate(
              angle: -0.1 + pageOffset * 0.1,
              child:
                  d == null || d.image.isEmpty
                      ? Image.asset(AssetsHelper.iphoneIMG, fit: BoxFit.contain)
                      : Image.network(
                        d.image,
                        fit: BoxFit.contain,
                        errorBuilder:
                            (_, _, _) => Image.asset(
                              AssetsHelper.iphoneIMG,
                              fit: BoxFit.contain,
                            ),
                      ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 150, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        size: 12,
                        color: Color(0xFFFFB340),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        d == null ? "FLEXIPHONES" : "HOT DEAL",
                        style: ptstyle(
                          size: 9.5,
                          weight: 700,
                          color: Colors.white,
                        ).copyWith(letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  d == null ? "Your next phone." : titleCase(d.fullName),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ptstyle(
                    size: 23,
                    weight: 800,
                    color: Colors.white,
                  ).copyWith(letterSpacing: -0.7, height: 1.08),
                ),
                const SizedBox(height: 5),
                Text(
                  storage == null
                      ? "Pay small small, every day."
                      : "$storage · Pay daily",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ptstyle(size: 12, weight: 400, color: Colors.white70),
                ),
                const Spacer(),
                if (d != null)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Shop now",
                          style: ptstyle(
                            size: 12,
                            weight: 700,
                            color: colors[0],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 15,
                          color: colors[0],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Why FlexiPhones
// ---------------------------------------------------------------------------

class _Perks extends StatelessWidget {
  const _Perks();

  @override
  Widget build(BuildContext context) {
    const perks = [
      (Icons.calendar_month_rounded, "Pay daily", Color(0xFF0071E3)),
      (Icons.verified_rounded, "Yours for good", Color(0xFF30A14E)),
      (Icons.storefront_rounded, "Trusted shops", Color(0xFFFF9F0A)),
    ];
    final ch = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Row(
        children: [
          for (var i = 0; i < perks.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Expanded(
              child: NeuBox(
                radius: 20,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 8,
                ),
                child: Column(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: perks[i].$3.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(perks[i].$1, color: perks[i].$3, size: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      perks[i].$2,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ptstyle(
                        size: 11.5,
                        weight: 600,
                        color: ch.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Brands, deals, recently viewed
// ---------------------------------------------------------------------------

class _BrandRow extends StatelessWidget {
  const _BrandRow({required this.p});
  final SharedProvider p;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView(
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        scrollDirection: Axis.horizontal,
        children: [
          _BrandBubble(
            label: "All",
            icon: Icons.apps_rounded,
            selected: p.brandFilter.isEmpty,
            onTap: () => p.setBrandFilter(context, null),
          ),
          for (final b in p.brands)
            _BrandBubble(
              label: b.displayName,
              logoUrl: b.logoUrl,
              selected: p.brandFilter.contains(b.name.toLowerCase()),
              onTap:
                  () => p.setBrandFilter(
                    context,
                    p.brandFilter.contains(b.name.toLowerCase())
                        ? null
                        : b.name,
                  ),
            ),
        ],
      ),
    );
  }
}

class _BrandBubble extends StatelessWidget {
  const _BrandBubble({
    required this.label,
    required this.selected,
    required this.onTap,
    this.logoUrl,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? logoUrl;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    final fg = selected ? Neu.blue : ch.onSurface;
    final initial = Text(
      label.isEmpty ? "?" : label[0],
      style: ptstyle(size: 22, weight: 800, color: fg),
    );
    final inner = SizedBox(
      width: 60,
      height: 60,
      child: Center(
        child:
            icon != null
                ? Icon(icon, color: fg, size: 26)
                : logoUrl == null
                ? initial
                : Padding(
                  padding: const EdgeInsets.all(14),
                  child: Image.network(
                    logoUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => initial,
                  ),
                ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child:
                  selected
                      ? NeuInset(
                        key: const ValueKey(true),
                        radius: 20,
                        child: inner,
                      )
                      : NeuBox(
                        key: const ValueKey(false),
                        radius: 20,
                        distance: 5,
                        blur: 12,
                        child: inner,
                      ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: ptstyle(
                size: 11.5,
                weight: selected ? 700 : 500,
                color: selected ? Neu.blue : ch.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DealCard extends StatelessWidget {
  const _DealCard({required this.deal, required this.onTap});
  final Deal deal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    final rating = double.tryParse(deal.rating) ?? 0;
    return NeuBox(
      radius: 24,
      padding: const EdgeInsets.all(8),
      onTap: onTap,
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NeuInset(
              radius: 18,
              child: SizedBox(
                height: 128,
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Image.network(
                    deal.image,
                    fit: BoxFit.contain,
                    errorBuilder:
                        (_, _, _) => Opacity(
                          opacity: 0.4,
                          child: Image.asset(AssetsHelper.dummyImage),
                        ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleCase("${deal.brand} ${deal.model}"),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ptstyle(size: 13, weight: 700, color: ch.onSurface),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Color(0xFFFF9F0A),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        rating > 0 ? rating.toStringAsFixed(1) : "New",
                        style: ptstyle(
                          size: 11,
                          weight: 600,
                          color: ch.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentBubble extends StatelessWidget {
  const _RecentBubble({required this.product, required this.onTap});
  final ProductModel product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    return SizedBox(
      width: 76,
      child: Column(
        children: [
          NeuBox(
            shape: BoxShape.circle,
            distance: 5,
            blur: 12,
            onTap: onTap,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Image.network(
                  product.image,
                  fit: BoxFit.contain,
                  errorBuilder:
                      (_, _, _) => Opacity(
                        opacity: 0.4,
                        child: Image.asset(AssetsHelper.dummyImage),
                      ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            titleCase(product.model.isEmpty ? product.fullName : product.model),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: ptstyle(size: 11, weight: 600, color: ch.onSurface),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// All phones: sort switch + grid
// ---------------------------------------------------------------------------

/// A pressed-in track with a raised thumb on the chosen sort.
class _SortSwitch extends StatelessWidget {
  const _SortSwitch({required this.p});
  final SharedProvider p;

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: NeuInset(
        radius: 18,
        padding: const EdgeInsets.all(5),
        child: Row(
          children: [
            for (final s in ProductSort.values)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  p.setProductSort(context, s);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color:
                        p.productSort == s
                            ? Neu.bg(context)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow:
                        p.productSort == s
                            ? Neu.raised(context, distance: 3, blur: 7)
                            : const [],
                  ),
                  child: Text(
                    s.label,
                    style: ptstyle(
                      size: 12.5,
                      weight: p.productSort == s ? 700 : 500,
                      color:
                          p.productSort == s ? Neu.blue : ch.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.p, required this.onOpen});
  final SharedProvider p;
  final ValueChanged<int> onOpen;

  static const _delegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    mainAxisSpacing: 18,
    crossAxisSpacing: 16,
    childAspectRatio: 0.56,
  );

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    if (p.products.isEmpty && p.loadingProducts) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        sliver: SliverGrid(
          gridDelegate: _delegate,
          delegate: SliverChildBuilderDelegate(
            (_, _) => Shimmer.fromColors(
              baseColor: ch.onSurface.withOpacity(0.04),
              highlightColor: ch.onSurface.withOpacity(0.09),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
            childCount: 4,
          ),
        ),
      );
    }
    if (p.products.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
          child: NeuBox(
            padding: const EdgeInsets.all(26),
            child: Column(
              children: [
                Icon(
                  Icons.phone_iphone_rounded,
                  size: 40,
                  color: ch.onSurfaceVariant.withOpacity(0.5),
                ),
                const SizedBox(height: 10),
                Text(
                  "No phones match this filter yet.",
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
      );
    }
    final signedIn = p.userData != null;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      sliver: SliverGrid(
        gridDelegate: _delegate,
        delegate: SliverChildBuilderDelegate((_, i) {
          final x = p.products[i];
          return FadeSlideIn(
            key: ValueKey("tile-${x.id}"),
            delay: Duration(milliseconds: 50 * (i % 6)),
            offset: 26,
            child: ProductTile(
              product: x,
              isFavorite: p.isFavorite(x.id),
              onFavorite: signedIn ? () => p.toggleFavorite(context, x) : null,
              onTap: () => onOpen(x.id),
            ),
          );
        }, childCount: p.products.length),
      ),
    );
  }
}
