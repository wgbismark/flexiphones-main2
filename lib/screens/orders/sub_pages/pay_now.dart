import 'dart:async';

import 'package:flexiphones/helpers/snackbar_helper.dart';
import 'package:flexiphones/models/repayment_info_m.dart';
import 'package:flexiphones/provider/provider_class.dart';
import 'package:flexiphones/shared_widgets/generalwidgets.dart';
import 'package:flexiphones/shared_widgets/input_field.dart';
import 'package:flexiphones/shared_widgets/fade_slide_in.dart';
import 'package:flexiphones/shared_widgets/slide_to_confirm.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _PayStage { loading, loadError, form, waiting, paid, failed, timedOut }

/// "Pay now" for an order's instalments:
/// 1. GET repayment-info, 2. POST repay, 3. poll repayment-status?since=…
/// every 5s for up to 4 minutes until it is done.
class PayNowScreen extends StatefulWidget {
  const PayNowScreen({
    super.key,
    required this.orderId,
    this.initialAmount,
    this.selectedDays = const [],
  });

  final int orderId;

  /// Pre-filled amount, e.g. the days picked on the payment squares.
  final num? initialAmount;

  /// The days the customer picked to pay for (shown as a reminder).
  final List<DateTime> selectedDays;

  @override
  State<PayNowScreen> createState() => _PayNowScreenState();
}

class _PayNowScreenState extends State<PayNowScreen> {
  static const _pollEvery = Duration(seconds: 5);
  static const _pollFor = Duration(minutes: 4);

  late final SharedProvider _provider;
  final _amountController = TextEditingController();
  final _phoneController = TextEditingController();

  _PayStage _stage = _PayStage.loading;
  RepaymentInfo? _info;
  String _message = "";
  bool _starting = false;
  num? _newBalance;

  Timer? _pollTimer;
  DateTime? _pollStartedAt;
  int? _since;
  bool _polling = false;

  String get _sinceKey => "repay_started_${widget.orderId}";

  @override
  void initState() {
    super.initState();
    _provider = Provider.of<SharedProvider>(context, listen: false);
    _loadInfo();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _amountController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    setState(() => _stage = _PayStage.loading);
    final result = await _provider.getRepaymentInfo(widget.orderId);
    if (!mounted) return;

    final info = result.info;
    if (info == null) {
      setState(() {
        _stage = _PayStage.loadError;
        _message = result.error ?? "Could not load payment details";
      });
      return;
    }

    _info = info;
    if (_phoneController.text.isEmpty) {
      _phoneController.text = info.defaultPhone ?? "";
    }
    if (_amountController.text.isEmpty) {
      final first =
          widget.initialAmount != null && widget.initialAmount! > 0
              ? widget.initialAmount!.clamp(
                info.minimumAmount,
                info.maximumAmount > 0
                    ? info.maximumAmount
                    : widget.initialAmount!,
              )
              : info.isOverdue && info.catchUpAmount > 0
              ? info.catchUpAmount
              : (info.suggestedAmounts.isNotEmpty
                  ? info.suggestedAmounts.first.amount
                  : null);
      if (first != null) _amountController.text = _fmt(first);
    }

    if (info.repaymentAllowed && info.inProgress) {
      // A repayment is already running: go straight to waiting.
      await _startWaiting(await _savedSince(), "Waiting for your payment…");
      return;
    }
    setState(() => _stage = _PayStage.form);
  }

  Future<void> _pay() async {
    final info = _info;
    if (info == null || _starting) return;

    final amount = num.tryParse(_amountController.text.trim());
    if (amount == null ||
        amount < info.minimumAmount ||
        amount > info.maximumAmount) {
      SnackbarHelper.danger(
        context: context,
        title: "Invalid Amount",
        message:
            "Enter an amount between GHS ${_fmt(info.minimumAmount)} and GHS ${_fmt(info.maximumAmount)}",
      );
      return;
    }

    setState(() => _starting = true);
    final r = await _provider.startRepayment(
      widget.orderId,
      amount,
      _phoneController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _starting = false);

    if (r.httpStatus == 202) {
      final since =
          r.startedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _saveSince(since);
      await _startWaiting(since, r.message);
    } else if (r.httpStatus == 409) {
      // One is already in progress for this order — follow it instead.
      await _startWaiting(await _savedSince(), r.message);
    } else {
      SnackbarHelper.danger(
        context: context,
        title: "Payment Not Started",
        message: r.httpStatus == 404 ? "Order not found" : r.message,
      );
    }
  }

  Future<void> _startWaiting(int since, String message) async {
    _since = since;
    _pollStartedAt = DateTime.now();
    _pollTimer?.cancel();
    setState(() {
      _stage = _PayStage.waiting;
      _message = message;
    });
    _pollTimer = Timer.periodic(_pollEvery, (_) => _poll());
    _poll();
  }

  Future<void> _poll() async {
    if (_polling || _stage != _PayStage.waiting || _since == null) return;
    if (DateTime.now().difference(_pollStartedAt!) > _pollFor) {
      _pollTimer?.cancel();
      setState(() => _stage = _PayStage.timedOut);
      return;
    }

    _polling = true;
    final status = await _provider.getRepaymentStatus(widget.orderId, _since!);
    _polling = false;
    if (!mounted || status == null || _stage != _PayStage.waiting) return;

    if (status.message.isNotEmpty) _message = status.message;
    if (!status.done) {
      setState(() {});
      return;
    }

    _pollTimer?.cancel();
    if (status.isPaid) {
      _newBalance = status.balance;
      setState(() => _stage = _PayStage.paid);
      _refreshAfterPayment();
    } else if (status.isFailed) {
      setState(() => _stage = _PayStage.failed);
    } else {
      // "none": nothing in progress any more — reload the form.
      await _loadInfo();
    }
  }

  /// Balance, history, the order and notifications all change on success.
  Future<void> _refreshAfterPayment() async {
    try {
      await Future.wait([
        _provider.getOrder(widget.orderId, silent: true),
        _provider.getOrders(refresh: true, next: false),
        _provider.getRepaymentCL(refresh: true, next: false),
        _provider.getNotifications(),
      ]);
    } catch (e) {
      debugPrint("!!! [payNow] refresh after payment failed: $e");
    }
  }

  Future<void> _saveSince(int since) async {
    try {
      (await SharedPreferences.getInstance()).setInt(_sinceKey, since);
    } catch (_) {}
  }

  /// `since` of the repayment we started last; if unknown, the last few
  /// minutes so an older finished repayment isn't mistaken for this one.
  Future<int> _savedSince() async {
    final fallback =
        DateTime.now()
            .subtract(const Duration(minutes: 5))
            .millisecondsSinceEpoch ~/
        1000;
    try {
      return (await SharedPreferences.getInstance()).getInt(_sinceKey) ??
          fallback;
    } catch (_) {
      return fallback;
    }
  }

  String _fmt(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final ch = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: ch.surface,
      appBar: AppBar(
        backgroundColor: ch.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          "Pay Now",
          style: ptstyle(size: 14, weight: 400, color: ch.onSurfaceVariant),
        ),
      ),
      body: SafeArea(child: _body(ch)),
    );
  }

  Widget _body(ColorScheme ch) {
    switch (_stage) {
      case _PayStage.loading:
        return const Center(child: CircularProgressIndicator());
      case _PayStage.loadError:
        return _statusView(
          ch,
          icon: Icons.error_outline,
          color: Colors.red,
          title: "Couldn't load payment details",
          message: _message,
          action: "Try Again",
          onAction: _loadInfo,
        );
      case _PayStage.waiting:
        return _statusView(
          ch,
          icon: Icons.phone_iphone_rounded,
          color: ch.primary,
          title: "Check your phone",
          message: _message,
          busy: true,
        );
      case _PayStage.paid:
        return _statusView(
          ch,
          icon: Icons.check_circle,
          color: Colors.green,
          title: "Payment Successful",
          message:
              _newBalance == null
                  ? _message
                  : "$_message\n\nBalance left: GHS ${_fmt(_newBalance!)}",
          action: "Done",
          onAction: () => Navigator.of(context).pop(),
        );
      case _PayStage.failed:
        return _statusView(
          ch,
          icon: Icons.cancel_outlined,
          color: Colors.red,
          title: "Payment Failed",
          message: _message,
          action: "Try Again",
          onAction: _loadInfo,
        );
      case _PayStage.timedOut:
        return _statusView(
          ch,
          icon: Icons.hourglass_bottom_rounded,
          color: Colors.orange.shade800,
          title: "Still waiting",
          message: "We will notify you when it is done.",
          action: "Done",
          onAction: () => Navigator.of(context).pop(),
        );
      case _PayStage.form:
        return _form(ch);
    }
  }

  Widget _form(ColorScheme ch) {
    final info = _info!;
    final amounts = <SuggestedAmount>[
      if (info.isOverdue && info.catchUpAmount > 0)
        SuggestedAmount(label: "Catch up", amount: info.catchUpAmount),
      ...info.suggestedAmounts,
    ];
    final progress =
        info.totalPayment > 0
            ? (info.totalPaid / info.totalPayment).clamp(0.0, 1.0).toDouble()
            : 0.0;
    final days = widget.selectedDays;
    final dayFmt = DateFormat("d MMM");

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        // Balance hero
        FadeSlideIn(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1D1D1F), Color(0xFF3A3A3C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "BALANCE",
                  style: ptstyle(
                    size: 10,
                    weight: 600,
                    color: Colors.white60,
                  ).copyWith(letterSpacing: 1.4),
                ),
                const SizedBox(height: 4),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: info.balance.toDouble()),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder:
                      (_, v, _) => Text(
                        "GHS ${_fmt(num.parse(v.toStringAsFixed(2)))}",
                        style: ptstyle(
                          size: 34,
                          weight: 700,
                          color: Colors.white,
                        ).copyWith(letterSpacing: -1),
                      ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeOutCubic,
                    builder:
                        (_, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 6,
                          color: const Color(0xFF30D158),
                          backgroundColor: Colors.white.withOpacity(0.15),
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "GHS ${_fmt(info.totalPaid)} paid of GHS ${_fmt(info.totalPayment)}",
                  style: ptstyle(size: 12, weight: 400, color: Colors.white70),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _heroPill("Daily", "GHS ${_fmt(info.dailyPayment)}"),
                    const SizedBox(width: 8),
                    if (info.nextDue != null)
                      Expanded(
                        child: _heroPill("Next due", _niceDate(info.nextDue!)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        if (days.isNotEmpty) ...[
          FadeSlideIn(
            delay: const Duration(milliseconds: 80),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0071E3).withOpacity(0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.grid_view_rounded,
                    color: Color(0xFF0071E3),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Paying for ${days.length} day${days.length == 1 ? "" : "s"}: "
                      "${days.map(dayFmt.format).join(", ")}",
                      style: ptstyle(
                        size: 12,
                        weight: 500,
                        color: ch.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],

        if (info.isOverdue) ...[
          OverdueBanner(
            daysOverdue: info.daysOverdue,
            catchUpAmount: info.catchUpAmount,
          ),
          const SizedBox(height: 14),
        ],

        if (!info.repaymentAllowed)
          _statusInline(
            ch,
            info.reason ?? "Repayment isn't available for this order yet.",
          )
        else
          FadeSlideIn(
            delay: const Duration(milliseconds: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "How much?",
                  style: ptstyle(size: 18, weight: 700, color: ch.onSurface),
                ),
                const SizedBox(height: 10),
                if (amounts.isNotEmpty)
                  SizedBox(
                    height: 74,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: amounts.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final a = amounts[i];
                        final sel = _amountController.text == _fmt(a.amount);
                        return PressScale(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(
                              () => _amountController.text = _fmt(a.amount),
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 118,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  sel
                                      ? const Color(0xFF0071E3)
                                      : ch.onSurface.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  a.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ptstyle(
                                    size: 11,
                                    weight: 500,
                                    color:
                                        sel
                                            ? Colors.white70
                                            : ch.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  "GHS ${_fmt(a.amount)}",
                                  style: ptstyle(
                                    size: 16,
                                    weight: 700,
                                    color: sel ? Colors.white : ch.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),
                OutlineInput(
                  label: "Amount (GHS)",
                  hintText:
                      "${_fmt(info.minimumAmount)} – ${_fmt(info.maximumAmount)}",
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onchange: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                OutlineInput(
                  label: "Mobile money number",
                  hintText: "eg: 0244000000",
                  controller: _phoneController,
                  maxLength: 10,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 20),
                SlideToConfirm(
                  label:
                      "Slide to pay GHS ${_amountController.text.isEmpty ? "…" : _amountController.text}",
                  enabled: _amountController.text.trim().isNotEmpty,
                  loading: _starting,
                  color:
                      info.isOverdue
                          ? const Color(0xFFE5484D)
                          : const Color(0xFF0071E3),
                  onConfirmed: () async {
                    FocusScope.of(context).unfocus();
                    await _pay();
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 13,
                      color: ch.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        "You'll get a prompt on your phone to approve it.",
                        textAlign: TextAlign.center,
                        style: ptstyle(
                          size: 11,
                          weight: 400,
                          color: ch.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _heroPill(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: ptstyle(size: 10, weight: 400, color: Colors.white60),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ptstyle(size: 13, weight: 600, color: Colors.white),
        ),
      ],
    ),
  );

  /// "2026-10-10" -> "Fri, 10 Oct"; anything else as-is.
  String _niceDate(String raw) {
    final d = DateTime.tryParse(raw);
    return d == null ? raw : DateFormat("EEE, d MMM").format(d);
  }

  Widget _statusInline(ColorScheme ch, String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: ch.onSurface.withOpacity(0.05),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: ptstyle(size: 12, weight: 500, color: ch.onSurfaceVariant),
    ),
  );

  Widget _statusView(
    ColorScheme ch, {
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    String? action,
    VoidCallback? onAction,
    bool busy = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              key: ValueKey(title),
              tween: Tween(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (_, s, child) => Transform.scale(scale: s, child: child),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 48, color: color),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: ptstyle(
                size: 22,
                weight: 700,
                color: ch.onSurface,
              ).copyWith(letterSpacing: -0.5),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: ptstyle(
                size: 13,
                weight: 400,
                color: ch.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 26),
            if (busy)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            if (action != null && onAction != null)
              SizedBox(
                width: 220,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0071E3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: onAction,
                  child: Text(action, style: ptstyle(size: 14, weight: 600)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Red warning shown on the Pay now screen and the order details page when
/// repayment-info reports the order as overdue.
class OverdueBanner extends StatelessWidget {
  const OverdueBanner({
    super.key,
    required this.daysOverdue,
    required this.catchUpAmount,
  });

  final int daysOverdue;
  final num catchUpAmount;

  @override
  Widget build(BuildContext context) {
    final amount =
        catchUpAmount == catchUpAmount.roundToDouble()
            ? catchUpAmount.toInt().toString()
            : catchUpAmount.toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        border: Border.all(color: Colors.red.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Payment overdue by $daysOverdue day${daysOverdue == 1 ? "" : "s"}. "
              "Pay GHS $amount now to avoid your device being locked.",
              style: ptstyle(size: 11, weight: 600, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
