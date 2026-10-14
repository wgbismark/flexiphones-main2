import 'package:flexiphones/helpers/api_helper.dart';

class PromotedProductsResponse {
  final String status;
  final String message;
  final List<HotDeal> hotDeals;

  PromotedProductsResponse({
    required this.status,
    required this.message,
    required this.hotDeals,
  });

  /// `hot_deals` is a plain list without `per_page`/`cursor` (old apps),
  /// and a cursor page object ({data, next_cursor, ...}) when `per_page` is
  /// sent — which this app now does. Both are accepted.
  factory PromotedProductsResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['hot_deals'];
    final items = raw is Map ? (raw['data'] as List? ?? []) : (raw as List? ?? []);
    return PromotedProductsResponse(
      status: json['status']?.toString() ?? "",
      message: json['message']?.toString() ?? "",
      hotDeals: List<HotDeal>.from(items.map((x) => HotDeal.fromJson(x))),
    );
  }
}

class HotDeal {
  final int id;
  final int vendorId;
  final String brand;
  final String model;
  final String fullName;
  final String colors;
  final String deviceSpecification;
  final String deviceType;
  final String image;
  final String status;
  final String rating;
  final String createdAt;
  final String updatedAt;
  final List<String> storages;

  HotDeal({
    required this.id,
    required this.vendorId,
    required this.brand,
    required this.model,
    required this.fullName,
    required this.colors,
    required this.deviceSpecification,
    required this.deviceType,
    required this.image,
    required this.status,
    required this.rating,
    required this.createdAt,
    required this.updatedAt,
    required this.storages,
  });

  factory HotDeal.fromJson(Map<String, dynamic> json) {
    return HotDeal(
      id: json['id'],
      vendorId: json['vendor_id'],
      brand: json['brand'],
      model: json['model'],
      colors: ApiUrls.productColorsText(json),
      fullName: "${ json['brand']} ${json['model']}",
      deviceSpecification: json['device_specification'],
      deviceType: json['device_type'],
      image: ApiUrls.productMainImage(json),
      status: json['status'],
      rating: json['rating'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      storages: List<String>.from(
        json['product_storages'].map((s) => s['storage']),
      ),
    );
  }
}
