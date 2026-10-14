import 'dart:convert';

import 'package:flexiphones/extensions/value_formating.dart';
import 'package:flexiphones/helpers/assets_helper.dart';
import 'package:flexiphones/helpers/navigation_helper.dart';
import 'package:flexiphones/models/product_m.dart';
import 'package:flexiphones/provider/provider_class.dart';
import 'package:flexiphones/screens/browse/sub_pages.dart/purchase_sheet.dart';
import 'package:flexiphones/screens/cash/cash_checkout.dart';
import 'package:flexiphones/shared_widgets/missed_payment_guard.dart';
import 'package:flexiphones/screens/onboarding/email_phone/email_signin.dart';
import 'package:flexiphones/screens/order_confirmation/confirm_order.dart';
import 'package:flexiphones/screens/layout/layout.dart';
import 'package:flexiphones/screens/store/store.dart';
import 'package:flexiphones/models/review_m.dart';
import 'package:flexiphones/screens/reviews/reviews.dart';
import 'package:flexiphones/shared_widgets/fade_slide_in.dart';
import 'package:flexiphones/shared_widgets/generalwidgets.dart';
import 'package:flexiphones/shared_widgets/image_preview.dart';
import 'package:flexiphones/shared_widgets/product_tile.dart';
import 'package:flexiphones/shared_widgets/shop_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

/// Spacing / radius tokens shared by this page.
class _T {
  static const double s4 = 4;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double rCard = 28;
  static const double rTile = 18;
  static const double rPill = 100;
}

const _blue = Color(0xFF0071E3);

/// Splits a product's colours (already normalised from `color_list` by
/// ApiUrls.productColorsText into "{A,B}") into a list. Values keep their
/// exact spelling, because one of them is sent as the order's `color`.
List<String> parseProductColors(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
  } catch (_) {}
  return colorNamesOf(raw);
}

/// Cheapest cash price across a phone's storage options, else the product
/// price; null when neither is known.
double? _lowestPrice(List<ProductStorage> storages, double productPrice) {
  final prices =
      storages
          .map((s) => double.tryParse(s.cashPrice) ?? 0)
          .where((p) => p > 0)
          .toList();
  if (prices.isNotEmpty) return prices.reduce((a, b) => a < b ? a : b);
  return productPrice > 0 ? productPrice : null;
}

/// The product page: a tall photo stage with a thumbnail strip, then a
/// white sheet that slides up over it with the name, price, colours,
/// storage, the seller, reviews and similar phones. Price and the two
/// buttons stay pinned at the bottom; both open the configure sheet.
class ProductDetailsPage extends StatefulWidget {
  ProductDetailsPage({
    super.key,
    required this.productId,
    this.fromStor = false,
  });
  final dynamic productId;
  bool fromStor;

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  int cp = 0;
  final pageController = PageController();
  final _scroll = ScrollController();
  double _offset = 0;
  bool showAll = false;
  SharedProvider? shd;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => setState(() => _offset = _scroll.offset));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = Provider.of<SharedProvider>(context, listen: false);
      p.getProductDetails(widget.productId, context);
      // "You may also like" draws from the product list.
      if (p.products.isEmpty)
        p.getProducts(context, refresh: true, next: false);
    });
  }

  @override
  void dispose() {
    shd?.productsVariations = false;
    _scroll.dispose();
    pageController.dispose();
    super.dispose();
  }

  /// Opens another phone from "You may also like". The shared productData
  /// is replaced by that page, so reload this one when coming back.
  Future<void> _openOtherProduct(int id) async {
    final p = Provider.of<SharedProvider>(context, listen: false);
    p.getProductDetails(id, context);
    await NavigationHelper.push(context, ProductDetailsPage(productId: id));
    if (!mounted) return;
    setState(() {
      cp = 0;
      showAll = false;
    });
    if (pageController.hasClients) pageController.jumpToPage(0);
    p.getProductDetails(widget.productId, context);
  }

  Future<void> _launch(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _goToCheckout(ProductModel product, ProductStorage ps) {
    final p = Provider.of<SharedProvider>(context, listen: false);
    final item = {
      'id': product.id,
      "vendor": product.vendor?.name,
      "productName":
          "${product.brand.toLowerCase()} ${product.model.toLowerCase()}",
      "image": product.image,
      "product_storages": ps.toJson(),
      "quantity": 1,
      "device_type": "smartphone",
      "service_tenure": p.slTenure,
      "color": p.colorSL,
      "isSelected": true,
      "package_id": null,
      "breakdowns": p.breakDownPrice?.breakdowns.toJson(),
    };
    NavigationHelper.push(context, OrderConfirmation(items: [item]));
  }

  void _openSheet({required bool buyNow, ProductStorage? storage}) {
    showPurchaseSheet(
      context,
      buyNow: buyNow,
      initialStorage: storage,
      onBuyNow: _goToCheckout,
    ).then((_) => shd?.togglePV());
  }

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    final p = Provider.of<SharedProvider>(context);
    shd = p;

    final matches =
        p.productData != null &&
        "${p.productData!.id}" == "${widget.productId}";
    if (p.loadingProduct || !matches) {
      if (p.productDetailsError != null && !p.loadingProduct) {
        return _ErrorScreen(
          ch: ch,
          message: p.productDetailsError!,
          onRetry: () => p.getProductDetails(widget.productId, context),
        );
      }
      return PDShimmer(ch: ch);
    }

    final product = p.productData!;
    final images =
        (product.images ?? [])
            .map((e) => e?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
    if (images.isEmpty && product.image.isNotEmpty) images.add(product.image);
    final storages = product.productStorages ?? [];
    final reviews = product.reviews ?? [];
    final avg =
        reviews.isEmpty
            ? 0.0
            : reviews.fold<int>(0, (s, r) => s + r.rating) / reviews.length;
    final colors = parseProductColors(product.colors);
    final fromPrice = _lowestPrice(storages, product.price);
    final spec = (product.deviceSpecification ?? "").trim();
    final inBag = p.cartItems.any((x) => x["id"] == product.id);
    final signedIn = p.userData != null;
    final barSolid = _offset > 300;
    final stageH = MediaQuery.of(context).size.height * 0.48;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      extendBodyBehindAppBar: true,
      // Own top bar (not AppBar actions) so the buttons keep a fixed size
      // and the bag's count badge is never cut off.
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: barSolid ? ch.surface : Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    _RoundIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => NavigationHelper.pop(context),
                    ),
                    Expanded(
                      child: AnimatedOpacity(
                        opacity: barSolid ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          titleCase(
                            product.model.isEmpty
                                ? product.fullName
                                : product.model,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ptstyle(
                            size: 16,
                            weight: 700,
                            color: ch.onSurface,
                          ),
                        ),
                      ),
                    ),
                    if (signedIn) ...[
                      _FavRound(
                        active: p.isFavorite(product.id),
                        onTap: () => p.toggleFavorite(context, product),
                      ),
                      const SizedBox(width: 10),
                    ],
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _RoundIconButton(
                            icon: Icons.shopping_bag_outlined,
                            onTap:
                                () => NavigationHelper.push(
                                  context,
                                  HomePage(initScreen: 2),
                                ),
                          ),
                          if (p.cartItems.isNotEmpty)
                            Positioned(
                              top: -3,
                              right: -3,
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey(p.cartItems.length),
                                tween: Tween(begin: 0.4, end: 1),
                                duration: const Duration(milliseconds: 500),
                                curve: Curves.elasticOut,
                                builder:
                                    (_, s, c) =>
                                        Transform.scale(scale: s, child: c),
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 19,
                                  ),
                                  height: 19,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _blue,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: Text(
                                    "${p.cartItems.length}",
                                    style: ptstyle(
                                      size: 9.5,
                                      weight: 800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      // Sale modes are re-read every time this page loads (never cached).
      bottomNavigationBar: _BuyBar(
        fromPrice: fromPrice,
        inBag: inBag,
        signedIn: signedIn,
        cash: product.supportsCash,
        installment: product.supportsInstallment,
        onBag: () => _openSheet(buyNow: false),
        onBuy:
            signedIn
                ? () async {
                  // Behind on a plan? No new phones until they catch up.
                  if (!await ensureNoMissedPayments(context)) return;
                  if (mounted) _openSheet(buyNow: true);
                }
                : () => NavigationHelper.push(context, EmailSignin()),
        onCash:
            signedIn
                // Cash is never blocked by an overdue plan.
                ? () => showCashCheckout(context, product)
                : () => NavigationHelper.push(context, EmailSignin()),
      ),
      body: ListView(
        controller: _scroll,
        padding: EdgeInsets.zero,
        children: [
          // ---------------- Photo stage ----------------
          SizedBox(
            height: stageH,
            child: Stack(
              children: [
                // Soft spotlight
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -0.1),
                        radius: 0.9,
                        colors: [Colors.white, Color(0xFFF2F4F7)],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  top: MediaQuery.of(context).padding.top + kToolbarHeight,
                  bottom: images.length > 1 ? 76 : 40,
                  child: Transform.translate(
                    // Gentle parallax as the sheet slides over.
                    offset: Offset(0, _offset * 0.35),
                    child:
                        images.isEmpty
                            ? Opacity(
                              opacity: 0.3,
                              child: Image.asset(AssetsHelper.dummyImage),
                            )
                            : PageView.builder(
                              controller: pageController,
                              itemCount: images.length,
                              onPageChanged: (v) => setState(() => cp = v),
                              itemBuilder:
                                  (_, i) => GestureDetector(
                                    onTap:
                                        () => showImagePreview(
                                          context,
                                          images[i],
                                          title: product.fullName,
                                        ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 40,
                                      ),
                                      child: Image.network(
                                        images[i],
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (_, _, _) => Opacity(
                                              opacity: 0.3,
                                              child: Image.asset(
                                                AssetsHelper.dummyImage,
                                              ),
                                            ),
                                      ),
                                    ),
                                  ),
                            ),
                  ),
                ),
                if (images.length > 1)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 40,
                    height: 52,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: images.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder:
                          (_, i) => GestureDetector(
                            onTap:
                                () => pageController.animateToPage(
                                  i,
                                  duration: const Duration(milliseconds: 350),
                                  curve: Curves.easeOutCubic,
                                ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 52,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color:
                                      cp == i
                                          ? _blue
                                          : Colors.black.withOpacity(0.06),
                                  width: cp == i ? 2 : 1,
                                ),
                              ),
                              child: Image.network(
                                images[i],
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const SizedBox(),
                              ),
                            ),
                          ),
                    ),
                  ),
              ],
            ),
          ),

          // ---------------- Content sheet ----------------
          Transform.translate(
            offset: const Offset(0, -24),
            child: Container(
              decoration: BoxDecoration(
                color: ch.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(0, _T.s24, 0, _T.s32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FadeSlideIn(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _T.s20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  product.brand.toUpperCase(),
                                  style: ptstyle(
                                    size: 11,
                                    weight: 800,
                                    color: _blue,
                                  ).copyWith(letterSpacing: 1.4),
                                ),
                              ),
                              if (reviews.isNotEmpty)
                                _Chip(
                                  icon: Icons.star_rounded,
                                  color: const Color(0xFFFF9F0A),
                                  text:
                                      "${avg.toStringAsFixed(1)} · ${reviews.length}",
                                ),
                            ],
                          ),
                          const SizedBox(height: _T.s4),
                          Text(
                            titleCase(
                              product.model.isNotEmpty
                                  ? product.model
                                  : product.fullName,
                            ),
                            style: ptstyle(
                              size: 30,
                              weight: 800,
                              color: ch.onSurface,
                              height: 1.08,
                            ).copyWith(letterSpacing: -1),
                          ),
                          const SizedBox(height: _T.s12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                fromPrice == null
                                    ? "See options"
                                    : "GHS ${fromPrice.toCommaSeparated(0, decimalPlaces: 0)}",
                                style: ptstyle(
                                  size: 24,
                                  weight: 800,
                                  color: ch.onSurface,
                                ).copyWith(letterSpacing: -0.6),
                              ),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  fromPrice == null ? "" : "starting price",
                                  style: ptstyle(
                                    size: 12,
                                    weight: 500,
                                    color: ch.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: _T.s16),
                          // Value props
                          Row(
                            children: [
                              _Perk(
                                icon: Icons.calendar_month_rounded,
                                title: "3–6 months",
                                sub: "to pay",
                              ),
                              const SizedBox(width: 10),
                              _Perk(
                                icon: Icons.sd_storage_rounded,
                                title:
                                    "${storages.length} size${storages.length == 1 ? "" : "s"}",
                                sub: "storage",
                              ),
                              const SizedBox(width: 10),
                              _Perk(
                                icon: Icons.palette_rounded,
                                title:
                                    "${colors.length} colour${colors.length == 1 ? "" : "s"}",
                                sub: "to pick",
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Seller
                  const SizedBox(height: _T.s20),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 80),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _T.s20),
                      child: _SellerCard(
                        product: product,
                        signedIn: signedIn,
                        onStore: () {
                          final id = product.vendor?.id;
                          if (id == null) return;
                          p.getVendorDetails(id);
                          widget.fromStor
                              ? NavigationHelper.pop(context)
                              : NavigationHelper.push(
                                context,
                                StoreInfoPage(store_id: id),
                              );
                        },
                        onCall: () {
                          final tel = product.vendor?.phoneNumber ?? "";
                          if (tel.isNotEmpty)
                            _launch(Uri(scheme: 'tel', path: tel));
                        },
                        onChat: () {
                          final tel = (product.vendor?.phoneNumber ?? "")
                              .replaceAll(RegExp(r'[^0-9]'), '');
                          if (tel.isEmpty) return;
                          final wa =
                              tel.startsWith("233")
                                  ? tel
                                  : "233${tel.startsWith("0") ? tel.substring(1) : tel}";
                          _launch(Uri.parse("https://wa.me/$wa"));
                        },
                      ),
                    ),
                  ),

                  // Colours
                  if (colors.isNotEmpty) ...[
                    const _SectionTitle("Colours"),
                    SizedBox(
                      height: 86,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: _T.s20),
                        itemCount: colors.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (_, i) {
                          final c = colors[i];
                          final sel = p.colorSL == c;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              p.selectColor(c);
                            },
                            child: SizedBox(
                              width: 60,
                              child: Column(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: sel ? _blue : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: swatchFor(c),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: ch.onSurface.withOpacity(0.12),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.1,
                                            ),
                                            blurRadius: 6,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    titleCase(c),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ptstyle(
                                      size: 11,
                                      weight: sel ? 700 : 500,
                                      color:
                                          sel
                                              ? ch.onSurface
                                              : ch.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  // Storage
                  const _SectionTitle(
                    "Storage",
                    sub: "Tap one to see the daily plans",
                  ),
                  if (storages.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _T.s20),
                      child: Text(
                        "No storage or pricing options yet.",
                        style: ptstyle(
                          size: 13,
                          weight: 400,
                          color: ch.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 104,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: _T.s20),
                        itemCount: storages.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (_, i) {
                          final s = storages[i];
                          final cash = double.tryParse(s.cashPrice) ?? 0;
                          return PressScale(
                            onTap: () => _openSheet(buyNow: false, storage: s),
                            child: Container(
                              width: 132,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F4F7),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.sd_card_rounded,
                                    size: 18,
                                    color: _blue,
                                  ),
                                  const Spacer(),
                                  Text(
                                    s.storage,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ptstyle(
                                      size: 16,
                                      weight: 800,
                                      color: ch.onSurface,
                                    ),
                                  ),
                                  Text(
                                    cash > 0
                                        ? "GHS ${cash.toCommaSeparated(0, decimalPlaces: 0)}"
                                        : "See plans",
                                    style: ptstyle(
                                      size: 12,
                                      weight: 500,
                                      color: ch.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  // About
                  if (spec.isNotEmpty) ...[
                    const _SectionTitle("About this phone"),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _T.s20),
                      child: GestureDetector(
                        onTap: () => setState(() => showAll = !showAll),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(_T.s16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F4F7),
                            borderRadius: BorderRadius.circular(_T.rTile),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AnimatedSize(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: Text(
                                  spec,
                                  maxLines: showAll ? null : 4,
                                  overflow:
                                      showAll
                                          ? TextOverflow.visible
                                          : TextOverflow.fade,
                                  style: ptstyle(
                                    size: 13,
                                    weight: 400,
                                    color: ch.onSurfaceVariant,
                                    height: 1.55,
                                  ),
                                ),
                              ),
                              if (spec.length > 160) ...[
                                const SizedBox(height: 6),
                                Text(
                                  showAll ? "Show less" : "Read more",
                                  style: ptstyle(
                                    size: 12,
                                    weight: 700,
                                    color: _blue,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Reviews (paged, with filters, write / edit / delete)
                  const _SectionTitle("Ratings & reviews"),
                  ReviewsSummary(
                    target: ReviewTarget.product,
                    targetId: product.id,
                    targetName: titleCase(product.fullName),
                  ),

                  _MoreProducts(current: product, onOpen: _openOtherProduct),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.sub});
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_T.s20, 28, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ptstyle(
                    size: 19,
                    weight: 800,
                    color: ch.onSurface,
                  ).copyWith(letterSpacing: -0.5),
                ),
                if (sub != null)
                  Text(
                    sub!,
                    style: ptstyle(
                      size: 12,
                      weight: 400,
                      color: ch.onSurfaceVariant,
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

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 3),
          Text(text, style: ptstyle(size: 12, weight: 700, color: color)),
        ],
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.title, required this.sub});
  final IconData icon;
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: _blue),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ptstyle(size: 13, weight: 700, color: ch.onSurface),
            ),
            Text(
              sub,
              style: ptstyle(size: 11, weight: 400, color: ch.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({
    required this.product,
    required this.signedIn,
    required this.onStore,
    required this.onCall,
    required this.onChat,
  });

  final ProductModel product;
  final bool signedIn;
  final VoidCallback onStore;
  final VoidCallback onCall;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final v = product.vendor;
    final name = v?.name ?? "Seller";
    final active = v?.isVerified ?? false;
    final close = v?.closingTime;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D1D1F), Color(0xFF3A3A3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: signedIn ? onStore : null,
            child: Row(
              children: [
                ShopAvatar(name: name, imageUrl: v?.image, size: 46, border: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "SOLD BY",
                        style: ptstyle(
                          size: 9.5,
                          weight: 700,
                          color: Colors.white54,
                        ).copyWith(letterSpacing: 1.2),
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ptstyle(
                                size: 15,
                                weight: 700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (active) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 15,
                              color: Color(0xFF64B5FF),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        [
                          if (signedIn && (v?.location ?? "").isNotEmpty)
                            v!.location,
                          if (close != null && close.isNotEmpty)
                            "Closes ${close.toAmPm()}",
                        ].join(" · "),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ptstyle(
                          size: 11,
                          weight: 400,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
                if (signedIn)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white54,
                  ),
              ],
            ),
          ),
          if (signedIn) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _darkAction(Icons.storefront_rounded, "Store", onStore),
                const SizedBox(width: 8),
                _darkAction(Icons.call_rounded, "Call", onCall),
                const SizedBox(width: 8),
                _darkAction(Icons.chat_bubble_rounded, "Chat", onChat),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              "Sign in to see where the shop is and contact them.",
              style: ptstyle(size: 11, weight: 400, color: Colors.white60),
            ),
          ],
        ],
      ),
    );
  }

  Widget _darkAction(IconData icon, String label, VoidCallback onTap) =>
      Expanded(
        child: PressScale(
          onTap: onTap,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: ptstyle(size: 12, weight: 600, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Pinned at the bottom: the starting price, a bag button and Buy now.
/// Pinned at the bottom. What it offers follows the phone's
/// `available_sale_modes`:
/// - daily payments only: price, bag, Buy now;
/// - cash only: price, Buy with cash (no bag; the bag is for daily plans);
/// - both: the price on top, then bag, Pay cash and Buy now.
class _BuyBar extends StatelessWidget {
  const _BuyBar({
    required this.fromPrice,
    required this.inBag,
    required this.signedIn,
    required this.onBag,
    required this.onBuy,
    required this.onCash,
    required this.cash,
    required this.installment,
  });

  final double? fromPrice;
  final bool inBag;
  final bool signedIn;
  final VoidCallback onBag;
  final VoidCallback onBuy;
  final VoidCallback onCash;
  final bool cash;
  final bool installment;

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    final both = cash && installment;
    final price = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cash && !installment
              ? "Cash price"
              : both
              ? "From · pay cash or daily"
              : "From",
          style: ptstyle(size: 11, weight: 500, color: ch.onSurfaceVariant),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            fromPrice == null
                ? "—"
                : "GHS ${fromPrice!.toCommaSeparated(0, decimalPlaces: 0)}",
            style: ptstyle(
              size: 19,
              weight: 800,
              color: ch.onSurface,
            ).copyWith(letterSpacing: -0.5),
          ),
        ),
      ],
    );
    final bag = SizedBox(
      width: 54,
      height: 54,
      child: Material(
        color:
            inBag
                ? const Color(0xFF30A14E).withOpacity(0.12)
                : const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onBag,
          child: Icon(
            inBag ? Icons.shopping_bag_rounded : Icons.add_shopping_cart_rounded,
            color: inBag ? const Color(0xFF30A14E) : ch.onSurface,
          ),
        ),
      ),
    );
    Widget button({
      required String label,
      required IconData icon,
      required Color color,
      required VoidCallback onTap,
    }) => SizedBox(
      height: 54,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 19),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: ptstyle(size: 15, weight: 700)),
        ),
      ),
    );
    final buyNow = button(
      label: signedIn ? "Buy now" : "Sign in to buy",
      icon: signedIn ? Icons.bolt_rounded : Icons.login_rounded,
      color: _blue,
      onTap: onBuy,
    );
    final payCash = button(
      label: signedIn ? (both ? "Pay cash" : "Buy with cash") : "Sign in to buy",
      icon: signedIn ? Icons.payments_rounded : Icons.login_rounded,
      color: const Color(0xFF1D1D1F),
      onTap: onCash,
    );

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: ch.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child:
          both
              ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  price,
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      bag,
                      const SizedBox(width: 10),
                      Expanded(child: payCash),
                      const SizedBox(width: 10),
                      Expanded(child: buyNow),
                    ],
                  ),
                ],
              )
              : Row(
                children: [
                  Expanded(child: price),
                  if (installment) ...[bag, const SizedBox(width: 10)],
                  installment ? buyNow : payCash,
                ],
              ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    return Center(
      child: Material(
        color: Colors.white.withOpacity(0.9),
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: Colors.black26,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 18, color: ch.onSurface),
          ),
        ),
      ),
    );
  }
}

class _FavRound extends StatelessWidget {
  const _FavRound({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.white.withOpacity(0.9),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: SizedBox(
            width: 40,
            height: 40,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder:
                  (c, a) => ScaleTransition(
                    scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
                    child: c,
                  ),
              child: Icon(
                active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                key: ValueKey(active),
                size: 19,
                color: active ? const Color(0xFFFF375F) : Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "You may also like": same brand first, then the same seller, then the
/// rest — drawn with the shared product card.
class _MoreProducts extends StatelessWidget {
  const _MoreProducts({required this.current, required this.onOpen});

  final ProductModel current;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final p = Provider.of<SharedProvider>(context);
    final others = p.products.where((x) => x.id != current.id).toList();
    if (others.isEmpty) return const SizedBox.shrink();

    int rank(ProductModel x) {
      if (x.brand.toLowerCase() == current.brand.toLowerCase()) return 0;
      if (x.vendorId != null && x.vendorId == current.vendorId) return 1;
      return 2;
    }

    others.sort((a, b) => rank(a).compareTo(rank(b)));
    final picks = others.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle("You may also like"),
        SizedBox(
          height: 322,
          child: ListView.separated(
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(_T.s20, 4, _T.s20, 12),
            scrollDirection: Axis.horizontal,
            itemCount: picks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder:
                (_, i) => SizedBox(
                  width: 172,
                  child: ProductTile(
                    product: picks[i],
                    isFavorite: p.isFavorite(picks[i].id),
                    onFavorite:
                        p.userData == null
                            ? null
                            : () => p.toggleFavorite(context, picks[i]),
                    onTap: () => onOpen(picks[i].id),
                  ),
                ),
          ),
        ),
      ],
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({
    required this.ch,
    required this.message,
    required this.onRetry,
  });
  final ColorScheme ch;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ch.surface,
      appBar: AppBar(
        backgroundColor: ch.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(_T.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: Color(0xFFF2F4F7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_off_rounded,
                  size: 34,
                  color: ch.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: _T.s16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: ptstyle(
                  size: 14,
                  weight: 500,
                  color: ch.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: _T.s24),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _blue),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("Try again"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PDShimmer extends StatelessWidget {
  const PDShimmer({super.key, required this.ch});
  final ColorScheme ch;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ch.surface,
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Product details',
          style: ptstyle(size: 14, weight: 600, color: ch.onSurfaceVariant),
        ),
      ),
      body: Shimmer.fromColors(
        period: const Duration(milliseconds: 900),
        baseColor: ch.surfaceContainerLow,
        highlightColor: ch.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_T.s16, 70, _T.s16, 0),
          child: Column(
            children: [
              // Flexible (not a fixed 320) so the placeholder fits short
              // screens like the M91 instead of overflowing.
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(_T.rCard),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: _T.s24),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(height: 22, width: 220, color: Colors.white),
              ),
              const SizedBox(height: _T.s24),
              Column(
                children: List.generate(
                  6,
                  (index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Container(
                      height: 12,
                      width: double.infinity,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: _T.s24),
              Row(
                children: List.generate(
                  3,
                  (index) => Padding(
                    padding: const EdgeInsets.only(right: _T.s12),
                    child: Container(
                      height: 80,
                      width: 90,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(_T.rTile),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: _T.s24),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(_T.rPill),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 48,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(_T.rPill),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _T.s24),
            ],
          ),
        ),
      ),
    );
  }
}
