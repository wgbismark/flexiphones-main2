/// GET /v1/orders/{id}/repayment-info — everything the "Pay now" screen needs.
class RepaymentInfo {
  final int orderId;
  final bool repaymentAllowed;
  final String? reason;
  final num totalPayment;
  final num totalPaid;
  final num balance;
  final num dailyPayment;
  final String? nextDue;
  final int daysOverdue;
  final bool isOverdue;
  final num catchUpAmount;
  final num minimumAmount;
  final num maximumAmount;
  final List<SuggestedAmount> suggestedAmounts;
  final String? defaultPhone;
  final bool inProgress;
  final String? displayStatus;

  RepaymentInfo({
    required this.orderId,
    required this.repaymentAllowed,
    this.reason,
    required this.totalPayment,
    required this.totalPaid,
    required this.balance,
    required this.dailyPayment,
    this.nextDue,
    required this.daysOverdue,
    required this.isOverdue,
    required this.catchUpAmount,
    required this.minimumAmount,
    required this.maximumAmount,
    required this.suggestedAmounts,
    this.defaultPhone,
    required this.inProgress,
    this.displayStatus,
  });

  factory RepaymentInfo.fromJson(Map<String, dynamic> json) {
    return RepaymentInfo(
      orderId: _int(json['order_id']),
      repaymentAllowed: json['repayment_allowed'] == true,
      reason: json['reason']?.toString(),
      totalPayment: _num(json['total_payment']),
      totalPaid: _num(json['total_paid']),
      balance: _num(json['balance']),
      dailyPayment: _num(json['daily_payment']),
      nextDue: json['next_due']?.toString(),
      daysOverdue: _int(json['days_overdue']),
      isOverdue: json['is_overdue'] == true,
      catchUpAmount: _num(json['catch_up_amount']),
      minimumAmount: _num(json['minimum_amount'], fallback: 1),
      maximumAmount: _num(json['maximum_amount']),
      suggestedAmounts:
          (json['suggested_amounts'] as List? ?? [])
              .whereType<Map>()
              .map((e) => SuggestedAmount.fromJson(Map<String, dynamic>.from(e)))
              .toList(),
      defaultPhone: json['default_phone']?.toString(),
      inProgress: json['in_progress'] == true,
      displayStatus: json['display_status']?.toString(),
    );
  }
}

class SuggestedAmount {
  final String label;
  final num amount;

  SuggestedAmount({required this.label, required this.amount});

  factory SuggestedAmount.fromJson(Map<String, dynamic> json) =>
      SuggestedAmount(
        label: json['label']?.toString() ?? "",
        amount: _num(json['amount']),
      );
}

/// GET /v1/orders/{id}/repayment-status?since=... — one poll result.
class RepaymentStatus {
  /// queued | awaiting_approval | processing | paid | failed | none
  final String state;
  final String message;
  final bool done;
  final String? reference;
  final num? totalPaid;
  final num? balance;
  final String? nextDue;

  RepaymentStatus({
    required this.state,
    required this.message,
    required this.done,
    this.reference,
    this.totalPaid,
    this.balance,
    this.nextDue,
  });

  bool get isPaid => state == "paid";
  bool get isFailed => state == "failed";

  factory RepaymentStatus.fromJson(Map<String, dynamic> json) {
    final order = json['order'] is Map ? json['order'] as Map : const {};
    return RepaymentStatus(
      state: json['state']?.toString() ?? "none",
      message: json['message']?.toString() ?? "",
      done: json['done'] == true,
      reference: json['reference']?.toString(),
      totalPaid: order['total_paid'] == null ? null : _num(order['total_paid']),
      balance: order['balance'] == null ? null : _num(order['balance']),
      nextDue: order['next_due']?.toString(),
    );
  }
}

// The API mixes numbers and numeric strings ("400.00"), so parse both.
num _num(dynamic v, {num fallback = 0}) =>
    v is num ? v : num.tryParse("${v ?? ""}") ?? fallback;

int _int(dynamic v) => v is int ? v : int.tryParse("${v ?? ""}") ?? 0;
